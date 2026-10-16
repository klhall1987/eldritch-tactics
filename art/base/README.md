# Base assets for realistic characters

Committed, freely licensed source assets that the character scripts in `art/blender/characters/`
build on. They're downloaded once, by hand, with the owner's approval, and committed here. Scripts
load these files, so builds are reproducible and need no network.

Every file here must be CC0 (or similarly free for any use). Record its source and licence below.

## Human base mesh

| File | Source | Licence |
|---|---|---|
| `human_male_realistic.blend` | `GEO-body_male_realistic` and its two eyes (`GEO-body_male_realistic.eye.L/.R`), extracted unchanged from Blender Studio's **Human Base Meshes** bundle v1.4.1 (`human_base_meshes_bundle.blend`), https://www.blender.org/download/demo-files/ (asset bundles). The bundle zip came from https://mirror.blender.org/demo/asset-bundles/human-base-meshes/human-base-meshes-bundle-v1.4.1.zip | CC0 1.0 |

The body keeps its multires sculpt. `kit.load_male_body()` (used by `cultist.py`) applies it to the base mesh at build time.

## Textures (`textures/`)

All from Poly Haven (https://polyhaven.com), CC0 1.0. Each is a colour (albedo/diffuse) map plus its
OpenGL normal map:

| Files | Poly Haven asset | Used for |
|---|---|---|
| `knitted_fleece_diff_1k.jpg`, `knitted_fleece_nor_gl_1k.jpg` | [knitted_fleece](https://polyhaven.com/a/knitted_fleece) (1k) | the cultist's under-robe and bandage wraps (recoloured, with grime and blood painted on) |
| `denim_fabric_diff_1k.jpg`, `denim_fabric_nor_gl_1k.jpg` | [denim_fabric](https://polyhaven.com/a/denim_fabric) (1k) | the cultist's robe, hood and rags (recoloured, with grime and blood painted on) |

## MakeHuman assets (`makehuman/`)

The player character (`art/blender/characters/character.py`) is built with **MPFB 2**, the MakeHuman
plugin for Blender (https://extensions.blender.org/add-ons/mpfb/, GPLv3 code; it must be installed in
Blender, and brings the MakeHuman base mesh, shape targets and skeletons). The assets fitted to him
are copied unchanged (minus thumbnails) from the **MakeHuman system assets** pack,
`makehuman_system_assets_cc0.zip`, downloaded from
https://files2.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip
(see https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html). Every
file is CC0 1.0, as each asset file's header states and https://static.makehumancommunity.org/about/license.html
confirms for MakeHuman's core assets.

| Folder | Asset | Used for |
|---|---|---|
| `proxymeshes/male1591/` | male1591 low-poly body (proxy) | his body |
| `skins/young_caucasian_male/` | young caucasian male skin | his skin texture |
| `eyes/low-poly/`, `eyes/materials/brown*` | low-poly eyes, brown eye material | his eyes |
| `eyebrows/eyebrow001/` | eyebrow001 | his eyebrows |
| `eyelashes/eyelashes01/` | eyelashes01 | his eyelashes |
| `hair/short02/` | short02 hair | his hair (darkened at build time) |

### Clothes (`makehuman/clothes/`)

The player character's clothes (`art/blender/clothes/outfit.py`), copied unchanged (minus thumbnails)
from MakeHuman asset packs. Every one is CC0 1.0, as its `.mhclo` header states.

| Folder | Pack (download) | Used for |
|---|---|---|
| `toigo_basic_tucked_t-shirt/` | Shirts 01, https://files2.makehumancommunity.org/asset_packs/shirts01/shirts01_cc0.zip | the purple tee (dyed) |
| `toigo_fisherman_sweater/` | Shirts 01 (as above) | the grey sweater (dyed) |
| `toigo_wool_pants/` | Pants 01, https://files2.makehumancommunity.org/asset_packs/pants01/pants01_cc0.zip | the blue jeans (dyed denim blue, legs tapered) |
| `shoes02/` | MakeHuman system assets (as above) | the dark sneakers (darkened) |
