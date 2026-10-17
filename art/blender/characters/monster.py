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

import bmesh
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
# Compact, so it fits about 0.31 m round (its legs aside), like the cultist it replaces: a round body
# with its head tucked in front, the legs high-kneed and splayed just enough to keep its footprint small.
HIP_Z = 0.5
LEGS = {  # leg: (hip, knee, foot), on its left; the right side mirrors them
    "leg_1": ((0.12, -0.05, HIP_Z), (0.28, -0.12, 0.9), (0.33, -0.2, 0.0)),
    "leg_2": ((0.12, 0.1, HIP_Z), (0.28, 0.16, 0.88), (0.33, 0.22, 0.0)),
}
MANDIBLE = ((0.05, -0.21, 0.52), (0.1, -0.27, 0.48), (0.035, -0.31, 0.45))  # root, bend, tip (its left)


def body_tool(name, points, handles="AUTO"):
    """A mesh grown by the Body Tool around a curve through `points`, [(position, radius), ...]; the
    body is about 0.4 x the radius across (at least 0.04 m). `handles` "VECTOR" makes the curve straight
    segments (jointed legs) rather than smooth."""
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
        point.handle_left_type = point.handle_right_type = handles
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


def hollow(part, centres, radius):
    """Deletes `part`'s vertices within `radius` of any of `centres` (where another part covers it)."""
    bm = bmesh.new()
    bm.from_mesh(part.data)
    gone = [v for v in bm.verts if any((v.co - Vector(c)).length < radius for c in centres)]
    bmesh.ops.delete(bm, geom=gone, context="VERTS")
    bm.to_mesh(part.data)
    bm.free()


def mirrored(p, side):
    return (p[0] * side, p[1], p[2])


skin = kit.material("monster_skin", (0.045, 0.055, 0.04), roughness=0.55)
glow = kit.material("monster_eyes", (0.5, 1.0, 0.3), emission=(0.5, 1.0, 0.3))

parts = []
abdomen = body_tool("abdomen", [((0, 0.1, 0.55), 1.1), ((0, 0.03, 0.56), 1.3), ((0, -0.04, 0.57), 1.05)])
follow(abdomen, "spine")
head = body_tool("head", [((0, -0.12, 0.6), 0.75), ((0, -0.17, 0.58), 0.6)])
follow(head, "head")
parts += [kit.decimate(abdomen, 0.22), kit.decimate(head, 0.35)]
# `root` never moves: the legs hang from it (not from the body), so the body can lunge and recoil
# while the feet stay planted.
# `spine` starts low in the body and `head` high on the head, so its torso (between them, where cuts
# go, #93) spans its height.
bones = [("root", (0, 0.02, 0.3), (0, 0.02, 0.4), None), ("spine", (0, 0.03, 0.42), (0, -0.06, 0.6), "root"),
         ("head", (0, -0.14, 0.74), (0, -0.24, 0.68), "spine")]
# The Body Tool mirrors what it grows across X, so each pair of legs (and the mandibles) is one curve
# on its left; every vertex then follows the nearest bone on whichever side it is.
for leg, (hip, knee, foot) in LEGS.items():
    part = body_tool(leg, [(hip, 0.27), (knee, 0.21), (foot, 0.2)], handles="VECTOR")
    hollow(part, [mirrored(knee, 1), mirrored(knee, -1)], 0.05)  # the knee bulge (below) takes its place there
    segments = []
    for side, s in ((1, "l"), (-1, "r")):
        h, k, f = mirrored(hip, side), mirrored(knee, side), mirrored(foot, side)
        upper, lower, end = f"{leg}_upper_{s}", f"{leg}_lower_{s}", f"{leg}_foot_{s}"
        segments += [(upper, h, k), (lower, k, f)]
        bones += [(upper, h, k, "root"), (lower, k, f, upper), (end, f, (f[0], f[1], f[2] - 0.03), lower)]
    follow_nearest(part, segments)
    parts.append(kit.decimate(part, 0.6))
    # A knobbly knee: a swollen joint of chitin around where the two segments meet.
    knob = body_tool(f"{leg}_knee", [(tuple(k + (h - k) * 0.22 for k, h in zip(knee, hip)), 0.32), (knee, 0.4), (tuple(k + (f - k) * 0.12 for k, f in zip(knee, foot)), 0.32)])
    follow_nearest(knob, segments)
    parts.append(kit.decimate(knob, 0.5))
mandibles = body_tool("mandibles", [(MANDIBLE[0], 0.38), (MANDIBLE[1], 0.3), (MANDIBLE[2], 0.2)])
segments = []
for side, s in ((1, "l"), (-1, "r")):
    root, bend, tip = (mirrored(p, side) for p in MANDIBLE)
    segments += [(f"mandible_{s}", root, bend), (f"mandible_{s}", bend, tip)]
    bones.append((f"mandible_{s}", root, tip, "head"))
follow_nearest(mandibles, segments)
parts.append(kit.decimate(mandibles, 0.6))
# A cluster of glowing eyes across the front of its head: two big, four small.
for x, z, r in ((0.05, 0.64, 0.025), (-0.05, 0.64, 0.025), (0.1, 0.6, 0.015), (-0.1, 0.6, 0.015), (0.03, 0.69, 0.013), (-0.03, 0.69, 0.013)):
    eye = kit.ball("eye", r, subdivisions=2, location=(x, -0.255 + abs(x) * 0.7, z), mat=glow)
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


# --- Surface: textures baked onto the game mesh ----------------------------------------------------
# Its hide gets three maps, baked with Cycles onto UVs unwrapped here: a normal map from a high-detail
# copy (chitin plates and fine pores displaced into it), and colour and roughness from a procedural
# shader (a dark back, a paler belly, mottling; glossy plates and matte crevices between them).

TEXTURE_SIZE = 1024


def select_only(*objects, active):
    for obj in scene.objects:
        obj.select_set(obj in objects)
    bpy.context.view_layer.objects.active = active


def image(name, colour=True):
    img = bpy.data.images.new(f"monster_{name}", TEXTURE_SIZE, TEXTURE_SIZE, alpha=False)
    img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    return img


def shader_nodes(material):
    """The procedural hide, in `material`'s node tree: returns (colour socket, roughness socket)."""
    nodes, links = material.node_tree.nodes, material.node_tree.links
    coords = nodes.new("ShaderNodeTexCoord")
    geometry = nodes.new("ShaderNodeNewGeometry")
    plates = nodes.new("ShaderNodeTexVoronoi")
    plates.feature = "DISTANCE_TO_EDGE"
    plates.inputs["Scale"].default_value = 22.0
    links.new(coords.outputs["Object"], plates.inputs["Vector"])
    mottle = nodes.new("ShaderNodeTexNoise")
    mottle.inputs["Scale"].default_value = 9.0
    mottle.inputs["Detail"].default_value = 6.0
    links.new(coords.outputs["Object"], mottle.inputs["Vector"])
    # How much a point faces down: 0 on its back and sides, 1 underneath.
    normal_z = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geometry.outputs["Normal"], normal_z.inputs["Vector"])
    belly = nodes.new("ShaderNodeMapRange")
    belly.inputs["From Min"].default_value = -0.1
    belly.inputs["From Max"].default_value = -0.75
    links.new(normal_z.outputs["Z"], belly.inputs["Value"])
    hide = nodes.new("ShaderNodeMix")
    hide.data_type = "RGBA"
    hide.inputs["A"].default_value = (0.022, 0.028, 0.02, 1)  # its back: near-black green
    hide.inputs["B"].default_value = (0.11, 0.095, 0.07, 1)  # its belly: pale, sickly
    links.new(belly.outputs["Result"], hide.inputs["Factor"])
    # Mottling and dark crevices between the plates.
    shade = nodes.new("ShaderNodeMapRange")
    shade.inputs["To Min"].default_value = 0.55
    shade.inputs["To Max"].default_value = 1.45
    links.new(mottle.outputs["Fac"], shade.inputs["Value"])
    crevice = nodes.new("ShaderNodeMapRange")
    crevice.inputs["From Max"].default_value = 0.08
    crevice.inputs["To Min"].default_value = 0.35
    links.new(plates.outputs["Distance"], crevice.inputs["Value"])
    tone = nodes.new("ShaderNodeMath")
    tone.operation = "MULTIPLY"
    links.new(shade.outputs["Result"], tone.inputs[0])
    links.new(crevice.outputs["Result"], tone.inputs[1])
    colour = nodes.new("ShaderNodeMix")
    colour.data_type = "RGBA"
    colour.blend_type = "MULTIPLY"
    colour.inputs["Factor"].default_value = 1.0
    links.new(hide.outputs["Result"], colour.inputs["A"])
    links.new(tone.outputs["Value"], colour.inputs["B"])
    # Glossy, wet plates; matte crevices and belly.
    rough = nodes.new("ShaderNodeMapRange")
    rough.inputs["From Max"].default_value = 0.08
    rough.inputs["To Min"].default_value = 0.85
    rough.inputs["To Max"].default_value = 0.2
    links.new(plates.outputs["Distance"], rough.inputs["Value"])
    roughness = nodes.new("ShaderNodeMath")
    roughness.operation = "MAXIMUM"
    links.new(rough.outputs["Result"], roughness.inputs[0])
    belly_rough = nodes.new("ShaderNodeMath")
    belly_rough.operation = "MULTIPLY"
    belly_rough.inputs[1].default_value = 0.75
    links.new(belly.outputs["Result"], belly_rough.inputs[0])
    links.new(belly_rough.outputs["Value"], roughness.inputs[1])
    return colour.outputs["Result"], roughness.outputs["Value"]


# UVs for the game mesh.
select_only(model, active=model)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.01)
bpy.ops.object.mode_set(mode="OBJECT")

# The high-detail copy: smoothed, with chitin plates and pores pushed into it.
detail = model.copy()
detail.data = model.data.copy()
detail.name = "monster_detail"
scene.collection.objects.link(detail)
detail.parent = None
detail.matrix_world = model.matrix_world
for mod in list(detail.modifiers):
    detail.modifiers.remove(mod)
detail.modifiers.new("Smooth", "SUBSURF").levels = 2
for name, kind, size, strength in (("plates", "VORONOI", 0.045, 0.012), ("pores", "CLOUDS", 0.008, 0.004)):
    texture = bpy.data.textures.new(f"monster_{name}", kind)
    texture.noise_scale = size
    displace = detail.modifiers.new(name, "DISPLACE")
    displace.texture = texture
    displace.texture_coords = "OBJECT"
    displace.strength = strength
kit.apply_modifiers(detail)

albedo, roughness_map, normal_map = image("albedo"), image("roughness", colour=False), image("normal", colour=False)
scene.render.engine = "CYCLES"
scene.cycles.samples = 4
scene.cycles.device = "CPU"
scene.render.bake.margin = 8
bake_material = bpy.data.materials.new("monster_skin_bake")
nodes, links = bake_material.node_tree.nodes, bake_material.node_tree.links
for node in list(nodes):
    nodes.remove(node)
colour_out, rough_out = shader_nodes(bake_material)
emit = nodes.new("ShaderNodeEmission")
output = nodes.new("ShaderNodeOutputMaterial")
links.new(emit.outputs["Emission"], output.inputs["Surface"])
target = nodes.new("ShaderNodeTexImage")
nodes.active = target
saved = list(model.data.materials)
for i in range(len(saved)):  # every face bakes into the one set of maps (slots swapped in place)
    model.data.materials[i] = bake_material
for img, source in ((albedo, colour_out), (roughness_map, rough_out)):
    links.new(source, emit.inputs["Color"])
    target.image = img
    select_only(model, active=model)
    bpy.ops.object.bake(type="EMIT")
target.image = normal_map
select_only(model, detail, active=model)
bpy.ops.object.bake(type="NORMAL", use_selected_to_active=True, cage_extrusion=0.03, normal_space="TANGENT")
bpy.data.objects.remove(detail)
for i, material in enumerate(saved):
    model.data.materials[i] = material
for img in (albedo, roughness_map, normal_map):
    img.pack()

# The skin's final material: the three maps.
nodes, links = skin.node_tree.nodes, skin.node_tree.links
bsdf = nodes["Principled BSDF"]
for img, socket in ((albedo, "Base Color"), (roughness_map, "Roughness")):
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    links.new(tex.outputs["Color"], bsdf.inputs[socket])
normal_tex = nodes.new("ShaderNodeTexImage")
normal_tex.image = normal_map
normal_node = nodes.new("ShaderNodeNormalMap")
links.new(normal_tex.outputs["Color"], normal_node.inputs["Color"])
links.new(normal_node.outputs["Normal"], bsdf.inputs["Normal"])
bsdf.inputs["Base Color"].default_value = (1, 1, 1, 1)
scene.render.engine = "BLENDER_WORKBENCH"
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
    0.15: merged(body(forward=-0.03), jaws(50)),
    0.32: merged(body(forward=0.13)),
    0.6: merged(body(forward=-0.02), jaws(50)),
    0.84: merged(body(forward=0.14)),
    1.2: {},
}, loop=False)

# Hit (0.6 s): it recoils, mandibles flaring, then settles.
animate("hit", {0.0: {}, 0.17: merged(body(forward=-0.1, up=0.02), jaws(12)), 0.6: {}}, loop=False)

for track in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(track)
kit.export("monster", "characters", preview_colors="TEXTURE", animation_mode="ACTIONS")
