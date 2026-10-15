extends CharacterBody3D
## The player: walks the detective (its child) around the floor with WASD or the arrow keys, in
## eight directions relative to the screen, turning to face where he walks. Plays `walk` while
## moving and `idle` when stopped.

## Walking speed in metres per second.
@export var speed := 2.5
## How quickly he turns to face his direction of travel (higher is snappier).
@export var turn_rate := 15.0

var _animation: AnimationPlayer


func _ready() -> void:
	var players := find_children("*", "AnimationPlayer", true, false)
	_animation = players[0] if not players.is_empty() else null


func _physics_process(delta: float) -> void:
	# Input.get_vector already caps the length at 1, so diagonals aren't faster.
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := _screen_to_floor(input)
	velocity = direction * speed
	move_and_slide()

	var moving := direction.length() > 0.01
	if moving:
		var target := atan2(direction.x, direction.z)  # the model faces its +Z (MODEL_FRONT)
		rotation.y = lerp_angle(rotation.y, target, 1.0 - exp(-turn_rate * delta))
	_play("walk" if moving else "idle")


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
	if _animation != null and _animation.current_animation != clip:
		_animation.play(clip)
