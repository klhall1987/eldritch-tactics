"""The garage: a single-car garage someone is secretly living in, about 8 m by 6 m.

Two back walls (Godot -X and -Z) with a roll-up door; the camera sides are open, with knee-high
cutaway wall stubs. Each prop is its own object, so it arrives in Godot as a node named after
it. Exports assets/models/environments/garage.glb.
Run: bash tools/blender.sh art/blender/environments/garage.py
"""

import pathlib
import sys

import bpy

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import kit

kit.reset()

concrete = kit.material("concrete", (0.36, 0.35, 0.33))
stain = kit.material("oil_stain", (0.12, 0.11, 0.1))
block = kit.material("cinder_block", (0.46, 0.45, 0.42))
door_paint = kit.material("door_paint", (0.55, 0.56, 0.52))
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
kit.box("floor", (8.0, 6.0, 0.1), location=(0, 0, -0.05), mat=concrete)
kit.box("oil_stain", (1.4, 0.9, 0.004), location=(1.4, 1.2, 0.002), mat=stain)

# Back walls, full height up to near the camera sides, then a knee-high cutaway stub.
kit.box("wall_west", (0.2, 5.4, 2.8), location=(-3.9, 0.3, 1.4), mat=block)
kit.box("wall_west_stub", (0.2, 0.6, 1.0), location=(-3.9, -2.7, 0.5), mat=block)
kit.box("wall_north", (7.2, 0.2, 2.8), location=(-0.2, 2.9, 1.4), mat=block)
kit.box("wall_north_stub", (0.6, 0.2, 1.0), location=(3.7, 2.9, 0.5), mat=block)

# Roll-up door, closed, on the north wall: a panel with horizontal ribs and a handle.
door = kit.box("garage_door", (2.6, 0.06, 2.3), location=(1.6, 2.77, 1.15), mat=door_paint)
group(door, *[
    kit.box(f"door_rib_{i}", (2.6, 0.03, 0.04), location=(1.6, 2.73, 0.3 + 0.45 * i), mat=metal)
    for i in range(5)
], kit.box("door_handle", (0.3, 0.05, 0.05), location=(1.6, 2.71, 0.25), mat=dark))

# Workbench against the west wall: top, legs, pegboard with tools, a red toolbox and a vise.
bench = kit.box("workbench", (0.7, 2.0, 0.08), location=(-3.45, 0.6, 0.9), mat=wood)
group(bench, *[
    kit.box(f"bench_leg_{i}", (0.07, 0.07, 0.86), location=(-3.45 + dx, 0.6 + dy, 0.43), mat=wood)
    for i, (dx, dy) in enumerate([(-0.28, -0.92), (0.28, -0.92), (-0.28, 0.92), (0.28, 0.92)])
],
    kit.box("bench_shelf", (0.62, 1.9, 0.04), location=(-3.45, 0.6, 0.25), mat=wood),
    kit.box("pegboard", (0.03, 1.8, 0.8), location=(-3.78, 0.6, 1.5), mat=pegboard),
    kit.box("hammer_head", (0.03, 0.12, 0.04), location=(-3.75, 0.1, 1.6), mat=metal),
    kit.box("hammer_handle", (0.03, 0.03, 0.28), location=(-3.75, 0.1, 1.45), mat=wood),
    kit.box("wrench", (0.02, 0.03, 0.3), location=(-3.75, 0.35, 1.5), rotation=(20, 0, 0), mat=metal),
    kit.box("saw", (0.02, 0.45, 0.14), location=(-3.75, 0.95, 1.65), mat=metal),
    kit.box("toolbox", (0.35, 0.5, 0.22), location=(-3.5, 1.2, 1.05), mat=red_paint),
    kit.box("vise", (0.16, 0.2, 0.14), location=(-3.2, -0.1, 1.01), mat=metal),
    kit.cone("coffee_mug", radius=0.05, depth=0.1, location=(-3.3, 0.5, 0.99), mat=fridge_white),
)

# An old yellowed fridge in the north-west corner.
fridge = kit.box("fridge", (0.65, 0.65, 1.7), location=(-3.45, 2.4, 0.85), mat=fridge_white)
group(fridge, kit.box("fridge_handle", (0.04, 0.04, 0.5), location=(-3.1, 2.2, 1.2), mat=metal),
      kit.box("fridge_seam", (0.01, 0.66, 0.02), location=(-3.12, 2.4, 1.15), mat=dark))

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

kit.export(model_name="garage", kind="environments")
