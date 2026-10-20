extends GutTest
# A combat stance when combat starts (ticket #71): character.glb has a looping `combat_idle` clip (a
# raised guard on a wider stance), which plays whenever he stands still in combat instead of `idle`.
# He still plays `walk` when he moves, and goes back to `idle` once combat ends. (Worn clothes moving
# with the stance went with the old clothes, #141.)
#
# Interface these tests choose:
# - His hands are the skeleton's `mixamorig_LeftHand` and `mixamorig_RightHand` bones (the Meshy rig,
#   #142); his feet are the lowest bone on each side (as in #65's tests). "Forward" is his +Z
#   (Vector3.MODEL_FRONT).
# - "Playing" a clip means the character's AnimationPlayer's `current_animation`.

const CHARACTER_PATH := "res://assets/models/characters/character.glb"
const SAMPLES := 12


# Loads and instantiates a node from `path`, or returns null (after failing the test).
func _load(path: String) -> Node3D:
	var packed: PackedScene = load(path)
	assert_not_null(packed, "%s loads" % path)
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	add_child_autofree(node)
	return node


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


func _player_of(character: Node) -> AnimationPlayer:
	var players := character.find_children("*", "AnimationPlayer", true, false)
	return players[0] if not players.is_empty() else null


func _skeleton_of(character: Node) -> Skeleton3D:
	var skeletons := character.find_children("*", "Skeleton3D", true, false)
	return skeletons[0] if not skeletons.is_empty() else null


# Every bone's position (in the character's space) at time `t` of `clip`.
func _pose_at(character: Node3D, player: AnimationPlayer, skeleton: Skeleton3D, clip: String, t: float) -> Array:
	player.play(clip)
	player.seek(t, true)
	player.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	var to_character := character.global_transform.affine_inverse() * skeleton.global_transform
	var positions := []
	for b in skeleton.get_bone_count():
		positions.append(to_character * skeleton.get_bone_global_pose(b).origin)
	return positions


# The average position of `bone` over `clip`.
func _average(character: Node3D, player: AnimationPlayer, skeleton: Skeleton3D, clip: String, bone: int) -> Vector3:
	var length := player.get_animation(clip).length
	var total := Vector3.ZERO
	for i in SAMPLES:
		total += _pose_at(character, player, skeleton, clip, length * i / SAMPLES)[bone]
	return total / SAMPLES


# The lowest bone on his left (+x) and right (-x) in the rest pose: his feet.
func _feet(character: Node3D, skeleton: Skeleton3D) -> Array:
	var to_character := character.global_transform.affine_inverse() * skeleton.global_transform
	var left := -1
	var right := -1
	var left_y := INF
	var right_y := INF
	for b in skeleton.get_bone_count():
		var p: Vector3 = to_character * skeleton.get_bone_global_rest(b).origin
		if p.x > 0.03 and p.y < left_y:
			left = b
			left_y = p.y
		elif p.x < -0.03 and p.y < right_y:
			right = b
			right_y = p.y
	return [left, right]


# [main, controller, body (Player), character, its AnimationPlayer], or [] (after failing).
func _scene() -> Array:
	var main := await _main()
	if main == null:
		return []
	var controller := main.find_child("CombatController", true, false)
	var body := main.find_child("Player", true, false) as CharacterBody3D
	var character := main.find_child("Character", true, false) as Node3D
	if controller == null or body == null or character == null:
		return []
	var player := _player_of(character)
	assert_not_null(player, "the character has an AnimationPlayer")
	if player == null:
		return []
	return [main, controller, body, character, player]


# Starts combat on the player's turn, with fixed dice.
func _start(controller: Node, body: CharacterBody3D, cultist: Node3D) -> void:
	body.controllable = false  # as when an encounter starts (#31)
	for attempt in 50:
		controller.rng.seed = 71 + attempt
		controller.start_combat([body, cultist])
		if controller.active == body:
			break
	assert_eq(controller.active, body, "it's the player's turn")


# Given character.glb, when its AnimationPlayer is inspected, then it has a looping combat_idle
# clip, with his feet staying put. Over the clip his hands sit higher and further forward than in idle
# (raised guard). (Since #142 it's Meshy's Block1, so its length and stance are Meshy's.)
func test_character_has_a_combat_idle_guard():
	var character := _load(CHARACTER_PATH)
	if character == null:
		return
	var player := _player_of(character)
	var skeleton := _skeleton_of(character)
	assert_true(player != null and skeleton != null, "the character has an AnimationPlayer and a skeleton")
	if player == null or skeleton == null:
		return
	assert_true(player.has_animation("combat_idle"), "he has a combat_idle animation")
	if not player.has_animation("combat_idle"):
		return
	var clip := player.get_animation("combat_idle")
	assert_ne(clip.loop_mode, Animation.LOOP_NONE, "combat_idle loops")
	var feet := _feet(character, skeleton)
	assert_true(feet[0] >= 0 and feet[1] >= 0, "he has a foot on each side")
	if feet[0] < 0 or feet[1] < 0:
		return
	var start := _pose_at(character, player, skeleton, "combat_idle", 0.0)
	for i in SAMPLES:
		var pose := _pose_at(character, player, skeleton, "combat_idle", clip.length * i / SAMPLES)
		for foot: int in feet:
			var moved: float = pose[foot].distance_to(start[foot])
			assert_lt(moved, 0.02, "his feet stay put in combat_idle (%s moved %.3f m)" % [skeleton.get_bone_name(foot), moved])
			if moved >= 0.02:
				return
	for hand in ["mixamorig_LeftHand", "mixamorig_RightHand"]:
		var bone := skeleton.find_bone(hand)
		assert_gte(bone, 0, "his skeleton has %s" % hand)
		if bone < 0:
			continue
		var relaxed := _average(character, player, skeleton, "idle", bone)
		var guard := _average(character, player, skeleton, "combat_idle", bone)
		assert_gt(guard.y - relaxed.y, 0.1, "%s is held higher in the guard (%.2f m higher)" % [hand, guard.y - relaxed.y])
		assert_gt(guard.z - relaxed.z, 0.1, "%s is held further forward in the guard (%.2f m)" % [hand, guard.z - relaxed.z])


# Given combat starts, when he's standing still, then combat_idle plays, on his own turn and on the
# cultist's.
func test_he_stands_in_his_guard_in_combat():
	var scene := await _scene()
	if scene.is_empty():
		return
	var main: Node3D = scene[0]
	var controller: Node = scene[1]
	var body: CharacterBody3D = scene[2]
	var player: AnimationPlayer = scene[4]
	await wait_physics_frames(3)
	assert_eq(player.current_animation, "idle", "out of combat he stands in idle")
	_start(controller, body, main.find_child("Cultist", true, false))
	await wait_physics_frames(3)
	assert_eq(player.current_animation, "combat_idle", "on his turn he stands in combat_idle")
	controller.end_turn()
	await wait_physics_frames(3)
	assert_eq(player.current_animation, "combat_idle", "on the cultist's turn he stands in combat_idle")


# Given combat is running, when he walks along a path (#47), then walk plays while he moves, and
# combat_idle again once he stops.
func test_he_walks_then_returns_to_his_guard():
	var scene := await _scene()
	if scene.is_empty():
		return
	var main: Node3D = scene[0]
	var controller: Node = scene[1]
	var body: CharacterBody3D = scene[2]
	var player: AnimationPlayer = scene[4]
	_start(controller, body, main.find_child("Cultist", true, false))
	await wait_physics_frames(3)
	var from := body.global_position
	body.walk_path(PackedVector3Array([from, from + Vector3(0.6, 0, 0)]))
	await wait_physics_frames(5)
	assert_eq(player.current_animation, "walk", "he plays walk while moving in combat")
	for tick in 120:
		await get_tree().physics_frame
		if not body.is_walking_path():
			break
	await wait_physics_frames(3)
	assert_false(body.is_walking_path(), "he reached the end of the path")
	assert_eq(player.current_animation, "combat_idle", "he's back in combat_idle once he stops")


# Given combat ends in victory, when he's standing still, then idle plays again.
func test_idle_again_after_victory():
	var scene := await _scene()
	if scene.is_empty():
		return
	var main: Node3D = scene[0]
	var controller: Node = scene[1]
	var body: CharacterBody3D = scene[2]
	var player: AnimationPlayer = scene[4]
	var cultist := main.find_child("Cultist", true, false) as Node3D
	_start(controller, body, cultist)
	await wait_physics_frames(3)
	assert_eq(player.current_animation, "combat_idle", "in combat he stands in combat_idle")
	controller.apply_damage(cultist, 100)
	assert_false(controller.running, "combat ended in victory")
	await wait_physics_frames(3)
	assert_eq(player.current_animation, "idle", "after victory he stands in idle again")
