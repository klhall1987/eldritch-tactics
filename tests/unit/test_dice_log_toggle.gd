extends GutTest
# Hide the dice log (ticket #102): when combat starts the combat HUD's dice log is hidden, though rolls
# are still logged into it; the `dice_log` key (L) shows it and hides it again, and every new combat
# starts with it hidden.
#
# Interface these tests choose:
# - The HUD is the main scene's `CombatHUD`; the log is its `DiceLog` node (#51), and "shown" means
#   `DiceLog.is_visible_in_tree()` (whatever panel it sits in counts with it). The other parts are
#   `TurnOrder`, `Movement`, `Action`, `BonusAction` and `EndTurn`.
# - The key is pressed through Input (`Input.action_press("dice_log")`, then released), and the
#   `dice_log` action is bound to the L key in the project's input map.

const OTHER_PARTS := ["TurnOrder", "Movement", "Action", "BonusAction", "EndTurn"]


func _main() -> Node3D:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the main scene (%s) loads" % path)
	if packed == null:
		return null
	var main := packed.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(3)
	return main as Node3D


# [main, hud, controller, body, cultist, log], in combat on the player's turn, or [] (after failing).
func _fight() -> Array:
	var main := await _main()
	if main == null:
		return []
	var hud := main.find_child("CombatHUD", true, false)
	var controller := main.find_child("CombatController", true, false)
	var body := main.find_child("Player", true, false) as CharacterBody3D
	var cultist := main.find_child("Cultist", true, false) as Node3D
	assert_not_null(hud, "the main scene has the CombatHUD")
	if hud == null or controller == null or body == null or cultist == null:
		return []
	var log := hud.find_child("DiceLog", true, false) as Control
	assert_not_null(log, "the HUD has a DiceLog")
	if log == null:
		return []
	_start(controller, body, cultist)
	await wait_process_frames(2)
	return [main, hud, controller, body, cultist, log]


func _start(controller: Node, body: CharacterBody3D, cultist: Node3D) -> void:
	body.controllable = false
	for attempt in 50:
		controller.rng.seed = 102 + attempt
		controller.start_combat([body, cultist])
		if controller.active == body:
			break


func _press_dice_log_key() -> void:
	Input.action_press("dice_log")
	await wait_process_frames(2)
	Input.action_release("dice_log")
	await wait_process_frames(2)


func _lines(log: Node) -> int:
	return log.get_children().filter(func(c: Node) -> bool: return c is Label).size()


# Given combat has started, when the HUD is shown, then the dice log isn't visible, and the turn order,
# movement, actions and End Turn are.
func test_the_dice_log_starts_hidden():
	var fight := await _fight()
	if fight.is_empty():
		return
	var hud: CanvasLayer = fight[1]
	var log: Control = fight[5]
	assert_true(hud.visible, "the HUD is shown in combat")
	assert_false(log.is_visible_in_tree(), "the dice log starts hidden")
	for part_name in OTHER_PARTS:
		var part := hud.find_child(part_name, true, false) as CanvasItem
		assert_true(part != null and part.is_visible_in_tree(), "%s is shown" % part_name)


# Given the dice log is hidden, when rolls happen, then they're still logged.
func test_rolls_are_logged_while_hidden():
	var fight := await _fight()
	if fight.is_empty():
		return
	var controller: Node = fight[2]
	var body: Node3D = fight[3]
	var cultist: Node3D = fight[4]
	var log: Control = fight[5]
	assert_false(log.is_visible_in_tree(), "the dice log is hidden")
	assert_gte(_lines(log), 2, "both initiative rolls are logged (%d lines)" % _lines(log))
	var before := _lines(log)
	controller.attack(body, cultist)
	await wait_process_frames(1)
	assert_eq(_lines(log), before + 1, "the attack is logged too")


# Given combat is running, when the player presses the dice_log key (L), then the log is shown; when
# they press it again, it's hidden.
func test_l_shows_and_hides_the_dice_log():
	var events: Array = InputMap.action_get_events("dice_log") if InputMap.has_action("dice_log") else []
	assert_true(events.any(func(e: InputEvent) -> bool:
		return e is InputEventKey and (e.physical_keycode == KEY_L or e.keycode == KEY_L)), "the dice_log action is bound to L")
	var fight := await _fight()
	if fight.is_empty() or not InputMap.has_action("dice_log"):
		return
	var log: Control = fight[5]
	await _press_dice_log_key()
	assert_true(log.is_visible_in_tree(), "L shows the dice log")
	await _press_dice_log_key()
	assert_false(log.is_visible_in_tree(), "L again hides it")


# Given the dice log was shown, when combat ends and a new combat starts, then it starts hidden again.
func test_each_combat_starts_with_it_hidden():
	var fight := await _fight()
	if fight.is_empty() or not InputMap.has_action("dice_log"):
		assert_true(InputMap.has_action("dice_log"), "there's a dice_log action")
		return
	var controller: Node = fight[2]
	var body: CharacterBody3D = fight[3]
	var cultist: Node3D = fight[4]
	var log: Control = fight[5]
	await _press_dice_log_key()
	assert_true(log.is_visible_in_tree(), "the dice log is shown")
	controller.apply_damage(cultist, 100)
	assert_false(controller.running, "combat ended")
	await wait_process_frames(2)
	_start(controller, body, cultist)
	await wait_process_frames(2)
	assert_true(controller.running, "a new combat started")
	assert_false(log.is_visible_in_tree(), "the new combat starts with the dice log hidden")
