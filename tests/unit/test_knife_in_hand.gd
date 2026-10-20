extends GutTest
# Knife in his hand in combat (ticket #91): a knife model, drawn into the player character's right
# hand when combat starts and put away when it ends.
#
# Interface these tests choose:
# - The model is `res://assets/models/props/knife.glb`. Its origin is the middle of its grip, and its
#   tip is its furthest point from there. Its materials are named `knife_blade*` and `knife_handle*`.
# - In the main scene the knife is a node named `Knife` somewhere under `Player` (e.g. on a
#   BoneAttachment3D); out of combat it is hidden or absent.
# - "His right hand" is the `mixamorig:RightHand` bone (#142: the Meshy rig has no finger bones, so
#   there's no fist to measure from and no thumb side).

const KNIFE_PATH := "res://assets/models/props/knife.glb"
const SAMPLES := 12


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


# [main, controller, body (Player), skeleton, AnimationPlayer], or [] (after failing).
func _scene() -> Array:
	var main := await _main()
	if main == null:
		return []
	var controller := main.find_child("CombatController", true, false)
	var body := main.find_child("Player", true, false) as CharacterBody3D
	var character := main.find_child("Character", true, false) as Node3D
	if controller == null or body == null or character == null:
		return []
	var skeletons := character.find_children("*", "Skeleton3D", true, false)
	var players := character.find_children("*", "AnimationPlayer", true, false)
	assert_true(not skeletons.is_empty() and not players.is_empty(), "the character has a skeleton and an AnimationPlayer")
	if skeletons.is_empty() or players.is_empty():
		return []
	return [main, controller, body, skeletons[0], players[0]]


# Starts combat on the player's turn, with fixed dice.
func _start(controller: Node, body: CharacterBody3D, cultist: Node3D) -> void:
	body.controllable = false
	for attempt in 50:
		controller.rng.seed = 91 + attempt
		controller.start_combat([body, cultist])
		if controller.active == body:
			break
	assert_eq(controller.active, body, "it's the player's turn")


func _bone_at(skeleton: Skeleton3D, name: String) -> Vector3:
	var b := skeleton.find_bone(name)
	assert_gte(b, 0, "his skeleton has %s" % name)
	return (skeleton.global_transform * skeleton.get_bone_global_pose(b)).origin if b >= 0 else Vector3.INF


func _fist(skeleton: Skeleton3D) -> Vector3:
	return _bone_at(skeleton, "mixamorig:RightHand")


func _knife(body: Node) -> Node3D:
	return body.find_child("Knife", true, false) as Node3D


func _shown(knife: Node3D) -> bool:
	return knife != null and knife.is_visible_in_tree()


# Every vertex of the meshes under `node`, in global space.
func _vertices(node: Node) -> Array:
	var points := []
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mi: MeshInstance3D in meshes:
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				points.append(mi.global_transform * v)
	return points


func _tip(knife: Node3D) -> Vector3:
	var origin := knife.global_position
	var tip := origin
	for p: Vector3 in _vertices(knife):
		if p.distance_to(origin) > tip.distance_to(origin):
			tip = p
	return tip


func _brightness(c: Color) -> float:
	return (c.r + c.g + c.b) / 3.0


# Given the knife model is loaded, when it is measured, then it is 0.20-0.30 m long, has at most 500
# triangles, and has a light, metallic blade material and a dark handle material.
func test_knife_model():
	var packed: PackedScene = load(KNIFE_PATH)
	assert_not_null(packed, "%s loads" % KNIFE_PATH)
	if packed == null:
		return
	var knife := packed.instantiate() as Node3D
	add_child_autofree(knife)
	var box := AABB()
	var first := true
	var triangles := 0
	var blade: StandardMaterial3D = null
	var handle: StandardMaterial3D = null
	for mi: MeshInstance3D in knife.find_children("*", "MeshInstance3D", true, false):
		var aabb := mi.global_transform * mi.mesh.get_aabb()
		box = aabb if first else box.merge(aabb)
		first = false
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var indices = arrays[Mesh.ARRAY_INDEX]
			triangles += (indices.size() if indices != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
			var material := mi.get_active_material(s) as StandardMaterial3D
			if material == null:
				continue
			if material.resource_name.begins_with("knife_blade"):
				blade = material
			elif material.resource_name.begins_with("knife_handle"):
				handle = material
	assert_false(first, "the knife has a mesh")
	var length := maxf(box.size.x, maxf(box.size.y, box.size.z))
	assert_between(length, 0.2, 0.3, "the knife is 0.20-0.30 m long (%.3f m)" % length)
	assert_lte(triangles, 500, "the knife has at most 500 triangles (%d)" % triangles)
	assert_not_null(blade, "the knife has a knife_blade material")
	assert_not_null(handle, "the knife has a knife_handle material")
	if blade != null:
		assert_gte(blade.metallic, 0.5, "the blade is metallic (%.2f)" % blade.metallic)
		assert_gte(_brightness(blade.albedo_color), 0.5, "the blade is light (%.2f)" % _brightness(blade.albedo_color))
	if handle != null:
		assert_lte(_brightness(handle.albedo_color), 0.25, "the handle is dark (%.2f)" % _brightness(handle.albedo_color))


# Given combat has started, when he stands in combat_idle, then the knife is visible, its grip is
# within 0.1 m of his right hand, and its tip is at least 0.15 m from it.
func test_he_draws_the_knife_in_combat():
	var scene := await _scene()
	if scene.is_empty():
		return
	var main: Node3D = scene[0]
	var controller: Node = scene[1]
	var body: CharacterBody3D = scene[2]
	var skeleton: Skeleton3D = scene[3]
	var player: AnimationPlayer = scene[4]
	_start(controller, body, main.find_child("Cultist", true, false))
	await wait_physics_frames(3)
	assert_eq(player.current_animation, "combat_idle", "he stands in combat_idle")
	var knife := _knife(body)
	assert_true(_shown(knife), "a visible Knife is in his hand")
	if not _shown(knife):
		return
	var fist := _fist(skeleton)
	var grip := knife.global_position.distance_to(fist)
	assert_lte(grip, 0.1, "the knife's grip is in his right hand (%.3f m from it)" % grip)
	var tip := _tip(knife)
	var reach := tip.distance_to(fist)
	assert_gte(reach, 0.15, "the blade sticks out of his fist (tip %.3f m from it)" % reach)


# Given combat is running, when combat_idle is sampled over the whole clip, then the knife stays in
# his right hand at every sample.
func test_the_knife_stays_in_his_hand():
	var scene := await _scene()
	if scene.is_empty():
		return
	var main: Node3D = scene[0]
	var controller: Node = scene[1]
	var body: CharacterBody3D = scene[2]
	var skeleton: Skeleton3D = scene[3]
	var player: AnimationPlayer = scene[4]
	_start(controller, body, main.find_child("Cultist", true, false))
	await wait_physics_frames(3)
	var knife := _knife(body)
	assert_true(_shown(knife), "a visible Knife is in his hand")
	if not _shown(knife):
		return
	var length := player.get_animation("combat_idle").length
	for i in SAMPLES:
		player.seek(length * i / SAMPLES, true)
		await wait_process_frames(1)
		var grip := knife.global_position.distance_to(_fist(skeleton))
		assert_lte(grip, 0.1, "at %.2f s the knife is still in his hand (%.3f m from it)" % [player.current_animation_position, grip])
		if grip > 0.1:
			return


# Given no combat is running (before combat, and after victory), when he stands or walks, then no knife
# is visible.
func test_no_knife_out_of_combat():
	var scene := await _scene()
	if scene.is_empty():
		return
	var main: Node3D = scene[0]
	var controller: Node = scene[1]
	var body: CharacterBody3D = scene[2]
	var player: AnimationPlayer = scene[4]
	var cultist := main.find_child("Cultist", true, false) as Node3D
	await wait_physics_frames(3)
	assert_eq(player.current_animation, "idle", "before combat he stands in idle")
	assert_false(_shown(_knife(body)), "no knife shows before combat")
	var from := body.global_position
	body.walk_path(PackedVector3Array([from, from + Vector3(0.6, 0, 0)]))
	await wait_physics_frames(5)
	assert_eq(player.current_animation, "walk", "he walks")
	assert_false(_shown(_knife(body)), "no knife shows while he walks out of combat")
	for tick in 120:
		await get_tree().physics_frame
		if not body.is_walking_path():
			break
	_start(controller, body, cultist)
	await wait_physics_frames(3)
	assert_true(_shown(_knife(body)), "the knife shows in combat")
	controller.apply_damage(cultist, 100)
	assert_false(controller.running, "combat ended in victory")
	await wait_physics_frames(3)
	assert_eq(player.current_animation, "idle", "after victory he stands in idle")
	assert_false(_shown(_knife(body)), "the knife is put away after victory")
