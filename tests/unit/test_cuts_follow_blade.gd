extends GutTest
# Cuts follow the blade (ticket #112): when the player character's knife slash hits the enemy, the cut
# opens where the blade's path meets its body, along the line of the slash, as long as the part of the
# slash that crosses the body. A second cut in the same place goes just beside the first.
#
# Interface these tests choose:
# - The knife is the `Knife` node under `Player` (#91); its tip is its furthest vertex from its origin.
#   The tests record the tip every physics frame while he attacks.
# - The blow lands when the cut appears (#93's `wounds` group, under the enemy). The tip's height "when
#   the blow landed" is its height at that frame; the way it "was moving" is from where it was 0.1 s
#   earlier to there (the backhand ends at the blow, so it has almost stopped by then).
# - "Seen from the attacker, on the plane facing him": positions are reduced to (across, up), where
#   across runs horizontally at right angles to the line from the enemy to him.
# - The enemy's body is its skinned vertices not following a `leg*` bone (#106), as posed when the cut
#   opens; its skin is all its skinned vertices.
# - A cut's long axis is its node's +X; its length is how far its meshes reach along that axis.
# - The slash's path is the tip's positions from halfway through `attack` (the backhand, #92) to the
#   blow; "its path across the enemy's width" is the part of it (seen from the attacker) whose across
#   lies within the body's.

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


# [main, controller, body (Player), enemy], in combat on his turn, him 1.2 m from it, or [].
func _fight() -> Array:
	var main := await _main()
	if main == null:
		return []
	var controller := main.find_child("CombatController", true, false)
	var body := main.find_child("Player", true, false) as CharacterBody3D
	var enemy := main.find_child("Cultist", true, false) as Node3D
	body.controllable = false
	body.global_position = enemy.global_position + Vector3(-0.85, 0, 0.85)
	body.look_at(enemy.global_position, Vector3.UP, true)
	await wait_physics_frames(2)
	for attempt in 50:
		controller.rng.seed = 112 + attempt
		controller.start_combat([body, enemy])
		if controller.active == body:
			break
	assert_eq(controller.active, body, "it's his turn")
	return [main, controller, body, enemy]


func _wounds(enemy: Node) -> Array:
	return get_tree().get_nodes_in_group("wounds").filter(func(w: Node) -> bool: return enemy.is_ancestor_of(w))


func _tip(knife: Node3D) -> Vector3:
	var origin := knife.global_position
	var tip := origin
	for mi: MeshInstance3D in knife.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p := mi.global_transform * v
				if p.distance_to(origin) > tip.distance_to(origin):
					tip = p
	return tip


# He attacks with a normal hit (peeking at the next dice pool), recording the knife's tip each physics
# frame until the cut opens. Returns {"wound", "path" [[clip time, tip]...], "attack_length"} or {}.
func _slash(controller: Node, body: CharacterBody3D, enemy: Node3D) -> Dictionary:
	for i in 1000:
		var state: int = controller.rng.state
		var dice: Array = controller.roll_pool(5)  # (a d20 until #120)
		if controller.count_successes(dice) >= 2 and dice.count(6) < 2:  # a hit against its defence 2 (agreed on #120), not a critical
			controller.rng.state = state
			break
	var knife := body.find_child("Knife", true, false) as Node3D
	var player := body.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	assert_not_null(knife, "he holds his knife")
	if knife == null:
		return {}
	var before := _wounds(enemy).size()
	controller.actions_left = 1
	var result: Dictionary = controller.attack(body, enemy)
	controller.hit_points[enemy] = 12
	assert_true(result.hit, "the slash hits")
	var path := []
	for tick in 200:
		await get_tree().physics_frame
		if player.current_animation == "attack":
			path.append([player.current_animation_position, _tip(knife)])
		var wounds := _wounds(enemy)
		if wounds.size() > before:
			return {"wound": wounds[-1], "path": path, "attack_length": player.get_animation("attack").length}
	fail_test("no cut opened")
	return {}


func _flat(p: Vector3, across: Vector3) -> Vector2:
	return Vector2(p.dot(across), p.y)


func _across(body: Node3D, enemy: Node3D) -> Vector3:
	var to_him := body.global_position - enemy.global_position
	to_him.y = 0.0
	return to_him.normalized().cross(Vector3.UP).normalized()


# Every skinned vertex of `enemy` as posed now: [[position, follows a leg bone], ...].
func _skin(enemy: Node3D) -> Array:
	var out := []
	for mi: MeshInstance3D in enemy.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null:
			continue
		var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			var per_vertex: int = weights.size() / vertices.size()
			for i in vertices.size():
				var at := Vector3.ZERO
				var main_bone := -1
				var main_w := 0.0
				for k in per_vertex:
					var w: float = weights[i * per_vertex + k]
					if w <= 0.0:
						continue
					var bind: int = bones[i * per_vertex + k]
					var bone := skeleton.find_bone(mi.skin.get_bind_name(bind)) if mi.skin.get_bind_name(bind) != StringName() else mi.skin.get_bind_bone(bind)
					at += (skeleton.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind) * vertices[i]) * w
					if w > main_w:
						main_w = w
						main_bone = bone
				out.append([skeleton.global_transform * at, main_bone >= 0 and skeleton.get_bone_name(main_bone).begins_with("leg")])
	return out


# The cut's length along its own +X, in metres.
func _cut_length(wound: Node3D) -> float:
	var axis := wound.global_basis.x.normalized()
	var lo := INF
	var hi := -INF
	for mi: MeshInstance3D in wound.find_children("*", "MeshInstance3D", true, false):
		var box := mi.mesh.get_aabb()
		for corner in 8:
			var p := mi.global_transform * box.get_endpoint(corner)
			lo = minf(lo, p.dot(axis))
			hi = maxf(hi, p.dot(axis))
	return hi - lo


# The tip's position `seconds` before the last recorded one.
func _tip_before(path: Array, seconds: float) -> Vector3:
	var last: float = path[-1][0]
	for i in range(path.size() - 1, -1, -1):
		if last - float(path[i][0]) >= seconds:
			return path[i][1]
	return path[0][1]


# Given a slash hits the enemy, when the cut opens, then its centre is on the enemy's skin (within
# 0.05 m) on the side facing him, at the tip's height when the blow landed (within 0.08 m), or the
# nearest height its body has if the tip passed above or below it.
func test_the_cut_opens_at_the_blades_height():
	var fight := await _fight()
	if fight.is_empty():
		return
	var body: CharacterBody3D = fight[2]
	var enemy: Node3D = fight[3]
	var slash := await _slash(fight[1], body, enemy)
	if slash.is_empty():
		return
	var wound: Node3D = slash.wound
	var tip: Vector3 = slash.path[-1][1]
	var skin := _skin(enemy)
	var low := INF
	var high := -INF
	var nearest := INF
	for v: Array in skin:
		nearest = minf(nearest, (v[0] as Vector3).distance_to(wound.global_position))
		if not v[1]:
			low = minf(low, (v[0] as Vector3).y)
			high = maxf(high, (v[0] as Vector3).y)
	var expected := clampf(tip.y, low, high)
	assert_almost_eq(wound.global_position.y, expected, 0.08, "the cut is at the blade's height (%.3f m; the tip was at %.3f m, its body %.3f-%.3f m)" % [wound.global_position.y, tip.y, low, high])
	assert_lte(nearest, 0.05, "the cut is on its skin (%.3f m from it)" % nearest)
	var out := Vector2(wound.global_position.x - enemy.global_position.x, wound.global_position.z - enemy.global_position.z)
	var to_him := Vector2(body.global_position.x - enemy.global_position.x, body.global_position.z - enemy.global_position.z)
	assert_gt(out.dot(to_him), 0.0, "the cut is on the side facing him")


# Given a slash hits the enemy, when the cut opens, then its long axis runs within 25 degrees of the
# way the tip was moving when the blow landed, seen from the attacker.
func test_the_cut_runs_along_the_slash():
	var fight := await _fight()
	if fight.is_empty():
		return
	var body: CharacterBody3D = fight[2]
	var enemy: Node3D = fight[3]
	var slash := await _slash(fight[1], body, enemy)
	if slash.is_empty():
		return
	var across := _across(body, enemy)
	var moving := _flat(slash.path[-1][1], across) - _flat(_tip_before(slash.path, 0.1), across)
	var axis := _flat((slash.wound as Node3D).global_basis.x, across)
	assert_gt(moving.length(), 0.01, "the tip was moving before the blow (%.3f m in 0.1 s)" % moving.length())
	var angle := rad_to_deg(absf(axis.angle_to(moving)))
	angle = minf(angle, 180.0 - angle)
	assert_lte(angle, 25.0, "the cut runs along the slash (%.0f degrees off)" % angle)


# Given a slash hits the enemy, when the cut opens, then it's as long as the tip's path across the
# enemy's width, seen from the attacker (within 25%), and at least 0.08 m.
func test_the_cut_is_as_long_as_the_slash_across_it():
	var fight := await _fight()
	if fight.is_empty():
		return
	var body: CharacterBody3D = fight[2]
	var enemy: Node3D = fight[3]
	var slash := await _slash(fight[1], body, enemy)
	if slash.is_empty():
		return
	var across := _across(body, enemy)
	var left := INF
	var right := -INF
	for v: Array in _skin(enemy):
		if not v[1]:
			left = minf(left, (v[0] as Vector3).dot(across))
			right = maxf(right, (v[0] as Vector3).dot(across))
	var swept := 0.0
	var backhand := (slash.path as Array).filter(func(p: Array) -> bool: return float(p[0]) >= float(slash.attack_length) / 2.0)
	for i in backhand.size() - 1:
		var a := _flat(backhand[i][1], across)
		var b := _flat(backhand[i + 1][1], across)
		if absf(b.x - a.x) < 1e-6:
			continue
		# The part of this step whose `across` lies within the body's.
		var t0 := clampf((left - a.x) / (b.x - a.x), 0.0, 1.0)
		var t1 := clampf((right - a.x) / (b.x - a.x), 0.0, 1.0)
		swept += a.distance_to(b) * absf(t1 - t0)
	var expected := maxf(swept, 0.08)
	var length := _cut_length(slash.wound)
	assert_gte(length, 0.08, "the cut is at least 0.08 m long (%.3f m)" % length)
	assert_almost_eq(length, expected, expected * 0.25, "the cut is as long as the slash across its body (%.3f m vs %.3f m)" % [length, expected])


# Given two slashes land in the same place, when the second cut opens, then it sits beside the first: at
# least 0.05 m away (and no more than 0.15 m), along or just below the same line.
func test_a_second_cut_goes_beside_the_first():
	var fight := await _fight()
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var enemy: Node3D = fight[3]
	var first := await _slash(controller, body, enemy)
	if first.is_empty():
		return
	var first_at := (first.wound as Node3D).global_position
	await wait_seconds(1.5)
	var second := await _slash(controller, body, enemy)
	if second.is_empty():
		return
	var second_at := (second.wound as Node3D).global_position
	var apart := first_at.distance_to(second_at)
	assert_between(apart, 0.05, 0.15, "the second cut is beside the first (%.3f m apart)" % apart)
	assert_lte(second_at.y, first_at.y + 0.01, "the second cut is along or below the first (%.3f m vs %.3f m)" % [second_at.y, first_at.y])
