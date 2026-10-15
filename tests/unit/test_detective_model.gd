extends GutTest
# The detective model (ticket #6): the player character, a low-poly noir detective about 1.85 m
# tall, with a glowing amulet on the chest and looping idle and walk animations, exported from
# Blender to a .glb.

const DETECTIVE_PATH := "res://assets/models/characters/detective.glb"


# Loads and instantiates the detective, or returns null (after failing the test) if it's missing.
func _detective() -> Node:
	var packed: PackedScene = load(DETECTIVE_PATH)
	assert_not_null(packed, "the detective model (%s) loads" % DETECTIVE_PATH)
	if packed == null:
		return null
	var detective := packed.instantiate()
	add_child_autofree(detective)
	return detective


func _meshes(detective: Node) -> Array[Node]:
	return detective.find_children("*", "MeshInstance3D", true, false)


# The model's rest-pose vertices of one mesh surface, in the detective's space.
func _surface_points(detective: Node3D, mesh_instance: MeshInstance3D, surface: int) -> PackedVector3Array:
	var to_detective := detective.global_transform.affine_inverse() * mesh_instance.global_transform
	var points := PackedVector3Array()
	for v in mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
		points.append(to_detective * v)
	return points


func _bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box


func _all_points(detective: Node3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	for mi: MeshInstance3D in _meshes(detective):
		for s in mi.mesh.get_surface_count():
			points.append_array(_surface_points(detective, mi, s))
	return points


func _animation_player(detective: Node) -> AnimationPlayer:
	var players := detective.find_children("*", "AnimationPlayer", true, false)
	assert_eq(players.size(), 1, "the detective has one AnimationPlayer")
	return players[0] if players.size() > 0 else null


# Given the project, when res://assets/models/characters/detective.glb is loaded and instantiated,
# then it loads without errors and its root is a Node3D.
func test_detective_loads_and_root_is_node3d():
	var detective := _detective()
	if detective == null:
		return
	assert_true(detective is Node3D, "the detective's root is a Node3D")
	assert_gt(_meshes(detective).size(), 0, "the detective has at least one mesh")


# Given the instantiated detective, when its mesh bounds are measured, then it is between 1.75 m
# and 1.95 m tall, with its lowest point at y = 0 (origin at the feet) and its horizontal centre
# within 0.1 m of the origin.
func test_detective_is_tall_with_origin_at_feet():
	var detective := _detective()
	if detective == null:
		return
	var points := _all_points(detective)
	assert_gt(points.size(), 0, "the detective has vertices to measure")
	if points.is_empty():
		return
	var box := _bounds(points)
	assert_between(box.size.y, 1.75, 1.95, "the detective is 1.75-1.95 m tall")
	assert_almost_eq(box.position.y, 0.0, 0.02, "the detective's lowest point is at y = 0")
	var centre := box.get_center()
	assert_lt(Vector2(centre.x, centre.z).length(), 0.1, "the detective is centred on the origin")


# Given the instantiated detective, when its materials are inspected, then at least one material is
# emissive (the amulet), and that emissive geometry sits on the model's front side (+Z,
# Vector3.MODEL_FRONT) and between 55% and 80% of its height (the chest).
func test_detective_has_glowing_amulet_on_its_chest():
	var detective := _detective()
	if detective == null:
		return
	var glowing := PackedVector3Array()
	for mi: MeshInstance3D in _meshes(detective):
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as BaseMaterial3D
			if mat != null and mat.emission_enabled:
				glowing.append_array(_surface_points(detective, mi, s))
	assert_gt(glowing.size(), 0, "the detective has emissive geometry (the amulet)")
	if glowing.is_empty():
		return
	var model := _bounds(_all_points(detective))
	var amulet := _bounds(glowing)
	assert_gt(amulet.get_center().z, model.get_center().z, "the amulet is on the front (+Z) side")
	assert_gte(amulet.position.y, model.position.y + 0.55 * model.size.y,
		"the amulet is no lower than 55% of the detective's height")
	assert_lte(amulet.end.y, model.position.y + 0.8 * model.size.y,
		"the amulet is no higher than 80% of the detective's height")


# Given the instantiated detective, when its AnimationPlayer is inspected, then it has an animation
# named idle whose loop mode is not LOOP_NONE.
func test_detective_has_looping_idle_animation():
	var detective := _detective()
	if detective == null:
		return
	var player := _animation_player(detective)
	if player == null:
		return
	assert_true(player.has_animation("idle"), "the detective has an idle animation")
	if not player.has_animation("idle"):
		return
	var idle := player.get_animation("idle")
	assert_gt(idle.length, 0.0, "idle has a length")
	assert_ne(idle.loop_mode, Animation.LOOP_NONE, "idle loops")


# Given the instantiated detective, when its AnimationPlayer is inspected, then it has an animation
# named walk whose loop mode is not LOOP_NONE, and the walk is in place (the model's root node
# does not move).
func test_detective_has_looping_in_place_walk_animation():
	var detective := _detective()
	if detective == null:
		return
	var player := _animation_player(detective)
	if player == null:
		return
	assert_true(player.has_animation("walk"), "the detective has a walk animation")
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
		assert_ne(String(path), ".", "walk doesn't animate the detective's root node")
		if walk.track_get_type(t) != Animation.TYPE_POSITION_3D or walk.track_get_key_count(t) == 0:
			continue
		var start: Vector3 = walk.track_get_key_value(t, 0)
		for k in walk.track_get_key_count(t):
			var p: Vector3 = walk.track_get_key_value(t, k)
			assert_lt(Vector2(p.x - start.x, p.z - start.z).length(), 0.01,
				"walk doesn't move %s horizontally" % path)
