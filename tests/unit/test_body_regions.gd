extends GutTest
# His body is split into hideable regions (ticket #151): character.glb's Meshy body is nine region
# meshes (head, torso, hips, upper arms, forearms, hands, thighs, calves, feet), each shown or hidden on
# its own, which together draw exactly his Meshy body as before.
#
# Interface these tests choose:
# - A region is the MeshInstance3D named `body_<region>` under the character, skinned to his skeleton
#   (its `skin` set, its `skeleton` path leading to his Skeleton3D).
# - Meshy's body (since #158 the dressed character's) has MESHY_TRIANGLES triangles, its colour texture is
#   MESHY_TEXTURE, and its vertices
#   span MESHY_LOW to MESHY_HIGH in the character's space: "its vertices where they were" means the
#   regions' vertices together span the same box (within 2 mm).
# - A vertex is "weighted mostly to" the bone with its largest weight, named by its bind.

const CHARACTER_PATH := "res://assets/models/characters/character.glb"
const MESHY_TRIANGLES := 312054
const MESHY_TEXTURE := "res://assets/models/characters/character_Material_0_baseColor.png"
const MESHY_LOW := Vector3(-0.4758, 0.0, -0.161)
const MESHY_HIGH := Vector3(0.4758, 1.75, 0.161)
# region -> the bones its vertices mostly follow
const REGIONS := {
	"head": ["neck", "Head", "head_end", "headfront"],
	"torso": ["Spine02", "Spine01", "Spine", "LeftShoulder", "RightShoulder"],
	"hips": ["Hips"],
	"upper_arms": ["LeftArm", "RightArm"],
	"forearms": ["LeftForeArm", "RightForeArm"],
	"hands": ["LeftHand", "RightHand"],
	"thighs": ["LeftUpLeg", "RightUpLeg"],
	"calves": ["LeftLeg", "RightLeg"],
	"feet": ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"],
}


# Loads and instantiates the character, or returns null (after failing the test).
func _character() -> Node3D:
	var packed: PackedScene = load(CHARACTER_PATH)
	assert_not_null(packed, "the character model (%s) loads" % CHARACTER_PATH)
	if packed == null:
		return null
	var character := packed.instantiate() as Node3D
	add_child_autofree(character)
	return character


# region -> its MeshInstance3D (only those found).
func _regions(character: Node3D) -> Dictionary:
	var found := {}
	for region: String in REGIONS:
		var mi := character.find_child("body_" + region, true, false) as MeshInstance3D
		if mi != null:
			found[region] = mi
	return found


func _triangles(mi: MeshInstance3D) -> int:
	var total := 0
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var indices = arrays[Mesh.ARRAY_INDEX]
		total += (indices.size() if indices != null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return total


# Given character.glb, when its meshes are listed, then his body is nine region meshes, body_head,
# body_torso, body_hips, body_upper_arms, body_forearms, body_hands, body_thighs, body_calves and
# body_feet, all skinned to his skeleton, and no other mesh is drawn.
func test_his_body_is_nine_regions():
	var character := _character()
	if character == null:
		return
	var skeletons := character.find_children("*", "Skeleton3D", true, false)
	assert_eq(skeletons.size(), 1, "he has one Skeleton3D")
	if skeletons.is_empty():
		return
	var regions := _regions(character)
	for region: String in REGIONS:
		assert_true(regions.has(region), "his body has the body_%s region" % region)
		if not regions.has(region):
			continue
		var mi: MeshInstance3D = regions[region]
		assert_not_null(mi.skin, "body_%s is skinned" % region)
		assert_eq(mi.get_node_or_null(mi.skeleton), skeletons[0], "body_%s is skinned to his skeleton" % region)
	for mi: MeshInstance3D in character.find_children("*", "MeshInstance3D", true, false):
		if mi.is_visible_in_tree():
			assert_true(str(mi.name).begins_with("body_") and str(mi.name).trim_prefix("body_") in REGIONS,
				"only his body's regions are drawn (found %s)" % mi.name)


# Given those regions, when their triangles are counted and compared, then together they have exactly
# the triangles of Meshy's body (the same total, at least 200,000), with every triangle in exactly one
# region, its vertices where they were, and the same colour texture.
func test_the_regions_are_exactly_his_meshy_body():
	var character := _character()
	if character == null:
		return
	var regions := _regions(character)
	assert_eq(regions.size(), REGIONS.size(), "all nine regions are there")
	if regions.is_empty():
		return
	var total := 0
	var low := Vector3.INF
	var high := -Vector3.INF
	for region: String in regions:
		var mi: MeshInstance3D = regions[region]
		var count := _triangles(mi)
		assert_gt(count, 0, "body_%s has triangles" % region)
		total += count
		var material := mi.get_active_material(0) as BaseMaterial3D
		var texture := material.albedo_texture if material != null else null
		assert_eq(texture.resource_path if texture != null else "", MESHY_TEXTURE, "body_%s keeps Meshy's colour texture" % region)
		var to_character := character.global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p := to_character * v
				low = low.min(p)
				high = high.max(p)
	assert_eq(total, MESHY_TRIANGLES, "together the regions have exactly Meshy's %d triangles (have %d)" % [MESHY_TRIANGLES, total])
	assert_gte(total, 200000, "his full-detail body (%d triangles)" % total)
	assert_lte(low.distance_to(MESHY_LOW), 0.002, "his vertices are where they were (low corner %s)" % low)
	assert_lte(high.distance_to(MESHY_HIGH), 0.002, "his vertices are where they were (high corner %s)" % high)


# Given each region, when its vertices are inspected, then most of them (at least 80%) are weighted
# mostly to that region's bones.
func test_each_region_follows_its_bones():
	var character := _character()
	if character == null:
		return
	var regions := _regions(character)
	assert_eq(regions.size(), REGIONS.size(), "all nine regions are there")
	for region: String in regions:
		var mi: MeshInstance3D = regions[region]
		if mi.skin == null:
			continue
		var on := 0
		var count := 0
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if weights == null or vertices.is_empty():
				continue
			var per_vertex: int = weights.size() / vertices.size()
			for i in vertices.size():
				var best := -1
				var best_w := 0.0
				for k in per_vertex:
					if weights[i * per_vertex + k] > best_w:
						best_w = weights[i * per_vertex + k]
						best = bones[i * per_vertex + k]
				count += 1
				if best >= 0 and str(mi.skin.get_bind_name(best)) in REGIONS[region]:
					on += 1
		var share := float(on) / maxi(1, count)
		assert_gte(share, 0.8, "body_%s's vertices mostly follow its bones (%.1f%%)" % [region, share * 100.0])
