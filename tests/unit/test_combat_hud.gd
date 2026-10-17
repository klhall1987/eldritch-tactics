extends GutTest
# The tabletop combat HUD and dice log (ticket #51): while combat runs, an on-screen HUD shows the
# turn order (with hit points and whose turn it is), the active combatant's movement, action and
# bonus action, an End Turn button, and a dice log of every roll. It's hidden outside combat.
#
# Interface these tests choose:
# - The main scene has a `CombatHUD` CanvasLayer, shown only while combat runs. Under it:
#   - `TurnOrder`: one Label per combatant, in initiative order, reading "<name> <hp>/<max>"; the
#     active combatant's Label starts with "▶". Names are node metadata `display_name`
#     ("Player", "Cultist").
#   - `Movement` (a Label with the movement left as "<metres to one decimal> m"), `Action` and
#     `BonusAction` (Labels reading "ready" or "used").
#   - `EndTurn`: a Button.
#   - `DiceLog`: a container of Labels, one per line, newest last. An initiative line reads like
#     "Player initiative: d20 14 + 2 = 16"; an attack line like
#     "Player attacks: 5 dice [6, 4, 2, 6, 1] = 5 successes vs defence 1, critical hit; damage 5" (the
#     d6 pool, #120).
# - The HUD reads the main scene's `CombatController` (#45-#50).

var _turns := []  # every combatant named by turn_started, in order


func before_each():
	_turns = []


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


# The physics body that carries the Detective (#28).
func _body(main: Node) -> CharacterBody3D:
	var node := main.find_child("Character", true, false)
	while node != null and not node is CharacterBody3D:
		node = node.get_parent()
	assert_not_null(node, "the Character is carried by a CharacterBody3D")
	return node as CharacterBody3D


func _part(hud: Node, part_name: String) -> Node:
	var node := hud.find_child(part_name, true, false)
	assert_not_null(node, "the HUD has %s" % part_name)
	return node


func _labels(container: Node) -> Array[String]:
	var texts: Array[String] = []
	if container == null:
		return texts
	for child in container.get_children():
		if child is Label:
			texts.append(child.text)
	return texts


# The main scene with its HUD, controller, detective and cultist.
# Returns [main, hud, controller, body, cultist], or [] (after failing).
func _scene() -> Array:
	var main := await _main()
	if main == null:
		return []
	var hud := main.find_child("CombatHUD", true, false)
	assert_true(hud is CanvasLayer, "the main scene has a CombatHUD CanvasLayer")
	var controller := main.find_child("CombatController", true, false)
	var body := _body(main)
	var cultist := main.find_child("Cultist", true, false) as Node3D
	if not hud is CanvasLayer or controller == null or body == null or cultist == null:
		return []
	controller.turn_started.connect(func(combatant): _turns.append(combatant))
	return [main, hud, controller, body, cultist]


# Starts combat with fixed dice, on the detective's turn, and lets the HUD catch up.
func _start(controller: Node, body: CharacterBody3D, cultist: Node3D) -> void:
	body.controllable = false  # as when an encounter starts (#31)
	for attempt in 50:
		controller.rng.seed = 51 + attempt
		controller.start_combat([body, cultist])
		if controller.active == body:
			break
	assert_eq(controller.active, body, "it's the detective's turn")
	await wait_frames_or_ticks()


func wait_frames_or_ticks() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await wait_physics_frames(1)


# Given combat isn't running, when the HUD is checked, then it's hidden; when combat starts, it's
# shown.
func test_hud_shows_only_during_combat():
	var scene := await _scene()
	if scene.is_empty():
		return
	var hud: CanvasLayer = scene[1]
	var controller: Node = scene[2]
	var body: CharacterBody3D = scene[3]
	var cultist: Node3D = scene[4]
	await wait_frames_or_ticks()
	assert_false(hud.visible, "before combat, the HUD is hidden")
	await _start(controller, body, cultist)
	assert_true(hud.visible, "once combat starts, the HUD is shown")
	controller.apply_damage(cultist, 100)  # the last enemy falls: victory (#49)
	assert_false(controller.running, "combat is over")
	await wait_frames_or_ticks()
	assert_false(hud.visible, "after combat, the HUD is hidden again")


# Given combat is running, when the HUD's turn order is read, then it lists the combatants in
# initiative order with their current and maximum hit points, marks the active one, and updates when
# the turn or anyone's hit points change.
func test_turn_order_with_hit_points():
	var scene := await _scene()
	if scene.is_empty():
		return
	var hud: CanvasLayer = scene[1]
	var controller: Node = scene[2]
	var body: CharacterBody3D = scene[3]
	var cultist: Node3D = scene[4]
	await _start(controller, body, cultist)
	var order := _part(hud, "TurnOrder")
	var entries := _labels(order)
	assert_eq(entries.size(), 2, "one entry per combatant")
	if entries.size() != 2:
		return
	var names := {body: "Player", cultist: "Cultist"}
	var hp := {body: "20/20", cultist: "12/12"}
	for i in 2:
		var combatant: Node3D = controller.turn_order[i]
		assert_string_contains(entries[i], names[combatant], "entry %d is %s, in initiative order" % [i + 1, names[combatant]])
		assert_string_contains(entries[i], hp[combatant], "it shows %s's hit points" % names[combatant])
	assert_true(entries[controller.turn_order.find(body)].begins_with("▶"), "the detective's entry is marked as active")
	assert_false(entries[controller.turn_order.find(cultist)].begins_with("▶"), "the cultist's entry isn't")

	controller.apply_damage(cultist, 5)
	await wait_frames_or_ticks()
	entries = _labels(order)
	assert_string_contains(entries[controller.turn_order.find(cultist)], "7/12", "the cultist's hit points update after damage")

	controller.end_turn()
	await wait_frames_or_ticks()
	entries = _labels(order)
	assert_true(entries[controller.turn_order.find(cultist)].begins_with("▶"), "on the cultist's turn, its entry is marked")
	assert_false(entries[controller.turn_order.find(body)].begins_with("▶"), "and the detective's isn't")


# Given it's the detective's turn, when the HUD's resources are read, then they show his remaining
# movement in metres (to one decimal) and whether his action and bonus action are available,
# updating as he spends them.
func test_resources_show_what_he_has_left():
	var scene := await _scene()
	if scene.is_empty():
		return
	var hud: CanvasLayer = scene[1]
	var controller: Node = scene[2]
	var body: CharacterBody3D = scene[3]
	var cultist: Node3D = scene[4]
	await _start(controller, body, cultist)
	var movement := _part(hud, "Movement") as Label
	var action := _part(hud, "Action") as Label
	var bonus := _part(hud, "BonusAction") as Label
	if movement == null or action == null or bonus == null:
		return
	assert_string_contains(movement.text, "9.0 m", "he has 9.0 m of movement")
	assert_string_contains(action.text, "ready", "his action is ready")
	assert_string_contains(bonus.text, "ready", "his bonus action is ready")

	controller.movement_left = 4.26  # as if he had walked 4.74 m
	controller.attack(body, cultist)  # spends his action
	controller.bonus_actions_left = 0
	await wait_frames_or_ticks()
	assert_string_contains(movement.text, "4.3 m", "the movement left updates, to one decimal")
	assert_string_contains(action.text, "used", "his action shows as used")
	assert_string_contains(bonus.text, "used", "his bonus action shows as used")


# Given the HUD's End Turn button is pressed on the detective's turn, when it's handled, then it ends
# his turn exactly like the `end_turn` key.
func test_end_turn_button_ends_his_turn():
	var scene := await _scene()
	if scene.is_empty():
		return
	var hud: CanvasLayer = scene[1]
	var controller: Node = scene[2]
	var body: CharacterBody3D = scene[3]
	var cultist: Node3D = scene[4]
	await _start(controller, body, cultist)
	var button := _part(hud, "EndTurn") as Button
	if button == null:
		return
	_turns = []
	button.pressed.emit()
	await wait_frames_or_ticks()
	assert_eq(controller.active, cultist, "the cultist's turn starts")
	assert_eq(_turns, [cultist], "turn_started names the cultist")
	# Like the key, it does nothing when it isn't his turn.
	var round_before: int = controller.round
	_turns = []
	button.pressed.emit()
	await wait_frames_or_ticks()
	assert_eq(controller.active, cultist, "on the cultist's turn, the button doesn't end it")
	assert_eq(controller.round, round_before, "nor start a new round")
	assert_eq(_turns, [], "no turn starts")


# Given an initiative roll, an attack roll or a damage roll happens, when the dice log is read, then
# its newest line shows that roll's dice, modifier and total (and for attacks, the target's AC and
# hit or miss).
func test_dice_log_shows_each_roll():
	var scene := await _scene()
	if scene.is_empty():
		return
	var hud: CanvasLayer = scene[1]
	var controller: Node = scene[2]
	var body: CharacterBody3D = scene[3]
	var cultist: Node3D = scene[4]
	await _start(controller, body, cultist)
	var log := _part(hud, "DiceLog")
	var lines := _labels(log)
	assert_gte(lines.size(), 2, "the initiative rolls are logged")
	if lines.size() < 2:
		return
	var newest := lines.slice(lines.size() - 2)
	var names := {body: "Player", cultist: "Cultist"}
	for combatant: Node3D in [body, cultist]:
		var roll: int = controller.rolls[combatant]
		var bonus: int = controller.initiative_bonus(combatant)
		var expected := "d20 %d + %d = %d" % [roll, bonus, roll + bonus]
		var found := false
		for line in newest:
			if line.contains(names[combatant]) and line.contains("initiative") and line.contains(expected):
				found = true
		assert_true(found, "a newest line shows %s's initiative: %s (lines: %s)" % [names[combatant], expected, newest])

	# Attacks until both a hit and a miss have been logged.
	var seen := {}
	for i in 60:
		var result: Dictionary = controller.attack(body, cultist)
		controller.hit_points[cultist] = 12  # keep the fight going
		await get_tree().process_frame
		lines = _labels(log)
		var line: String = lines[-1] if not lines.is_empty() else ""
		assert_string_contains(line, "Player", "the attack line names the attacker")
		# (The d20 parts of this check were rewritten for the d6 pool by #120, as its ticket says.)
		assert_string_contains(line, "%d dice %s = %d successes" % [result.dice.size(), str(result.dice), result.successes], "the newest line shows the dice and the successes")
		assert_string_contains(line, "vs defence 1", "it shows the target's defence")
		if result.hit:
			assert_string_contains(line, "hit", "it says hit")
			assert_string_contains(line, "damage %d" % result.damage, "it shows the damage")
			if result.critical:
				assert_string_contains(line, "critical", "it says critical")
		else:
			assert_string_contains(line, "miss", "it says miss")
		seen[result.hit] = true
		if seen.size() == 2:
			break
	assert_eq(seen.size(), 2, "both a hit and a miss were logged")
