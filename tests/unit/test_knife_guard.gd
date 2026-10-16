extends GutTest
# A knife fighter's guard (ticket #100): in combat_idle the player character's left arm guards close in
# front of him without folding flat (so its skin keeps its thickness), and his right arm reaches out
# with the knife pointed at his opponent.
#
# Interface these tests choose (positions are bone heads in the character's space: +X his left, +Y up,
# +Z the way he faces):
# - His shoulder is `upperarm_*`, elbow `lowerarm_*`, wrist `hand_*`, chest `spine_03`, waist `pelvis`
#   and chin height the `head` bone (at the top of his neck).
# - The elbow's bend is the angle at `lowerarm_l` between the upper arm (towards `upperarm_l`) and the
#   forearm (towards `hand_l`): 180 is straight, small is folded flat.
# - His left forearm's skin is the vertices of his `body` mesh that follow `lowerarm_l` most. Its
#   thickness is their average distance from the forearm's bone line (`lowerarm_l` to `hand_l`): in
#   the rest pose from the mesh as stored, in combat_idle skinned on the CPU.
# - The knife is the `Knife` node under `Player` (#91), its grip its origin and its tip its furthest
#   vertex; "forward" is the Player's facing (+Z).

const CHARACTER_PATH := "res://assets/models/characters/character.glb"
const SAMPLES := 12


# [character, player, skeleton], or [] (after failing).
func _rig() -> Array:
	var packed: PackedScene = load(CHARACTER_PATH)
	assert_not_null(packed, "%s loads" % CHARACTER_PATH)
	if packed == null:
		return []
	var character := packed.instantiate() as Node3D
	add_child_autofree(character)
	var players := character.find_children("*", "AnimationPlayer", true, false)
	var skeletons := character.find_children("*", "Skeleton3D", true, false)
	assert_true(not players.is_empty() and not skeletons.is_empty(), "the character has an AnimationPlayer and a skeleton")
	if players.is_empty() or skeletons.is_empty():
		return []
	return [character, players[0], skeletons[0]]


func _pose_at(rig: Array, clip: String, t: float) -> void:
	var player: AnimationPlayer = rig[1]
	var skeleton: Skeleton3D = rig[2]
	player.play(clip)
	player.seek(t, true)
	player.advance(0.0)
	skeleton.force_update_all_bone_transforms()


# Where bone `name` is now, in the character's space.
func _at(rig: Array, name: String) -> Vector3:
	var character: Node3D = rig[0]
	var skeleton: Skeleton3D = rig[2]
	var b := skeleton.find_bone(name)
	assert_gte(b, 0, "his skeleton has %s" % name)
	return (character.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(b)).origin


func _each_sample(rig: Array, check: Callable) -> void:
	var length := (rig[1] as AnimationPlayer).get_animation("combat_idle").length
	for i in SAMPLES:
		_pose_at(rig, "combat_idle", length * i / SAMPLES)
		if not check.call(length * i / SAMPLES):
			return


# Given combat_idle is sampled, when his right arm is measured, then his right wrist is at least 0.4 m
# from his right shoulder and at least 0.35 m further forward than his chest.
func test_knife_arm_reaches_out():
	var rig := _rig()
	if rig.is_empty():
		return
	_each_sample(rig, func(t: float) -> bool:
		var wrist := _at(rig, "hand_r")
		var reach := wrist.distance_to(_at(rig, "upperarm_r"))
		var ahead := wrist.z - _at(rig, "spine_03").z
		assert_gte(reach, 0.4, "at %.2f s his knife arm is extended (wrist %.3f m from his shoulder)" % [t, reach])
		assert_gte(ahead, 0.35, "at %.2f s his knife hand is out in front (%.3f m ahead of his chest)" % [t, ahead])
		return reach >= 0.4 and ahead >= 0.35)


# Given combat_idle is sampled, when his left arm is measured, then his left wrist is in front of his
# chest (at least 0.1 m ahead), between his waist and chin height, and his left elbow is bent no tighter
# than 60 degrees.
func test_left_arm_guards_without_folding():
	var rig := _rig()
	if rig.is_empty():
		return
	_each_sample(rig, func(t: float) -> bool:
		var wrist := _at(rig, "hand_l")
		var elbow := _at(rig, "lowerarm_l")
		var ahead := wrist.z - _at(rig, "spine_03").z
		var waist := _at(rig, "pelvis").y
		var chin := _at(rig, "head").y
		var bend := rad_to_deg((_at(rig, "upperarm_l") - elbow).angle_to(wrist - elbow))
		assert_gte(ahead, 0.1, "at %.2f s his left hand guards in front of his chest (%.3f m ahead)" % [t, ahead])
		assert_between(wrist.y, waist, chin, "at %.2f s his left hand is between waist and chin (%.2f m; %.2f-%.2f)" % [t, wrist.y, waist, chin])
		assert_gte(bend, 60.0, "at %.2f s his left elbow isn't folded flat (%.0f degrees)" % [t, bend])
		return ahead >= 0.1 and bend >= 60.0 and wrist.y >= waist and wrist.y <= chin)


# The distance from `p` to the segment `a`-`b`.
func _from_line(p: Vector3, a: Vector3, b: Vector3) -> float:
	var along := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	return p.distance_to(a + (b - a) * along)


# Given combat_idle is sampled, when his left forearm's skin is measured, then its vertices' average
# distance from the forearm bone is at least 85% of what it is in his rest pose.
func test_left_forearm_keeps_its_thickness():
	var rig := _rig()
	if rig.is_empty():
		return
	var skeleton: Skeleton3D = rig[2]
	var body: MeshInstance3D = null
	for mi: MeshInstance3D in (rig[0] as Node).find_children("*", "MeshInstance3D", true, false):
		if mi.name.begins_with("body"):
			body = mi
	assert_not_null(body, "he has a body mesh")
	if body == null or body.skin == null:
		return
	var forearm := skeleton.find_bone("lowerarm_l")
	var wrist := skeleton.find_bone("hand_l")
	assert_true(forearm >= 0 and wrist >= 0, "his skeleton has lowerarm_l and hand_l")
	if forearm < 0 or wrist < 0:
		return
	var arrays := body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights = arrays[Mesh.ARRAY_WEIGHTS]
	var per_vertex: int = weights.size() / vertices.size()
	var bone_of := func(bind: int) -> int:
		return skeleton.find_bone(body.skin.get_bind_name(bind)) if body.skin.get_bind_name(bind) != StringName() else body.skin.get_bind_bone(bind)
	# The forearm's vertices: those that follow lowerarm_l most.
	var picked := []
	for i in vertices.size():
		var best := -1
		var best_w := 0.0
		for k in per_vertex:
			if weights[i * per_vertex + k] > best_w:
				best_w = weights[i * per_vertex + k]
				best = bone_of.call(bones[i * per_vertex + k])
		if best == forearm:
			picked.append(i)
	assert_gte(picked.size(), 8, "his left forearm has skin to measure (%d vertices)" % picked.size())
	if picked.size() < 8:
		return
	var rest_a := skeleton.get_bone_global_rest(forearm).origin
	var rest_b := skeleton.get_bone_global_rest(wrist).origin
	var rest := 0.0
	for i: int in picked:
		rest += _from_line(vertices[i], rest_a, rest_b)
	rest /= picked.size()
	_each_sample(rig, func(t: float) -> bool:
		var a := skeleton.get_bone_global_pose(forearm).origin
		var b := skeleton.get_bone_global_pose(wrist).origin
		var now := 0.0
		for i: int in picked:
			var at := Vector3.ZERO
			for k in per_vertex:
				var w: float = weights[i * per_vertex + k]
				if w > 0.0:
					var bind: int = bones[i * per_vertex + k]
					at += (skeleton.get_bone_global_pose(bone_of.call(bind)) * body.skin.get_bind_pose(bind) * vertices[i]) * w
			now += _from_line(at, a, b)
		now /= picked.size()
		assert_gte(now, rest * 0.85, "at %.2f s his left forearm keeps its thickness (%.4f m vs %.4f m at rest)" % [t, now, rest])
		return now >= rest * 0.85)


# Given he stands in combat_idle in combat, when the knife is measured, then its tip is at least 0.1 m
# further forward than its grip.
func test_knife_points_at_his_opponent():
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var main := (load(path) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	var controller := main.find_child("CombatController", true, false)
	var body := main.find_child("Player", true, false) as CharacterBody3D
	var cultist := main.find_child("Cultist", true, false) as Node3D
	body.controllable = false
	for attempt in 50:
		controller.rng.seed = 100 + attempt
		controller.start_combat([body, cultist])
		if controller.active == body:
			break
	await wait_physics_frames(3)
	var knife := body.find_child("Knife", true, false) as Node3D
	assert_true(knife != null and knife.is_visible_in_tree(), "his knife is drawn")
	if knife == null:
		return
	var grip := knife.global_position
	var tip := grip
	for mi: MeshInstance3D in knife.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p := mi.global_transform * v
				if p.distance_to(grip) > tip.distance_to(grip):
					tip = p
	var forward := body.global_basis.z.normalized()
	var ahead := (tip - grip).dot(forward)
	assert_gte(ahead, 0.1, "the knife points ahead at his opponent (tip %.3f m further forward than the grip)" % ahead)
