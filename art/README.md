# Generated 3D art

Models are built from code in Blender, so every asset can be regenerated and reviewed as a diff.
Godot ignores this folder (`.gdignore`); only the exported `.glb` files in `assets/models/` are game assets.

## Run a model script

```bash
bash tools/blender.sh art/blender/characters/<model>.py
```

Needs Blender 5.2 (`BLENDER` is set in `.claude/settings.local.json`; otherwise `blender` must be on PATH).
A script writes `assets/models/<kind>/<model>.glb` and preview renders to `art/previews/<model>_{iso,front,side}.png`.
CI has no Blender, so commit the `.glb` and the previews together with the script that made them.
For a textured model, Godot extracts its textures next to the `.glb` (`<model>_<texture>.png` and
their `.import` files) the first time it imports it: commit those too.

## Layout

- `base/` - committed CC0 base meshes and textures for realistic characters, with their sources
- `blender/lib/kit.py` - shared helpers: primitives, materials, rigging, animation, export, previews
- `blender/characters/` - one script per character, named like the model it exports
- `previews/` - renders for reviewing a model without opening Godot

## Conventions

- **Style:** two styles, while the game moves towards realistic characters.
  - **Characters: realistic, Resident Evil (REmake)-style.** Built on committed CC0 assets in
    `art/base/` (see its README): a human base mesh, re-posed and fitted with clothes cut from the
    body itself (`kit.load_objects`, `kit.shell`), and photo textures with normal maps
    (`kit.load_image`, `kit.textured_material(..., normal_image=...)`). Faces and other unique
    detail can be painted in code with numpy (`kit.image_texture`, `kit.normal_map_from_height`).
    They're smoothly skinned with automatic weights (`kit.bind_weighted`), not rigidly. Roughly
    5,000-20,000 triangles a character, and more for `--combat` versions. New downloaded assets
    must be CC0 (or as free), approved by the owner, committed under `art/base/` and recorded in
    its README; scripts never download anything. Pass `preview_colors="TEXTURE"` to `kit.export()`
    so the previews show the textures. The cultist is built this way.
  - **The player character is the owner's Meshy model, used as Meshy delivered it** (#142; see
    `art/base/README.md`, "Meshy"): it isn't built from code or held to the triangle budget above.
    The glb is copied unchanged to `assets/models/characters/character.glb`, and
    `scripts/character_import.gd` fits it to the game at import (drops a stray mesh, folds the rig's
    0.01 scale into the skeleton, names the clips the game plays, splits his body into regions).
  - **The monster is built with the Creature Creator** (CC BY 4.0; see `art/base/README.md`):
    `art/blender/characters/monster.py` opens the owner's Creature Creator file (path in `CREATURE_CREATOR`),
    grows its parts with the tool's `Body Tool`, and exports only the finished, rigged monster.
  - **Props and environments: low-poly PS1 horror.** Flat-shaded primitives (6-8 sided), flat
    colors, no textures.
  - In both, emission is for things that should glow in the dark (eyes, sigils).
- **Body types and the shared skeleton** (#150-#154), as in Baldur's Gate 3: every humanoid
  character model uses the **shared skeleton** (the player's dressed Meshy rig, #158: 22 bones from
  `Hips` to `RightToeBase` plus `head_end` and `headfront`, with the same parents and rest pose) and is one of the
  **body types** in `scripts/body_types.gd` (the first is `male_average`, the player). Characters of
  one body type share the body and skeleton, and differ in head, hair and skin.
  - **Every clothing piece is made for one body type**, on its skeleton: its glTF extras name its
    `slot`, its `body_type` and the body regions it `covers` (`scripts/clothing_import.gd` lifts
    them). The Outfit only puts on a piece made for the character's body type, and hides the body
    regions it covers (`body_head`, `body_torso`, `body_hips`, `body_upper_arms`, `body_forearms`,
    `body_hands`, `body_thighs`, `body_calves`, `body_feet`) so skin can't show through.
- **Units:** 1 Blender unit = 1 m = 1 Godot unit. A human-sized character is about 1.7 m tall.
- **Origin:** at the feet, centred, on the ground (z = 0 in Blender, y = 0 in Godot).
- **Facing:** characters face Blender -Y, which is Godot +Z (`Vector3.MODEL_FRONT`).
- **Rigging:** low-poly models use rigid skinning: each part belongs to exactly one bone (`bone=` on the primitive), then
  `kit.bind()` joins them into one mesh. Bone names are lowercase with `_l`/`_r` sides.
- **Animation:** `kit.animate()` at 30 fps. Looping clips (default) arrive in Godot as the plain name with
  loop on. One-shots (`loop=False`) don't loop.
