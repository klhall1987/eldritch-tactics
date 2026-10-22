extends GutTest
# The garage's floor and walls are the Meshy basement pieces (ticket #164): its floor and two back
# walls are built from the owner's Meshy floor tile, wall sections, wall corner and window strip, each
# scaled as a whole and reduced once, with Meshy's maps; the furniture, the bulb and the room's shape
# stay as they were (still checked by test_garage_model.gd).
#
# Interface these tests choose (positions in the garage's space: +Y up, its back walls on -X and -Z):
# - A Meshy piece is a MeshInstance3D named for the piece it is, then anything (`floor_tile_3`,
#   `wall_section_1`, `wall_corner`, `window_wall`; #165 adds `doorway_wall`, `wooden_door`,
#   `garage_door` and `stairs`). Its size is its mesh's own bounds times its node's scale on each
#   axis; MESHY_SIZES holds each piece's size as Meshy delivered it (x, up, depth).
# - "Scaled as a whole": each of its sizes, over its largest, is within 0.02 of Meshy's.
# - Its back walls are the `wall_west` and `wall_north` parts and everything under them. The room's
#   footprint is the whole garage's bounds. A wall "covers its edge" when, sampled every 0.01 m along
#   that edge (from the back corner to 0.5 m short of the open camera side) at 0.3 m, 1.0 m and 2.2 m
#   high, no stretch longer than 0.05 m lies outside every piece of that wall (and the `garage_door`,
#   which stands in a wall) within 0.6 m of the edge.
# - The wall corner is "where they meet" when its bounds come within 0.3 m of the footprint's back
#   corner; the window strip is "high" when its bottom is at least 1.2 m up.
# - A material's maps are its StandardMaterial3D's albedo and normal textures.

const GARAGE_PATH := "res://assets/models/environments/garage.glb"
# piece -> its size as Meshy delivered it: [x, up, depth] (metres; Meshy fit each to a 1.9 m box).
const MESHY_SIZES := {
	"floor_tile": Vector3(1.88, 0.18, 1.90),
	"wall_section": Vector3(1.11, 1.90, 0.19),
	"wall_corner": Vector3(1.20, 1.90, 1.20),
	"window_wall": Vector3(1.90, 0.89, 0.11),
	"doorway_wall": Vector3(1.43, 1.90, 0.20),
	"wooden_door": Vector3(0.93, 1.90, 0.18),
	"garage_door": Vector3(1.90, 1.60, 0.07),
	"stairs": Vector3(1.90, 1.29, 0.58),
}
const SHELL := ["floor_tile", "wall_section", "wall_corner", "window_wall"]
const MAX_TRIANGLES := 50000
const MIN_MAP := 1024


func _garage() -> Node3D:
	var packed: PackedScene = load(GARAGE_PATH)
	assert_not_null(packed, "the garage model (%s) loads" % GARAGE_PATH)
	if packed == null:
		return null
	var garage := packed.instantiate() as Node3D
	add_child_autofree(garage)
	return garage


func _part(garage: Node3D, name: String) -> Node3D:
	var part := garage.find_child(name, true, false) as Node3D
	assert_not_null(part, "the garage has its %s" % name)
	return part


# Every MeshInstance3D at or under `node`.
func _meshes(node: Node) -> Array:
	var found := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		found.append(node)
	return found


# The piece `mi` is (a key of MESHY_SIZES), or "".
func _kind(mi: Node) -> String:
	for kind: String in MESHY_SIZES:
		if str(mi.name).begins_with(kind):
			return kind
	return ""


func _pieces(node: Node, kinds: Array) -> Array:
	return _meshes(node).filter(func(mi: MeshInstance3D) -> bool: return _kind(mi) in kinds)


# A mesh's bounds in the garage's space.
func _box(garage: Node3D, mi: MeshInstance3D) -> AABB:
	return (garage.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()


func _boxes(garage: Node3D, node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in _meshes(node):
		box = _box(garage, mi) if first else box.merge(_box(garage, mi))
		first = false
	return box


# A piece's size: its mesh's own bounds, times its node's scale on each axis.
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


func _image(texture: Texture2D) -> Image:
	var image := texture.get_image()
	if image != null and image.is_compressed():
		image.decompress()
	return image


# Checks every piece in `pieces` is Meshy's, scaled as a whole and reduced, with Meshy's maps.
func _check_pieces(pieces: Array) -> void:
	for mi: MeshInstance3D in pieces:
		var kind := _kind(mi)
		var triangles := _triangles(mi)
		assert_lte(triangles, MAX_TRIANGLES, "%s is reduced to at most %d triangles (has %d)" % [mi.name, MAX_TRIANGLES, triangles])
		var size := _size(mi)
		var meshy: Vector3 = MESHY_SIZES[kind]
		var largest := maxf(size.x, maxf(size.y, size.z))
		var meshy_largest := maxf(meshy.x, maxf(meshy.y, meshy.z))
		for axis in 3:
			var ours := size[axis] / largest
			var theirs := meshy[axis] / meshy_largest
			assert_almost_eq(ours, theirs, 0.02, "%s is Meshy's %s scaled as a whole (axis %d: %.3f of its largest, Meshy's %.3f)" % [mi.name, kind, axis, ours, theirs])


func _check_maps(pieces: Array) -> void:
	for mi: MeshInstance3D in pieces:
		var material := mi.get_active_material(0) as StandardMaterial3D
		assert_not_null(material, "%s has a StandardMaterial3D" % mi.name)
		if material == null:
			continue
		for spec in [["colour", material.albedo_texture], ["normal", material.normal_texture]]:
			var texture: Texture2D = spec[1]
			assert_not_null(texture, "%s has Meshy's %s map" % [mi.name, spec[0]])
			if texture != null:
				assert_gte(mini(texture.get_width(), texture.get_height()), MIN_MAP, "%s's %s map is at least %d px (%dx%d)" % [mi.name, spec[0], MIN_MAP, texture.get_width(), texture.get_height()])
		assert_true(material.normal_enabled, "%s's normal map is used" % mi.name)
		if material.albedo_texture == null:
			continue
		var image := _image(material.albedo_texture)
		var lo := 1.0
		var hi := 0.0
		for i in 400:
			var c := image.get_pixel((i * 97) % image.get_width(), (i * 61) % image.get_height())
			lo = minf(lo, c.v)
			hi = maxf(hi, c.v)
		assert_gt(hi - lo, 0.1, "%s's colour map is Meshy's painted one (texels range %.2f-%.2f)" % [mi.name, lo, hi])


# The longest stretch (metres) along a back wall's edge that `covering` leaves open.
# `axis` is the axis the wall runs along (0 x, 2 z); `at` its edge's other coordinate.
func _longest_gap(garage: Node3D, covering: Array, axis: int, at: float, from: float, to: float) -> float:
	var across := 2 if axis == 0 else 0
	var boxes := covering.map(func(mi: MeshInstance3D) -> AABB: return _box(garage, mi)).filter(
		func(b: AABB) -> bool: return b.position[across] <= at + 0.6 and b.end[across] >= at - 0.6)
	var longest := 0.0
	for height in [0.3, 1.0, 2.2]:
		var run := 0.0
		var s := from
		while s <= to:
			var covered := false
			for b: AABB in boxes:
				if b.position[axis] <= s and s <= b.end[axis] and b.position.y <= height and height <= b.end.y:
					covered = true
					break
			run = 0.0 if covered else run + 0.01
			longest = maxf(longest, run)
			s += 0.01
	return longest


# Given garage.glb, when its floor is inspected, then the part named floor is made of Meshy's floor
# tile, repeated to cover the room's 8 m by 6 m footprint (within 0.3 m), with its top at y = 0 (within
# 0.02 m).
func test_the_floor_is_meshys_tiles():
	var garage := _garage()
	if garage == null:
		return
	var floor_part := _part(garage, "floor")
	if floor_part == null:
		return
	var meshes := _meshes(floor_part)
	var tiles := _pieces(floor_part, ["floor_tile"])
	assert_gt(tiles.size(), 1, "the floor is Meshy's floor tile, repeated (%d tiles)" % tiles.size())
	assert_eq(tiles.size(), meshes.size(), "the floor is only floor tiles (%d of %d meshes)" % [tiles.size(), meshes.size()])
	if tiles.is_empty():
		return
	var box := AABB()
	for i in tiles.size():
		box = _box(garage, tiles[i]) if i == 0 else box.merge(_box(garage, tiles[i]))
	assert_almost_eq(box.size.x, 8.0, 0.3, "the tiles cover the room's 8 m along X (%.2f m)" % box.size.x)
	assert_almost_eq(box.size.z, 6.0, 0.3, "the tiles cover the room's 6 m along Z (%.2f m)" % box.size.z)
	assert_almost_eq(box.end.y, 0.0, 0.02, "the floor's top is at y = 0 (%.3f)" % box.end.y)


# Given its back walls, when they're inspected, then each of wall_west and wall_north is made of Meshy's
# wall pieces (wall sections, the wall corner where they meet, and the window strip high on
# wall_north), covering its edge end to end up to where the camera sides open, with no gap wider than
# 0.05 m between pieces, standing 2.5 m high, the camera sides still open.
func test_the_back_walls_are_meshys_pieces():
	var garage := _garage()
	if garage == null:
		return
	var west := _part(garage, "wall_west")
	var north := _part(garage, "wall_north")
	if west == null or north == null:
		return
	var footprint := _boxes(garage, garage)
	for wall: Node3D in [west, north]:
		assert_gt(_pieces(wall, ["wall_section"]).size(), 0, "%s has Meshy's wall sections" % wall.name)
		var top := _boxes(garage, wall).end.y
		assert_between(top, 2.45, 2.6, "%s stands 2.5 m high (%.2f m)" % [wall.name, top])
	var corners := _pieces(west, ["wall_corner"]) + _pieces(north, ["wall_corner"])
	assert_eq(corners.size(), 1, "one of the walls has Meshy's wall corner")
	if corners.size() == 1:
		var corner := _box(garage, corners[0])
		var gap := Vector2(maxf(corner.position.x - footprint.position.x, 0.0), maxf(corner.position.z - footprint.position.z, 0.0)).length()
		assert_lte(gap, 0.3, "the corner is where the walls meet (%.2f m from the back corner)" % gap)
	var windows := _pieces(north, ["window_wall"])
	assert_eq(windows.size(), 1, "wall_north has Meshy's window strip")
	if windows.size() == 1:
		var bottom := _box(garage, windows[0]).position.y
		assert_gte(bottom, 1.2, "the window is high on the wall (its bottom %.2f m up)" % bottom)
	var door := garage.find_child("garage_door", true, false)
	var door_meshes := _meshes(door) if door != null else []
	var west_gap := _longest_gap(garage, _meshes(west) + door_meshes, 2, footprint.position.x, footprint.position.z, footprint.end.z - 0.5)
	assert_lte(west_gap, 0.05, "wall_west covers its edge end to end (longest gap %.2f m)" % west_gap)
	var north_gap := _longest_gap(garage, _meshes(north) + door_meshes, 0, footprint.position.z, footprint.position.x, footprint.end.x - 0.5)
	assert_lte(north_gap, 0.05, "wall_north covers its edge end to end (longest gap %.2f m)" % north_gap)


# Given each Meshy piece in the garage, when its mesh is measured, then it has at most 50,000 triangles
# and is still Meshy's piece, scaled as a whole: the same proportions within 2%.
func test_each_piece_is_reduced_and_scaled_as_a_whole():
	var garage := _garage()
	if garage == null:
		return
	var pieces := _pieces(garage, SHELL)
	for kind: String in SHELL:
		assert_gt(_pieces(garage, [kind]).size(), 0, "the garage has Meshy's %s" % kind)
	_check_pieces(pieces)


# Given each Meshy piece's material, when it's inspected, then it uses Meshy's colour and normal maps for
# that piece, each at least 1024 px.
func test_each_piece_has_meshys_maps():
	var garage := _garage()
	if garage == null:
		return
	var pieces := _pieces(garage, SHELL)
	assert_gt(pieces.size(), 0, "the garage has Meshy's pieces")
	_check_maps(pieces)


# Given art/base/README.md, when it's read, then its Meshy section names the basement pieces the garage
# is built from.
func test_the_readme_names_the_pieces():
	var readme := FileAccess.get_file_as_string("res://art/base/README.md")
	assert_ne(readme, "", "art/base/README.md is there")
	var start := readme.find("## Meshy")
	assert_ne(start, -1, "art/base/README.md has a Meshy section")
	if start < 0:
		return
	var rest := readme.substr(start + 1)
	var next := rest.find("\n## ")
	var section := rest if next < 0 else rest.substr(0, next)
	for piece in ["Floor_Tile", "Wall_Section", "Wall_Corner", "Garage_Door_"]:
		assert_true(piece in section, "the Meshy section names the %s piece" % piece)
