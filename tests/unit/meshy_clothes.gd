extends RefCounted
# Shared measurements for the Meshy clothing pieces' tests (#145-#147). Not a test itself (no `test_`
# prefix): the tests load() it.
#
# Every point is measured as the Outfit draws it on him: a mesh's vertex is skinned with its own bind
# poses onto the character's skeleton in its rest pose, in the skeleton's space. So a piece whose
# skeleton doesn't match his shows up as a bad fit. The meshes are huge (Meshy's, as delivered), so the
# measurements sample up to SAMPLES vertices of each.

const CHARACTER_PATH := "res://assets/models/characters/character.glb"
const SAMPLES := 20000
const CELL := 0.05  # metres: the spatial grid's cell size
const NEAR := 0.05  # a piece's vertex counts as on his body within this
const COVERS := 0.08  # a body vertex is in the area a piece covers if one of its vertices is this close,
const ALONG := 30.0  # and within this many degrees of the body vertex's normal line (in front or behind)


# The first MeshInstance3D under `node`, or null.
static func mesh_of(node: Node) -> MeshInstance3D:
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	return meshes[0] if not meshes.is_empty() else null


# The character's Skeleton3D, or null.
static func skeleton_of(node: Node) -> Skeleton3D:
	var skeletons := node.find_children("*", "Skeleton3D", true, false)
	return skeletons[0] if not skeletons.is_empty() else null


# How many triangles `mi`'s mesh has, over all its surfaces.
static func triangles(mi: MeshInstance3D) -> int:
	var total := 0
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var indices = arrays[Mesh.ARRAY_INDEX]
		total += (indices.size() if indices != null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return total


# The bone of `skeleton` that bind `bind` of `skin` drives (by name when the skin names its bones).
static func _bone(skin: Skin, skeleton: Skeleton3D, bind: int) -> int:
	var name := skin.get_bind_name(bind)
	return skeleton.find_bone(name) if name != StringName() else skin.get_bind_bone(bind)


# Sampled vertices of `mi` as drawn on `skeleton` at rest: {"points": PackedVector3Array, "normals":
# PackedVector3Array, "uvs": PackedVector2Array, "bones": PackedStringArray (each vertex's strongest
# bone, "" if none), "missing": int (binds naming a bone his skeleton hasn't got)}.
static func drawn(mi: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	var out := {"points": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array(),
		"bones": PackedStringArray(), "missing": 0}
	var skin := mi.skin
	var binds := []  # bind -> [bone, rest * bind pose] or null
	if skin != null:
		for b in skin.get_bind_count():
			var bone := _bone(skin, skeleton, b)
			if bone < 0:
				out.missing += 1
				binds.append(null)
			else:
				binds.append([bone, skeleton.get_bone_global_rest(bone) * skin.get_bind_pose(b)])
	var total := 0
	for s in mi.mesh.get_surface_count():
		total += mi.mesh.surface_get_array_len(s)
	var step := maxi(1, total / SAMPLES)
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals = arrays[Mesh.ARRAY_NORMAL]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var per_vertex: int = weights.size() / vertices.size() if weights != null and vertices.size() > 0 else 0
		for i in range(0, vertices.size(), step):
			var at := Vector3.ZERO
			var basis := Basis()
			var strongest := ""
			var strongest_w := 0.0
			var weighed := 0.0
			for k in per_vertex:
				var w: float = weights[i * per_vertex + k]
				if w <= 0.0:
					continue
				var bind = binds[bones[i * per_vertex + k]] if skin != null else null
				if bind == null:
					continue
				var xf: Transform3D = bind[1]
				at += (xf * vertices[i]) * w
				basis = xf.basis if weighed == 0.0 else basis
				weighed += w
				if w > strongest_w:
					strongest_w = w
					strongest = skeleton.get_bone_name(bind[0])
			if weighed <= 0.0:
				at = mi.transform * vertices[i]
			else:
				at /= weighed
			out.points.append(at)
			out.normals.append((basis * normals[i]).normalized() if normals != null else Vector3.ZERO)
			out.uvs.append(uvs[i] if uvs != null else Vector2.ZERO)
			out.bones.append(strongest)
	return out


static func _cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))


# A spatial grid of `points`: cell -> PackedInt32Array of indices.
static func grid(points: PackedVector3Array) -> Dictionary:
	var cells := {}
	for i in points.size():
		var c := _cell(points[i])
		if not cells.has(c):
			cells[c] = PackedInt32Array()
		cells[c].append(i)
	return cells


# The index of the point in `points` (gridded as `cells`) nearest to `p` within `reach` (at most two
# cells), or -1.
static func nearest(points: PackedVector3Array, cells: Dictionary, p: Vector3, reach: float) -> int:
	var best := -1
	var best_d := reach
	var c := _cell(p)
	var span := ceili(reach / CELL)
	for x in range(-span, span + 1):
		for y in range(-span, span + 1):
			for z in range(-span, span + 1):
				var key := c + Vector3i(x, y, z)
				if not cells.has(key):
					continue
				for i: int in cells[key]:
					var d := points[i].distance_to(p)
					if d < best_d:
						best_d = d
						best = i
	return best


# The index of the point in `points` (gridded as `cells`) nearest to `p` within `reach` that lies
# within ALONG degrees of the line through `p` along `normal` (in front of `p` or behind it), or -1.
static func nearest_along(points: PackedVector3Array, cells: Dictionary, p: Vector3, normal: Vector3, reach: float) -> int:
	var best := -1
	var best_d := reach
	var within := cos(deg_to_rad(ALONG))
	var c := _cell(p)
	var span := ceili(reach / CELL)
	for x in range(-span, span + 1):
		for y in range(-span, span + 1):
			for z in range(-span, span + 1):
				var key := c + Vector3i(x, y, z)
				if not cells.has(key):
					continue
				for i: int in cells[key]:
					var offset := points[i] - p
					var d := offset.length()
					if d < best_d and d > 0.0 and absf(offset.dot(normal)) / d >= within:
						best_d = d
						best = i
	return best


# How the piece's mesh `piece` fits his body `body`, both drawn on `skeleton` at rest: {"near": share
# of the piece's vertices within NEAR of his body's, "covered": how many body vertices lie in the area
# it covers (a piece vertex within COVERS, roughly along the body vertex's normal: within ALONG
# degrees, agreed on #145, so his jaw beside a collar or his forearm past a cuff isn't counted),
# "poking": the share of those that poke out through it (that piece vertex lies behind them, along the
# body's normal)}. With `only_bones`, only body vertices mostly following one of those bones count as
# covered.
static func fit(piece: MeshInstance3D, body: MeshInstance3D, skeleton: Skeleton3D, only_bones := PackedStringArray()) -> Dictionary:
	var cloth := drawn(piece, skeleton)
	var skin := drawn(body, skeleton)
	var skin_cells := grid(skin.points)
	var near := 0
	for p in cloth.points:
		if nearest(skin.points, skin_cells, p, NEAR) >= 0:
			near += 1
	var cloth_cells := grid(cloth.points)
	var covered := 0
	var poking := 0
	for i in skin.points.size():
		if not only_bones.is_empty() and not skin.bones[i] in only_bones:
			continue
		var j := nearest_along(cloth.points, cloth_cells, skin.points[i], skin.normals[i], COVERS)
		if j < 0:
			continue
		covered += 1
		if (cloth.points[j] - skin.points[i]).dot(skin.normals[i]) < 0.0:
			poking += 1
	return {
		"near": float(near) / maxi(1, cloth.points.size()),
		"covered": covered,
		"poking": float(poking) / maxi(1, covered),
	}


# The average colour of `mi`'s colour texture where its sampled vertices' UVs land, times its albedo
# colour (as #116's tests sample textures).
static func colour(mi: MeshInstance3D, skeleton: Skeleton3D) -> Color:
	var material := mi.get_active_material(0) as BaseMaterial3D
	if material == null:
		return Color(0, 0, 0, 0)
	if material.albedo_texture == null:
		return material.albedo_color
	var image := material.albedo_texture.get_image()
	if image.is_compressed():
		image.decompress()
	var total := Color(0, 0, 0, 0)
	var uvs: PackedVector2Array = drawn(mi, skeleton).uvs
	for uv in uvs:
		var x := clampi(int(fposmod(uv.x, 1.0) * image.get_width()), 0, image.get_width() - 1)
		var y := clampi(int(fposmod(uv.y, 1.0) * image.get_height()), 0, image.get_height() - 1)
		total += image.get_pixel(x, y)
	var average := total / maxi(1, uvs.size())
	return Color(average.r * material.albedo_color.r, average.g * material.albedo_color.g, average.b * material.albedo_color.b)


# The shortest side of `mi`'s colour texture, or 0.
static func texture_size(mi: MeshInstance3D) -> int:
	var material := mi.get_active_material(0) as BaseMaterial3D
	if material == null or material.albedo_texture == null:
		return 0
	return mini(material.albedo_texture.get_width(), material.albedo_texture.get_height())
