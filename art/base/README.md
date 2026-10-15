# Base assets for realistic characters

Committed, freely licensed source assets that the character scripts in `art/blender/characters/`
build on. They're downloaded once, by hand, with the owner's approval, and committed here. Scripts
load these files, so builds are reproducible and need no network.

Every file here must be CC0 (or similarly free for any use). Record its source and licence below.

## Human base mesh

| File | Source | Licence |
|---|---|---|
| `human_male_realistic.blend` | `GEO-body_male_realistic` and its two eyes (`GEO-body_male_realistic.eye.L/.R`), extracted unchanged from Blender Studio's **Human Base Meshes** bundle v1.4.1 (`human_base_meshes_bundle.blend`), https://www.blender.org/download/demo-files/ (asset bundles). The bundle zip came from https://mirror.blender.org/demo/asset-bundles/human-base-meshes/human-base-meshes-bundle-v1.4.1.zip | CC0 1.0 |

The body keeps its multires sculpt. `kit.load_male_body()` (used by `cultist.py`) and `detective.py` apply it to the base mesh at build time. Both characters are built on this one body.

## Textures (`textures/`)

All from Poly Haven (https://polyhaven.com), CC0 1.0. Each is a colour (albedo/diffuse) map plus its
OpenGL normal map:

| Files | Poly Haven asset | Used for |
|---|---|---|
| `brown_leather_albedo_2k.jpg`, `brown_leather_nor_gl_2k.jpg` | [brown_leather](https://polyhaven.com/a/brown_leather) (2k) | the detective's duster |
| `knitted_fleece_diff_1k.jpg`, `knitted_fleece_nor_gl_1k.jpg` | [knitted_fleece](https://polyhaven.com/a/knitted_fleece) (1k) | the detective's turtleneck; the cultist's under-robe and bandage wraps (recoloured, with grime and blood painted on) |
| `denim_fabric_diff_1k.jpg`, `denim_fabric_nor_gl_1k.jpg` | [denim_fabric](https://polyhaven.com/a/denim_fabric) (1k) | the detective's trousers (tinted dark); the cultist's robe, hood and rags (recoloured, with grime and blood painted on) |
| `fabric_leather_02_diff_1k.jpg`, `fabric_leather_02_nor_gl_1k.jpg` | [fabric_leather_02](https://polyhaven.com/a/fabric_leather_02) (1k) | the detective's boots (tinted dark) |
