"""The player character's knife: a plain fixed-blade knife, about 0.25 m long, low-poly.

Its origin is the middle of its grip, with the blade pointing up Blender +Z (Godot +Y), its edge
towards -Y (Godot +Z), so a hand can hold it by its origin. Materials: `knife_blade` (light, metallic)
and `knife_handle` (dark).
Exports assets/models/props/knife.glb. Run: bash tools/blender.sh art/blender/props/knife.py
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import kit

kit.reset()

steel = kit.material("knife_blade", (0.78, 0.79, 0.8), roughness=0.3)
steel.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 1.0
handle = kit.material("knife_handle", (0.025, 0.02, 0.016), roughness=0.8)
guard = kit.material("knife_guard", (0.3, 0.3, 0.32), roughness=0.5)

GRIP = 0.1  # the handle runs from -GRIP/2 to +GRIP/2
BLADE = 0.145

kit.cone("handle", 0.012, GRIP, top_radius=0.012, segments=8, mat=handle)
kit.box("guard", (0.012, 0.04, 0.008), location=(0, 0, GRIP / 2 + 0.004), mat=guard)
kit.cone("pommel", 0.014, 0.01, top_radius=0.012, segments=8, location=(0, 0, -GRIP / 2 - 0.005), mat=guard)

# The blade: a flat bar with a straight spine (+Y), then a point where the edge (-Y) sweeps up to the
# spine.
STRAIGHT = 0.09
base = GRIP / 2 + 0.008
kit.box("blade", (0.004, 0.026, STRAIGHT), location=(0, 0, base + STRAIGHT / 2), mat=steel)
point = kit.box("blade_point", (0.004, 0.026, BLADE - STRAIGHT), location=(0, 0, base + STRAIGHT + (BLADE - STRAIGHT) / 2), mat=steel)


def to_point(v):
    if v.z > 0:  # the tip end: edge and sides meet at the spine
        v.y = 0.013
        v.x *= 0.3
    return v


kit.reshape(point, to_point)
kit.export("knife", "props")
