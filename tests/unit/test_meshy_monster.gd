extends GutTest
# The Meshy monster model (ticket #160): monster.glb is the owner's Meshy monster, its mesh and textures
# as Meshy delivered them, on Meshy's own rig with its bones named for what they move, and each leg's
# skin following only that leg.
#
# Interface these tests choose (positions in the monster's space, in its rest pose: +X its left, +Y up,
# +Z the way it faces, as #106 chose):
# - Its bones are BONES: Meshy's 54 (`Bone_000` ... `Bone_053`), each renamed, with Meshy's parents.
#   `root` (Meshy's Bone_000) holds `body` (Bone_001), which everything else hangs from. Its legs are
#   `leg_<N>_<k>_<S>`: N 1 front, 2 back; k 1 at its body down to its foot; S `l` or `r`. Its claw is
#   `claw_1`, `claw_2` and three fingers `claw_finger_<F>_<k>`; its head `head_1` ... `head_5`; the
#   spines on its back `spike_<N>_<k>`.
# - "Facing +Z": its front feet (the last bone of each `leg_1_*` chain) are further along +Z than its
#   back feet, and so is its head (`head_1`).
# - Its drawn mesh is every visible MeshInstance3D with a mesh; its height is the vertical extent of
#   their vertices.
# - Meshy's maps are its material's albedo, normal and roughness textures (Godot reads glTF's
#   metallic-roughness map as both the roughness and the metallic texture), told by their sizes.
# - A vertex follows the bone it's weighted to most. A leg's bones are its `leg_<N>_*_<S>` bones; its
#   line is the polyline through their heads, top to bottom.
# - The README check reads art/base/README.md's sections, each from its "## " heading to the next.

const MONSTER_PATH := "res://assets/models/characters/monster.glb"
# bone -> its parent ("" for the root). Meshy's bone each one was, in the comments.
const BONES := {
	"root": "", "body": "root",  # Bone_000, Bone_001
	"spike_1_1": "body", "spike_1_2": "spike_1_1", "spike_1_3": "spike_1_2", "spike_1_4": "spike_1_3",  # 005-002
	"spike_2_1": "body", "spike_2_2": "spike_2_1", "spike_2_3": "spike_2_2", "spike_2_4": "spike_2_3",  # 009-006
	"spike_3_1": "body", "spike_3_2": "spike_3_1", "spike_3_3": "spike_3_2",  # 012-010
	"spike_4_1": "body", "spike_4_2": "spike_4_1", "spike_4_3": "spike_4_2", "spike_4_4": "spike_4_3",  # 016-013
	"head_1": "body", "head_2": "head_1", "head_3": "head_2", "head_4": "head_3", "head_5": "head_4",  # 021-017
	"claw_1": "body", "claw_2": "claw_1",  # 023, 022
	"claw_finger_1_1": "claw_2", "claw_finger_1_2": "claw_finger_1_1", "claw_finger_1_3": "claw_finger_1_2",  # 045-043
	"claw_finger_2_1": "claw_2", "claw_finger_2_2": "claw_finger_2_1", "claw_finger_2_3": "claw_finger_2_2",
	"claw_finger_2_4": "claw_finger_2_3",  # 049-046
	"claw_finger_3_1": "claw_2", "claw_finger_3_2": "claw_finger_3_1", "claw_finger_3_3": "claw_finger_3_2",
	"claw_finger_3_4": "claw_finger_3_3",  # 053-050
	"leg_1_1_l": "body", "leg_1_2_l": "leg_1_1_l", "leg_1_3_l": "leg_1_2_l", "leg_1_4_l": "leg_1_3_l",
	"leg_1_5_l": "leg_1_4_l",  # 033-029
	"leg_1_1_r": "body", "leg_1_2_r": "leg_1_1_r", "leg_1_3_r": "leg_1_2_r", "leg_1_4_r": "leg_1_3_r",
	"leg_1_5_r": "leg_1_4_r",  # 038-034
	"leg_2_1_l": "body", "leg_2_2_l": "leg_2_1_l", "leg_2_3_l": "leg_2_2_l", "leg_2_4_l": "leg_2_3_l",
	"leg_2_5_l": "leg_2_4_l",  # 028-024
	"leg_2_1_r": "body", "leg_2_2_r": "leg_2_1_r", "leg_2_3_r": "leg_2_2_r", "leg_2_4_r": "leg_2_3_r",  # 042-039
}
const LEGS := ["leg_1_%d_l", "leg_1_%d_r", "leg_2_%d_l", "leg_2_%d_r"]
const OFF_ITS_LEG := 0.15  # how far a leg's skin may be from its line


func _monster() -> Node3D:
	var packed: PackedScene = load(MONSTER_PATH)
	assert_not_null(packed, "%s loads" % MONSTER_PATH)
	if packed == null:
		return null
	var monster := packed.instantiate() as Node3D
	add_child_autofree(monster)
	return monster


func _skeleton(monster: Node3D) -> Skeleton3D:
	var skeletons := monster.find_children("*", "Skeleton3D", true, false)
	assert_eq(skeletons.size(), 1, "it has one Skeleton3D")
	return skeletons[0] if not skeletons.is_empty() else null


func _drawn(monster: Node3D) -> Array:
	var drawn := []
	for mi: MeshInstance3D in monster.find_children("*", "MeshInstance3D", true, false):
		if mi.is_visible_in_tree() and mi.mesh != null:
			drawn.append(mi)
	return drawn


# A bone's head in the monster's space, in its rest pose.
func _rest(monster: Node3D, skeleton: Skeleton3D, bone: int) -> Vector3:
	return monster.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_rest(bone).origin


# The bones of the leg named by `pattern` (e.g. "leg_1_%d_l"), top to bottom.
func _leg(skeleton: Skeleton3D, pattern: String) -> Array:
	var bones := []
	for k in range(1, 10):
		var b := skeleton.find_bone(pattern % k)
		if b < 0:
			break
		bones.append(b)
	return bones


func _image(texture: Texture2D) -> Image:
	var image := texture.get_image()
	if image != null and image.is_compressed():
		image.decompress()
	return image


func _section(readme: String, heading: String) -> String:
	var start := readme.find("## " + heading)
	if start < 0:
		return ""
	var rest := readme.substr(start + 1)
	var next := rest.find("\n## ")
	return rest if next < 0 else rest.substr(0, next)


func _distance_to_line(p: Vector3, line: Array) -> float:
	var best := INF
	for i in line.size() - 1:
		best = minf(best, p.distance_to(Geometry3D.get_closest_point_to_segment(p, line[i], line[i + 1])))
	return best


# Given monster.glb, when it's loaded, then it's Meshy's mesh as delivered: one skinned mesh of at least
# 90,000 triangles (Meshy's has 90,349), 0.8-0.85 m tall (Meshy's 1.70 m scaled about 0.48x, agreed on #162)
# with its lowest point at y = 0, facing +Z, with
# Meshy's stray Icosphere not drawn.
func test_the_meshy_mesh_as_delivered():
	var monster := _monster()
	if monster == null:
		return
	var drawn := _drawn(monster)
	assert_eq(drawn.size(), 1, "one mesh is drawn (%s)" % [drawn.map(func(mi: Node) -> String: return mi.name)])
	for mi: MeshInstance3D in monster.find_children("*", "MeshInstance3D", true, false):
		assert_false(str(mi.name).begins_with("Icosphere") and mi.is_visible_in_tree(), "Meshy's Icosphere isn't drawn")
	if drawn.size() != 1:
		return
	var mesh: MeshInstance3D = drawn[0]
	assert_not_null(mesh.skin, "its mesh is skinned")
	var triangles := 0
	var lowest := INF
	var highest := -INF
	var to_monster := monster.global_transform.affine_inverse() * mesh.global_transform
	for s in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices = arrays[Mesh.ARRAY_INDEX]
		triangles += (indices.size() if indices != null and not indices.is_empty() else vertices.size()) / 3
		for v in vertices:
			var y := (to_monster * v).y
			lowest = minf(lowest, y)
			highest = maxf(highest, y)
	assert_gte(triangles, 90000, "Meshy's full mesh, at least 90,000 triangles (has %d)" % triangles)
	assert_between(highest - lowest, 0.8, 0.85, "it's 0.8-0.85 m tall (is %.3f m)" % (highest - lowest))
	assert_almost_eq(lowest, 0.0, 0.01, "its lowest point is at y = 0 (is %.3f)" % lowest)
	var skeleton := _skeleton(monster)
	if skeleton == null:
		return
	var front := _leg(skeleton, "leg_1_%d_l") + _leg(skeleton, "leg_1_%d_r")
	var back := _leg(skeleton, "leg_2_%d_l") + _leg(skeleton, "leg_2_%d_r")
	var head := skeleton.find_bone("head_1")
	assert_true(not front.is_empty() and not back.is_empty() and head >= 0, "it has front legs, back legs and a head")
	if front.is_empty() or back.is_empty() or head < 0:
		return
	var front_z := -INF
	for pattern in ["leg_1_%d_l", "leg_1_%d_r"]:
		var leg := _leg(skeleton, pattern)
		if not leg.is_empty():
			front_z = maxf(front_z, _rest(monster, skeleton, leg[-1]).z)
	var back_z := INF
	for pattern in ["leg_2_%d_l", "leg_2_%d_r"]:
		var leg := _leg(skeleton, pattern)
		if not leg.is_empty():
			back_z = minf(back_z, _rest(monster, skeleton, leg[-1]).z)
	assert_gt(front_z, back_z, "it faces +Z: its front feet are ahead of its back feet")
	assert_gt(_rest(monster, skeleton, head).z, back_z, "it faces +Z: its head is ahead of its back feet")


# Given its material, when it's inspected, then it uses Meshy's colour map (2048 px), normal map (2048 px)
# and metallic-roughness map (4096 px), each unchanged.
func test_meshys_maps():
	var monster := _monster()
	if monster == null:
		return
	var drawn := _drawn(monster)
	if drawn.is_empty():
		assert_true(false, "it has a mesh drawn")
		return
	var mi: MeshInstance3D = drawn[0]
	var material := mi.get_active_material(0) as StandardMaterial3D
	assert_not_null(material, "its mesh has a StandardMaterial3D")
	if material == null:
		return
	for spec in [["colour", material.albedo_texture, 2048], ["normal", material.normal_texture, 2048],
			["roughness", material.roughness_texture, 4096], ["metallic", material.metallic_texture, 4096]]:
		var texture: Texture2D = spec[1]
		assert_not_null(texture, "it has Meshy's %s map" % spec[0])
		if texture == null:
			continue
		assert_eq(texture.get_width(), spec[2], "its %s map is Meshy's %d px (is %d px)" % [spec[0], spec[2], texture.get_width()])
	assert_true(material.normal_enabled, "its normal map is used")
	if material.albedo_texture == null:
		return
	# Meshy's colour map, not a flat stand-in: its texels vary.
	var image := _image(material.albedo_texture)
	var lo := 1.0
	var hi := 0.0
	for i in 400:
		var c := image.get_pixel((i * 97) % image.get_width(), (i * 61) % image.get_height())
		lo = minf(lo, c.v)
		hi = maxf(hi, c.v)
	assert_gt(hi - lo, 0.2, "its colour map is Meshy's painted one (texels range %.2f-%.2f)" % [lo, hi])


# Given its skeleton, when its bones are listed, then it has Meshy's 54 bones with their parents, renamed
# for what they move: four legs (left legs end _l, right legs _r, front and back told apart), its claw,
# its head and its body (the bone everything else hangs from).
func test_meshys_rig_named_for_what_it_moves():
	var monster := _monster()
	if monster == null:
		return
	var skeleton := _skeleton(monster)
	if skeleton == null:
		return
	assert_eq(skeleton.get_bone_count(), BONES.size(), "it has Meshy's %d bones (has %d)" % [BONES.size(), skeleton.get_bone_count()])
	for bone: String in BONES:
		var b := skeleton.find_bone(bone)
		assert_gte(b, 0, "it has %s" % bone)
		if b < 0:
			continue
		var parent := skeleton.get_bone_parent(b)
		var parent_name := skeleton.get_bone_name(parent) if parent >= 0 else ""
		assert_eq(parent_name, BONES[bone], "%s hangs from %s" % [bone, BONES[bone] if BONES[bone] != "" else "nothing"])
	# Its left legs are on its left (+X), its right legs on its right.
	for pattern in LEGS:
		var leg := _leg(skeleton, pattern)
		if leg.is_empty():
			continue
		var x := _rest(monster, skeleton, leg[-1]).x
		if pattern.ends_with("_l"):
			assert_gt(x, 0.0, "%s's foot is on its left (x %.2f)" % [pattern % leg.size(), x])
		else:
			assert_lt(x, 0.0, "%s's foot is on its right (x %.2f)" % [pattern % leg.size(), x])


# Given its skin, when each vertex is assigned to the bone it follows most, then no vertex following a leg
# bone is more than 0.15 m from that leg's bones. (Meshy put most of the tail's skin on the front-right
# leg; that skin follows the body instead.)
func test_each_legs_skin_follows_only_that_leg():
	var monster := _monster()
	if monster == null:
		return
	var skeleton := _skeleton(monster)
	var drawn := _drawn(monster)
	if skeleton == null or drawn.is_empty():
		return
	var mi: MeshInstance3D = drawn[0]
	if mi.skin == null:
		assert_true(false, "its mesh is skinned")
		return
	var line_of := {}  # bone -> its leg's line
	for pattern in LEGS:
		var leg := _leg(skeleton, pattern)
		assert_gte(leg.size(), 2, "it has the leg %s" % pattern)
		var line := leg.map(func(b: int) -> Vector3: return _rest(monster, skeleton, b))
		for b: int in leg:
			line_of[b] = line
	var to_monster := monster.global_transform.affine_inverse() * mi.global_transform
	var counted := 0
	var worst := 0.0
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var per_vertex: int = weights.size() / vertices.size()
		for i in vertices.size():
			var best := -1
			var best_w := 0.0
			for k in per_vertex:
				if weights[i * per_vertex + k] > best_w:
					best_w = weights[i * per_vertex + k]
					var bind: int = bones[i * per_vertex + k]
					best = skeleton.find_bone(mi.skin.get_bind_name(bind)) if mi.skin.get_bind_name(bind) != StringName() else mi.skin.get_bind_bone(bind)
			if not line_of.has(best):
				continue
			counted += 1
			worst = maxf(worst, _distance_to_line(to_monster * vertices[i], line_of[best]))
	assert_gt(counted, 1000, "its legs have skin (%d vertices)" % counted)
	assert_lte(worst, OFF_ITS_LEG, "every leg's skin is within %.2f m of that leg (furthest %.3f m)" % [OFF_ITS_LEG, worst])


# Given art/base/README.md, when it's read, then its Meshy section names monster_model.glb as the monster's
# source, and the Creature Creator section no longer lists the monster.
func test_the_readme_names_its_source():
	var readme := FileAccess.get_file_as_string("res://art/base/README.md")
	assert_ne(readme, "", "art/base/README.md is there")
	var meshy := _section(readme, "Meshy")
	assert_ne(meshy, "", "art/base/README.md has a Meshy section")
	assert_true("monster_model.glb" in meshy, "the Meshy section names monster_model.glb")
	var creature := _section(readme, "Creature Creator")
	assert_false("monster" in creature.to_lower(), "the Creature Creator section (if any) no longer lists the monster")
