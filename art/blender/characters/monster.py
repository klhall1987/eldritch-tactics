"""The monster: a small Lovecraftian creature, about a metre tall, built with Joey Carlino's Creature
Creator (CC BY 4.0, see art/base/README.md).

A thick, bulbous body and head on four skinny, high-kneed insect legs, with a pair of curved
mandibles at its mouth and a cluster of glowing eyes. Every part is the Creature Creator's `Body Tool`
(a Geometry Nodes tool that grows a smooth, blobby body around a curve, as thick as the curve's
radius), drawn along curves here and turned into meshes; the eyes are plain glowing spheres. The
parts are then rigged to a skeleton (`spine`, `head`, `mandible_l/r`, and a three-bone chain per leg),
each vertex following the bone of the part it belongs to.

The Creature Creator isn't in the repo: like MPFB, it's a tool on this machine. Set `CREATURE_CREATOR`
to the path of `creature_creator_v1.blend` (in .claude/settings.local.json, like BLENDER).

Exports assets/models/characters/monster.glb. Run: bash tools/blender.sh art/blender/characters/monster.py
"""

import math
import os
import pathlib
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import kit

SOURCE = os.environ.get("CREATURE_CREATOR")
if not SOURCE or not pathlib.Path(SOURCE).is_file():
    raise SystemExit("Set CREATURE_CREATOR to the path of the Creature Creator's creature_creator_v1.blend.")
bpy.ops.wm.open_mainfile(filepath=SOURCE, load_ui=False)
scene = bpy.context.scene
scene.render.fps = kit.FPS
BODY_TOOL = bpy.data.objects["Body Tool.005"]  # the Creature Creator's own body tool, copied for each part

# Blender axes: +X its left, -Y in front of it, +Z up. Its feet touch z = 0.
HIP_Z = 0.55
LEGS = {  # leg: (hip, knee, foot), on its left; the right side mirrors them
    "leg_1": ((0.14, -0.1, HIP_Z), (0.36, -0.24, 0.8), (0.5, -0.36, 0.0)),
    "leg_2": ((0.14, 0.14, HIP_Z), (0.38, 0.26, 0.78), (0.52, 0.4, 0.0)),
}
MANDIBLE = ((0.06, -0.44, 0.58), (0.13, -0.54, 0.52), (0.05, -0.62, 0.47))  # root, bend, tip (its left)


def body_tool(name, points):
    """A mesh grown by the Body Tool around a curve through `points`, [(position, radius), ...]; the
    body is about 0.4 x the radius across (at least 0.04 m)."""
    obj = BODY_TOOL.copy()
    obj.data = BODY_TOOL.data.copy()
    scene.collection.objects.link(obj)
    obj.parent = None
    obj.location, obj.rotation_euler, obj.scale = (0, 0, 0), (0, 0, 0), (1, 1, 1)
    curve = obj.data
    while curve.splines:
        curve.splines.remove(curve.splines[0])
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, (at, radius) in zip(spline.bezier_points, points):
        point.co, point.radius = at, radius
        point.handle_left_type = point.handle_right_type = "AUTO"
    bpy.context.view_layer.update()
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = bpy.data.meshes.new_from_object(evaluated)
    part = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(part)
    bpy.data.objects.remove(obj)
    for attribute in [a.name for a in mesh.attributes if a.name not in ("position", ".edge_verts", ".corner_vert", ".corner_edge", ".select_vert", ".select_edge", ".select_poly", "sharp_face")]:
        if attribute in mesh.attributes and not attribute.startswith("."):
            mesh.attributes.remove(mesh.attributes[attribute])
    mesh.materials.clear()
    return part


def follow(part, bone):
    part.vertex_groups.new(name=bone).add(range(len(part.data.vertices)), 1.0, "REPLACE")


def follow_nearest(part, segments):
    """Each vertex follows the bone of the segment it's nearest: `segments` is [(bone, head, tail)]."""
    groups = {}
    for bone, _, _ in segments:
        if bone not in groups:
            groups[bone] = part.vertex_groups.new(name=bone)
    for v in part.data.vertices:
        def gap(segment):
            _, a, b = segment
            a, b = Vector(a), Vector(b)
            t = max(0.0, min(1.0, (v.co - a).dot(b - a) / (b - a).length_squared))
            return (v.co - (a + (b - a) * t)).length
        groups[min(segments, key=gap)[0]].add([v.index], 1.0, "REPLACE")


def mirrored(p, side):
    return (p[0] * side, p[1], p[2])


skin = kit.material("monster_skin", (0.045, 0.055, 0.04), roughness=0.55)
glow = kit.material("monster_eyes", (0.5, 1.0, 0.3), emission=(0.5, 1.0, 0.3))

parts = []
abdomen = body_tool("abdomen", [((0, 0.32, 0.6), 1.0), ((0, 0.08, 0.62), 1.6), ((0, -0.18, 0.64), 1.25)])
follow(abdomen, "spine")
head = body_tool("head", [((0, -0.26, 0.68), 0.85), ((0, -0.4, 0.64), 0.7)])
follow(head, "head")
parts += [kit.decimate(abdomen, 0.22), kit.decimate(head, 0.35)]
# `root` never moves: the legs hang from it (not from the body), so the body can lunge and recoil
# while the feet stay planted.
bones = [("root", (0, 0.05, 0.3), (0, 0.05, 0.45), None), ("spine", (0, 0.3, 0.6), (0, -0.16, 0.64), "root"),
         ("head", (0, -0.22, 0.66), (0, -0.44, 0.64), "spine")]
# The Body Tool mirrors what it grows across X, so each pair of legs (and the mandibles) is one curve
# on its left; every vertex then follows the nearest bone on whichever side it is.
for leg, (hip, knee, foot) in LEGS.items():
    part = body_tool(leg, [(hip, 0.32), (knee, 0.24), (foot, 0.2)])
    segments = []
    for side, s in ((1, "l"), (-1, "r")):
        h, k, f = mirrored(hip, side), mirrored(knee, side), mirrored(foot, side)
        upper, lower, end = f"{leg}_upper_{s}", f"{leg}_lower_{s}", f"{leg}_foot_{s}"
        segments += [(upper, h, k), (lower, k, f)]
        bones += [(upper, h, k, "root"), (lower, k, f, upper), (end, f, (f[0], f[1], f[2] - 0.03), lower)]
    follow_nearest(part, segments)
    parts.append(kit.decimate(part, 0.6))
mandibles = body_tool("mandibles", [(MANDIBLE[0], 0.38), (MANDIBLE[1], 0.3), (MANDIBLE[2], 0.2)])
segments = []
for side, s in ((1, "l"), (-1, "r")):
    root, bend, tip = (mirrored(p, side) for p in MANDIBLE)
    segments += [(f"mandible_{s}", root, bend), (f"mandible_{s}", bend, tip)]
    bones.append((f"mandible_{s}", root, tip, "head"))
follow_nearest(mandibles, segments)
parts.append(kit.decimate(mandibles, 0.6))
# A cluster of glowing eyes across the front of its head: two big, four small.
for x, z, r in ((0.07, 0.72, 0.03), (-0.07, 0.72, 0.03), (0.13, 0.67, 0.018), (-0.13, 0.67, 0.018), (0.04, 0.78, 0.016), (-0.04, 0.78, 0.016)):
    eye = kit.ball("eye", r, subdivisions=2, location=(x, -0.45 + abs(x) * 0.6, z), mat=glow)
    follow(eye, "head")
    parts.append(eye)
for part in parts:
    if not part.data.materials:
        part.data.materials.append(skin)

# Everything else from the Creature Creator's file goes; only the monster is exported.
for obj in [o for o in scene.objects if o not in parts]:
    bpy.data.objects.remove(obj)
for collection in list(bpy.data.collections):
    bpy.data.collections.remove(collection)

# Its feet on the floor: everything, bones too, lifted (or lowered) so its lowest point is at z = 0.
bpy.context.view_layer.update()
lowest = min((part.matrix_world @ v.co).z for part in parts for v in part.data.vertices)
for part in parts:
    part.location.z -= lowest
bones = [(bone, (h[0], h[1], h[2] - lowest), (t[0], t[1], t[2] - lowest), parent) for bone, h, t, parent in bones]

rig = kit.armature("monster", bones)
model = kit.bind(rig, parts, "monster")
for poly in model.data.polygons:
    poly.use_smooth = True
bpy.ops.outliner.orphans_purge(do_recursive=True)

# --- Animation -------------------------------------------------------------------------------------
# Poses are turns about the world's axes (Blender's: +X its left, -Y ahead, +Z up), applied parent first,
# and moves of whole bones; each clip is its own action.

X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
MOVE = "move"


def pose(turns):
    """Poses the rig: `turns` maps bone -> [(world axis, degrees) or (MOVE, offset), ...]."""
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    bpy.context.view_layer.update()
    for pb in rig.pose.bones:  # parents come before their children
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


def jaws(degrees):
    """Its mandibles opened `degrees` each, swinging out to its sides."""
    return {"mandible_l": [(Z, degrees)], "mandible_r": [(Z, -degrees)]}


def body(forward=0.0, up=0.0):
    """Its body (and head) shifted `forward` and `up` metres; its legs stay where they stand."""
    return {"spine": [(MOVE, (0, -forward, up))]}


# Idle (3 s): breathing, a twitch of the mandibles and a slow look round.
animate("idle", {
    0.0: {},
    1.0: merged(body(up=0.015), jaws(5), {"head": [(Z, 8)]}),
    2.0: merged(body(up=0.005), jaws(2), {"head": [(Z, -6)]}),
    3.0: {},
})

LEFT_PAIR = ("leg_1_upper_l", "leg_2_upper_r")  # the diagonal pairs step together
RIGHT_PAIR = ("leg_1_upper_r", "leg_2_upper_l")
SWING, LIFT = 14, 12


def step(forward, lifted):
    """Its legs mid-stride: the `forward` pair swung ahead (the other back), `lifted` raised off the floor."""
    turns = {}
    for pair, ahead in ((LEFT_PAIR, forward == LEFT_PAIR), (RIGHT_PAIR, forward == RIGHT_PAIR)):
        for bone in pair:
            side = 1 if bone.endswith("_l") else -1
            swing = -side * (SWING if ahead else -SWING)
            turns[bone] = [(Z, swing)] + ([(Y, -side * LIFT)] if pair == lifted else [])
    return turns


def passing(lifted):
    """Its legs passing under it: `lifted` pair raised, swinging through."""
    turns = {}
    for bone in lifted:
        side = 1 if bone.endswith("_l") else -1
        turns[bone] = [(Y, -side * LIFT)]
    return turns


# Walk (1 s): a scuttle in place, the diagonal pairs of legs stepping in turn.
animate("walk", {
    0.0: step(RIGHT_PAIR, None),
    0.25: merged(passing(LEFT_PAIR), body(up=0.01)),
    0.5: step(LEFT_PAIR, None),
    0.75: merged(passing(RIGHT_PAIR), body(up=0.01)),
    1.0: step(RIGHT_PAIR, None),
})

# Attack (1.2 s): two lunges, each snapping its mandibles shut; the second lands at the combat
# controller's HIT_AT (0.7 of the way through).
animate("attack", {
    0.0: {},
    0.15: merged(body(forward=-0.03), jaws(24)),
    0.32: merged(body(forward=0.13)),
    0.6: merged(body(forward=-0.02), jaws(24)),
    0.84: merged(body(forward=0.14)),
    1.2: {},
}, loop=False)

# Hit (0.6 s): it recoils, mandibles flaring, then settles.
animate("hit", {0.0: {}, 0.17: merged(body(forward=-0.1, up=0.02), jaws(12)), 0.6: {}}, loop=False)

for track in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(track)
kit.export("monster", "characters", animation_mode="ACTIONS")
