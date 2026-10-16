extends GutTest
# Combat turns (ticket #46): on their turn a combatant gets the tabletop action economy (movement in
# metres, one action, one bonus action). Ending the turn (End Turn, Space) passes play to the next
# combatant in the initiative order, and after the last one a new round begins.
#
# Interface these tests choose, on the main scene's `CombatController` (#45):
# - The active combatant's resources: `movement_left` (metres), `actions_left` and
#   `bonus_actions_left`.
# - Full movement is node metadata, `movement` (metres), read through `movement(combatant)`.
# - `end_turn()` ends the active combatant's turn. `round` counts rounds, starting at 1.
# - The `end_turn` input action (Space) ends the detective's turn, and only his.

const PHYSICS_TICKS := 3  # ticks to let a key press be seen


var _turns := []  # every combatant named by turn_started, in order


func before_each():
	_turns = []


func after_each():
	if InputMap.has_action("end_turn"):
		Input.action_release("end_turn")


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


# Starts combat in a fresh main scene between the detective and the cultist, with fixed dice.
# Returns [controller, detective's body, cultist], or [] (after failing).
func _combat(seed_value := 45) -> Array:
	var main := await _main()
	if main == null:
		return []
	var controller := main.find_child("CombatController", true, false)
	assert_not_null(controller, "the main scene has CombatController")
	if controller == null:
		return []
	for method in ["start_combat", "end_turn", "movement"]:
		assert_true(controller.has_method(method), "CombatController has %s()" % method)
		if not controller.has_method(method):
			return []
	var body := _body(main)
	var cultist := main.find_child("Cultist", true, false) as Node3D
	assert_not_null(cultist, "the main scene has the Cultist")
	if body == null or cultist == null:
		return []
	controller.turn_started.connect(func(combatant): _turns.append(combatant))
	controller.rng.seed = seed_value
	controller.start_combat([body, cultist])
	return [controller, body, cultist]


# Ends turns (directly) until it's `combatant`'s turn.
func _until_turn_of(controller: Node, combatant: Node3D) -> void:
	for i in 4:
		if controller.active == combatant:
			return
		controller.end_turn()
	assert_eq(controller.active, combatant, "it's %s's turn" % combatant.name)


func _press_end_turn() -> void:
	Input.action_press("end_turn")
	await wait_physics_frames(PHYSICS_TICKS)
	Input.action_release("end_turn")
	await wait_physics_frames(PHYSICS_TICKS)


# Given a combatant's turn starts, when their resources are checked, then they have their full
# movement (detective 9 m, cultist 6 m), one action and one bonus action.
func test_a_turn_starts_with_full_resources():
	var fight := await _combat()
	if fight.is_empty():
		return
	var controller: Node = fight[0]
	var body: CharacterBody3D = fight[1]
	var cultist: Node3D = fight[2]
	assert_almost_eq(controller.movement(body), 9.0, 0.001, "the detective's movement is 9 m")
	assert_almost_eq(controller.movement(cultist), 6.0, 0.001, "the cultist's movement is 6 m")
	for combatant: Node3D in [body, cultist]:
		await _until_turn_of(controller, combatant)
		var expected := 9.0 if combatant == body else 6.0
		assert_almost_eq(controller.movement_left, expected, 0.001, "%s starts the turn with %.0f m of movement" % [combatant.name, expected])
		assert_eq(controller.actions_left, 1, "%s starts the turn with one action" % combatant.name)
		assert_eq(controller.bonus_actions_left, 1, "%s starts the turn with one bonus action" % combatant.name)


# Given it's the detective's turn, when the `end_turn` input action (Space) is pressed, then the
# next combatant in the initiative order becomes active and a turn-started signal names them.
func test_end_turn_key_passes_play_on():
	assert_true(InputMap.has_action("end_turn"), "the input map has end_turn")
	if not InputMap.has_action("end_turn"):
		return
	var keys := []
	for event in InputMap.action_get_events("end_turn"):
		if event is InputEventKey:
			keys.append(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	assert_has(keys, KEY_SPACE, "end_turn is bound to Space")
	var fight := await _combat()
	if fight.is_empty():
		return
	var controller: Node = fight[0]
	var body: CharacterBody3D = fight[1]
	await _until_turn_of(controller, body)
	var next: Node3D = controller.turn_order[(controller.turn_order.find(body) + 1) % controller.turn_order.size()]
	_turns = []
	await _press_end_turn()
	assert_eq(controller.active, next, "the next combatant in the order is active")
	assert_eq(_turns, [next], "turn_started fires once, naming them")


# Given the last combatant in the order ends their turn, when play moves on, then the round counter
# goes up by one, and the first combatant's turn starts again with refreshed resources.
func test_a_new_round_starts_after_the_last_turn():
	var fight := await _combat()
	if fight.is_empty():
		return
	var controller: Node = fight[0]
	assert_eq(controller.round, 1, "combat starts in round 1")
	var first: Node3D = controller.turn_order[0]
	var last: Node3D = controller.turn_order[-1]
	await _until_turn_of(controller, last)
	assert_eq(controller.round, 1, "still round 1 on the last combatant's turn")
	# Spend everything, as if they had moved and acted.
	controller.movement_left = 0.0
	controller.actions_left = 0
	controller.bonus_actions_left = 0
	_turns = []
	controller.end_turn()
	assert_eq(controller.round, 2, "ending the last turn starts round 2")
	assert_eq(controller.active, first, "the first combatant in the order acts again")
	assert_eq(_turns, [first], "turn_started names them")
	assert_almost_eq(controller.movement_left, controller.movement(first), 0.001, "their movement is refreshed")
	assert_eq(controller.actions_left, 1, "their action is refreshed")
	assert_eq(controller.bonus_actions_left, 1, "their bonus action is refreshed")


# Given it isn't the detective's turn, when `end_turn` is pressed, then nothing happens.
func test_end_turn_key_does_nothing_on_the_cultists_turn():
	assert_true(InputMap.has_action("end_turn"), "the input map has end_turn")
	if not InputMap.has_action("end_turn"):
		return
	var fight := await _combat()
	if fight.is_empty():
		return
	var controller: Node = fight[0]
	var cultist: Node3D = fight[2]
	await _until_turn_of(controller, cultist)
	var round_before: int = controller.round
	_turns = []
	await _press_end_turn()
	assert_eq(controller.active, cultist, "it's still the cultist's turn")
	assert_eq(controller.round, round_before, "the round doesn't change")
	assert_eq(_turns, [], "no turn starts")
