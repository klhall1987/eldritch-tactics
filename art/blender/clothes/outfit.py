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
import numpy as np
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


FABRIC_SIZE = 1024  # the tee's and jeans' colour and normal maps, in pixels (#131)


def fabric_detail(piece, folder, image):
    """Makes the cloth read at the game's zoom: a height map of its fabric becomes a normal map, and is
    baked lightly into its colour (keeping the colour's average, so the dye stays as it is). The tee's
    height is its own MakeHuman bump map (folds and knit); the jeans' is a painted denim twill with
    some fading, since their source has no bump map. Other pieces are left as they are."""
    if piece not in ("tee_purple", "jeans_blue"):
        return image, None
    if image.size[0] > FABRIC_SIZE:  # plenty at the game's zoom, a quarter of the 2048 px source (#131)
        image.scale(FABRIC_SIZE, FABRIC_SIZE)
    w, h = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rng = np.random.default_rng(82)
    if piece == "tee_purple":
        bump = human.load(f"clothes/{folder}/T-shirt_basic-bump.png")
        if bump.size[:] != image.size[:]:
            bump.scale(w, h)
        bw, bh = bump.size
        height = np.array(bump.pixels[:], dtype=np.float32).reshape(bh, bw, 4)[..., :3].mean(axis=-1)
        height = (height - height.min()) / max(1e-6, np.ptp(height))
        knit = rng.random((h, w)) * 0.15
        height = np.clip(height * 0.85 + knit, 0.0, 1.0)
        shade = 1.0 + 0.55 * (height - height.mean())
    else:
        y, x = np.mgrid[0:h, 0:w].astype(np.float32)
        twill = 0.5 + 0.5 * np.sin((x + y) * (2 * np.pi / 6.0))  # fine diagonal ribs, as denim has
        weave = rng.random((h, w))
        fade = np.clip(np.sin(x / w * np.pi * 7) * np.sin(y / h * np.pi * 5), 0.0, 1.0)  # worn, lighter patches
        height = np.clip(0.6 * twill + 0.4 * weave, 0.0, 1.0)
        shade = 0.88 + 0.28 * (height - height.mean()) + 0.22 * fade
        shade = shade / shade.mean()
    pixels[..., :3] = np.clip(pixels[..., :3] * shade[..., None], 0.0, 1.0)
    detailed = bpy.data.images.new(f"{piece}_fabric", w, h, alpha=True)
    detailed.pixels.foreach_set(pixels.ravel())
    detailed.pack()
    normal = kit.normal_map_from_height(f"{piece}_normal", height, strength=3.0)
    normal.pack()
    return detailed, normal


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
    image, normal = fabric_detail(piece, folder, image)
    human.use(cloth, human.textured(piece, image, roughness=roughness, cutout=True,
                                    normal_image=normal, normal_strength=1.0))
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
