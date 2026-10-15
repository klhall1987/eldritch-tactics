extends GutTest
# The Resident Evil-style cultist (ticket #42): a smoothly skinned, decayed, bloodied zombie in
# robes, on the CC0 base-mesh pipeline, with photo-real, normal-mapped textures.
# (Criterion 4, "the existing cultist, scene, encounter and combat tests still pass", is covered by
# those test files themselves.)

const CULTIST_PATH := "res://assets/models/characters/cultist.glb"
const NOT_BODY := ["eye", "hair"]  # body and clothes: everything but eyes, hair and anything glowing
const FACE_PREFIXES := ["face", "skin"]
const CLOTHES_PREFIXES := ["robe", "rag", "wrap"]
const SHARED_WEIGHT := 0.05
const SAMPLE_SIZE := 128  # textures are shrunk to this before their colours are measured


# Every surface of the cultist as {"material": String, "emissive": bool, "texture": Texture2D or
# null, "normal_map": Texture2D or null, "vertices": int, "shared": int (vertices weighted to 2+
# bones above SHARED_WEIGHT)}, or [] (after failing).
func _surfaces() -> Array:
	var packed: PackedScene = load(CULTIST_PATH)
	assert_not_null(packed, "the cultist model (%s) loads" % CULTIST_PATH)
	if packed == null:
		return []
	var cultist := packed.instantiate() as Node3D
	add_child_autofree(cultist)
	var surfaces := []
	for mi: MeshInstance3D in cultist.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var count: int = arrays[Mesh.ARRAY_VERTEX].size()
			var shared := 0
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if weights != null and not weights.is_empty() and count > 0:
				var per_vertex: int = weights.size() / count
				for i in count:
					var bones := 0
					for k in per_vertex:
						if weights[i * per_vertex + k] > SHARED_WEIGHT:
							bones += 1
					if bones >= 2:
						shared += 1
			var material := mi.get_active_material(s) as BaseMaterial3D
			surfaces.append({
				"material": material.resource_name if material != null else "",
				"emissive": material != null and material.emission_enabled,
				"texture": material.albedo_texture if material != null else null,
				"normal_map": material.normal_texture if material != null and material.normal_enabled else null,
				"vertices": count,
				"shared": shared,
			})
	assert_gt(surfaces.size(), 0, "the cultist has surfaces")
	return surfaces


func _starts_with_any(material: String, prefixes: Array) -> bool:
	for prefix: String in prefixes:
		if material.begins_with(prefix):
			return true
	return false


func _texture_size(texture: Texture2D) -> int:
	return mini(texture.get_width(), texture.get_height()) if texture != null else 0


# A texture's pixels as an Image, decompressed and shrunk to SAMPLE_SIZE for measuring.
func _sample(texture: Texture2D) -> Image:
	var image := texture.get_image().duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGB8)
	image.resize(SAMPLE_SIZE, SAMPLE_SIZE, Image.INTERPOLATE_BILINEAR)
	return image


# Given the cultist (cultist.glb), when its body and clothes are inspected, then it is smoothly
# skinned: at least 25% of its vertices are influenced by two or more bones (each with weight above
# 0.05).
func test_cultist_is_smoothly_skinned():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	var vertices := 0
	var shared := 0
	for surface in surfaces:
		if surface.emissive or _starts_with_any(surface.material, NOT_BODY):
			continue
		vertices += surface.vertices
		shared += surface.shared
	assert_gt(vertices, 0, "the cultist has body and clothes vertices")
	if vertices > 0:
		var share := float(shared) / vertices
		assert_gte(share, 0.25, "at least 25%% of the body's vertices are shared between bones (%.1f%%)" % (share * 100.0))


# Given the cultist, when its materials are inspected, then its face/skin has an albedo texture at
# least 1024 px and a normal map, and at least three clothes materials (robe.../rag.../wrap...) have
# albedo textures at least 512 px.
func test_cultist_has_photo_real_normal_mapped_textures():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	var face_ok := false
	var best_face := 0
	for surface in surfaces:
		if _starts_with_any(surface.material, FACE_PREFIXES):
			best_face = maxi(best_face, _texture_size(surface.texture))
			if _texture_size(surface.texture) >= 1024 and surface.normal_map != null:
				face_ok = true
	assert_true(face_ok, "a face/skin material has a 1024 px albedo texture and a normal map (largest %d px)" % best_face)
	var clothes := {}
	for surface in surfaces:
		if _starts_with_any(surface.material, CLOTHES_PREFIXES) and _texture_size(surface.texture) >= 512:
			clothes[surface.material] = true
	assert_gte(clothes.size(), 3, "at least 3 clothes materials have 512 px textures (%s)" % [clothes.keys()])


# Given the cultist's textures, when their colours are measured, then the skin is corpse-pale (the
# face texture's average colour has a saturation below 0.25), and the clothes are bloodied (at least
# 3% of the pixels of one of the clothes textures are blood-red: red over 0.15 and more than 1.6
# times both green and blue).
func test_cultist_is_decayed_and_bloodied():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	var face_texture: Texture2D = null
	for surface in surfaces:
		if surface.material.begins_with("face") and _texture_size(surface.texture) > _texture_size(face_texture):
			face_texture = surface.texture
	assert_not_null(face_texture, "the cultist's face has a texture")
	if face_texture != null:
		var image := _sample(face_texture)
		var total := Color(0, 0, 0)
		for y in SAMPLE_SIZE:
			for x in SAMPLE_SIZE:
				var c := image.get_pixel(x, y)
				total = Color(total.r + c.r, total.g + c.g, total.b + c.b)
		var n := float(SAMPLE_SIZE * SAMPLE_SIZE)
		var average := Color(total.r / n, total.g / n, total.b / n)
		assert_lt(average.s, 0.25, "the skin is corpse-pale (average %s, saturation %.2f)" % [average, average.s])
	var bloodiest := 0.0
	var clothes_textures := 0
	for surface in surfaces:
		if not _starts_with_any(surface.material, CLOTHES_PREFIXES) or surface.texture == null:
			continue
		clothes_textures += 1
		var image := _sample(surface.texture)
		var blood := 0
		for y in SAMPLE_SIZE:
			for x in SAMPLE_SIZE:
				var c := image.get_pixel(x, y)
				if c.r > 0.15 and c.r > 1.6 * c.g and c.r > 1.6 * c.b:
					blood += 1
		bloodiest = maxf(bloodiest, float(blood) / (SAMPLE_SIZE * SAMPLE_SIZE))
	assert_gt(clothes_textures, 0, "the cultist's clothes are textured")
	assert_gte(bloodiest, 0.03, "a clothes texture is at least 3%% blood-red (bloodiest %.1f%%)" % (bloodiest * 100.0))
