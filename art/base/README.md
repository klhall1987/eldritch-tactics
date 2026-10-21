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

## Creature Creator (the monster)

The monster (`art/blender/characters/monster.py` → `assets/models/characters/monster.glb`) is built
with **Creature Creator for Blender** by Joey Carlino (https://joeycarlino.itch.io/creature-creator-for-blender,
also https://joeycarlino.gumroad.com/l/creature), licensed **CC BY 4.0**
(https://creativecommons.org/licenses/by/4.0/). Changes: the monster's body, head, legs and mandibles
are grown with the Creature Creator's `Body Tool` along new curves, turned into meshes, decimated,
recoloured, given glowing eyes, and rigged and animated for this game.

The tool isn't committed here: it's the owner's `creature_creator_v1.blend`, which the build
script reads from the `CREATURE_CREATOR` path (set in `.claude/settings.local.json`).

## Meshy (the player character and his clothes)

The owner generated the player character and three clothing pieces with **Meshy**
(https://www.meshy.ai). They aren't CC0: they were made on a paid Meshy plan, so the owner owns them
("customers on a paid Meshy plan own their Customer Output", Meshy Terms of Use §3.2,
https://www.meshy.ai/terms-of-use). No credit is required. The terms also say Meshy's AI-generated
identifiers (watermarks, metadata) must not be removed (§2.4), and that Meshy-made assets must not be
used to train AI models that compete with Meshy (§2.6).

**The player character** (#157) is the owner's fully dressed Meshy character (white long-sleeve
button-down, blue jeans, white tennis shoes, short messy hair), made with Meshy's text-to-image,
image-to-3D, auto-rigging and animation library. Four files, copied unchanged into the game:

| Meshy file | In the game | What it is |
|---|---|---|
| `dressed_character_animations.glb` | `assets/models/characters/character.glb` (19 MB) | his 312,054-triangle mesh, one 2048 px colour texture, Meshy's 24-bone rig (`Hips` ... `RightToeBase`, `head_end`, `headfront`; no finger bones), and the clips Idle_03, Combat_Stance, Right_Hand_Sword_Slash and Hit_Reaction |
| `dressed_character_walking.glb` | `assets/models/characters/character_walk.glb` (30 MB, imported as-is) | the same rig with the walking clip from Meshy's rigging |
| `dressed_character_idle.glb` | `assets/models/characters/character_idle.glb` (30 MB, imported as-is) | the same rig with a relaxed idle, Idle_3 (library id 243; the main file's Idle_03 holds his hands up) |
| `dressed_character_guard.glb` | `assets/models/characters/character_guard.glb` (30 MB, imported as-is) | the same rig with a raised guard, Block1 (library id 138; the main file's Combat_Stance crouches with his hands low), played as `combat_idle` |

`scripts/character_import.gd` fits them to the game at import. (Before #157 he was
`Meshy_AI_rigged_male_character_All_Animations.glb`, the undressed character, #142.)

**The clothes** aren't in the game yet. They're the owner's files, in the folder the `MESHY` path
points to (set in `.claude/settings.local.json`):

| File | What it is |
|---|---|
| `white_button_down_shi.glb` | a white button-down shirt with rolled sleeves (unrigged, about 535,000 triangles) |
| `lighter_blue_jeans.glb` | light blue jeans (unrigged, about 560,000 triangles) |
| `black_trim_tennis_sho.glb` | a pair of light grey tennis shoes with black trim (unrigged, about 1.3 million triangles) |

They come out of Meshy scaled to fit a 1.9 m box, not to his body.
