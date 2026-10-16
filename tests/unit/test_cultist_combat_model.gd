extends GutTest
# The cultist's combat model (ticket #33): a more detailed cultist_combat.glb, built by the same
# script at a higher detail level, used by the combat screen, while the garage keeps cultist.glb.
# It's measured the way #22's tests (tests/unit/test_cultist_detail.gd) measure the garage model.

const GARAGE_MODEL := "res://assets/models/characters/cultist.glb"
const COMBAT_MODEL := "res://assets/models/characters/cultist_combat.glb"
const FACE_PREFIXES := ["face", "skin"]
const CLOTHES_PREFIXES := ["robe", "rag", "wrap"]


# Loads and instantiates a model, or returns null (after failing the test).
func _model(path: String) -> Node3D:
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the model %s loads" % path)
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	add_child_autofree(model)
	return model


# Every surface of a model as {"material": String, "emissive": bool, "points":
# PackedVector3Array (in the model's space), "triangles": Array of [Vector3, Vector3, Vector3]}.
func _surfaces(model: Node3D) -> Array:
	var surfaces := []
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var to_model := model.global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var points := PackedVector3Array()
			for v in arrays[Mesh.ARRAY_VERTEX]:
				points.append(to_model * v)
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
				"points": points,
				"triangles": triangles,
			})
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


func _triangles(surfaces: Array) -> int:
	var total := 0
	for surface in surfaces:
		total += surface.triangles.size()
	return total


# Face and skin triangles in the top 25% of the height, as #22 counts them.
func _face_triangles(surfaces: Array) -> int:
	var box := _bounds(surfaces)
	var face_line := box.position.y + 0.75 * box.size.y
	var count := 0
	for surface in surfaces:
		if _is(surface, FACE_PREFIXES) and not _is(surface, CLOTHES_PREFIXES):
			for tri in surface.triangles:
				if (tri[0] + tri[1] + tri[2]).y / 3.0 >= face_line:
					count += 1
	return count


func _direction(p: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(p.x, p.z)), 360.0)


func _bone_names(model: Node) -> Array:
	var names := []
	for skeleton: Skeleton3D in model.find_children("*", "Skeleton3D", true, false):
		for i in skeleton.get_bone_count():
			names.append(skeleton.get_bone_name(i))
	names.sort()
	return names


# Given the project, when res://assets/models/characters/cultist_combat.glb is loaded, then it
# loads, and has at least twice as many triangles as cultist.glb and at most 40000.
func test_combat_model_is_twice_as_detailed():
	var garage := _model(GARAGE_MODEL)
	var combat := _model(COMBAT_MODEL)
	if garage == null or combat == null:
		return
	var garage_triangles := _triangles(_surfaces(garage))
	var combat_triangles := _triangles(_surfaces(combat))
	assert_gte(combat_triangles, 2 * garage_triangles,
		"the combat model has at least twice the garage model's %d triangles (has %d)" % [garage_triangles, combat_triangles])
	assert_lte(combat_triangles, 40000, "the combat model has at most 40000 triangles (has %d)" % combat_triangles)


# Given the combat model, when its clothes and face are measured the way #22's tests measure the
# garage model, then it is still rounded and ragged (at least 16 directions at 0.5-0.7 m, at least 3
# clothes materials, a hem spread of at least 0.08 m), with at least twice the garage model's face
# triangles.
func test_combat_model_is_still_rounded_and_ragged_with_a_finer_face():
	var garage := _model(GARAGE_MODEL)
	var combat := _model(COMBAT_MODEL)
	if garage == null or combat == null:
		return
	var surfaces := _surfaces(combat)
	var directions := {}
	var lowest := {}  # sector -> lowest clothes height in it
	var materials := {}
	for surface in surfaces:
		if not _is(surface, CLOTHES_PREFIXES):
			continue
		materials[surface.material] = true
		for p: Vector3 in surface.points:
			if p.y >= 0.5 and p.y <= 0.7:
				directions[int(_direction(p) / 5.0)] = true
			var sector := int(_direction(p) / 22.5) % 16
			lowest[sector] = minf(lowest.get(sector, INF), p.y)
	assert_gte(directions.size(), 16, "the clothes at 0.5-0.7 m face at least 16 directions (face %d)" % directions.size())
	assert_gte(materials.size(), 3, "the clothes use at least 3 materials (use %s)" % [materials.keys()])
	assert_eq(lowest.size(), 16, "the clothes reach all 16 sectors around the cultist")
	if lowest.size() == 16:
		var hem: Array = lowest.values()
		assert_gte(hem.max() - hem.min(), 0.08, "the hem is ragged (spread %.3f m)" % (hem.max() - hem.min()))
	var garage_face := _face_triangles(_surfaces(garage))
	var combat_face := _face_triangles(surfaces)
	assert_gte(combat_face, 2 * garage_face,
		"the face has at least twice the garage model's %d triangles (has %d)" % [garage_face, combat_face])


# Given the combat model, when it is compared with cultist.glb, then it has the same height (within
# 2 cm), the same bone names, and looping idle and walk clips, and its only emissive material is
# the eyes.
func test_combat_model_matches_the_garage_model():
	var garage := _model(GARAGE_MODEL)
	var combat := _model(COMBAT_MODEL)
	if garage == null or combat == null:
		return
	var surfaces := _surfaces(combat)
	assert_almost_eq(_bounds(surfaces).size.y, _bounds(_surfaces(garage)).size.y, 0.02,
		"the combat model is as tall as the garage model")
	var bones := _bone_names(combat)
	assert_gt(bones.size(), 0, "the combat model has a skeleton")
	assert_eq(bones, _bone_names(garage), "the combat model has the same bones")
	var players := combat.find_children("*", "AnimationPlayer", true, false)
	assert_eq(players.size(), 1, "the combat model has one AnimationPlayer")
	if not players.is_empty():
		var player := players[0] as AnimationPlayer
		for clip in ["idle", "walk"]:
			assert_true(player.has_animation(clip), "the combat model has %s" % clip)
			if player.has_animation(clip):
				assert_ne(player.get_animation(clip).loop_mode, Animation.LOOP_NONE, "%s loops" % clip)
	var glowing := []
	for surface in surfaces:
		if surface.emissive:
			glowing.append(surface.material)
	assert_gt(glowing.size(), 0, "the eyes glow")
	for material: String in glowing:
		assert_true(material.begins_with("eye"), "only the eyes glow (%s does too)" % material)

