extends GutTest
# The player character's attack and hit animations (ticket #79): character.glb has `attack`, a jab
# then a cross thrown from his guard, and `hit`, a flinch backwards. Both play once and start and end
# in his guard (combat_idle's first frame), with his feet staying put.
#
# Interface these tests choose: his fists are the skeleton's `hand_l`/`hand_r`, his head is `head`,
# his feet are the lowest bone on each side (as in #65's and #71's tests), and forward is his +Z.

const CHARACTER_PATH := "res://assets/models/characters/character.glb"
const SAMPLES := 32


func _character() -> Node3D:
	var packed: PackedScene = load(CHARACTER_PATH)
	assert_not_null(packed, "%s loads" % CHARACTER_PATH)
	if packed == null:
		return null
	var character := packed.instantiate() as Node3D
	add_child_autofree(character)
	return character


# [character, player, skeleton], or [] (after failing).
func _rig() -> Array:
	var character := _character()
	if character == null:
		return []
	var players := character.find_children("*", "AnimationPlayer", true, false)
	var skeletons := character.find_children("*", "Skeleton3D", true, false)
	assert_true(not players.is_empty() and not skeletons.is_empty(), "the character has an AnimationPlayer and a skeleton")
	if players.is_empty() or skeletons.is_empty():
		return []
	var player := players[0] as AnimationPlayer
	for clip in ["attack", "hit", "combat_idle"]:
		assert_true(player.has_animation(clip), "he has a %s animation" % clip)
		if not player.has_animation(clip):
			return []
	return [character, player, skeletons[0]]


# Every bone's position (in the character's space) at time `t` of `clip`.
func _pose_at(rig: Array, clip: String, t: float) -> Array:
	var character: Node3D = rig[0]
	var player: AnimationPlayer = rig[1]
	var skeleton: Skeleton3D = rig[2]
	player.play(clip)
	player.seek(t, true)
	player.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	var to_character := character.global_transform.affine_inverse() * skeleton.global_transform
	var positions := []
	for b in skeleton.get_bone_count():
		positions.append(to_character * skeleton.get_bone_global_pose(b).origin)
	return positions


func _feet(rig: Array) -> Array:
	var character: Node3D = rig[0]
	var skeleton: Skeleton3D = rig[2]
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


# The largest distance between any bone in two poses.
func _largest_difference(a: Array, b: Array) -> float:
	var largest := 0.0
	for i in a.size():
		largest = maxf(largest, (a[i] as Vector3).distance_to(b[i]))
	return largest


# Given character.glb, when its AnimationPlayer is inspected, then it has attack (1.0-1.6 s) and hit
# (0.4-0.8 s), neither looping, and both start and end in his guard pose (combat_idle's first frame),
# within 3 cm for every bone.
func test_attack_and_hit_clips_start_and_end_in_his_guard():
	var rig := _rig()
	if rig.is_empty():
		return
	var player: AnimationPlayer = rig[1]
	var attack := player.get_animation("attack")
	var hit := player.get_animation("hit")
	assert_between(attack.length, 1.0, 1.6, "attack lasts 1.0-1.6 s (%.2f s)" % attack.length)
	assert_between(hit.length, 0.4, 0.8, "hit lasts 0.4-0.8 s (%.2f s)" % hit.length)
	for clip in ["attack", "hit"]:
		assert_eq(player.get_animation(clip).loop_mode, Animation.LOOP_NONE, "%s plays once" % clip)
	var guard := _pose_at(rig, "combat_idle", 0.0)
	for clip in ["attack", "hit"]:
		var length := player.get_animation(clip).length
		var start := _largest_difference(_pose_at(rig, clip, 0.0), guard)
		var finish := _largest_difference(_pose_at(rig, clip, length), guard)
		assert_lte(start, 0.03, "%s starts in his guard (%.3f m off)" % [clip, start])
		assert_lte(finish, 0.03, "%s ends in his guard (%.3f m off)" % [clip, finish])


# Given attack is sampled, when his fists are measured, then each fist (hand_l, hand_r) shoots out
# once: at least 0.25 m further forward than in his guard at its peak. The left fist peaks in the
# first half of the clip and the right fist in the second half.
func test_attack_throws_a_jab_then_a_cross():
	var rig := _rig()
	if rig.is_empty():
		return
	var player: AnimationPlayer = rig[1]
	var skeleton: Skeleton3D = rig[2]
	var length := player.get_animation("attack").length
	var guard := _pose_at(rig, "combat_idle", 0.0)
	for hand in ["hand_l", "hand_r"]:
		var bone := skeleton.find_bone(hand)
		assert_gte(bone, 0, "his skeleton has %s" % hand)
		if bone < 0:
			return
		var best := -INF
		var best_t := 0.0
		for i in SAMPLES + 1:
			var t := length * i / SAMPLES
			var reach: float = _pose_at(rig, "attack", t)[bone].z - guard[bone].z
			if reach > best:
				best = reach
				best_t = t
		assert_gte(best, 0.25, "%s shoots out at least 0.25 m from his guard (%.2f m)" % [hand, best])
		if hand == "hand_l":
			assert_lt(best_t, length / 2.0, "the left fist peaks in the first half (at %.2f of %.2f s)" % [best_t, length])
		else:
			assert_gt(best_t, length / 2.0, "the right fist peaks in the second half (at %.2f of %.2f s)" % [best_t, length])


# Given hit is sampled, when his head is measured, then it rocks back at least 0.08 m from where it
# is in his guard before returning.
func test_hit_rocks_his_head_back():
	var rig := _rig()
	if rig.is_empty():
		return
	var player: AnimationPlayer = rig[1]
	var skeleton: Skeleton3D = rig[2]
	var head := skeleton.find_bone("head")
	assert_gte(head, 0, "his skeleton has a head bone")
	if head < 0:
		return
	var length := player.get_animation("hit").length
	var guard_z: float = _pose_at(rig, "combat_idle", 0.0)[head].z
	var furthest := 0.0
	for i in SAMPLES + 1:
		furthest = maxf(furthest, guard_z - _pose_at(rig, "hit", length * i / SAMPLES)[head].z)
	assert_gte(furthest, 0.08, "his head rocks back at least 0.08 m (%.2f m)" % furthest)


# Given attack or hit is playing, when his feet are measured, then they stay put (within 3 cm).
func test_his_feet_stay_put():
	var rig := _rig()
	if rig.is_empty():
		return
	var player: AnimationPlayer = rig[1]
	var skeleton: Skeleton3D = rig[2]
	var feet := _feet(rig)
	assert_true(feet[0] >= 0 and feet[1] >= 0, "he has a foot on each side")
	if feet[0] < 0 or feet[1] < 0:
		return
	for clip in ["attack", "hit"]:
		var length := player.get_animation(clip).length
		var start := _pose_at(rig, clip, 0.0)
		for i in SAMPLES + 1:
			var pose := _pose_at(rig, clip, length * i / SAMPLES)
			for foot: int in feet:
				var moved: float = pose[foot].distance_to(start[foot])
				assert_lt(moved, 0.03, "his feet stay put in %s (%s moved %.3f m)" % [clip, skeleton.get_bone_name(foot), moved])
				if moved >= 0.03:
					return
