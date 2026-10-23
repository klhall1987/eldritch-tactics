extends GutTest
# The detective's collision (ticket #29): walls, the garage's props and the open edges of the room
# stop him, so he can only walk around the clear floor; against a wall he slides rather than sticks.
#
# Each test drives the real movement (the input actions from #28) and starts the detective at a
# measured point by moving his physics body (the CharacterBody3D that carries the Detective).

const PHYSICS_FPS := 60
const ACTIONS := ["move_up", "move_down", "move_left", "move_right"]
# Screen directions are diagonal in the world (#28); pairs of them walk along the world axes.
const WALK_MINUS_X := ["move_up", "move_left"]
const WALK_PLUS_X := ["move_down", "move_right"]
const WALK_MINUS_Z := ["move_up", "move_right"]
const WALK_PLUS_Z := ["move_down", "move_left"]


func after_each():
	_release()


func _release() -> void:
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


# The physics body that carries the Detective (from #28), or null (after failing the test).
func _body(main: Node) -> CharacterBody3D:
	var detective := main.find_child("Character", true, false)
	assert_not_null(detective, "the main scene has the Character")
	var node := detective
	while node != null and not node is CharacterBody3D:
		node = node.get_parent()
	assert_not_null(node, "the Character is carried by a CharacterBody3D")
	return node as CharacterBody3D


# The world bounds, seen from above, of every mesh under `node` (rest pose).
func _bounds(node: Node) -> AABB:
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in meshes:
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _overlap_from_above(a: AABB, b: AABB) -> bool:
	return a.position.x < b.end.x and b.position.x < a.end.x and a.position.z < b.end.z and b.position.z < a.end.z


# How far a point is from a box, seen from above (0 if it's inside).
func _distance_from_above(point: Vector3, box: AABB) -> float:
	var dx := maxf(maxf(box.position.x - point.x, point.x - box.end.x), 0.0)
	var dz := maxf(maxf(box.position.z - point.z, point.z - box.end.z), 0.0)
	return Vector2(dx, dz).length()


func _place(body: CharacterBody3D, at: Vector3) -> void:
	body.global_position = at
	body.velocity = Vector3.ZERO


func _press(actions: Array) -> void:
	for action: String in actions:
		assert_true(InputMap.has_action(action), "the input map has %s" % action)
		if InputMap.has_action(action):
			Input.action_press(action)


# Given the game is running, when the detective walks towards each of the room's four edges (the
# two back walls and the two open camera sides) for 6 seconds, then he never leaves the garage
# floor's footprint, and ends within 0.6 m of that edge.
func test_room_edges_keep_him_on_the_floor():
	var main := await _main()
	if main == null:
		return
	var body := _body(main)
	var floor_node := main.find_child("floor", true, false)
	assert_not_null(floor_node, "the garage has its floor")
	if body == null or floor_node == null:
		return
	var footprint := _bounds(floor_node)
	# [edge name, start (on a lane clear of furniture), keys, the edge's coordinate, axis]
	var edges := [
		["back wall (-X)", Vector3(-1.0, 0, 1.2), WALK_MINUS_X, footprint.position.x, "x"],
		# (-Z: to the garage door, clear of the stairs, agreed on #165.)
		["back wall (-Z)", Vector3(2.2, 0, 0.0), WALK_MINUS_Z, footprint.position.z, "z"],
		["open side (+X)", Vector3(1.0, 0, 1.5), WALK_PLUS_X, footprint.end.x, "x"],
		["open side (+Z)", Vector3(0.5, 0, 0.0), WALK_PLUS_Z, footprint.end.z, "z"],
	]
	for edge in edges:
		_place(body, edge[1])
		await wait_physics_frames(2)
		_press(edge[2])
		var left_floor := false
		for tick in 6 * PHYSICS_FPS:
			await get_tree().physics_frame
			var at := body.global_position
			if at.x < footprint.position.x or at.x > footprint.end.x or at.z < footprint.position.z or at.z > footprint.end.z:
				left_floor = true
		_release()
		assert_false(left_floor, "walking at the %s, he never leaves the floor" % edge[0])
		var coordinate: float = body.global_position.x if edge[4] == "x" else body.global_position.z
		var gap := absf(coordinate - float(edge[3]))
		assert_lte(gap, 0.6, "he ends within 0.6 m of the %s (%.2f m)" % [edge[0], gap])


# Given the detective stands in front of a garage prop (workbench, couch, shelves, fridge, mattress
# or garage_door), when he walks straight at it for 4 seconds, then his body never overlaps the
# prop's bounds (seen from above), and he ends within 0.4 m of it.
func test_props_block_him():
	var main := await _main()
	if main == null:
		return
	var body := _body(main)
	var garage := main.find_child("Garage", true, false)
	var detective := main.find_child("Character", true, false)
	assert_not_null(garage, "the main scene has the Garage")
	if body == null or garage == null or detective == null:
		return
	# [prop, start (with a clear straight run at the prop), keys]. The fridge is boxed in by the
	# workbench and the shelves, so he reaches it through the gap between them.
	var approaches := [
		["workbench", Vector3(-1.5, 0, -0.6), WALK_MINUS_X],
		["couch", Vector3(1.0, 0, -0.4), WALK_PLUS_X],
		["shelves", Vector3(-2.2, 0, -0.8), WALK_MINUS_Z],
		["fridge", Vector3(-1.5, 0, -2.0), WALK_MINUS_X],
		["mattress", Vector3(0.0, 0, 2.4), WALK_MINUS_X],
		["garage_door", Vector3(1.6, 0, -0.8), WALK_MINUS_Z],
	]
	for approach in approaches:
		var prop := garage.find_child(approach[0], true, false)
		assert_not_null(prop, "the garage has its %s" % approach[0])
		if prop == null:
			continue
		var prop_box := _bounds(prop)
		_place(body, approach[1])
		await wait_physics_frames(2)
		_press(approach[2])
		var overlapped := false
		for tick in 4 * PHYSICS_FPS:
			await get_tree().physics_frame
			if _overlap_from_above(_bounds(detective), prop_box):
				overlapped = true
		_release()
		assert_false(overlapped, "walking at the %s, his body never overlaps it" % approach[0])
		var gap := _distance_from_above(body.global_position, prop_box)
		assert_lte(gap, 0.4, "he ends within 0.4 m of the %s (%.2f m)" % [approach[0], gap])


# Given the detective is pressed against a wall, when he walks diagonally along it, then he slides
# along it (still moves at least 1 m in 1 second) rather than sticking.
func test_he_slides_along_walls():
	var main := await _main()
	if main == null:
		return
	var body := _body(main)
	if body == null:
		return
	# Press him against the back wall (-Z) at the garage door, clear of the stairs (agreed on #165).
	_place(body, Vector3(3.0, 0, -1.5))
	await wait_physics_frames(2)
	_press(WALK_MINUS_Z)
	await wait_physics_frames(PHYSICS_FPS)
	_release()
	var against_wall := body.global_position
	assert_lt(against_wall.z, -2.2, "he has reached the back wall (z %.2f)" % against_wall.z)
	# Walk up-screen: diagonally into the wall and along it (towards -X).
	_press(["move_up"])
	await wait_physics_frames(PHYSICS_FPS)
	_release()
	var along := absf(body.global_position.x - against_wall.x)
	assert_gte(along, 1.0, "he slides at least 1 m along the wall in a second (%.2f m)" % along)
	assert_lt(body.global_position.z, -2.2, "he stays against the wall while sliding")


# Given the room's collision, when the open camera sides are inspected, then their barriers are
# invisible: no new mesh is drawn there, and the room still looks as before.
func test_barriers_are_invisible():
	var main := await _main()
	if main == null:
		return
	var expected := []  # every mesh comes from the garage or the two characters
	for owner_name in ["Garage", "Character", "Cultist"]:
		var node := main.find_child(owner_name, true, false)
		assert_not_null(node, "the main scene has %s" % owner_name)
		if node != null:
			expected.append_array(node.find_children("*", "MeshInstance3D", true, false))
	assert_gt(expected.size(), 0, "the garage and characters have meshes")
	var extra := []
	for mi: MeshInstance3D in main.find_children("*", "MeshInstance3D", true, false):
		if not mi in expected and mi.is_visible_in_tree():
			extra.append(String(main.get_path_to(mi)))
	assert_eq(extra, [], "no meshes are drawn besides the garage and the characters")
	# And the room's collision exists: at least one static body for walls, props and edges.
	assert_gt(main.find_children("*", "StaticBody3D", true, false).size(), 0, "the room has static collision bodies")
