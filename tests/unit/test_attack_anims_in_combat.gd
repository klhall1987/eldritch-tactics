extends GutTest
# Attack and hit animations play in combat (ticket #81): when an attack resolves, the attacker plays
# `attack`; if it hit, the target plays `hit` as the second punch lands (after the attack's halfway
# point, before it ends). Both then return to their stance, the player's own animation choice doesn't
# cut them short, and the cultist's turn waits for its attack to finish before ending.
#
# Interface these tests choose: "plays" means the character's AnimationPlayer's
# `current_animation`. Timing is measured in physics ticks (60 a second).

const PHYSICS_FPS := 60
const START := Vector3(-1.2, 0, 0.6)  # clear floor
const DETECTIVE_RADIUS := 0.27  # the Player's capsule (#68)

var _window: SubViewport
var _results := []  # every attack_resolved result


func before_each():
	_results = []


func after_each():
	_window = null


# The main scene in a viewport the size of the game's window, or null (after failing).
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


func _animation(node: Node) -> AnimationPlayer:
	var players := node.find_children("*", "AnimationPlayer", true, false)
	return players[0] if not players.is_empty() else null


# How far a node's meshes reach from its origin, seen from above (its body's radius).
func _body_radius(node: Node3D) -> float:
	var reach := 0.0
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mi.global_transform * mi.get_aabb()
		for x in [box.position.x, box.end.x]:
			for z in [box.position.z, box.end.z]:
				reach = maxf(reach, Vector2(x - node.global_position.x, z - node.global_position.z).length() / sqrt(2.0))
	return reach


# A fight in a fresh main scene: the player at START and the cultist `gap` m away (edge to edge),
# with dice `seed_value`, on the player's turn when `players_turn` (else the cultist's turn has just
# begun). Returns [main, controller, body, cultist, body's AnimationPlayer, cultist's], or [].
func _fight(seed_value: int, players_turn := true, gap := 1.0) -> Array:
	var main := await _main()
	if main == null:
		return []
	var controller := main.find_child("CombatController", true, false)
	var body := main.find_child("Player", true, false) as CharacterBody3D
	var cultist := main.find_child("Cultist", true, false) as Node3D
	if controller == null or body == null or cultist == null:
		return []
	controller.attack_resolved.connect(func(result): _results.append(result))
	body.global_position = START
	body.velocity = Vector3.ZERO
	body.controllable = false
	cultist.global_position = START + Vector3(DETECTIVE_RADIUS + _body_radius(cultist) + gap, 0, 0)
	for attempt in 50:
		controller.rng.seed = seed_value * 100 + attempt
		controller.start_combat([body, cultist])
		if controller.active == body:
			break
	if not players_turn:
		controller.end_turn()
	await wait_physics_frames(3)
	return [main, controller, body, cultist, _animation(body), _animation(cultist)]


func _click_on(node: Node3D) -> void:
	var at := _window.get_camera_3d().unproject_position(node.global_position + Vector3.UP * 0.9)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		_window.push_input(click)


# Watches both animation players for up to `seconds` after an attack is made, returning the tick at
# which the attacker first plays `attack`, the tick at which the target first plays `hit` (-1 if
# never), and each one's animation at the end.
func _watch(attacker: AnimationPlayer, target: AnimationPlayer, seconds: float, until := Callable()) -> Dictionary:
	var watch := {"attack_at": -1, "hit_at": -1, "attack_seen_mid": [], "attack_ended_at": -1}
	for tick in int(seconds * PHYSICS_FPS):
		await get_tree().physics_frame
		if watch.attack_at < 0 and attacker.current_animation == "attack":
			watch.attack_at = tick
		if watch.attack_at >= 0 and watch.attack_ended_at < 0 and attacker.current_animation != "attack":
			watch.attack_ended_at = tick
		if watch.hit_at < 0 and target.current_animation == "hit":
			watch.hit_at = tick
		if until.is_valid() and until.call():
			break
	watch.attacker_now = attacker.current_animation
	watch.target_now = target.current_animation
	return watch


# The player's attack on the cultist with dice that hit (or miss, when `want_hit` is false): the
# watch, the fight, and the attack's length in ticks. Tries seeds until the attack goes as wanted.
func _player_attack(want_hit: bool) -> Array:
	for seed_value in range(1, 30):
		var fight := await _fight(seed_value)
		if fight.is_empty():
			return []
		_results = []
		_click_on(fight[3])
		var watch := await _watch(fight[4], fight[5], 3.5)
		if _results.is_empty():
			continue
		if bool(_results[0].hit) == want_hit:
			var length := int(round((fight[4] as AnimationPlayer).get_animation("attack").length * PHYSICS_FPS))
			return [watch, fight, length]
	fail_test("no seed gave a %s" % ("hit" if want_hit else "miss"))
	return []


# Given the player clicks the cultist within reach (#48), when the attack resolves, then the player
# character plays attack. If it hit, the cultist plays hit, starting after the player's attack has
# passed its halfway point and before it ends.
func test_player_attack_plays_and_a_hit_makes_the_cultist_flinch():
	var outcome := await _player_attack(true)
	if outcome.is_empty():
		return
	var watch: Dictionary = outcome[0]
	var length: int = outcome[2]
	assert_gte(watch.attack_at, 0, "the player plays attack")
	assert_gte(watch.hit_at, 0, "the cultist plays hit")
	if watch.attack_at < 0 or watch.hit_at < 0:
		return
	var delay: int = watch.hit_at - watch.attack_at
	assert_between(delay, length / 2, length, "the cultist flinches after the attack's halfway point and before it ends (%d of %d ticks)" % [delay, length])


# Given the cultist attacks the player on its turn (#50), when the attack resolves, then the cultist
# plays attack, and if it hit, the player character plays hit the same way.
func test_cultist_attack_plays_and_a_hit_makes_the_player_flinch():
	for seed_value in range(1, 30):
		var fight := await _fight(seed_value, false, 1.0)
		if fight.is_empty():
			return
		var controller: Node = fight[1]
		var watch := await _watch(fight[5], fight[4], 7.0, func(): return not _results.is_empty() and fight[4].current_animation == "hit")
		if _results.is_empty() or not bool(_results[0].hit):
			continue
		var length := int(round((fight[5] as AnimationPlayer).get_animation("attack").length * PHYSICS_FPS))
		assert_eq(_results[0].attacker, fight[3], "the cultist attacked")
		assert_gte(watch.attack_at, 0, "the cultist plays attack")
		assert_gte(watch.hit_at, 0, "the player plays hit")
		if watch.attack_at >= 0 and watch.hit_at >= 0:
			var delay: int = watch.hit_at - watch.attack_at
			assert_between(delay, length / 2, length, "the player flinches after the attack's halfway point and before it ends (%d of %d ticks)" % [delay, length])
		return
	fail_test("no seed gave the cultist a hit")


# Given an attack misses, when it plays out, then the attacker still plays attack, and the target
# plays no hit.
func test_a_miss_plays_the_attack_without_a_flinch():
	var outcome := await _player_attack(false)
	if outcome.is_empty():
		return
	var watch: Dictionary = outcome[0]
	assert_gte(watch.attack_at, 0, "the player still plays attack")
	assert_eq(watch.hit_at, -1, "the cultist plays no hit on a miss")


# Given the attack and reaction have finished, when they're checked, then each goes back to its
# stance: the player to combat_idle (or idle if the fight is over) and the cultist to idle. The
# player's stance and walk animations don't cut attack or hit short.
func test_both_return_to_their_stance_and_nothing_cuts_them_short():
	var outcome := await _player_attack(true)
	if outcome.is_empty():
		return
	var watch: Dictionary = outcome[0]
	var fight: Array = outcome[1]
	var length: int = outcome[2]
	var controller: Node = fight[1]
	assert_gte(watch.attack_at, 0, "the player played attack")
	if watch.attack_at >= 0 and watch.attack_ended_at >= 0:
		var lasted: int = watch.attack_ended_at - watch.attack_at
		assert_gte(lasted, length - 3, "nothing cut the player's attack short (it played %d of %d ticks)" % [lasted, length])
	var expected := "combat_idle" if controller.running else "idle"
	assert_eq(watch.attacker_now, expected, "afterwards the player is back in %s" % expected)
	assert_eq(watch.target_now, "idle", "afterwards the cultist is back in idle")


# Given the cultist attacks on its turn, when its turn ends, then it ends only after its attack has
# finished, and still within 8 s of the turn starting.
func test_cultist_turn_waits_for_its_attack():
	var fight := await _fight(7, false, 1.0)
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist_animation: AnimationPlayer = fight[5]
	var attack_started := -1
	var attack_ended := -1
	var turn_ended := -1
	for tick in 8 * PHYSICS_FPS:
		await get_tree().physics_frame
		if attack_started < 0 and cultist_animation.current_animation == "attack":
			attack_started = tick
		if attack_started >= 0 and attack_ended < 0 and cultist_animation.current_animation != "attack":
			attack_ended = tick
		if controller.active == body or not controller.running:
			turn_ended = tick
			break
	assert_gte(attack_started, 0, "the cultist attacked on its turn")
	assert_gte(turn_ended, 0, "its turn ended within 8 s")
	if attack_started >= 0 and turn_ended >= 0:
		assert_true(attack_ended >= 0 and turn_ended >= attack_ended, "its turn ended only after its attack finished (attack ended at tick %d, turn at %d)" % [attack_ended, turn_ended])
