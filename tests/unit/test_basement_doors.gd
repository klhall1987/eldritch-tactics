extends GutTest
# The garage's Meshy doors and stairs (ticket #165): its back walls have the owner's Meshy roll-up
# garage door, a doorway with the wooden door in it, and stairs up along a back wall, which he can't
# walk through.
#
# Interface these tests choose (as #164's test_basement_shell.gd does; positions in the garage's space,
# +Y up, its back walls on -X and -Z):
# - A Meshy piece is a MeshInstance3D named for the piece it is (`garage_door`, `doorway_wall`,
#   `wooden_door`, `stairs`); its size, "scaled as a whole", its triangles and its maps are measured as
#   in test_basement_shell.gd.
# - "Against a back wall": its back side (towards that wall) is within 0.1 m of the wall's inner face,
#   or in the wall. A wall's faces are its `wall_section` pieces' bounds across it.
# - The doorway's opening is where its frame isn't: its vertices are flattened onto the wall (along it,
#   and up). The door "stands closed in its opening" when no frame vertex lies inside the door's
#   outline (shrunk 0.03 m), and the frame comes within 0.05 m of the door's two sides and its top.
# - "Its long axis runs along the wall": its bounds are longer along that wall than across it.
# - Walking into a piece: he starts 1.2 m out from its middle (the stairs: from 0.4 m inside their west
#   end, agreed on #165), into the room, and walks straight at it for 4 seconds, as
#   test_character_collision.gd's props do.

const GARAGE_PATH := "res://assets/models/environments/garage.glb"
const MESHY_SIZES := {
	"doorway_wall": Vector3(1.43, 1.90, 0.20),
	"wooden_door": Vector3(0.93, 1.90, 0.18),
	"garage_door": Vector3(1.90, 1.60, 0.07),
	"stairs": Vector3(1.90, 1.29, 0.58),
}
const MAX_TRIANGLES := 50000
const MIN_MAP := 1024
const PHYSICS_FPS := 60
const ACTIONS := ["move_up", "move_down", "move_left", "move_right"]
const WALK_MINUS_X := ["move_up", "move_left"]
const WALK_MINUS_Z := ["move_up", "move_right"]


func after_each():
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			Input.action_release(action)


func _garage() -> Node3D:
	var packed: PackedScene = load(GARAGE_PATH)
	assert_not_null(packed, "the garage model (%s) loads" % GARAGE_PATH)
	if packed == null:
		return null
	var garage := packed.instantiate() as Node3D
	add_child_autofree(garage)
	return garage


func _meshes(node: Node) -> Array:
	var found := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		found.append(node)
	return found


func _piece(garage: Node, name: String, under: Node = null) -> MeshInstance3D:
	var found := (under if under != null else garage).find_child(name, true, false)
	assert_true(found is MeshInstance3D, "the garage has Meshy's %s%s" % [name, " in %s" % under.name if under != null else ""])
	return found as MeshInstance3D


func _box(garage: Node3D, mi: MeshInstance3D) -> AABB:
	return (garage.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()


func _boxes(garage: Node3D, node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in _meshes(node):
		box = _box(garage, mi) if first else box.merge(_box(garage, mi))
		first = false
	return box


func _size(mi: MeshInstance3D) -> Vector3:
	var basis := mi.global_transform.basis
	var own := mi.get_aabb().size
	return Vector3(own.x * basis.x.length(), own.y * basis.y.length(), own.z * basis.z.length())


func _triangles(mi: MeshInstance3D) -> int:
	var count := 0
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var indices = arrays[Mesh.ARRAY_INDEX]
		count += (indices.size() if indices != null and not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return count


# The back wall `box` stands against: [the wall's part name, its inner face's coordinate, its axis], or [].
func _against(garage: Node3D, box: AABB) -> Array:
	# Its back side reaches the wall (within 0.1 m of its inner face, or into it).
	var north := _wall_slab(garage, "wall_north", 2)
	if box.position.z <= north.y + 0.1 and box.end.z >= north.x:
		return ["wall_north", north.y, 2]
	var west := _wall_slab(garage, "wall_west", 0)
	if box.position.x <= west.y + 0.1 and box.end.x >= west.x:
		return ["wall_west", west.y, 0]
	return []


# A back wall's slab across `axis`: (its outer face, its inner face), from its wall sections' bounds.
func _wall_slab(garage: Node3D, wall: String, axis: int) -> Vector2:
	var slab := Vector2(INF, -INF)
	for mi: MeshInstance3D in _meshes(garage.find_child(wall, true, false)):
		if str(mi.name).begins_with("wall_section"):
			var b := _box(garage, mi)
			slab = Vector2(minf(slab.x, b.position[axis]), maxf(slab.y, b.end[axis]))
	return slab


# Given garage.glb, when garage_door is inspected, then it's Meshy's roll-up garage door, scaled with the
# walls and set in wall_north, inside the footprint and against that wall.
func test_meshys_garage_door_in_the_north_wall():
	var garage := _garage()
	if garage == null:
		return
	var north := garage.find_child("wall_north", true, false)
	assert_not_null(north, "the garage has wall_north")
	if north == null:
		return
	var door := _piece(garage, "garage_door", north)
	if door == null:
		return
	var footprint := _boxes(garage, garage)
	var box := _box(garage, door)
	assert_true(box.position.x >= footprint.position.x - 0.01 and box.end.x <= footprint.end.x + 0.01, "the garage door is inside the footprint")
	var against := _against(garage, box)
	assert_true(not against.is_empty() and against[0] == "wall_north", "the garage door is against wall_north")


# Given wall_west, when it's inspected, then it includes Meshy's doorway wall, with Meshy's wooden door
# (a part named wooden_door) standing closed in its opening: within 0.05 m of the opening's sides and
# top.
func test_the_wooden_door_in_its_doorway():
	var garage := _garage()
	if garage == null:
		return
	var west := garage.find_child("wall_west", true, false)
	assert_not_null(west, "the garage has wall_west")
	if west == null:
		return
	var doorway := _piece(garage, "doorway_wall", west)
	var door := _piece(garage, "wooden_door")
	if doorway == null or door == null:
		return
	# Flatten both onto the west wall: (along it, up), i.e. (z, y).
	var door_box := _box(garage, door)
	var lo := Vector2(door_box.position.z, door_box.position.y)
	var hi := Vector2(door_box.end.z, door_box.end.y)
	var to_garage := garage.global_transform.affine_inverse() * doorway.global_transform
	var inside := 0
	var left := INF
	var right := INF
	var top := INF
	for s in doorway.mesh.get_surface_count():
		for v: Vector3 in doorway.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			var p := to_garage * v
			var q := Vector2(p.z, p.y)
			if q.x > lo.x + 0.03 and q.x < hi.x - 0.03 and q.y > lo.y + 0.03 and q.y < hi.y - 0.03:
				inside += 1
			if q.y >= lo.y and q.y <= hi.y:
				if q.x <= lo.x + 0.03:
					left = minf(left, lo.x - q.x)
				if q.x >= hi.x - 0.03:
					right = minf(right, q.x - hi.x)
			if q.x >= lo.x and q.x <= hi.x and q.y >= hi.y - 0.03:
				top = minf(top, q.y - hi.y)
	assert_eq(inside, 0, "the door stands in the opening, clear of its frame (%d frame vertices inside it)" % inside)
	assert_lte(maxf(left, 0.0), 0.05, "the frame is within 0.05 m of the door's left side (%.3f m)" % left)
	assert_lte(maxf(right, 0.0), 0.05, "the frame is within 0.05 m of the door's right side (%.3f m)" % right)
	assert_lte(maxf(top, 0.0), 0.05, "the frame is within 0.05 m of the door's top (%.3f m)" % top)
	assert_almost_eq(door_box.position.y, 0.0, 0.05, "the door stands on the floor (%.3f)" % door_box.position.y)


# Given the garage, when its parts are listed, then it has Meshy's stairs (a part named stairs) against
# one of the back walls and inside the footprint, rising along that wall.
func test_meshys_stairs_against_a_back_wall():
	var garage := _garage()
	if garage == null:
		return
	var stairs := _piece(garage, "stairs")
	if stairs == null:
		return
	var footprint := _boxes(garage, garage)
	var box := _box(garage, stairs)
	assert_true(box.position.x >= footprint.position.x - 0.01 and box.end.x <= footprint.end.x + 0.01
		and box.position.z >= footprint.position.z - 0.01 and box.end.z <= footprint.end.z + 0.01, "the stairs are inside the footprint")
	var against := _against(garage, box)
	assert_false(against.is_empty(), "the stairs are against a back wall")
	if against.is_empty():
		return
	var along := 2 if against[2] == 0 else 0
	assert_gt(box.size[along], box.size[against[2]], "the stairs run along %s (%.2f m along, %.2f m across)" % [against[0], box.size[along], box.size[against[2]]])
	assert_gt(box.size.y, 1.0, "the stairs rise (%.2f m)" % box.size.y)


# Given the main scene, when he walks into the stairs or the wooden door, then he's stopped: he ends
# within 0.4 m of it and never passes through it.
func test_the_stairs_and_door_block_him():
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var main := (load(path) as PackedScene).instantiate() as Node3D
	add_child_autofree(main)
	await wait_physics_frames(2)
	var garage := main.find_child("Garage", true, false) as Node3D
	var detective := main.find_child("Character", true, false) as Node3D
	var body := detective
	while body != null and not body is CharacterBody3D:
		body = body.get_parent()
	assert_true(garage != null and body != null, "the main scene has the Garage and his body")
	if garage == null or body == null:
		return
	for spec in [["stairs", WALK_MINUS_Z, Vector3(0, 0, 1.2)], ["wooden_door", WALK_MINUS_X, Vector3(1.2, 0, 0)]]:
		var piece := garage.find_child(spec[0], true, false) as MeshInstance3D
		assert_not_null(piece, "the garage has its %s" % spec[0])
		if piece == null:
			continue
		var box: AABB = piece.global_transform * piece.get_aabb()
		# Out from its middle; the stairs from 0.4 m inside their west end, clear of the monster's touch area
		# (agreed on #165).
		var along_x := box.position.x + 0.4 if spec[0] == "stairs" else box.get_center().x
		var front := Vector3(along_x if spec[2].x == 0 else box.end.x, 0, box.get_center().z if spec[2].z == 0 else box.end.z)
		(body as CharacterBody3D).global_position = front + spec[2]
		(body as CharacterBody3D).velocity = Vector3.ZERO
		await wait_physics_frames(2)
		for action: String in spec[1]:
			Input.action_press(action)
		var through := false
		for tick in 4 * PHYSICS_FPS:
			await get_tree().physics_frame
			var at := (body as Node3D).global_position
			if at.x > box.position.x and at.x < box.end.x and at.z > box.position.z and at.z < box.end.z:
				through = true
		after_each()
		assert_false(through, "walking at the %s, he never passes into it" % spec[0])
		var at := (body as Node3D).global_position
		var dx := maxf(maxf(box.position.x - at.x, at.x - box.end.x), 0.0)
		var dz := maxf(maxf(box.position.z - at.z, at.z - box.end.z), 0.0)
		var gap := Vector2(dx, dz).length()
		assert_lte(gap, 0.4, "he ends within 0.4 m of the %s (%.2f m)" % [spec[0], gap])


# Given each of these Meshy pieces, when its mesh is measured, then it has at most 50,000 triangles, is
# Meshy's piece scaled as a whole (proportions within 2%), and uses Meshy's colour and normal maps (at
# least 1024 px).
func test_each_door_and_the_stairs_is_meshys_reduced():
	var garage := _garage()
	if garage == null:
		return
	for kind: String in MESHY_SIZES:
		var mi := _piece(garage, kind)
		if mi == null:
			continue
		var triangles := _triangles(mi)
		assert_lte(triangles, MAX_TRIANGLES, "%s is reduced to at most %d triangles (has %d)" % [kind, MAX_TRIANGLES, triangles])
		var size := _size(mi)
		var meshy: Vector3 = MESHY_SIZES[kind]
		var largest := maxf(size.x, maxf(size.y, size.z))
		var meshy_largest := maxf(meshy.x, maxf(meshy.y, meshy.z))
		for axis in 3:
			assert_almost_eq(size[axis] / largest, meshy[axis] / meshy_largest, 0.02, "%s is Meshy's, scaled as a whole (axis %d)" % [kind, axis])
		var material := mi.get_active_material(0) as StandardMaterial3D
		assert_not_null(material, "%s has a StandardMaterial3D" % kind)
		if material == null:
			continue
		for spec in [["colour", material.albedo_texture], ["normal", material.normal_texture]]:
			var texture: Texture2D = spec[1]
			assert_not_null(texture, "%s has Meshy's %s map" % [kind, spec[0]])
			if texture != null:
				assert_gte(mini(texture.get_width(), texture.get_height()), MIN_MAP, "%s's %s map is at least %d px" % [kind, spec[0], MIN_MAP])
