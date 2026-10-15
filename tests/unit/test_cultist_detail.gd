extends GutTest
# The detailed cultist (ticket #22): a slender, Silent Hill-style cultist with a sculpted face and
# layered, rounded, ragged clothes. Parts are told apart by material name: the face is `face...`
# or `skin...`; the clothes are `robe...`, `rag...` or `wrap...`.
# (Criterion 5, "the existing cultist and garage scene tests still pass", is covered by those
# test files themselves: tests/unit/test_cultist_model.gd and the scene tests.)

const CULTIST_PATH := "res://assets/models/characters/cultist.glb"
const FACE_PREFIXES := ["face", "skin"]
const CLOTHES_PREFIXES := ["robe", "rag", "wrap"]


# Every surface of the cultist as {"material": String, "points": PackedVector3Array (in the
# cultist's space), "triangles": Array of [Vector3, Vector3, Vector3]}, or [] (after failing).
func _surfaces() -> Array:
	var packed: PackedScene = load(CULTIST_PATH)
	assert_not_null(packed, "the cultist model (%s) loads" % CULTIST_PATH)
	if packed == null:
		return []
	var cultist := packed.instantiate() as Node3D
	add_child_autofree(cultist)
	var surfaces := []
	for mi: MeshInstance3D in cultist.find_children("*", "MeshInstance3D", true, false):
		var to_cultist := cultist.global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var points := PackedVector3Array()
			for v in arrays[Mesh.ARRAY_VERTEX]:
				points.append(to_cultist * v)
			var indices = arrays[Mesh.ARRAY_INDEX]
			if indices == null or indices.is_empty():
				indices = range(points.size())
			var triangles := []
			for t in range(0, indices.size() - 2, 3):
				triangles.append([points[indices[t]], points[indices[t + 1]], points[indices[t + 2]]])
			var material := mi.get_active_material(s)
			surfaces.append({
				"material": material.resource_name if material != null else "",
				"points": points,
				"triangles": triangles,
			})
	assert_gt(surfaces.size(), 0, "the cultist has surfaces")
	return surfaces


func _is(surface: Dictionary, prefixes: Array) -> bool:
	for prefix: String in prefixes:
		if String(surface.material).begins_with(prefix):
			return true
	return false


func _bounds(surfaces: Array) -> AABB:
	var box := AABB()
	var first := true
	for surface in surfaces:
		for p: Vector3 in surface.points:
			box = AABB(p, Vector3.ZERO) if first else box.expand(p)
			first = false
	return box


func _clothes_points(surfaces: Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	for surface in surfaces:
		if _is(surface, CLOTHES_PREFIXES):
			points.append_array(surface.points)
	return points


# Degrees (0-360) around the vertical axis of a point, from +Z towards +X.
func _direction(p: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(p.x, p.z)), 360.0)


# Given the instantiated cultist, when its triangles are counted, then the whole model has between
# 3000 and 15000 (the current model has 244); its face (surfaces whose material name starts with
# face or skin, in the top 25% of its height) has at least 400, and its clothes (surfaces whose
# material name starts with robe, rag or wrap) have at least 1500.
func test_cultist_is_detailed_in_face_and_clothes():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	var box := _bounds(surfaces)
	var face_line := box.position.y + 0.75 * box.size.y
	var total := 0
	var face := 0
	var clothes := 0
	for surface in surfaces:
		total += surface.triangles.size()
		if _is(surface, CLOTHES_PREFIXES):
			clothes += surface.triangles.size()
		elif _is(surface, FACE_PREFIXES):
			for tri in surface.triangles:
				if (tri[0] + tri[1] + tri[2]).y / 3.0 >= face_line:
					face += 1
	assert_between(total, 3000, 15000, "the cultist has 3000-15000 triangles (has %d)" % total)
	assert_gte(face, 400, "the cultist's face has at least 400 triangles (has %d)" % face)
	assert_gte(clothes, 1500, "the cultist's clothes have at least 1500 triangles (has %d)" % clothes)


# Given the instantiated cultist, when its rest-pose bounds are measured, then it is at most
# 0.55 m wide along X (currently 0.70 m) and at most 0.6 m deep along Z (currently 0.72 m).
func test_cultist_is_slender():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	var box := _bounds(surfaces)
	assert_lte(box.size.x, 0.55, "the cultist is at most 0.55 m wide along X (is %.2f m)" % box.size.x)
	assert_lte(box.size.z, 0.6, "the cultist is at most 0.6 m deep along Z (is %.2f m)" % box.size.z)


# Given the cultist's clothes, when the clothes vertices between 0.5 m and 0.7 m high are grouped by
# direction around the vertical axis in 5-degree steps, then they cover at least 16 different
# directions (the shroud is rounded, not 6-sided), and the clothes use at least 3 different
# materials (layers, not one sheet).
func test_cultist_shroud_is_rounded_and_layered():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	var directions := {}
	for p in _clothes_points(surfaces):
		if p.y >= 0.5 and p.y <= 0.7:
			directions[int(_direction(p) / 5.0)] = true
	assert_gte(directions.size(), 16,
		"the clothes at 0.5-0.7 m face at least 16 directions (face %d)" % directions.size())
	var materials := {}
	for surface in surfaces:
		if _is(surface, CLOTHES_PREFIXES):
			materials[surface.material] = true
	assert_gte(materials.size(), 3, "the clothes use at least 3 materials (use %s)" % materials.keys())


# Given the same clothes, when the lowest clothes point is found in each of 16 equal sectors around
# the vertical axis, then the highest and lowest of those 16 hem heights differ by at least
# 0.08 m: the hem is ragged, not a flat ring.
func test_cultist_hem_is_ragged():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	var lowest := {}  # sector -> lowest clothes height in it
	for p in _clothes_points(surfaces):
		var sector := int(_direction(p) / 22.5) % 16
		lowest[sector] = minf(lowest.get(sector, INF), p.y)
	assert_eq(lowest.size(), 16, "the clothes reach all 16 sectors around the cultist")
	if lowest.size() < 16:
		return
	var hem: Array = lowest.values()
	var spread: float = hem.max() - hem.min()
	assert_gte(spread, 0.08, "the hem's height varies by at least 0.08 m around the cultist (%.3f m)" % spread)
