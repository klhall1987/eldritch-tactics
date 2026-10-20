extends GutTest
# Changing the player character's clothes by slot (ticket #68). Since #141 the old MakeHuman clothes are
# gone, so the game starts with nothing worn over his own model. Putting pieces on, replacing them,
# taking them off and their moving with him come back with the Meshy clothes.
#
# Interface these tests choose:
# - An `Outfit` node in the main scene owns the slots (`top`, `bottom`, `feet`):
#   `wear(slot, piece_path) -> bool` (false, and nothing changes, if the piece doesn't fill that
#   slot), `take_off(slot)`, `worn(slot) -> String` (the piece's glb path, or "" when empty) and
#   `worn_meshes(slot) -> Array` (the MeshInstance3Ds drawn for it).
# - "No clothing mesh is drawn on him" (#141): the Character in the main scene has exactly the meshes
#   of character.glb on its own.

const CHARACTER_PATH := "res://assets/models/characters/character.glb"
const SLOTS := ["top", "bottom", "feet"]


# Instantiates the main scene into the tree and lets it settle, or returns null (after failing).
func _main() -> Node3D:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the main scene (%s) loads" % path)
	if packed == null:
		return null
	var main := packed.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	return main as Node3D


# The main scene's Outfit node and the Character, or [] (after failing).
func _scene() -> Array:
	var main := await _main()
	if main == null:
		return []
	var outfit := main.find_child("Outfit", true, false)
	assert_not_null(outfit, "the main scene has an Outfit node")
	var character := main.find_child("Character", true, false) as Node3D
	assert_not_null(character, "the main scene has the Character")
	if outfit == null or character == null:
		return []
	for method in ["wear", "take_off", "worn", "worn_meshes"]:
		assert_true(outfit.has_method(method), "Outfit has %s()" % method)
		if not outfit.has_method(method):
			return []
	return [main, outfit, character]


# Given the game starts, when his Outfit is checked, then every slot (top, bottom, feet) is empty and no
# clothing mesh is drawn on him.
func test_starts_with_nothing_worn():
	var scene := await _scene()
	if scene.is_empty():
		return
	var outfit: Node = scene[1]
	var character: Node3D = scene[2]
	for slot: String in SLOTS:
		assert_eq(outfit.worn(slot), "", "nothing is worn in %s" % slot)
		assert_eq(outfit.worn_meshes(slot), [], "nothing is drawn for %s" % slot)
	var own: Node3D = (load(CHARACTER_PATH) as PackedScene).instantiate()
	add_child_autofree(own)
	var expected := own.find_children("*", "MeshInstance3D", true, false).size()
	assert_gt(expected, 0, "character.glb has meshes of its own")
	var drawn := character.find_children("*", "MeshInstance3D", true, false).size()
	assert_eq(drawn, expected, "only his own meshes are drawn on him, no clothes (%d, his own %d)" % [drawn, expected])
