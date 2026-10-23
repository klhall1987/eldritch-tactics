extends GutTest
# Zoom the camera in and out (ticket #168): the mouse wheel, or `=` and `-`, zoom the orthographic
# camera in or out on the player character by 0.5 m a notch, between 2 m and 8 m, keeping him centred.
#
# Interface these tests choose (building on test_camera_turn.gd, #167):
# - Zoom is the camera's orthographic `size`.
# - A wheel notch is an InputEventMouseButton (MOUSE_BUTTON_WHEEL_UP / _DOWN, pressed) pushed into
#   the main scene's viewport; a key press is an InputEventKey (`=` / `-`, pressed then released)
#   pushed the same way. They're the input actions `camera_zoom_in` and `camera_zoom_out`.
# - "Centred": his centre within 5% of the middle of the screen, as in test_camera_follows_character.gd.

const STEP := 0.5
const CLOSEST := 2.0
const FURTHEST := 8.0
const CENTRE_TOLERANCE := 0.05
const FPS := 60


func after_each():
	for action in ["camera_turn_left"]:
		if InputMap.has_action(action):
			Input.action_release(action)


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


func _wheel(main: Node, button: MouseButton) -> void:
	var notch := InputEventMouseButton.new()
	notch.button_index = button
	notch.pressed = true
	notch.position = Vector2(200, 200)
	main.get_viewport().push_input(notch)
	var up := notch.duplicate() as InputEventMouseButton
	up.pressed = false
	main.get_viewport().push_input(up)
	await wait_frames(1)


func _key(main: Node, key: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = key
	press.physical_keycode = key
	press.pressed = true
	main.get_viewport().push_input(press)
	await wait_frames(1)
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	main.get_viewport().push_input(release)
	await wait_frames(1)


func _assert_centred(camera: Camera3D, detective: Node3D, when: String) -> void:
	var size := camera.get_viewport().get_visible_rect().size
	var on_screen := camera.unproject_position(detective.global_position + Vector3.UP * 1.0)
	var off := (on_screen - size / 2.0).abs()
	assert_lte(off.x, size.x * CENTRE_TOLERANCE, "he's centred left-right %s (off by %.1f px)" % [when, off.x])
	assert_lte(off.y, size.y * CENTRE_TOLERANCE, "he's centred up-down %s (off by %.1f px)" % [when, off.y])


# Given the main scene, when it starts, then the camera's zoom is today's (orthographic size 4 m).
func test_it_starts_at_todays_zoom():
	var main := await _main()
	if main == null:
		return
	var camera := _camera(main)
	if camera == null:
		return
	assert_almost_eq(camera.size, 4.0, 0.001, "it starts at size 4 m (%.2f)" % camera.size)


# Given the game is running, when the mouse wheel scrolls up one notch, then the camera zooms in by 0.5 m
# of orthographic size; a notch down zooms out by 0.5 m; `=` or `-` does the same as a notch up or down.
func test_wheel_and_keys_zoom_by_a_notch():
	var main := await _main()
	if main == null:
		return
	var camera := _camera(main)
	if camera == null:
		return
	for action in ["camera_zoom_in", "camera_zoom_out"]:
		assert_true(InputMap.has_action(action), "the input map has %s" % action)
	var before := camera.size
	await _wheel(main, MOUSE_BUTTON_WHEEL_UP)
	assert_almost_eq(camera.size, before - STEP, 0.001, "a notch up zooms in 0.5 m (%.2f to %.2f)" % [before, camera.size])
	before = camera.size
	await _wheel(main, MOUSE_BUTTON_WHEEL_DOWN)
	assert_almost_eq(camera.size, before + STEP, 0.001, "a notch down zooms out 0.5 m (%.2f to %.2f)" % [before, camera.size])
	before = camera.size
	await _key(main, KEY_EQUAL)
	assert_almost_eq(camera.size, before - STEP, 0.001, "= zooms in 0.5 m (%.2f to %.2f)" % [before, camera.size])
	before = camera.size
	await _key(main, KEY_MINUS)
	assert_almost_eq(camera.size, before + STEP, 0.001, "- zooms out 0.5 m (%.2f to %.2f)" % [before, camera.size])


# Given the camera is zoomed in or out as far as it goes, when the player zooms further, then it stays
# between 2 m (close) and 8 m (most of the room).
func test_zoom_stays_between_2_and_8_m():
	var main := await _main()
	if main == null:
		return
	var camera := _camera(main)
	if camera == null:
		return
	for i in 12:
		await _wheel(main, MOUSE_BUTTON_WHEEL_UP)
	assert_almost_eq(camera.size, CLOSEST, 0.001, "zoomed in as far as it goes, it's 2 m (%.2f)" % camera.size)
	for i in 20:
		await _wheel(main, MOUSE_BUTTON_WHEEL_DOWN)
	assert_almost_eq(camera.size, FURTHEST, 0.001, "zoomed out as far as it goes, it's 8 m (%.2f)" % camera.size)


# Given the camera is zoomed in or out, or turned (#167), when he moves, then he stays centred on screen.
func test_he_stays_centred_zoomed_and_turned():
	var main := await _main()
	if main == null:
		return
	var camera := _camera(main)
	var detective := main.find_child("Character", true, false) as Node3D
	if camera == null or detective == null:
		return
	for i in 3:
		await _wheel(main, MOUSE_BUTTON_WHEEL_UP)
	detective.global_position += Vector3(1.0, 0, 0)
	await wait_frames(1)
	_assert_centred(camera, detective, "zoomed in, after moving")
	for i in 6:
		await _wheel(main, MOUSE_BUTTON_WHEEL_DOWN)
	assert_true(InputMap.has_action("camera_turn_left"), "the input map has camera_turn_left")
	if InputMap.has_action("camera_turn_left"):
		Input.action_press("camera_turn_left")
		await wait_frames(FPS / 2)
		Input.action_release("camera_turn_left")
	detective.global_position += Vector3(0, 0, 1.0)
	await wait_frames(1)
	_assert_centred(camera, detective, "zoomed out and turned, after moving")
