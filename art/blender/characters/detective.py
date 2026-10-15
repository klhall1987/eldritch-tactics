"""The detective: the player character, a realistic, PS2-era model about 1.9 m tall.

Harry Dresden meets Solid Snake: a tall, lean, broad-shouldered man in a worn brown leather duster,
open at the front over a ribbed charcoal turtleneck, with dark twill trousers and scuffed boots,
and a faintly glowing blue-white pentacle amulet on his chest. Smooth, subdivided shapes with
textures painted in code (no downloaded assets). A sculpted, PS2-era face with a painted texture
(stubble, heavy brows, sunken eyes), separate grey-blue eyes, and dark hair swept back.

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
skin = kit.material("skin", (0.62, 0.45, 0.36), roughness=0.7)  # matches the face texture
chain = kit.material("chain_silver", (0.6, 0.6, 0.62), roughness=0.3)
amulet = kit.material("amulet", (0.6, 0.85, 1.0), emission=(0.6, 0.85, 1.0))


# --- The face ---------------------------------------------------------------------------------------
# The head is an ellipsoid (radius HEAD_R, squashed by HEAD_SCALE) sculpted into a face. Its UVs wrap
# around it (kit.uv_cylinder): u = 0.25 is straight ahead, and v runs 0..1 from the bottom of the head
# to the top, so the face texture below is painted in (angle from the front, height) coordinates.

HEAD = (0.0, -0.01, 1.775)
HEAD_R = 0.12
HEAD_SCALE = (0.66, 0.78, 1.0)
EYE_X, EYE_Z = 0.032, 0.018  # in the head's own space (z up from its centre)


def bump(d, width):
    """1 at d = 0, falling smoothly to 0 at |d| = width."""
    t = np.clip(1.0 - np.abs(d) / width, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def sculpt_head(v):
    """Turns the ellipsoid into a rugged man's head: square jaw, cheekbones, brow, sockets, nose."""
    x, y, z = v.x, v.y, v.z
    front = y < 0
    if z < -0.02:  # a square jaw, narrowing only near the chin
        t = (-0.02 - z) / 0.1
        x *= 1.0 - 0.2 * t * t
    if not front and z < -0.03:  # the back of the head tucks in towards the neck
        y *= 0.86
    if front:
        y *= 0.93  # a flatter face
        for side in (-1, 1):  # eye sockets
            d = math.hypot(x - side * EYE_X, z - EYE_Z)
            y += 0.009 * float(bump(d, 0.024))
            # cheekbones, just below and outside the eyes
            y -= 0.004 * float(bump(math.hypot(x - side * 0.05, z + 0.005), 0.025))
        y -= 0.005 * float(bump(z - 0.042, 0.012)) * float(bump(x, 0.06))  # brow ridge
        nose = float(bump(x - 0.002 * (z + 0.03) / 0.05, 0.013)) * float(bump(z + 0.008, 0.032))
        y -= 0.02 * nose * (0.6 + 0.4 * float(np.clip((0.02 - z) / 0.05, 0, 1)))  # longest at the tip
        y += 0.003 * float(bump(z + 0.055, 0.006)) * float(bump(x, 0.024))  # mouth line
        y -= 0.007 * float(bump(z + 0.098, 0.02)) * float(bump(x, 0.03))  # chin
    return (x, y, z)


def face_texture(size):
    """Skin, stubble, brows, lips and shading, painted in the head's (angle, height) UV space."""
    v, u = (np.mgrid[0:size, 0:size] + 0.5) / size
    angle = (u - 0.25) * 2 * math.pi  # 0 = straight ahead, + = his left
    z = (v - 0.5) * 2 * HEAD_R  # height in the head's own space
    across = np.sin(angle) * HEAD_R * HEAD_SCALE[0]  # roughly x on the face
    facing = np.cos(angle) > 0.2  # the front of the head

    shade = 0.92 + 0.16 * fbm(size, 8, 5)
    image = tint((0.76, 0.57, 0.46), shade)
    # Warmer, redder cheeks and nose.
    flush = (bump(np.hypot(np.abs(across) - 0.045, z + 0.01), 0.03) + bump(np.hypot(across, z + 0.01), 0.018)) * facing
    image = image * (1 - 0.25 * flush[..., None]) + np.array([0.8, 0.45, 0.4]) * 0.25 * flush[..., None]
    # Shadows: deep eye sockets, under the cheekbones, along the jaw.
    sockets = bump(np.hypot(np.abs(across) - EYE_X, (z - EYE_Z) * 1.4), 0.02) * facing
    hollows = bump(np.hypot(np.abs(across) - 0.05, z + 0.035), 0.022) * facing
    image *= (1 - 0.35 * sockets - 0.12 * hollows)[..., None]
    # A day or two of dark stubble on the jaw, chin and upper lip, as fine speckle.
    speckle = rng.random((size, size)) < 0.45
    stubble_area = np.clip((-0.045 - z) / 0.03, 0, 1) * (np.abs(np.sin(angle)) < 0.95)
    stubble_area = np.maximum(stubble_area, bump(z + 0.045, 0.008) * bump(across, 0.025) * facing)
    lips = bump(z + 0.056, 0.0055) * bump(across, 0.02) * facing
    stubble = stubble_area * (1 - lips) * (0.55 + 0.45 * speckle)
    image = image * (1 - 0.6 * stubble[..., None]) + np.array([0.18, 0.14, 0.12]) * 0.6 * stubble[..., None]
    # Thin, pale-red lips.
    image = image * (1 - 0.5 * lips[..., None]) + np.array([0.6, 0.36, 0.33]) * 0.5 * lips[..., None]
    # Heavy, dark eyebrows, angled slightly down towards the nose.
    for side in (-1, 1):
        brow_z = 0.041 + 0.006 * (np.abs(across) - EYE_X) / 0.02
        brow = bump(z - brow_z, 0.0055) * bump(across - side * (EYE_X + 0.002), 0.022) * facing
        brow *= 0.7 + 0.3 * speckle
        image = image * (1 - 0.85 * brow[..., None]) + np.array([0.1, 0.07, 0.05]) * 0.85 * brow[..., None]
    # Faint crow's feet at the outer corners of the eyes.
    crows = bump(np.abs(across) - 0.055, 0.008) * bump(z - EYE_Z, 0.012) * (np.sin(z * 900) > 0.6) * facing
    image *= (1 - 0.2 * crows)[..., None]
    return image


face_skin = kit.textured_material("face_skin", kit.image_texture("face_skin", face_texture(512)), roughness=0.65)
eye_white = kit.material("eye_white", (0.86, 0.83, 0.78), roughness=0.2)
eye_iris = kit.material("eye_iris", (0.36, 0.46, 0.56), roughness=0.2)
eye_pupil = kit.material("eye_pupil", (0.02, 0.02, 0.02), roughness=0.2)
face_lid = kit.material("face_lid", (0.56, 0.4, 0.32), roughness=0.7)  # eyelids, a touch darker than the skin
hair = kit.material("hair_dark", (0.06, 0.045, 0.035), roughness=0.85)


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
                (0.12, 1.53), (0.07, 1.57), (0.068, 1.635)],
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

# Neck and head. The neck tapers upward, so its narrowest point is just under the jaw.
parts.append(finish(kit.lathe(
    "neck", [(0.062, 1.55), (0.06, 1.6), (0.056, 1.645), (0.058, 1.68), (0.06, 1.72)],
    segments=16, mat=skin, bone="head")))
hx, hy, hz = HEAD
head = kit.ball("head", HEAD_R, subdivisions=4, location=HEAD, scale=HEAD_SCALE, mat=face_skin, bone="head")
kit.reshape(head, sculpt_head)
kit.uv_cylinder(head, v_scale=1 / (2 * HEAD_R), v_offset=0.5)
parts.append(kit.smooth(head))
for side, name in ((1, "l"), (-1, "r")):
    # Ears, and eyes set into the sockets: a white, a grey-blue iris and a pupil.
    parts.append(finish(kit.ball(f"ear_{name}", 0.03, subdivisions=1, location=(side * 0.077, hy + 0.008, hz),
                                 scale=(0.3, 0.6, 1.0), mat=skin, bone="head"), levels=0))
    ex, ey, ez = hx + side * EYE_X, hy - 0.068, hz + EYE_Z
    parts.append(kit.smooth(kit.ball(f"eye_{name}", 0.012, subdivisions=2, location=(ex, ey, ez), mat=eye_white,
                                     bone="head")))
    parts.append(kit.smooth(kit.ball(f"iris_{name}", 0.0055, subdivisions=1, location=(ex, ey - 0.0105, ez),
                                     scale=(1, 0.35, 1), mat=eye_iris, bone="head")))
    parts.append(kit.smooth(kit.ball(f"pupil_{name}", 0.0025, subdivisions=1, location=(ex, ey - 0.0122, ez),
                                     scale=(1, 0.3, 1), mat=eye_pupil, bone="head")))
    # Heavy upper and lower lids over the eyeball, leaving a narrow, hard-eyed gap.
    parts.append(kit.smooth(kit.ball(f"lid_upper_{name}", 0.0135, subdivisions=2, location=(ex, ey - 0.001, ez + 0.0102),
                                     scale=(1.15, 1.0, 0.62), mat=face_lid, bone="head")))
    parts.append(kit.smooth(kit.ball(f"lid_lower_{name}", 0.0135, subdivisions=2, location=(ex, ey - 0.001, ez - 0.0089),
                                     scale=(1.1, 0.95, 0.45), mat=face_lid, bone="head")))


def shape_hair(v):
    """A hair cap: tucked inside the head over the face and below the ears, swept back over the
    crown, and hanging to the collar behind."""
    x, y, z = v.x, v.y, v.z
    if (y < -0.03 and z < 0.05) or (z < -0.015 and y < 0.03):
        return (x * 0.85, y * 0.85, z * 0.85)  # hidden inside the head
    if y >= 0.03 and z < -0.04:  # collar-length at the back
        return (x * 1.04, y * 1.06, z)
    return (x * 1.02, y, z)


cap = kit.ball("hair_cap", HEAD_R + 0.003, subdivisions=3, location=(hx, hy + 0.004, hz + 0.006),
               scale=HEAD_SCALE, mat=hair, bone="head")
parts.append(finish(kit.reshape(cap, shape_hair), levels=0))
# Chunky locks: swept back over the top, and messy strands round the sides and back.
for i in range(6):
    x = (i - 2.5) * 0.02
    parts.append(finish(kit.ball(f"lock_top_{i}", 0.026, subdivisions=1, location=(hx + x, hy + 0.012, hz + 0.104),
                                 rotation=(-6, 0, rng.uniform(-5, 5) - x * 120), scale=(0.45, 1.9, 0.28),
                                 mat=hair, bone="head"), levels=0))
for i in range(10):
    a = math.radians(15 + i * 15)  # round the back, from his left to his right
    z = hz + rng.uniform(-0.02, 0.05)
    r = 0.084
    parts.append(finish(kit.ball(f"lock_back_{i}", 0.026, subdivisions=1,
                                 location=(hx + r * math.cos(a) * 0.9, hy + r * math.sin(a), z),
                                 rotation=(rng.uniform(8, 18), 0, math.degrees(a) - 90), scale=(0.4, 0.32, 1.7),
                                 mat=hair, bone="head"), levels=0))

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
