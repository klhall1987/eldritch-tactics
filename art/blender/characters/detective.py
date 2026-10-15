"""The detective: the player character, a realistic, Resident Evil (REmake)-style model about 1.88 m tall.

Built on a committed CC0 human base mesh (art/base/human_male_realistic.blend, from Blender Studio's
Human Base Meshes) and committed CC0 photo textures (art/base/textures, from Poly Haven); see
art/base/README.md. The script re-poses the base body (arms down, feet in), fits clothes to it as
shells of the body itself (a worn leather duster, open over a knit turtleneck, dark trousers and
leather boots), paints his face (stubble, brows, lips, shading) over the body's real anatomy, adds
eyes and hair, and binds it all to the game's rig with smooth (automatic) weights.

Exports assets/models/characters/detective.glb with looping `idle` and `walk` clips (walk is in
place; game code moves the node). Run: bash tools/blender.sh art/blender/characters/detective.py
With `--combat` it builds the more detailed combat-screen version instead (finer head, fuller-
resolution clothes, a bigger face texture), exported as detective_combat.glb:
bash tools/blender.sh art/blender/characters/detective.py --combat

Material names matter to the tests: the coat is `coat*`; `face*`, `skin*`, `eye*` and `hair*`
aren't clothes; the amulet is the only emissive material.
"""

import math
import pathlib
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, kdtree

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import kit

kit.reset()
COMBAT = "--combat" in kit.script_args()  # the more detailed combat-screen model
SHELL_RATIO = 0.65 if COMBAT else 0.3  # how much of the body's resolution the clothes keep
HAIR_RATIO = 1.0  # hair keeps the body's resolution: decimating it makes a ragged hairline
FACE_PX = 2048 if COMBAT else 1024
rng = np.random.default_rng(11)  # fixed seed: the same face every build

BASE = pathlib.Path(__file__).resolve().parents[2] / "base"
TEXTURES = BASE / "textures"
S = 1.11  # scale from the base body (1.684 m) to the detective (about 1.87 m before hair)
LEAN = 0.94  # narrower across than the base body: lean, not a bodybuilder
EYE = Vector((0.0329 * LEAN, -0.1222, 1.5737)) * S  # his left eye's centre (+X is his left)


# --- The base body -----------------------------------------------------------------------------------

body, eye_l, eye_r = kit.load_objects(
    BASE / "human_male_realistic.blend",
    ["GEO-body_male_realistic", "GEO-body_male_realistic.eye.L", "GEO-body_male_realistic.eye.R"])
body.location = (0, 0, 0)
bpy.context.view_layer.update()
for eye in (eye_l, eye_r):  # bake the eyes in place, unparented
    world = eye.matrix_world.copy()
    eye.parent = None
    eye.data.transform(world)
    eye.matrix_world = Matrix.Identity(4)
if body.modifiers:  # bring the sculpted detail down into the base mesh, then drop the multires
    try:
        with bpy.context.temp_override(object=body, active_object=body):
            bpy.ops.object.multires_base_apply(modifier=body.modifiers[0].name)
    except RuntimeError:
        pass
    body.modifiers.clear()

# Re-pose: the base stands with its arms ~23 degrees out and its feet apart. A temporary rig with
# automatic weights brings the arms down by his sides and the feet in, and the pose is baked in.
SHOULDER, ELBOW, WRIST, HAND = (0.165, 0, 1.385), (0.305, 0, 1.065), (0.385, 0, 0.865), (0.44, 0, 0.73)
HIP, KNEE, ANKLE, TOE = (0.09, 0, 0.9), (0.14, 0, 0.48), (0.19, 0.02, 0.08), (0.21, -0.12, 0.02)
ARM_DOWN = math.radians(17)  # leaves the arms hanging ~6 degrees out
LEGS_IN = math.radians(5)


def mirror(p, side):
    return (p[0] * side, p[1], p[2])


bones = [("spine", (0, 0, 0.85), (0, 0, 1.35), None), ("head", (0, 0, 1.35), (0, 0, 1.72), "spine")]
for side, s in ((1, "l"), (-1, "r")):
    bones += [
        (f"upperarm_{s}", mirror(SHOULDER, side), mirror(ELBOW, side), "spine"),
        (f"forearm_{s}", mirror(ELBOW, side), mirror(WRIST, side), f"upperarm_{s}"),
        (f"hand_{s}", mirror(WRIST, side), mirror(HAND, side), f"forearm_{s}"),
        (f"thigh_{s}", mirror(HIP, side), mirror(KNEE, side), "spine"),
        (f"shin_{s}", mirror(KNEE, side), mirror(ANKLE, side), f"thigh_{s}"),
        (f"foot_{s}", mirror(ANKLE, side), mirror(TOE, side), f"shin_{s}"),
    ]
pose_rig = kit.armature("repose", bones)
kit.auto_weights(pose_rig, body)


def rotate_about(point, angle):
    """A rotation about the world Y axis (front-back) through `point`."""
    p = Vector(point)
    return Matrix.Translation(p) @ Matrix.Rotation(angle, 4, "Y") @ Matrix.Translation(-p)


for side, s in ((1, "l"), (-1, "r")):
    for bone, pivot, angle in ((f"upperarm_{s}", SHOULDER, ARM_DOWN), (f"thigh_{s}", HIP, LEGS_IN)):
        pb = pose_rig.pose.bones[bone]
        pb.matrix = rotate_about(mirror(pivot, side), angle * side) @ pb.bone.matrix_local
bpy.context.view_layer.update()
kit.apply_modifiers(body)

# Label every vertex by the part of the body it belongs to (its strongest re-pose bone), so clothes
# can be cut from the right regions; then drop the temporary rig.
group_names = {g.index: g.name for g in body.vertex_groups}
labels = []
for v in body.data.vertices:
    best = max(v.groups, key=lambda g: g.weight, default=None)
    labels.append(group_names[best.group].rsplit("_", 1)[0] if best else "spine")
body.parent = None
body.vertex_groups.clear()
bpy.data.objects.remove(pose_rig)

# Scale to his height, and a touch leaner than the muscular base.
for obj in (body, eye_l, eye_r):
    obj.data.transform(Matrix.Diagonal((S * LEAN, S, S, 1.0)))
tree = kdtree.KDTree(len(body.data.vertices))
for i, v in enumerate(body.data.vertices):
    tree.insert(v.co, i)
tree.balance()


def part(p):
    """Which part of the body a point is on: spine, head, upperarm, forearm, hand, thigh, shin, foot."""
    return labels[tree.find(p)[1]]


def posed(point, pivot, angle, side):
    """Where a base-mesh landmark ended up after the re-pose and scaling."""
    v = rotate_about(mirror(pivot, side), angle * side) @ Vector(mirror(point, side))
    return Vector((v.x * S * LEAN, v.y * S, v.z * S))


TOP = max(v.co.z for v in body.data.vertices)
HEAD_BOTTOM = 1.43 * S  # under the jaw
COLLAR = 1.445 * S  # top of the turtleneck's roll collar, below the narrowest point of the neck
WAIST = 0.97 * S


# --- Textures and materials ------------------------------------------------------------------------

def noise(size, cells):
    """Smooth value noise in 0..1 that tiles."""
    grid = rng.random((cells + 1, cells + 1))
    grid[-1, :], grid[:, -1] = grid[0, :], grid[:, 0]
    x = np.linspace(0, cells, size, endpoint=False)
    i = x.astype(int)
    f = x - i
    f = f * f * (3 - 2 * f)
    rows = grid[i][:, i] * (1 - f)[None, :] + grid[i][:, i + 1] * f[None, :]
    rows_below = grid[i + 1][:, i] * (1 - f)[None, :] + grid[i + 1][:, i + 1] * f[None, :]
    return rows * (1 - f)[:, None] + rows_below * f[:, None]


def fbm(size, cells=4, octaves=5):
    total, weight, norm = np.zeros((size, size)), 1.0, 0.0
    for octave in range(octaves):
        total += weight * noise(size, cells * 2 ** octave)
        norm += weight
        weight *= 0.5
    return total / norm


def bump(d, width):
    t = np.clip(1.0 - np.abs(d) / width, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def face_textures(size):
    """His face, painted in the head's cylindrical UV space (see the uv_cylinder call below):
    weathered skin, a flush on the cheeks and nose, dark stubble, heavy brows, thin lips, shading,
    plus a height map (pores, stubble, brow and forehead lines) for the normal map."""
    v, u = (np.mgrid[0:size, 0:size] + 0.5) / size
    angle = (u - 0.25) * 2 * math.pi  # 0 = straight ahead, + = towards his left
    z = HEAD_BOTTOM + v * (TOP - HEAD_BOTTOM)
    radius = 0.075 * S
    across = np.sin(angle) * radius  # roughly x on the face
    front = np.clip(np.cos(angle) * 3.0, 0.0, 1.0)  # fades round to the sides
    eye_z, eye_x = EYE.z, EYE.x
    brow_z, nose_z, mouth_z, chin_z = eye_z + 0.024 * S, eye_z - 0.045 * S, eye_z - 0.072 * S, eye_z - 0.112 * S

    shade = 0.9 + 0.2 * fbm(size, 8, 6)
    image = np.array([0.88, 0.7, 0.6])[None, None, :] * shade[..., None]
    flush = (bump(np.hypot(np.abs(across) - 0.035 * S, z - nose_z), 0.025 * S)
             + bump(np.hypot(across, z - nose_z), 0.015 * S)) * front
    image = image * (1 - 0.14 * flush[..., None]) + np.array([0.86, 0.52, 0.46]) * 0.14 * flush[..., None]
    sockets = bump(np.hypot(np.abs(across) - eye_x, (z - eye_z) * 1.3), 0.02 * S) * front
    hollows = bump(np.hypot(np.abs(across) - 0.045 * S, z - (nose_z - 0.012 * S)), 0.02 * S) * front
    image *= (1 - 0.3 * sockets - 0.1 * hollows)[..., None]

    speckle = (rng.random((size, size)) < 0.5).astype(float)
    jaw = np.clip((mouth_z + 0.012 * S - z) / (0.012 * S), 0, 1) * np.clip((z - chin_z + 0.04 * S) / (0.02 * S), 0, 1)
    jaw *= np.abs(np.sin(angle)) < 0.97
    upper_lip = bump(z - (mouth_z + 0.01 * S), 0.006 * S) * bump(across, 0.024 * S) * front
    lips = bump(z - mouth_z, 0.0045 * S) * bump(across, 0.022 * S) * front
    stubble = np.maximum(jaw, upper_lip) * (1 - lips) * (0.5 + 0.5 * speckle)
    image = image * (1 - 0.55 * stubble[..., None]) + np.array([0.17, 0.13, 0.11]) * 0.55 * stubble[..., None]
    image = image * (1 - 0.45 * lips[..., None]) + np.array([0.58, 0.34, 0.31]) * 0.45 * lips[..., None]
    brows = np.zeros((size, size))
    for side in (-1, 1):
        line = brow_z + 0.004 * S * (np.abs(across) - eye_x) / (0.02 * S)
        brows += bump(z - line, 0.005 * S) * bump(across - side * (eye_x + 0.003 * S), 0.021 * S) * front
    brows *= 0.7 + 0.3 * speckle
    image = image * (1 - 0.85 * brows[..., None]) + np.array([0.09, 0.06, 0.05]) * 0.85 * brows[..., None]

    forehead = bump(z - (brow_z + 0.025 * S), 0.015 * S) * (np.sin(z * 1400) > 0.7) * front
    crows = bump(np.abs(across) - 0.05 * S, 0.008 * S) * bump(z - eye_z, 0.01 * S) * (np.sin(z * 1800) > 0.6)
    image *= (1 - 0.035 * forehead - 0.12 * crows)[..., None]
    height = 0.5 + 0.15 * noise(size, 160) + 0.25 * stubble * speckle - 0.3 * (forehead + crows) + 0.2 * brows
    return image, height


face_rgb, face_height = face_textures(FACE_PX)
face_skin = kit.textured_material("face_skin", kit.image_texture("face_skin", face_rgb), roughness=0.6,
                                  normal_image=kit.normal_map_from_height("face_skin_normal", face_height, 3.0))
skin = kit.material("skin", (0.8, 0.63, 0.53), roughness=0.65)


def photo(name, albedo, normal, roughness, tint=None):
    """A material from a committed photo texture and its normal map. `tint` (r, g, b) darkens and
    recolours the photo: it's desaturated, then multiplied by the tint."""
    image = kit.load_image(TEXTURES / albedo)
    if tint is not None:
        w, h = image.size
        rgb = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)[..., :3]
        grey = rgb.mean(axis=-1, keepdims=True)
        image = kit.image_texture(name, grey * np.array(tint)[None, None, :] * 1.6)
    return kit.textured_material(name, image, roughness=roughness, normal_image=kit.load_image(TEXTURES / normal))


coat = photo("coat_leather", "brown_leather_albedo_2k.jpg", "brown_leather_nor_gl_2k.jpg", 0.55)
sweater = photo("sweater_knit", "knitted_fleece_diff_1k.jpg", "knitted_fleece_nor_gl_1k.jpg", 0.9)
trousers = photo("trousers_denim", "denim_fabric_diff_1k.jpg", "denim_fabric_nor_gl_1k.jpg", 0.85, tint=(0.16, 0.16, 0.18))
boots = photo("boots_leather", "fabric_leather_02_diff_1k.jpg", "fabric_leather_02_nor_gl_1k.jpg", 0.5, tint=(0.14, 0.1, 0.08))
eye_white = kit.material("eye_white", (0.86, 0.83, 0.78), roughness=0.15)
eye_iris = kit.material("eye_iris", (0.34, 0.44, 0.52), roughness=0.15)
eye_pupil = kit.material("eye_pupil", (0.02, 0.02, 0.02), roughness=0.15)
def hair_textures(size):
    """Dark brown hair as streaks of strands running back over the head (along v), with a height
    map so the strands catch the light."""
    u = np.arange(size)[None, :] / size
    strands = 0.6 * noise(size, 96) + 0.4 * np.abs(np.sin((u + 0.05 * noise(size, 6)) * math.pi * 180))
    streaks = np.repeat(strands.mean(axis=0, keepdims=True), size, axis=0) * 0.7 + strands * 0.3
    shade = 0.55 + 0.6 * streaks
    image = np.array([0.075, 0.055, 0.042])[None, None, :] * shade[..., None]
    return image, streaks


hair_rgb, hair_height = hair_textures(512)
hair = kit.textured_material("hair_dark", kit.image_texture("hair_dark", hair_rgb), roughness=0.7,
                             normal_image=kit.normal_map_from_height("hair_dark_normal", hair_height, 2.5))
chain = kit.material("chain_silver", (0.6, 0.6, 0.62), roughness=0.3)
amulet = kit.material("amulet", (0.6, 0.85, 1.0), emission=(0.6, 0.85, 1.0))


# --- Clothes and hair, fitted to the body ----------------------------------------------------------

def finish(obj, ratio, u_repeat, v_scale):
    kit.decimate(obj, ratio)
    kit.uv_cylinder(obj, u_repeat=u_repeat, v_scale=v_scale)
    return kit.smooth(obj)


def in_sweater(p):
    return WAIST - 0.05 * S < p.z < COLLAR and part(p) in ("spine", "head")


def in_coat(p):
    opening = abs(p.x) < 0.05 * S and p.y < -0.04 * S and p.z < 1.36 * S  # open at the front
    torso = part(p) == "spine" and 0.9 * S < p.z < 1.43 * S
    return (torso or part(p) in ("upperarm", "forearm")) and not opening


def in_trousers(p):
    return (part(p) in ("thigh", "shin") and p.z > 0.13 * S) or (part(p) == "spine" and p.z < WAIST)


def in_boots(p):
    return part(p) == "foot" or (part(p) == "shin" and p.z < 0.16 * S)


def in_hair(p):
    """A man's hairline: high on the forehead, down past the temples to above the ears, and down to
    the nape at the back."""
    forward = max(0.0, min(1.0, -(p.y + 0.02 * S) / (0.09 * S)))  # 0 at the sides/back, 1 at the brow
    hairline = EYE.z + (0.02 + 0.045 * forward) * S
    back = p.y > 0.01 * S and p.z > 1.5 * S
    return part(p) == "head" and (p.z > hairline or back)


weighted = [
    finish(kit.shell(body, "sweater", in_sweater, 0.007, sweater, smoothing=10, edge_smoothing=25), SHELL_RATIO, 6, 4),
    finish(kit.shell(body, "coat", in_coat, 0.018, coat, smoothing=12, edge_smoothing=25), SHELL_RATIO, 4, 1.5),
    finish(kit.shell(body, "trousers", in_trousers, 0.009, trousers, smoothing=6, edge_smoothing=15), SHELL_RATIO, 4, 3),
    finish(kit.shell(body, "boots", in_boots, 0.02, boots, smoothing=24, min_z=0.0, edge_smoothing=15), SHELL_RATIO, 3, 4),
    finish(kit.shell(body, "hair", in_hair, 0.01, hair, smoothing=6, edge_smoothing=40), HAIR_RATIO, 3, 2),
]
# The duster's skirt: from the hips, flaring to below the knee, open at the front.
skirt = kit.lathe(
    "coat_skirt", [(0.3, 0.45), (0.28, 0.58), (0.25, 0.75), (0.22, 0.9), (0.2, 1.02), (0.19, 1.08)],
    segments=40 if COMBAT else 28, arc=326, arc_start=287, mat=coat,
    deform=lambda v, a, ring: (v.x, v.y * 0.72, v.z))
weighted.append(finish(kit.subdivide(skirt, 2 if COMBAT else 1), 1.0, 4, 1.5))

# Eyes (the base mesh's own, with an iris and pupil each), messy locks of hair, and the amulet.
rigid = []
for eye, side, s in ((eye_l, 1, "l"), (eye_r, -1, "r")):
    eye.data.materials.clear()
    eye.data.materials.append(eye_white)
    eye.vertex_groups.new(name="head").add(range(len(eye.data.vertices)), 1.0, "REPLACE")
    centre = Vector((EYE.x * side, EYE.y, EYE.z))
    rigid.append(kit.smooth(eye))
    rigid.append(kit.smooth(kit.ball(f"iris_{s}", 0.0058 * S, subdivisions=2, location=centre + Vector((0, -0.0118 * S, 0)),
                                     scale=(1, 0.3, 1), mat=eye_iris, bone="head")))
    rigid.append(kit.smooth(kit.ball(f"pupil_{s}", 0.0026 * S, subdivisions=1, location=centre + Vector((0, -0.0128 * S, 0)),
                                     scale=(1, 0.3, 1), mat=eye_pupil, bone="head")))
for i in range(7):
    x = (i - 3) * 0.018 * S
    rigid.append(kit.smooth(kit.ball(f"lock_{i}", 0.024 * S, subdivisions=2,
                                     location=(x, -0.02 * S, TOP - 0.012 - abs(x) * 0.25),
                                     rotation=(-14, 0, rng.uniform(-10, 10) - x * 150), scale=(0.45, 1.9, 0.28),
                                     mat=hair, bone="head")))
rigid.append(kit.smooth(kit.lathe("chain", [(0.072 * S, 0.0), (0.077 * S, 0.01)], segments=24,
                                  location=(0, -0.02, 1.36 * S), rotation=(-24, 0, 0), mat=chain, bone="chest")))
rigid.append(kit.smooth(kit.ball("amulet", 0.03, subdivisions=2, location=(0, -0.155 * S, 1.2 * S), scale=(1, 0.3, 1),
                                 mat=amulet, bone="chest")))

# The body itself shows only at the head and hands; the face is textured.
body.data.materials.clear()
body.data.materials.append(face_skin)
body.data.materials.append(skin)
for poly in body.data.polygons:
    poly.material_index = 0 if part(poly.center) == "head" else 1
if COMBAT:  # a finer head for the combat close-ups
    body.modifiers.new("Subdivision", "SUBSURF").levels = 1
    kit.apply_modifiers(body)
kit.uv_cylinder(body, v_scale=1 / (TOP - HEAD_BOTTOM), v_offset=-HEAD_BOTTOM / (TOP - HEAD_BOTTOM))
kit.smooth(body)


# --- Rig, skinning and animation -------------------------------------------------------------------

shoulder = Vector((SHOULDER[0] * LEAN, SHOULDER[1], SHOULDER[2])) * S
hip = Vector((HIP[0] * LEAN, HIP[1], HIP[2])) * S
rig = kit.armature("detective", [
    ("spine", (0, 0, 0.9 * S), (0, 0, 1.2 * S), None),
    ("chest", (0, 0, 1.2 * S), (0, 0, 1.42 * S), "spine"),
    ("head", (0, 0, 1.42 * S), (0, 0, TOP), "chest"),
    ("arm_l", tuple(shoulder), tuple(posed(WRIST, SHOULDER, ARM_DOWN, 1)), "chest"),
    ("arm_r", (-shoulder.x, shoulder.y, shoulder.z), tuple(posed(WRIST, SHOULDER, ARM_DOWN, -1)), "chest"),
    ("leg_l", tuple(hip), tuple(posed(ANKLE, HIP, LEGS_IN, 1)), None),
    ("leg_r", (-hip.x, hip.y, hip.z), tuple(posed(ANKLE, HIP, LEGS_IN, -1)), None),
])


def body_shows(p):
    """Only the head (above the collar) and the hands are bare; the rest is under clothes."""
    return (part(p) == "head" and p.z > HEAD_BOTTOM - 0.03 * S) or part(p) == "hand"


model = kit.bind_weighted(rig, body, weighted, rigid, "detective", keep_body_face=body_shows)

# Idle: a slow breath while he glances left, then right (3 s).
kit.animate(rig, "idle", {
    0: {"head": (0, 0, 0)},
    30: {"chest": (2, 0, 0), "head": (0, 0, 15), "arm_l": (0, 2, 0), "arm_r": (0, -2, 0)},
    60: {"head": (0, 0, 0)},
    75: {"chest": (2, 0, 0), "head": (-3, 0, -15), "arm_l": (0, 2, 0), "arm_r": (0, -2, 0)},
    90: {"head": (0, 0, 0)},
})

# Walk: a long-legged stride, arms swinging against the legs, in place (1 s).
kit.animate(rig, "walk", {
    0: {"leg_l": (18, 0, 0), "leg_r": (-18, 0, 0), "arm_l": (-14, 0, 0), "arm_r": (14, 0, 0), "spine": (0, 3, 0)},
    15: {"leg_l": (-18, 0, 0), "leg_r": (18, 0, 0), "arm_l": (14, 0, 0), "arm_r": (-14, 0, 0), "spine": (0, -3, 0)},
    30: {"leg_l": (18, 0, 0), "leg_r": (-18, 0, 0), "arm_l": (-14, 0, 0), "arm_r": (14, 0, 0), "spine": (0, 3, 0)},
})

kit.export(model_name="detective_combat" if COMBAT else "detective", kind="characters", preview_colors="TEXTURE")
