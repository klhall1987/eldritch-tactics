extends GutTest
# A detailed, textured monster (ticket #115): monster.glb's skin has a varied albedo texture (a darker
# back, a paler underside), a baked normal map, a roughness texture that's glossy in places and matte in
# others, and its legs have knobbly knees, while #106-#112's monster tests still hold.
#
# Interface these tests choose (the monster in its rest pose, in its own space):
# - Its skin material is the one named `monster_skin*` (#106).
# - Textures are sampled where the skin's vertices' UVs land (as in #82's tests). Brightness is the mean
#   of red, green and blue, times the material's albedo colour.
# - A vertex faces down when its normal's y is at most -0.707 (45 degrees below horizontal), up when at
#   least 0.707.
# - A normal-map texel's tilt is the angle between its decoded normal (each channel x 2 - 1) and flat
#   (0, 0, 1).
# - Roughness is the roughness texture's channel the material reads (glTF: green), times the material's
#   roughness. "Some" parts means at least 5% of the skin's vertices.
# - A leg's line runs through its bones' heads (#106). Its thickness somewhere is the average distance
#   from that line of its skin's vertices whose nearest point on the line is within 0.04 m of there.
#   The knee is the lower leg bone's head; halfway is the middle of the upper segment.

const MONSTER_PATH := "res://assets/models/characters/monster.glb"


func _monster() -> Node3D:
	var packed: PackedScene = load(MONSTER_PATH)
	assert_not_null(packed, "%s loads" % MONSTER_PATH)
	if packed == null:
		return null
	var monster := packed.instantiate() as Node3D
	add_child_autofree(monster)
	return monster


# The skin's surfaces: [{"arrays", "material"}, ...].
func _skin_surfaces(monster: Node) -> Array:
	var out := []
	for mi: MeshInstance3D in monster.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var material := mi.get_active_material(s) as StandardMaterial3D
			if material != null and material.resource_name.begins_with("monster_skin"):
				out.append({"arrays": mi.mesh.surface_get_arrays(s), "material": material, "mesh": mi})
	assert_gt(out.size(), 0, "it has a monster_skin surface")
	return out


func _image(texture: Texture2D) -> Image:
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	return image


func _sample(image: Image, uv: Vector2) -> Color:
	var x := clampi(int(fposmod(uv.x, 1.0) * image.get_width()), 0, image.get_width() - 1)
	var y := clampi(int(fposmod(uv.y, 1.0) * image.get_height()), 0, image.get_height() - 1)
	return image.get_pixel(x, y)


func _brightness(c: Color) -> float:
	return (c.r + c.g + c.b) / 3.0


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
	return _brightness(c)


# Given its skin material, when it's inspected, then it has an albedo texture of at least 512 px whose
# brightness where its UVs land varies (standard deviation at least 0.04), while staying dark overall
# (at most 0.35).
func test_a_varied_dark_hide():
	var monster := _monster()
	if monster == null:
		return
	for surface: Dictionary in _skin_surfaces(monster):
		var material: StandardMaterial3D = surface.material
		assert_not_null(material.albedo_texture, "its skin has an albedo texture")
		if material.albedo_texture == null:
			continue
		var size := mini(material.albedo_texture.get_width(), material.albedo_texture.get_height())
		assert_gte(size, 512, "the albedo texture is at least 512 px (%d)" % size)
		var image := _image(material.albedo_texture)
		var values := []
		for uv: Vector2 in surface.arrays[Mesh.ARRAY_TEX_UV]:
			values.append(_brightness(_sample(image, uv) * material.albedo_color))
		var mean: float = values.reduce(func(a, b): return a + b, 0.0) / values.size()
		var spread: float = sqrt(values.reduce(func(a, b): return a + (b - mean) * (b - mean), 0.0) / values.size())
		assert_gte(spread, 0.04, "its hide varies (standard deviation %.3f)" % spread)
		assert_lte(mean, 0.35, "its hide stays dark (brightness %.3f)" % mean)


# Given its skin, when the albedo is sampled at its vertices, then vertices facing down average at least
# 1.3 times the brightness of those facing up.
func test_a_paler_underside():
	var monster := _monster()
	if monster == null:
		return
	var up := 0.0
	var up_count := 0
	var down := 0.0
	var down_count := 0
	for surface: Dictionary in _skin_surfaces(monster):
		var material: StandardMaterial3D = surface.material
		if material.albedo_texture == null:
			fail_test("its skin has an albedo texture")
			return
		var image := _image(material.albedo_texture)
		assert_not_null(surface.arrays[Mesh.ARRAY_TEX_UV], "its skin has UVs")
		if surface.arrays[Mesh.ARRAY_TEX_UV] == null:
			continue
		var uvs: PackedVector2Array = surface.arrays[Mesh.ARRAY_TEX_UV]
		var normals: PackedVector3Array = surface.arrays[Mesh.ARRAY_NORMAL]
		for i in uvs.size():
			var brightness := _brightness(_sample(image, uvs[i]) * material.albedo_color)
			if normals[i].y >= 0.707:
				up += brightness
				up_count += 1
			elif normals[i].y <= -0.707:
				down += brightness
				down_count += 1
	assert_true(up_count > 0 and down_count > 0, "it has skin facing up and down (%d up, %d down)" % [up_count, down_count])
	if up_count == 0 or down_count == 0:
		return
	up /= up_count
	down /= down_count
	assert_gte(down, up * 1.3, "its underside is paler than its back (%.3f vs %.3f)" % [down, up])


# Given its skin material, when it's inspected, then it has a normal map of at least 512 px whose normals
# are on average at least 10 degrees off flat, and a roughness texture with some parts glossy (at most
# 0.35) and some matte (at least 0.6).
func test_baked_detail_and_glossy_chitin():
	var monster := _monster()
	if monster == null:
		return
	for surface: Dictionary in _skin_surfaces(monster):
		var material: StandardMaterial3D = surface.material
		assert_not_null(surface.arrays[Mesh.ARRAY_TEX_UV], "its skin has UVs")
		if surface.arrays[Mesh.ARRAY_TEX_UV] == null:
			continue
		var uvs: PackedVector2Array = surface.arrays[Mesh.ARRAY_TEX_UV]
		assert_true(material.normal_enabled and material.normal_texture != null, "its skin has a normal map")
		if material.normal_texture != null:
			var size := mini(material.normal_texture.get_width(), material.normal_texture.get_height())
			assert_gte(size, 512, "the normal map is at least 512 px (%d)" % size)
			var image := _image(material.normal_texture)
			var tilt := 0.0
			for uv in uvs:
				var c := _sample(image, uv)
				var n := Vector3(c.r * 2.0 - 1.0, c.g * 2.0 - 1.0, c.b * 2.0 - 1.0)
				if n.length() > 0.01:
					tilt += rad_to_deg(n.normalized().angle_to(Vector3(0, 0, 1)))
			tilt /= uvs.size()
			assert_gte(tilt, 10.0, "its normal map carries detail (%.1f degrees off flat on average)" % tilt)
		assert_not_null(material.roughness_texture, "its skin has a roughness texture")
		if material.roughness_texture != null:
			var image := _image(material.roughness_texture)
			var glossy := 0
			var matte := 0
			for uv in uvs:
				var r := _channel(_sample(image, uv), material.roughness_texture_channel) * material.roughness
				if r <= 0.35:
					glossy += 1
				elif r >= 0.6:
					matte += 1
			assert_gte(glossy, uvs.size() * 0.05, "some of its skin is glossy (%d of %d)" % [glossy, uvs.size()])
			assert_gte(matte, uvs.size() * 0.05, "some of its skin is matte (%d of %d)" % [matte, uvs.size()])


# Given its legs, when their skin is measured, then each knee is at least 1.5 times as thick as halfway
# along the upper segment.
func test_knobbly_knees():
	var monster := _monster()
	if monster == null:
		return
	var skeleton := monster.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var to_monster := monster.global_transform.affine_inverse() * skeleton.global_transform
	# Every skinned vertex: [position, bone it follows most].
	var vertices := []
	for mi: MeshInstance3D in monster.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null:
			continue
		var into := monster.global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			var per_vertex: int = weights.size() / points.size()
			for i in points.size():
				var best := -1
				var best_w := 0.0
				for k in per_vertex:
					if weights[i * per_vertex + k] > best_w:
						best_w = weights[i * per_vertex + k]
						var bind: int = bones[i * per_vertex + k]
						best = skeleton.find_bone(mi.skin.get_bind_name(bind)) if mi.skin.get_bind_name(bind) != StringName() else mi.skin.get_bind_bone(bind)
				vertices.append([into * points[i], best])
	var legs := 0
	for b in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(b)
		var parent := skeleton.get_bone_parent(b)
		if not name.begins_with("leg") or (parent >= 0 and skeleton.get_bone_name(parent).begins_with("leg")):
			continue
		var chain := [b]
		var at := b
		while true:
			var next := -1
			for child in skeleton.get_bone_children(at):
				if skeleton.get_bone_name(child).begins_with("leg"):
					next = child
			if next < 0:
				break
			chain.append(next)
			at = next
		if chain.size() < 3:
			continue
		legs += 1
		var hip := (to_monster * skeleton.get_bone_global_rest(chain[0])).origin
		var knee := (to_monster * skeleton.get_bone_global_rest(chain[1])).origin
		var foot := (to_monster * skeleton.get_bone_global_rest(chain[2])).origin
		var halfway := (hip + knee) / 2.0
		var around_knee := []
		var around_halfway := []
		for v: Array in vertices:
			if not chain.has(v[1]):
				continue
			var p: Vector3 = v[0]
			var on_upper := Geometry3D.get_closest_point_to_segment(p, hip, knee)
			var on_lower := Geometry3D.get_closest_point_to_segment(p, knee, foot)
			var nearest := on_upper if p.distance_to(on_upper) <= p.distance_to(on_lower) else on_lower
			if nearest.distance_to(knee) <= 0.04:
				around_knee.append(p.distance_to(nearest))
			elif nearest.distance_to(halfway) <= 0.04:
				around_halfway.append(p.distance_to(nearest))
		assert_true(not around_knee.is_empty() and not around_halfway.is_empty(), "%s has skin at its knee and halfway up" % name)
		if around_knee.is_empty() or around_halfway.is_empty():
			continue
		var knee_thick: float = around_knee.reduce(func(a, b): return a + b, 0.0) / around_knee.size()
		var mid_thick: float = around_halfway.reduce(func(a, b): return a + b, 0.0) / around_halfway.size()
		assert_gte(knee_thick, mid_thick * 1.5, "%s has a knobbly knee (%.3f m vs %.3f m halfway up)" % [name, knee_thick, mid_thick])
	assert_gte(legs, 4, "it has legs to measure")
