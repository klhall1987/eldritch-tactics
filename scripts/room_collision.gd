extends StaticBody3D
## The garage's collision, built when the scene starts: a box for each prop the player character must
## walk around (sized from its meshes), the two back walls, and invisible barriers just past the
## two open camera sides, so he stays on the floor. Nothing here is drawn.

## The garage instance to build collision for.
@export var garage_path: NodePath
## Props that block the player character. Smaller clutter (boxes, the TV crate, the bulb) doesn't.
@export var props: PackedStringArray = ["workbench", "couch", "shelves", "fridge", "mattress", "garage_door"]
## How tall every box is. Taller than anyone, so even a low prop like the mattress is a wall to
## the player character's capsule rather than a ledge he could slide up onto.
@export var height := 3.0
## How thick the invisible barriers past the open sides are.
@export var barrier_thickness := 0.5
## Gaps between boxes narrower than this (the player character's width) are filled in, so he meets a flat
## face instead of wedging his capsule into a slot he can't fit through.
@export var min_gap := 0.5


func _ready() -> void:
	var garage := get_node(garage_path) as Node3D
	var areas: Array[AABB] = []
	for prop in props:
		areas.append(_bounds(garage.find_child(prop, true, false)))
	for wall in ["wall_west", "wall_north"]:
		areas.append(_bounds(garage.find_child(wall, true, false)))
	# The open +X and +Z sides: barriers just outside the floor, running past both corners.
	var floor_box := _bounds(garage.find_child("floor", true, false))
	var t := barrier_thickness
	areas.append(AABB(Vector3(floor_box.end.x, 0, floor_box.position.z - t), Vector3(t, 0, floor_box.size.z + 2 * t)))
	areas.append(AABB(Vector3(floor_box.position.x - t, 0, floor_box.end.z), Vector3(floor_box.size.x + 2 * t, 0, t)))
	for area in areas + _gap_fillers(areas):
		_add_box(area)


## Boxes that fill the narrow gaps (under `min_gap`) between neighbouring areas, seen from above.
func _gap_fillers(areas: Array[AABB]) -> Array[AABB]:
	var fillers: Array[AABB] = []
	for i in areas.size():
		for j in range(i + 1, areas.size()):
			for axis in [Vector3.AXIS_X, Vector3.AXIS_Z]:
				var across := Vector3.AXIS_Z if axis == Vector3.AXIS_X else Vector3.AXIS_X
				var a := areas[i]
				var b := areas[j]
				# They must face each other: overlapping along `across`, apart along `axis`.
				var lo := maxf(a.position[across], b.position[across])
				var hi := minf(a.end[across], b.end[across])
				if hi <= lo:
					continue
				var first := a if a.position[axis] < b.position[axis] else b
				var second := b if first == a else a
				var gap := second.position[axis] - first.end[axis]
				if gap <= 0.0 or gap >= min_gap:
					continue
				var filler := AABB()
				filler.position[axis] = first.end[axis]
				filler.size[axis] = gap
				filler.position[across] = lo
				filler.size[across] = hi - lo
				fillers.append(filler)
	return fillers


## Adds a full-height box covering `area` (only its x and z matter) to this body.
func _add_box(area: AABB) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(area.size.x, height, area.size.z)
	var shape := CollisionShape3D.new()
	shape.shape = box
	add_child(shape)
	shape.global_position = Vector3(area.get_center().x, height / 2.0, area.get_center().z)


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
