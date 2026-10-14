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

## Layout

- `blender/lib/kit.py` - shared helpers: primitives, materials, rigging, animation, export, previews
- `blender/characters/` - one script per character, named like the model it exports
- `previews/` - renders for reviewing a model without opening Godot

## Conventions

- **Style:** low-poly PS1 horror. Flat-shaded primitives (6-8 sided), flat colors, no textures.
  Emission is for things that should glow in the dark (eyes, sigils).
- **Units:** 1 Blender unit = 1 m = 1 Godot unit. A human-sized character is about 1.7 m tall.
- **Origin:** at the feet, centred, on the ground (z = 0 in Blender, y = 0 in Godot).
- **Facing:** characters face Blender -Y, which is Godot +Z (`Vector3.MODEL_FRONT`).
- **Rigging:** rigid skinning. Each part belongs to exactly one bone (`bone=` on the primitive), then
  `kit.bind()` joins them into one mesh. Bone names are lowercase with `_l`/`_r` sides.
- **Animation:** `kit.animate()` at 30 fps. Looping clips (default) arrive in Godot as the plain name with
  loop on. One-shots (`loop=False`) don't loop.
