extends GutTest
# Cuts on the enemy (ticket #93): when the player character's knife slash hits the cultist, a wound
# (a dark red gash) opens on the cultist's torso where the blade landed, on the side facing the
# attacker, and stays on him as he moves. Misses, and the cultist's punches, leave none.
#
# Interface these tests choose:
# - A wound is a Node3D in the group `wounds`, under the wounded combatant's node (e.g. on a
#   BoneAttachment3D); its position is where the cut is, and its meshes draw the gash.
# - "Dark red" is the wound mesh's material albedo: red at least 0.25, green and blue at most 0.15.
# - His torso runs from his waist (the cultist's `spine` bone) to his shoulders (his `head` bone, at the
#   neck). His body's surface is his skinned meshes (everything under him but the wounds), skinned on
#   the CPU.
# - The slash lands when the cultist's `hit` clip starts (#81).

const SAMPLES := 10

var _window: SubViewport


func after_each():
	_window = null


func _main() -> Node3D:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the main scene (%s) loads" % path)
	if packed == null:
		return null
	_window = SubViewport.new()
	_window.size = Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	add_child_autofree(_window)
	var main := packed.instantiate()
	_window.add_child(main)
	await wait_physics_frames(3)
	return main as Node3D


# [main, controller, body (Player), cultist], in combat on the player's turn, or [] (after failing).
func _fight() -> Array:
	var main := await _main()
	if main == null:
		return []
	var controller := main.find_child("CombatController", true, false)
	var body := main.find_child("Player", true, false) as CharacterBody3D
	var cultist := main.find_child("Cultist", true, false) as Node3D
	if controller == null or body == null or cultist == null:
		return []
	body.controllable = false
	body.global_position = cultist.global_position + Vector3(-0.9, 0, 0.9)  # within reach, facing him
	body.look_at(cultist.global_position, Vector3.UP, true)
	await wait_physics_frames(2)
	for attempt in 50:
		controller.rng.seed = 93 + attempt
		controller.start_combat([body, cultist])
		if controller.active == body:
			break
	assert_eq(controller.active, body, "it's the player's turn")
	return [main, controller, body, cultist]


func _wounds(on: Node) -> Array:
	return get_tree().get_nodes_in_group("wounds").filter(func(w: Node) -> bool: return on.is_ancestor_of(w))


func _animation_player(node: Node) -> AnimationPlayer:
	var players := node.find_children("*", "AnimationPlayer", true, false)
	return players[0] if not players.is_empty() else null


func _skeleton(node: Node) -> Skeleton3D:
	var skeletons := node.find_children("*", "Skeleton3D", true, false)
	return skeletons[0] if not skeletons.is_empty() else null


func _bone_y(skeleton: Skeleton3D, name: String) -> float:
	var b := skeleton.find_bone(name)
	assert_gte(b, 0, "the cultist has a %s bone" % name)
	return (skeleton.global_transform * skeleton.get_bone_global_pose(b)).origin.y if b >= 0 else NAN


# Attacks the cultist (keeping him alive) until a hit, then waits until the slash lands (his `hit` clip
# starts). Returns the hit's result, or {} (after failing).
func _land_a_hit(controller: Node, body: Node3D, cultist: Node3D) -> Dictionary:
	var player := _animation_player(cultist)
	for i in 40:
		controller.actions_left = 1
		var result: Dictionary = controller.attack(body, cultist)
		controller.hit_points[cultist] = 12
		if not result.hit:
			await wait_seconds(1.3)  # let the miss play out
			continue
		for tick in 120:
			await get_tree().physics_frame
			if player.current_animation == "hit":
				break
		assert_eq(player.current_animation, "hit", "the cultist flinches as the slash lands")
		await wait_physics_frames(2)
		return result
	fail_test("the player character landed no hit in 40 attacks")
	return {}


# The skinned meshes of `node` (not the wounds).
func _body_meshes(node: Node) -> Array:
	return node.find_children("*", "MeshInstance3D", true, false).filter(func(mi: MeshInstance3D) -> bool:
		for wound in get_tree().get_nodes_in_group("wounds"):
			if wound == mi or wound.is_ancestor_of(mi):
				return false
		return mi.skin != null)


# Where vertex `index` of surface `s` of `mi` is drawn now, skinned on the CPU.
func _skinned(mi: MeshInstance3D, s: int, index: int) -> Vector3:
	var arrays := mi.mesh.surface_get_arrays(s)
	var vertex: Vector3 = arrays[Mesh.ARRAY_VERTEX][index]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights = arrays[Mesh.ARRAY_WEIGHTS]
	var per_vertex: int = weights.size() / arrays[Mesh.ARRAY_VERTEX].size()
	var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	if skeleton == null:
		return mi.global_transform * vertex
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


# The nearest point of `node`'s body surface to `point`: [distance, mesh, surface, vertex index].
func _nearest_skin(node: Node, point: Vector3) -> Array:
	var best := [INF, null, -1, -1]
	for mi: MeshInstance3D in _body_meshes(node):
		for s in mi.mesh.get_surface_count():
			var count: int = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
			for i in count:
				var d := _skinned(mi, s, i).distance_to(point)
				if d < best[0]:
					best = [d, mi, s, i]
	return best


func _gash_colour_and_length(wound: Node3D) -> Array:
	var meshes := wound.find_children("*", "MeshInstance3D", true, false)
	if wound is MeshInstance3D:
		meshes.append(wound)
	var length := 0.0
	var colour := Color(0, 0, 0, 0)
	for mi: MeshInstance3D in meshes:
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		length = maxf(length, maxf(box.size.x, maxf(box.size.y, box.size.z)))
		for s in mi.mesh.get_surface_count():
			var material := mi.get_active_material(s) as BaseMaterial3D
			if material != null:
				colour = material.albedo_color
	return [colour, length]


# Given the player character hits the cultist, when the slash lands (his hit reaction starts), then a
# wound appears on him: a dark red gash at least 0.08 m long, on the side facing the attacker, within
# 0.05 m of his body's surface.
# (Changed by #112, as its ticket says: the torso check is gone, since the cut now goes at the blade's
# height; test_cuts_follow_blade.gd checks where.)
func test_a_hit_opens_a_wound():
	var fight := await _fight()
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	assert_eq(_wounds(cultist).size(), 0, "no wound before the fight")
	var result := await _land_a_hit(controller, body, cultist)
	if result.is_empty():
		return
	var wounds := _wounds(cultist)
	assert_eq(wounds.size(), 1, "one wound opens on the cultist")
	if wounds.is_empty():
		return
	var wound: Node3D = wounds[0]
	var look := _gash_colour_and_length(wound)
	var colour: Color = look[0]
	assert_true(colour.r >= 0.25 and colour.g <= 0.15 and colour.b <= 0.15, "the wound is dark red (%s)" % colour)
	assert_gte(look[1], 0.08, "the gash is at least 0.08 m long (%.3f m)" % look[1])
	var at := wound.global_position
	var out := Vector2(at.x - cultist.global_position.x, at.z - cultist.global_position.z)
	var to_attacker := Vector2(body.global_position.x - cultist.global_position.x, body.global_position.z - cultist.global_position.z)
	assert_gt(out.dot(to_attacker), 0.0, "the wound is on the side facing the attacker")
	var skin := _nearest_skin(cultist, at)
	assert_lte(skin[0], 0.05, "the wound is on his body's surface (%.3f m from it)" % skin[0])


# Given a wound is on the cultist, when he plays his hit and idle clips, then it moves with him: it stays
# within 0.05 m of the same point on his skin.
func test_the_wound_moves_with_him():
	var fight := await _fight()
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	var result := await _land_a_hit(controller, body, cultist)
	if result.is_empty():
		return
	var wounds := _wounds(cultist)
	assert_eq(wounds.size(), 1, "a wound opened")
	if wounds.is_empty():
		return
	var wound: Node3D = wounds[0]
	var skin := _nearest_skin(cultist, wound.global_position)
	if skin[1] == null:
		fail_test("the cultist has a skinned body")
		return
	var player := _animation_player(cultist)
	for clip in ["hit", "idle"]:
		var length := player.get_animation(clip).length
		for i in SAMPLES:
			player.play(clip)
			player.seek(length * i / SAMPLES, true)
			await wait_process_frames(1)
			var gap := wound.global_position.distance_to(_skinned(skin[1], skin[2], skin[3]))
			assert_lte(gap, 0.05, "in %s the wound stays on the same spot on his skin (%.3f m from it)" % [clip, gap])
			if gap > 0.05:
				return


# Given the player character hits the cultist twice, when both wounds are measured, then there are two
# at least 0.05 m apart.
func test_two_hits_two_cuts():
	var fight := await _fight()
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	for i in 2:
		var result := await _land_a_hit(controller, body, cultist)
		if result.is_empty():
			return
		await wait_seconds(0.8)  # let the hit play out
	var wounds := _wounds(cultist)
	assert_eq(wounds.size(), 2, "two hits leave two wounds")
	if wounds.size() < 2:
		return
	var apart: float = (wounds[0] as Node3D).global_position.distance_to((wounds[1] as Node3D).global_position)
	assert_gte(apart, 0.05, "the cuts aren't in the same spot (%.3f m apart)" % apart)


# Given an attack misses, or the cultist punches the player character, when the attack resolves, then
# no wound appears on anyone.
func test_misses_and_punches_leave_no_wounds():
	var fight := await _fight()
	if fight.is_empty():
		return
	var main: Node3D = fight[0]
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	cultist.set_meta("armour_class", 100)  # only a natural 20 hits
	var misses := 0
	for i in 6:
		controller.actions_left = 1
		var result: Dictionary = controller.attack(body, cultist)
		controller.hit_points[cultist] = 12
		await wait_seconds(1.3)
		if result.hit:
			return  # a natural 20: this check can't tell; the other tests cover hits
		misses += 1
		assert_eq(get_tree().get_nodes_in_group("wounds").size(), 0, "a miss leaves no wound")
	assert_gt(misses, 0, "some attacks missed")
	body.set_meta("armour_class", 0)  # the cultist's punches land
	var punched := false
	for i in 4:
		var result: Dictionary = controller.attack(cultist, body)
		controller.hit_points[body] = 20
		punched = punched or result.hit
		await wait_seconds(1.3)
	assert_true(punched, "the cultist's punches landed")
	assert_eq(_wounds(main).size(), 0, "the cultist's punches leave no wound on anyone")
