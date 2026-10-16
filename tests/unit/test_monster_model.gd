extends GutTest
# A small Lovecraftian monster model (ticket #106): monster.glb, built with the Creature Creator, is a
# small creature with a thick body on skinny legs and a pair of mandibles, rigged for animation.
#
# Interface these tests choose (positions in the model's space, in its rest pose: +X its left, +Y up,
# +Z the way it faces):
# - Its legs are bone chains whose names start with `leg`: a leg starts at a `leg*` bone whose parent
#   isn't one, and runs down its `leg*` children. Left legs' names end `_l`, right legs' `_r`. A leg's
#   line is the polyline through its bones' heads, top to bottom (so a leg ends in a bone at its foot).
# - A vertex belongs to the bone it's weighted to most. Its body's skin is the vertices belonging to
#   `spine`, measured from that bone's head; a leg's skin is the vertices belonging to its bones,
#   measured from the leg's line; a mandible's skin is the vertices belonging to `mandible_l`/`_r`.
# - "Dark": a material's albedo colour (times its texture's average colour, if it has one) has a
#   brightness (mean of red, green and blue) of at most 0.35. "Glows": emission is enabled, with an
#   emission colour of brightness at least 0.3.

const MONSTER_PATH := "res://assets/models/characters/monster.glb"


func _monster() -> Node3D:
	var packed: PackedScene = load(MONSTER_PATH)
	assert_not_null(packed, "%s loads" % MONSTER_PATH)
	if packed == null:
		return null
	var monster := packed.instantiate() as Node3D
	add_child_autofree(monster)
	return monster


func _skeleton(monster: Node) -> Skeleton3D:
	var skeletons := monster.find_children("*", "Skeleton3D", true, false)
	assert_eq(skeletons.size(), 1, "the monster has one skeleton")
	return skeletons[0] if not skeletons.is_empty() else null


func _meshes(monster: Node) -> Array:
	return monster.find_children("*", "MeshInstance3D", true, false)


# Every skinned vertex: [[position in the monster's space, bone it follows most], ...].
func _vertices(monster: Node3D, skeleton: Skeleton3D) -> Array:
	var out := []
	for mi: MeshInstance3D in _meshes(monster):
		if mi.skin == null:
			continue
		var to_monster := monster.global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null:
				continue
			var per_vertex: int = weights.size() / vertices.size()
			for i in vertices.size():
				var best := -1
				var best_w := 0.0
				for k in per_vertex:
					var w: float = weights[i * per_vertex + k]
					if w > best_w:
						best_w = w
						var bind: int = bones[i * per_vertex + k]
						best = skeleton.find_bone(mi.skin.get_bind_name(bind)) if mi.skin.get_bind_name(bind) != StringName() else mi.skin.get_bind_bone(bind)
				out.append([to_monster * vertices[i], best])
	return out


func _rest(monster: Node3D, skeleton: Skeleton3D, bone: int) -> Vector3:
	return (monster.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_rest(bone)).origin


# Each leg: an Array of bone indices, top to bottom.
func _legs(skeleton: Skeleton3D) -> Array:
	var legs := []
	for b in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(b)
		if not skeleton.get_bone_name(b).begins_with("leg") or (parent >= 0 and skeleton.get_bone_name(parent).begins_with("leg")):
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
		legs.append(chain)
	return legs


func _from_polyline(p: Vector3, points: Array) -> float:
	var best := INF
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var along := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 1e-8), 0.0, 1.0)
		best = minf(best, p.distance_to(a + (b - a) * along))
	return best


# Given monster.glb is loaded, when it is measured, then it stands 0.8-1.3 m tall with its lowest point
# on the floor (within 0.01 m), is centred on its origin (within 0.1 m), and has 3,000-25,000 triangles.
func test_small_and_game_ready():
	var monster := _monster()
	if monster == null:
		return
	var box := AABB()
	var first := true
	var triangles := 0
	for mi: MeshInstance3D in _meshes(monster):
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var indices = arrays[Mesh.ARRAY_INDEX]
			triangles += (indices.size() if indices != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	assert_false(first, "the monster has meshes")
	assert_between(box.size.y, 0.8, 1.3, "it stands 0.8-1.3 m tall (%.3f m)" % box.size.y)
	assert_almost_eq(box.position.y, 0.0, 0.01, "its lowest point is on the floor (%.3f m)" % box.position.y)
	var centre := box.get_center()
	assert_lte(Vector2(centre.x, centre.z).length(), 0.1, "it's centred on its origin")
	assert_between(triangles, 3000, 25000, "it has 3,000-25,000 triangles (%d)" % triangles)


# Given its skeleton, when its bones are listed, then it has at least four legs (chains of at least two
# bones, as many on the left as the right), a spine bone, a head bone above it, and mandible_l and
# mandible_r; and every vertex is skinned to at least one bone.
func test_rigged_with_legs_spine_head_and_mandibles():
	var monster := _monster()
	if monster == null:
		return
	var skeleton := _skeleton(monster)
	if skeleton == null:
		return
	var legs := _legs(skeleton)
	var left := legs.filter(func(chain: Array) -> bool: return skeleton.get_bone_name(chain[0]).ends_with("_l"))
	var right := legs.filter(func(chain: Array) -> bool: return skeleton.get_bone_name(chain[0]).ends_with("_r"))
	assert_gte(legs.size(), 4, "it has at least four legs (%d)" % legs.size())
	assert_eq(left.size(), right.size(), "as many legs on the left as the right (%d, %d)" % [left.size(), right.size()])
	for chain: Array in legs:
		assert_gte(chain.size(), 2, "leg %s has at least two bones" % skeleton.get_bone_name(chain[0]))
	for name in ["spine", "head", "mandible_l", "mandible_r"]:
		assert_gte(skeleton.find_bone(name), 0, "it has a %s bone" % name)
	if skeleton.find_bone("spine") >= 0 and skeleton.find_bone("head") >= 0:
		assert_gt(_rest(monster, skeleton, skeleton.find_bone("head")).y, _rest(monster, skeleton, skeleton.find_bone("spine")).y, "its head bone is above its spine bone")
	var unskinned := 0
	var total := 0
	for mi: MeshInstance3D in _meshes(monster):
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var count: int = arrays[Mesh.ARRAY_VERTEX].size()
			total += count
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if mi.skin == null or weights == null:
				unskinned += count
				continue
			var per_vertex: int = weights.size() / count
			for i in count:
				var sum := 0.0
				for k in per_vertex:
					sum += weights[i * per_vertex + k]
				if sum <= 0.0:
					unskinned += 1
	assert_gt(total, 0, "it has vertices")
	assert_eq(unskinned, 0, "every vertex is skinned to a bone (%d of %d aren't)" % [unskinned, total])


# Given its skin, when the body and legs are measured, then its body's skin is on average at least 0.15 m
# from the spine bone, and each leg's skin is on average at most a quarter of that from the leg's line.
func test_thick_body_skinny_legs():
	var monster := _monster()
	if monster == null:
		return
	var skeleton := _skeleton(monster)
	if skeleton == null or skeleton.find_bone("spine") < 0:
		fail_test("it has a skeleton with a spine bone")
		return
	var vertices := _vertices(monster, skeleton)
	var spine := skeleton.find_bone("spine")
	var spine_at := _rest(monster, skeleton, spine)
	var body := 0.0
	var body_count := 0
	for v: Array in vertices:
		if v[1] == spine:
			body += (v[0] as Vector3).distance_to(spine_at)
			body_count += 1
	assert_gt(body_count, 0, "its body has skin on the spine bone")
	if body_count == 0:
		return
	body /= body_count
	assert_gte(body, 0.15, "its body is thick (%.3f m from the spine on average)" % body)
	var legs := _legs(skeleton)
	assert_gte(legs.size(), 4, "it has legs to measure")
	for chain: Array in legs:
		var line := chain.map(func(b: int) -> Vector3: return _rest(monster, skeleton, b))
		var leg := 0.0
		var count := 0
		for v: Array in vertices:
			if chain.has(v[1]):
				leg += _from_polyline(v[0], line)
				count += 1
		assert_gt(count, 0, "leg %s has skin" % skeleton.get_bone_name(chain[0]))
		if count == 0:
			continue
		leg /= count
		assert_lte(leg, body / 4.0, "leg %s is skinny (%.3f m from its bones, body %.3f m)" % [skeleton.get_bone_name(chain[0]), leg, body])


# Given its head, when the mandibles are measured, then each mandible's skin reaches at least 0.08 m in
# front of the head bone, the left one on its left and the right one on its right.
func test_mandibles_at_the_front():
	var monster := _monster()
	if monster == null:
		return
	var skeleton := _skeleton(monster)
	if skeleton == null or skeleton.find_bone("head") < 0:
		fail_test("it has a skeleton with a head bone")
		return
	var head_z := _rest(monster, skeleton, skeleton.find_bone("head")).z
	var vertices := _vertices(monster, skeleton)
	for side in [["mandible_l", 1.0], ["mandible_r", -1.0]]:
		var bone := skeleton.find_bone(side[0])
		assert_gte(bone, 0, "it has %s" % side[0])
		if bone < 0:
			continue
		var reach := -INF
		var x := 0.0
		var count := 0
		for v: Array in vertices:
			if v[1] == bone:
				reach = maxf(reach, (v[0] as Vector3).z - head_z)
				x += (v[0] as Vector3).x
				count += 1
		assert_gt(count, 0, "%s has skin" % side[0])
		if count == 0:
			continue
		assert_gte(reach, 0.08, "%s reaches out in front of its head (%.3f m)" % [side[0], reach])
		assert_gt(x / count * side[1], 0.0, "%s is on its %s" % [side[0], "left" if side[1] > 0 else "right"])


func _texture_average(texture: Texture2D) -> Color:
	if texture == null:
		return Color.WHITE
	var image := texture.get_image()
	if image == null:
		return Color.WHITE
	if image.is_compressed():
		image.decompress()
	image.resize(16, 16)
	var total := Color(0, 0, 0, 0)
	for y in 16:
		for x in 16:
			total += image.get_pixel(x, y)
	return total / 256.0


func _brightness(c: Color) -> float:
	return (c.r + c.g + c.b) / 3.0


# Given its materials, when they are inspected, then its skin is dark (brightness at most 0.35), and its
# eyes glow (an emissive material).
func test_dark_skin_and_glowing_eyes():
	var monster := _monster()
	if monster == null:
		return
	var glows := false
	var materials := 0
	for mi: MeshInstance3D in _meshes(monster):
		for s in mi.mesh.get_surface_count():
			var material := mi.get_active_material(s) as StandardMaterial3D
			if material == null:
				continue
			materials += 1
			if material.emission_enabled:
				if _brightness(material.emission) >= 0.3 and material.emission_energy_multiplier > 0.0:
					glows = true
				continue
			var colour := material.albedo_color * _texture_average(material.albedo_texture)
			assert_lte(_brightness(colour), 0.35, "%s is dark (brightness %.2f)" % [material.resource_name, _brightness(colour)])
	assert_gt(materials, 0, "it has materials")
	assert_true(glows, "it has glowing (emissive) eyes")
