"""The garage: a single-car garage someone is secretly living in, about 8 m by 6 m.

Its floor and two back walls (Godot -X and -Z) are the owner's Meshy basement pieces (#164, #165):
concrete floor tiles, brick-and-concrete walls with a corner, a roll-up garage door under a window, a
wooden door in its doorway and stairs; the camera sides are open. The furniture is built from boxes.
Each prop is its own object, so it arrives in Godot as a node named after
it. Exports assets/models/environments/garage.glb.
Run: bash tools/blender.sh art/blender/environments/garage.py
"""

import glob
import math
import os
import pathlib
import sys

import bpy
import numpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import kit

kit.reset()

stain = kit.material("oil_stain", (0.12, 0.11, 0.1))
wood = kit.material("wood", (0.42, 0.28, 0.15))
pegboard = kit.material("pegboard", (0.5, 0.38, 0.24))
metal = kit.material("metal", (0.34, 0.36, 0.4))
red_paint = kit.material("red_paint", (0.55, 0.1, 0.08))
couch_fabric = kit.material("couch_fabric", (0.27, 0.32, 0.2))
ticking = kit.material("mattress", (0.74, 0.71, 0.6))
blanket = kit.material("blanket", (0.32, 0.17, 0.36))
fridge_white = kit.material("fridge_white", (0.8, 0.77, 0.64))
cardboard = kit.material("cardboard", (0.56, 0.42, 0.25))
dark = kit.material("dark", (0.05, 0.05, 0.05))
bulb_glow = kit.material("bulb", (1.0, 0.85, 0.5), emission=(1.0, 0.8, 0.45))


def group(parent, *children):
    """Parents children to `parent` in place, so they arrive in Godot under the parent's node."""
    bpy.context.view_layer.update()
    for child in children:
        child.parent = parent
        child.matrix_parent_inverse = parent.matrix_world.inverted()
    return parent


# Blender axes: X is Godot X, +Y is Godot -Z (the back), -Y is Godot +Z (towards the camera).
# The room spans x -4..4 and y -3..3, with the floor's top at z = 0.

# --- The owner's Meshy basement pieces (#164, #165) ------------------------------------------------
# Each comes from the `MESHY` folder, normalised by Meshy to a 1.9 m box. Each is reduced once (to
# PIECE_TRIANGLES) and its maps resized (to PIECE_MAPS px, exported as JPEG), then placed as copies that
# share its mesh, each scaled as a whole.
MESHY = os.environ.get("MESHY")
if not MESHY or not glob.glob(f"{MESHY}/Meshy_AI_Basement_*.glb"):
    raise SystemExit("Set MESHY to the folder holding Meshy's basement pieces (Meshy_AI_Basement_*.glb).")
PIECE_TRIANGLES = 40000
PIECE_MAPS = 2048


def meshy_piece(source, kind):
    """Meshy's basement piece `source` (e.g. "Wall_Section"), reduced, as a template named `kind`."""
    path = glob.glob(f"{MESHY}/Meshy_AI_Basement_{source}_1020*.glb")[0]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    piece = next(o for o in new if o.type == "MESH")
    for o in new:
        if o is not piece:
            bpy.data.objects.remove(o)
    piece.parent = None
    piece.matrix_world = Matrix()
    piece.name = piece.data.name = f"template_{kind}"  # its copies take the plain names
    triangles = sum(len(p.vertices) - 2 for p in piece.data.polygons)
    if triangles > PIECE_TRIANGLES:
        bpy.context.view_layer.objects.active = piece
        reduce = piece.modifiers.new("reduce", "DECIMATE")
        reduce.ratio = PIECE_TRIANGLES / triangles
        bpy.ops.object.modifier_apply(modifier=reduce.name)
    for material in piece.data.materials:
        for node in material.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image and max(node.image.size) > PIECE_MAPS:
                node.image.scale(PIECE_MAPS, PIECE_MAPS)
            if node.type == "BSDF_PRINCIPLED":
                node.inputs["Emission Strength"].default_value = 0.0
    piece.hide_render = True  # only its copies are drawn
    return piece


def size(piece):
    """The template's size as Meshy made it: (x, y, z)."""
    corners = [Vector(c) for c in piece.bound_box]
    return Vector([max(c[i] for c in corners) - min(c[i] for c in corners) for i in range(3)])


def place(template, name, scale, turn=0, parent=None, **edges):
    """A copy of `template`, sharing its mesh, scaled as a whole by `scale` and turned `turn` degrees about
    Z, moved so its bounds' edges sit where `edges` says (xmin, xmax, ymin, ymax, zmin)."""
    piece = template.copy()
    piece.name = name
    piece.hide_render = False
    scene.collection.objects.link(piece)
    piece.scale = (scale, scale, scale)
    piece.rotation_mode = "XYZ"  # glTF imports leave it in quaternions
    piece.rotation_euler = (0, 0, math.radians(turn))
    piece.location = (0, 0, 0)
    bpy.context.view_layer.update()
    corners = [piece.matrix_world @ Vector(c) for c in piece.bound_box]
    shift = Vector()
    for key, at in edges.items():
        axis = "xyz".index(key[0])
        now = (min if key.endswith("min") else max)(c[axis] for c in corners)
        shift[axis] = at - now
    piece.location = shift
    if parent is not None:
        group(parent, piece)
    return piece


def part(name):
    """An empty named part, so its pieces arrive in Godot under one node named `name`."""
    empty = bpy.data.objects.new(name, None)
    scene.collection.objects.link(empty)
    return empty


scene = bpy.context.scene
templates = {kind: meshy_piece(source, kind) for kind, source in {
    "floor_tile": "Floor_Tile", "wall_section": "Wall_Section", "wall_corner": "Wall_Corner",
    "window_wall": "Garage_Door_", "doorway_wall": "Doorway_Wall", "wooden_door": "Wooden_Door",
    "garage_door": "Garage_Door", "stairs": "Stairs"}.items()}

# The floor: twelve tiles, each scaled to about 2 m square, 4 by 3 over the room, their tops at z = 0.
TILE = 2.0 / size(templates["floor_tile"]).y
floor_part = part("floor")
for i, x in enumerate((-3, -1, 1, 3)):
    for j, y in enumerate((-2, 0, 2)):
        tile = place(templates["floor_tile"], f"floor_tile_{i * 3 + j + 1}", TILE, parent=floor_part, zmin=0)
        tile.location += Vector((x, y, 0)) - Vector((0, 0, size(templates["floor_tile"]).z * TILE))
kit.box("oil_stain", (1.4, 0.9, 0.004), location=(1.4, 1.2, 0.002), mat=stain)
# The floor's edges as the game measures them (its vertices): the walls stop 0.52 m short of the open
# camera sides, so nothing tall stands within the 0.5 m the garage tests keep open.
bpy.context.view_layer.update()
floor_points = [t.matrix_world @ v.co for t in floor_part.children for v in t.data.vertices]
OPEN_X = max(p.x for p in floor_points) - 0.52
OPEN_Y = min(p.y for p in floor_points) + 0.52

# The back walls: 2.52 m high, their outer faces on the room's edges (x = -4, y = 3), ending just over 0.5 m
# short of the open camera sides. Where pieces overlap, one stands 1 cm behind the other.
WALL = 2.52 / size(templates["wall_section"]).z
DEPTH = size(templates["wall_section"]).y * WALL
west = part("wall_west")
north = part("wall_north")
# Meshy's corner has its walls along its +X and +Y sides; turned 90 degrees they're the west and north.
place(templates["wall_corner"], "wall_corner", WALL, turn=90, parent=north, xmin=-4.0, ymax=3.0, zmin=0)
for i, (xmin, back) in enumerate([(-4.0, 0.01), (-2.45, 0.0), (-0.99, 0.0), (-0.11, 0.01), (None, 0.01)]):
    ends = {"xmin": xmin} if xmin is not None else {"xmax": OPEN_X}
    place(templates["wall_section"], f"wall_section_n{i + 1}", WALL, parent=north, ymax=3.0 + back, zmin=0, **ends)

# The roll-up garage door, with Meshy's window strip above it (the two stack to the walls' height),
# flush with the wall's inner face; the wall section behind its east end stands 1 cm back.
GARAGE = 2.52 / (size(templates["garage_door"]).z + size(templates["window_wall"]).z)
GARAGE_AT = 1.35  # its west edge: it spans x = 1.6, where the garage tests walk him up to it
door = place(templates["garage_door"], "garage_door", GARAGE, parent=north, xmin=GARAGE_AT, ymin=3.0 - DEPTH, zmin=0)
door_top = size(templates["garage_door"]).z * GARAGE
place(templates["window_wall"], "window_wall", GARAGE, parent=north, xmin=GARAGE_AT, ymin=3.0 - DEPTH, zmin=door_top)

# The west wall: sections turned to run along it, and Meshy's doorway between the workbench and the
# mattress, its inner face flush with the wall's. The sections behind the doorway (and behind the
# corner's west side, so the west wall runs end to end on its own) stand 1 cm back.
for i, (ymin, back) in enumerate([(OPEN_Y, 0.01), (-1.06, 0.01), (-0.04, 0.0), (1.38, 0.01), (None, 0.01)]):
    ends = {"ymin": ymin} if ymin is not None else {"ymax": 3.0}
    place(templates["wall_section"], f"wall_section_w{i + 1}", WALL, turn=90, parent=west, xmin=-4.0 - back, zmin=0, **ends)
# The doorway is scaled so Meshy's wooden door, scaled as a whole, fills its opening (Meshy's opening is
# squatter than its door, so a 2.5 m doorway's door couldn't).
DOORWAY = 1.16
DOOR_AT = -1.3  # the opening's centre along the wall
doorway = place(templates["doorway_wall"], "doorway_wall", DOORWAY, turn=90, parent=west,
                xmax=-4.0 + DEPTH, ymin=DOOR_AT - size(templates["doorway_wall"]).x * DOORWAY / 2, zmin=0)


def door_fit(frame, centre, door_size):
    """The scale and lift that stand Meshy's door, scaled as a whole, closed in the doorway: clear of
    its frame (`frame`: its vertices flattened onto the wall, along it and up) by up to 3 cm of overlap,
    and within 5 cm of its sides and top, its foot within 5 cm of the floor. Best margin first."""
    best = None
    for scale in numpy.arange(0.5, 1.2, 0.001):
        w, h = door_size.x * scale, door_size.z * scale
        for lift in numpy.arange(0.0, 0.0501, 0.005):
            lo = numpy.array([centre - w / 2, lift])
            hi = numpy.array([centre + w / 2, lift + h])
            inside = ((frame[:, 0] > lo[0] + 0.03) & (frame[:, 0] < hi[0] - 0.03)
                      & (frame[:, 1] > lo[1] + 0.03) & (frame[:, 1] < hi[1] - 0.03)).any()
            if inside:
                continue
            tall = (frame[:, 1] >= lo[1]) & (frame[:, 1] <= hi[1])
            wide = (frame[:, 0] >= lo[0]) & (frame[:, 0] <= hi[0])
            left = frame[tall & (frame[:, 0] <= lo[0] + 0.03), 0]
            right = frame[tall & (frame[:, 0] >= hi[0] - 0.03), 0]
            top = frame[wide & (frame[:, 1] >= hi[1] - 0.03), 1]
            if not len(left) or not len(right) or not len(top):
                continue
            gaps = [max(lo[0] - left.max(), 0), max(right.min() - hi[0], 0), max(top.min() - hi[1], 0)]
            margin = min(0.05 - max(gaps), 0.05 - lift)
            if margin > 0 and (best is None or margin > best[0]):
                best = (margin, scale, lift)
    if best is None:
        raise SystemExit("Meshy's wooden door doesn't fit its doorway at this size.")
    return best


bpy.context.view_layer.update()
frame = numpy.array([(v.y, v.z) for v in (doorway.matrix_world @ p.co for p in doorway.data.vertices)])
middle = frame[(frame[:, 1] > 0.4) & (frame[:, 1] < 1.0)]
opening = ((middle[middle[:, 0] < DOOR_AT, 0]).max() + (middle[middle[:, 0] > DOOR_AT, 0]).min()) / 2
margin, door_scale, door_lift = door_fit(frame, opening, size(templates["wooden_door"]))
print(f"GARAGE: the wooden door is scaled {door_scale:.3f}, {door_lift:.3f} m up ({margin * 100:.1f} cm to spare)")
door_width = size(templates["wooden_door"]).x * door_scale
place(templates["wooden_door"], "wooden_door", door_scale, turn=90, parent=west,
      xmax=-4.0 + DEPTH, ymin=opening - door_width / 2, zmin=door_lift)

# Meshy's stairs, scaled with the walls, against the north wall between the shelves and the garage
# door (x = -1.5 to about 1.0, agreed on #165), their railing to the room.
place(templates["stairs"], "stairs", WALL, xmin=-1.5, ymax=3.0 - DEPTH, zmin=0)
for template in templates.values():
    bpy.data.objects.remove(template)

# Workbench against the west wall: top, legs, pegboard with tools, a red toolbox and a vise.
bench = kit.box("workbench", (0.7, 2.0, 0.08), location=(-3.38, 0.6, 0.9), mat=wood)
group(bench, *[
    kit.box(f"bench_leg_{i}", (0.07, 0.07, 0.86), location=(-3.38 + dx, 0.6 + dy, 0.43), mat=wood)
    for i, (dx, dy) in enumerate([(-0.28, -0.92), (0.28, -0.92), (-0.28, 0.92), (0.28, 0.92)])
],
    kit.box("bench_shelf", (0.62, 1.9, 0.04), location=(-3.38, 0.6, 0.25), mat=wood),
    kit.box("pegboard", (0.03, 1.8, 0.8), location=(-3.72, 0.6, 1.5), mat=pegboard),
    kit.box("hammer_head", (0.03, 0.12, 0.04), location=(-3.69, 0.1, 1.6), mat=metal),
    kit.box("hammer_handle", (0.03, 0.03, 0.28), location=(-3.69, 0.1, 1.45), mat=wood),
    kit.box("wrench", (0.02, 0.03, 0.3), location=(-3.69, 0.35, 1.5), rotation=(20, 0, 0), mat=metal),
    kit.box("saw", (0.02, 0.45, 0.14), location=(-3.69, 0.95, 1.65), mat=metal),
    kit.box("toolbox", (0.35, 0.5, 0.22), location=(-3.43, 1.2, 1.05), mat=red_paint),
    kit.box("vise", (0.16, 0.2, 0.14), location=(-3.13, -0.1, 1.01), mat=metal),
    kit.cone("coffee_mug", radius=0.05, depth=0.1, location=(-3.23, 0.5, 0.99), mat=fridge_white),
)

# An old yellowed fridge in the north-west corner.
fridge = kit.box("fridge", (0.65, 0.65, 1.7), location=(-3.40, 2.4, 0.85), mat=fridge_white)
group(fridge, kit.box("fridge_handle", (0.04, 0.04, 0.5), location=(-3.05, 2.2, 1.2), mat=metal),
      kit.box("fridge_seam", (0.01, 0.66, 0.02), location=(-3.07, 2.4, 1.15), mat=dark))

# Metal shelves on the north wall, loaded with boxes and paint cans.
shelves = kit.box("shelves", (1.2, 0.4, 0.03), location=(-2.2, 2.55, 0.15), mat=metal)
group(shelves, *[
    kit.box(f"shelf_{i}", (1.2, 0.4, 0.03), location=(-2.2, 2.55, 0.15 + 0.55 * i), mat=metal)
    for i in range(1, 4)
], *[
    kit.box(f"shelf_post_{i}", (0.04, 0.04, 1.9), location=(-2.2 + dx, 2.55 + dy, 0.95), mat=metal)
    for i, (dx, dy) in enumerate([(-0.58, -0.18), (0.58, -0.18), (-0.58, 0.18), (0.58, 0.18)])
],
    kit.box("shelf_box_a", (0.45, 0.35, 0.3), location=(-2.5, 2.55, 0.32), mat=cardboard),
    kit.box("shelf_box_b", (0.4, 0.35, 0.35), location=(-1.95, 2.55, 0.87), mat=cardboard),
    kit.box("shelf_box_c", (0.5, 0.35, 0.25), location=(-2.4, 2.55, 1.4), mat=cardboard),
    *[kit.cone(f"paint_can_{i}", radius=0.08, depth=0.18, location=(-2.6 + 0.2 * i, 2.55, 1.94), mat=metal)
      for i in range(3)],
)

# A sagging couch on the east side, facing into the room, with a lumpy cushion.
couch = kit.box("couch", (0.9, 2.0, 0.4), location=(3.0, 0.4, 0.2), rotation=(0, 2, 0), mat=couch_fabric)
group(couch,
      kit.box("couch_back", (0.25, 2.0, 0.5), location=(3.35, 0.4, 0.6), mat=couch_fabric),
      kit.box("couch_arm_s", (0.9, 0.2, 0.25), location=(3.0, -0.6, 0.52), mat=couch_fabric),
      kit.box("couch_arm_n", (0.9, 0.2, 0.25), location=(3.0, 1.4, 0.52), mat=couch_fabric),
      kit.box("couch_cushion", (0.5, 0.45, 0.15), location=(2.95, 0.9, 0.47), rotation=(0, -8, 20), mat=blanket))

# A bare mattress on the floor near the front, with a rumpled blanket and a pillow.
mattress = kit.box("mattress", (1.9, 1.0, 0.2), location=(-2.7, -2.4, 0.1), rotation=(0, 0, 4), mat=ticking)
group(mattress,
      kit.box("mattress_blanket", (1.2, 1.05, 0.06), location=(-2.4, -2.38, 0.23), rotation=(0, 3, 6), mat=blanket),
      kit.box("pillow", (0.35, 0.6, 0.1), location=(-3.4, -2.45, 0.25), mat=fridge_white))

# Clutter: boxes by the door, a TV on a crate facing the couch, a pizza box, a space heater.
kit.box("boxes_low", (0.6, 0.5, 0.45), location=(3.5, 2.4, 0.225), mat=cardboard)
kit.box("boxes_high", (0.5, 0.45, 0.4), location=(3.45, 2.42, 0.65), rotation=(0, 0, 8), mat=cardboard)
crate = kit.box("tv_crate", (0.5, 0.5, 0.45), location=(1.9, 0.4, 0.225), mat=wood)
group(crate, kit.box("tv", (0.4, 0.5, 0.38), location=(1.9, 0.4, 0.64), mat=dark))
kit.box("pizza_box", (0.4, 0.4, 0.05), location=(2.4, -1.4, 0.025), rotation=(0, 0, 25), mat=cardboard)
kit.box("space_heater", (0.25, 0.15, 0.35), location=(-1.4, -2.2, 0.175), mat=red_paint)

# A beam out from the north wall with a bare bulb hanging over the middle of the room.
kit.box("beam", (0.15, 3.9, 0.15), location=(0, 0.95, 2.72), mat=wood)
kit.box("bulb_cord", (0.01, 0.01, 0.45), location=(0, 0.2, 2.42), mat=dark)
kit.ball("bulb", 0.07, location=(0, 0.2, 2.15), mat=bulb_glow)

kit.export(model_name="garage", kind="environments", preview_colors="TEXTURE", export_image_format="JPEG")
