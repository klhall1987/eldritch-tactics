extends GutTest
# Hit points, defeat and the end of combat (ticket #49): a hit takes that many hit points off the
# target. At 0 a combatant is defeated and out of the fight; when no enemies are left, combat ends in
# victory and the detective walks freely again. If the detective drops to 0, combat ends in defeat.
#
# Interface these tests choose, on the main scene's `CombatController` (#45-#48):
# - `hit_points` (combatant -> current hit points), set when combat starts from each combatant's
#   maximum, `max_hit_points(c)` (node metadata `max_hit_points`).
# - `apply_damage(target, amount)`; `attack()` applies its damage on a hit.
#   `hit_points_changed(combatant, hit_points)` reports each change.
# - `is_defeated(c)`. Defeated combatants leave `turn_order`.
# - `victory` and `defeat` signals when combat ends; `running` goes false.

const ACTIONS := ["move_up", "move_down", "move_left", "move_right"]
const WALK_MINUS_Z := ["move_up", "move_right"]  # screen up+right walks along world -Z (#28)
const START := Vector3(-1.2, 0, 0.6)  # clear floor

var _window: SubViewport
var _changes := []  # [combatant, hit points] for each hit_points_changed
var _ends := []  # "victory" or "defeat", for each end of combat


func before_each():
	_changes = []
	_ends = []


func after_each():
	_window = null
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			Input.action_release(action)


# Instantiates the main scene inside a viewport the size of the project's default window.
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
	var node := main.find_child("Detective", true, false)
	while node != null and not node is CharacterBody3D:
		node = node.get_parent()
	assert_not_null(node, "the Detective is carried by a CharacterBody3D")
	return node as CharacterBody3D


# The main scene with its controller, the detective's body and the cultist, the signals these tests
# watch connected. Returns [main, controller, body, cultist], or [] (after failing).
func _scene() -> Array:
	var main := await _main()
	if main == null:
		return []
	var controller := main.find_child("CombatController", true, false)
	assert_not_null(controller, "the main scene has CombatController")
	var body := _body(main)
	var cultist := main.find_child("Cultist", true, false) as Node3D
	if controller == null or body == null or cultist == null:
		return []
	for method in ["apply_damage", "max_hit_points", "is_defeated", "attack", "can_attack"]:
		assert_true(controller.has_method(method), "CombatController has %s()" % method)
		if not controller.has_method(method):
			return []
	for sig in ["hit_points_changed", "victory", "defeat"]:
		assert_true(controller.has_signal(sig), "CombatController has a %s signal" % sig)
		if not controller.has_signal(sig):
			return []
	controller.hit_points_changed.connect(func(combatant, hp): _changes.append([combatant, hp]))
	controller.victory.connect(func(): _ends.append("victory"))
	controller.defeat.connect(func(): _ends.append("defeat"))
	return [main, controller, body, cultist]


# Combat between `fighters` with fixed dice, on the detective's turn.
func _start(controller: Node, body: CharacterBody3D, fighters: Array) -> void:
	body.controllable = false  # as when an encounter starts (#31)
	controller.rng.seed = 49
	controller.start_combat(fighters)
	for i in fighters.size():
		if controller.active == body:
			break
		controller.end_turn()


func _press(actions: Array) -> void:
	for action: String in actions:
		if InputMap.has_action(action):
			Input.action_press(action)


func _release(actions: Array) -> void:
	for action: String in actions:
		if InputMap.has_action(action):
			Input.action_release(action)


# Attacks `target` until a hit lands (the seeded dice), returning that attack's result.
func _hit(controller: Node, attacker: Node3D, target: Node3D) -> Dictionary:
	for i in 100:
		var result: Dictionary = controller.attack(attacker, target)
		if result.get("hit"):
			return result
	fail_test("no hit in 100 attacks")
	return {}


# Given combat starts, when hit points are checked, then the detective has 20 and the cultist 12, and
# each has that as their maximum.
func test_combatants_start_at_full_hit_points():
	var scene := await _scene()
	if scene.is_empty():
		return
	var controller: Node = scene[1]
	var body: CharacterBody3D = scene[2]
	var cultist: Node3D = scene[3]
	_start(controller, body, [body, cultist])
	assert_eq(controller.max_hit_points(body), 20, "the detective's maximum is 20")
	assert_eq(controller.max_hit_points(cultist), 12, "the cultist's maximum is 12")
	assert_eq(controller.hit_points.get(body), 20, "the detective starts with 20")
	assert_eq(controller.hit_points.get(cultist), 12, "the cultist starts with 12")


# Given an attack hits, when its damage is applied, then the target's hit points go down by that
# much, never below 0, and a hit-points-changed signal reports the new value.
func test_hits_take_off_hit_points():
	var scene := await _scene()
	if scene.is_empty():
		return
	var controller: Node = scene[1]
	var body: CharacterBody3D = scene[2]
	var cultist: Node3D = scene[3]
	_start(controller, body, [body, cultist])
	var result := _hit(controller, body, cultist)
	if result.is_empty():
		return
	var damage: int = result.get("damage")
	assert_gt(damage, 0, "a hit deals damage")
	assert_eq(controller.hit_points.get(cultist), 12 - damage, "the cultist loses the %d damage" % damage)
	assert_eq(_changes, [[cultist, 12 - damage]], "hit_points_changed reports the cultist's new hit points")
	var misses_before: int = controller.hit_points.get(cultist)
	_changes = []
	for i in 100:
		var miss: Dictionary = controller.attack(body, cultist)
		if not miss.get("hit"):
			break
		misses_before = controller.hit_points.get(cultist)
		_changes = []
	assert_eq(controller.hit_points.get(cultist), misses_before, "a miss takes nothing off")
	assert_eq(_changes, [], "a miss changes nothing")

	controller.apply_damage(body, 100)
	assert_eq(controller.hit_points.get(body), 0, "hit points never go below 0")
	assert_eq(_changes[-1] if not _changes.is_empty() else [], [body, 0], "hit_points_changed reports 0")


# Given a combatant reaches 0 hit points, when that happens, then they are defeated: they leave the
# turn order, and a defeated combatant can't be attacked or take turns.
func test_zero_hit_points_is_defeat():
	var scene := await _scene()
	if scene.is_empty():
		return
	var main: Node3D = scene[0]
	var controller: Node = scene[1]
	var body: CharacterBody3D = scene[2]
	var cultist: Node3D = scene[3]
	# A second cultist, so the fight goes on after the first falls.
	var second := cultist.duplicate() as Node3D
	main.add_child(second)
	second.global_position = cultist.global_position + Vector3(1.5, 0, 0)
	cultist.global_position = body.global_position + Vector3(1.0, 0, 0)  # well within reach
	_start(controller, body, [body, cultist, second])
	assert_eq(controller.turn_order.size(), 3, "three combatants in the turn order")
	assert_false(controller.is_defeated(cultist), "the cultist isn't defeated at full hit points")
	controller.apply_damage(cultist, 12)
	assert_true(controller.is_defeated(cultist), "at 0 hit points the cultist is defeated")
	assert_false(controller.turn_order.has(cultist), "it leaves the turn order")
	assert_eq(controller.turn_order.size(), 2, "the others stay in the turn order")
	assert_true(controller.running, "with another enemy standing, combat goes on")
	assert_eq(controller.active, body, "it's still the detective's turn")
	assert_eq(controller.actions_left, 1, "he still has his action")
	assert_false(controller.can_attack(body, cultist), "a defeated cultist can't be attacked")
	var seen := {}
	for i in 6:
		controller.end_turn()
		seen[controller.active] = true
	assert_false(seen.has(cultist), "a defeated cultist never takes a turn")
	assert_true(seen.has(second) and seen.has(body), "the others keep taking turns")


# Given the last enemy is defeated, when the attack resolves, then combat ends with a victory signal,
# the detective's free movement (WASD) works again, and bumping into a defeated enemy doesn't start
# another fight.
func test_defeating_the_last_enemy_wins():
	var scene := await _scene()
	if scene.is_empty():
		return
	var main: Node3D = scene[0]
	var controller: Node = scene[1]
	var body: CharacterBody3D = scene[2]
	var cultist: Node3D = scene[3]
	body.global_position = START
	_start(controller, body, [body, cultist])
	controller.hit_points[cultist] = 1
	var result := _hit(controller, body, cultist)
	if result.is_empty():
		return
	assert_true(controller.is_defeated(cultist), "the cultist is defeated")
	assert_eq(_ends, ["victory"], "combat ends with one victory signal")
	assert_false(controller.running, "combat is over")
	await wait_physics_frames(2)

	var held_at := body.global_position
	_press(["move_up"])
	await wait_physics_frames(30)
	_release(["move_up"])
	var moved := Vector2(body.global_position.x - held_at.x, body.global_position.z - held_at.z).length()
	assert_gt(moved, 0.5, "WASD moves him again (%.2f m in half a second)" % moved)

	var encounters := []
	if main.has_signal("encounter_started"):
		main.encounter_started.connect(func(enemy): encounters.append(enemy))
	body.global_position = cultist.global_position + Vector3(0, 0, 2.0)
	body.velocity = Vector3.ZERO
	await wait_physics_frames(2)
	_press(WALK_MINUS_Z)
	await wait_physics_frames(120)
	_release(WALK_MINUS_Z)
	assert_eq(encounters, [], "bumping into the defeated cultist doesn't start an encounter")
	assert_false(controller.running, "no new fight starts")
	assert_eq(_ends, ["victory"], "nothing else ends")


# Given the detective is defeated, when that happens, then combat ends with a defeat signal and he
# can't move.
func test_the_detective_falling_is_defeat():
	var scene := await _scene()
	if scene.is_empty():
		return
	var controller: Node = scene[1]
	var body: CharacterBody3D = scene[2]
	var cultist: Node3D = scene[3]
	body.global_position = START
	_start(controller, body, [body, cultist])
	controller.end_turn()
	assert_eq(controller.active, cultist, "it's the cultist's turn")
	controller.hit_points[body] = 1
	var result := _hit(controller, cultist, body)
	if result.is_empty():
		return
	assert_true(controller.is_defeated(body), "the detective is defeated")
	assert_eq(_ends, ["defeat"], "combat ends with one defeat signal")
	assert_false(controller.running, "combat is over")
	await wait_physics_frames(2)
	var held_at := body.global_position
	_press(["move_up"])
	await wait_physics_frames(30)
	_release(["move_up"])
	var moved := Vector2(body.global_position.x - held_at.x, body.global_position.z - held_at.z).length()
	assert_lt(moved, 0.01, "he can't move (moved %.3f m)" % moved)
