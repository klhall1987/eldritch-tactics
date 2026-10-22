"""The monster: the owner's Meshy monster (#160), its mesh and textures exactly as Meshy delivered them.

Meshy's `monster_model.glb` (in the `MESHY` folder, see art/base/README.md) is a 1.70 m creature on four
long legs, with one large claw and a segmented tail curled under it, on Meshy's 54-bone auto-rig
("SmartRig", bones `Bone_000` ... `Bone_053`) and with no animations. This script imports it, drops
Meshy's stray `Icosphere`, renames each bone for what it moves, moves the skin Meshy put on a leg that
isn't near that leg (most of the tail rode on its front-left leg) onto its body, makes its clips (#161)
and exports it. Its vertices and images aren't touched.

Set `MESHY` to the Meshy folder (in .claude/settings.local.json, like BLENDER).

Exports assets/models/characters/monster.glb. Run: bash tools/blender.sh art/blender/characters/monster.py
"""

import math
import os
import pathlib
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector
from mathutils.geometry import intersect_point_line

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import kit

MESHY = os.environ.get("MESHY")
SOURCE = pathlib.Path(MESHY or "") / "monster_model.glb"
if not MESHY or not SOURCE.is_file():
    raise SystemExit("Set MESHY to the folder holding Meshy's monster_model.glb.")

kit.reset()
scene = bpy.context.scene
scene.render.fps = kit.FPS
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
bpy.data.objects.remove(bpy.data.objects["Icosphere"])
rig = bpy.data.objects["SmartRigArmature"]
skin = bpy.data.objects["output_unwrapped"]

# --- Bones -----------------------------------------------------------------------------------------
# Blender axes: +X its left, -Y in front of it, +Z up. Meshy's chains, each top to bottom, measured in
# Blender: the legs come off its body and run down to a foot on the floor; the claw (on its right)
# hangs from its shoulder with three fingers; the head runs down its front; four short spines stand on
# its back.
CHAINS = {
    "spike_1_%d": ["Bone_005", "Bone_004", "Bone_003", "Bone_002"],
    "spike_2_%d": ["Bone_009", "Bone_008", "Bone_007", "Bone_006"],
    "spike_3_%d": ["Bone_012", "Bone_011", "Bone_010"],
    "spike_4_%d": ["Bone_016", "Bone_015", "Bone_014", "Bone_013"],
    "head_%d": ["Bone_021", "Bone_020", "Bone_019", "Bone_018", "Bone_017"],
    "claw_%d": ["Bone_023", "Bone_022"],
    "claw_finger_1_%d": ["Bone_045", "Bone_044", "Bone_043"],
    "claw_finger_2_%d": ["Bone_049", "Bone_048", "Bone_047", "Bone_046"],
    "claw_finger_3_%d": ["Bone_053", "Bone_052", "Bone_051", "Bone_050"],
    "leg_1_%d_l": ["Bone_033", "Bone_032", "Bone_031", "Bone_030", "Bone_029"],
    "leg_1_%d_r": ["Bone_038", "Bone_037", "Bone_036", "Bone_035", "Bone_034"],
    "leg_2_%d_l": ["Bone_028", "Bone_027", "Bone_026", "Bone_025", "Bone_024"],
    "leg_2_%d_r": ["Bone_042", "Bone_041", "Bone_040", "Bone_039"],
}
NAMES = {"Bone_000": "root", "Bone_001": "body"}
for pattern, chain in CHAINS.items():
    for k, bone in enumerate(chain, 1):
        NAMES[bone] = pattern % k
for meshy, name in NAMES.items():
    rig.data.bones[meshy].name = name  # renames its vertex group too
LEGS = [[pattern % k for k in range(1, len(chain) + 1)] for pattern, chain in CHAINS.items() if pattern.startswith("leg")]

# --- Skin ------------------------------------------------------------------------------------------
# Skin Meshy put on a leg but further than this from that leg's bones isn't that leg's (the tail, and
# the body's shell where the legs join it): it follows the body instead. A little inside the 0.15 m the
# tests allow, as the game keeps only each vertex's four strongest weights.
OFF_ITS_LEG = 0.14

to_world = rig.matrix_world
line_of = {}
for leg in LEGS:
    line = [to_world @ rig.data.bones[b].head_local for b in leg]
    for b in leg:
        line_of[b] = line


def distance_to_line(p, line):
    best = math.inf
    for a, b in zip(line, line[1:]):
        q, t = intersect_point_line(p, a, b)
        q = a + (b - a) * min(max(t, 0.0), 1.0)
        best = min(best, (p - q).length)
    return best


groups = {g.index: g.name for g in skin.vertex_groups}
body_group = skin.vertex_groups["body"]
moved = 0
for v in skin.data.vertices:
    if not v.groups:
        continue
    strongest = max(v.groups, key=lambda g: g.weight)
    name = groups[strongest.group]
    if name not in line_of or distance_to_line(skin.matrix_world @ v.co, line_of[name]) <= OFF_ITS_LEG:
        continue
    on_legs = [(g.group, g.weight) for g in v.groups if groups[g.group] in line_of]
    for group, _ in on_legs:
        skin.vertex_groups[groups[group]].remove([v.index])
    body_group.add([v.index], sum(w for _, w in on_legs), "ADD")
    moved += 1
print(f"MONSTER: {moved} vertices of leg skin now follow its body")

# --- Size ------------------------------------------------------------------------------------------
# Scaled as a whole to the old monster's footprint (agreed on #162): about 0.82 m tall and 0.4 m round,
# its legs aside, so it fits the garage and the reach the game gives an enemy. Applied to the rig and
# its mesh, so the clips below move it in metres.
SCALE = 0.48
rig.scale = rig.scale * SCALE
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
skin.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

# --- Animation -------------------------------------------------------------------------------------
# Poses are turns about the world's axes (+X its left, -Y ahead, +Z up), applied parent first, and moves
# of whole bones; each clip is its own action. Its legs' top bones keep their rest place whatever its
# body does, so its feet stay where they stand unless a leg is turned.

X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
MOVE = "move"
PLANTED = {leg[0] for leg in LEGS}
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE")


def pose(turns):
    """Poses the rig: `turns` maps bone -> [(world axis, degrees) or (MOVE, offset), ...]."""
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
        pb.scale = Vector((1, 1, 1))
    bpy.context.view_layer.update()
    for pb in rig.pose.bones:  # parents come before their children
        if pb.name in PLANTED:
            pb.matrix = pb.bone.matrix_local.copy()
            bpy.context.view_layer.update()
        for axis, amount in turns.get(pb.name, []):
            if axis == MOVE:
                pb.matrix = Matrix.Translation(Vector(amount)) @ pb.matrix
            else:
                head = pb.matrix.translation.copy()
                pb.matrix = Matrix.Translation(head) @ Matrix.Rotation(math.radians(amount), 4, axis) @ Matrix.Translation(-head) @ pb.matrix
            bpy.context.view_layer.update()


def animate(name, keys, loop=True):
    """A clip: `keys` maps time in seconds -> turns (see pose). Looping clips get Godot's -loop suffix."""
    action = bpy.data.actions.new(name + "-loop" if loop else name)
    action.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = action
    for seconds, turns in sorted(keys.items()):
        pose(turns)
        for pb in rig.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=round(seconds * kit.FPS))
            pb.keyframe_insert("location", frame=round(seconds * kit.FPS))
    rig.animation_data.action = None
    pose({})


def merged(*parts):
    turns = {}
    for part in parts:
        for bone, entries in part.items():
            turns.setdefault(bone, []).extend(entries)
    return turns


def body(forward=0.0, up=0.0, pitch=0.0):
    """Its body (and claw, head and tail) shifted `forward` and `up` metres and tipped `pitch` degrees
    nose-down; its legs stay where they stand."""
    return {"body": [(MOVE, (0, -forward, up))] + ([(X, pitch)] if pitch else [])}


def claw(lift=0.0, turn=0.0):
    """Its claw swung up and forward `lift` degrees at its shoulder, and `turn` degrees in towards it."""
    return {"claw_1": [(X, -lift)] + ([(Z, -turn)] if turn else [])}


def head(nod=0.0, turn=0.0):
    return {"head_1": [(X, nod)] + ([(Z, turn)] if turn else [])}


# Idle (3 s): breathing, the claw flexing and a slow look round.
animate("idle", {
    0.0: {},
    1.0: merged(body(up=0.015), claw(lift=6), head(turn=6)),
    2.0: merged(body(up=0.005), claw(lift=2), head(turn=-5)),
    3.0: {},
})


def leg_direction(leg):
    """Its leg's way out from its body, seen from above: from its top bone to its foot."""
    top = rig.data.bones[leg[0]].head_local
    foot = rig.data.bones[leg[-1]].head_local
    d = Vector((foot.x - top.x, foot.y - top.y, 0))
    return d.normalized()


SWING, LIFT = 14, 9
FRONT_L, FRONT_R, BACK_L, BACK_R = LEGS  # in CHAINS' order
LEFT_PAIR = (FRONT_L, BACK_R)  # the diagonal pairs step together
RIGHT_PAIR = (FRONT_R, BACK_L)


def step(forward, lifted):
    """Its legs mid-stride: the `forward` pair swung ahead (the other back), `lifted` raised off the floor."""
    turns = {}
    for pair in (LEFT_PAIR, RIGHT_PAIR):
        for leg in pair:
            side = 1 if leg[0].endswith("_l") else -1
            ahead = pair is forward
            turns[leg[0]] = [(Z, -side * (SWING if ahead else -SWING))]
            if pair is lifted:
                turns[leg[0]].append((leg_direction(leg).cross(Z), LIFT))
    return turns


def passing(lifted):
    """Its legs passing under it: the `lifted` pair raised, swinging through."""
    return {leg[0]: [(leg_direction(leg).cross(Z), LIFT)] for leg in lifted}


# Walk (1 s): a scuttle in place, the diagonal pairs of legs stepping in turn.
animate("walk", {
    0.0: step(RIGHT_PAIR, None),
    0.25: merged(passing(LEFT_PAIR), body(up=0.015)),
    0.5: step(LEFT_PAIR, None),
    0.75: merged(passing(RIGHT_PAIR), body(up=0.015)),
    1.0: step(RIGHT_PAIR, None),
})

# Attack (1.3 s): it rears back with its claw raised, then lunges and swipes the claw down and forward;
# the blow lands at 0.6 of the way through (its hit_at in the main scene).
animate("attack", {
    0.0: {},
    0.35: merged(body(forward=-0.06, up=0.03, pitch=-6), claw(lift=55), head(nod=-8)),
    0.78: merged(body(forward=0.24), claw(lift=48), head(nod=6)),
    1.0: merged(body(forward=0.1, pitch=4), claw(lift=30)),
    1.3: {},
}, loop=False)

# Hit (0.6 s): it recoils, head and claw thrown back, then settles.
animate("hit", {
    0.0: {},
    0.17: merged(body(forward=-0.12, up=0.02), claw(lift=-10), head(nod=15)),
    0.6: {},
}, loop=False)

bpy.ops.object.mode_set(mode="OBJECT")
for track in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(track)
kit.export("monster", "characters", preview_colors="TEXTURE", animation_mode="ACTIONS")
