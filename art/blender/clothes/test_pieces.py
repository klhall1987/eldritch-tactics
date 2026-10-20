"""Placeholder clothing pieces for the body-type tests (#152-#154): plain tubes round the player
character's upper arms, made on his shared skeleton (#150) from the committed game model,
assets/models/characters/character.glb. They aren't given to the player; they let the tests put pieces
on and off before the real clothes are remade for his body type.

Each exports alone (his skeleton and its skinned mesh) to assets/models/clothes/<piece>.glb, with its
`slot`, `body_type` (unless it has none) and the body regions it `covers` as glTF extras on the mesh
node (scripts/clothing_import.gd lifts them).

Run: bash tools/blender.sh art/blender/clothes/test_pieces.py
"""

import math
import pathlib
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import kit

CHARACTER = kit.ASSETS_DIR / "characters" / "character.glb"
SEGMENTS = 12  # around each tube
RINGS = 4  # along it

# piece -> (slot, body type (None: names none), covers, where along the upper arm it runs (0 shoulder,
# 1 elbow), how far it stands off his skin in metres, colour)
PIECES = {
    "test_sleeves": ("top", "male_average", ["upper_arms"], (0.3, 0.7), 0.012, (0.5, 0.5, 0.55)),
    "test_arm_bands": ("bottom", "male_average", ["upper_arms"], (0.45, 0.55), 0.02, (0.6, 0.2, 0.2)),
    "test_sleeves_female": ("top", "female_average", ["upper_arms"], (0.3, 0.7), 0.012, (0.6, 0.4, 0.6)),
    "test_sleeves_untyped": ("top", None, ["upper_arms"], (0.3, 0.7), 0.012, (0.4, 0.6, 0.4)),
}


def character():
    """His armature and body, at rest, with the armature's 0.01 scale applied (bones in metres, as Godot
    imports him)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(CHARACTER))
    objects = [obj for obj in bpy.data.objects if obj not in before]
    rig = next(obj for obj in objects if obj.type == "ARMATURE")
    body = next(obj for obj in objects if obj.type == "MESH" and obj.parent == rig)
    for obj in list(bpy.data.objects):  # Meshy's stray Icosphere too, wherever the import put it
        if obj not in (rig, body):
            bpy.data.objects.remove(obj)
    rig.animation_data_clear()
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (rig, body):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.context.view_layer.update()
    return rig, body


def ends(rig, bone):
    """Where `bone` starts and where it reaches: its child's joint (glTF imports give bones only a
    guessed tail)."""
    b = rig.data.bones[bone]
    return rig.matrix_world @ b.head_local, rig.matrix_world @ b.children[0].head_local


def frame(rig, bone):
    """`bone`'s head, its length's direction and two directions across it."""
    head, tail = ends(rig, bone)
    along = (tail - head).normalized()
    side = along.cross(Vector((0, 1, 0))).normalized()
    return head, tail, along, side, along.cross(side)


def skin_reach(body, rig, bone):
    """His skin following `bone`, as (fraction along the bone, angle round it, distance from its line)."""
    head, tail, along, side, front = frame(rig, bone)
    group = body.vertex_groups[bone].index
    out = []
    for v in body.data.vertices:
        if v.groups and max(v.groups, key=lambda g: g.weight).group == group:
            p = body.matrix_world @ v.co - head
            across = p - along * p.dot(along)
            out.append((p.dot(along) / (tail - head).length, math.atan2(across.dot(front), across.dot(side)), across.length))
    return np.array(out)


def tube(bm, body, rig, bone, span, offset, group):
    """A tube round `bone` over `span` of its length, each vertex `offset` out from his skin in its
    direction (as far as his skin reaches there, near that ring), its vertices in `group`."""
    head, tail, along, side, front = frame(rig, bone)
    reach = skin_reach(body, rig, bone)
    deform = bm.verts.layers.deform.verify()
    rings = []
    for r in range(RINGS):
        t = span[0] + (span[1] - span[0]) * r / (RINGS - 1)
        centre = head + (tail - head) * t
        near = reach[np.abs(reach[:, 0] - t) < 0.08]
        ring = []
        for s in range(SEGMENTS):
            a = 2 * math.pi * s / SEGMENTS
            turn = np.abs((near[:, 1] - a + math.pi) % (2 * math.pi) - math.pi)
            there = near[turn < math.pi / SEGMENTS * 1.5, 2]
            radius = (float(there.max()) if len(there) else float(np.median(near[:, 2]))) + offset
            v = bm.verts.new(centre + (side * math.cos(a) + front * math.sin(a)) * radius)
            v[deform][group] = 1.0
            ring.append(v)
        rings.append(ring)
    for r in range(RINGS - 1):
        for s in range(SEGMENTS):
            n = (s + 1) % SEGMENTS
            bm.faces.new((rings[r][s], rings[r][n], rings[r + 1][n], rings[r + 1][s]))


def build(name, slot, body_type, covers, span, offset, colour):
    kit.reset()
    rig, body = character()
    piece = bpy.data.objects.new(name, bpy.data.meshes.new(name))
    bpy.context.scene.collection.objects.link(piece)
    bm = bmesh.new()
    for bone in ("mixamorig:LeftArm", "mixamorig:RightArm"):
        group = piece.vertex_groups.new(name=bone).index
        tube(bm, body, rig, bone, span, offset, group)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(piece.data)
    bm.free()
    piece.data.materials.append(kit.material(name, colour, roughness=0.8))
    kit.smooth(piece)
    piece.parent = rig
    piece.modifiers.new("Armature", "ARMATURE").object = rig
    piece["slot"] = slot
    if body_type is not None:
        piece["body_type"] = body_type
    piece["covers"] = covers
    bpy.data.objects.remove(body)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (rig, piece):
        obj.select_set(True)
    out = kit.ASSETS_DIR / "clothes" / f"{name}.glb"
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_skins=True, export_animations=False, export_extras=True)
    print(f"KIT: exported {out} ({len(piece.data.polygons)} faces)")


only = kit.script_args()  # optionally, just the pieces named
for name, spec in PIECES.items():
    if not only or name in only:
        build(name, *spec)
