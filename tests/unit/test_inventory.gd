extends GutTest
# An inventory of clothes the player can equip and unequip (ticket #69): he owns the tee, jeans,
# sneakers and sweater. Equipping a carried item puts it on (through #68's Outfit), and whatever it
# replaced goes back into the inventory; unequipping a worn item puts it back. Items he doesn't own,
# and any change while combat runs, are refused. Every change fires a signal.
#
# Interface these tests choose:
# - An `Inventory` node in the main scene: `items` (every item he owns), `carried()` (owned items not
#   being worn), `item_for(piece_path)` (his item for that clothing glb, or null), `equip(item) -> bool`,
#   `unequip(item) -> bool`, and an `inventory_changed` signal.
# - Items are resources (`scripts/clothing_item.gd`) with `display_name`, `piece` (the clothing glb's
#   path) and `slot`.

const TEE := "res://assets/models/clothes/tee_purple.glb"
const SWEATER := "res://assets/models/clothes/sweater_grey.glb"
const JEANS := "res://assets/models/clothes/jeans_blue.glb"
const SNEAKERS := "res://assets/models/clothes/sneakers_dark.glb"

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


func _pieces(items: Array) -> Array:
	var pieces := []
	for item in items:
		pieces.append(item.piece)
	pieces.sort()
	return pieces


func _worn(outfit: Node) -> Array:
	return [outfit.worn("top"), outfit.worn("bottom"), outfit.worn("feet")]


# Given the game starts, when the inventory is checked, then he owns the tee, jeans, sneakers and
# sweater: the first three worn, and the sweater held in the inventory, not worn.
func test_starts_owning_his_four_pieces():
	var scene := await _scene()
	if scene.is_empty():
		return
	var inventory: Node = scene[1]
	var outfit: Node = scene[2]
	var owned := [JEANS, SNEAKERS, SWEATER, TEE]
	owned.sort()
	assert_eq(_pieces(inventory.items), owned, "he owns the tee, jeans, sneakers and sweater")
	assert_eq(_pieces(inventory.carried()), [SWEATER], "only the sweater is carried, not worn")
	assert_eq(_worn(outfit), [TEE, JEANS, SNEAKERS], "he wears the tee, jeans and sneakers")
	for item in inventory.items:
		assert_true(item.display_name != "", "%s has a display name" % item.piece.get_file())


# Given an item in the inventory, when it's equipped, then he wears it (through part 4's slots), it
# leaves the inventory, and the piece it replaced (if any) goes back into the inventory.
func test_equipping_swaps_with_whats_worn():
	var scene := await _scene()
	if scene.is_empty():
		return
	var inventory: Node = scene[1]
	var outfit: Node = scene[2]
	var sweater: Resource = inventory.item_for(SWEATER)
	assert_not_null(sweater, "he has a sweater item")
	if sweater == null:
		return
	assert_true(inventory.equip(sweater), "the sweater is equipped")
	assert_eq(outfit.worn("top"), SWEATER, "he wears the sweater")
	assert_eq(_pieces(inventory.carried()), [TEE], "the sweater left the inventory and the tee went back into it")
	assert_eq(outfit.worn("bottom"), JEANS, "the jeans stay on")


# Given a worn item, when it's unequipped, then its slot is empty and the item is back in the
# inventory.
func test_unequipping_puts_it_back():
	var scene := await _scene()
	if scene.is_empty():
		return
	var inventory: Node = scene[1]
	var outfit: Node = scene[2]
	var jeans: Resource = inventory.item_for(JEANS)
	assert_not_null(jeans, "he has a jeans item")
	if jeans == null:
		return
	assert_true(inventory.unequip(jeans), "the jeans are unequipped")
	assert_eq(outfit.worn("bottom"), "", "the bottom slot is empty")
	var carried := [JEANS, SWEATER]
	assert_eq(_pieces(inventory.carried()), carried, "the jeans are back in the inventory")


# Given an item he doesn't own, or combat is running, when it's equipped or unequipped, then it's
# refused and neither his outfit nor the inventory changes.
func test_refused_when_not_owned_or_in_combat():
	var scene := await _scene()
	if scene.is_empty():
		return
	var main: Node3D = scene[0]
	var inventory: Node = scene[1]
	var outfit: Node = scene[2]
	var controller: Node = scene[3]
	var stranger: Resource = load("res://scripts/clothing_item.gd").new()
	stranger.display_name = "Someone else's sweater"
	stranger.piece = SWEATER
	stranger.slot = "top"
	var worn_before := _worn(outfit)
	var carried_before := _pieces(inventory.carried())
	assert_false(inventory.equip(stranger), "an item he doesn't own can't be equipped")
	assert_false(inventory.unequip(stranger), "an item he doesn't own can't be unequipped")
	assert_eq(_worn(outfit), worn_before, "his outfit doesn't change")
	assert_eq(_pieces(inventory.carried()), carried_before, "the inventory doesn't change")

	var body := main.find_child("Player", true, false) as Node3D
	var cultist := main.find_child("Cultist", true, false) as Node3D
	controller.start_combat([body, cultist])
	assert_true(controller.running, "combat is running")
	assert_false(inventory.equip(inventory.item_for(SWEATER)), "in combat, equipping is refused")
	assert_false(inventory.unequip(inventory.item_for(TEE)), "in combat, unequipping is refused")
	assert_eq(_worn(outfit), worn_before, "his outfit doesn't change in combat")
	assert_eq(_pieces(inventory.carried()), carried_before, "the inventory doesn't change in combat")
	assert_eq(_changes, 0, "nothing changed, so no inventory_changed")


# Given the inventory changes (equip or unequip), when it's handled, then an inventory-changed signal
# fires, so a screen can redraw.
func test_changes_fire_a_signal():
	var scene := await _scene()
	if scene.is_empty():
		return
	var inventory: Node = scene[1]
	inventory.equip(inventory.item_for(SWEATER))
	assert_eq(_changes, 1, "equipping fires inventory_changed once")
	inventory.unequip(inventory.item_for(JEANS))
	assert_eq(_changes, 2, "unequipping fires inventory_changed once")
