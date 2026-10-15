extends GutTest
# The garage room model (ticket #8): a lived-in garage about 8 m by 6 m, with two back walls
# (on -X and -Z), open towards the camera, named props and a glowing bulb, exported to a .glb.

const GARAGE_PATH := "res://assets/models/environments/garage.glb"
const PROPS := ["garage_door", "workbench", "couch", "shelves", "fridge", "mattress"]


# Loads and instantiates the garage, or returns null (after failing the test) if it's missing.
func _garage() -> Node3D:
	var packed: PackedScene = load(GARAGE_PATH)
	assert_not_null(packed, "the garage model (%s) loads" % GARAGE_PATH)
	if packed == null:
		return null
	var garage := packed.instantiate()
	add_child_autofree(garage)
	assert_true(garage is Node3D, "the garage's root is a Node3D")
	return garage as Node3D


# Every MeshInstance3D at or under `node`.
func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.find_children("*", "MeshInstance3D", true, false):
		found.append(child)
	return found


# The vertices of one mesh surface, in the garage's space.
func _surface_points(garage: Node3D, mesh_instance: MeshInstance3D, surface: int) -> PackedVector3Array:
	var to_garage := garage.global_transform.affine_inverse() * mesh_instance.global_transform
	var points := PackedVector3Array()
	for v in mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
		points.append(to_garage * v)
	return points


# The vertices of every mesh at or under `node`, in the garage's space.
func _points(garage: Node3D, node: Node) -> PackedVector3Array:
	var points := PackedVector3Array()
	for mi in _meshes(node):
		for s in mi.mesh.get_surface_count():
			points.append_array(_surface_points(garage, mi, s))
	return points


func _bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box


# The whole garage's bounds, or an empty AABB (after failing the test) if it has no geometry.
func _footprint(garage: Node3D) -> AABB:
	var points := _points(garage, garage)
	assert_gt(points.size(), 0, "the garage has geometry to measure")
	return _bounds(points) if points.size() > 0 else AABB()


# True when `inner` lies inside `outer` horizontally (x and z), allowing 1 cm for rounding.
func _inside_horizontally(inner: AABB, outer: AABB) -> bool:
	return (inner.position.x >= outer.position.x - 0.01 and inner.end.x <= outer.end.x + 0.01
		and inner.position.z >= outer.position.z - 0.01 and inner.end.z <= outer.end.z + 0.01)


# Given the project, when res://assets/models/environments/garage.glb is loaded and instantiated,
# then it loads without errors and its root is a Node3D.
func test_garage_loads_and_root_is_node3d():
	var garage := _garage()
	if garage == null:
		return
	assert_gt(_meshes(garage).size(), 0, "the garage has at least one mesh")


# Given the instantiated garage, when its mesh bounds are measured, then its footprint is 8 m along
# X and 6 m along Z (each within 0.3 m, walls included) and centred on the origin within 0.1 m,
# and a part named floor has its top surface at y = 0 (within 0.02 m).
func test_garage_is_8_by_6_m_centred_with_floor_at_y0():
	var garage := _garage()
	if garage == null:
		return
	var box := _footprint(garage)
	assert_almost_eq(box.size.x, 8.0, 0.3, "the garage is 8 m along X")
	assert_almost_eq(box.size.z, 6.0, 0.3, "the garage is 6 m along Z")
	var centre := box.get_center()
	assert_lt(Vector2(centre.x, centre.z).length(), 0.1, "the garage is centred on the origin")

	var floor_node := garage.find_child("floor", true, false)
	assert_not_null(floor_node, "the garage has a part named floor")
	if floor_node == null:
		return
	var floor_points := _points(garage, floor_node)
	assert_gt(floor_points.size(), 0, "the floor has geometry")
	if floor_points.is_empty():
		return
	assert_almost_eq(_bounds(floor_points).end.y, 0.0, 0.02, "the floor's top surface is at y = 0")


# Given the instantiated garage, when its geometry is measured, then the back walls (along its -X
# and -Z edges) reach between 2.5 m and 3.5 m high, and the camera sides are open: no geometry
# within 0.5 m of the +X or +Z edges is higher than 1.2 m.
func test_garage_has_back_walls_and_open_camera_sides():
	var garage := _garage()
	if garage == null:
		return
	var points := _points(garage, garage)
	if points.is_empty():
		assert_gt(points.size(), 0, "the garage has geometry to measure")
		return
	var box := _bounds(points)
	var back_x_top := -INF  # highest point within 0.5 m of the -X edge
	var back_z_top := -INF  # highest point within 0.5 m of the -Z edge
	var front_top := -INF   # highest point within 0.5 m of the +X or +Z edge
	for p in points:
		if p.x <= box.position.x + 0.5:
			back_x_top = maxf(back_x_top, p.y)
		if p.z <= box.position.z + 0.5:
			back_z_top = maxf(back_z_top, p.y)
		if p.x >= box.end.x - 0.5 or p.z >= box.end.z - 0.5:
			front_top = maxf(front_top, p.y)
	assert_between(back_x_top, 2.5, 3.5, "the back wall along -X is 2.5-3.5 m high")
	assert_between(back_z_top, 2.5, 3.5, "the back wall along -Z is 2.5-3.5 m high")
	assert_gt(front_top, -INF, "there is geometry along the +X/+Z edges (the floor)")
	assert_lte(front_top, 1.2, "nothing along the +X/+Z camera sides is higher than 1.2 m")


# Given the instantiated garage, when its parts are listed, then it has separately named parts
# garage_door, workbench, couch, shelves, fridge and mattress, each lying inside the footprint,
# with garage_door against one of the back walls.
func test_garage_has_lived_in_props_inside_it():
	var garage := _garage()
	if garage == null:
		return
	var box := _footprint(garage)
	for prop: String in PROPS:
		var node := garage.find_child(prop, true, false)
		assert_not_null(node, "the garage has a part named %s" % prop)
		if node == null:
			continue
		var points := _points(garage, node)
		assert_gt(points.size(), 0, "%s has geometry" % prop)
		if points.is_empty():
			continue
		var part := _bounds(points)
		assert_true(_inside_horizontally(part, box), "%s lies inside the garage's footprint" % prop)
		if prop == "garage_door":
			var on_back_wall := (part.position.x <= box.position.x + 0.5
				or part.position.z <= box.position.z + 0.5)
			assert_true(on_back_wall, "the garage door is against a back wall (-X or -Z)")


# Given the instantiated garage, when its materials are inspected, then at least one material is
# emissive (a light bulb), and that emissive geometry is inside the footprint and more than 1.5 m
# above the floor.
func test_garage_has_glowing_bulb_up_high():
	var garage := _garage()
	if garage == null:
		return
	var glowing := PackedVector3Array()
	for mi in _meshes(garage):
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as BaseMaterial3D
			if mat != null and mat.emission_enabled:
				glowing.append_array(_surface_points(garage, mi, s))
	assert_gt(glowing.size(), 0, "the garage has emissive geometry (a light bulb)")
	if glowing.is_empty():
		return
	var bulb := _bounds(glowing)
	assert_true(_inside_horizontally(bulb, _footprint(garage)), "the bulb is inside the garage's footprint")
	assert_gt(bulb.position.y, 1.5, "the bulb is more than 1.5 m above the floor")
