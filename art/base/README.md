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

## Creature Creator (the monster)

The monster (`art/blender/characters/monster.py` → `assets/models/characters/monster.glb`) is built
with **Creature Creator for Blender** by Joey Carlino (https://joeycarlino.itch.io/creature-creator-for-blender,
also https://joeycarlino.gumroad.com/l/creature), licensed **CC BY 4.0**
(https://creativecommons.org/licenses/by/4.0/). Changes: the monster's body, head, legs and mandibles
are grown with the Creature Creator's `Body Tool` along new curves, turned into meshes, decimated,
recoloured, given glowing eyes, and rigged and animated for this game.

Like MPFB, the tool isn't committed here: it's the owner's `creature_creator_v1.blend`, which the build
script reads from the `CREATURE_CREATOR` path (set in `.claude/settings.local.json`).

## Meshy (the player character and his clothes)

The owner generated the player character's new body and three clothing pieces with **Meshy**
(https://www.meshy.ai). They aren't CC0: they were made on a paid Meshy plan, so the owner owns them
("customers on a paid Meshy plan own their Customer Output", Meshy Terms of Use §3.2,
https://www.meshy.ai/terms-of-use). No credit is required. The terms also say Meshy's AI-generated
identifiers (watermarks, metadata) must not be removed (§2.4), and that Meshy-made assets must not be
used to train AI models that compete with Meshy (§2.6).

Like the Creature Creator, they aren't committed here (they're over 100 MB in all): they're the
owner's files, in the folder the `MESHY` path points to (set in `.claude/settings.local.json`):

| File | What it is |
|---|---|
| `Meshy_AI_rigged_male_character_biped/Meshy_AI_rigged_male_character_biped_Meshy_Merged_Animations.fbx` | his body (about 224,000 triangles, 1.75 m), on Meshy's 23-bone Mixamo-style rig with four clips (Walking, Running, air_squat, Block1), and its colour, normal, roughness and metallic maps (`..._texture_0*.png`, 4096 px) next to it |
| `white_button_down_shi.glb` | a white button-down shirt with rolled sleeves (unrigged, about 535,000 triangles) |
| `lighter_blue_jeans.glb` | light blue jeans (unrigged, about 560,000 triangles) |
| `black_trim_tennis_sho.glb` | a pair of light grey tennis shoes with black trim (unrigged, about 1.3 million triangles) |

The clothes come out of Meshy scaled to fit a 1.9 m box, not to his body.
