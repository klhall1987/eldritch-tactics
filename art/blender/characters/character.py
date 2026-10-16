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


AIM = "aim"


def pose(turns):
    """Poses the rig: `turns` maps bone -> [(world axis, degrees), ...], applied in order. An entry
    (AIM, direction) instead turns the bone to point along that world direction, wherever its parents
    have put it."""
    for pb in rig.pose.bones:
        pb.rotation_quaternion = Quaternion()
    bpy.context.view_layer.update()
    for pb in rig.pose.bones:  # parents come before their children
        if pb.name not in turns:
            continue
        head = pb.matrix.translation.copy()
        turn = Matrix.Identity(4)
        for axis, degrees in turns[pb.name]:
            if axis == AIM:
                current = (pb.tail - pb.head).normalized()
                turn = current.rotation_difference(Vector(degrees).normalized()).to_matrix().to_4x4() @ turn
                continue
            turn = Matrix.Rotation(math.radians(degrees), 4, axis) @ turn
        pb.matrix = Matrix.Translation(head) @ turn @ Matrix.Translation(-head) @ pb.matrix
        bpy.context.view_layer.update()


def animate(name, keys, loop=True):
    """A clip: `keys` maps frame -> turns (see pose). Looping clips get Godot's -loop import suffix;
    with `loop=False` it plays once.
    Each clip stays its own action (no NLA tracks): the exporter writes actions one at a time, so no
    clip leaks into another."""
    action = bpy.data.actions.new(name + "-loop" if loop else name)
    action.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = action
    for frame, turns in sorted(keys.items()):
        pose(turns)
        for pb in rig.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=frame)
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


def guard(bounce):
    """His bare-handed fighting stance: fists up by his chin, elbows in, left foot ahead and feet set
    wide. `bounce` (0..1) dips the chest and fists a little; his legs don't move, so his feet stay put."""
    stance = {
        "thigh_l": [(Y, -4), (X, -7)],  # out to his left and a little ahead
        "thigh_r": [(Y, 4), (X, 4)],  # out to his right and a little behind
        "spine_01": [(Z, 22), (X, -9 - 2 * bounce)],  # side-on, left shoulder leading, hunched forward
    }
    # The arms are aimed (world directions, Blender's: +X his left, -Y ahead, +Z up), so the twist of
    # his torso doesn't swing them out: upper arms down and forward with the elbows in, forearms up to
    # fists by his chin, the lead (left) fist a little further out.
    dip = 0.06 * bounce
    fists = {
        "clavicle_l": [(Y, -6)],  # shoulders hunched up a little
        "clavicle_r": [(Y, 6)],
        "upperarm_l": [(AIM, (-0.12, -0.62, -0.78 - dip))],
        "upperarm_r": [(AIM, (0.18, -0.5, -0.85 - dip))],
        "lowerarm_l": [(AIM, (-0.3, -0.55, 0.78 - dip))],
        "lowerarm_r": [(AIM, (0.42, -0.42, 0.8 - dip))],
        "neck_01": [(X, 6)],  # chin tucked
    }
    return merged(stance, fists)


# Combat idle (1.5 s): standing in his guard, bouncing gently on the spot.
animate("combat_idle", {0: guard(0), int(0.75 * FPS): guard(1), int(1.5 * FPS): guard(0)})


def punch(side):
    """His guard with one arm thrown straight out at shoulder height: the left (+1) is the jab, the
    right (-1) the cross, with his torso turning and leaning into it. His legs keep the guard's."""
    pose_ = guard(0)
    s = "l" if side > 0 else "r"
    reach = (-0.1 * side, -1.0, 0.04)  # straight ahead, angled in a little towards the centre line
    pose_[f"upperarm_{s}"] = [(AIM, reach)]
    pose_[f"lowerarm_{s}"] = [(AIM, reach)]
    pose_["spine_01"] = [(Z, 26 if side > 0 else -8), (X, 8)]  # turn the punching shoulder forward, lean in
    return pose_


# Attack (1.2 s): a jab with the lead (left) fist, back to the guard, then a cross with the right.
animate("attack", {
    0: guard(0),
    int(0.27 * FPS): punch(1),
    int(0.5 * FPS): guard(0),
    int(0.8 * FPS): punch(-1),
    int(1.2 * FPS): guard(0),
}, loop=False)


def flinch():
    """His guard knocked back: chest and head snapping back, fists lifting a little to cover."""
    pose_ = guard(0)
    pose_["spine_01"] = [(Z, 22), (X, -20)]
    pose_["neck_01"] = [(X, -8)]
    return pose_


# Hit (0.6 s): a quick flinch backwards, then he recovers his guard.
animate("hit", {0: guard(0), int(0.17 * FPS): flinch(), int(0.6 * FPS): guard(0)}, loop=False)

out = kit.ASSETS_DIR / "characters" / "character.glb"
bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", export_yup=True, export_apply=True,
                          export_animations=True, export_animation_mode="ACTIONS")
print(f"KIT: exported {out}")
for path in kit.render_previews("character", colors="TEXTURE"):
    print(f"KIT: preview {path}")
