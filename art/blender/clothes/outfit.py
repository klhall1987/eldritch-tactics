"""The player character's clothes: separate pieces he can put on and take off, each fitted to his body
and skinned to his skeleton, from CC0 MakeHuman clothes (art/base/makehuman/clothes).

Every piece is built on the same MPFB body, skeleton and arms-down rest pose as the character
(art/blender/lib/human.py): MPFB fits the garment to the body and weights it to the skeleton, the
pose is baked in, the cloth is pushed a few millimetres clear wherever the low-poly body would poke
through it, and its texture is dyed. Each exports alone (its skeleton and skinned mesh) to
assets/models/clothes/<piece>.glb, with the slot it fills as `slot` (glTF extras on the mesh node).

Run: bash tools/blender.sh art/blender/clothes/outfit.py
"""

import pathlib
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import human
import kit

GAP = 0.005  # metres: the least the cloth keeps clear of the body

# piece -> (MakeHuman clothes folder, slot, dye colour (sRGB) or None to darken, roughness, the most
# it may stand off the body in metres (None: as made))
PIECES = {
    "tee_purple": ("toigo_basic_tucked_t-shirt", "top", (0.28, 0.14, 0.38), 0.8, None),
    "sweater_grey": ("toigo_fisherman_sweater", "top", (0.42, 0.42, 0.42), 0.9, None),
    "jeans_blue": ("toigo_wool_pants", "bottom", (0.16, 0.26, 0.42), 0.85, 0.025),  # straight-leg trousers, tapered
    "sneakers_dark": ("shoes02", "feet", None, 0.6, None),
}


def mhclo(folder):
    return next((human.MAKEHUMAN / "clothes" / folder).glob("*.mhclo")).relative_to(human.MAKEHUMAN)


def diffuse(folder):
    """The garment's colour map: the image its .mhmat names as diffuseTexture."""
    mhmat = next((human.MAKEHUMAN / "clothes" / folder).glob("*.mhmat"))
    for line in mhmat.read_text(errors="replace").splitlines():
        if line.startswith("diffuseTexture"):
            return pathlib.Path("clothes") / folder / pathlib.Path(line.split(None, 1)[1].strip()).name
    raise SystemExit(f"{mhmat} names no diffuseTexture")


def keep_clear(cloth, body, fit=None):
    """Moves the cloth out wherever it's closer to the body than GAP (or inside it), along the body's
    surface normal, so in the rest pose the body doesn't show through the cloth. With `fit`, cloth
    standing further off the body than that is drawn in to it (a closer cut)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    body_tree = BVHTree.FromObject(body, depsgraph)
    for v in cloth.data.vertices:
        hit, normal, _, _ = body_tree.find_nearest(v.co)
        if hit is None:
            continue
        if (v.co - hit).dot(normal) < GAP:
            v.co = hit + normal * GAP
        elif fit is not None and (v.co - hit).length > fit:
            v.co = hit + (v.co - hit).normalized() * fit
    # Where the low-poly body bulges between cloth vertices, a body vertex can still show through:
    # the cloth lies just behind it and not in front of it. Lift the cloth around it.
    body_mesh = body.evaluated_get(depsgraph).data
    for _ in range(8):
        cloth.data.update()
        cloth_tree = BVHTree.FromObject(cloth, bpy.context.evaluated_depsgraph_get())
        poking = []
        for bv in body_mesh.vertices:
            p, n = body.matrix_world @ bv.co, (body.matrix_world.to_3x3() @ bv.normal).normalized()
            if cloth_tree.ray_cast(p, n, 0.04)[0] is None and cloth_tree.ray_cast(p, -n, 0.02)[0] is not None:
                poking.append((p, n))
        if not poking:
            break
        for p, n in poking:
            for v in cloth.data.vertices:
                if (v.co - p).length < 0.04:
                    depth = (v.co - p).dot(n)
                    if depth < 2 * GAP:
                        v.co += n * (2 * GAP - depth)


def build(piece, folder, slot, dye, roughness, fit):
    kit.reset()
    human.start()
    basemesh, rig = human.create()
    body = human.body(basemesh)
    cloth = human.asset(basemesh, str(mhclo(folder)), "Clothes")
    bpy.data.objects.remove(basemesh)
    cloth.name = cloth.data.name = piece
    human.arms_down(rig, (body, cloth))
    for mod in list(cloth.modifiers):  # skinned to the rig again by arms_down; nothing else
        if mod.type != "ARMATURE":
            cloth.modifiers.remove(mod)
    bpy.context.view_layer.update()
    bm = bmesh.new()  # triangulated now, so the clearing below sees the same surface the game will
    bm.from_mesh(cloth.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(cloth.data)
    bm.free()
    keep_clear(cloth, body, fit)
    image = human.load(str(diffuse(folder)))
    image = human.darkened(image, 0.2) if dye is None else human.recoloured(image, dye, piece)
    human.use(cloth, human.textured(piece, image, roughness=roughness, cutout=True))
    kit.smooth(cloth)
    cloth["slot"] = slot
    bpy.data.objects.remove(body)
    out = kit.ASSETS_DIR / "clothes" / f"{piece}.glb"
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", export_yup=True, export_apply=True,
                              export_animations=False, export_extras=True)
    print(f"KIT: exported {out} ({sum(len(p.vertices) - 2 for p in cloth.data.polygons)} triangles)")
    for path in kit.render_previews(piece, colors="TEXTURE"):
        print(f"KIT: preview {path}")


only = kit.script_args()  # optionally, just the pieces named
for piece, (folder, slot, dye, roughness, fit) in PIECES.items():
    if not only or piece in only:
        build(piece, folder, slot, dye, roughness, fit)
