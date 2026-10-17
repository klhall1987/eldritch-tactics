extends GutTest
# Attacks (ticket #48): on the detective's turn, clicking the cultist within reach (1.5 m between
# their bodies' edges) spends his action on an attack. Since #120 it's resolved with a pool of d6, like
# Vampire: The Masquerade: each die of 4+ is a success, a pair of 6s counts as four (a critical), it
# hits if the successes reach the target's defence (no successes at all is a total failure), and the
# damage is the weapon's damage plus the successes beyond the defence, at least 1. (Changed from the
# d20 rules by #120, as its ticket says.)
#
# Interface these tests choose, on the main scene's `CombatController` (#45-#47):
# - `attack(attacker, target)` resolves one attack with the controller's seeded dice, spends the
#   attacker's action when it's their turn, emits `attack_resolved(result)` and returns `result`: a
#   Dictionary with `attacker`, `target`, `dice` (each d6 rolled), `successes`, `defence`, `hit`,
#   `critical` and `damage`.
# - Stats are node metadata, read through `attack_pool(c)`, `defence(c)` and `weapon_damage(c)`.
# - Clicking the cultist (anywhere on it, in the scene's viewport) attacks it when allowed. A click
#   on the cultist never walks him there.

const START := Vector3(-1.2, 0, 0.6)  # clear floor
const DETECTIVE_RADIUS := 0.25  # his capsule (#29)
const IN_REACH_GAP := 1.0  # metres between the bodies' edges
const OUT_OF_REACH_GAP := 2.2

var _window: SubViewport
var _attacks := []  # every attack_resolved result, in order


func before_each():
	_attacks = []


func after_each():
	_window = null


# Instantiates the main scene inside a viewport the size of the project's default window, so
# screen positions are judged at the game's real size rather than the tiny headless test viewport.
func _main() -> Node3D:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the main scene (%s) loads" % path)
	if packed == null:
		return null
	_window = SubViewport.new()
	_window.size = Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	add_child_autofree(_window)
	var main := packed.instantiate()
	_window.add_child(main)
	await wait_physics_frames(3)
	return main as Node3D


# The physics body that carries the Detective (#28).
func _body(main: Node) -> CharacterBody3D:
	var node := main.find_child("Character", true, false)
	while node != null and not node is CharacterBody3D:
		node = node.get_parent()
	assert_not_null(node, "the Character is carried by a CharacterBody3D")
	return node as CharacterBody3D


# How far a node's meshes reach from its origin, seen from above (its body's radius).
func _body_radius(node: Node3D) -> float:
	var reach := 0.0
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mi.global_transform * mi.get_aabb()
		for x in [box.position.x, box.end.x]:
			for z in [box.position.z, box.end.z]:
				reach = maxf(reach, Vector2(x - node.global_position.x, z - node.global_position.z).length() / sqrt(2.0))
	return reach


# Main scene in combat between the detective (at START) and the cultist, `gap` metres apart
# between their bodies' edges, on the detective's turn, with fixed dice.
# Returns [main, controller, body, cultist], or [] (after failing).
func _combat(gap := IN_REACH_GAP, seed_value := 48) -> Array:
	var main := await _main()
	if main == null:
		return []
	var controller := main.find_child("CombatController", true, false)
	assert_not_null(controller, "the main scene has CombatController")
	var body := _body(main)
	var cultist := main.find_child("Cultist", true, false) as Node3D
	if controller == null or body == null or cultist == null:
		return []
	for method in ["attack", "attack_pool", "defence", "weapon_damage"]:  # (d20 names until #120; agreed on #120)
		assert_true(controller.has_method(method), "CombatController has %s()" % method)
		if not controller.has_method(method):
			return []
	assert_true(controller.has_signal("attack_resolved"), "CombatController has an attack_resolved signal")
	if not controller.has_signal("attack_resolved"):
		return []
	controller.attack_resolved.connect(func(result): _attacks.append(result))
	body.global_position = START
	body.velocity = Vector3.ZERO
	body.controllable = false  # as when an encounter starts (#31)
	var radius := _body_radius(cultist)
	cultist.global_position = START + Vector3(DETECTIVE_RADIUS + radius + gap, 0, 0)
	controller.rng.seed = seed_value
	controller.start_combat([body, cultist])
	if controller.active != body:
		controller.end_turn()
	assert_eq(controller.active, body, "it's the detective's turn")
	await wait_physics_frames(3)  # the camera follows him
	return [main, controller, body, cultist]


func _click_on(node: Node3D) -> void:
	var at := _window.get_camera_3d().unproject_position(node.global_position + Vector3.UP * 0.9)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	_window.push_input(motion)
	await wait_physics_frames(1)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		_window.push_input(click)
	await wait_physics_frames(30)


# The successes in `dice`: one per 4+, and each pair of 6s counts as four rather than two.
func _successes(dice: Array) -> int:
	var successes := 0
	var sixes := 0
	for die: int in dice:
		if die >= 4:
			successes += 1
		if die == 6:
			sixes += 1
	return successes + (sixes / 2) * 2


# The rules the result must follow, for an attacker with `pool` dice and `weapon` damage against a
# target with `defence`. (Rewritten for the d6 pool by #120.)
func _assert_follows_rules(result: Dictionary, pool: int, defence: int, weapon: int, who: String) -> void:
	var dice: Array = result.get("dice", [])
	assert_eq(dice.size(), pool, "%s: rolls %d d6" % [who, pool])
	var sixes := 0
	for die: int in dice:
		assert_between(die, 1, 6, "%s: each die is a d6" % who)
		if die == 6:
			sixes += 1
	var successes := _successes(dice)
	assert_eq(result.get("successes"), successes, "%s: %s is %d successes" % [who, dice, successes])
	assert_eq(result.get("defence"), defence, "%s: against defence %d" % [who, defence])
	var should_hit := successes > 0 and successes >= defence
	assert_eq(result.get("hit"), should_hit, "%s: %d successes against defence %d %s" % [who, successes, defence, "hits" if should_hit else "misses"])
	assert_eq(result.get("critical"), should_hit and sixes >= 2, "%s: a hit with a pair of 6s is a critical" % who)
	if not should_hit:
		assert_eq(result.get("damage"), 0, "%s: a miss deals no damage" % who)
		return
	var damage := maxi(1, weapon + successes - defence)
	assert_eq(result.get("damage"), damage, "%s: damage is %d + %d beyond the defence (at least 1)" % [who, weapon, successes - defence])


# Given it's the detective's turn, he has his action, and the cultist is within his reach (1.5 m,
# measured between their bodies' edges), when the player clicks the cultist, then he attacks it:
# his action is spent and an attack-resolved signal reports the roll, the total and whether it hit.
func test_clicking_the_cultist_in_reach_attacks_it():
	var fight := await _combat(IN_REACH_GAP)
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	assert_eq(controller.actions_left, 1, "he has his action")
	var movement_before: float = controller.movement_left
	await _click_on(cultist)
	assert_eq(_attacks.size(), 1, "one attack is resolved")
	if _attacks.is_empty():
		return
	var result: Dictionary = _attacks[0]
	assert_eq(result.get("attacker"), body, "the detective attacks")
	assert_eq(result.get("target"), cultist, "the cultist is attacked")
	for key in ["dice", "successes", "hit"]:  # (the d6 pool's, since #120)
		assert_true(result.has(key), "the result reports %s" % key)
	assert_eq(controller.actions_left, 0, "his action is spent")
	assert_almost_eq(controller.movement_left, movement_before, 0.001, "attacking doesn't spend movement")
	assert_lt(Vector2(body.global_position.x - START.x, body.global_position.z - START.z).length(), 0.01, "clicking the cultist doesn't walk him")


# Given an attack, when it is rolled, then the attacker rolls their attack pool of d6 (detective 5,
# cultist 4), counting a success for each 4+ and four for each pair of 6s. It hits if the successes
# reach the target's defence (detective 2, cultist 2: raised from 1 as agreed on #120); no successes
# at all is a total failure.
# (Rewritten for the d6 pool by #120, as its ticket says.)
func test_attack_rolls_follow_the_rules():
	var fight := await _combat()
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	assert_eq(controller.attack_pool(body), 5, "the detective's attack pool is 5 dice")
	assert_eq(controller.attack_pool(cultist), 4, "the cultist's attack pool is 4 dice")
	assert_eq(controller.defence(body), 2, "the detective's defence is 2")
	assert_eq(controller.defence(cultist), 2, "the cultist's defence is 2")
	var hits := {true: 0, false: 0}
	var criticals := 0
	var total_failures := 0
	for i in 400:
		var result: Dictionary = controller.attack(body, cultist)
		_assert_follows_rules(result, 5, 2, 1, "detective")
		hits[result.get("hit")] += 1
		if result.get("critical"):
			criticals += 1
		result = controller.attack(cultist, body)
		_assert_follows_rules(result, 4, 2, 1, "cultist")
		if result.get("successes") == 0:
			total_failures += 1
	assert_gt(hits[true], 0, "some attacks hit")
	assert_gt(hits[false], 0, "some attacks miss")
	assert_gt(criticals, 0, "in 400 attacks some are criticals")
	assert_gt(total_failures, 0, "in 400 attacks some are total failures")


# Given a hit, when damage is worked out, then it's the attacker's weapon damage (detective's knife 1,
# cultist's mandibles 1) plus the successes beyond the defence, at least 1; a critical's extra
# successes make it hit harder than any normal hit, and a miss deals no damage.
# (Rewritten for the d6 pool by #120, as its ticket says.)
func test_damage_dice_on_a_hit():
	var fight := await _combat()
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	assert_eq(controller.weapon_damage(body), 1, "the detective's knife does 1")
	assert_eq(controller.weapon_damage(cultist), 1, "the cultist's mandibles do 1")
	var normal := {}  # damage dealt on ordinary hits
	var critical_max := 0
	var cultist_damage := {}
	for i in 600:
		var result: Dictionary = controller.attack(body, cultist)
		_assert_follows_rules(result, 5, 2, 1, "detective")
		if result.get("hit") and not result.get("critical"):
			normal[result.get("damage")] = true
		elif result.get("critical"):
			critical_max = maxi(critical_max, result.get("damage"))
		result = controller.attack(cultist, body)
		_assert_follows_rules(result, 4, 2, 1, "cultist")
		if result.get("hit") and not result.get("critical"):
			cultist_damage[result.get("damage")] = true
	assert_eq(normal.keys().min(), 1, "the detective's lowest normal hit is 1")
	assert_eq(normal.keys().max(), 4, "the detective's highest normal hit is 1 + 3 beyond the cultist's defence")
	assert_gt(critical_max, 4, "a critical hit can deal more than any normal hit (best %d)" % critical_max)
	assert_eq(cultist_damage.keys().min(), 1, "the cultist's lowest hit is 1")
	assert_eq(cultist_damage.keys().max(), 3, "the cultist's highest normal hit is 1 + 2 beyond the detective's defence")


# Given the cultist is out of reach, or his action is already spent, or it isn't his turn, when the
# player clicks the cultist, then no attack happens and nothing is spent.
func test_no_attack_out_of_reach_without_an_action_or_off_turn():
	# Out of reach.
	var fight := await _combat(OUT_OF_REACH_GAP)
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	var movement_before: float = controller.movement_left
	await _click_on(cultist)
	assert_eq(_attacks.size(), 0, "out of reach, no attack")
	assert_eq(controller.actions_left, 1, "out of reach, his action isn't spent")
	assert_almost_eq(controller.movement_left, movement_before, 0.001, "out of reach, no movement is spent")
	assert_lt(Vector2(body.global_position.x - START.x, body.global_position.z - START.z).length(), 0.01, "out of reach, he doesn't walk to it")

	# Action already spent.
	fight = await _combat(IN_REACH_GAP)
	if fight.is_empty():
		return
	controller = fight[1]
	cultist = fight[3]
	controller.actions_left = 0
	movement_before = controller.movement_left
	_attacks = []
	await _click_on(cultist)
	assert_eq(_attacks.size(), 0, "with his action spent, no attack")
	assert_eq(controller.actions_left, 0, "nothing more is spent")
	assert_almost_eq(controller.movement_left, movement_before, 0.001, "no movement is spent")

	# The cultist's turn.
	fight = await _combat(IN_REACH_GAP)
	if fight.is_empty():
		return
	controller = fight[1]
	cultist = fight[3]
	controller.end_turn()
	assert_eq(controller.active, cultist, "it's the cultist's turn")
	_attacks = []
	await _click_on(cultist)
	assert_eq(_attacks.size(), 0, "on the cultist's turn, no attack")
	assert_eq(controller.actions_left, 1, "the cultist's action isn't spent")


# Given the dice come from #45's seedable random generator, when a test fixes the seed, then the
# attack's rolls are repeatable.
func test_attacks_are_repeatable_with_a_seed():
	var fight := await _combat()
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	var runs := []
	for run in 2:
		controller.rng.seed = 4848
		var results := []
		for i in 20:
			var result: Dictionary = controller.attack(body, cultist)
			results.append([result.get("roll"), result.get("hit"), result.get("damage_rolls"), result.get("damage")])
		runs.append(results)
	assert_eq(runs[0].size(), 20, "twenty attacks were rolled")
	assert_eq(runs[1], runs[0], "the same seed rolls the same attacks")
