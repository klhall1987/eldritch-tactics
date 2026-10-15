extends Camera3D
## Keeps a target centred on screen, keeping the camera's angle and zoom: the camera moves so it
## looks straight at a point `target_height` above the target's origin, every physics tick and
## every frame, so the view is never a step behind the target.

## The node to follow.
@export var target_path: NodePath
## How far above the target's origin to centre on (about the middle of a character).
@export var target_height := 1.0
## How far back along its view direction the camera sits from that point.
@export var distance := 20.0


func _ready() -> void:
	_follow()


func _physics_process(_delta: float) -> void:
	_follow()


func _process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	var target := get_node_or_null(target_path) as Node3D
	if target == null:
		return
	var focus := target.global_position + Vector3.UP * target_height
	global_position = focus + global_transform.basis.z.normalized() * distance
