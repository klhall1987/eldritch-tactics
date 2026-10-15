extends GutTest
# The Resident Evil-style detective (ticket #41): rebuilt from a CC0 base mesh, smoothly skinned so
# his joints bend, with photo-real, normal-mapped textures and a more detailed face.
# (Criterion 4, "the existing detective, scene, movement and combat tests still pass", is covered by
# those test files themselves.)

const DETECTIVE_PATH := "res://assets/models/characters/detective.glb"
const NOT_BODY := ["eye", "hair"]  # body and clothes: everything but eyes, hair and the glowing amulet
const NOT_CLOTHES := ["coat", "face", "skin", "eye", "hair"]
const FACE_PREFIXES := ["face", "skin"]
const SHARED_WEIGHT := 0.05


# Every surface of the detective as {"material": String, "emissive": bool, "texture": Texture2D or
# null, "normal_map": Texture2D or null, "points": PackedVector3Array (in the detective's space),
# "triangles": Array of [Vector3, Vector3, Vector3], "influences": Array of ints (per vertex, how
# many bones weigh in above SHARED_WEIGHT)}, or [] (after failing).
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
			var influences := []
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if weights != null and not weights.is_empty() and points.size() > 0:
				var per_vertex: int = weights.size() / points.size()
				for i in points.size():
					var count := 0
					for k in per_vertex:
						if weights[i * per_vertex + k] > SHARED_WEIGHT:
							count += 1
					influences.append(count)
			var material := mi.get_active_material(s) as BaseMaterial3D
			surfaces.append({
				"material": material.resource_name if material != null else "",
				"emissive": material != null and material.emission_enabled,
				"texture": material.albedo_texture if material != null else null,
				"normal_map": material.normal_texture if material != null and material.normal_enabled else null,
				"points": points,
				"triangles": triangles,
				"influences": influences,
			})
	assert_gt(surfaces.size(), 0, "the detective has surfaces")
	return surfaces


func _starts_with_any(material: String, prefixes: Array) -> bool:
	for prefix: String in prefixes:
		if material.begins_with(prefix):
			return true
	return false


func _texture_size(texture: Texture2D) -> int:
	return mini(texture.get_width(), texture.get_height()) if texture != null else 0


# Given the detective (detective.glb), when its body and clothes are inspected, then it is smoothly
# skinned: at least 25% of its vertices are influenced by two or more bones (each with weight above
# 0.05), so knees, elbows, shoulders and neck bend instead of the parts moving rigidly.
func test_detective_is_smoothly_skinned():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	var vertices := 0
	var shared := 0
	for surface in surfaces:
		if surface.emissive or _starts_with_any(surface.material, NOT_BODY):
			continue
		vertices += surface.points.size()
		for count: int in surface.influences:
			if count >= 2:
				shared += 1
	assert_gt(vertices, 0, "the detective has body and clothes vertices")
	if vertices > 0:
		var share := float(shared) / vertices
		assert_gte(share, 0.25, "at least 25%% of the body's vertices are shared between bones (%.1f%%)" % (share * 100.0))


# Given the detective, when its materials are inspected, then the face and the coat each have an
# albedo texture at least 1024 px and a normal map, and at least two other clothing materials have
# albedo textures at least 512 px.
func test_detective_has_photo_real_normal_mapped_textures():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	for part in ["face", "coat"]:
		var best := -1  # -1: no such material at all
		var normal_mapped := false
		for surface in surfaces:
			if surface.material.begins_with(part):
				best = maxi(best, _texture_size(surface.texture))
				normal_mapped = normal_mapped or surface.normal_map != null
		assert_gte(best, 1024, "the %s has an albedo texture of at least 1024 px (%d)" % [part, best])
		assert_true(normal_mapped, "the %s has a normal map" % part)
	var clothes := {}
	for surface in surfaces:
		if not surface.emissive and not _starts_with_any(surface.material, NOT_CLOTHES) and _texture_size(surface.texture) >= 512:
			clothes[surface.material] = true
	assert_gte(clothes.size(), 2, "at least 2 other clothing materials have 512 px textures (%s)" % [clothes.keys()])


# Given the detective, when the triangles of its face and skin surfaces (face.../skin...) in the top
# 15% of its height are counted, then there are at least 3000 (double #25's minimum).
func test_detective_face_is_twice_as_detailed():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	var box := AABB()
	var first := true
	for surface in surfaces:
		for p: Vector3 in surface.points:
			box = AABB(p, Vector3.ZERO) if first else box.expand(p)
			first = false
	var head_line := box.end.y - 0.15 * box.size.y
	var count := 0
	for surface in surfaces:
		if _starts_with_any(surface.material, FACE_PREFIXES):
			for tri in surface.triangles:
				if (tri[0] + tri[1] + tri[2]).y / 3.0 >= head_line:
					count += 1
	assert_gte(count, 3000, "the head's face and skin have at least 3000 triangles (have %d)" % count)
