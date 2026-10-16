extends GutTest
# Readable fabric textures on the tee and jeans (ticket #82): each has a normal map from the garment's
# own detail, and its colour texture shows visible fabric detail where its UVs actually sample it,
# rather than flat colour. (Criterion 3, "#67's checks still pass unchanged", is covered by
# tests/unit/test_clothing_pieces.gd itself.)
#
# Interface these tests choose: "the pixels its UVs actually use" are the albedo texture sampled at
# every vertex's UV and every triangle's centre.

const PIECES := ["tee_purple", "jeans_blue"]


func _surfaces(piece: String) -> Array:
	var path := "res://assets/models/clothes/%s.glb" % piece
	var packed: PackedScene = load(path)
	assert_not_null(packed, "%s loads" % path)
	if packed == null:
		return []
	var node := packed.instantiate() as Node3D
	add_child_autofree(node)
	var surfaces := []
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			surfaces.append({"arrays": mi.mesh.surface_get_arrays(s), "material": mi.get_active_material(s) as BaseMaterial3D})
	assert_gt(surfaces.size(), 0, "%s has a mesh" % piece)
	return surfaces


func _image(texture: Texture2D) -> Image:
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	return image


func _sample(image: Image, uv: Vector2) -> Color:
	var x := clampi(int(fposmod(uv.x, 1.0) * image.get_width()), 0, image.get_width() - 1)
	var y := clampi(int(fposmod(uv.y, 1.0) * image.get_height()), 0, image.get_height() - 1)
	return image.get_pixel(x, y)


# Given tee_purple.glb and jeans_blue.glb, when their materials are inspected, then each has a normal
# map (made from the garment's own detail, such as the tee's T-shirt_basic-bump.png) of at least
# 512 px.
func test_tee_and_jeans_have_normal_maps():
	for piece: String in PIECES:
		for surface in _surfaces(piece):
			var material: BaseMaterial3D = surface.material
			assert_not_null(material, "%s has a material" % piece)
			if material == null:
				continue
			assert_true(material.normal_enabled, "%s's material uses a normal map" % piece)
			var normal := material.normal_texture
			assert_not_null(normal, "%s has a normal map texture" % piece)
			if normal != null:
				var size := mini(normal.get_width(), normal.get_height())
				assert_gte(size, 512, "%s's normal map is at least 512 px (is %d)" % [piece, size])


# Given each one's albedo texture, when the pixels its UVs actually use are measured, then the fabric
# detail is visible: their brightness has a standard deviation of at least 0.05 (today's tee is
# nearly flat).
func test_fabric_detail_shows_in_the_colour():
	for piece: String in PIECES:
		var values := PackedFloat32Array()
		for surface in _surfaces(piece):
			var material: BaseMaterial3D = surface.material
			if material == null or material.albedo_texture == null:
				continue
			var image := _image(material.albedo_texture)
			var uvs: PackedVector2Array = surface.arrays[Mesh.ARRAY_TEX_UV]
			var indices = surface.arrays[Mesh.ARRAY_INDEX]
			for uv in uvs:
				values.append(_sample(image, uv).v)
			if indices != null:
				for t in range(0, indices.size() - 2, 3):
					values.append(_sample(image, (uvs[indices[t]] + uvs[indices[t + 1]] + uvs[indices[t + 2]]) / 3.0).v)
		assert_gt(values.size(), 0, "%s's texture is sampled" % piece)
		if values.is_empty():
			continue
		var mean := 0.0
		for v in values:
			mean += v
		mean /= values.size()
		var variance := 0.0
		for v in values:
			variance += (v - mean) * (v - mean)
		var deviation := sqrt(variance / values.size())
		assert_gte(deviation, 0.05, "%s's fabric detail shows (brightness standard deviation %.3f)" % [piece, deviation])
