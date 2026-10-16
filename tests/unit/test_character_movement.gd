extends GutTest
# Moving the detective (ticket #28): holding WASD or the arrow keys walks him in eight directions
# relative to the screen at about 2.5 m/s, facing where he walks and playing `walk`, and he stops
# and idles when the keys are released.

const ACTIONS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
}
const PHYSICS_FPS := 60  # Godot's default physics tick rate: 60 ticks = 1 second of movement
const MIN_DISTANCE := 2.2
const MAX_DISTANCE := 2.8
const DIRECTION_TOLERANCE := 5.0  # degrees
const FACING_TOLERANCE := 10.0  # degrees


func after_each():
	for action in ACTIONS:
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


func _detective(main: Node) -> Node3D:
	var detective := main.find_child("Character", true, false) as Node3D
	assert_not_null(detective, "the main scene has the Character")
	return detective


# The camera's forward and right directions, flattened onto the floor: "up" and "right" on screen.
func _screen_axes(main: Node) -> Array[Vector3]:
	var cameras := main.find_children("*", "Camera3D", true, false)
	assert_eq(cameras.size(), 1, "the main scene has one Camera3D")
	if cameras.is_empty():
		return [Vector3.ZERO, Vector3.ZERO]
	var basis: Basis = cameras[0].global_transform.basis
	var up := Vector3(-basis.z.x, 0, -basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0, basis.x.z).normalized()
	return [up, right]


func _press(actions: Array) -> void:
	for action: String in actions:
		assert_true(InputMap.has_action(action), "the input map has %s" % action)
		if InputMap.has_action(action):
			Input.action_press(action)


func _release(actions: Array) -> void:
	for action: String in actions:
		if InputMap.has_action(action):
			Input.action_release(action)


func _animation_player(detective: Node) -> AnimationPlayer:
	var players := detective.find_children("*", "AnimationPlayer", true, false)
	assert_eq(players.size(), 1, "the detective has one AnimationPlayer")
	return players[0] if players.size() > 0 else null


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


# Holds `actions` for one second of physics and returns how far the detective moved.
func _walk_for_a_second(detective: Node3D, actions: Array) -> Vector3:
	var start := detective.global_position
	_press(actions)
	await wait_physics_frames(PHYSICS_FPS)
	_release(actions)
	return detective.global_position - start


# Given the project, when its input map is inspected, then it has actions move_up, move_down,
# move_left and move_right, bound to W/S/A/D and to the Up/Down/Left/Right arrow keys.
func test_input_map_has_movement_actions():
	for action: String in ACTIONS:
		assert_true(InputMap.has_action(action), "the input map has %s" % action)
		if not InputMap.has_action(action):
			continue
		var keys := []
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				keys.append(event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode)
		for key: Key in ACTIONS[action]:
			assert_has(keys, key, "%s is bound to %s" % [action, OS.get_keycode_string(key)])


# Given the game is running, when move_up is held for 1 second, then the detective moves 2.2-2.8 m
# (a walking speed of about 2.5 m/s) in the direction that is "up" on screen (the camera's forward
# direction, flattened onto the floor), and stays on the floor (y = 0).
func test_move_up_walks_up_the_screen():
	var main := await _main()
	if main == null:
		return
	var detective := _detective(main)
	var axes := _screen_axes(main)
	if detective == null:
		return
	var moved := await _walk_for_a_second(detective, ["move_up"])
	var flat := _flat(moved)
	assert_between(flat.length(), MIN_DISTANCE, MAX_DISTANCE, "he walks 2.2-2.8 m in a second (walked %.2f m)" % flat.length())
	if flat.length() > 0.01:
		var off := rad_to_deg(flat.angle_to(axes[0]))
		assert_lte(off, DIRECTION_TOLERANCE, "he walks up the screen (%.1f degrees off)" % off)
	assert_almost_eq(detective.global_position.y, 0.0, 0.01, "he stays on the floor")


# Given the game is running, when move_up and move_right are held together for 1 second, then the
# detective moves the same 2.2-2.8 m (diagonals are not faster), diagonally up-right on screen,
# within 5 degrees.
func test_diagonal_is_not_faster():
	var main := await _main()
	if main == null:
		return
	var detective := _detective(main)
	var axes := _screen_axes(main)
	if detective == null:
		return
	var moved := await _walk_for_a_second(detective, ["move_up", "move_right"])
	var flat := _flat(moved)
	assert_between(flat.length(), MIN_DISTANCE, MAX_DISTANCE, "he walks 2.2-2.8 m diagonally (walked %.2f m)" % flat.length())
	if flat.length() > 0.01:
		var off := rad_to_deg(flat.angle_to((axes[0] + axes[1]).normalized()))
		assert_lte(off, DIRECTION_TOLERANCE, "he walks up-right on screen (%.1f degrees off)" % off)


# Given the detective is walking, when his facing (Vector3.MODEL_FRONT) and animation are checked,
# then he faces his direction of travel within 10 degrees and is playing walk. Within 0.1 seconds
# of every direction being released, he has stopped and is playing idle.
func test_faces_where_he_walks_then_stops_and_idles():
	var main := await _main()
	if main == null:
		return
	var detective := _detective(main)
	if detective == null:
		return
	var player := _animation_player(detective)

	# Walk left on screen (he starts facing elsewhere, so he has to turn).
	_press(["move_left"])
	await wait_physics_frames(30)
	var before := detective.global_position
	await wait_physics_frames(6)
	var travel := _flat(detective.global_position - before)
	var facing := _flat(detective.global_transform.basis * Vector3.MODEL_FRONT)
	assert_gt(travel.length(), 0.05, "he is walking")
	if travel.length() > 0.05 and facing.length() > 0.0:
		var off := rad_to_deg(facing.angle_to(travel))
		assert_lte(off, FACING_TOLERANCE, "he faces where he walks (%.1f degrees off)" % off)
	if player != null:
		assert_eq(player.current_animation, "walk", "he plays walk while walking")

	_release(["move_left"])
	await wait_physics_frames(PHYSICS_FPS / 10)  # 0.1 seconds
	var stopped_at := detective.global_position
	await wait_physics_frames(3)
	assert_lt(detective.global_position.distance_to(stopped_at), 0.001, "he has stopped within 0.1 s")
	if player != null:
		assert_eq(player.current_animation, "idle", "he plays idle once stopped")
