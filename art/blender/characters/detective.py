"""The detective: the player character, a noir detective about 1.85 m tall in a fedora and a tan
duster, with dark hair and a faintly glowing blue-white amulet on the chest.

Exports assets/models/characters/detective.glb with looping `idle` and `walk` clips (walk is in
place; game code moves the node). Run: bash tools/blender.sh art/blender/characters/detective.py
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import kit

kit.reset()

# A light coat and a cool glow, so he reads clearly against the dark red, green-eyed cultists.
coat = kit.material("coat", (0.62, 0.48, 0.3))
lapel = kit.material("lapel", (0.42, 0.31, 0.18))
trousers = kit.material("trousers", (0.08, 0.08, 0.1))
shoes = kit.material("shoes", (0.04, 0.03, 0.03))
skin = kit.material("skin", (0.8, 0.7, 0.6))
hair = kit.material("hair", (0.04, 0.03, 0.03))
hat = kit.material("hat", (0.13, 0.12, 0.13))
band = kit.material("band", (0.03, 0.03, 0.03))
amulet = kit.material("amulet", (0.6, 0.85, 1.0), emission=(0.6, 0.85, 1.0))

# Front is Blender -Y. Legs and shoes hang off the leg bones; the duster's skirt off the spine.
parts = [
    kit.box("shoe_l", (0.1, 0.22, 0.08), location=(0.1, -0.04, 0.04), mat=shoes, bone="leg_l"),
    kit.box("shoe_r", (0.1, 0.22, 0.08), location=(-0.1, -0.04, 0.04), mat=shoes, bone="leg_r"),
    kit.cone("leg_l", radius=0.065, top_radius=0.08, depth=0.82, location=(0.1, 0, 0.49), mat=trousers, bone="leg_l"),
    kit.cone("leg_r", radius=0.065, top_radius=0.08, depth=0.82, location=(-0.1, 0, 0.49), mat=trousers, bone="leg_r"),
    kit.cone("skirt", radius=0.32, top_radius=0.21, depth=0.68, location=(0, 0, 0.64), mat=coat, bone="spine"),
    kit.cone("hem", radius=0.33, top_radius=0.32, depth=0.05, location=(0, 0, 0.3), mat=lapel, bone="spine"),
    kit.cone("torso", radius=0.2, top_radius=0.24, depth=0.5, location=(0, 0, 1.2), mat=coat, bone="chest"),
    kit.cone("collar", radius=0.17, top_radius=0.13, depth=0.1, location=(0, 0, 1.49), mat=lapel, bone="chest"),
    kit.box("lapels", (0.12, 0.04, 0.3), location=(0, -0.2, 1.3), mat=lapel, bone="chest"),
    kit.ball("amulet", 0.05, location=(0, -0.24, 1.22), scale=(1, 0.4, 1), mat=amulet, bone="chest"),
    kit.cone("arm_l", radius=0.07, top_radius=0.09, depth=0.52, location=(0.27, 0, 1.17), mat=coat, bone="arm_l"),
    kit.cone("arm_r", radius=0.07, top_radius=0.09, depth=0.52, location=(-0.27, 0, 1.17), mat=coat, bone="arm_r"),
    kit.ball("hand_l", 0.05, location=(0.27, 0, 0.87), mat=skin, bone="arm_l"),
    kit.ball("hand_r", 0.05, location=(-0.27, 0, 0.87), mat=skin, bone="arm_r"),
    kit.ball("head", 0.11, location=(0, -0.01, 1.61), mat=skin, bone="head"),
    kit.ball("hair", 0.125, location=(0, 0.03, 1.64), scale=(1.05, 1.0, 0.9), mat=hair, bone="head"),
    kit.box("eye_l", (0.025, 0.02, 0.02), location=(0.04, -0.11, 1.62), mat=hair, bone="head"),
    kit.box("eye_r", (0.025, 0.02, 0.02), location=(-0.04, -0.11, 1.62), mat=hair, bone="head"),
    kit.cone("brim", radius=0.24, top_radius=0.24, depth=0.02, segments=8, location=(0, 0, 1.71), mat=hat, bone="head"),
    kit.cone("crown", radius=0.12, top_radius=0.1, depth=0.15, segments=8, location=(0, 0, 1.79), mat=hat, bone="head"),
    kit.cone("hatband", radius=0.125, top_radius=0.12, depth=0.035, segments=8, location=(0, 0, 1.735), mat=band, bone="head"),
]

rig = kit.armature("detective", [
    ("spine", (0, 0, 0.9), (0, 0, 1.2), None),
    ("chest", (0, 0, 1.2), (0, 0, 1.5), "spine"),
    ("head", (0, 0, 1.5), (0, 0, 1.86), "chest"),
    ("arm_l", (0.27, 0, 1.43), (0.27, 0, 0.88), "chest"),
    ("arm_r", (-0.27, 0, 1.43), (-0.27, 0, 0.88), "chest"),
    ("leg_l", (0.1, 0, 0.9), (0.1, 0, 0.05), None),
    ("leg_r", (-0.1, 0, 0.9), (-0.1, 0, 0.05), None),
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

kit.export(model_name="detective", kind="characters")
