"""The player character: a realistic, normal-looking man, built with MPFB (the MakeHuman plugin for
Blender) from CC0 MakeHuman assets.

His base layer only: a slim man in his 30s with short dark hair and plain boxer briefs (painted onto
the body), so clothes can go on over him as separate models (art/blender/clothes/outfit.py). The
body, skeleton and arms-down rest pose come from art/blender/lib/human.py, shared with the clothes so
they fit him exactly. On top of it, MPFB fits low-poly eyes, eyebrows, eyelashes and short hair; the
script swaps MPFB's materials for plain textured ones that export cleanly to glTF, and authors
looping `idle` and `walk` clips (walk is in place; game code moves him).

Exports assets/models/characters/character.glb. Run: bash tools/blender.sh art/blender/characters/character.py

Material names matter to the tests: `skin*`, `eye*`, `brow*`, `lash*`, `hair*` and `underwear*`.
"""

import math
import pathlib
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import human
import kit

FPS = kit.FPS

kit.reset()
human.start()
basemesh, rig = human.create()
body = human.body(basemesh)
eyes = human.asset(basemesh, "eyes/low-poly/low-poly.mhclo", "Eyes")
brows = human.asset(basemesh, "eyebrows/eyebrow001/eyebrow001.mhclo", "Eyebrows")
lashes = human.asset(basemesh, "eyelashes/eyelashes01/eyelashes01.mhclo", "Eyelashes")
hair = human.asset(basemesh, "hair/short02/short02.mhclo", "Hair")
bpy.data.objects.remove(basemesh)  # the full-resolution mesh: only its low-poly body is shipped
for obj, name in ((eyes, "eyes"), (brows, "eyebrows"), (lashes, "eyelashes"), (hair, "hair")):
    obj.name = obj.data.name = name
bpy.context.view_layer.update()
HEIGHT = human.height((body, hair))


# --- Materials: plain textures that export cleanly ------------------------------------------------

skin = human.textured("skin", human.load("skins/young_caucasian_male/young_lightskinned_male_diffuse.png"), roughness=0.55)
briefs = kit.material("underwear_briefs", (0.03, 0.03, 0.035), roughness=0.75)
waistband = kit.material("underwear_waistband", (0.16, 0.16, 0.18), roughness=0.65)
human.use(body, skin, briefs, waistband)
human.use(eyes, human.textured("eye_brown", human.load("eyes/materials/brown_eye.png"), roughness=0.1))
human.use(brows, human.textured("brow", human.load("eyebrows/eyebrow001/eyebrow001.png"), roughness=0.8, cutout=True))
human.use(lashes, human.textured("lash", human.load("eyelashes/eyelashes01/eyelashes01.png"), roughness=0.8, cutout=True))
human.use(hair, human.textured("hair_short", human.darkened(human.load("hair/short02/short02_diffuse.png"), 0.13),
                               roughness=0.5, cutout=True))

# Boxer briefs, painted onto the body (no separate shell to poke through): the body is cut straight
# across at the leg openings, the bottom of the waistband and its top, and the faces between take the
# briefs' materials. His arms are out to the sides in MPFB's pose, so only the hips are in range.
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

human.arms_down(rig, (body, eyes, brows, lashes, hair))


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
