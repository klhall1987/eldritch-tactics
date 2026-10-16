extends GutTest
# Changing the player character's clothes by slot (ticket #68): the game starts with him in his
# default outfit (tee, jeans, sneakers) over his base layer, and game code can put a piece on in a
# slot (replacing what was there), take it off (showing his base layer), and refuses a piece in a slot
# it doesn't fill. Worn pieces move with his skeleton.
#
# Interface these tests choose:
# - An `Outfit` node in the main scene owns the slots (`top`, `bottom`, `feet`):
#   `wear(slot, piece_path) -> bool` (false, and nothing changes, if the piece doesn't fill that
#   slot), `take_off(slot)`, `worn(slot) -> String` (the piece's glb path, or "" when empty) and
#   `worn_meshes(slot) -> Array` (the MeshInstance3Ds drawn for it).
# - A piece's slot is its `slot` metadata (#67).

const CLOTHES := "res://assets/models/clothes/%s.glb"
const TEE := "res://assets/models/clothes/tee_purple.glb"
const SWEATER := "res://assets/models/clothes/sweater_grey.glb"
const JEANS := "res://assets/models/clothes/jeans_blue.glb"
const SNEAKERS := "res://assets/models/clothes/sneakers_dark.glb"
const SAMPLES := 16


# Instantiates the main scene into the tree and lets it settle, or returns null (after failing).
func _main() -> Node3D:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the main scene (%s) loads" % path)
	if packed == null:
		return null
	var main := packed.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	return main as Node3D


# The main scene's Outfit node and the Character, or [] (after failing).
func _scene() -> Array:
	var main := await _main()
	if main == null:
		return []
	var outfit := main.find_child("Outfit", true, false)
	assert_not_null(outfit, "the main scene has an Outfit node")
	var character := main.find_child("Character", true, false) as Node3D
	assert_not_null(character, "the main scene has the Character")
	if outfit == null or character == null:
		return []
	for method in ["wear", "take_off", "worn", "worn_meshes"]:
		assert_true(outfit.has_method(method), "Outfit has %s()" % method)
		if not outfit.has_method(method):
			return []
	return [main, outfit, character]


# Whether every mesh in `meshes` is drawn as part of the character.
func _shown_on(meshes: Array, character: Node3D) -> bool:
	if meshes.is_empty():
		return false
	for mi in meshes:
		if not is_instance_valid(mi) or not (mi is MeshInstance3D) or not character.is_ancestor_of(mi) or not mi.is_visible_in_tree():
			return false
	return true


# Where vertex `index` of `mi` is drawn now, skinned on the CPU with the skeleton the mesh is bound
# to (in that skeleton's space).
func _skinned(mi: MeshInstance3D, index: int) -> Vector3:
	var arrays := mi.mesh.surface_get_arrays(0)
	var vertex: Vector3 = arrays[Mesh.ARRAY_VERTEX][index]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights = arrays[Mesh.ARRAY_WEIGHTS]
	var per_vertex: int = weights.size() / arrays[Mesh.ARRAY_VERTEX].size()
	var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	if skeleton == null or mi.skin == null:
		return mi.global_transform * vertex  # not skinned: wherever the mesh node is
	var result := Vector3.ZERO
	for k in per_vertex:
		var w: float = weights[index * per_vertex + k]
		if w <= 0.0:
			continue
		var bind: int = bones[index * per_vertex + k]
		var bone := mi.skin.get_bind_bone(bind)
		if mi.skin.get_bind_name(bind) != StringName():
			bone = skeleton.find_bone(mi.skin.get_bind_name(bind))
		result += (skeleton.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind) * vertex) * w
	return skeleton.global_transform * result


# The index of the vertex of `mi` nearest to `point` (in the character's rest pose, in mesh space).
func _nearest_vertex(mi: MeshInstance3D, point: Vector3) -> int:
	var vertices: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var best := -1
	var best_distance := INF
	for i in vertices.size():
		var d := vertices[i].distance_to(point)
		if d < best_distance:
			best_distance = d
			best = i
	return best


# Given the game starts, when the character's outfit is checked, then he wears the tee in top, the
# jeans in bottom and the sneakers in feet, and their meshes are shown on him.
func test_starts_in_his_default_outfit():
	var scene := await _scene()
	if scene.is_empty():
		return
	var outfit: Node = scene[1]
	var character: Node3D = scene[2]
	for pair in [["top", TEE], ["bottom", JEANS], ["feet", SNEAKERS]]:
		assert_eq(outfit.worn(pair[0]), pair[1], "he wears %s in %s" % [pair[1].get_file(), pair[0]])
		assert_true(_shown_on(outfit.worn_meshes(pair[0]), character), "the %s piece is shown on him" % pair[0])


# Given he wears a piece in a slot, when another piece for that slot is put on (the sweater as a
# top), then the old one is removed and the new one shown, and the other slots don't change.
func test_putting_on_a_piece_replaces_its_slot():
	var scene := await _scene()
	if scene.is_empty():
		return
	var outfit: Node = scene[1]
	var character: Node3D = scene[2]
	var tee_meshes: Array = outfit.worn_meshes("top")
	var bottom_meshes: Array = outfit.worn_meshes("bottom")
	var feet_meshes: Array = outfit.worn_meshes("feet")
	assert_true(outfit.wear("top", SWEATER), "the sweater goes on as a top")
	await wait_physics_frames(1)
	assert_eq(outfit.worn("top"), SWEATER, "he wears the sweater as his top")
	assert_true(_shown_on(outfit.worn_meshes("top"), character), "the sweater is shown on him")
	for mi in tee_meshes:
		assert_false(is_instance_valid(mi) and character.is_ancestor_of(mi), "the tee is removed")
	assert_eq(outfit.worn("bottom"), JEANS, "the jeans stay on")
	assert_eq(outfit.worn_meshes("bottom"), bottom_meshes, "the jeans' meshes are untouched")
	assert_eq(outfit.worn("feet"), SNEAKERS, "the sneakers stay on")
	assert_eq(outfit.worn_meshes("feet"), feet_meshes, "the sneakers' meshes are untouched")


# Given he wears a piece in a slot, when it's taken off, then the slot is empty and nothing is drawn
# there but his base layer.
func test_taking_off_a_piece_empties_its_slot():
	var scene := await _scene()
	if scene.is_empty():
		return
	var outfit: Node = scene[1]
	var character: Node3D = scene[2]
	var tee_meshes: Array = outfit.worn_meshes("top")
	var before := character.find_children("*", "MeshInstance3D", true, false).size()
	outfit.take_off("top")
	await wait_physics_frames(1)
	assert_eq(outfit.worn("top"), "", "the top slot is empty")
	assert_eq(outfit.worn_meshes("top"), [], "nothing is drawn for the top slot")
	for mi in tee_meshes:
		assert_false(is_instance_valid(mi) and character.is_ancestor_of(mi), "the tee is gone from him")
	var after := character.find_children("*", "MeshInstance3D", true, false).size()
	assert_eq(after, before - tee_meshes.size(), "only the tee's meshes went: his base layer and the other pieces stay")


# Given he's walking (walk playing), when a worn piece is measured over the clip, then it moves with
# his skeleton: the jeans at a knee stay within 3 cm of the body's own knee, relative to that knee's
# bone.
func test_worn_pieces_move_with_him():
	var scene := await _scene()
	if scene.is_empty():
		return
	var outfit: Node = scene[1]
	var character: Node3D = scene[2]
	var jeans: Array = outfit.worn_meshes("bottom")
	assert_gt(jeans.size(), 0, "he wears the jeans")
	var body := character.find_child("body", true, false) as MeshInstance3D
	assert_not_null(body, "the character has his body mesh")
	var skeleton := body.get_node_or_null(body.skeleton) as Skeleton3D if body != null else null
	assert_not_null(skeleton, "his body is skinned to his skeleton")
	if jeans.is_empty() or skeleton == null:
		return
	var knee_bone := skeleton.find_bone("calf_l")
	assert_gte(knee_bone, 0, "his skeleton has a left knee (calf_l)")
	if knee_bone < 0:
		return
	var knee := skeleton.get_bone_global_rest(knee_bone).origin  # the knee joint, in skeleton space
	var mesh_space := skeleton.global_transform.affine_inverse()
	var body_vertex := _nearest_vertex(body, knee)
	var jeans_mesh: MeshInstance3D = jeans[0]
	var jeans_vertex := _nearest_vertex(jeans_mesh, body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][body_vertex])
	var player := character.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.play("walk")
	var length := player.get_animation("walk").length
	var rest_gap := INF
	var travel := 0.0
	var first := Vector3.ZERO
	for i in SAMPLES + 1:
		player.seek(length * i / SAMPLES, true)
		player.advance(0.0)
		skeleton.force_update_all_bone_transforms()
		var knee_pose := skeleton.get_bone_global_pose(knee_bone)
		var body_at := knee_pose.affine_inverse() * (mesh_space * _skinned(body, body_vertex))
		var jeans_at := knee_pose.affine_inverse() * (mesh_space * _skinned(jeans_mesh, jeans_vertex))
		var gap := body_at.distance_to(jeans_at)
		if i == 0:
			rest_gap = gap
			first = mesh_space * _skinned(jeans_mesh, jeans_vertex)
		else:
			travel = maxf(travel, first.distance_to(mesh_space * _skinned(jeans_mesh, jeans_vertex)))
		assert_lte(gap, 0.03, "the jeans at his knee stay within 3 cm of his knee, relative to the knee bone (%.3f m at %.2f s)" % [gap, length * i / SAMPLES])
		if gap > 0.03:
			return
	assert_gt(travel, 0.05, "the jeans at his knee move as he walks (%.2f m)" % travel)


# Given a piece is put on in a slot it doesn't fill (such as the jeans as a top), when it's handled,
# then it's refused and his outfit doesn't change.
func test_a_piece_in_the_wrong_slot_is_refused():
	var scene := await _scene()
	if scene.is_empty():
		return
	var outfit: Node = scene[1]
	var top_meshes: Array = outfit.worn_meshes("top")
	assert_false(outfit.wear("top", JEANS), "the jeans are refused as a top")
	assert_false(outfit.wear("feet", SWEATER), "the sweater is refused as feet")
	await wait_physics_frames(1)
	assert_eq(outfit.worn("top"), TEE, "he still wears the tee")
	assert_eq(outfit.worn_meshes("top"), top_meshes, "the tee's meshes are untouched")
	assert_eq(outfit.worn("bottom"), JEANS, "the jeans stay where they were")
	assert_eq(outfit.worn("feet"), SNEAKERS, "the sneakers stay where they were")
