extends GutTest
# Blood spray on knife hits (ticket #94): when the player character's slash hits the cultist, a small
# one-shot spray of dark red blood bursts from the new cut, away from the attacker; a critical hit
# sprays far more, faster. Sprays clean themselves up; misses and the cultist's punches spray nothing.
#
# Interface these tests choose:
# - A spray is a CPUParticles3D in the group `blood_sprays`, added to the scene (not under the wound).
#   Its particle count is `amount`, its speed `initial_velocity_min`, its colour `color`, and the way it
#   flies its `direction` turned by its global basis.
# - "Dark red": red at least 0.25, green and blue at most 0.15. "Mostly away from the attacker": the
#   spray's direction, flattened, points within 60 degrees of straight away from him.
# - The new wound is the newest node in the `wounds` group (#93).
# - The tests pick a normal hit, a critical or a miss by peeking at the controller's next dice pool
#   (`roll_pool()`, saving and restoring `rng.state`; a d20 until #120).

var _window: SubViewport


func after_each():
	_window = null


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


# [main, controller, body (Player), cultist], in combat on the player's turn, or [] (after failing).
func _fight() -> Array:
	var main := await _main()
	if main == null:
		return []
	var controller := main.find_child("CombatController", true, false)
	var body := main.find_child("Player", true, false) as CharacterBody3D
	var cultist := main.find_child("Cultist", true, false) as Node3D
	if controller == null or body == null or cultist == null:
		return []
	body.controllable = false
	body.global_position = cultist.global_position + Vector3(-0.9, 0, 0.9)
	body.look_at(cultist.global_position, Vector3.UP, true)
	await wait_physics_frames(2)
	for attempt in 50:
		controller.rng.seed = 94 + attempt
		controller.start_combat([body, cultist])
		if controller.active == body:
			break
	assert_eq(controller.active, body, "it's the player's turn")
	return [main, controller, body, cultist]


func _sprays() -> Array:
	return get_tree().get_nodes_in_group("blood_sprays")


# Advances the dice until the next pool of `pool` d6 is one `wanted` accepts (leaving it to be rolled
# next). (Peeked at the d20 until #120 moved attacks to the d6 pool, as its ticket says.)
func _next_roll(controller: Node, wanted: Callable, pool := 5) -> void:
	for i in 1000:
		var state: int = controller.rng.state
		var dice: Array = controller.roll_pool(pool)
		if wanted.call(dice):
			controller.rng.state = state
			return
	fail_test("no wanted pool came up in 1000 rolls")


# The successes in `dice` (#120): one per 4+, four per pair of 6s.
func _successes(dice: Array) -> int:
	var sixes := dice.count(6)
	return dice.filter(func(d: int) -> bool: return d >= 4).size() + (sixes / 2) * 2


# The player character attacks the cultist with the next pool `wanted` accepts, then waits for the
# slash to land and a spray to start. Returns [result, spray or null].
func _slash(controller: Node, body: Node3D, cultist: Node3D, wanted: Callable) -> Array:
	_next_roll(controller, wanted)
	controller.actions_left = 1
	var result: Dictionary = controller.attack(body, cultist)
	controller.hit_points[cultist] = 12
	var spray: CPUParticles3D = null
	for tick in 120:
		await get_tree().physics_frame
		if not _sprays().is_empty():
			spray = _sprays()[-1] as CPUParticles3D
			break
	return [result, spray]


func _normal_hit(dice: Array) -> bool:
	return _successes(dice) >= 2 and dice.count(6) < 2  # a hit against the cultist's defence 2 (agreed on #120), no critical


func _critical(dice: Array) -> bool:
	return dice.count(6) >= 2  # a pair of 6s: a critical hit


func _away(spray: CPUParticles3D, attacker: Node3D, target: Node3D) -> float:
	var flies := spray.global_basis * spray.direction
	var away := Vector2(target.global_position.x - attacker.global_position.x, target.global_position.z - attacker.global_position.z).normalized()
	return rad_to_deg(Vector2(flies.x, flies.z).normalized().angle_to(away))


# Given the player character hits the cultist (not a critical hit), when the slash lands, then a
# one-shot spray of dark red blood starts within 0.1 m of the new wound and flies mostly away from the
# attacker.
func test_a_hit_sprays_blood():
	var fight := await _fight()
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	var slash := await _slash(controller, body, cultist, _normal_hit)
	assert_true(slash[0].hit and not slash[0].critical, "a normal hit")
	var spray: CPUParticles3D = slash[1]
	assert_not_null(spray, "blood sprays as the slash lands")
	if spray == null:
		return
	assert_true(spray.one_shot, "the spray is one burst")
	assert_true(spray.emitting, "the spray is going")
	assert_true(spray.color.r >= 0.25 and spray.color.g <= 0.15 and spray.color.b <= 0.15, "the blood is dark red (%s)" % spray.color)
	assert_false(cultist.is_ancestor_of(spray), "the spray is in the scene, not on the cultist")
	var wounds := get_tree().get_nodes_in_group("wounds")
	assert_false(wounds.is_empty(), "the hit opened a wound")
	if not wounds.is_empty():
		var gap := spray.global_position.distance_to((wounds[-1] as Node3D).global_position)
		assert_lte(gap, 0.1, "the spray starts at the new wound (%.3f m from it)" % gap)
	var angle := absf(_away(spray, body, cultist))
	assert_lte(angle, 60.0, "the blood flies away from the attacker (%.0f degrees off)" % angle)


# Given the player character lands a critical hit, when the slash lands, then the spray has at least 3
# times as many particles as a normal hit's, flying at least 1.5 times as fast.
func test_a_critical_sprays_far_more():
	var fight := await _fight()
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	var normal := await _slash(controller, body, cultist, _normal_hit)
	var small: CPUParticles3D = normal[1]
	assert_not_null(small, "a normal hit sprays")
	if small == null:
		return
	var amount := small.amount
	var speed := small.initial_velocity_min
	await wait_seconds(1.0)
	var critical := await _slash(controller, body, cultist, _critical)
	assert_true(critical[0].critical, "a critical hit")
	var big: CPUParticles3D = critical[1]
	assert_true(big != null and big != small, "the critical hit sprays")
	if big == null or big == small:
		return
	assert_gte(big.amount, amount * 3, "a critical sprays at least 3 times the blood (%d vs %d particles)" % [big.amount, amount])
	assert_gte(big.initial_velocity_min, speed * 1.5, "and it flies at least 1.5 times as fast (%.2f vs %.2f m/s)" % [big.initial_velocity_min, speed])


# Given a spray has started, when 3 seconds have passed, then it has finished and been removed.
func test_sprays_clean_up():
	var fight := await _fight()
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	var slash := await _slash(controller, body, cultist, _critical)
	assert_not_null(slash[1], "blood sprays")
	await wait_seconds(3.0)
	assert_eq(_sprays().size(), 0, "3 s later no spray is left")


# Given an attack misses, or the cultist punches the player character, when the attack resolves, then
# no blood sprays.
func test_misses_and_punches_spray_nothing():
	var fight := await _fight()
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	for i in 3:
		_next_roll(controller, func(dice: Array) -> bool: return _successes(dice) < 2)  # short of its defence 2
		controller.actions_left = 1
		var result: Dictionary = controller.attack(body, cultist)
		assert_false(result.hit, "the attack misses")
		await wait_seconds(1.3)
		assert_eq(_sprays().size(), 0, "a miss sprays no blood")
	body.set_meta("defence", 0)  # the cultist's attacks land unless they roll no successes (#120)
	for i in 3:
		_next_roll(controller, func(dice: Array) -> bool: return _successes(dice) > 0, 4)
		var result: Dictionary = controller.attack(cultist, body)
		controller.hit_points[body] = 20
		assert_true(result.hit, "the cultist's punch lands")
		await wait_seconds(1.3)
		assert_eq(_sprays().size(), 0, "the cultist's punch sprays no blood")
