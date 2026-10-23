extends GutTest
# Turn the camera around him (ticket #167): holding Q or E, or dragging with the right mouse button,
# turns the camera around the player character, all the way round if held, keeping him centred and
# 30 degrees down; his movement keys stay relative to the screen.
#
# Interface these tests choose:
# - Input actions `camera_turn_left` (Q) and `camera_turn_right` (E), held as the movement tests hold
#   theirs (Input.action_press).
# - The camera's turn is its flat view direction's angle around +Y (degrees); "one way" and "the
#   other" are the two signs of its change, followed frame by frame so a full turn adds up to 360.
# - A right-button drag is mouse events pushed into the main scene's viewport: the right button
#   pressed, mouse motion with a sideways `relative`, then the button released.
# - "Centred": his centre (1 m above his origin) within 5% of the middle of the screen, as in
#   test_camera_follows_character.gd.

const ANGLE_TOLERANCE := 1.0  # degrees, for the pitch
const TURN_TOLERANCE := 10.0  # degrees
const CENTRE_TOLERANCE := 0.05
const FPS := 60  # the test runner's --fixed-fps


func after_each():
	for action in ["camera_turn_left", "camera_turn_right", "move_up"]:
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


func _forward(camera: Camera3D) -> Vector3:
	return -camera.global_transform.basis.z.normalized()


# The camera's turn: its flat view direction's angle around +Y, in degrees.
func _yaw(camera: Camera3D) -> float:
	var f := _forward(camera)
	return rad_to_deg(atan2(-f.x, -f.z))


func _pitch(camera: Camera3D) -> float:
	return rad_to_deg(asin(-_forward(camera).y))


func _assert_centred(camera: Camera3D, detective: Node3D, when: String) -> void:
	var size := camera.get_viewport().get_visible_rect().size
	var on_screen := camera.unproject_position(detective.global_position + Vector3.UP * 1.0)
	var off := (on_screen - size / 2.0).abs()
	assert_lte(off.x, size.x * CENTRE_TOLERANCE, "he's centred left-right %s (off by %.1f px)" % [when, off.x])
	assert_lte(off.y, size.y * CENTRE_TOLERANCE, "he's centred up-down %s (off by %.1f px)" % [when, off.y])


# Holds `action` for `seconds`, following the camera's turn frame by frame; returns the total turn.
func _hold(camera: Camera3D, action: String, seconds: float) -> float:
	assert_true(InputMap.has_action(action), "the input map has %s" % action)
	if not InputMap.has_action(action):
		return 0.0
	var turned := 0.0
	var last := _yaw(camera)
	Input.action_press(action)
	for frame in int(seconds * FPS):
		await wait_frames(1)
		var now := _yaw(camera)
		turned += wrapf(now - last, -180.0, 180.0)
		last = now
	Input.action_release(action)
	await wait_frames(1)
	turned += wrapf(_yaw(camera) - last, -180.0, 180.0)
	return turned


func _bound_to(action: String, key: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event.keycode == key or event.physical_keycode == key):
			return true
	return false


# Given the main scene, when it starts, then the camera is where it is today: 30 degrees down, 45 degrees
# around, looking from the room's open +X/+Z corner, with him centred.
func test_it_starts_where_it_is_today():
	var main := await _main()
	if main == null:
		return
	var camera := _camera(main)
	var detective := main.find_child("Character", true, false) as Node3D
	if camera == null or detective == null:
		return
	assert_almost_eq(_pitch(camera), 30.0, ANGLE_TOLERANCE, "it looks 30 degrees down")
	var flat := Vector3(_forward(camera).x, 0, _forward(camera).z).normalized()
	assert_almost_eq(rad_to_deg(flat.angle_to(Vector3(-1, 0, -1).normalized())), 0.0, ANGLE_TOLERANCE, "it looks from the +X/+Z corner")
	_assert_centred(camera, detective, "at the start")


# Given the game is running, when Q is held for 1 second, then the camera turns 90 degrees (within 10)
# one way around him; E turns it the other way; it's still 30 degrees down, not rolled, and he's still
# centred.
func test_q_and_e_turn_it_around_him():
	var main := await _main()
	if main == null:
		return
	var camera := _camera(main)
	var detective := main.find_child("Character", true, false) as Node3D
	if camera == null or detective == null:
		return
	assert_true(_bound_to("camera_turn_left", KEY_Q), "camera_turn_left is bound to Q")
	assert_true(_bound_to("camera_turn_right", KEY_E), "camera_turn_right is bound to E")
	var left := await _hold(camera, "camera_turn_left", 1.0)
	assert_almost_eq(absf(left), 90.0, TURN_TOLERANCE, "Q held for a second turns it 90 degrees (%.1f)" % left)
	assert_almost_eq(_pitch(camera), 30.0, ANGLE_TOLERANCE, "it still looks 30 degrees down")
	assert_almost_eq(camera.global_transform.basis.x.normalized().y, 0.0, 0.02, "it isn't rolled")
	_assert_centred(camera, detective, "after turning with Q")
	var right := await _hold(camera, "camera_turn_right", 1.0)
	assert_almost_eq(absf(right), 90.0, TURN_TOLERANCE, "E held for a second turns it 90 degrees (%.1f)" % right)
	assert_true(signf(left) != signf(right), "E turns it the other way from Q (%.1f vs %.1f)" % [left, right])
	_assert_centred(camera, detective, "after turning with E")


# Given Q is held for 4 seconds, when the camera has turned, then it has gone all the way round (360
# degrees, within 10) and keeps turning with no stop or limit.
func test_it_goes_all_the_way_round():
	var main := await _main()
	if main == null:
		return
	var camera := _camera(main)
	if camera == null:
		return
	var turned := await _hold(camera, "camera_turn_left", 4.0)
	assert_almost_eq(absf(turned), 360.0, TURN_TOLERANCE, "4 seconds of Q turn it all the way round (%.1f degrees)" % turned)
	var more := await _hold(camera, "camera_turn_left", 1.0)
	assert_almost_eq(absf(more), 90.0, TURN_TOLERANCE, "and it keeps turning past a full turn (%.1f more)" % more)
	assert_true(signf(more) == signf(turned), "still the same way round")


# Given the right mouse button is held, when the mouse moves sideways, then the camera turns around him
# by 0.3 degrees per pixel: one way for right, the other for left; releasing the button stops it.
func test_right_drag_turns_it():
	var main := await _main()
	if main == null:
		return
	var camera := _camera(main)
	if camera == null:
		return
	var viewport := main.get_viewport()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = Vector2(200, 200)
	viewport.push_input(press)
	await wait_frames(1)
	var before := _yaw(camera)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	motion.relative = Vector2(100, 0)
	motion.position = Vector2(300, 200)
	viewport.push_input(motion)
	await wait_frames(1)
	var right_turn := wrapf(_yaw(camera) - before, -180.0, 180.0)
	assert_almost_eq(absf(right_turn), 30.0, 1.0, "100 px right turns it 30 degrees (%.1f)" % right_turn)
	before = _yaw(camera)
	motion = InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	motion.relative = Vector2(-50, 0)
	motion.position = Vector2(250, 200)
	viewport.push_input(motion)
	await wait_frames(1)
	var left_turn := wrapf(_yaw(camera) - before, -180.0, 180.0)
	assert_almost_eq(absf(left_turn), 15.0, 1.0, "50 px left turns it 15 degrees (%.1f)" % left_turn)
	assert_true(signf(left_turn) != signf(right_turn), "left turns it the other way from right")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = Vector2(250, 200)
	viewport.push_input(release)
	await wait_frames(1)
	before = _yaw(camera)
	motion = InputEventMouseMotion.new()
	motion.relative = Vector2(100, 0)
	motion.position = Vector2(350, 200)
	viewport.push_input(motion)
	await wait_frames(1)
	assert_almost_eq(wrapf(_yaw(camera) - before, -180.0, 180.0), 0.0, 0.1, "with the button released, moving the mouse doesn't turn it")


# Given the camera has turned 90 degrees, when the player presses "up", then he walks the way that's up
# on the new screen (away from the camera), as he does today.
func test_up_is_up_on_the_turned_screen():
	var main := await _main()
	if main == null:
		return
	var camera := _camera(main)
	var detective := main.find_child("Character", true, false) as Node3D
	if camera == null or detective == null:
		return
	var turned := await _hold(camera, "camera_turn_left", 1.0)
	assert_almost_eq(absf(turned), 90.0, TURN_TOLERANCE, "the camera has turned about 90 degrees")
	var up := Vector3(_forward(camera).x, 0, _forward(camera).z).normalized()
	# From the middle of the room, clear of the furniture and the monster whichever way it turned.
	var body := detective.get_parent()
	while body != null and not body is CharacterBody3D:
		body = body.get_parent()
	(body as CharacterBody3D).global_position = Vector3(0.3, 0, 0.8)
	await wait_physics_frames(2)
	var start := detective.global_position
	Input.action_press("move_up")
	await wait_physics_frames(int(0.6 * FPS))
	Input.action_release("move_up")
	var walked := detective.global_position - start
	walked.y = 0.0
	assert_gt(walked.length(), 0.8, "he walks (%.2f m)" % walked.length())
	if walked.length() > 0.01:
		var off := rad_to_deg(walked.normalized().angle_to(up))
		assert_lte(off, 5.0, "he walks up the turned screen (%.1f degrees off)" % off)
