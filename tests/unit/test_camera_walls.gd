extends GutTest
# Back walls hide when the camera is behind them (ticket #169): while the camera looks at one of the
# garage's back walls from outside, that wall (with its doors and window) is hidden, and it shows again
# when the camera turns back in front of it; its collision stays.
#
# Interface these tests choose (building on test_camera_turn.gd, #167):
# - The camera is turned by holding `camera_turn_left` a second at a time (about 90 degrees each).
# - "Looks at a wall from outside": the camera's flat view direction points towards +X (`wall_west`)
#   or +Z (`wall_north`). The camera only ever sits about 45 degrees off those axes here, so each
#   check is clear-cut.
# - A wall is "hidden" when none of the meshes under its part is visible in the tree, and "shown" when
#   all of them are.
# - Its collision is RoomCollision's boxes: the same number of them, one still covering the wall's
#   middle.

const FPS := 60


func after_each():
	if InputMap.has_action("camera_turn_left"):
		Input.action_release("camera_turn_left")


func _main() -> Node3D:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the main scene (%s) loads" % path)
	if packed == null:
		return null
	var main := packed.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	return main as Node3D


func _camera(main: Node) -> Camera3D:
	var cameras := main.find_children("*", "Camera3D", true, false)
	assert_eq(cameras.size(), 1, "the main scene has one Camera3D")
	return cameras[0] if cameras.size() > 0 else null


func _meshes(node: Node) -> Array:
	return node.find_children("*", "MeshInstance3D", true, false)


# [shown, hidden] counts of the wall's meshes.
func _shown(wall: Node) -> Array:
	var shown := 0
	var hidden := 0
	for mi: MeshInstance3D in _meshes(wall):
		if mi.is_visible_in_tree():
			shown += 1
		else:
			hidden += 1
	return [shown, hidden]


func _turn(seconds: float) -> void:
	assert_true(InputMap.has_action("camera_turn_left"), "the input map has camera_turn_left")
	if not InputMap.has_action("camera_turn_left"):
		return
	Input.action_press("camera_turn_left")
	await wait_frames(int(seconds * FPS))
	Input.action_release("camera_turn_left")
	await wait_frames(2)


# Checks each wall is hidden exactly when the camera looks at it from outside.
func _check_rule(camera: Camera3D, walls: Dictionary, when: String) -> void:
	var f := -camera.global_transform.basis.z
	for wall_name: String in walls:
		var outside: bool = f.x > 0.0 if wall_name == "wall_west" else f.z > 0.0
		var counts := _shown(walls[wall_name])
		if outside:
			assert_eq(counts[0], 0, "%s: %s is hidden, seen from outside (%d meshes still shown)" % [when, wall_name, counts[0]])
		else:
			assert_eq(counts[1], 0, "%s: %s is shown, seen from inside (%d meshes hidden)" % [when, wall_name, counts[1]])


func _walls(main: Node) -> Dictionary:
	var walls := {}
	for wall_name in ["wall_west", "wall_north"]:
		var wall := main.find_child(wall_name, true, false)
		assert_not_null(wall, "the garage has %s" % wall_name)
		if wall != null:
			assert_gt(_meshes(wall).size(), 0, "%s has meshes" % wall_name)
			walls[wall_name] = wall
	return walls


# Given the camera at its start (looking from the +X/+Z corner), when the room is drawn, then both back
# walls, wall_west and wall_north, are shown.
func test_both_walls_show_at_the_start():
	var main := await _main()
	if main == null:
		return
	var walls := _walls(main)
	for wall_name: String in walls:
		assert_eq(_shown(walls[wall_name])[1], 0, "%s is shown at the start" % wall_name)


# Given the camera turned so it looks at a back wall from outside (its flat view direction towards +X for
# wall_west, towards +Z for wall_north), when the room is drawn, then that wall and everything in it is
# hidden; the other wall follows the same rule on its own.
func test_a_wall_seen_from_outside_hides():
	var main := await _main()
	var camera := _camera(main) if main != null else null
	if camera == null:
		return
	var walls := _walls(main)
	var hid_one_alone := false
	var hid_both := false
	for quarter in 3:
		await _turn(1.0)
		_check_rule(camera, walls, "after %d s of turning" % (quarter + 1))
		var hidden := walls.keys().filter(func(w: String) -> bool: return _shown(walls[w])[0] == 0).size()
		hid_one_alone = hid_one_alone or hidden == 1
		hid_both = hid_both or hidden == 2
	assert_true(hid_one_alone, "turned a quarter, one wall hides on its own")
	assert_true(hid_both, "turned half way round, both walls hide")


# Given the camera turns back in front of a hidden wall, when the room is drawn, then the wall is shown
# again.
func test_a_hidden_wall_comes_back():
	var main := await _main()
	var camera := _camera(main) if main != null else null
	if camera == null:
		return
	var walls := _walls(main)
	await _turn(2.0)  # half way round: behind both
	await _turn(2.0)  # back round to the front
	_check_rule(camera, walls, "turned all the way round")
	for wall_name: String in walls:
		assert_eq(_shown(walls[wall_name])[1], 0, "%s is shown again" % wall_name)


# Given a wall is hidden, when he walks into it, then it still blocks him (its collision stays).
func test_hidden_walls_still_block():
	var main := await _main()
	var camera := _camera(main) if main != null else null
	if camera == null:
		return
	var room := main.find_child("RoomCollision", true, false)
	assert_not_null(room, "the main scene has RoomCollision")
	if room == null:
		return
	var before := room.find_children("*", "CollisionShape3D", false, false).size()
	var walls := _walls(main)
	await _turn(2.0)
	for wall_name: String in walls:
		assert_eq(_shown(walls[wall_name])[0], 0, "%s is hidden, half way round" % wall_name)
	var shapes := room.find_children("*", "CollisionShape3D", false, false)
	assert_eq(shapes.size(), before, "the room keeps all its collision boxes (%d of %d)" % [shapes.size(), before])
	for wall_name: String in walls:
		var box := AABB()
		var first := true
		for mi: MeshInstance3D in _meshes(walls[wall_name]):
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var middle := box.get_center()
		var covered := false
		for shape: CollisionShape3D in shapes:
			var boxed := shape.shape as BoxShape3D
			if boxed == null:
				continue
			var local := shape.global_transform.affine_inverse() * Vector3(middle.x, 0.5, middle.z)
			if absf(local.x) <= boxed.size.x / 2.0 and absf(local.z) <= boxed.size.z / 2.0:
				covered = true
		assert_true(covered, "%s still has a collision box at its middle" % wall_name)
