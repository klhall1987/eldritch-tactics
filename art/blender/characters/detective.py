"""The detective: the player character, a realistic, PS2-era model about 1.9 m tall.

Harry Dresden meets Solid Snake: a tall, lean, broad-shouldered man in a worn brown leather duster,
open at the front over a ribbed charcoal turtleneck, with dark twill trousers and scuffed boots,
and a faintly glowing blue-white pentacle amulet on his chest. Smooth, subdivided shapes with
textures painted in code (no downloaded assets). The head is a plain placeholder for now; the
detailed face, eyes and hair come in ticket #25.

Exports assets/models/characters/detective.glb with looping `idle` and `walk` clips (walk is in
place; game code moves the node). Run: bash tools/blender.sh art/blender/characters/detective.py

Material names matter to the tests: the coat is `coat*`; `face*`, `skin*`, `eye*` and `hair*`
aren't clothes; the amulet is the only emissive material.
"""

import math
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import kit

kit.reset()
rng = np.random.default_rng(11)  # fixed seed: the same textures every build


# --- Textures, painted with numpy ------------------------------------------------------------------

def noise(size, cells):
    """Smooth value noise in 0..1 that tiles left-right and top-bottom (so it wraps round a body)."""
    grid = rng.random((cells + 1, cells + 1))
    grid[-1, :], grid[:, -1] = grid[0, :], grid[:, 0]
    x = np.linspace(0, cells, size, endpoint=False)
    i = x.astype(int)
    f = x - i
    f = f * f * (3 - 2 * f)
    rows = grid[i][:, i] * (1 - f)[None, :] + grid[i][:, i + 1] * f[None, :]
    rows_below = grid[i + 1][:, i] * (1 - f)[None, :] + grid[i + 1][:, i + 1] * f[None, :]
    return rows * (1 - f)[:, None] + rows_below * f[:, None]


def fbm(size, cells=4, octaves=5):
    """Layered noise: big blotches with finer grain on top, in 0..1."""
    total, weight, norm = np.zeros((size, size)), 1.0, 0.0
    for octave in range(octaves):
        total += weight * noise(size, cells * 2 ** octave)
        norm += weight
        weight *= 0.5
    return total / norm


def tint(base, shade):
    """Multiplies an (r, g, b) colour by a (h, w) shade map into an (h, w, 3) image."""
    return np.asarray(base)[None, None, :] * shade[..., None]


def leather_texture(size, base):
    """Worn leather: blotchy tone, fine grain, pale scuffs and a few dark creases."""
    grain = fbm(size, 4, 6)
    shade = 0.75 + 0.45 * grain
    scuffs = np.clip((fbm(size, 8, 4) - 0.62) * 6.0, 0.0, 1.0)  # pale worn patches
    creases = np.clip((0.04 - np.abs(noise(size, 6) - 0.5)) * 18.0, 0.0, 1.0)  # thin dark lines
    image = tint(base, shade * (1.0 - 0.35 * creases))
    return image * (1 - 0.5 * scuffs[..., None]) + np.array([0.55, 0.45, 0.35]) * 0.5 * scuffs[..., None]


def coat_texture(size):
    """The duster: brown leather with vertical panel seams and stitching."""
    image = leather_texture(size, (0.36, 0.22, 0.12))
    u = np.arange(size) / size
    seam = np.abs(((u * 8) % 1.0) - 0.5) < 0.012  # 8 panels around the coat
    image[:, seam] *= 0.55
    stitch = (np.abs(((u * 8) % 1.0) - 0.5) < 0.03) & ~seam
    stitch_rows = (np.arange(size) // 6) % 2 == 0
    image[np.ix_(stitch_rows, stitch)] = image[np.ix_(stitch_rows, stitch)] * 0.6 + 0.4 * np.array([0.6, 0.5, 0.35])
    return image


def knit_texture(size):
    """The turtleneck: charcoal wool in vertical ribs."""
    u = np.arange(size)[None, :] / size
    ribs = 0.85 + 0.15 * np.sin(u * 2 * math.pi * 48) ** 2
    return tint((0.14, 0.14, 0.15), ribs * (0.85 + 0.3 * fbm(size, 8, 4)))


def twill_texture(size):
    """The trousers: dark blue-grey twill, a fine diagonal weave."""
    y, x = np.mgrid[0:size, 0:size] / size
    weave = 0.88 + 0.12 * np.sin((x + y) * 2 * math.pi * 64)
    return tint((0.11, 0.12, 0.15), weave * (0.8 + 0.4 * fbm(size, 6, 4)))


coat = kit.textured_material("coat_leather", kit.image_texture("coat_leather", coat_texture(512)), roughness=0.6)
sweater = kit.textured_material("sweater_knit", kit.image_texture("sweater_knit", knit_texture(256)))
trousers = kit.textured_material("trousers_twill", kit.image_texture("trousers_twill", twill_texture(256)))
boots = kit.textured_material("boots_leather", kit.image_texture("boots_leather", leather_texture(256, (0.1, 0.07, 0.05))),
                              roughness=0.5)
skin = kit.material("skin", (0.78, 0.6, 0.5), roughness=0.7)
chain = kit.material("chain_silver", (0.6, 0.6, 0.62), roughness=0.3)
amulet = kit.material("amulet", (0.6, 0.85, 1.0), emission=(0.6, 0.85, 1.0))


# --- Shapes ------------------------------------------------------------------------------------------

def finish(obj, levels=1, v_scale=1.0, u_repeat=1.0):
    """Subdivides, UV-wraps and smooth-shades a part: the realistic-character treatment."""
    if levels:
        kit.subdivide(obj, levels)
    kit.uv_cylinder(obj, v_scale=v_scale, u_repeat=u_repeat)
    return kit.smooth(obj)


def oval(sx, sy):
    """A lathe deform that squashes a round profile into an oval cross-section (wide, not deep)."""
    return lambda v, angle, ring: (v.x * sx, v.y * sy, v.z)


ARM_X = 0.19
LEG_X = 0.095
parts = []

# Legs, hips and boots.
for side, bone in ((1, "leg_l"), (-1, "leg_r")):
    x = side * LEG_X
    parts.append(finish(kit.lathe(
        f"leg_{bone}", [(0.05, 0.2), (0.055, 0.3), (0.062, 0.45), (0.068, 0.6), (0.078, 0.75), (0.088, 0.88),
                        (0.092, 0.97)],
        segments=16, location=(x, 0, 0), mat=trousers, bone=bone), v_scale=2.0))
    parts.append(finish(kit.lathe(
        f"boot_shaft_{bone}", [(0.058, 0.05), (0.06, 0.12), (0.057, 0.2), (0.06, 0.25)],
        segments=16, location=(x, 0, 0), mat=boots, bone=bone), v_scale=3.0))
    parts.append(finish(kit.ball(f"boot_{bone}", 0.07, subdivisions=2, location=(x, -0.045, 0.063),
                                 scale=(0.85, 1.6, 0.9), mat=boots, bone=bone), levels=0, v_scale=4.0))
parts.append(finish(kit.lathe(
    "hips", [(0.15, 0.86), (0.165, 0.93), (0.165, 1.0), (0.15, 1.04)],
    segments=24, mat=trousers, bone="spine", deform=oval(1.0, 0.72)), v_scale=2.0, u_repeat=2.0))

# Turtleneck: torso up to a rolled collar under the chin.
parts.append(finish(kit.lathe(
    "sweater", [(0.14, 0.98), (0.155, 1.08), (0.165, 1.2), (0.185, 1.33), (0.19, 1.42), (0.17, 1.49),
                (0.12, 1.53), (0.068, 1.56), (0.066, 1.6)],
    segments=24, mat=sweater, bone="chest", deform=oval(1.0, 0.68)), v_scale=1.5, u_repeat=2.0))

# The duster: open at the front (a 34 degree gap centred on -Y), flaring below the waist to
# below the knee, with an upturned collar and sleeves.
parts.append(finish(kit.lathe(
    "duster", [(0.3, 0.45), (0.28, 0.6), (0.25, 0.8), (0.22, 0.96), (0.205, 1.06), (0.205, 1.16), (0.215, 1.3),
               (0.228, 1.42), (0.215, 1.5), (0.17, 1.55), (0.11, 1.575)],
    segments=32, arc=326, arc_start=287, mat=coat, bone="spine", deform=oval(1.0, 0.78))))
parts.append(finish(kit.lathe(
    "collar", [(0.115, 1.5), (0.125, 1.56), (0.13, 1.6)],
    segments=24, arc=280, arc_start=310, mat=coat, bone="chest", deform=oval(1.0, 0.85))))
for side, bone in ((1, "arm_l"), (-1, "arm_r")):
    x = side * ARM_X
    parts.append(finish(kit.lathe(
        f"sleeve_{bone}", [(0.046, 0.86), (0.05, 0.9), (0.052, 1.0), (0.054, 1.12), (0.058, 1.26), (0.06, 1.38),
                           (0.056, 1.48)],
        segments=16, location=(x, 0, 0), mat=coat, bone=bone)))
    # Hand: a palm and four fingers and a thumb, hanging relaxed.
    parts.append(finish(kit.ball(f"palm_{bone}", 0.045, subdivisions=2, location=(x, -0.005, 0.805),
                                 scale=(0.45, 0.85, 1.05), mat=skin, bone=bone), levels=0))
    for j, y in enumerate((-0.024, -0.008, 0.008, 0.023)):
        length = (0.07, 0.08, 0.075, 0.06)[j]
        parts.append(finish(kit.ball(f"finger_{bone}_{j}", length / 2, subdivisions=1,
                                     location=(x + side * 0.004, y - 0.004, 0.76 - length / 2 + 0.02),
                                     scale=(0.22, 0.24, 1.0), mat=skin, bone=bone)))
    parts.append(finish(kit.ball(f"thumb_{bone}", 0.03, subdivisions=1, location=(x - side * 0.012, -0.035, 0.79),
                                 rotation=(-25, 0, 0), scale=(0.3, 0.3, 1.0), mat=skin, bone=bone)))

# Neck and placeholder head (the detailed face comes in ticket #25). The neck tapers upward, so its
# narrowest point is just under the jaw.
parts.append(finish(kit.lathe(
    "neck", [(0.056, 1.55), (0.053, 1.6), (0.048, 1.645), (0.05, 1.68), (0.055, 1.72)],
    segments=16, mat=skin, bone="head")))
parts.append(finish(kit.ball("head", 0.12, subdivisions=3, location=(0, -0.01, 1.775), scale=(0.66, 0.78, 1.0),
                             mat=skin, bone="head"), levels=0))

# Amulet: a silver chain and a glowing pentacle disc on the chest.
parts.append(finish(kit.lathe(
    "chain", [(0.07, 0.0), (0.075, 0.01)], segments=24, location=(0, -0.04, 1.48), rotation=(-28, 0, 0),
    mat=chain, bone="chest")))
parts.append(kit.smooth(kit.ball("amulet", 0.03, subdivisions=2, location=(0, -0.14, 1.3), scale=(1, 0.3, 1),
                                 mat=amulet, bone="chest")))

rig = kit.armature("detective", [
    ("spine", (0, 0, 0.95), (0, 0, 1.3), None),
    ("chest", (0, 0, 1.3), (0, 0, 1.56), "spine"),
    ("head", (0, 0, 1.56), (0, 0, 1.9), "chest"),
    ("arm_l", (ARM_X, 0, 1.48), (ARM_X, 0, 0.8), "chest"),
    ("arm_r", (-ARM_X, 0, 1.48), (-ARM_X, 0, 0.8), "chest"),
    ("leg_l", (LEG_X, 0, 0.95), (LEG_X, 0, 0.08), None),
    ("leg_r", (-LEG_X, 0, 0.95), (-LEG_X, 0, 0.08), None),
])
model = kit.bind(rig, parts, "detective")

# Idle: a slow breath while he glances left, then right (3 s).
kit.animate(rig, "idle", {
    0: {"head": (0, 0, 0)},
    30: {"chest": (2, 0, 0), "head": (0, 0, 15), "arm_l": (0, 2, 0), "arm_r": (0, -2, 0)},
    60: {"head": (0, 0, 0)},
    75: {"chest": (2, 0, 0), "head": (-3, 0, -15), "arm_l": (0, 2, 0), "arm_r": (0, -2, 0)},
    90: {"head": (0, 0, 0)},
})

# Walk: a long-legged stride, arms swinging against the legs, in place (1 s).
kit.animate(rig, "walk", {
    0: {"leg_l": (18, 0, 0), "leg_r": (-18, 0, 0), "arm_l": (-18, 0, 0), "arm_r": (18, 0, 0), "spine": (0, 3, 0)},
    15: {"leg_l": (-18, 0, 0), "leg_r": (18, 0, 0), "arm_l": (18, 0, 0), "arm_r": (-18, 0, 0), "spine": (0, -3, 0)},
    30: {"leg_l": (18, 0, 0), "leg_r": (-18, 0, 0), "arm_l": (-18, 0, 0), "arm_r": (18, 0, 0), "spine": (0, 3, 0)},
})

kit.export(model_name="detective", kind="characters", preview_colors="TEXTURE")
