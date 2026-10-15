extends GutTest
# Combat starts in the overworld (ticket #45): bumping into an enemy starts turn-based combat right
# there in the garage. Everyone rolls initiative (d20 + bonus), the turn order runs from highest to
# lowest, and the first combatant's turn begins.
#
# Interface these tests choose:
# - The main scene has a `CombatController` node. It has `running` (bool), `combatants` (Array),
#   `rolls` (combatant -> its d20 roll), `turn_order` (Array, first to act first) and `active` (the
#   combatant whose turn it is), plus a `turn_started(combatant)` signal.
# - `start_combat(combatants)` rolls initiative and starts the first turn. The detective's
#   combatant is his physics body (the `Player` CharacterBody3D), and the controller's `detective`
#   property points at it.
# - Every die comes from the controller's `rng` (a RandomNumberGenerator), through `roll_d20()`.
#   Setting `rng.seed` fixes the dice.
# - Initiative bonuses are node metadata, `initiative_bonus`, read through
#   `initiative_bonus(combatant)`. `order_by_initiative(rolls)` sorts combatants by roll plus bonus.

const ACTIONS := ["move_up", "move_down", "move_left", "move_right"]
const WALK_MINUS_Z := ["move_up", "move_right"]  # screen up+right walks along world -Z (#28)

var _turns := []  # every combatant named by turn_started, in order


func before_each():
	_turns = []


func after_each():
	for action: String in ACTIONS:
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


func _node(main: Node, node_name: String) -> Node:
	var node := main.find_child(node_name, true, false)
	assert_not_null(node, "the main scene has %s" % node_name)
	return node


# The physics body that carries the Detective (#28).
func _body(main: Node) -> CharacterBody3D:
	var node := main.find_child("Detective", true, false)
	while node != null and not node is CharacterBody3D:
		node = node.get_parent()
	assert_not_null(node, "the Detective is carried by a CharacterBody3D")
	return node as CharacterBody3D


# The main scene's combat controller, with the pieces these tests use, or null (after failing).
func _controller(main: Node) -> Node:
	var controller := _node(main, "CombatController")
	if controller == null:
		return null
	for method in ["start_combat", "roll_d20", "initiative_bonus", "order_by_initiative"]:
		assert_true(controller.has_method(method), "CombatController has %s()" % method)
		if not controller.has_method(method):
			return null
	assert_true(controller.has_signal("turn_started"), "CombatController has a turn_started signal")
	if not controller.has_signal("turn_started"):
		return null
	controller.turn_started.connect(func(combatant): _turns.append(combatant))
	return controller


func _press(actions: Array) -> void:
	for action: String in actions:
		if InputMap.has_action(action):
			Input.action_press(action)


# Walks the detective into the cultist from 2 m away, until combat starts (or 2 s pass).
func _bump(controller: Node, body: CharacterBody3D, cultist: Node3D) -> void:
	body.global_position = cultist.global_position + Vector3(0, 0, 2.0)
	body.velocity = Vector3.ZERO
	await wait_physics_frames(2)
	_press(WALK_MINUS_Z)
	for tick in 120:
		await get_tree().physics_frame
		if controller.running:
			break


# Given the detective walks into the cultist, when the encounter starts, then combat begins in the
# main scene: no scene switch is requested, a combat controller reports combat as running with the
# detective and the cultist as its combatants, and the keys no longer move the detective freely.
func test_bumping_into_the_cultist_starts_combat_in_place():
	var main := await _main()
	if main == null:
		return
	var controller := _controller(main)
	var body := _body(main)
	var cultist := _node(main, "Cultist") as Node3D
	if controller == null or body == null or cultist == null:
		return
	assert_false(controller.running, "combat isn't running at the start of the game")
	watch_signals(main)
	var runner := get_tree().current_scene
	await _bump(controller, body, cultist)
	assert_true(controller.running, "combat is running once he bumps into the cultist")
	assert_eq(controller.combatants.size(), 2, "two combatants")
	assert_true(controller.combatants.has(body), "the detective (his Player body) is a combatant")
	assert_true(controller.combatants.has(cultist), "the cultist is a combatant")
	if main.has_signal("combat_requested"):
		assert_signal_not_emitted(main, "combat_requested", "no switch to the combat screen is requested")
	await wait_physics_frames(2)
	assert_eq(get_tree().current_scene, runner, "the scene wasn't switched")
	assert_true(is_instance_valid(main) and main.is_inside_tree(), "the main scene is still running")
	var held_at := body.global_position
	await wait_physics_frames(30)  # still holding the keys
	var moved := body.global_position.distance_to(held_at)
	assert_lt(moved, 0.01, "the keys don't move him once combat starts (moved %.3f m)" % moved)


# Given combat starts, when initiative is rolled, then each combatant's roll is a d20 (1-20) plus
# their initiative bonus (detective +2, cultist +1), and every roll comes from a seedable random
# generator, so a test can fix the dice.
func test_initiative_is_a_seeded_d20_plus_bonus():
	var main := await _main()
	if main == null:
		return
	var controller := _controller(main)
	var body := _body(main)
	var cultist := _node(main, "Cultist") as Node3D
	if controller == null or body == null or cultist == null:
		return
	assert_eq(controller.initiative_bonus(body), 2, "the detective's initiative bonus is +2")
	assert_eq(controller.initiative_bonus(cultist), 1, "the cultist's initiative bonus is +1")
	assert_true(controller.rng is RandomNumberGenerator, "the dice come from a RandomNumberGenerator")

	# A d20: always 1-20, and over many rolls every face comes up.
	controller.rng.seed = 1234
	var faces := {}
	for i in 400:
		var roll: int = controller.roll_d20()
		assert_between(roll, 1, 20, "a d20 roll is 1-20")
		faces[roll] = true
	assert_eq(faces.size(), 20, "all twenty faces come up in 400 rolls")

	# Seeded: the same seed gives the same dice.
	controller.rng.seed = 77
	var first := []
	for i in 10:
		first.append(controller.roll_d20())
	controller.rng.seed = 77
	var again := []
	for i in 10:
		again.append(controller.roll_d20())
	assert_eq(again, first, "the same seed rolls the same dice")

	# Combat's initiative rolls are such dice, and fixed by the seed.
	controller.rng.seed = 2024
	controller.start_combat([body, cultist])
	assert_eq(controller.rolls.size(), 2, "one initiative roll per combatant")
	var rolled := {}
	for combatant: Node3D in [body, cultist]:
		assert_true(controller.rolls.has(combatant), "%s rolled initiative" % combatant.name)
		if controller.rolls.has(combatant):
			assert_between(controller.rolls[combatant], 1, 20, "%s's initiative roll is a d20" % combatant.name)
			rolled[combatant] = controller.rolls[combatant]
	var other := await _main()
	var other_controller := _controller(other) if other != null else null
	if other_controller == null:
		return
	var other_body := _body(other)
	var other_cultist := _node(other, "Cultist") as Node3D
	other_controller.rng.seed = 2024
	other_controller.start_combat([other_body, other_cultist])
	assert_eq(other_controller.rolls.get(other_body), rolled.get(body), "the same seed gives the detective the same roll")
	assert_eq(other_controller.rolls.get(other_cultist), rolled.get(cultist), "the same seed gives the cultist the same roll")


# Given the initiative rolls, when the turn order is set, then it is sorted from highest to lowest
# total, ties going to the higher bonus and then to the detective.
func test_turn_order_runs_from_highest_total():
	var main := await _main()
	if main == null:
		return
	var controller := _controller(main)
	var body := _body(main)
	var cultist := _node(main, "Cultist") as Node3D
	if controller == null or body == null or cultist == null:
		return
	assert_eq(controller.detective, body, "the controller knows the detective's combatant")
	# Totals decide: detective 3 + 2 = 5, cultist 15 + 1 = 16.
	assert_eq(controller.order_by_initiative({body: 3, cultist: 15}), [cultist, body], "the higher total goes first")
	assert_eq(controller.order_by_initiative({cultist: 3, body: 15}), [body, cultist], "the higher total goes first, whatever order they're listed in")
	# A tie on 12: detective 10 + 2, cultist 11 + 1. The higher bonus goes first.
	assert_eq(controller.order_by_initiative({cultist: 11, body: 10}), [body, cultist], "a tied total goes to the higher bonus")
	# A tie on total and bonus: the detective goes first.
	cultist.set_meta("initiative_bonus", 2)
	assert_eq(controller.order_by_initiative({cultist: 10, body: 10}), [body, cultist], "a full tie goes to the detective")

	# Combat uses that order for the rolls it made.
	cultist.set_meta("initiative_bonus", 1)
	controller.rng.seed = 99
	controller.start_combat([body, cultist])
	assert_eq(controller.turn_order, controller.order_by_initiative(controller.rolls), "combat's turn order follows its initiative rolls")
	assert_eq(controller.turn_order.size(), 2, "both combatants are in the turn order")


# Given the turn order is set, when combat starts, then the first combatant in it is the active one,
# and a turn-started signal names them.
func test_first_in_the_order_takes_the_first_turn():
	var main := await _main()
	if main == null:
		return
	var controller := _controller(main)
	var body := _body(main)
	var cultist := _node(main, "Cultist") as Node3D
	if controller == null or body == null or cultist == null:
		return
	# Try seeds until both the detective and the cultist have gone first.
	var firsts := {}
	for seed_value in range(1, 41):
		var each := await _main()
		var each_controller := _controller(each) if each != null else null
		if each_controller == null:
			return
		_turns = []
		each_controller.rng.seed = seed_value
		each_controller.start_combat([_body(each), each.find_child("Cultist", true, false)])
		assert_eq(each_controller.turn_order.size(), 2, "the turn order is set")
		if each_controller.turn_order.is_empty():
			return
		assert_eq(each_controller.active, each_controller.turn_order[0], "the first in the order is active (seed %d)" % seed_value)
		assert_eq(_turns, [each_controller.turn_order[0]], "turn_started fires once, naming them (seed %d)" % seed_value)
		firsts[each_controller.turn_order[0].name] = true
		each.queue_free()
		if firsts.size() == 2:
			break
	assert_eq(firsts.size(), 2, "within 40 seeds, each side goes first at least once")

	# Starting combat by bumping into the cultist starts the first turn too.
	_turns = []
	await _bump(controller, body, cultist)
	assert_true(controller.running, "combat started")
	assert_eq(controller.turn_order.size(), 2, "the turn order is set")
	if controller.turn_order.is_empty():
		return
	assert_eq(controller.active, controller.turn_order[0], "the first in the order is active")
	assert_eq(_turns, [controller.turn_order[0]], "turn_started fires once, naming them")
