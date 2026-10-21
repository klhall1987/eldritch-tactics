extends GutTest
# Body types on one shared skeleton (ticket #150): the game knows its body types, every body type's model
# is built on one shared skeleton (the same bones, parents and rest pose), so clothing made for a body
# type binds to any character of that type by bone name. The player's Meshy character is the first,
# `male_average`.
#
# Interface these tests choose:
# - `res://scripts/body_types.gd` (load() it) has static functions: `names() -> Array` (the body type
#   names), `model(name) -> String` (that body type's model glb, or "") and `shared_model() -> String`
#   (the model whose skeleton is the shared skeleton).
# - A character model says its body type with `body_type` metadata on its root.
# - The shared skeleton's bones are SHARED_BONES, with their parents: since #158 the dressed character's
#   rig (22 limb and spine bones from `Hips` to `RightToeBase`, plus `head_end` and `headfront`). A rest
#   "matches" when its position is within 1 mm and its rotation within 1 degree of the shared
#   skeleton's, both in skeleton space.

const BODY_TYPES_PATH := "res://scripts/body_types.gd"
const CHARACTER_PATH := "res://assets/models/characters/character.glb"
# bone -> parent ("" for the root)
const SHARED_BONES := {
	"Hips": "",
	"Spine02": "Hips", "Spine01": "Spine02", "Spine": "Spine01", "neck": "Spine", "Head": "neck",
	"head_end": "Head", "headfront": "Head",
	"LeftShoulder": "Spine", "LeftArm": "LeftShoulder", "LeftForeArm": "LeftArm", "LeftHand": "LeftForeArm",
	"RightShoulder": "Spine", "RightArm": "RightShoulder", "RightForeArm": "RightArm", "RightHand": "RightForeArm",
	"LeftUpLeg": "Hips", "LeftLeg": "LeftUpLeg", "LeftFoot": "LeftLeg", "LeftToeBase": "LeftFoot",
	"RightUpLeg": "Hips", "RightLeg": "RightUpLeg", "RightFoot": "RightLeg", "RightToeBase": "RightFoot",
}


func _body_types() -> Script:
	var script = load(BODY_TYPES_PATH) if ResourceLoader.exists(BODY_TYPES_PATH) else null
	assert_not_null(script, "%s exists" % BODY_TYPES_PATH)
	return script


# Loads and instantiates a glb, or returns null (after failing the test).
func _load(path: String) -> Node3D:
	var packed = load(path) if path != "" and ResourceLoader.exists(path) else null
	assert_not_null(packed, "%s loads" % path)
	if packed == null:
		return null
	var node := (packed as PackedScene).instantiate() as Node3D
	add_child_autofree(node)
	return node


func _skeleton(node: Node) -> Skeleton3D:
	var skeletons := node.find_children("*", "Skeleton3D", true, false)
	assert_eq(skeletons.size(), 1, "%s has one Skeleton3D" % node.name)
	return skeletons[0] if not skeletons.is_empty() else null


# Given the game's body types, when they're listed, then there's `male_average`, whose model is
# assets/models/characters/character.glb.
func test_male_average_is_a_body_type():
	var types := _body_types()
	if types == null:
		return
	assert_has(types.names(), "male_average", "male_average is a body type")
	assert_eq(types.model("male_average"), CHARACTER_PATH, "male_average's model is character.glb")


# Given character.glb, when it's loaded, then it says it's the `male_average` body type.
func test_the_player_is_male_average():
	var character := _load(CHARACTER_PATH)
	if character == null:
		return
	assert_eq(str(character.get_meta("body_type", "")), "male_average", "character.glb is the male_average body type")


# Given every body type's model, when its skeleton is compared with the shared skeleton, then it has
# exactly the shared skeleton's bones (since #158 the dressed rig's 24: `Hips` to `RightToeBase`, plus
# `head_end` and `headfront`), each with the same parent, and each bone's rest is within 1 mm and 1
# degree of the shared skeleton's.
func test_every_body_type_is_on_the_shared_skeleton():
	var types := _body_types()
	if types == null:
		return
	var shared_node := _load(types.shared_model())
	if shared_node == null:
		return
	var shared := _skeleton(shared_node)
	if shared == null:
		return
	assert_gt(types.names().size(), 0, "there are body types")
	for type: String in types.names():
		var model := _load(types.model(type))
		if model == null:
			continue
		var skeleton := _skeleton(model)
		if skeleton == null:
			continue
		assert_eq(skeleton.get_bone_count(), SHARED_BONES.size(), "%s has exactly the shared skeleton's %d bones" % [type, SHARED_BONES.size()])
		for bone: String in SHARED_BONES:
			var b := skeleton.find_bone(bone)
			var s := shared.find_bone(bone)
			assert_true(b >= 0 and s >= 0, "%s and the shared skeleton have %s" % [type, bone])
			if b < 0 or s < 0:
				continue
			var parent := skeleton.get_bone_parent(b)
			var parent_name := skeleton.get_bone_name(parent) if parent >= 0 else ""
			assert_eq(parent_name, SHARED_BONES[bone], "%s's %s hangs from %s" % [type, bone, SHARED_BONES[bone]])
			var rest := skeleton.get_bone_global_rest(b)
			var shared_rest := shared.get_bone_global_rest(s)
			var moved := rest.origin.distance_to(shared_rest.origin)
			assert_lte(moved, 0.001, "%s's %s rests where the shared skeleton's does (%.4f m off)" % [type, bone, moved])
			var turned := rad_to_deg(rest.basis.get_rotation_quaternion().angle_to(shared_rest.basis.get_rotation_quaternion()))
			assert_lte(turned, 1.0, "%s's %s rests turned as the shared skeleton's does (%.2f degrees off)" % [type, bone, turned])


# Given art/README.md, when it's read, then it states the rule: every humanoid character model uses the
# shared skeleton and is one of the body types, and every clothing piece is made for one body type.
func test_the_rule_is_documented():
	var readme := FileAccess.get_file_as_string("res://art/README.md")
	assert_ne(readme, "", "art/README.md is there")
	var lower := readme.to_lower()
	for phrase in ["shared skeleton", "body type", "every clothing piece"]:
		assert_true(phrase in lower, "art/README.md states the rule (mentions \"%s\")" % phrase)
