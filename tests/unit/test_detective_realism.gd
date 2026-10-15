extends GutTest
# The realistic detective body (ticket #24): a PS2-era detective, with realistic proportions,
# smooth-shaded surfaces and textured clothes, and no hat. Parts are told apart by material name:
# the coat is `coat...`; `face`, `skin`, `eye` and `hair` materials aren't clothes; the amulet is
# the emissive one.
# (Criterion 5, "the existing detective and scene tests still pass", is covered by those test
# files themselves: tests/unit/test_detective_model.gd and the scene tests.)

const DETECTIVE_PATH := "res://assets/models/characters/detective.glb"
const NOT_CLOTHES := ["coat", "face", "skin", "eye", "hair"]
const NOT_BODY := ["eye", "hair"]  # detailed in ticket #25, so not held to this ticket's smoothness
const MIN_TEXTURE := 256  # pixels on the shorter side
const SAME_POSITION := 0.0001  # metres: vertices this close count as one position


# Every surface of the detective as {"material": String, "emissive": bool, "texture": Texture2D
# or null, "points": PackedVector3Array (in the detective's space), "triangles": int}, or [].
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
			var material := mi.get_active_material(s) as BaseMaterial3D
			surfaces.append({
				"material": material.resource_name if material != null else "",
				"emissive": material != null and material.emission_enabled,
				"texture": material.albedo_texture if material != null else null,
				"points": points,
				"triangles": (indices.size() if indices != null and not indices.is_empty() else points.size()) / 3,
			})
	assert_gt(surfaces.size(), 0, "the detective has surfaces")
	return surfaces


func _starts_with_any(material: String, prefixes: Array) -> bool:
	for prefix: String in prefixes:
		if material.begins_with(prefix):
			return true
	return false


func _all_points(surfaces: Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	for surface in surfaces:
		points.append_array(surface.points)
	return points


func _bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box


# How many distinct positions (to within SAME_POSITION) `points` holds.
func _distinct_positions(points: PackedVector3Array) -> int:
	var seen := {}
	for p in points:
		seen[Vector3i((p / SAME_POSITION).round())] = true
	return seen.size()


func _texture_size(texture: Texture2D) -> int:
	return mini(texture.get_width(), texture.get_height()) if texture != null else 0


# The x-width of the points whose height is within [low, high).
func _width_between(points: PackedVector3Array, low: float, high: float) -> float:
	var min_x := INF
	var max_x := -INF
	for p in points:
		if p.y >= low and p.y < high:
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
	return max_x - min_x if max_x >= min_x else 0.0


# Given the instantiated detective, when its triangles are counted, then there are between 5000 and
# 20000 (the current model has far fewer).
func test_detective_has_ps2_era_triangle_count():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	var total := 0
	for surface in surfaces:
		total += surface.triangles
	assert_between(total, 5000, 20000, "the detective has 5000-20000 triangles (has %d)" % total)


# Given the detective's body and clothes meshes, when their vertices are compared with their
# distinct positions, then there are at most 1.6 vertices per distinct position: the surfaces are
# smooth-shaded, not flat (flat shading duplicates every vertex per face).
func test_detective_is_smooth_shaded():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	var vertices := 0
	var positions := 0
	for surface in surfaces:
		if surface.emissive or _starts_with_any(surface.material, NOT_BODY):
			continue
		vertices += surface.points.size()
		positions += _distinct_positions(surface.points)
	assert_gt(positions, 0, "the detective has body and clothes surfaces")
	if positions == 0:
		return
	var ratio := float(vertices) / positions
	assert_lte(ratio, 1.6, "the body and clothes have at most 1.6 vertices per position (have %.2f)" % ratio)


# Given the detective's materials, when the coat's material (name starting coat) and at least two
# other clothing materials are inspected, then each has an albedo texture at least 256 pixels on
# its shorter side.
func test_detective_clothes_are_textured():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	var coat_texture := 0
	var textured_clothes := {}
	for surface in surfaces:
		var size := _texture_size(surface.texture)
		if surface.material.begins_with("coat"):
			coat_texture = maxi(coat_texture, size)
		elif not surface.emissive and not _starts_with_any(surface.material, NOT_CLOTHES) and size >= MIN_TEXTURE:
			textured_clothes[surface.material] = true
	assert_gte(coat_texture, MIN_TEXTURE, "the coat has an albedo texture of at least %d px (has %d)" % [MIN_TEXTURE, coat_texture])
	assert_gte(textured_clothes.size(), 2,
		"at least 2 other clothing materials have %d px textures (%s)" % [MIN_TEXTURE, textured_clothes.keys()])


# Given the instantiated detective, when its proportions are measured, then it is 1.8-1.95 m tall
# with no hat, its shoulders (the widest point between 75% and 85% of its height) are 0.42-0.52 m
# wide, and its head (everything above the neck, at about 87% of its height) is 0.22-0.27 m tall.
func test_detective_has_realistic_proportions():
	var surfaces := _surfaces()
	if surfaces.is_empty():
		return
	for surface in surfaces:
		assert_false("hat" in surface.material, "the detective has no hat (material %s)" % surface.material)
	var points := _all_points(surfaces)
	var box := _bounds(points)
	var height := box.size.y
	assert_between(height, 1.8, 1.95, "the detective is 1.8-1.95 m tall (is %.3f m)" % height)

	var shoulders := _width_between(points, box.position.y + 0.75 * height, box.position.y + 0.85 * height)
	assert_between(shoulders, 0.42, 0.52, "the shoulders are 0.42-0.52 m wide (are %.3f m)" % shoulders)

	# The neck is the narrowest 1 cm slice between 80% and 92% of the height; the head is above it.
	var neck_y := 0.0
	var neck_width := INF
	var y := box.position.y + 0.8 * height
	while y < box.position.y + 0.92 * height:
		var width := _width_between(points, y, y + 0.01)
		if width > 0.0 and width < neck_width:
			neck_width = width
			neck_y = y
		y += 0.01
	assert_lt(neck_width, INF, "the detective has a neck to measure")
	var head := box.end.y - neck_y
	assert_between(head, 0.22, 0.27, "the head is 0.22-0.27 m tall (is %.3f m, neck at %.2f m)" % [head, neck_y])
