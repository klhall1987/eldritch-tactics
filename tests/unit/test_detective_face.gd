extends GutTest
# The detective's PS2-era face (ticket #25): a detailed, smooth-shaded head with a painted face
# texture, two separate (non-glowing) eyes, and hair crowning the head. Parts are told apart by
# material name: the face and skin are `face...` or `skin...`, the eyes `eye...`, the hair `hair...`.

const DETECTIVE_PATH := "res://assets/models/characters/detective.glb"
const FACE_PREFIXES := ["face", "skin"]
const SAME_POSITION := 0.0001  # metres: vertices this close count as one position


# Every surface of the detective as {"material": String, "emissive": bool, "texture": Texture2D or
# null, "points": PackedVector3Array (in the detective's space), "triangles": Array of
# [Vector3, Vector3, Vector3]}, or [] (after failing).
func _surfaces() -> Array:
	var packed: PackedScene = load(DETECTIVE_PATH)
	assert_not_null(packed, "the detective model (%s) loads" % DETECTIVE_PATH)
	if packed == null:
		return []
	var detective := packed.instantiate() as Node3D
	add_child_autofree(detective)
	var surfaces := []
	for mi: MeshInstance3D in detective.find_children("*", "MeshInstance3D", true, false):
		var to_detective := detective.global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var points := PackedVector3Array()
			for v in arrays[Mesh.ARRAY_VERTEX]:
				points.append(to_detective * v)
			var indices = arrays[Mesh.ARRAY_INDEX]
			if indices == null or indices.is_empty():
				indices = range(points.size())
			var triangles := []
			for t in range(0, indices.size() - 2, 3):
				triangles.append([points[indices[t]], points[indices[t + 1]], points[indices[t + 2]]])
			var material := mi.get_active_material(s) as BaseMaterial3D
			surfaces.append({
				"material": material.resource_name if material != null else "",
				"emissive": material != null and material.emission_enabled,
				"texture": material.albedo_texture if material != null else null,
				"points": points,
				"triangles": triangles,
			})
	assert_gt(surfaces.size(), 0, "the detective has surfaces")
	return surfaces


func _starts_with_any(material: String, prefixes: Array) -> bool:
	for prefix: String in prefixes:
		if material.begins_with(prefix):
			return true
	return false


func _bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box


func _model_bounds(surfaces: Array) -> AABB:
	var points := PackedVector3Array()
	for surface in surfaces:
		points.append_array(surface.points)
	return _bounds(points)


func _centroid(triangle: Array) -> Vector3:
	return (triangle[0] + triangle[1] + triangle[2]) / 3.0


func _distinct_positions(points: PackedVector3Array) -> int:
	var seen := {}
	for p in points:
		seen[Vector3i((p / SAME_POSITION).round())] = true
	return seen.size()


func _texture_size(texture: Texture2D) -> int:
	return mini(texture.get_width(), texture.get_height()) if texture != null else 0


# Given the instantiated detective, when the triangles of its face and skin surfaces (material
# names starting face or skin) in the top 15% of its height are counted, then there are at least
# 1500, and those surfaces have at most 1.6 vertices per distinct position (smooth-shaded).
func test_head_is_detailed_and_smooth():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	var box := _model_bounds(surfaces)
	var head_line := box.end.y - 0.15 * box.size.y
	var head_triangles := 0
	var vertices := 0
	var positions := 0
	for surface in surfaces:
		if not _starts_with_any(surface.material, FACE_PREFIXES):
			continue
		vertices += surface.points.size()
		positions += _distinct_positions(surface.points)
		for triangle in surface.triangles:
			if _centroid(triangle).y >= head_line:
				head_triangles += 1
	assert_gte(head_triangles, 1500, "the head's face and skin have at least 1500 triangles (have %d)" % head_triangles)
	assert_gt(positions, 0, "the detective has face or skin surfaces")
	if positions > 0:
		var ratio := float(vertices) / positions
		assert_lte(ratio, 1.6, "the face and skin have at most 1.6 vertices per position (have %.2f)" % ratio)


# Given the detective's face material, when it is inspected, then it has an albedo texture at least
# 512 pixels on its shorter side.
func test_face_is_textured():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	var best := -1  # -1: no face material at all
	for surface in surfaces:
		if surface.material.begins_with("face"):
			best = maxi(best, _texture_size(surface.texture))
	assert_gte(best, 0, "the detective has a face material (name starting face)")
	assert_gte(best, 512, "the face has an albedo texture of at least 512 px (has %d)" % maxi(best, 0))


# Given the instantiated detective, when its eyes (surfaces whose material name starts with eye)
# are measured, then there are two separate eyes on the front of the head, each with at least 80
# triangles, mirrored left and right within 1 cm of each other, and neither is emissive.
func test_two_mirrored_eyes_on_the_front():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	var box := _model_bounds(surfaces)
	var head_line := box.end.y - 0.15 * box.size.y
	var head_points := PackedVector3Array()
	for surface in surfaces:
		for p: Vector3 in surface.points:
			if p.y >= head_line:
				head_points.append(p)
	var head_centre := _bounds(head_points).get_center()

	# Split the eye triangles into the eye on the detective's left (+X) and the one on his right.
	var sides := {"left": [], "right": []}
	for surface in surfaces:
		if not surface.material.begins_with("eye"):
			continue
		assert_false(surface.emissive, "the eye material %s doesn't glow" % surface.material)
		for triangle in surface.triangles:
			sides["left" if _centroid(triangle).x > 0.0 else "right"].append(triangle)
	var centres := {}
	for side in sides:
		var triangles: Array = sides[side]
		assert_gte(triangles.size(), 80, "the %s eye has at least 80 triangles (has %d)" % [side, triangles.size()])
		if triangles.is_empty():
			continue
		var sum := Vector3.ZERO
		for triangle in triangles:
			sum += _centroid(triangle)
		centres[side] = sum / triangles.size()
		assert_gte(centres[side].y, head_line, "the %s eye is in the head" % side)
		assert_gt(centres[side].z, head_centre.z, "the %s eye is on the front of the head" % side)
	if centres.size() < 2:
		return
	var left: Vector3 = centres.left
	var right: Vector3 = centres.right
	assert_lte(absf(left.x + right.x), 0.01, "the eyes are mirrored left-right (x %.3f vs %.3f)" % [left.x, right.x])
	assert_lte(absf(left.y - right.y), 0.01, "the eyes are at the same height (%.3f vs %.3f)" % [left.y, right.y])
	assert_lte(absf(left.z - right.z), 0.01, "the eyes are equally far forward (%.3f vs %.3f)" % [left.z, right.z])


# Given the detective's hair (surfaces whose material name starts with hair), when it is measured,
# then it has at least 400 triangles, and its highest point is within 2 cm of the top of the
# model (the hair crowns the head).
func test_hair_crowns_the_head():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	var top := _model_bounds(surfaces).end.y
	var triangles := 0
	var hair_top := -INF
	for surface in surfaces:
		if not surface.material.begins_with("hair"):
			continue
		triangles += surface.triangles.size()
		for p: Vector3 in surface.points:
			hair_top = maxf(hair_top, p.y)
	assert_gte(triangles, 400, "the hair has at least 400 triangles (has %d)" % triangles)
	assert_gt(hair_top, -INF, "the detective has hair")
	if hair_top > -INF:
		assert_lte(top - hair_top, 0.02, "the hair reaches within 2 cm of the top (%.3f m below)" % (top - hair_top))
