extends NavigationRegion3D
## The garage's walkable floor for paths in combat, baked when the scene starts: the floor, with
## RoomCollision's boxes (props, walls and the open-side barriers) cut out, shrunk by the
## player character's radius so a path never brushes a box.

## The garage instance whose floor is walked on.
@export var garage_path: NodePath
## The RoomCollision body whose boxes block paths. It must come before this node in the tree, so
## its boxes exist when this bakes.
@export var room_path: NodePath
## How far paths keep from the boxes: a little more than the player character's capsule radius.
@export var agent_radius := 0.3


func _ready() -> void:
	# Its own map, not the world's: another copy of the scene sharing the world (as in tests) would
	# otherwise lay a second, overlapping floor onto the same map.
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, ProjectSettings.get_setting("navigation/3d/default_cell_size"))
	NavigationServer3D.map_set_cell_height(map, ProjectSettings.get_setting("navigation/3d/default_cell_height"))
	NavigationServer3D.map_set_use_async_iterations(map, false)
	NavigationServer3D.map_set_active(map, true)
	set_navigation_map(map)
	var source := NavigationMeshSourceGeometryData3D.new()
	var floor_box := _bounds(get_node(garage_path).find_child("floor", true, false))
	var a := Vector3(floor_box.position.x, 0, floor_box.position.z)
	var b := Vector3(floor_box.end.x, 0, floor_box.position.z)
	var c := Vector3(floor_box.end.x, 0, floor_box.end.z)
	var d := Vector3(floor_box.position.x, 0, floor_box.end.z)
	source.add_faces(PackedVector3Array([a, b, c, a, c, d]), Transform3D.IDENTITY)
	for shape: CollisionShape3D in get_node(room_path).find_children("*", "CollisionShape3D", false, false):
		var box := shape.shape as BoxShape3D
		if box == null or box.size.x <= 0.0 or box.size.z <= 0.0:
			continue
		source.add_faces(_box_faces(box.size), shape.global_transform)

	var mesh := NavigationMesh.new()
	mesh.cell_size = ProjectSettings.get_setting("navigation/3d/default_cell_size")
	mesh.cell_height = ProjectSettings.get_setting("navigation/3d/default_cell_height")
	mesh.agent_radius = agent_radius
	mesh.agent_height = 1.8
	mesh.agent_max_climb = 0.2
	# Only the floor and the bottom of the boxes: their tops would be (unreachable) floors of their own.
	mesh.filter_baking_aabb = AABB(Vector3(-100, -1, -100), Vector3(200, 2, 200))
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	navigation_mesh = mesh


func _exit_tree() -> void:
	var map := get_navigation_map()
	set_navigation_map(get_world_3d().navigation_map)
	NavigationServer3D.free_rid(map)


## The triangles of a box of `size` centred on the origin (built here rather than read from a mesh,
## which would mean fetching it back from the GPU).
func _box_faces(size: Vector3) -> PackedVector3Array:
	var h := size / 2.0
	var c := []
	for i in 8:
		c.append(Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	var faces := PackedVector3Array()
	for quad in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		faces.append_array([c[quad[0]], c[quad[1]], c[quad[2]], c[quad[0]], c[quad[2]], c[quad[3]]])
	return faces


## The world bounds of every mesh at or under `node`.
func _bounds(node: Node) -> AABB:
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	var box := AABB()
	for i in meshes.size():
		var mi := meshes[i] as MeshInstance3D
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if i == 0 else box.merge(b)
	return box
