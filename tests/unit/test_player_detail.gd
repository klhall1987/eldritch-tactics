extends GutTest
# A more lifelike player character (ticket #116): character.glb has a denser body, and skin with a
# normal map and varying roughness; in the game his skin uses subsurface scattering.
#
# Interface these tests choose:
# - His body is character.glb's surfaces whose material is named `skin*` (#65).
# - Textures are sampled where those surfaces' UVs land (as in #82's and #115's tests). A normal-map
#   texel's tilt is the angle between its decoded normal (each channel x 2 - 1) and flat (0, 0, 1).
# - Roughness is the roughness texture's channel the material reads (glTF: green), times the
#   material's roughness; its span is from its 5th to its 95th percentile over the sampled vertices.
# - In the game, his skin material is the active material of the `skin*` surfaces under
#   `Player/Character` in the main scene.

const CHARACTER_PATH := "res://assets/models/characters/character.glb"


func _skin_surfaces(root: Node) -> Array:
	var out := []
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var material := mi.get_active_material(s) as BaseMaterial3D
			if material != null and material.resource_name.begins_with("skin"):
				out.append({"arrays": mi.mesh.surface_get_arrays(s), "material": material})
	assert_gt(out.size(), 0, "he has skin surfaces")
	return out


func _character() -> Node3D:
	var packed: PackedScene = load(CHARACTER_PATH)
	assert_not_null(packed, "%s loads" % CHARACTER_PATH)
	if packed == null:
		return null
	var character := packed.instantiate() as Node3D
	add_child_autofree(character)
	return character


func _image(texture: Texture2D) -> Image:
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	return image


func _sample(image: Image, uv: Vector2) -> Color:
	var x := clampi(int(fposmod(uv.x, 1.0) * image.get_width()), 0, image.get_width() - 1)
	var y := clampi(int(fposmod(uv.y, 1.0) * image.get_height()), 0, image.get_height() - 1)
	return image.get_pixel(x, y)


func _channel(c: Color, channel: int) -> float:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_RED:
			return c.r
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return c.g
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return c.b
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return c.a
	return (c.r + c.g + c.b) / 3.0


# Given character.glb, when his body is measured, then it has at least 6,000 triangles.
func test_a_denser_body():
	var character := _character()
	if character == null:
		return
	var triangles := 0
	for surface: Dictionary in _skin_surfaces(character):
		var indices = surface.arrays[Mesh.ARRAY_INDEX]
		triangles += (indices.size() if indices != null else surface.arrays[Mesh.ARRAY_VERTEX].size()) / 3
	assert_gte(triangles, 6000, "his body has at least 6,000 triangles (%d)" % triangles)


# Given his skin material, when it's inspected, then it has a normal map of at least 1024 px whose
# normals are on average at least 5 degrees off flat, and a roughness texture whose values span at least
# 0.2.
func test_skin_detail_maps():
	var character := _character()
	if character == null:
		return
	for surface: Dictionary in _skin_surfaces(character):
		var material: BaseMaterial3D = surface.material
		assert_not_null(surface.arrays[Mesh.ARRAY_TEX_UV], "his skin has UVs")
		if surface.arrays[Mesh.ARRAY_TEX_UV] == null:
			continue
		var uvs: PackedVector2Array = surface.arrays[Mesh.ARRAY_TEX_UV]
		assert_true(material.normal_enabled and material.normal_texture != null, "his skin has a normal map")
		if material.normal_texture != null:
			var size := mini(material.normal_texture.get_width(), material.normal_texture.get_height())
			assert_gte(size, 1024, "the normal map is at least 1024 px (%d)" % size)
			var image := _image(material.normal_texture)
			var tilt := 0.0
			for uv in uvs:
				var c := _sample(image, uv)
				var n := Vector3(c.r * 2.0 - 1.0, c.g * 2.0 - 1.0, c.b * 2.0 - 1.0)
				if n.length() > 0.01:
					tilt += rad_to_deg(n.normalized().angle_to(Vector3(0, 0, 1)))
			tilt /= uvs.size()
			assert_gte(tilt, 5.0, "his skin's normal map carries detail (%.1f degrees off flat on average)" % tilt)
		assert_not_null(material.roughness_texture, "his skin has a roughness texture")
		if material.roughness_texture != null:
			var image := _image(material.roughness_texture)
			var values := []
			for uv in uvs:
				values.append(_channel(_sample(image, uv), material.roughness_texture_channel) * material.roughness)
			values.sort()
			var span: float = values[int(values.size() * 0.95)] - values[int(values.size() * 0.05)]
			assert_gte(span, 0.2, "his skin's roughness varies (spans %.2f)" % span)


# Given he's in the main scene, when his skin material is inspected, then subsurface scattering is on
# (strength 0.1-0.6), and the project's subsurface scattering quality isn't disabled.
func test_soft_skin_in_the_game():
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var main := (load(path) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	var character := main.find_child("Character", true, false)
	assert_not_null(character, "the main scene has Player/Character")
	if character == null:
		return
	for surface: Dictionary in _skin_surfaces(character):
		var material: BaseMaterial3D = surface.material
		assert_true(material.subsurf_scatter_enabled, "his skin scatters light under its surface")
		assert_between(material.subsurf_scatter_strength, 0.1, 0.6, "its subsurface scattering is gentle (%.2f)" % material.subsurf_scatter_strength)
	var quality: int = ProjectSettings.get_setting("rendering/environment/subsurface_scattering/subsurface_scattering_quality", 1)
	assert_ne(quality, 0, "the project's subsurface scattering isn't disabled")
