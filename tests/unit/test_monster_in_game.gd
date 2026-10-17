extends GutTest
# The monster takes the cultist's place (ticket #108): the main scene's `Cultist` node shows
# monster.glb and fights as the cultist did (turns, stats, reach), with the knife's cuts and blood
# landing on its body.
#
# Interface these tests choose:
# - The enemy is still the `Cultist` node (#10); its model is the scene it instances.
# - "Its widest point, seen from above, excluding its legs" is the furthest any of its skinned vertices
#   not following a `leg*` bone (most) reaches, horizontally, from its origin, in its rest pose. Its
#   TouchArea keeps #19's rule (checked in test_enemy_encounter.gd).
# - Cuts and blood are #93's `wounds` and #94's `blood_sprays` groups.

const MONSTER_PATH := "res://assets/models/characters/monster.glb"
# (The attack stats became the d6 pool's with #120, as its ticket says, with defence 2 as agreed on
# #120; initiative became a pool with #121.)
const STATS := {"initiative_pool": 3, "movement": 6.0, "attack_pool": 4, "defence": 2, "weapon_damage": 1,
	"max_hit_points": 12}
const WHERE := Vector3(0.6, 0, -1.2)  # where the cultist stood (#10)

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


func _animation_player(node: Node) -> AnimationPlayer:
	var players := node.find_children("*", "AnimationPlayer", true, false)
	return players[0] if not players.is_empty() else null


# Starts combat with `first` taking the first turn.
func _start(controller: Node, body: CharacterBody3D, monster: Node3D, first: Node3D) -> void:
	body.controllable = false
	for attempt in 80:
		controller.rng.seed = 108 + attempt
		controller.start_combat([body, monster])
		if controller.active == first:
			break
	assert_eq(controller.active, first, "%s has the first turn" % first.name)


# Given the main scene, when the Cultist node is inspected, then it shows monster.glb, keeps its stats,
# its enemies group and its TouchArea, and stands where the cultist stood.
func test_the_monster_stands_in_for_the_cultist():
	var main := await _main()
	if main == null:
		return
	var monster := main.find_child("Cultist", true, false) as Node3D
	assert_not_null(monster, "the main scene still has the Cultist node")
	if monster == null:
		return
	assert_eq(monster.scene_file_path, MONSTER_PATH, "it shows the monster model")
	for key in STATS:
		assert_eq(monster.get_meta(key, null), STATS[key], "it keeps its %s" % key)
	assert_true(monster.is_in_group("enemies"), "it's still an enemy")
	assert_not_null(monster.find_child("TouchArea", false, false), "it keeps its TouchArea")
	assert_lt(monster.position.distance_to(WHERE), 0.01, "it stands where the cultist stood")


# Given combat with the monster, when it takes its turn, then it walks towards him playing walk and
# attacks playing attack; and when he hits it, it plays hit, then settles back into idle.
func test_it_fights_with_its_own_clips():
	var main := await _main()
	if main == null:
		return
	var controller := main.find_child("CombatController", true, false)
	var body := main.find_child("Player", true, false) as CharacterBody3D
	var monster := main.find_child("Cultist", true, false) as Node3D
	var player := _animation_player(monster)
	assert_not_null(player, "the monster has an AnimationPlayer")
	if player == null:
		return
	# Its turn, with him a few metres away: it walks to him, then attacks.
	body.global_position = monster.global_position + Vector3(-2.6, 0, 1.4)
	await wait_physics_frames(2)
	_start(controller, body, monster, monster)
	var seen := {}
	for tick in 600:
		await get_tree().physics_frame
		seen[player.current_animation] = true
		if seen.has("attack") or controller.active != monster:
			break
	assert_true(seen.has("walk"), "it walks towards him playing walk (saw %s)" % [seen.keys()])
	assert_true(seen.has("attack"), "it attacks him playing attack (saw %s)" % [seen.keys()])
	# His turn: a hit makes it flinch, then it settles into idle.
	await wait_seconds(2.0)
	var landed := false
	for i in 40:
		controller.actions_left = 1
		var result: Dictionary = controller.attack(body, monster)
		controller.hit_points[monster] = 12
		if result.hit:
			landed = true
			break
	assert_true(landed, "he lands a hit")
	var flinched := false
	for tick in 120:
		await get_tree().physics_frame
		if player.current_animation == "hit":
			flinched = true
			break
	assert_true(flinched, "it plays hit when he hits it")
	for tick in 120:
		await get_tree().physics_frame
		if player.current_animation == "idle":
			break
	assert_eq(player.current_animation, "idle", "then it settles back into idle")


# Given he hits the monster, when the slash lands, then a cut opens on its body facing him, within
# 0.05 m of its skin, and blood sprays from it.
func test_cuts_and_blood_land_on_it():
	var main := await _main()
	if main == null:
		return
	var controller := main.find_child("CombatController", true, false)
	var body := main.find_child("Player", true, false) as CharacterBody3D
	var monster := main.find_child("Cultist", true, false) as Node3D
	body.global_position = monster.global_position + Vector3(-1.2, 0, 1.2)
	body.look_at(monster.global_position, Vector3.UP, true)
	await wait_physics_frames(2)
	_start(controller, body, monster, body)
	var wound: Node3D = null
	var sprayed := false
	for i in 40:
		controller.actions_left = 1
		var result: Dictionary = controller.attack(body, monster)
		controller.hit_points[monster] = 12
		if not result.hit:
			await wait_seconds(1.3)
			continue
		for tick in 120:
			await get_tree().physics_frame
			sprayed = sprayed or not get_tree().get_nodes_in_group("blood_sprays").is_empty()
			var wounds := get_tree().get_nodes_in_group("wounds").filter(func(w: Node) -> bool: return monster.is_ancestor_of(w))
			if not wounds.is_empty():
				wound = wounds[0]
				break
		break
	assert_not_null(wound, "a cut opens on the monster")
	assert_true(sprayed, "blood sprays from it")
	if wound == null:
		return
	# (The spine-to-head band check was replaced by #112, as its ticket says: the cut goes at the blade's
	# height, checked in test_cuts_follow_blade.gd.)
	var at := wound.global_position
	var out := Vector2(at.x - monster.global_position.x, at.z - monster.global_position.z)
	var to_him := Vector2(body.global_position.x - monster.global_position.x, body.global_position.z - monster.global_position.z)
	assert_gt(out.dot(to_him), 0.0, "the cut is on the side facing him")
	var nearest := INF
	for mi: MeshInstance3D in monster.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or wound.is_ancestor_of(mi):
			continue
		for s in mi.mesh.get_surface_count():
			for i in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size():
				nearest = minf(nearest, _skinned(mi, s, i).distance_to(at))
	assert_lte(nearest, 0.05, "the cut is on its skin (%.3f m from it)" % nearest)


func _skinned(mi: MeshInstance3D, s: int, index: int) -> Vector3:
	var arrays := mi.mesh.surface_get_arrays(s)
	var vertex: Vector3 = arrays[Mesh.ARRAY_VERTEX][index]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights = arrays[Mesh.ARRAY_WEIGHTS]
	var per_vertex: int = weights.size() / arrays[Mesh.ARRAY_VERTEX].size()
	var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	var result := Vector3.ZERO
	for k in per_vertex:
		var w: float = weights[index * per_vertex + k]
		if w <= 0.0:
			continue
		var bind: int = bones[index * per_vertex + k]
		var bone := skeleton.find_bone(mi.skin.get_bind_name(bind)) if mi.skin.get_bind_name(bind) != StringName() else mi.skin.get_bind_bone(bind)
		result += (skeleton.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind) * vertex) * w
	return skeleton.global_transform * result


# Given the monster's size, when its body radius is checked, then its body_radius metadata is within
# 0.05 m of its widest point, seen from above, excluding its legs.
# (Changed with the owner's go-ahead on #108, answer 1a: the TouchArea isn't checked here; it keeps
# reaching 0.2-0.5 m beyond body_radius, as test_enemy_encounter.gd (#19) requires.)
func test_its_reach_fits_its_body():
	var main := await _main()
	if main == null:
		return
	var monster := main.find_child("Cultist", true, false) as Node3D
	var skeleton := monster.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var widest := 0.0
	for mi: MeshInstance3D in monster.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null:
			continue
		var to_monster := monster.global_transform.affine_inverse() * mi.global_transform
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
				if best >= 0 and skeleton.get_bone_name(best).begins_with("leg"):
					continue
				var p := to_monster * vertices[i]
				widest = maxf(widest, Vector2(p.x, p.z).length())
	assert_gt(widest, 0.2, "the monster has a body to measure (%.3f m)" % widest)
	var radius: float = monster.get_meta("body_radius", 0.0)
	assert_almost_eq(radius, widest, 0.05, "its body_radius matches its body (%.3f m vs %.3f m)" % [radius, widest])
