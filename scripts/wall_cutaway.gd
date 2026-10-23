extends Node
## Hides a back wall of the garage while the camera looks at it from outside (#169), so the player
## character and the room stay in view as the camera turns round; it shows again once the camera is
## back in front of it. Only the wall's meshes hide: its collision (RoomCollision) stays.

## The garage instance whose back walls hide.
@export var garage_path: NodePath
## The camera they hide from.
@export var camera_path: NodePath
## Each back wall's part, and the way the camera looks when it sees that wall from outside.
@export var walls := {"wall_west": Vector3.RIGHT, "wall_north": Vector3.BACK}

var _parts := {}  # wall part -> the way that sees it from outside


func _ready() -> void:
	var garage := get_node(garage_path)
	for wall: String in walls:
		_parts[garage.find_child(wall, true, false)] = walls[wall]


func _process(_delta: float) -> void:
	var camera := get_node_or_null(camera_path) as Camera3D
	if camera == null:
		return
	var looking := -camera.global_transform.basis.z
	looking.y = 0.0
	for part: Node3D in _parts:
		part.visible = looking.dot(_parts[part]) <= 0.0
