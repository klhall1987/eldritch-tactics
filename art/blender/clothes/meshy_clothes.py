"""The player character's clothes: the owner's Meshy pieces as Meshy delivered them (#145-#147),
made wearable. Each keeps Meshy's full mesh, texture and material; it's only scaled and placed over his
body in its rest pose, given his body's skin weights, and exported on his skeleton.

His body and skeleton come from the committed game model, assets/models/characters/character.glb (the
Meshy character, #142). Its armature carries a 0.01 scale, which is applied here, so a piece's skeleton
is in metres with Meshy's bone names, as Godot imports the character (scripts/character_import.gd folds
the same scale into his skeleton). The Meshy pieces are read from the owner's folder in the `MESHY`
environment variable (see art/base/README.md, "Meshy"); scripts never download anything.

A piece comes out of Meshy scaled to fit a 1.9 m box, centred on the origin. It's placed by a search
over one uniform scale and a position, from a first guess (its top at TOP, its middle over his
skeleton's), towards where its vertices lie close to his body without sinking into it.

Each piece exports alone (his skeleton and its skinned mesh) to assets/models/clothes/<piece>.glb, with
the slot it fills as `slot` (glTF extras on the mesh node; scripts/clothing_import.gd lifts it).

Run: bash tools/blender.sh art/blender/clothes/meshy_clothes.py [piece ...]
"""

import os
import pathlib
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import kit

CHARACTER = kit.ASSETS_DIR / "characters" / "character.glb"
SAMPLES = 4000  # vertices of a piece, and of his body, the placement search measures
# As the tests measure a fit (tests/unit/meshy_clothes.gd): a piece vertex is on his body within NEAR,
# at least FAR_SHARE of them should be, and a body vertex is in the area a piece covers if a piece
# vertex is within COVERS.
NEAR = 0.05
FAR_SHARE = 0.92
COVERS = 0.08
GAP = 0.004  # metres: the least a piece keeps clear of his skin
PUSH = 0.02  # metres: the most a vertex is pushed out to keep clear (agreed on #145)
TURN = 12  # degrees: the most a limb of a piece is bent each way to lie on his

# piece -> (Meshy file, slot, where its top goes: (Meshy joint, metres above it), where its bottom
# roughly goes: (joint, metres above it), the joint its middle sits over, the bones whose skin it covers
# (None: any), and the limbs bent onto his: one list of bones per pass, parents first)
ARMS = [["mixamorig:LeftArm", "mixamorig:RightArm"]]
PIECES = {
    "shirt_white": ("white_button_down_shi.glb", "top", ("Neck", 0.05), ("Hips", -0.17), "Spine2", None, ARMS),
}


def meshy_path(name):
    folder = os.environ.get("MESHY")
    if not folder:
        raise SystemExit("Set MESHY to the folder holding the owner's Meshy files (see art/base/README.md).")
    path = pathlib.Path(folder) / name
    if not path.exists():
        raise SystemExit(f"There's no {path}: see art/base/README.md for the Meshy files.")
    return path


def imported(path):
    """The objects a glTF import adds."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return [obj for obj in bpy.data.objects if obj not in before]


def character():
    """His armature and body from character.glb, at rest, with the armature's scale applied. Returns
    (rig, body, joints): joints maps a Meshy joint's name (without `mixamorig:`) to its world position."""
    objects = imported(CHARACTER)
    rig = next(obj for obj in objects if obj.type == "ARMATURE")
    body = next(obj for obj in objects if obj.type == "MESH" and obj.parent == rig)
    for obj in objects:
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
    joints = {b.name.removeprefix("mixamorig:"): rig.matrix_world @ b.head_local for b in rig.data.bones}
    # Meshy's `headfront` bone (a marker on his face) drives nothing a piece covers: a piece's skeleton
    # is just his `mixamorig:` bones.
    bpy.ops.object.mode_set(mode="EDIT")
    for eb in [eb for eb in rig.data.edit_bones if not eb.name.startswith("mixamorig:")]:
        rig.data.edit_bones.remove(eb)
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig, body, joints


def points(obj):
    return np.array([obj.matrix_world @ v.co for v in obj.data.vertices])


def kdtree(cloud):
    tree = KDTree(len(cloud))
    for i, p in enumerate(cloud):
        tree.insert(Vector(p), i)
    tree.balance()
    return tree


def place(piece, body, top, bottom, middle, bones):
    """Scales and moves `piece` (one uniform scale and a position) to fit loosely over his body: a first
    guess maps its height onto `top` to `bottom` and its middle onto `middle` (x, y), or with `top` None
    starts from where it is, then a pattern search improves it. A placement is scored as the tests measure a fit: the share of his body's
    vertices it covers (those following `bones`, with a piece vertex within COVERS) that poke out
    through it (the nearest piece vertex lies behind them), plus a penalty for each point that fewer
    than FAR_SHARE of its vertices are within NEAR of his body."""
    rng = np.random.default_rng(145)
    p = points(piece)
    lo, hi = p.min(axis=0), p.max(axis=0)
    sample = p[rng.choice(len(p), size=min(SAMPLES, len(p)), replace=False)]
    centre = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, hi[2]])
    groups = {g.index for g in body.vertex_groups if bones is None or g.name.removeprefix("mixamorig:") in bones}
    skin, normals = [], []
    for v in body.data.vertices:
        if bones is None or v.groups and max(v.groups, key=lambda g: g.weight).group in groups:
            skin.append(body.matrix_world @ v.co)
            normals.append((body.matrix_world.to_3x3() @ v.normal).normalized())
    pick = rng.choice(len(skin), size=min(SAMPLES, len(skin)), replace=False)
    skin, normals = [skin[i] for i in pick], [normals[i] for i in pick]
    body_tree = kdtree([body.matrix_world @ v.co for v in body.data.vertices])

    def placed(params):
        s, x, y, z = params
        return (sample - centre) * s + np.array([x, y, z])

    def score(params):
        cloth = placed(params)
        tree = kdtree(cloth)
        covered = poking = 0
        for b, n in zip(skin, normals):
            co, _, distance = tree.find(b)
            if distance <= COVERS:
                covered += 1
                if (co - b).dot(n) < 0.0:
                    poking += 1
        near = sum(1 for v in cloth if body_tree.find(Vector(v))[2] <= NEAR) / len(cloth)
        return poking / max(1, covered) + 4.0 * max(0.0, FAR_SHARE - near), poking / max(1, covered), near

    if top is None:  # from where it is now
        params = np.array([1.0, centre[0], centre[1], centre[2]])
    else:
        params = np.array([(top[2] - bottom[2]) / (hi[2] - lo[2]), middle[0], middle[1], top[2]])
    best = score(params)
    steps = np.array([0.04 * params[0], 0.02, 0.02, 0.02])
    while steps[1] > 0.001:
        improved = False
        for k in range(4):
            for sign in (1, -1):
                trial = params.copy()
                trial[k] += sign * steps[k]
                value = score(trial)
                if value[0] < best[0]:
                    params, best, improved = trial, value, True
        if not improved:
            steps /= 2
    s, x, y, z = params
    piece.data.transform(Matrix.Translation(Vector((x, y, z))) @ Matrix.Scale(s, 4)
                         @ Matrix.Translation(Vector(-centre)) @ piece.matrix_world)
    piece.matrix_world = Matrix.Identity(4)
    print(f"KIT: placed at scale {s:.4f}, ({x:.3f}, {y:.3f}, {z:.3f}): {best[1]:.1%} of his body pokes "
          f"through, {best[2]:.1%} within {NEAR} m")


def chain(rig, name):
    """`name` and every bone below it."""
    names = [name]
    for child in rig.data.bones[name].children_recursive:
        names.append(child.name)
    return names


def follows(obj, names):
    """Each vertex's total weight to `names` (0-1), and the vertices' world positions."""
    groups = {g.index for g in obj.vertex_groups if g.name in names}
    weight = np.array([min(1.0, sum(g.weight for g in v.groups if g.group in groups)) for v in obj.data.vertices])
    return weight, points(obj)


def bend(piece, body, rig, limbs):
    """Bends the piece's limbs onto his (agreed on #145): for each bone in `limbs`, the part of the piece
    that follows it is turned about the bone's joint, searching (up to TURN degrees each way, about the
    two axes across the bone) for the turn that leaves the least of his skin there poking out through it
    deeper than PUSH can fix. The search moves sampled points by how much they follow the bone; the turn
    found is then posed with his skeleton (skinned with his body's weights) and kept. The piece's mesh,
    topology and texture stay as they are. Its weights are copied from his body again after each pass."""
    rng = np.random.default_rng(145)
    for bones in limbs:
        for pb in rig.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()
        for name in bones:
            pb = rig.pose.bones[name]
            joint = np.array(rig.matrix_world @ pb.head)
            along = np.array((rig.matrix_world @ pb.tail - Vector(joint)).normalized())
            across = np.cross(along, [0.0, 1.0, 0.0])
            across /= np.linalg.norm(across)
            ahead = np.cross(along, across)
            names = chain(rig, name)
            weight, cloth = follows(piece, names)
            keep = np.nonzero(weight > 0.05)[0]
            if len(keep) == 0:
                continue
            keep = keep[rng.choice(len(keep), size=min(SAMPLES, len(keep)), replace=False)]
            cloth, weight = cloth[keep], weight[keep]
            skin_weight, skin = follows(body, names)
            skin_normals = np.array([body.matrix_world.to_3x3() @ v.normal for v in body.data.vertices])
            on = np.nonzero(skin_weight > 0.5)[0]
            on = on[rng.choice(len(on), size=min(SAMPLES, len(on)), replace=False)]
            skin, skin_normals = skin[on], skin_normals[on]

            def turned(a, b):
                turn = np.array(Matrix.Rotation(np.radians(a), 3, Vector(across))
                                @ Matrix.Rotation(np.radians(b), 3, Vector(ahead)))
                moved = (cloth - joint) @ turn.T + joint
                return cloth + (moved - cloth) * weight[:, None]

            def deep(a, b):
                tree = kdtree(turned(a, b))
                count = 0
                for p, n in zip(skin, skin_normals):
                    co, _, distance = tree.find(p)
                    if distance <= COVERS and (np.array(co) - p) @ n < -PUSH * 0.9:
                        count += 1
                return count

            best = (deep(0, 0), 0, 0)
            for a in range(-TURN, TURN + 1, 2):
                for b in range(-TURN, TURN + 1, 2):
                    best = min(best, (deep(a, b), a, b))
            _, a, b = best
            turn = (Matrix.Rotation(np.radians(a), 4, Vector(across)) @ Matrix.Rotation(np.radians(b), 4, Vector(ahead)))
            pb.matrix = Matrix.Translation(Vector(joint)) @ turn @ Matrix.Translation(Vector(-joint)) @ pb.matrix
            bpy.context.view_layer.update()
            print(f"KIT: bent {name} by ({a}, {b}) degrees: {best[0]} of {len(skin)} skin points too deep")
        piece.modifiers.new("Bend", "ARMATURE").object = rig
        kit.apply_modifiers(piece)
        for pb in rig.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()
        for group in list(piece.vertex_groups):
            piece.vertex_groups.remove(group)
        kit.transfer_weights(body, piece)


def keep_clear(piece, body):
    """Pushes the piece out wherever his body would show through it (agreed on #145): each vertex closer
    to his skin than GAP, or inside it, moves out along the skin's normal to GAP in front of it, by at
    most PUSH. Only vertices move; the mesh's topology and texture stay as they are."""
    tree = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    moved = 0
    for v in piece.data.vertices:
        hit, normal, _, _ = tree.find_nearest(v.co, PUSH + GAP)
        if hit is None:
            continue
        depth = GAP - (v.co - hit).dot(normal)
        if depth > 0.0:
            v.co += normal * min(depth, PUSH)
            moved += 1
    piece.data.update()
    print(f"KIT: pushed {moved} of {len(piece.data.vertices)} vertices clear of his body")


def build(name, file, slot, top, bottom, middle, bones, limbs):
    kit.reset()
    rig, body, joints = character()
    objects = imported(meshy_path(file))
    piece = next(obj for obj in objects if obj.type == "MESH")
    for obj in objects:
        if obj != piece:
            bpy.data.objects.remove(obj)
    piece.parent = None
    piece.name = piece.data.name = name
    place(piece, body, joints[top[0]] + Vector((0, 0, top[1])), joints[bottom[0]] + Vector((0, 0, bottom[1])),
          joints[middle], bones)
    kit.transfer_weights(body, piece)
    bend(piece, body, rig, limbs)
    keep_clear(piece, body)
    for group in list(piece.vertex_groups):
        piece.vertex_groups.remove(group)
    kit.transfer_weights(body, piece)
    piece.parent = rig
    piece.modifiers.new("Armature", "ARMATURE").object = rig
    piece["slot"] = slot
    for path in kit.render_previews(name, colors="TEXTURE"):  # on his body, to see the fit
        print(f"KIT: preview {path}")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (rig, piece):
        obj.select_set(True)
    out = kit.ASSETS_DIR / "clothes" / f"{name}.glb"
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_skins=True, export_animations=False, export_extras=True)
    print(f"KIT: exported {out} ({len(piece.data.polygons)} faces)")


only = kit.script_args()  # optionally, just the pieces named
for name, (file, slot, top, bottom, middle, bones, limbs) in PIECES.items():
    if not only or name in only:
        build(name, file, slot, top, bottom, middle, bones, limbs)
