extends CharacterBody3D
## The player: walks the player character (its child) around the floor with WASD or the arrow keys, in
## eight directions relative to the screen, turning to face where he walks. Plays `walk` while
## moving and `idle` when stopped. In combat he walks along a path instead (`walk_path`), and stands
## in his guard (`combat_idle`) rather than `idle`.

## Emitted when he reaches the end of a path given to `walk_path`.
signal path_finished

## Walking speed in metres per second.
@export var speed := 2.5
## How quickly he turns to face his direction of travel (higher is snappier).
@export var turn_rate := 25.0
## The combat controller: while combat runs, he stands in `combat_idle`.
@export var combat_controller_path: NodePath

## When false (e.g. once an encounter starts), the keys don't move him and he stands idle.
var controllable := true

var _animation: AnimationPlayer
var _path := PackedVector3Array()  # the points still to walk to, in order

@onready var _combat := get_node_or_null(combat_controller_path)


func _ready() -> void:
	var players := find_children("*", "AnimationPlayer", true, false)
	_animation = players[0] if not players.is_empty() else null


func _physics_process(delta: float) -> void:
	var direction := Vector3.ZERO
	var pace := speed
	if is_walking_path():
		var to_next := _path[0] - global_position
		to_next.y = 0.0
		var distance := to_next.length()
		direction = to_next / distance if distance > 0.0 else Vector3.ZERO
		pace = minf(speed, distance / delta)  # don't overshoot the point
	else:
		# Input.get_vector already caps the length at 1, so diagonals aren't faster.
		var input := Input.get_vector("move_left", "move_right", "move_up", "move_down") if controllable else Vector2.ZERO
		direction = _screen_to_floor(input)
	velocity = direction * pace
	move_and_slide()
	global_position.y = 0.0  # he walks on the floor; sliding off a box edge must not lift him
	_advance_path()

	var moving := direction.length() > 0.01
	if moving:
		# Face where he actually goes: along a wall he turns to the way he's sliding, not into it.
		var travel := get_real_velocity()
		travel.y = 0.0
		# (Only a real slide counts: a twitch on hitting something head-on mustn't swing him round.)
		var heading := travel if travel.length() > pace * 0.5 else direction
		var target := atan2(heading.x, heading.z)  # the model faces its +Z (MODEL_FRONT)
		rotation.y = lerp_angle(rotation.y, target, 1.0 - exp(-turn_rate * delta))
	var standing: StringName = &"combat_idle" if _combat != null and _combat.running else &"idle"
	_play(&"walk" if moving else standing)


## Walks him along `path` (from where he stands, through each point in turn), ignoring the keys.
func walk_path(path: PackedVector3Array) -> void:
	_path = path.slice(1)  # the first point is where he already is


func is_walking_path() -> bool:
	return not _path.is_empty()


## Drops the path points he has reached, announcing the end of the path.
func _advance_path() -> void:
	if not is_walking_path():
		return
	while not _path.is_empty() and Vector2(_path[0].x - global_position.x, _path[0].z - global_position.z).length() < 0.02:
		_path.remove_at(0)
	if _path.is_empty():
		velocity = Vector3.ZERO
		path_finished.emit()


## Turns a screen-space input (x right, y down) into a direction on the floor, using the current
## camera: up on screen is away from the camera, right is the camera's right.
func _screen_to_floor(input: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null or input == Vector2.ZERO:
		return Vector3.ZERO
	var basis := camera.global_transform.basis
	var forward := Vector3(-basis.z.x, 0, -basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0, basis.x.z).normalized()
	return right * input.x - forward * input.y


func _play(clip: StringName) -> void:
	if _animation == null:
		return
	# A punch or a flinch (played by the combat controller, #81) runs to its end before he goes back
	# to walking or standing.
	if _animation.is_playing() and _animation.current_animation in [&"attack", &"hit"]:
		return
	if _animation.current_animation != clip:
		_animation.play(clip)
