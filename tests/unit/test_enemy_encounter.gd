extends GutTest
# Bumping into an enemy (ticket #31): the cultist is an enemy with a touch area; walking the
# detective into it starts an encounter once and stops his movement.
#
# The main scene announces the encounter with `encounter_started(enemy)`. Since #45, combat then
# starts in place (test_overworld_combat.gd) instead of switching to the combat screen.

const ACTIONS := ["move_up", "move_down", "move_left", "move_right"]
const WALK_MINUS_Z := ["move_up", "move_right"]  # screen up+right walks along world -Z (#28)

var _encounters := []  # [enemy, gap in metres when it started] for each encounter_started


func before_each():
	_encounters = []


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


func _node(main: Node, node_name: String) -> Node3D:
	var node := main.find_child(node_name, true, false) as Node3D
	assert_not_null(node, "the main scene has %s" % node_name)
	return node


# The physics body that carries the Detective (#28).
func _body(main: Node) -> CharacterBody3D:
	var node := main.find_child("Detective", true, false)
	while node != null and not node is CharacterBody3D:
		node = node.get_parent()
	assert_not_null(node, "the Detective is carried by a CharacterBody3D")
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


# How far a collision shape reaches sideways from its centre (its smallest horizontal radius).
func _shape_reach(shape: Shape3D) -> float:
	if shape is SphereShape3D:
		return shape.radius
	if shape is CylinderShape3D:
		return shape.radius
	if shape is CapsuleShape3D:
		return shape.radius
	if shape is BoxShape3D:
		return minf(shape.size.x, shape.size.z) / 2.0
	return 0.0


func _detective_radius(body: CharacterBody3D) -> float:
	for shape: CollisionShape3D in body.find_children("*", "CollisionShape3D", false, false):
		return _shape_reach(shape.shape)
	return 0.0


# The gap between the detective's and the cultist's bodies, seen from above.
func _gap(body: CharacterBody3D, cultist: Node3D) -> float:
	var centres := Vector2(body.global_position.x - cultist.global_position.x, body.global_position.z - cultist.global_position.z).length()
	return centres - _detective_radius(body) - _body_radius(cultist)


# Puts the detective 2 m (between centres) in front of the cultist, ready to walk at it along -Z,
# and records every encounter (with the gap at that moment).
func _approach(main: Node3D, body: CharacterBody3D, cultist: Node3D) -> void:
	if main.has_signal("encounter_started"):
		main.encounter_started.connect(func(enemy): _encounters.append([enemy, _gap(body, cultist)]))
	body.global_position = cultist.global_position + Vector3(0, 0, 2.0)
	body.velocity = Vector3.ZERO
	await wait_physics_frames(2)


func _press(actions: Array) -> void:
	for action: String in actions:
		if InputMap.has_action(action):
			Input.action_press(action)


# Given the garage scene, when its nodes are inspected, then the cultist is in the enemies group and
# has a touch area around it, reaching 0.2-0.5 m beyond its body.
func test_cultist_is_an_enemy_with_a_touch_area():
	var main := await _main()
	if main == null:
		return
	var cultist := _node(main, "Cultist")
	if cultist == null:
		return
	assert_true(cultist.is_in_group("enemies"), "the cultist is in the enemies group")
	var areas := cultist.find_children("*", "Area3D", true, false)
	assert_eq(areas.size(), 1, "the cultist has one touch area (Area3D)")
	if areas.is_empty():
		return
	var shapes := (areas[0] as Node).find_children("*", "CollisionShape3D", true, false)
	assert_gt(shapes.size(), 0, "the touch area has a collision shape")
	if shapes.is_empty():
		return
	var shape := shapes[0] as CollisionShape3D
	var reach := _shape_reach(shape.shape)
	var offset := Vector2(shape.global_position.x - cultist.global_position.x, shape.global_position.z - cultist.global_position.z).length()
	var beyond := reach - offset - _body_radius(cultist)
	assert_between(beyond, 0.2, 0.5, "the touch area reaches 0.2-0.5 m beyond the cultist's body (%.2f m)" % beyond)


# Given the detective is walking towards the cultist, when he touches its touch area, then an
# encounter starts exactly once, naming that cultist as the enemy, and it does not start while he
# is still more than 0.5 m away.
func test_bumping_into_the_cultist_starts_one_encounter():
	var main := await _main()
	if main == null:
		return
	assert_true(main.has_signal("encounter_started"), "the main scene has an encounter_started signal")
	var body := _body(main)
	var cultist := _node(main, "Cultist")
	if body == null or cultist == null:
		return
	await wait_physics_frames(10)
	assert_eq(_encounters.size(), 0, "no encounter is running at the start of the game")
	await _approach(main, body, cultist)
	_press(WALK_MINUS_Z)
	await wait_physics_frames(120)  # long enough to walk the 2 m and keep pushing into him
	assert_eq(_encounters.size(), 1, "exactly one encounter starts")
	if _encounters.is_empty():
		return
	assert_eq(_encounters[0][0], cultist, "the encounter names the cultist as the enemy")
	assert_lte(_encounters[0][1], 0.5, "it starts only once he's within 0.5 m (gap %.2f m)" % _encounters[0][1])


# Given an encounter has started, when the movement keys are held, then the detective no longer
# moves.
func test_movement_stops_once_the_encounter_starts():
	var main := await _main()
	if main == null:
		return
	var body := _body(main)
	var cultist := _node(main, "Cultist")
	if body == null or cultist == null:
		return
	await _approach(main, body, cultist)
	_press(WALK_MINUS_Z)
	for tick in 120:
		await get_tree().physics_frame
		if not _encounters.is_empty():
			break
	assert_eq(_encounters.size(), 1, "the encounter has started")
	await wait_physics_frames(2)
	var held_at := body.global_position
	await wait_physics_frames(30)  # still holding the keys
	var moved := body.global_position.distance_to(held_at)
	assert_lt(moved, 0.01, "he doesn't move once the encounter has started (moved %.3f m)" % moved)

