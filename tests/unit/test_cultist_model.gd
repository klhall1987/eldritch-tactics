extends GutTest
# The cultist model (ticket #4): a low-poly robed figure about 1.7 m tall, with glowing eyes
# on its front and looping idle and walk animations, exported from Blender to a .glb.

const CULTIST_PATH := "res://assets/models/characters/cultist.glb"


# Loads and instantiates the cultist, or returns null (after failing the test) if it's missing.
func _cultist() -> Node:
	var packed: PackedScene = load(CULTIST_PATH)
	assert_not_null(packed, "the cultist model (%s) loads" % CULTIST_PATH)
	if packed == null:
		return null
	var cultist := packed.instantiate()
	add_child_autofree(cultist)
	return cultist


func _meshes(cultist: Node) -> Array[Node]:
	return cultist.find_children("*", "MeshInstance3D", true, false)


# The model's rest-pose vertices of one mesh surface, in the cultist's space.
func _surface_points(cultist: Node3D, mesh_instance: MeshInstance3D, surface: int) -> PackedVector3Array:
	var to_cultist := cultist.global_transform.affine_inverse() * mesh_instance.global_transform
	var points := PackedVector3Array()
	for v in mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
		points.append(to_cultist * v)
	return points


func _bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box


func _all_points(cultist: Node3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	for mi: MeshInstance3D in _meshes(cultist):
		for s in mi.mesh.get_surface_count():
			points.append_array(_surface_points(cultist, mi, s))
	return points


func _animation_player(cultist: Node) -> AnimationPlayer:
	var players := cultist.find_children("*", "AnimationPlayer", true, false)
	assert_eq(players.size(), 1, "the cultist has one AnimationPlayer")
	return players[0] if players.size() > 0 else null


# Given the project, when res://assets/models/characters/cultist.glb is loaded and instantiated,
# then it loads without errors and its root is a Node3D.
func test_cultist_loads_and_root_is_node3d():
	var cultist := _cultist()
	if cultist == null:
		return
	assert_true(cultist is Node3D, "the cultist's root is a Node3D")
	assert_gt(_meshes(cultist).size(), 0, "the cultist has at least one mesh")


# Given the instantiated cultist, when its mesh bounds are measured, then it is between 1.6 m and
# 1.8 m tall, with its lowest point at y = 0 (origin at the feet) and its horizontal centre within
# 0.1 m of the origin.
func test_cultist_is_human_sized_with_origin_at_feet():
	var cultist := _cultist()
	if cultist == null:
		return
	var points := _all_points(cultist)
	assert_gt(points.size(), 0, "the cultist has vertices to measure")
	if points.is_empty():
		return
	var box := _bounds(points)
	assert_between(box.size.y, 1.6, 1.8, "the cultist is 1.6-1.8 m tall")
	assert_almost_eq(box.position.y, 0.0, 0.02, "the cultist's lowest point is at y = 0")
	var centre := box.get_center()
	assert_lt(Vector2(centre.x, centre.z).length(), 0.1, "the cultist is centred on the origin")


# Given the instantiated cultist, when its materials are inspected, then at least one material is
# emissive (the eyes), and that emissive geometry sits on the model's front side (+Z,
# Vector3.MODEL_FRONT) and in the top 20% of its height.
func test_cultist_has_glowing_eyes_on_its_front_near_the_top():
	var cultist := _cultist()
	if cultist == null:
		return
	var glowing := PackedVector3Array()
	for mi: MeshInstance3D in _meshes(cultist):
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as BaseMaterial3D
			if mat != null and mat.emission_enabled:
				glowing.append_array(_surface_points(cultist, mi, s))
	assert_gt(glowing.size(), 0, "the cultist has emissive geometry (the eyes)")
	if glowing.is_empty():
		return
	var model := _bounds(_all_points(cultist))
	var eyes := _bounds(glowing)
	assert_gt(eyes.get_center().z, model.get_center().z, "the eyes are on the front (+Z) side")
	assert_gte(eyes.position.y, model.position.y + 0.8 * model.size.y,
		"the eyes are in the top 20% of the cultist's height")


# Given the instantiated cultist, when its AnimationPlayer is inspected, then it has an animation
# named idle whose loop mode is not LOOP_NONE.
func test_cultist_has_looping_idle_animation():
	var cultist := _cultist()
	if cultist == null:
		return
	var player := _animation_player(cultist)
	if player == null:
		return
	assert_true(player.has_animation("idle"), "the cultist has an idle animation")
	if not player.has_animation("idle"):
		return
	var idle := player.get_animation("idle")
	assert_gt(idle.length, 0.0, "idle has a length")
	assert_ne(idle.loop_mode, Animation.LOOP_NONE, "idle loops")


# Given the instantiated cultist, when its AnimationPlayer is inspected, then it has an animation
# named walk whose loop mode is not LOOP_NONE, and the walk is in place (the model's root node
# does not move).
func test_cultist_has_looping_in_place_walk_animation():
	var cultist := _cultist()
	if cultist == null:
		return
	var player := _animation_player(cultist)
	if player == null:
		return
	assert_true(player.has_animation("walk"), "the cultist has a walk animation")
	if not player.has_animation("walk"):
		return
	var walk := player.get_animation("walk")
	assert_gt(walk.length, 0.0, "walk has a length")
	assert_gt(walk.get_track_count(), 0, "walk animates something")
	assert_ne(walk.loop_mode, Animation.LOOP_NONE, "walk loops")

	# In place: walking must not carry the root anywhere. Nothing animates the root node itself,
	# and no position track travels horizontally over the clip (a vertical bob is fine).
	for t in walk.get_track_count():
		var path := walk.track_get_path(t)
		assert_ne(String(path), ".", "walk doesn't animate the cultist's root node")
		if walk.track_get_type(t) != Animation.TYPE_POSITION_3D or walk.track_get_key_count(t) == 0:
			continue
		var start: Vector3 = walk.track_get_key_value(t, 0)
		for k in walk.track_get_key_count(t):
			var p: Vector3 = walk.track_get_key_value(t, k)
			assert_lt(Vector2(p.x - start.x, p.z - start.z).length(), 0.01,
				"walk doesn't move %s horizontally" % path)
