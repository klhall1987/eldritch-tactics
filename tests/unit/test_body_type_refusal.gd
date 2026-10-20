extends GutTest
# The Outfit refuses clothes made for another body type (ticket #154): a piece goes on a character only if
# it was made for that character's body type (#150's `body_type` on the model, #152's on the piece).
#
# Interface these tests choose:
# - The Outfit is the main scene's `Outfit` node (#68); its `wear(slot, piece_path)` returns whether
#   the piece went on. The Inventory (#69) is the main scene's `Inventory` node: `items`, `carried()`,
#   `equip(item) -> bool`, `inventory_changed`.
# - The pieces are placeholders, all `top` pieces covering `upper_arms`: test_sleeves.glb (made for
#   `male_average`, #152), test_sleeves_female.glb (made for `female_average`) and
#   test_sleeves_untyped.glb (naming no body type).
# - His shown regions are the `visible` of his `body_<region>` meshes (#151).

const SLEEVES := "res://assets/models/clothes/test_sleeves.glb"
const FEMALE := "res://assets/models/clothes/test_sleeves_female.glb"
const UNTYPED := "res://assets/models/clothes/test_sleeves_untyped.glb"
const SLOTS := ["top", "bottom", "feet"]
const REGIONS := ["head", "torso", "hips", "upper_arms", "forearms", "hands", "thighs", "calves", "feet"]

var _changes := 0


func before_each():
	_changes = 0


# [outfit, character, inventory], from the main scene put into the tree and let settle, or [].
func _scene() -> Array:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the main scene (%s) loads" % path)
	if packed == null:
		return []
	var main := packed.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	var outfit := main.find_child("Outfit", true, false)
	var character := main.find_child("Character", true, false) as Node3D
	var inventory := main.find_child("Inventory", true, false)
	assert_true(outfit != null and character != null and inventory != null, "the main scene has the Outfit, the Character and the Inventory")
	if outfit == null or character == null or inventory == null:
		return []
	inventory.inventory_changed.connect(func(): _changes += 1)
	return [outfit, character, inventory]


# What he wears and shows now: [worn per slot, shown per region].
func _state(outfit: Node, character: Node3D) -> Array:
	var worn := []
	for slot: String in SLOTS:
		worn.append(outfit.worn(slot))
	var shown := []
	for region: String in REGIONS:
		var mi := character.find_child("body_" + region, true, false) as MeshInstance3D
		shown.append(mi.visible if mi != null else null)
	return [worn, shown]


func _assert_refused(scene: Array, path: String, what: String) -> void:
	var outfit: Node = scene[0]
	var before := _state(outfit, scene[1])
	var carried_before: Array = scene[2].carried()
	assert_true(ResourceLoader.exists(path), "%s exists" % path)
	assert_false(outfit.wear("top", path), "%s is refused" % what)
	await wait_physics_frames(1)
	assert_eq(_state(outfit, scene[1]), before, "his outfit and shown regions don't change for %s" % what)
	assert_eq(scene[2].carried(), carried_before, "his inventory doesn't change for %s" % what)


# Given the player (male_average), when the test piece made for male_average is put on, then it's worn.
func test_a_piece_for_his_body_type_goes_on():
	var scene := await _scene()
	if scene.is_empty():
		return
	assert_true(scene[0].wear("top", SLEEVES), "the male_average sleeves go on")
	assert_eq(scene[0].worn("top"), SLEEVES, "he wears them")


# Given the player, when a piece made for another body type is put on, then wear returns false and his
# outfit, his shown body regions and his inventory don't change.
func test_a_piece_for_another_body_type_is_refused():
	var scene := await _scene()
	if scene.is_empty():
		return
	await _assert_refused(scene, FEMALE, "the female_average sleeves")


# Given the player, when a piece that names no body type is put on, then it's refused the same way.
func test_a_piece_with_no_body_type_is_refused():
	var scene := await _scene()
	if scene.is_empty():
		return
	await _assert_refused(scene, UNTYPED, "sleeves naming no body type")


# Given his inventory holds an item for a piece of another body type, when it's equipped, then it's
# refused and nothing changes.
func test_equipping_an_item_for_another_body_type_is_refused():
	var scene := await _scene()
	if scene.is_empty():
		return
	var outfit: Node = scene[0]
	var inventory: Node = scene[2]
	var item: Resource = load("res://scripts/clothing_item.gd").new()
	item.display_name = "Someone else's sleeves"
	item.piece = FEMALE
	item.slot = "top"
	inventory.items.append(item)
	var before := _state(outfit, scene[1])
	var carried_before: Array = inventory.carried()
	assert_has(carried_before, item, "he carries the item")
	assert_false(inventory.equip(item), "equipping the female_average sleeves is refused")
	await wait_physics_frames(1)
	assert_eq(_state(outfit, scene[1]), before, "his outfit and shown regions don't change")
	assert_eq(inventory.carried(), carried_before, "the item stays carried")
	assert_eq(_changes, 0, "nothing changed, so no inventory_changed")
