"""The cultist: a hooded, robed figure about 1.7 m tall with glowing green eyes.

Exports assets/models/characters/cultist.glb with looping `idle` and `walk` clips (walk is in
place; game code moves the node). Run: bash tools/blender.sh art/blender/characters/cultist.py
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import kit

kit.reset()

robe = kit.material("robe", (0.25, 0.04, 0.04))
trim = kit.material("trim", (0.12, 0.02, 0.02))
shadow = kit.material("face", (0.02, 0.02, 0.02))
skin = kit.material("skin", (0.55, 0.5, 0.42))
eyes = kit.material("eyes", (0.4, 1.0, 0.3), emission=(0.4, 1.0, 0.3))

# Front is Blender -Y. Feet poke out under the hem; everything else hangs off the spine.
parts = [
    kit.box("foot_l", (0.1, 0.22, 0.08), location=(0.1, -0.22, 0.04), mat=trim, bone="leg_l"),
    kit.box("foot_r", (0.1, 0.22, 0.08), location=(-0.1, -0.22, 0.04), mat=trim, bone="leg_r"),
    kit.cone("robe", radius=0.34, top_radius=0.2, depth=1.0, location=(0, 0, 0.56), mat=robe, bone="spine"),
    kit.cone("hem", radius=0.36, top_radius=0.34, depth=0.06, location=(0, 0, 0.09), mat=trim, bone="spine"),
    kit.cone("chest", radius=0.2, top_radius=0.24, depth=0.3, location=(0, 0, 1.2), mat=robe, bone="chest"),
    kit.cone("arm_l", radius=0.07, top_radius=0.09, depth=0.55, location=(0.27, 0, 1.08), mat=robe, bone="arm_l"),
    kit.cone("arm_r", radius=0.07, top_radius=0.09, depth=0.55, location=(-0.27, 0, 1.08), mat=robe, bone="arm_r"),
    kit.ball("hand_l", 0.05, location=(0.27, 0, 0.77), mat=skin, bone="arm_l"),
    kit.ball("hand_r", 0.05, location=(-0.27, 0, 0.77), mat=skin, bone="arm_r"),
    kit.cone("hood", radius=0.19, top_radius=0.02, depth=0.4, location=(0, 0.04, 1.52), mat=robe, bone="head"),
    kit.ball("face", 0.11, location=(0, -0.04, 1.49), mat=shadow, bone="head"),
    kit.ball("eye_l", 0.025, location=(0.045, -0.14, 1.51), mat=eyes, bone="head"),
    kit.ball("eye_r", 0.025, location=(-0.045, -0.14, 1.51), mat=eyes, bone="head"),
]

rig = kit.armature("cultist", [
    ("spine", (0, 0, 0.1), (0, 0, 1.05), None),
    ("chest", (0, 0, 1.05), (0, 0, 1.36), "spine"),
    ("head", (0, 0, 1.36), (0, 0, 1.7), "chest"),
    ("arm_l", (0.27, 0, 1.34), (0.27, 0, 0.8), "chest"),
    ("arm_r", (-0.27, 0, 1.34), (-0.27, 0, 0.8), "chest"),
    ("leg_l", (0.1, 0, 0.9), (0.1, 0, 0.05), None),
    ("leg_r", (-0.1, 0, 0.9), (-0.1, 0, 0.05), None),
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
