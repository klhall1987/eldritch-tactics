extends GutTest
# The cultist takes its own turn (ticket #50): on its turn it shambles towards the detective along a
# path (around walls and props), up to its 6 m of movement, stopping at reach; it attacks him if it
# ends within reach (#48's rules), and then its turn ends by itself. A defeated cultist is skipped.
#
# Interface these tests choose, on the main scene's `CombatController` (#45-#49): nothing new to
# call. The cultist's turn plays out by itself once it starts; these tests watch `turn_started`,
# `attack_resolved`, the cultist's position and its AnimationPlayer. Its turn may begin with a short
# pause, but the whole turn takes no more than TURN_SECONDS.

const PHYSICS_FPS := 60
const TURN_SECONDS := 8.0  # "within a few seconds of play"
const DETECTIVE_RADIUS := 0.25  # his capsule (#29)
const REACH := 1.5  # between the bodies' edges (#48)
# Either side of the prop against the east side of the room: the straight line between them runs
# through it (as in #47's tests).
const SOUTH_OF_PROP := Vector3(3.0, 0, 1.4)
const NORTH_OF_PROP := Vector3(3.0, 0, -2.2)
# Opposite corners of the room: more than 6 m apart along any path.
const WEST_CORNER := Vector3(-3.3, 0, 1.2)
const EAST_CORNER := Vector3(3.6, 0, -2.3)
const CLEAR := Vector3(-1.2, 0, 0.6)  # clear floor

var _window: SubViewport
var _turns := []  # every combatant named by turn_started, in order
var _attacks := []  # every attack_resolved result, in order


func before_each():
	_turns = []
	_attacks = []


func after_each():
	_window = null


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


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


# The gap between the detective's and the cultist's bodies, edge to edge, seen from above.
func _gap(body: Node3D, cultist: Node3D, cultist_radius: float) -> float:
	return _flat(body.global_position).distance_to(_flat(cultist.global_position)) - DETECTIVE_RADIUS - cultist_radius


# The footprints (seen from above) of the room's collision boxes (#29).
func _blockers(main: Node) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for shape: CollisionShape3D in main.find_child("RoomCollision", true, false).find_children("*", "CollisionShape3D", true, false):
		if shape.shape is BoxShape3D:
			var size: Vector3 = shape.shape.size
			rects.append(Rect2(shape.global_position.x - size.x / 2, shape.global_position.z - size.z / 2, size.x, size.z))
	return rects


func _blocked(rects: Array[Rect2], point: Vector3) -> bool:
	for rect in rects:
		if rect.has_point(_flat(point)):
			return true
	return false


# The main scene with the detective at `detective_at` and the cultist at `cultist_at`, in combat,
# with the signals these tests watch connected, on the detective's turn (so the cultist hasn't moved
# yet). Returns [main, controller, body, cultist], or [] (after failing).
func _combat(detective_at: Vector3, cultist_at: Vector3, seed_value := 50) -> Array:
	var main := await _main()
	if main == null:
		return []
	var controller := main.find_child("CombatController", true, false)
	assert_not_null(controller, "the main scene has CombatController")
	var body := _body(main)
	var cultist := main.find_child("Cultist", true, false) as Node3D
	if controller == null or body == null or cultist == null:
		return []
	controller.turn_started.connect(func(combatant): _turns.append(combatant))
	controller.attack_resolved.connect(func(result): _attacks.append(result))
	body.global_position = detective_at
	body.velocity = Vector3.ZERO
	body.controllable = false  # as when an encounter starts (#31)
	cultist.global_position = cultist_at
	controller.rng.seed = seed_value
	controller.start_combat([body, cultist])
	# If the cultist won initiative, its first turn is already under way: start again until the
	# detective goes first, so every test begins on his turn with the cultist untouched.
	for attempt in 50:
		if controller.active == body:
			break
		controller.rng.seed = seed_value + attempt + 1
		cultist.global_position = cultist_at
		controller.start_combat([body, cultist])
	assert_eq(controller.active, body, "the fight starts on the detective's turn")
	_turns = []
	_attacks = []
	await wait_physics_frames(2)
	return [main, controller, body, cultist]


# Hands the turn to the cultist and waits (up to TURN_SECONDS) for its turn to end, recording where
# it walked. Returns how many seconds its turn took (more than TURN_SECONDS if it never ended).
func _play_cultist_turn(controller: Node, cultist: Node3D, track: Array, animations := []) -> float:
	var player := cultist.find_children("*", "AnimationPlayer", true, false)
	controller.end_turn()
	assert_eq(controller.active, cultist, "it's the cultist's turn")
	track.append(cultist.global_position)
	for tick in int(TURN_SECONDS * PHYSICS_FPS) + 1:
		await get_tree().physics_frame
		track.append(cultist.global_position)
		if not player.is_empty():
			animations.append(player[0].current_animation)
		if controller.active != cultist or not controller.running:
			return float(tick + 1) / PHYSICS_FPS
	return TURN_SECONDS + 1.0


func _walked(track: Array) -> float:
	var total := 0.0
	for i in range(1, track.size()):
		total += _flat(track[i]).distance_to(_flat(track[i - 1]))
	return total


# Given it's the cultist's turn and the detective is out of its reach, when its turn plays out, then
# it walks towards him along a path that avoids walls and props, no further than its movement (6 m),
# stopping at reach rather than walking into him.
func test_cultist_walks_towards_him_around_props_and_stops_at_reach():
	var fight := await _combat(SOUTH_OF_PROP, NORTH_OF_PROP)
	if fight.is_empty():
		return
	var main: Node3D = fight[0]
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	var radius := _body_radius(cultist)
	var blockers := _blockers(main)
	assert_true(_blocked(blockers, (SOUTH_OF_PROP + NORTH_OF_PROP) / 2.0), "a prop stands between them")
	assert_gt(_gap(body, cultist, radius), REACH, "he starts out of its reach")
	var track := []
	var animations := []
	await _play_cultist_turn(controller, cultist, track, animations)
	for point: Vector3 in track:
		assert_false(_blocked(blockers, point), "it never walks into a wall or prop (at %s)" % point)
		if _blocked(blockers, point):
			break
	var walked := _walked(track)
	assert_gt(walked, 1.0, "it walked towards him (%.2f m)" % walked)
	assert_lte(walked, 6.1, "no further than its 6 m of movement (%.2f m)" % walked)
	var gap := _gap(body, cultist, radius)
	assert_lte(gap, REACH, "it ends within reach of him (%.2f m between them)" % gap)
	assert_gte(gap, 0.5, "it stops at reach rather than walking into him (%.2f m between them)" % gap)
	assert_has(animations, "walk", "it plays walk on the way")

	# Too far to reach in one turn: it walks its full movement towards him and stops there.
	fight = await _combat(WEST_CORNER, EAST_CORNER)
	if fight.is_empty():
		return
	controller = fight[1]
	body = fight[2]
	cultist = fight[3]
	var start_distance := _flat(body.global_position).distance_to(_flat(cultist.global_position))
	track = []
	await _play_cultist_turn(controller, cultist, track)
	walked = _walked(track)
	assert_between(walked, 5.0, 6.1, "it uses its movement, and no more (%.2f m)" % walked)
	var closer := start_distance - _flat(body.global_position).distance_to(_flat(cultist.global_position))
	assert_gt(closer, 4.0, "it ends much closer to him (%.2f m closer)" % closer)
	var ended_in_reach := _gap(body, cultist, _body_radius(cultist)) <= REACH
	assert_eq(_attacks.size(), 1 if ended_in_reach else 0, "it attacks if and only if it ended within reach")


# Given the cultist ends its movement within reach (1.5 m between their bodies' edges), when its
# turn continues, then it attacks the detective with the attack rules from #48 (since #120, a pool of
# 4 d6 against his defence 2, 1 damage plus the successes beyond it).
func test_cultist_attacks_when_in_reach():
	# It walks up first (about 3 m of clear floor), then attacks.
	var fight := await _combat(CLEAR, CLEAR + Vector3(3.0, 0, 0))
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	var track := []
	await _play_cultist_turn(controller, cultist, track)
	assert_gt(_walked(track), 0.5, "it walked up to him first")
	assert_eq(_attacks.size(), 1, "it attacks once")
	if _attacks.is_empty():
		return
	var result: Dictionary = _attacks[0]
	assert_eq(result.get("attacker"), cultist, "the cultist attacks")
	assert_eq(result.get("target"), body, "the detective is attacked")
	# (The d20 check below was rewritten for the d6 pool by #120, as its ticket says: 4 dice against his
	# defence 2, its mandibles' 1 damage plus the successes beyond his defence.)
	var dice: Array = result.get("dice", [])
	assert_eq(dice.size(), 4, "a pool of 4 d6")
	var successes := 0
	var sixes := 0
	for die: int in dice:
		if die >= 4:
			successes += 1
		if die == 6:
			sixes += 1
	successes += (sixes / 2) * 2
	var should_hit := successes > 0 and successes >= 2
	assert_eq(result.get("hit"), should_hit, "%d successes against his defence 2" % successes)
	if should_hit:
		assert_eq(result.get("damage"), maxi(1, 1 + successes - 2), "1 + the successes beyond his defence")
		assert_eq(controller.hit_points.get(body), 20 - int(result.get("damage")), "the hit lands on his hit points")

	# Already within reach: it attacks without walking.
	fight = await _combat(CLEAR, CLEAR + Vector3(1.4, 0, 0))
	if fight.is_empty():
		return
	controller = fight[1]
	cultist = fight[3]
	track = []
	await _play_cultist_turn(controller, cultist, track)
	assert_lt(_walked(track), 0.05, "already within reach, it doesn't walk")
	assert_eq(_attacks.size(), 1, "it attacks")


# Given the cultist has moved and attacked, or can't reach the detective at all, when it's done, then
# its turn ends by itself and the next combatant's turn starts, within a few seconds of play.
func test_cultist_turn_ends_by_itself():
	var fight := await _combat(CLEAR, CLEAR + Vector3(3.0, 0, 0))
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	var round_before: int = controller.round
	var seconds := await _play_cultist_turn(controller, cultist, [])
	assert_lte(seconds, TURN_SECONDS, "its turn ends by itself within %.0f s (%.1f s)" % [TURN_SECONDS, seconds])
	if controller.running:
		assert_eq(controller.active, body, "the detective's turn starts next")
		assert_eq(_turns, [cultist, body], "turn_started named the cultist, then the detective")
		assert_eq(controller.round, round_before + 1, "after the cultist (last in the order) a new round begins")

	# It can't reach him at all this turn (no movement left): its turn still ends, without an attack.
	fight = await _combat(WEST_CORNER, EAST_CORNER)
	if fight.is_empty():
		return
	controller = fight[1]
	body = fight[2]
	cultist = fight[3]
	controller.turn_started.connect(func(combatant):
		if combatant == cultist:
			controller.movement_left = 0.0)
	var track := []
	seconds = await _play_cultist_turn(controller, cultist, track)
	assert_lte(seconds, TURN_SECONDS, "its turn ends by itself within %.0f s (%.1f s)" % [TURN_SECONDS, seconds])
	assert_eq(controller.active, body, "the detective's turn starts next")
	assert_lt(_walked(track), 0.05, "with no movement, it doesn't walk")
	assert_eq(_attacks, [], "out of reach, it doesn't attack")


# Given the cultist is defeated, when its turn would come, then it's skipped.
func test_defeated_cultist_is_skipped():
	var fight := await _combat(CLEAR, CLEAR + Vector3(1.4, 0, 0))
	if fight.is_empty():
		return
	var main: Node3D = fight[0]
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	# A second cultist far away, so the fight goes on after the first falls.
	var second := cultist.duplicate() as Node3D
	main.add_child(second)
	second.global_position = EAST_CORNER
	controller.rng.seed = 5050
	controller.start_combat([body, cultist, second])
	for attempt in 50:
		if controller.active == body:
			break
		controller.rng.seed = 5051 + attempt
		controller.start_combat([body, cultist, second])
	assert_eq(controller.active, body, "the fight starts on the detective's turn")
	controller.apply_damage(cultist, 100)
	assert_true(controller.is_defeated(cultist), "the first cultist is defeated")
	assert_true(controller.running, "the fight goes on")
	var held_at := cultist.global_position
	_turns = []
	_attacks = []
	# Two rounds: the detective ends his turns; the second cultist plays its own.
	for round_number in 2:
		controller.end_turn()
		for tick in int(TURN_SECONDS * PHYSICS_FPS):
			await get_tree().physics_frame
			if controller.active == body or not controller.running:
				break
		assert_eq(controller.active, body, "play comes back round to the detective")
	assert_false(_turns.has(cultist), "the defeated cultist's turn never comes")
	assert_true(_turns.has(second), "the other cultist takes its turns")
	assert_lt(_flat(cultist.global_position).distance_to(_flat(held_at)), 0.01, "the defeated cultist doesn't move")
	for result: Dictionary in _attacks:
		assert_ne(result.get("attacker"), cultist, "the defeated cultist never attacks")
