"""The cultist: a gaunt, Silent Hill-style figure about 1.77 m tall, in layered, filthy rags.

A sculpted, sickly face half-wrapped in stained bandages, its mouth stitched shut and green eyes
glowing from sunken sockets, under a rounded hood pushed back off the face. A torn under-robe and
a rounded outer shroud with ragged hems, a capelet, ragged sleeves, hanging strips, and
bandage-wrapped forearms ending in long bony hands.

Exports assets/models/characters/cultist.glb with looping `idle` and `walk` clips (walk is in
place; game code moves the node). Run: bash tools/blender.sh art/blender/characters/cultist.py

Material names matter to the tests: clothes are `robe*`, `rag*` or `wrap*`; the face is `face*`
and bare skin `skin*`; the eyes are the only emissive material.
"""

import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import kit

kit.reset()
rng = random.Random(7)  # fixed seed: the same rags every time the script runs

robe = kit.material("robe", (0.32, 0.09, 0.06))
robe_cape = kit.material("robe_cape", (0.25, 0.075, 0.05))
robe_hood = kit.material("robe_hood", (0.29, 0.085, 0.06))
robe_under = kit.material("robe_under", (0.19, 0.12, 0.08))
rags = kit.material("rags", (0.36, 0.24, 0.16))
wrap_bandage = kit.material("wrap_bandage", (0.62, 0.57, 0.45))
wrap_face = kit.material("wrap_face", (0.55, 0.5, 0.38))
wrap_feet = kit.material("wrap_feet", (0.38, 0.31, 0.23))
face_skin = kit.material("face_skin", (0.68, 0.66, 0.56))
face_socket = kit.material("face_socket", (0.06, 0.03, 0.03))
face_mouth = kit.material("face_mouth", (0.13, 0.03, 0.03))
face_stitch = kit.material("face_stitch", (0.1, 0.08, 0.06))
skin = kit.material("skin", (0.6, 0.57, 0.48))
eyes = kit.material("eyes", (0.4, 1.0, 0.3), emission=(0.4, 1.0, 0.3))

HEAD = (0.0, -0.025, 1.56)  # centre of the skull; front is Blender -Y
ARM_X = 0.19


def folds(amount, waves, phase=0.0):
    """A deform for kit.lathe that ripples the cloth's radius into vertical folds."""
    def deform(v, angle, ring):
        scale = 1.0 + amount * math.sin(waves * angle + phase + ring * 0.7) + rng.uniform(-0.01, 0.01)
        return (v.x * scale, v.y * scale, v.z)
    return deform


def ragged(base, hem):
    """Wraps a deform so the bottom ring (the hem) is moved to height `hem(angle)`."""
    def deform(v, angle, ring):
        x, y, z = base(v, angle, ring)
        if ring == 0:
            z = hem(angle)
            jitter = 1.0 + rng.uniform(-0.05, 0.05)
            x, y = x * jitter, y * jitter
        return (x, y, z)
    return deform


def band(name, radius, height, location, rotation, mat, bone, segments=16):
    """A wrapped strip of cloth: a short, slightly bulging ring."""
    lip = height * 0.25
    profile = [(radius, 0.0), (radius + 0.004, lip), (radius + 0.004, height - lip), (radius, height)]
    return kit.lathe(name, profile, segments=segments, location=location, rotation=rotation, mat=mat, bone=bone)


def sculpt_face(v):
    """Turns an elongated ball into a gaunt face: narrow jaw, hollow cheeks, deep sockets, a nose."""
    x, y, z = v.x, v.y, v.z
    chin = max(0.0, -z / 0.12)
    x *= 1.0 - 0.35 * chin
    if y < 0:
        y *= 1.0 - 0.12 * chin
    if y < -0.01 and -0.065 < z < 0.012 and abs(x) > 0.025:  # hollow cheeks
        x *= 0.86
        y *= 0.9
    for side in (-1, 1):  # eye sockets
        d = math.hypot(x - side * 0.033, z - 0.02)
        if y < 0 and d < 0.03:
            y += 0.02 * (1.0 - d / 0.03)
    if y < 0 and 0.035 < z < 0.055:  # brow ridge
        y -= 0.006
    if y < 0 and abs(x) < 0.013 and -0.025 < z < 0.02:  # a thin nose
        y -= 0.012 * (1.0 - abs(x) / 0.013)
    if z > 0.06:  # a long skull
        z = 0.06 + (z - 0.06) * 1.1
    return (x, y, z)


parts = []

# --- Legs and feet: bony shins and wrapped feet, mostly hidden under the robes.
for side, bone in ((1, "leg_l"), (-1, "leg_r")):
    parts.append(kit.cone(f"shin_{bone}", radius=0.022, top_radius=0.028, depth=0.45, segments=8,
                          location=(side * 0.07, 0, 0.27), mat=skin, bone=bone))
    parts.append(kit.box(f"foot_{bone}", (0.07, 0.17, 0.06), location=(side * 0.07, -0.04, 0.03),
                         mat=wrap_feet, bone=bone))

# --- Under-robe: torn up high at the sides, dragging front and back.
parts.append(kit.lathe(
    "under_robe",
    [(0.205, 0.04), (0.2, 0.18), (0.185, 0.35), (0.17, 0.55), (0.16, 0.62), (0.155, 0.7), (0.15, 0.9), (0.15, 1.1)],
    segments=28, mat=robe_under, bone="spine",
    deform=ragged(folds(0.03, 6), lambda a: 0.04 + 0.1 * (0.5 + 0.5 * math.cos(2 * a)) + rng.uniform(0, 0.025)),
))

# --- Outer shroud: rounded, folded, its hem torn short in front and longer behind.
parts.append(kit.lathe(
    "shroud",
    [(0.225, 0.3), (0.21, 0.42), (0.195, 0.55), (0.185, 0.62), (0.175, 0.7), (0.165, 0.85), (0.16, 1.0),
     (0.17, 1.12), (0.18, 1.22)],
    segments=32, mat=robe, bone="spine",
    deform=ragged(folds(0.05, 9), lambda a: 0.3 - 0.1 * max(0.0, math.sin(a)) + rng.uniform(0, 0.07)),
))

# Strips torn from the shroud's hem, hanging down.
for i in range(14):
    a = 2 * math.pi * (i + rng.uniform(-0.3, 0.3)) / 14
    bottom = rng.uniform(0.17, 0.26)
    top = 0.36
    parts.append(kit.box(f"strip_{i}", (rng.uniform(0.03, 0.05), 0.008, top - bottom),
                         location=(0.215 * math.cos(a), 0.215 * math.sin(a), (top + bottom) / 2),
                         rotation=(rng.uniform(-6, 6), 8, math.degrees(a) + 90), mat=rags, bone="spine"))

# --- Capelet over the shoulders, ragged at the bottom.
parts.append(kit.lathe(
    "capelet",
    [(0.215, 1.18), (0.215, 1.26), (0.19, 1.35), (0.14, 1.42), (0.06, 1.46)],
    segments=30, mat=robe_cape, bone="chest",
    deform=ragged(folds(0.04, 7, 1.0), lambda a: 1.18 + rng.uniform(-0.03, 0.05)),
))

# --- Arms: ragged sleeves, bandaged forearms, long bony hands.
for side, bone in ((1, "arm_l"), (-1, "arm_r")):
    x = side * ARM_X
    parts.append(kit.lathe(
        f"sleeve_{bone}",
        [(0.058, 0.84), (0.062, 0.95), (0.06, 1.1), (0.055, 1.25), (0.06, 1.38)],
        segments=16, location=(x, 0, 0), mat=robe, bone=bone,
        deform=ragged(folds(0.04, 5), lambda a: 0.84 + rng.uniform(-0.02, 0.05)),
    ))
    for j in range(2):
        parts.append(kit.box(f"sleeve_strip_{bone}_{j}", (0.02, 0.006, rng.uniform(0.07, 0.11)),
                             location=(x + side * 0.03, (j - 0.5) * 0.06, 0.8),
                             rotation=(rng.uniform(-8, 8), 0, 90), mat=rags, bone=bone))
    parts.append(kit.cone(f"forearm_{bone}", radius=0.026, depth=0.18, segments=10,
                          location=(x, 0, 0.79), mat=skin, bone=bone))
    for j, z in enumerate((0.715, 0.75, 0.785, 0.82)):
        parts.append(band(f"bandage_{bone}_{j}", 0.03, 0.032, (x, 0, z),
                          (rng.uniform(-12, 12), rng.uniform(-12, 12), 0), wrap_bandage, bone))
    parts.append(kit.box(f"bandage_tail_{bone}", (0.006, 0.02, 0.09), location=(x + side * 0.032, 0.01, 0.68),
                         rotation=(0, side * 10, 0), mat=wrap_bandage, bone=bone))
    parts.append(kit.box(f"palm_{bone}", (0.022, 0.06, 0.07), location=(x, -0.005, 0.675), mat=skin, bone=bone))
    for j, y in enumerate((-0.026, -0.009, 0.008, 0.024)):
        length = (0.11, 0.125, 0.12, 0.1)[j]
        parts.append(kit.box(f"finger_{bone}_{j}", (0.011, 0.011, length),
                             location=(x + side * 0.004, y - 0.005, 0.64 - length / 2),
                             rotation=(rng.uniform(-6, 6), side * rng.uniform(4, 12), 0), mat=skin, bone=bone))
    parts.append(kit.box(f"thumb_{bone}", (0.011, 0.011, 0.07), location=(x - side * 0.008, -0.04, 0.64),
                         rotation=(-25, 0, 0), mat=skin, bone=bone))

# --- Head: neck, sculpted face, sockets, glowing eyes, stitched mouth, wrappings, hood.
hx, hy, hz = HEAD
parts.append(kit.cone("neck", radius=0.03, depth=0.12, segments=10, location=(0, -0.01, 1.44), mat=skin, bone="head"))
face = kit.ball("face", 0.1, subdivisions=3, location=HEAD, scale=(0.8, 0.85, 1.2), mat=face_skin, bone="head")
parts.append(kit.reshape(face, sculpt_face))
for side, name in ((1, "l"), (-1, "r")):
    parts.append(kit.ball(f"socket_{name}", 0.02, location=(side * 0.033, -0.093, 1.58), scale=(1, 0.5, 0.85),
                          mat=face_socket, bone="head"))
    parts.append(kit.ball(f"eye_{name}", 0.012, location=(side * 0.033, -0.098, 1.58), mat=eyes, bone="head"))
parts.append(kit.box("mouth", (0.05, 0.008, 0.004), location=(0, -0.094, 1.5), mat=face_mouth, bone="head"))
for j in range(5):
    parts.append(kit.box(f"stitch_{j}", (0.003, 0.006, 0.022), location=(-0.02 + 0.01 * j, -0.096, 1.5),
                         rotation=(0, rng.uniform(-15, 15), 0), mat=face_stitch, bone="head"))
# Bandages: one diagonally across the jaw and a cheek (leaving the eyes), one across the brow.
parts.append(band("face_wrap_jaw", 0.086, 0.03, (hx, hy, hz - 0.05), (0, 20, 0), wrap_face, "head", segments=28))
parts.append(band("face_wrap_brow", 0.076, 0.026, (hx, hy, hz + 0.058), (-10, -8, 0), wrap_face, "head", segments=28))
# Hood: a rounded shell open at the front (centred on -Y), pushed back to show the face.
parts.append(kit.lathe(
    "hood",
    [(0.125, -0.13), (0.14, -0.04), (0.14, 0.05), (0.12, 0.12), (0.085, 0.17), (0.04, 0.2), (0.008, 0.21)],
    segments=28, arc=260, arc_start=-40, location=(hx, hy + 0.015, hz), mat=robe_hood, bone="head",
    deform=lambda v, a, ring: (v.x * (1 + 0.05 * math.sin(7 * a)), v.y * (1 + 0.05 * math.sin(7 * a)),
                               v.z - (0.04 * max(0.0, math.sin(a)) if ring == 0 else 0.0)),
))

rig = kit.armature("cultist", [
    ("spine", (0, 0, 0.1), (0, 0, 1.05), None),
    ("chest", (0, 0, 1.05), (0, 0, 1.36), "spine"),
    ("head", (0, 0, 1.36), (0, 0, 1.75), "chest"),
    ("arm_l", (ARM_X, 0, 1.38), (ARM_X, 0, 0.7), "chest"),
    ("arm_r", (-ARM_X, 0, 1.38), (-ARM_X, 0, 0.7), "chest"),
    ("leg_l", (0.07, 0, 0.5), (0.07, 0, 0.03), None),
    ("leg_r", (-0.07, 0, 0.5), (-0.07, 0, 0.03), None),
])
model = kit.bind(rig, parts, "cultist")

# Idle: a slow, swaying breath with the head lolling (2 s).
kit.animate(rig, "idle", {
    0: {"spine": (0, 0, 0), "head": (0, 0, 0)},
    30: {"spine": (2, 2, 0), "chest": (3, 0, 0), "head": (-6, 0, 4), "arm_l": (0, 3, 0), "arm_r": (0, -3, 0)},
    60: {"spine": (0, 0, 0), "head": (0, 0, 0)},
})

# Walk: legs and arms swing in opposition, in place (1 s).
kit.animate(rig, "walk", {
    0: {"leg_l": (22, 0, 0), "leg_r": (-22, 0, 0), "arm_l": (-15, 0, 0), "arm_r": (15, 0, 0), "spine": (0, 3, 0)},
    15: {"leg_l": (-22, 0, 0), "leg_r": (22, 0, 0), "arm_l": (15, 0, 0), "arm_r": (-15, 0, 0), "spine": (0, -3, 0)},
    30: {"leg_l": (22, 0, 0), "leg_r": (-22, 0, 0), "arm_l": (-15, 0, 0), "arm_r": (15, 0, 0), "spine": (0, 3, 0)},
})

kit.export(model_name="cultist", kind="characters")
