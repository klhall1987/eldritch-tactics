extends GutTest
# Smaller, compressed tee and jeans textures (ticket #131): the tee's and jeans' colour and normal maps
# (#82) are 1024 px, compressed for the GPU like the other clothes, with the normal maps imported as
# normal maps, and each glb is at most 6 MB.
#
# Interface these tests choose:
# - A piece's textures are its material's `albedo_texture` and `normal_texture` (#82), and their import
#   settings are in each texture file's `.import` file: `compress/mode=2` is VRAM compression, and
#   `compress/normal_map=1` imports it as a normal map.

const PIECES := ["res://assets/models/clothes/tee_purple.glb", "res://assets/models/clothes/jeans_blue.glb"]
const MAX_GLB_BYTES := 6 * 1024 * 1024


# [[texture, "albedo" or "normal"], ...] for the piece at `path`.
func _textures(path: String) -> Array:
	var packed: PackedScene = load(path)
	assert_not_null(packed, "%s loads" % path)
	if packed == null:
		return []
	var piece := packed.instantiate()
	var out := []
	for mi: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var material := mi.get_active_material(s) as BaseMaterial3D
			if material == null:
				continue
			if material.albedo_texture != null:
				out.append([material.albedo_texture, "albedo"])
			if material.normal_texture != null:
				out.append([material.normal_texture, "normal"])
	piece.free()
	assert_gte(out.size(), 2, "%s has a colour map and a normal map" % path.get_file())
	return out


func _import_setting(texture: Texture2D, key: String) -> String:
	var text := FileAccess.get_file_as_string(texture.resource_path + ".import")
	for line in text.split("\n"):
		if line.begins_with(key + "="):
			return line.substr(key.length() + 1).strip_edges()
	return ""


# Given the tee and jeans, when their textures are inspected, then each colour and normal map is 1024 px.
func test_textures_are_1024_px():
	for path: String in PIECES:
		for entry: Array in _textures(path):
			var texture: Texture2D = entry[0]
			assert_eq(Vector2i(texture.get_width(), texture.get_height()), Vector2i(1024, 1024),
				"%s's %s map is 1024 px (%dx%d)" % [path.get_file(), entry[1], texture.get_width(), texture.get_height()])


# Given those textures, when their import settings are checked, then they're VRAM-compressed, and the
# normal maps are imported as normal maps.
func test_textures_are_compressed_for_the_gpu():
	for path: String in PIECES:
		for entry: Array in _textures(path):
			var texture: Texture2D = entry[0]
			assert_eq(_import_setting(texture, "compress/mode"), "2", "%s's %s map is VRAM-compressed (%s)" % [path.get_file(), entry[1], texture.resource_path.get_file()])
			if entry[1] == "normal":
				assert_eq(_import_setting(texture, "compress/normal_map"), "1", "%s's normal map is imported as a normal map" % path.get_file())


# Given the rebuilt pieces, when the files are measured, then each glb is at most 6 MB.
func test_pieces_are_at_most_6_mb():
	for path: String in PIECES:
		var bytes := FileAccess.get_file_as_bytes(path).size()
		assert_gt(bytes, 0, "%s exists" % path.get_file())
		assert_lte(bytes, MAX_GLB_BYTES, "%s is at most 6 MB (%.1f MB)" % [path.get_file(), bytes / 1048576.0])
