extends Camera3D
## Keeps a target centred on screen at the camera's angle and zoom: the camera moves so it looks
## straight at a point `target_height` above the target's origin, every physics tick and every frame,
## so the view is never a step behind the target. The player turns it around the target (#167):
## holding `camera_turn_left` / `camera_turn_right` (Q, E), or dragging with the right mouse button.
## They zoom it in and out (#168) with `camera_zoom_in` / `camera_zoom_out` (the mouse wheel, `=`
## and `-`). Its tilt never changes.

## The node to follow.
@export var target_path: NodePath
## How far above the target's origin to centre on (about the middle of a character).
@export var target_height := 1.0
## How far back along its view direction the camera sits from that point.
@export var distance := 20.0
## How fast holding a turn key turns it, in degrees a second.
@export var turn_speed := 90.0
## How far a right-button drag turns it, in degrees per pixel the mouse moves sideways.
@export var drag_turn := 0.3
## How much one zoom notch changes the orthographic size, in metres, and the closest and furthest it goes.
@export var zoom_step := 0.5
@export var closest := 2.0
@export var furthest := 8.0

var _dragging := false


func _ready() -> void:
	_follow()


func _physics_process(_delta: float) -> void:
	_follow()


func _process(delta: float) -> void:
	var turn := Input.get_action_strength("camera_turn_left") - Input.get_action_strength("camera_turn_right")
	if turn != 0.0:
		_turn(turn * turn_speed * delta)
	_follow()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_turn(-event.relative.x * drag_turn)
		_follow()
	if event.is_action_pressed("camera_zoom_in"):
		size = clampf(size - zoom_step, closest, furthest)
	elif event.is_action_pressed("camera_zoom_out"):
		size = clampf(size + zoom_step, closest, furthest)


## Turns the camera `degrees` around the vertical (positive: anticlockwise seen from above).
func _turn(degrees: float) -> void:
	global_transform.basis = Basis(Vector3.UP, deg_to_rad(degrees)) * global_transform.basis


func _follow() -> void:
	var target := get_node_or_null(target_path) as Node3D
	if target == null:
		return
	var focus := target.global_position + Vector3.UP * target_height
	global_position = focus + global_transform.basis.z.normalized() * distance
