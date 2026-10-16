extends GutTest
# The inventory screen (ticket #70): outside combat, I opens a screen listing what he wears in each
# slot and what he carries. Clicking a carried item wears it, clicking a worn one takes it off, and I
# again (or Escape) closes it. It doesn't open in combat, and while it's open he doesn't walk.
#
# Interface these tests choose:
# - The main scene has an `InventoryScreen` CanvasLayer, shown only while open.
# - Under it, `WornList` holds one Button per slot (top, bottom, feet), its text naming the slot and
#   the item worn there, or "empty"; `CarriedList` holds one Button per carried item, its text the
#   item's name. Clicking means the button's `pressed` signal.
# - The `inventory` input action is bound to I; Escape is `ui_cancel`.

const ACTIONS := ["move_up", "move_down", "move_left", "move_right"]
const TEE := "res://assets/models/clothes/tee_purple.glb"
const SWEATER := "res://assets/models/clothes/sweater_grey.glb"


func after_each():
	for action in ACTIONS + ["inventory", "ui_cancel"]:
		if InputMap.has_action(action):
			Input.action_release(action)


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


# [main, screen, outfit, controller], or [] (after failing).
func _scene() -> Array:
	assert_true(InputMap.has_action("inventory"), "the input map has an inventory action")
	if InputMap.has_action("inventory"):
		var keys := []
		for event in InputMap.action_get_events("inventory"):
			if event is InputEventKey:
				keys.append(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
		assert_has(keys, KEY_I, "inventory is bound to I")
	var main := await _main()
	if main == null:
		return []
	var screen := main.find_child("InventoryScreen", true, false)
	assert_true(screen is CanvasLayer, "the main scene has an InventoryScreen CanvasLayer")
	var outfit := main.find_child("Outfit", true, false)
	var controller := main.find_child("CombatController", true, false)
	if not screen is CanvasLayer or outfit == null or controller == null or not InputMap.has_action("inventory"):
		return []
	return [main, screen, outfit, controller]


func _press(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame


func _buttons(screen: Node, list_name: String) -> Array:
	var list := screen.find_child(list_name, true, false)
	assert_not_null(list, "the screen has %s" % list_name)
	return list.find_children("*", "Button", true, false) if list != null else []


func _texts(buttons: Array) -> Array:
	var texts := []
	for button: Button in buttons:
		texts.append(button.text)
	return texts


func _button_naming(buttons: Array, name: String) -> Button:
	for button: Button in buttons:
		if name in button.text:
			return button
	return null


# Given combat isn't running, when the inventory action (I) is pressed, then the inventory screen
# opens; when it's pressed again or ui_cancel (Escape) is pressed, it closes.
func test_i_opens_and_closes_it():
	var scene := await _scene()
	if scene.is_empty():
		return
	var screen: CanvasLayer = scene[1]
	assert_false(screen.visible, "the screen starts closed")
	await _press("inventory")
	assert_true(screen.visible, "I opens it")
	await _press("inventory")
	assert_false(screen.visible, "I again closes it")
	await _press("inventory")
	assert_true(screen.visible, "I opens it again")
	await _press("ui_cancel")
	assert_false(screen.visible, "Escape closes it")


# Given the screen is open, when it's read, then it lists each slot (top, bottom, feet) with the name
# of the item worn there (or "empty"), and every carried item by name.
func test_it_lists_worn_and_carried_clothes():
	var scene := await _scene()
	if scene.is_empty():
		return
	var screen: CanvasLayer = scene[1]
	var outfit: Node = scene[2]
	await _press("inventory")
	var worn := _texts(_buttons(screen, "WornList"))
	assert_eq(worn.size(), 3, "one entry per slot")
	for pair in [["top", "Purple T-shirt"], ["bottom", "Blue jeans"], ["feet", "Dark sneakers"]]:
		var found := false
		for text: String in worn:
			if pair[0] in text.to_lower() and pair[1] in text:
				found = true
		assert_true(found, "the %s slot shows %s (%s)" % [pair[0], pair[1], worn])
	assert_eq(_texts(_buttons(screen, "CarriedList")), ["Grey sweater"], "the carried list shows the sweater")
	outfit.take_off("feet")
	main_inventory(scene).inventory_changed.emit()
	await get_tree().process_frame
	worn = _texts(_buttons(screen, "WornList"))
	var empty := false
	for text: String in worn:
		if "feet" in text.to_lower() and "empty" in text.to_lower():
			empty = true
	assert_true(empty, "an empty slot reads \"empty\" (%s)" % [worn])


func main_inventory(scene: Array) -> Node:
	return scene[0].find_child("Inventory", true, false)


# Given the screen is open, when a carried item is clicked, then he wears it (through part 5's
# equip), and the screen updates to show it worn and the replaced item carried.
func test_clicking_a_carried_item_wears_it():
	var scene := await _scene()
	if scene.is_empty():
		return
	var screen: CanvasLayer = scene[1]
	var outfit: Node = scene[2]
	await _press("inventory")
	var sweater := _button_naming(_buttons(screen, "CarriedList"), "Grey sweater")
	assert_not_null(sweater, "the sweater is listed as carried")
	if sweater == null:
		return
	sweater.pressed.emit()
	await get_tree().process_frame
	assert_eq(outfit.worn("top"), SWEATER, "clicking the sweater puts it on")
	assert_not_null(_button_naming(_buttons(screen, "WornList"), "Grey sweater"), "the screen shows the sweater worn")
	assert_eq(_texts(_buttons(screen, "CarriedList")), ["Purple T-shirt"], "the screen shows the tee carried")


# Given the screen is open, when a worn item is clicked, then it's taken off into the inventory, and
# the screen updates.
func test_clicking_a_worn_item_takes_it_off():
	var scene := await _scene()
	if scene.is_empty():
		return
	var screen: CanvasLayer = scene[1]
	var outfit: Node = scene[2]
	await _press("inventory")
	var tee := _button_naming(_buttons(screen, "WornList"), "Purple T-shirt")
	assert_not_null(tee, "the tee is listed as worn")
	if tee == null:
		return
	tee.pressed.emit()
	await get_tree().process_frame
	assert_eq(outfit.worn("top"), "", "clicking the tee takes it off")
	var carried := _texts(_buttons(screen, "CarriedList"))
	carried.sort()
	assert_eq(carried, ["Grey sweater", "Purple T-shirt"], "the screen shows the tee carried")
	assert_null(_button_naming(_buttons(screen, "WornList"), "Purple T-shirt"), "the tee no longer shows as worn")


# Given combat is running, when I is pressed, then the screen doesn't open; and while the screen is
# open, the character doesn't walk from the movement keys or from clicks behind it.
func test_not_in_combat_and_he_stays_put_while_open():
	var scene := await _scene()
	if scene.is_empty():
		return
	var main: Node3D = scene[0]
	var screen: CanvasLayer = scene[1]
	var controller: Node = scene[3]
	var body := main.find_child("Player", true, false) as CharacterBody3D
	assert_not_null(body, "the main scene has the Player body")
	if body == null:
		return

	# While it's open, the movement keys and a click on the floor don't move him.
	await _press("inventory")
	assert_true(screen.visible, "the screen is open")
	var held_at := body.global_position
	for action in ["move_up", "move_right"]:
		Input.action_press(action)
	await wait_physics_frames(30)
	for action in ["move_up", "move_right"]:
		Input.action_release(action)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(50, 50)
	Input.parse_input_event(click)
	await wait_physics_frames(30)
	var moved := Vector2(body.global_position.x - held_at.x, body.global_position.z - held_at.z).length()
	assert_lt(moved, 0.01, "he doesn't walk while the screen is open (moved %.3f m)" % moved)
	await _press("inventory")
	assert_false(screen.visible, "the screen is closed")
	for action in ["move_up", "move_right"]:
		Input.action_press(action)
	await wait_physics_frames(30)
	for action in ["move_up", "move_right"]:
		Input.action_release(action)
	moved = Vector2(body.global_position.x - held_at.x, body.global_position.z - held_at.z).length()
	assert_gt(moved, 0.3, "once it's closed he walks again (%.2f m)" % moved)

	# In combat, I doesn't open it.
	controller.start_combat([body, main.find_child("Cultist", true, false)])
	await _press("inventory")
	assert_false(screen.visible, "in combat, I doesn't open the screen")
