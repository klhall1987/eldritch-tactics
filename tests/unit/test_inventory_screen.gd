extends GutTest
# The inventory screen (ticket #70): outside combat, I opens a screen listing what he wears in each
# slot and what he carries. Clicking a carried item wears it, clicking a worn one takes it off, and I
# again (or Escape) closes it. It doesn't open in combat, and while it's open he doesn't walk. Since
# #141 he owns no clothes, so it lists empty slots; clicking items comes back with the Meshy clothes.
#
# Interface these tests choose:
# - The main scene has an `InventoryScreen` CanvasLayer, shown only while open.
# - Under it, `WornList` holds one Button per slot (top, bottom, feet), its text naming the slot and
#   the item worn there, or "empty"; `CarriedList` holds one Button per carried item, its text the
#   item's name. Clicking means the button's `pressed` signal.
# - The `inventory` input action is bound to I; Escape is `ui_cancel`.

const ACTIONS := ["move_up", "move_down", "move_left", "move_right"]


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


# Given the game starts and the screen is opened (I), when it's read, then it lists the three slots
# (top, bottom, feet) as empty and nothing carried (#141: he owns no clothes until the Meshy ones).
func test_it_lists_empty_slots_and_nothing_carried():
	var scene := await _scene()
	if scene.is_empty():
		return
	var screen: CanvasLayer = scene[1]
	await _press("inventory")
	assert_true(screen.visible, "the screen is open")
	var worn := _texts(_buttons(screen, "WornList"))
	assert_eq(worn.size(), 3, "one entry per slot (%s)" % [worn])
	for slot in ["top", "bottom", "feet"]:
		var empty := false
		for text: String in worn:
			if slot in text.to_lower() and "empty" in text.to_lower():
				empty = true
		assert_true(empty, "the %s slot reads \"empty\" (%s)" % [slot, worn])
	assert_eq(_texts(_buttons(screen, "CarriedList")), [], "nothing is listed as carried")


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
