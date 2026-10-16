extends GutTest
# The player character's clothes as separate, fitted pieces (ticket #67): a dark purple t-shirt, a
# grey sweater, blue jeans and dark sneakers, each its own glb in assets/models/clothes/, skinned to
# the character's skeleton (same bone names as character.glb) and fitted to his body in the rest
# pose, each naming the slot it fills.
#
# Interface these tests choose:
# - A piece names its slot with `slot` metadata (`top`, `bottom` or `feet`) on any node in it.
# - "Sleeves end above the elbows" means no tee vertex is weighted mostly to a forearm bone
#   (`lowerarm_l`/`lowerarm_r`); "long sleeves" means some sweater vertices are, on both arms.
#   "Covering both feet" means some sneaker vertices are weighted mostly to each foot
#   (`foot_*` or `ball_*`).
# - "Fits": in the rest pose, no body vertex pokes out through the piece (cloth within 2 cm behind
#   it along its normal, but none within 4 cm in front), and at least 90% of the piece's vertices
#   are within 3 cm of the body's surface (hems and cuffs may hang a little looser).
# - Colours are the average of a piece's albedo texture (sampled) times its albedo colour.

const CHARACTER_PATH := "res://assets/models/characters/character.glb"
const PIECES := {
	"tee_purple": "top",
	"sweater_grey": "top",
	"jeans_blue": "bottom",
	"sneakers_dark": "feet",
}
const CELL := 0.04  # metres: the spatial grid's cell size


func _path(piece: String) -> String:
	return "res://assets/models/clothes/%s.glb" % piece


# Loads and instantiates a glb, or returns null (after failing the test).
func _load(path: String) -> Node3D:
	var packed: PackedScene = load(path)
	assert_not_null(packed, "%s loads" % path)
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	add_child_autofree(node)
	return node


func _skeleton(node: Node) -> Skeleton3D:
	var skeletons := node.find_children("*", "Skeleton3D", true, false)
	return skeletons[0] if not skeletons.is_empty() else null


func _bone_names(skeleton: Skeleton3D) -> Array:
	var names := []
	if skeleton != null:
		for b in skeleton.get_bone_count():
			names.append(skeleton.get_bone_name(b))
	names.sort()
	return names


# Every surface of the meshes in `node` (or only those named `only`): points and normals in `node`'s
# space, triangles (index triples), material, texture, colour, and each vertex's strongest bone name.
func _surfaces(node: Node3D, only := "") -> Array:
	var surfaces := []
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if only != "" and mi.name != only:
			continue
		var to_node := node.global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var points := PackedVector3Array()
			var normals := PackedVector3Array()
			for v in arrays[Mesh.ARRAY_VERTEX]:
				points.append(to_node * v)
			for n in arrays[Mesh.ARRAY_NORMAL]:
				normals.append((to_node.basis * n).normalized())
			var indices = arrays[Mesh.ARRAY_INDEX]
			if indices == null or indices.is_empty():
				indices = PackedInt32Array(range(points.size()))
			var strongest := []
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if bones != null and not bones.is_empty() and mi.skin != null and points.size() > 0:
				var per_vertex: int = weights.size() / points.size()
				var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
				for i in points.size():
					var best := -1
					var best_weight := -1.0
					for k in per_vertex:
						if weights[i * per_vertex + k] > best_weight:
							best_weight = weights[i * per_vertex + k]
							best = bones[i * per_vertex + k]
					var bone_name := ""
					if best >= 0 and best < mi.skin.get_bind_count():
						bone_name = String(mi.skin.get_bind_name(best))
						if bone_name == "" and skeleton != null:
							bone_name = skeleton.get_bone_name(mi.skin.get_bind_bone(best))
					strongest.append(bone_name)
			var material := mi.get_active_material(s) as BaseMaterial3D
			surfaces.append({
				"mesh": mi,
				"points": points,
				"normals": normals,
				"indices": indices,
				"material": material.resource_name if material != null else "",
				"texture": material.albedo_texture if material != null else null,
				"colour": material.albedo_color if material != null else Color.WHITE,
				"strongest": strongest,
				"skinned": mi.skin != null and bones != null and not bones.is_empty(),
			})
	return surfaces


func _all_points(surfaces: Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	for surface in surfaces:
		points.append_array(surface.points)
	return points


# The average colour of a piece: its surfaces' textures (sampled) times their albedo colours,
# weighted by vertex count.
func _colour(surfaces: Array) -> Color:
	var total := Color(0, 0, 0, 0)
	var weight := 0.0
	for surface in surfaces:
		var colour: Color = surface.colour
		var texture: Texture2D = surface.texture
		var average := Color(1, 1, 1)
		if texture != null:
			var image := texture.get_image()
			if image.is_compressed():
				image.decompress()
			var sum := Color(0, 0, 0, 0)
			var samples := 0
			var step := maxi(1, image.get_width() / 32)
			for y in range(0, image.get_height(), step):
				for x in range(0, image.get_width(), step):
					var pixel := image.get_pixel(x, y)
					if pixel.a < 0.5:
						continue
					sum += pixel
					samples += 1
			if samples > 0:
				average = sum / samples
		var w := float(surface.points.size())
		total += Color(average.r * colour.r, average.g * colour.g, average.b * colour.b) * w
		weight += w
	return total / weight if weight > 0.0 else Color()


# A spatial grid of the triangles in `surfaces`: cell -> [[a, b, c, normal], ...].
func _grid(surfaces: Array) -> Dictionary:
	var grid := {}
	for surface in surfaces:
		var points: PackedVector3Array = surface.points
		var indices = surface.indices
		for t in range(0, indices.size() - 2, 3):
			var a := points[indices[t]]
			var b := points[indices[t + 1]]
			var c := points[indices[t + 2]]
			var normal := (b - a).cross(c - a)
			if normal.length() < 1e-12:
				continue
			normal = normal.normalized()
			var box := AABB(a, Vector3.ZERO).expand(b).expand(c)
			var lo := Vector3i((box.position / CELL).floor())
			var hi := Vector3i((box.end / CELL).floor())
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					for z in range(lo.z, hi.z + 1):
						var key := Vector3i(x, y, z)
						if not grid.has(key):
							grid[key] = []
						grid[key].append([a, b, c, normal])
	return grid


# The closest point to `p` on a triangle a-b-c.
func _closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denominator := 1.0 / (va + vb + vc)
	return a + ab * (vb * denominator) + ac * (vc * denominator)


# The closest point on the grid's triangles to `p` within `reach` (CELL-sized steps), as
# [point, normal], or [] if none is that close.
func _closest(grid: Dictionary, p: Vector3, reach := 1) -> Array:
	var cell := Vector3i((p / CELL).floor())
	var best := []
	var best_distance := INF
	for x in range(cell.x - reach, cell.x + reach + 1):
		for y in range(cell.y - reach, cell.y + reach + 1):
			for z in range(cell.z - reach, cell.z + reach + 1):
				for tri in grid.get(Vector3i(x, y, z), []):
					var q := _closest_on_triangle(p, tri[0], tri[1], tri[2])
					var d := p.distance_squared_to(q)
					if d < best_distance:
						best_distance = d
						best = [q, tri[3]]
	return best


# Whether a ray from `from` along `direction` (a unit vector) hits one of the grid's triangles within
# `reach` metres.
func _ray_hits(grid: Dictionary, from: Vector3, direction: Vector3, reach: float) -> bool:
	var seen := {}
	var steps := int(ceil(reach / (CELL * 0.5)))
	for i in steps + 1:
		var cell := Vector3i(((from + direction * (reach * i / steps)) / CELL).floor())
		for x in range(cell.x - 1, cell.x + 2):
			for y in range(cell.y - 1, cell.y + 2):
				for z in range(cell.z - 1, cell.z + 2):
					for tri in grid.get(Vector3i(x, y, z), []):
						var id: int = tri.hash()
						if seen.has(id):
							continue
						seen[id] = true
						var hit = Geometry3D.ray_intersects_triangle(from, direction, tri[0], tri[1], tri[2])
						if hit != null and from.distance_to(hit) <= reach:
							return true
	return false


# Given assets/models/clothes/, when its pieces are loaded, then there's tee_purple.glb,
# sweater_grey.glb, jeans_blue.glb and sneakers_dark.glb. Each has the same bone names as
# character.glb's skeleton, and its mesh is skinned to those bones.
func test_four_pieces_skinned_to_his_skeleton():
	var character := _load(CHARACTER_PATH)
	if character == null:
		return
	var bones := _bone_names(_skeleton(character))
	assert_gt(bones.size(), 0, "the character has a skeleton")
	for piece: String in PIECES:
		var node := _load(_path(piece))
		if node == null:
			continue
		var skeleton := _skeleton(node)
		assert_not_null(skeleton, "%s has a skeleton" % piece)
		assert_eq(_bone_names(skeleton), bones, "%s's skeleton has the character's bone names" % piece)
		var surfaces := _surfaces(node)
		assert_gt(surfaces.size(), 0, "%s has a mesh" % piece)
		for surface in surfaces:
			assert_true(surface.skinned, "%s's %s mesh is skinned" % [piece, surface.mesh.name])


# Given each piece, when it's inspected, then it names the slot it fills (top, bottom or feet), and
# its material looks right: the tee dark purple (hue 260-300 degrees, brightness at most 0.45) with
# sleeves ending above the elbows; the sweater grey (saturation at most 0.15) with long sleeves; the
# jeans denim blue (hue 200-235 degrees) reaching within 0.15 m of the floor; the sneakers dark
# (brightness at most 0.25), covering both feet.
func test_slots_colours_and_cut():
	var pieces := {}
	for piece: String in PIECES:
		var node := _load(_path(piece))
		if node == null:
			return
		var slot := ""
		for child in [node] + node.find_children("*", "", true, false):
			if child.has_meta("slot"):
				slot = str(child.get_meta("slot"))
		assert_eq(slot, PIECES[piece], "%s fills the %s slot" % [piece, PIECES[piece]])
		pieces[piece] = _surfaces(node)

	var tee := _colour(pieces.tee_purple)
	assert_between(tee.h * 360.0, 260.0, 300.0, "the tee is purple (hue %.0f)" % (tee.h * 360.0))
	assert_lte(tee.v, 0.45, "the tee is dark (brightness %.2f)" % tee.v)
	var forearm := 0
	for surface in pieces.tee_purple:
		for bone: String in surface.strongest:
			if bone.begins_with("lowerarm"):
				forearm += 1
	assert_eq(forearm, 0, "the tee's sleeves end above the elbows (%d vertices on a forearm)" % forearm)

	var sweater := _colour(pieces.sweater_grey)
	assert_lte(sweater.s, 0.15, "the sweater is grey (saturation %.2f)" % sweater.s)
	var sleeves := {"lowerarm_l": 0, "lowerarm_r": 0}
	for surface in pieces.sweater_grey:
		for bone: String in surface.strongest:
			if sleeves.has(bone):
				sleeves[bone] += 1
	assert_true(sleeves.lowerarm_l > 0 and sleeves.lowerarm_r > 0, "the sweater has long sleeves over both forearms (%s)" % sleeves)

	var jeans := _colour(pieces.jeans_blue)
	assert_between(jeans.h * 360.0, 200.0, 235.0, "the jeans are denim blue (hue %.0f)" % (jeans.h * 360.0))
	var lowest := INF
	for p in _all_points(pieces.jeans_blue):
		lowest = minf(lowest, p.y)
	assert_lte(lowest, 0.15, "the jeans reach within 0.15 m of the floor (down to %.2f m)" % lowest)

	var sneakers := _colour(pieces.sneakers_dark)
	assert_lte(sneakers.v, 0.25, "the sneakers are dark (brightness %.2f)" % sneakers.v)
	var feet := {"l": 0, "r": 0}
	for surface in pieces.sneakers_dark:
		for bone: String in surface.strongest:
			if bone.begins_with("foot_") or bone.begins_with("ball_"):
				feet[bone.right(1)] += 1
	assert_true(feet.l > 0 and feet.r > 0, "the sneakers cover both feet (%s)" % feet)


# Given each piece over character.glb in the rest pose, when they're compared, then it fits: no
# body vertex in the area it covers pokes out through it, and it sits no more than 3 cm off the body.
func test_pieces_fit_his_body():
	var character := _load(CHARACTER_PATH)
	if character == null:
		return
	var body := _surfaces(character, "body")
	assert_gt(body.size(), 0, "the character has a mesh named body")
	if body.is_empty():
		return
	var body_grid := _grid(body)
	var body_points := _all_points(body)
	for piece: String in PIECES:
		var node := _load(_path(piece))
		if node == null:
			continue
		var surfaces := _surfaces(node)
		var piece_grid := _grid(surfaces)
		# No body vertex pokes out through it: along the body's own normal, a vertex with cloth within
		# 2 cm behind it but none within 4 cm in front of it shows through. (Changed with the owner's
		# go-ahead on #67: judging by the nearest cloth misread clockwise triangles, hems and the
		# space between trouser legs.) The vertices it covers are those with cloth in front.
		var covered := 0
		var poking := 0
		for surface in body:
			var points: PackedVector3Array = surface.points
			var normals: PackedVector3Array = surface.normals
			for i in points.size():
				if _ray_hits(piece_grid, points[i], normals[i], 0.04):
					covered += 1
				elif _ray_hits(piece_grid, points[i], -normals[i], 0.02):
					poking += 1
		assert_gt(covered, 0, "%s covers some of his body" % piece)
		assert_eq(poking, 0, "no body vertex pokes out through %s (%d do)" % [piece, poking])
		# At least 90% of the piece's vertices are within 3 cm of his body.
		var near := 0
		var points := _all_points(surfaces)
		for p in points:
			var hit := _closest(body_grid, p)
			if not hit.is_empty() and p.distance_to(hit[0]) <= 0.03:
				near += 1
		var share := float(near) / maxf(1.0, points.size())
		assert_gte(share, 0.9, "%s sits within 3 cm of his body (%.0f%% of it does)" % [piece, share * 100.0])


# Given each piece, when its geometry and materials are inspected, then it's game-ready like the
# body: at most 6000 triangles, with an albedo texture of at least 512 px.
func test_pieces_are_game_ready():
	for piece: String in PIECES:
		var node := _load(_path(piece))
		if node == null:
			continue
		var triangles := 0
		var texture := 0
		for surface in _surfaces(node):
			triangles += surface.indices.size() / 3
			if surface.texture != null:
				texture = maxi(texture, mini(surface.texture.get_width(), surface.texture.get_height()))
		assert_between(triangles, 1, 6000, "%s has at most 6000 triangles (has %d)" % [piece, triangles])
		assert_gte(texture, 512, "%s has an albedo texture of at least 512 px (has %d)" % [piece, texture])
