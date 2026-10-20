extends GutTest
# An inventory of clothes the player can equip and unequip (ticket #69). Since #141 the old MakeHuman
# clothes are gone, so he starts owning nothing. Items he doesn't own are still refused. Equipping,
# unequipping, refusing changes in combat and the change signal come back with the Meshy clothes.
#
# Interface these tests choose:
# - An `Inventory` node in the main scene: `items` (every item he owns), `carried()` (owned items not
#   being worn), `item_for(piece_path)` (his item for that clothing glb, or null), `equip(item) -> bool`,
#   `unequip(item) -> bool`, and an `inventory_changed` signal.
# - Items are resources (`scripts/clothing_item.gd`) with `display_name`, `piece` (the clothing glb's
#   path) and `slot`.

var _changes := 0


func before_each():
	_changes = 0


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


# [main, inventory, outfit, controller], or [] (after failing).
func _scene() -> Array:
	var main := await _main()
	if main == null:
		return []
	var inventory := main.find_child("Inventory", true, false)
	assert_not_null(inventory, "the main scene has an Inventory node")
	var outfit := main.find_child("Outfit", true, false)
	var controller := main.find_child("CombatController", true, false)
	if inventory == null or outfit == null or controller == null:
		return []
	for method in ["carried", "item_for", "equip", "unequip"]:
		assert_true(inventory.has_method(method), "Inventory has %s()" % method)
		if not inventory.has_method(method):
			return []
	assert_true(inventory.has_signal("inventory_changed"), "Inventory has an inventory_changed signal")
	if not inventory.has_signal("inventory_changed"):
		return []
	inventory.inventory_changed.connect(func(): _changes += 1)
	return [main, inventory, outfit, controller]


func _worn(outfit: Node) -> Array:
	return [outfit.worn("top"), outfit.worn("bottom"), outfit.worn("feet")]


# Given the game starts, when his inventory is checked, then he owns nothing (and carries nothing).
func test_starts_owning_nothing():
	var scene := await _scene()
	if scene.is_empty():
		return
	var inventory: Node = scene[1]
	assert_eq(inventory.items.size(), 0, "he owns nothing (owns %d items)" % inventory.items.size())
	assert_eq(inventory.carried(), [], "he carries nothing")


# Given an item he doesn't own, when it's equipped or unequipped, then it's refused and neither his
# outfit nor the inventory changes.
func test_refused_when_not_owned():
	var scene := await _scene()
	if scene.is_empty():
		return
	var inventory: Node = scene[1]
	var outfit: Node = scene[2]
	var stranger: Resource = load("res://scripts/clothing_item.gd").new()
	stranger.display_name = "Someone else's shirt"
	stranger.piece = "res://assets/models/clothes/someone_elses_shirt.glb"
	stranger.slot = "top"
	var worn_before := _worn(outfit)
	var carried_before: Array = inventory.carried()
	assert_false(inventory.equip(stranger), "an item he doesn't own can't be equipped")
	assert_false(inventory.unequip(stranger), "an item he doesn't own can't be unequipped")
	assert_eq(_worn(outfit), worn_before, "his outfit doesn't change")
	assert_eq(inventory.carried(), carried_before, "the inventory doesn't change")
	assert_eq(_changes, 0, "nothing changed, so no inventory_changed")
