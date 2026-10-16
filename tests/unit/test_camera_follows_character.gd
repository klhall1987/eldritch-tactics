extends GutTest
# The camera on the detective (ticket #14): the isometric camera is zoomed in on the detective
# and keeps him centred on screen, following him when he moves.

const ANGLE_TOLERANCE := 1.0  # degrees
const CENTRE_TOLERANCE := 0.05  # fraction of the viewport's size
const MAX_SIZE := 4.0  # metres


# Instantiates the main scene into the tree, or returns null (after failing the test).
func _main() -> Node3D:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the main scene (%s) loads" % path)
	if packed == null:
		return null
	var main := packed.instantiate()
	add_child_autofree(main)
	return main as Node3D


# Instantiates the main scene inside a viewport the size of the project's default window, so
# "in view" is judged at the game's real size rather than the tiny headless test viewport.
func _main_in_game_window() -> Node3D:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the main scene (%s) loads" % path)
	if packed == null:
		return null
	var window := SubViewport.new()
	window.size = Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	add_child_autofree(window)
	var main := packed.instantiate()
	window.add_child(main)
	return main as Node3D


func _camera(main: Node) -> Camera3D:
	var cameras := main.find_children("*", "Camera3D", true, false)
	assert_eq(cameras.size(), 1, "the main scene has one Camera3D")
	return cameras[0] if cameras.size() > 0 else null


func _node(main: Node, node_name: String) -> Node3D:
	var node := main.find_child(node_name, true, false) as Node3D
	assert_not_null(node, "the main scene has a Node3D named %s" % node_name)
	return node


# Asserts the detective's centre (1 m above his origin) is within CENTRE_TOLERANCE of the
# middle of the screen.
func _assert_centred(camera: Camera3D, detective: Node3D, when: String) -> void:
	var size := camera.get_viewport().get_visible_rect().size
	var on_screen := camera.unproject_position(detective.global_position + Vector3.UP * 1.0)
	var off := (on_screen - size / 2.0).abs()
	assert_lte(off.x, size.x * CENTRE_TOLERANCE, "the detective is centred left-right %s (off by %.1f px)" % [when, off.x])
	assert_lte(off.y, size.y * CENTRE_TOLERANCE, "the detective is centred up-down %s (off by %.1f px)" % [when, off.y])


# Given the main scene, when the camera is inspected, then it is still the current orthographic
# camera at the isometric angle (30 degrees down, 45 degrees around), and its orthographic size is
# at most 4 m (zoomed in from the original 10.5 m).
func test_camera_is_zoomed_in_at_the_isometric_angle():
	var main := _main()
	if main == null:
		return
	var camera := _camera(main)
	if camera == null:
		return
	assert_true(camera.is_current(), "the camera is the current camera")
	assert_eq(camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "the camera is orthographic")
	var forward := -camera.global_transform.basis.z.normalized()
	assert_almost_eq(rad_to_deg(asin(-forward.y)), 30.0, ANGLE_TOLERANCE, "the camera looks 30 degrees down")
	var flat := Vector3(forward.x, 0, forward.z).normalized()
	assert_almost_eq(rad_to_deg(flat.angle_to(Vector3(-1, 0, -1).normalized())), 0.0, ANGLE_TOLERANCE,
		"the camera is turned 45 degrees, looking towards -X/-Z")
	assert_lte(camera.size, MAX_SIZE, "the camera is zoomed in (orthographic size at most %.1f m)" % MAX_SIZE)


# Given the main scene has run its first frame, when the detective's centre (1 m above his origin)
# is projected to the screen, then it is within 5% of the viewport's size from the viewport's
# centre.
func test_detective_is_centred_on_screen():
	var main := _main()
	if main == null:
		return
	await wait_frames(1)
	var camera := _camera(main)
	var detective := _node(main, "Character")
	if camera == null or detective == null:
		return
	_assert_centred(camera, detective, "at the start")


# Given the main scene is running, when the detective is moved 2 m along X and then 2 m along Z
# and a frame passes after each move, then he is centred again (same 5% tolerance) and the
# camera's angle and size are unchanged.
func test_camera_follows_the_detective():
	var main := _main()
	if main == null:
		return
	await wait_frames(1)
	var camera := _camera(main)
	var detective := _node(main, "Character")
	if camera == null or detective == null:
		return
	var basis_before := camera.global_transform.basis
	var size_before := camera.size

	detective.global_position += Vector3(2, 0, 0)
	await wait_frames(1)
	_assert_centred(camera, detective, "after moving 2 m along X")

	detective.global_position += Vector3(0, 0, 2)
	await wait_frames(1)
	_assert_centred(camera, detective, "after moving 2 m along Z")

	assert_true(camera.global_transform.basis.is_equal_approx(basis_before), "the camera's angle is unchanged")
	assert_almost_eq(camera.size, size_before, 0.001, "the camera's size is unchanged")


# Given the main scene has run its first frame, when the detective's and the cultist's feet and
# heads are tested against the camera, in a viewport of the default window size, then all four
# points are inside its view.
func test_camera_sees_both_characters_after_first_frame():
	var main := _main_in_game_window()
	if main == null:
		return
	await wait_frames(1)
	var camera := _camera(main)
	if camera == null:
		return
	for character_name in ["Character", "Cultist"]:
		var character := _node(main, character_name)
		if character == null:
			continue
		var feet := character.global_position
		var top := -INF
		for mi: MeshInstance3D in character.find_children("*", "MeshInstance3D", true, false):
			top = maxf(top, (mi.global_transform * mi.get_aabb()).end.y)
		assert_gt(top, feet.y, "%s has a head to test" % character_name)
		assert_true(camera.is_position_in_frustum(feet), "%s's feet are in view" % character_name)
		assert_true(camera.is_position_in_frustum(Vector3(feet.x, top, feet.z)),
			"%s's head is in view" % character_name)
