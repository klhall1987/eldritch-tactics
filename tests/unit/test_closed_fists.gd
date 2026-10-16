extends GutTest
# Closed fists in the combat stance (ticket #83): in combat_idle his hands are fists, fingers curled
# into the palm and thumb wrapped over them; in idle they stay relaxed.
#
# Interface these tests choose: MPFB's game-engine finger bones, `<finger>_<joint>_<side>` (index,
# middle, ring, pinky, thumb; joints 01-03; l/r), and the wrist `hand_<side>`. Positions are the bones'
# heads in the character's space.

const CHARACTER_PATH := "res://assets/models/characters/character.glb"
const FINGERS := ["index", "middle", "ring", "pinky"]
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


func _bone(rig: Array, name: String) -> int:
	var b := (rig[2] as Skeleton3D).find_bone(name)
	assert_gte(b, 0, "his skeleton has %s" % name)
	return b


# Given combat_idle is sampled over the whole clip, when each hand is measured, then every fingertip
# (the last joint of the index, middle, ring and pinky: *_03_l/*_03_r) stays within 0.07 m of that
# hand's wrist (hand_l/hand_r).
func test_fingers_curl_into_fists_in_combat():
	var rig := _rig()
	if rig.is_empty():
		return
	var player: AnimationPlayer = rig[1]
	var length := player.get_animation("combat_idle").length
	for i in SAMPLES:
		var pose := _pose_at(rig, "combat_idle", length * i / SAMPLES)
		for side in ["l", "r"]:
			var wrist := _bone(rig, "hand_" + side)
			for finger in FINGERS:
				var tip := _bone(rig, "%s_03_%s" % [finger, side])
				if wrist < 0 or tip < 0:
					return
				var reach: float = pose[tip].distance_to(pose[wrist])
				assert_lte(reach, 0.07, "in his guard, his %s %s fingertip is curled in (%.3f m from the wrist)" % [side, finger, reach])
				if reach > 0.07:
					return


# Given combat_idle is sampled, when each thumb is measured, then its last joint (thumb_03_*) is
# within 0.05 m of the index finger's middle joint (index_02_*), wrapped over the fingers.
func test_thumbs_wrap_over_the_fingers():
	var rig := _rig()
	if rig.is_empty():
		return
	var player: AnimationPlayer = rig[1]
	var length := player.get_animation("combat_idle").length
	for i in SAMPLES:
		var pose := _pose_at(rig, "combat_idle", length * i / SAMPLES)
		for side in ["l", "r"]:
			var thumb := _bone(rig, "thumb_03_" + side)
			var index := _bone(rig, "index_02_" + side)
			if thumb < 0 or index < 0:
				return
			var gap: float = pose[thumb].distance_to(pose[index])
			assert_lte(gap, 0.05, "his %s thumb wraps over his fingers (%.3f m from the index's middle joint)" % [side, gap])
			if gap > 0.05:
				return


# Given idle is sampled, when his fingertips are measured, then they're as relaxed as before: each at
# least 0.1 m from its wrist.
func test_hands_stay_relaxed_out_of_combat():
	var rig := _rig()
	if rig.is_empty():
		return
	var player: AnimationPlayer = rig[1]
	var length := player.get_animation("idle").length
	for i in SAMPLES:
		var pose := _pose_at(rig, "idle", length * i / SAMPLES)
		for side in ["l", "r"]:
			var wrist := _bone(rig, "hand_" + side)
			for finger in FINGERS:
				var tip := _bone(rig, "%s_03_%s" % [finger, side])
				if wrist < 0 or tip < 0:
					return
				var reach: float = pose[tip].distance_to(pose[wrist])
				assert_gte(reach, 0.1, "out of combat his %s %s fingertip stays relaxed (%.3f m from the wrist)" % [side, finger, reach])
				if reach < 0.1:
					return
