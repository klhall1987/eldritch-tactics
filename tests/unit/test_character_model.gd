extends GutTest
# The new player character model (ticket #65): character.glb is a realistic, normal-looking man built
# with MPFB, with short dark hair and plain underwear as his base layer (so clothes can go on over
# him), skinned to a skeleton, with looping idle and walk animations.
# Parts are told apart by material name: skin..., eye..., brow..., lash..., teeth..., hair...,
# underwear....

const CHARACTER_PATH := "res://assets/models/characters/character.glb"
const BASE_LAYER := ["skin", "eye", "brow", "lash", "teeth", "hair", "underwear"]
const SHARED_WEIGHT := 0.05  # a bone "weighs in" on a vertex above this weight
const SAMPLES := 24  # poses sampled over a clip


# Loads and instantiates the character, or returns null (after failing the test).
func _character() -> Node3D:
	var packed: PackedScene = load(CHARACTER_PATH)
	assert_not_null(packed, "the character model (%s) loads" % CHARACTER_PATH)
	if packed == null:
		return null
	var character := packed.instantiate() as Node3D
	add_child_autofree(character)
	return character


# Every surface of the character as {"material": String, "emissive": bool, "texture": Texture2D or
# null, "colour": Color, "points": PackedVector3Array (in the character's space), "triangles": int,
# "influences": Array of ints (per vertex, how many bones weigh in above SHARED_WEIGHT)}.
func _surfaces(character: Node3D) -> Array:
	var surfaces := []
	for mi: MeshInstance3D in character.find_children("*", "MeshInstance3D", true, false):
		var to_character := character.global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var points := PackedVector3Array()
			for v in arrays[Mesh.ARRAY_VERTEX]:
				points.append(to_character * v)
			var indices = arrays[Mesh.ARRAY_INDEX]
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
				"colour": material.albedo_color if material != null else Color.WHITE,
				"points": points,
				"triangles": (indices.size() if indices != null and not indices.is_empty() else points.size()) / 3,
				"influences": influences,
			})
	assert_gt(surfaces.size(), 0, "the character has surfaces")
	return surfaces


func _bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box


func _all_points(surfaces: Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	for surface in surfaces:
		points.append_array(surface.points)
	return points


func _starts_with_any(material: String, prefixes: Array) -> bool:
	for prefix: String in prefixes:
		if material.begins_with(prefix):
			return true
	return false


# The average colour of a surface: its texture's pixels (sampled) times its albedo colour.
func _colour(surface: Dictionary) -> Color:
	var colour: Color = surface.colour
	var texture: Texture2D = surface.texture
	if texture == null:
		return colour
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	var total := Color(0, 0, 0, 0)
	var samples := 0
	var step := maxi(1, image.get_width() / 32)
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			var pixel := image.get_pixel(x, y)
			if pixel.a < 0.5:
				continue  # see-through parts of hair cards don't count
			total += pixel
			samples += 1
	if samples == 0:
		return colour
	var average := total / samples
	return Color(average.r * colour.r, average.g * colour.g, average.b * colour.b)


func _skeleton(character: Node) -> Skeleton3D:
	var skeletons := character.find_children("*", "Skeleton3D", true, false)
	assert_eq(skeletons.size(), 1, "the character has one Skeleton3D")
	return skeletons[0] if not skeletons.is_empty() else null


func _player(character: Node) -> AnimationPlayer:
	var players := character.find_children("*", "AnimationPlayer", true, false)
	assert_eq(players.size(), 1, "the character has one AnimationPlayer")
	return players[0] if not players.is_empty() else null


# Where each bone is (in the character's space) at time `t` of `clip`.
func _pose_at(character: Node3D, player: AnimationPlayer, skeleton: Skeleton3D, clip: String, t: float) -> Array:
	player.play(clip)
	player.seek(t, true)
	player.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	var to_character := character.global_transform.affine_inverse() * skeleton.global_transform
	var positions := []
	for b in skeleton.get_bone_count():
		positions.append(to_character * skeleton.get_bone_global_pose(b).origin)
	return positions


# The lowest bone on his left (+x) and right (-x) in the rest pose: his feet.
func _feet(character: Node3D, skeleton: Skeleton3D) -> Array:
	var to_character := character.global_transform.affine_inverse() * skeleton.global_transform
	var left := -1
	var right := -1
	var left_y := INF
	var right_y := INF
	for b in skeleton.get_bone_count():
		var p: Vector3 = to_character * skeleton.get_bone_global_rest(b).origin
		if p.x > 0.03 and p.y < left_y:
			left = b
			left_y = p.y
		elif p.x < -0.03 and p.y < right_y:
			right = b
			right_y = p.y
	return [left, right]


# Given character.glb, when it's loaded and measured, then he's 1.75-1.90 m tall with his origin at
# his feet (lowest point at y = 0, centred within 0.1 m), and his mesh is skinned to a skeleton, with
# at least 25% of his vertices weighted to two or more bones so his joints bend smoothly.
func test_normal_height_and_smoothly_skinned():
	var character := _character()
	if character == null:
		return
	var surfaces := _surfaces(character)
	if surfaces.is_empty():
		return
	var box := _bounds(_all_points(surfaces))
	assert_between(box.size.y, 1.75, 1.9, "he's 1.75-1.90 m tall (is %.3f m)" % box.size.y)
	assert_almost_eq(box.position.y, 0.0, 0.01, "his lowest point is at y = 0 (is %.3f)" % box.position.y)
	var centre := box.get_center()
	assert_lt(Vector2(centre.x, centre.z).length(), 0.1, "he's centred on his origin")
	assert_not_null(_skeleton(character), "he has a skeleton")
	var vertices := 0
	var shared := 0
	for surface in surfaces:
		if surface.material.begins_with("skin"):
			vertices += surface.points.size()
			for count: int in surface.influences:
				if count >= 2:
					shared += 1
	assert_gt(vertices, 0, "he has a skin surface")
	if vertices > 0:
		var share := float(shared) / vertices
		assert_gte(share, 0.25, "at least 25%% of his body's vertices are shared between bones (%.1f%%)" % (share * 100.0))


# Given character.glb, when its geometry and materials are inspected, then he's realistic and
# game-ready: 5000-20000 triangles, and his skin has an albedo texture of at least 1024 px (normal
# maps are allowed).
func test_realistic_and_game_ready():
	var character := _character()
	if character == null:
		return
	var surfaces := _surfaces(character)
	var total := 0
	var skin_texture := 0
	for surface in surfaces:
		total += surface.triangles
		if surface.material.begins_with("skin") and surface.texture != null:
			skin_texture = maxi(skin_texture, mini(surface.texture.get_width(), surface.texture.get_height()))
	assert_between(total, 5000, 20000, "he has 5000-20000 triangles (has %d)" % total)
	assert_gte(skin_texture, 1024, "his skin has an albedo texture of at least 1024 px (has %d)" % skin_texture)


# Given character.glb, when its materials are inspected, then it's only his base layer: every
# material is skin, eyes, eyebrows, eyelashes, teeth, hair or underwear, the underwear covers his
# hips, nothing glows, and his hair is short and dark (all of it in the top 15% of his height,
# brightness at most 0.2).
func test_base_layer_with_short_dark_hair():
	var character := _character()
	if character == null:
		return
	var surfaces := _surfaces(character)
	if surfaces.is_empty():
		return
	var box := _bounds(_all_points(surfaces))
	var underwear := PackedVector3Array()
	var hair := 0
	for surface in surfaces:
		assert_true(_starts_with_any(surface.material, BASE_LAYER),
			"%s is part of his base layer (skin, eye, brow, lash, teeth, hair or underwear)" % surface.material)
		assert_false(surface.emissive, "%s doesn't glow" % surface.material)
		if surface.material.begins_with("underwear"):
			underwear.append_array(surface.points)
		if surface.material.begins_with("hair"):
			hair += 1
			var bottom := _bounds(surface.points).position.y
			var limit := box.end.y - 0.15 * box.size.y
			assert_gte(bottom, limit, "%s stays in the top 15%% of his height (down to %.3f m, limit %.3f m)" % [surface.material, bottom, limit])
			var brightness := _colour(surface).v
			assert_lte(brightness, 0.2, "%s is dark (brightness %.2f)" % [surface.material, brightness])
	assert_gt(hair, 0, "he has hair")
	assert_gt(underwear.size(), 0, "he wears underwear")
	if underwear.is_empty():
		return
	var shorts := _bounds(underwear)
	assert_lte(shorts.position.y, box.position.y + 0.46 * box.size.y, "the underwear reaches down to 46%% of his height")
	assert_gte(shorts.end.y, box.position.y + 0.52 * box.size.y, "the underwear reaches up to 52%% of his height")
	assert_true(shorts.position.x < -0.05 and shorts.end.x > 0.05, "the underwear covers both hips")


# Given his AnimationPlayer, when its clips are inspected and played, then idle loops and lasts 2-4 s
# with his feet staying put, and walk loops in place (his root doesn't travel) with each leg swinging
# forward and back over the cycle.
func test_idle_and_walk_animations():
	var character := _character()
	if character == null:
		return
	var player := _player(character)
	var skeleton := _skeleton(character)
	if player == null or skeleton == null:
		return
	for clip in ["idle", "walk"]:
		assert_true(player.has_animation(clip), "he has a %s animation" % clip)
		if not player.has_animation(clip):
			return
		assert_ne(player.get_animation(clip).loop_mode, Animation.LOOP_NONE, "%s loops" % clip)
	var idle := player.get_animation("idle")
	assert_between(idle.length, 2.0, 4.0, "idle lasts 2-4 s (lasts %.2f s)" % idle.length)
	var feet := _feet(character, skeleton)
	assert_true(feet[0] >= 0 and feet[1] >= 0, "his skeleton has a foot on each side")
	if feet[0] < 0 or feet[1] < 0:
		return

	# Idle: his feet stay put.
	var start := _pose_at(character, player, skeleton, "idle", 0.0)
	for i in SAMPLES:
		var pose := _pose_at(character, player, skeleton, "idle", idle.length * i / SAMPLES)
		for foot: int in feet:
			var moved: float = pose[foot].distance_to(start[foot])
			assert_lt(moved, 0.02, "his feet stay put in idle (%s moved %.3f m)" % [skeleton.get_bone_name(foot), moved])
			if moved >= 0.02:
				return

	# Walk: in place (no position track carries anything horizontally), each leg swinging.
	var walk := player.get_animation("walk")
	for t in walk.get_track_count():
		if walk.track_get_type(t) != Animation.TYPE_POSITION_3D or walk.track_get_key_count(t) == 0:
			continue
		var first: Vector3 = walk.track_get_key_value(t, 0)
		for k in walk.track_get_key_count(t):
			var p: Vector3 = walk.track_get_key_value(t, k)
			assert_lt(Vector2(p.x - first.x, p.z - first.z).length(), 0.02,
				"walk doesn't carry %s horizontally" % walk.track_get_path(t))
	var reach := {feet[0]: Vector2(INF, -INF), feet[1]: Vector2(INF, -INF)}  # min and max forward (z)
	for i in SAMPLES:
		var pose := _pose_at(character, player, skeleton, "walk", walk.length * i / SAMPLES)
		for foot: int in feet:
			var z: float = pose[foot].z
			reach[foot] = Vector2(minf(reach[foot].x, z), maxf(reach[foot].y, z))
	for foot: int in feet:
		var swing: float = reach[foot].y - reach[foot].x
		assert_gte(swing, 0.25, "%s swings forward and back over the walk (%.2f m)" % [skeleton.get_bone_name(foot), swing])
