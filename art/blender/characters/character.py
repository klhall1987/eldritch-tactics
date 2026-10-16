"""The player character: a realistic, normal-looking man, built with MPFB (the MakeHuman plugin for
Blender) from CC0 MakeHuman assets.

His base layer only: a slim man in his 30s with short dark hair and plain boxer briefs (painted onto
the body), so clothes can go on over him as separate models. MPFB makes the body from its sliders
and fits a low-poly body mesh (male1591), eyes, eyebrows, eyelashes and short hair to it, on its
game-engine skeleton. The MakeHuman assets he uses are committed under art/base/makehuman (see
art/base/README.md); MPFB itself must be installed in Blender (it brings the base mesh, its shape
targets and the skeleton). The script swaps MPFB's materials for plain textured ones that export
cleanly to glTF, and authors looping `idle` and `walk` clips (walk is in place; game code moves him).

Exports assets/models/characters/character.glb. Run: bash tools/blender.sh art/blender/characters/character.py

Material names matter to the tests: `skin*`, `eye*`, `brow*`, `lash*`, `hair*` and `underwear*`.
"""

import math
import pathlib
import sys

import addon_utils
import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import kit

MPFB = "bl_ext.user_default.mpfb"
MAKEHUMAN = pathlib.Path(__file__).resolve().parents[2] / "base" / "makehuman"
FPS = kit.FPS

kit.reset()
# tools/blender.sh starts Blender with --factory-startup, which leaves user add-ons off. MPFB reads
# its own preferences while registering, so it has to be enabled as a (session-only) preference.
addon_utils.enable(MPFB, default_set=True)
if not addon_utils.check(MPFB)[1]:
    raise SystemExit("MPFB isn't installed in this Blender: install the MPFB extension "
                     "(https://extensions.blender.org/add-ons/mpfb/) and try again.")
from bl_ext.user_default.mpfb.services import HumanService, TargetService  # noqa: E402

for obj in list(bpy.data.objects):  # MPFB works in the scene; start it empty
    bpy.data.objects.remove(obj)


# --- The body, from MPFB's sliders -----------------------------------------------------------------

macro = TargetService.get_default_macro_info_dict()
macro.update({
    "gender": 1.0,  # male
    "age": 0.55,  # about 32
    "muscle": 0.5,
    "weight": 0.38,  # slim
    "height": 0.6,  # about 1.86 m to the top of his hair
    "proportions": 0.5,
})
macro["race"] = {"caucasian": 1.0, "asian": 0.0, "african": 0.0}
basemesh = HumanService.create_human(macro_detail_dict=macro)
rig = HumanService.add_builtin_rig(basemesh, "game_engine")
rig.name = rig.data.name = "character"


def asset(path, kind):
    """Fits a MakeHuman asset (committed under art/base/makehuman) to the body, skinned to the rig."""
    return HumanService.add_mhclo_asset(str(MAKEHUMAN / path), basemesh, asset_type=kind, subdiv_levels=0)


body = asset("proxymeshes/male1591/male1591.proxy", "Proxymeshes")
eyes = asset("eyes/low-poly/low-poly.mhclo", "Eyes")
brows = asset("eyebrows/eyebrow001/eyebrow001.mhclo", "Eyebrows")
lashes = asset("eyelashes/eyelashes01/eyelashes01.mhclo", "Eyelashes")
hair = asset("hair/short02/short02.mhclo", "Hair")
bpy.data.objects.remove(basemesh)  # the full-resolution mesh: only its low-poly body is shipped
for obj, name in ((body, "body"), (eyes, "eyes"), (brows, "eyebrows"), (lashes, "eyelashes"), (hair, "hair")):
    obj.name = obj.data.name = name
bpy.context.view_layer.update()
HEIGHT = max((obj.matrix_world @ v.co).z for obj in (body, hair) for v in obj.data.vertices)


# --- Materials: plain textures that export cleanly ------------------------------------------------

def load(path):
    return bpy.data.images.load(str(MAKEHUMAN / path), check_existing=True)


def darkened(image, brightness):
    """A copy of `image` scaled so its opaque pixels average `brightness` (the brightest channel)."""
    w, h = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)
    opaque = pixels[..., 3] > 0.5
    current = pixels[..., :3][opaque].max(axis=-1).mean()
    pixels[..., :3] *= brightness / current
    copy = bpy.data.images.new(image.name.rsplit(".", 1)[0] + "_dark", w, h, alpha=True)
    copy.pixels.foreach_set(pixels.ravel())
    copy.pack()
    return copy


def textured(name, image, roughness=0.6, cutout=False):
    """A Principled material showing `image`. With `cutout`, the image's alpha cuts holes (alpha clip:
    glTF's MASK mode, which a Round node on the alpha tells the exporter)."""
    mat = bpy.data.materials.new(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = roughness
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if cutout:
        clip = nodes.new("ShaderNodeMath")
        clip.operation = "ROUND"
        links.new(tex.outputs["Alpha"], clip.inputs[0])
        links.new(clip.outputs[0], bsdf.inputs["Alpha"])
    return mat


def use(obj, *materials):
    obj.data.materials.clear()
    for mat in materials:
        obj.data.materials.append(mat)


skin = textured("skin", load("skins/young_caucasian_male/young_lightskinned_male_diffuse.png"), roughness=0.55)
briefs = kit.material("underwear_briefs", (0.03, 0.03, 0.035), roughness=0.75)
waistband = kit.material("underwear_waistband", (0.16, 0.16, 0.18), roughness=0.65)
use(body, skin, briefs, waistband)
use(eyes, textured("eye_brown", load("eyes/materials/brown_eye.png"), roughness=0.1))
use(brows, textured("brow", load("eyebrows/eyebrow001/eyebrow001.png"), roughness=0.8, cutout=True))
use(lashes, textured("lash", load("eyelashes/eyelashes01/eyelashes01.png"), roughness=0.8, cutout=True))
use(hair, textured("hair_short", darkened(load("hair/short02/short02_diffuse.png"), 0.13), roughness=0.5, cutout=True))

# Boxer briefs, painted onto the body (no separate shell to poke through): the body is cut straight
# across at the leg openings, the bottom of the waistband and its top, and the faces between take the
# briefs' materials. His arms are out to the sides in the rest pose, so only the hips are in range.
BRIEFS_BOTTOM = 0.43 * HEIGHT
WAISTBAND = 0.535 * HEIGHT
BRIEFS_TOP = 0.55 * HEIGHT
bm = bmesh.new()
bm.from_mesh(body.data)
for z in (BRIEFS_BOTTOM, WAISTBAND, BRIEFS_TOP):
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, z), plane_no=(0, 0, 1))
bm.to_mesh(body.data)
bm.free()
for poly in body.data.polygons:
    c = poly.center
    if abs(c.x) < 0.22 and BRIEFS_BOTTOM < c.z < BRIEFS_TOP:
        poly.material_index = 2 if c.z > WAISTBAND else 1
for obj in (body, eyes, brows, lashes, hair):
    kit.smooth(obj)


# --- Rest pose: arms down -----------------------------------------------------------------------------
# MPFB's rest pose holds the arms out and forward. He's re-posed standing with his arms hanging just
# clear of his sides, and that becomes the rest pose (the clothes are fitted to it, and his animations
# start from it): each arm bone is turned so it points down, the pose is baked into the meshes, and
# the skeleton's rest is set to it.

for pb in rig.pose.bones:
    pb.rotation_mode = "QUATERNION"
MESHES = (body, eyes, brows, lashes, hair)


def aim(bone, direction):
    """Turns `bone` about its head so it points along `direction` (world: +X his left, -Y ahead, +Z up)."""
    bpy.context.view_layer.update()
    pb = rig.pose.bones[bone]
    head = pb.matrix.translation.copy()
    turn = (pb.tail - pb.head).normalized().rotation_difference(Vector(direction).normalized())
    pb.matrix = Matrix.Translation(head) @ turn.to_matrix().to_4x4() @ Matrix.Translation(-head) @ pb.matrix
    bpy.context.view_layer.update()


for side in (1, -1):
    s = "l" if side > 0 else "r"
    aim(f"upperarm_{s}", (0.13 * side, 0.02, -1.0))  # hanging, a hand's width out from his side
    aim(f"lowerarm_{s}", (0.06 * side, -0.14, -1.0))  # elbow a little bent, forearm slightly forward
for obj in MESHES:  # bake the pose into the meshes...
    with bpy.context.temp_override(object=obj, active_object=obj):
        for mod in [m for m in obj.modifiers if m.type == "ARMATURE"]:
            bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.pose.armature_apply(selected=False)  # ...make it the skeleton's rest...
bpy.ops.object.mode_set(mode="OBJECT")
for obj in MESHES:  # ...and skin them to it again, with the same weights.
    obj.modifiers.new("Armature", "ARMATURE").object = rig


# --- Animation ----------------------------------------------------------------------------------------
# The game-engine skeleton's bones are rolled every which way, so poses are given as turns about the
# world's axes (Blender's: +X his left, -Y in front of him, +Z up) and applied parent first.

X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))


def arms(swing_l=0.0, swing_r=0.0, bend=0.0):
    """His arms swung forward (+) or back (-) by `swing_*` degrees, elbows bent `bend` more than at rest."""
    return {
        "upperarm_l": [(X, -swing_l)],
        "upperarm_r": [(X, -swing_r)],
        "lowerarm_l": [(X, -bend)],
        "lowerarm_r": [(X, -bend)],
    }


def pose(turns):
    """Poses the rig: `turns` maps bone -> [(world axis, degrees), ...], applied in order."""
    for pb in rig.pose.bones:
        pb.rotation_quaternion = Quaternion()
    bpy.context.view_layer.update()
    for pb in rig.pose.bones:  # parents come before their children
        if pb.name not in turns:
            continue
        head = pb.matrix.translation.copy()
        turn = Matrix.Identity(4)
        for axis, degrees in turns[pb.name]:
            turn = Matrix.Rotation(math.radians(degrees), 4, axis) @ turn
        pb.matrix = Matrix.Translation(head) @ turn @ Matrix.Translation(-head) @ pb.matrix
        bpy.context.view_layer.update()


def animate(name, keys):
    """A looping clip: `keys` maps frame -> turns (see pose). It gets Godot's -loop import suffix."""
    action = bpy.data.actions.new(name + "-loop")
    action.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = action
    for frame, turns in sorted(keys.items()):
        pose(turns)
        for pb in rig.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=frame)
    track = rig.animation_data.nla_tracks.new()
    track.name = action.name
    track.strips.new(action.name, int(min(keys)), action)
    rig.animation_data.action = None
    pose({})


def merged(*parts):
    turns = {}
    for part in parts:
        for bone, rotations in part.items():
            turns.setdefault(bone, []).extend(rotations)
    return turns


# Idle (3 s): standing easy, a slow breath, a glance to one side and back. Hips and legs stay still.
animate("idle", {
    0: merged(arms()),
    int(1.0 * FPS): merged(arms(bend=2), {"spine_02": [(X, -1.5)], "neck_01": [(Z, 10)]}),
    int(2.0 * FPS): merged(arms(bend=1), {"spine_02": [(X, -0.5)], "neck_01": [(Z, -6)]}),
    int(3.0 * FPS): merged(arms()),
})


def stride(lead):
    """Half a walk cycle: `lead` (+1 left, -1 right) is the leg out in front, the other behind with its
    knee bending, arms swinging against the legs."""
    left, right = 26 * lead, -26 * lead
    return merged(
        arms(swing_l=-16 * lead, swing_r=16 * lead, bend=6),
        {"thigh_l": [(X, -left)], "thigh_r": [(X, -right)],
         "calf_l": [(X, 30 if lead < 0 else 4)], "calf_r": [(X, 30 if lead > 0 else 4)],
         "spine_01": [(Z, 4 * lead)], "pelvis": [(Z, -3 * lead)]})


# Walk (1 s): a relaxed stride, in place.
animate("walk", {0: stride(1), int(0.5 * FPS): stride(-1), FPS: stride(1)})

kit.export(model_name="character", kind="characters", preview_colors="TEXTURE")
