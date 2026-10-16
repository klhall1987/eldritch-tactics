"""The cultist: a Resident Evil-style zombie in cultist's robes, about 1.78 m tall to the top of its hood.

Built on the committed CC0 male base body (art/base/human_male_realistic.blend), re-posed and made
gaunt, with grey, blotchy, veined, bloodied skin painted over the body's real anatomy (and a normal
map), glowing green eyes (the base mesh's own), and a torn, filthy, blood-stained hooded robe: a
robe fitted to the body over the chest and arms, an outer shroud and a darker under-robe with ragged
hems, hanging strips, a rounded hood, and bandage wraps on the forearms. Bare, rotting hands and
feet. Cloth uses the committed CC0 photo textures (art/base/textures), recoloured and painted with
grime and dried blood in code; see art/base/README.md. Smoothly skinned to the game's rig.

Exports assets/models/characters/cultist.glb with looping `idle` and `walk` clips (walk is in
place; game code moves the node). Run: bash tools/blender.sh art/blender/characters/cultist.py
With `--combat` it builds the more detailed combat-screen version instead (the body at full
resolution, finer robes and more strips), exported as cultist_combat.glb.

Material names matter to the tests: clothes are `robe*`, `rag*` or `wrap*`; the face and bare skin
are `face*`; the eyes are `eyes`, the only emissive material.
"""

import math
import pathlib
import sys

import numpy as np
from mathutils import Vector

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import kit

kit.reset()
COMBAT = "--combat" in kit.script_args()  # the more detailed combat-screen model
BODY_RATIO = 1.0 if COMBAT else 0.35  # how much of the base body's resolution it keeps
SHELL_RATIO = 0.8 if COMBAT else 0.35
SEGMENTS = 64 if COMBAT else 32  # round the robes
STRIPS = 28 if COMBAT else 14
TEXTURES = pathlib.Path(__file__).resolve().parents[2] / "base" / "textures"
rng = np.random.default_rng(23)  # fixed seed: the same rot, grime and blood every build
cloth_rng = __import__("random").Random(7)  # and the same rags

LEAN = 0.9  # gaunt: narrower across than the base body
S = 1.0  # the base body's own height (1.684 m); the hood brings it to about 1.78 m

# --- The base body, re-posed, made gaunt, and its parts ------------------------------------------------

body, eye_l, eye_r, part = kit.load_male_body(arm_down_degrees=19.0, legs_in_degrees=6.0)
kit.scale_body((body, eye_l, eye_r), part, LEAN * S, S, S)
kit.decimate(body, BODY_RATIO)
TOP = max(v.co.z for v in body.data.vertices)
EYE = Vector((kit.MALE_EYE[0] * LEAN, kit.MALE_EYE[1], kit.MALE_EYE[2])) * S
HEAD_BOTTOM = 1.43 * S
WAIST = 0.97 * S


# --- Textures ----------------------------------------------------------------------------------------

def noise(size, cells):
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


def mix(image, mask, colour):
    return image * (1 - mask[..., None]) + np.asarray(colour)[None, None, :] * mask[..., None]


def corpse_skin(size):
    """Dead skin, painted in the head's cylindrical UV space: grey-green and blotchy, with dark veins,
    purple bruising, sunken sockets, dark lips and dried blood round the mouth and chin; plus a height
    map (veins, pores, wrinkles) for the normal map."""
    v, u = (np.mgrid[0:size, 0:size] + 0.5) / size
    angle = (u - 0.25) * 2 * math.pi
    z = HEAD_BOTTOM + v * (TOP - HEAD_BOTTOM)
    across = np.sin(angle) * 0.075 * S
    front = np.clip(np.cos(angle) * 3.0, 0.0, 1.0)
    mouth_z, chin_z = EYE.z - 0.072 * S, EYE.z - 0.112 * S

    blotch = fbm(size, 6, 6)
    image = np.array([0.52, 0.55, 0.47])[None, None, :] * (0.8 + 0.4 * blotch[..., None])
    image = mix(image, np.clip((noise(size, 5) - 0.55) * 3.0, 0, 0.6), (0.4, 0.34, 0.37))  # bruising
    branching = noise(size, 22) * 0.75 + noise(size, 60) * 0.25  # thin, forking veins
    veins = np.clip((0.012 - np.abs(branching - 0.5)) * 60.0, 0.0, 1.0) * np.clip(noise(size, 4) * 1.6 - 0.4, 0, 1)
    image = mix(image, veins * 0.45, (0.27, 0.25, 0.31))
    sockets = bump(np.hypot(np.abs(across) - EYE.x, (z - EYE.z) * 1.2), 0.024 * S) * front
    image *= (1 - 0.5 * sockets)[..., None]
    lips = bump(z - mouth_z, 0.006 * S) * bump(across, 0.024 * S) * front
    image = mix(image, lips * 0.7, (0.24, 0.12, 0.13))
    gore = bump(across, 0.04 * S) * np.clip((mouth_z + 0.004 * S - z) / (0.01 * S), 0, 1)
    gore *= np.clip((z - chin_z + 0.03 * S) / (0.02 * S), 0, 1) * front
    gore *= np.clip(noise(size, 18) * 1.6 - 0.2, 0, 1)
    image = mix(image, gore * 0.85, (0.3, 0.04, 0.03))
    height = 0.5 + 0.12 * noise(size, 150) + 0.3 * veins + 0.08 * blotch - 0.2 * sockets
    return image, height


def stained(name, source, tint, blood=0.0, grime=0.5, stripes=0.0):
    """A cloth texture from a committed photo, desaturated and recoloured by `tint`, then painted with
    filth (`grime`) and patches of dried blood (`blood`: roughly the share of the cloth soaked)."""
    photo = kit.load_image(TEXTURES / source)
    w, h = photo.size
    grey = np.array(photo.pixels[:], dtype=np.float32).reshape(h, w, 4)[..., :3].mean(axis=-1)
    image = grey[..., None] * np.asarray(tint)[None, None, :] * 1.7
    if stripes:  # bandage wraps: bands of cloth wound round and round
        image *= (1 - stripes * (np.sin(np.arange(h)[:, None] / h * math.pi * 40) > 0.85))[..., None]
    side = max(w, h)  # photos needn't be square: paint masks at the larger size and crop
    filth = np.clip((fbm(side, 4, 5)[:h, :w] - 0.4) * 2.5, 0, 1) * grime
    image = mix(image, filth * 0.7, (0.1, 0.08, 0.06))
    if blood:
        soak = fbm(side, 3, 5)[:h, :w]
        threshold = np.quantile(soak, 1.0 - blood)
        patches = np.clip((soak - threshold) * 30.0, 0, 1)
        image = mix(image, patches * 0.92, (0.32, 0.035, 0.03))
    return kit.image_texture(name, image)


skin_rgb, skin_height = corpse_skin(2048 if COMBAT else 1024)
face_skin = kit.textured_material("face_skin", kit.image_texture("face_skin", skin_rgb), roughness=0.55,
                                  normal_image=kit.normal_map_from_height("face_skin_normal", skin_height, 3.5))


def cloth(name, source, normal, tint, roughness=0.9, **paint):
    return kit.textured_material(name, stained(name, source, tint, **paint), roughness=roughness,
                                 normal_image=kit.load_image(TEXTURES / normal))


robe = cloth("robe", "denim_fabric_diff_1k.jpg", "denim_fabric_nor_gl_1k.jpg", (0.36, 0.13, 0.08), blood=0.09)
robe_under = cloth("robe_under", "knitted_fleece_diff_1k.jpg", "knitted_fleece_nor_gl_1k.jpg", (0.3, 0.2, 0.13),
                   blood=0.05)
robe_hood = cloth("robe_hood", "denim_fabric_diff_1k.jpg", "denim_fabric_nor_gl_1k.jpg", (0.3, 0.11, 0.07), blood=0.04)
rags = cloth("rags", "denim_fabric_diff_1k.jpg", "denim_fabric_nor_gl_1k.jpg", (0.34, 0.25, 0.17), grime=0.8)
wrap_bandage = cloth("wrap_bandage", "knitted_fleece_diff_1k.jpg", "knitted_fleece_nor_gl_1k.jpg",
                     (0.6, 0.55, 0.42), blood=0.06, grime=0.7, stripes=0.35)
eyes = kit.material("eyes", (0.35, 0.9, 0.3), emission=(0.4, 1.0, 0.3))


# --- Robes, rags and wraps ---------------------------------------------------------------------------

def finish(obj, ratio, u_repeat, v_scale):
    kit.decimate(obj, ratio)
    kit.uv_cylinder(obj, u_repeat=u_repeat, v_scale=v_scale)
    return kit.smooth(obj)


def folds(amount, waves):
    def deform(v, angle, ring):
        scale = 1.0 + amount * math.sin(waves * angle + ring * 0.7) + cloth_rng.uniform(-0.01, 0.01)
        return (v.x * scale, v.y * scale * 0.85, v.z)
    return deform


def ragged(base, hem):
    def deform(v, angle, ring):
        x, y, z = base(v, angle, ring)
        if ring == 0:
            z = hem(angle)
            jitter = 1.0 + cloth_rng.uniform(-0.04, 0.04)
            x, y = x * jitter, y * jitter
        return (x, y, z)
    return deform


def in_robe_top(p):
    torso = part(p) == "spine" and 0.92 * S < p.z < 1.44 * S
    return torso or part(p) == "upperarm" or (part(p) == "forearm" and p.z > 1.0 * S)


def in_wraps(p):
    return part(p) == "forearm" and p.z <= 1.02 * S


weighted = [
    finish(kit.shell(body, "robe_top", in_robe_top, 0.03, robe, smoothing=14, edge_smoothing=20), SHELL_RATIO, 4, 1.5),
    finish(kit.shell(body, "wraps", in_wraps, 0.008, wrap_bandage, smoothing=4, edge_smoothing=10), SHELL_RATIO, 2, 6),
]
# The under-robe: torn up high at the sides, dragging front and back.
draped = [finish(kit.lathe(
    "under_robe", [(0.2, 0.04), (0.19, 0.18), (0.18, 0.35), (0.17, 0.55), (0.165, 0.62), (0.16, 0.7), (0.17, 0.9),
                   (0.18, 1.0)],
    segments=SEGMENTS, mat=robe_under,
    deform=ragged(folds(0.03, 6), lambda a: 0.04 + 0.1 * (0.5 + 0.5 * math.cos(2 * a)) + cloth_rng.uniform(0, 0.025))),
    1.0, 4, 1.5)]
# The outer shroud: rounded, folded, its hem torn short in front and longer behind.
draped.append(finish(kit.lathe(
    "shroud", [(0.23, 0.3), (0.215, 0.42), (0.2, 0.55), (0.19, 0.62), (0.185, 0.7), (0.18, 0.85), (0.19, 0.97),
               (0.2, 1.06)],
    segments=SEGMENTS, mat=robe,
    deform=ragged(folds(0.05, 9), lambda a: 0.3 - 0.1 * max(0.0, math.sin(a)) + cloth_rng.uniform(0, 0.07))),
    1.0, 4, 1.5))
# The hood: a rounded shell open at the front, sitting back on the skull.
hood = (finish(kit.lathe(
    "hood", [(0.13, -0.15), (0.15, -0.05), (0.155, 0.04), (0.14, 0.11), (0.1, 0.165), (0.05, 0.195), (0.01, 0.205)],
    segments=SEGMENTS - 4, arc=260, arc_start=-40, location=(0, -0.01, 1.575 * S), mat=robe_hood,
    deform=lambda v, a, ring: (v.x * (1 + 0.04 * math.sin(7 * a)), v.y * 1.2 * (1 + 0.04 * math.sin(7 * a)),
                               v.z - (0.04 * max(0.0, math.sin(a)) if ring == 0 else 0.0))), 1.0, 3, 2))
# Strips torn from the shroud's hem.
for i in range(STRIPS):
    a = 2 * math.pi * (i + cloth_rng.uniform(-0.3, 0.3)) / STRIPS
    bottom, top = cloth_rng.uniform(0.17, 0.26), 0.36
    strip = kit.box(f"strip_{i}", (cloth_rng.uniform(0.03, 0.05), 0.008, top - bottom),
                    location=(0.22 * math.cos(a), 0.22 * 0.85 * math.sin(a), (top + bottom) / 2),
                    rotation=(cloth_rng.uniform(-6, 6), 8, math.degrees(a) + 90), mat=rags)
    draped.append(finish(strip, 1.0, 1, 1))


def weigh(obj, weights_at):
    """Skins a cloth part by hand: weights_at(point) gives {bone: weight} for each vertex."""
    for v in obj.data.vertices:
        for bone, weight in weights_at(v.co).items():
            if weight > 0.0:
                group = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
                group.add([v.index], weight, "REPLACE")
    return obj


def skirt_weights(p):
    """A skirt hangs from the hips and is dragged by both legs: pure spine at the waist, blending
    lower down into a mix of the legs, most of all the nearer one."""
    drag = min(1.0, max(0.0, (WAIST - p.z) / (WAIST - 0.3))) * 0.7
    side = min(1.0, max(-1.0, p.x / 0.12))
    left, right = drag * (0.5 + 0.5 * side), drag * (0.5 - 0.5 * side)
    return {"spine": 1.0 - left - right, "leg_l": left, "leg_r": right}


def hood_weights(p):
    """The hood moves with the head, and its lower edge with the shoulders."""
    shoulders = min(1.0, max(0.0, (1.5 * S - p.z) / 0.12)) * 0.6
    return {"head": 1.0 - shoulders, "chest": shoulders}


# Eyes: the base mesh's own, glowing a faint green out of the hood's shadow.
rigid = [weigh(cloth_part, skirt_weights) for cloth_part in draped] + [weigh(hood, hood_weights)]
for eye in (eye_l, eye_r):
    eye.data.materials.clear()
    eye.data.materials.append(eyes)
    eye.vertex_groups.new(name="head").add(range(len(eye.data.vertices)), 1.0, "REPLACE")
    rigid.append(kit.smooth(eye))

# The bare body (head, hands and feet) all wears the dead skin.
body.data.materials.clear()
body.data.materials.append(face_skin)
kit.uv_cylinder(body, v_scale=1 / (TOP - HEAD_BOTTOM), v_offset=-HEAD_BOTTOM / (TOP - HEAD_BOTTOM))
kit.smooth(body)


# --- Rig, skinning and animation -------------------------------------------------------------------

def posed(point, pivot, degrees, side):
    p = kit.rotate_about_y((pivot[0] * side, pivot[1], pivot[2]), math.radians(degrees) * side) @ Vector(
        (point[0] * side, point[1], point[2]))
    return (p.x * LEAN * S, p.y * S, p.z * S)


shoulder = (kit.MALE_SHOULDER[0] * LEAN * S, 0.0, kit.MALE_SHOULDER[2] * S)
hip = (kit.MALE_HIP[0] * LEAN * S, 0.0, kit.MALE_HIP[2] * S)
rig = kit.armature("cultist", [
    ("spine", (0, 0, 0.9 * S), (0, 0, 1.2 * S), None),
    ("chest", (0, 0, 1.2 * S), (0, 0, 1.42 * S), "spine"),
    ("head", (0, 0, 1.42 * S), (0, 0, TOP), "chest"),
    ("arm_l", shoulder, posed(kit.MALE_WRIST, kit.MALE_SHOULDER, 19.0, 1), "chest"),
    ("arm_r", (-shoulder[0], 0.0, shoulder[2]), posed(kit.MALE_WRIST, kit.MALE_SHOULDER, 19.0, -1), "chest"),
    ("leg_l", hip, posed(kit.MALE_ANKLE, kit.MALE_HIP, 6.0, 1), None),
    ("leg_r", (-hip[0], 0.0, hip[2]), posed(kit.MALE_ANKLE, kit.MALE_HIP, 6.0, -1), None),
])


def body_shows(p):
    """Only the head (inside the hood), the hands and the bare feet show; the rest is under robes."""
    return (part(p) == "head" and p.z > HEAD_BOTTOM - 0.03 * S) or part(p) in ("hand", "foot")


model = kit.bind_weighted(rig, body, weighted, rigid, "cultist", keep_body_face=body_shows, weight_smoothing=25)

# Idle: a slow, swaying breath with the head lolling (2 s).
kit.animate(rig, "idle", {
    0: {"spine": (0, 0, 0), "head": (0, 0, 0)},
    30: {"spine": (2, 2, 0), "chest": (3, 0, 0), "head": (-6, 0, 4), "arm_l": (0, 3, 0), "arm_r": (0, -3, 0)},
    60: {"spine": (0, 0, 0), "head": (0, 0, 0)},
})

SWING = -95  # degrees an arm turns about its own X to fling up and forward (negative: forward)
FPS = kit.FPS

# Walk: legs and arms swing in opposition, in place (1 s).
kit.animate(rig, "walk", {
    0: {"leg_l": (22, 0, 0), "leg_r": (-22, 0, 0), "arm_l": (-15, 0, 0), "arm_r": (15, 0, 0), "spine": (0, 3, 0)},
    15: {"leg_l": (-22, 0, 0), "leg_r": (22, 0, 0), "arm_l": (15, 0, 0), "arm_r": (-15, 0, 0), "spine": (0, -3, 0)},
    30: {"leg_l": (22, 0, 0), "leg_r": (-22, 0, 0), "arm_l": (-15, 0, 0), "arm_r": (15, 0, 0), "spine": (0, 3, 0)},
})

# Attack (1.2 s): two fist swings, the left arm then the right, each flung up and forward from the
# shoulder (its arms are single bones, with no elbow), its chest leaning into the blow. It starts and
# ends in the pose idle starts in; its legs don't move.
kit.animate(rig, "attack", {
    0: {},
    int(0.3 * FPS): {"arm_l": (SWING, 0, 0), "chest": (8, 0, -10), "spine": (4, 0, 0)},
    int(0.55 * FPS): {},
    int(0.85 * FPS): {"arm_r": (SWING, 0, 0), "chest": (8, 0, 10), "spine": (4, 0, 0)},
    int(1.2 * FPS): {},
}, loop=False)

# Hit (0.6 s): a flinch, chest and head knocked back, then it recovers.
kit.animate(rig, "hit", {
    0: {},
    int(0.17 * FPS): {"spine": (-10, 0, 0), "chest": (-10, 0, 0), "head": (-14, 0, 0)},
    int(0.6 * FPS): {},
}, loop=False)

# Each clip goes out as its own action (see kit.export): the NLA tracks kit.animate made are dropped.
for track in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(track)
kit.export(model_name="cultist_combat" if COMBAT else "cultist", kind="characters", preview_colors="TEXTURE",
           animation_mode="ACTIONS")
