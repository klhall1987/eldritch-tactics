extends GutTest
# The monster's animations (ticket #107): monster.glb idles, scuttles in place on its skinny legs,
# attacks with a lunge and two snaps of its mandibles, and recoils when hit.
#
# Interface these tests choose (positions are bone heads in the monster's space: +Y up, +Z the way it
# faces):
# - Its feet are the last bone of each `leg*` chain (#106's legs): the `leg*` bone with no `leg*`
#   child. A foot is "on the floor" when it's within 0.03 m of its rest height.
# - How far the mandibles are open is the angle between the `mandible_l` and `mandible_r` bones'
#   directions (each bone's +Y axis), against that angle in `idle`'s first frame. "Open" is at least
#   20 degrees wider than that; "closed" is within 8 degrees of it.
# - Its "idle pose" is `idle`'s first frame; a clip starts or ends in it when every bone is within
#   0.03 m of it.

const MONSTER_PATH := "res://assets/models/characters/monster.glb"
const SAMPLES := 48


# [monster, player, skeleton], or [] (after failing).
func _rig() -> Array:
	var packed: PackedScene = load(MONSTER_PATH)
	assert_not_null(packed, "%s loads" % MONSTER_PATH)
	if packed == null:
		return []
	var monster := packed.instantiate() as Node3D
	add_child_autofree(monster)
	var players := monster.find_children("*", "AnimationPlayer", true, false)
	var skeletons := monster.find_children("*", "Skeleton3D", true, false)
	assert_true(not players.is_empty() and not skeletons.is_empty(), "the monster has an AnimationPlayer and a skeleton")
	if players.is_empty() or skeletons.is_empty():
		return []
	return [monster, players[0], skeletons[0]]


func _has_clips(rig: Array, clips: Array) -> bool:
	var player: AnimationPlayer = rig[1]
	for clip in clips:
		assert_true(player.has_animation(clip), "it has a %s animation" % clip)
		if not player.has_animation(clip):
			return false
	return true


# Every bone's global pose (in the monster's space) at time `t` of `clip`.
func _pose_at(rig: Array, clip: String, t: float) -> Array:
	var monster: Node3D = rig[0]
	var player: AnimationPlayer = rig[1]
	var skeleton: Skeleton3D = rig[2]
	player.play(clip)
	player.seek(t, true)
	player.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	var to_monster := monster.global_transform.affine_inverse() * skeleton.global_transform
	var poses := []
	for b in skeleton.get_bone_count():
		poses.append(to_monster * skeleton.get_bone_global_pose(b))
	return poses


func _length(rig: Array, clip: String) -> float:
	return (rig[1] as AnimationPlayer).get_animation(clip).length


func _feet(skeleton: Skeleton3D) -> Array:
	var feet := []
	for b in skeleton.get_bone_count():
		if not skeleton.get_bone_name(b).begins_with("leg"):
			continue
		var has_leg_child := false
		for child in skeleton.get_bone_children(b):
			if skeleton.get_bone_name(child).begins_with("leg"):
				has_leg_child = true
		if not has_leg_child:
			feet.append(b)
	return feet


func _bone(rig: Array, name: String) -> int:
	var b := (rig[2] as Skeleton3D).find_bone(name)
	assert_gte(b, 0, "it has a %s bone" % name)
	return b


func _largest_difference(a: Array, b: Array) -> float:
	var largest := 0.0
	for i in a.size():
		largest = maxf(largest, (a[i] as Transform3D).origin.distance_to((b[i] as Transform3D).origin))
	return largest


func _mandible_angle(pose: Array, left: int, right: int) -> float:
	return rad_to_deg((pose[left] as Transform3D).basis.y.angle_to((pose[right] as Transform3D).basis.y))


func _starts_and_ends_idle(rig: Array, clip: String) -> void:
	var idle := _pose_at(rig, "idle", 0.0)
	var start := _largest_difference(_pose_at(rig, clip, 0.0), idle)
	var finish := _largest_difference(_pose_at(rig, clip, _length(rig, clip)), idle)
	assert_lte(start, 0.03, "%s starts in its idle pose (%.3f m off)" % [clip, start])
	assert_lte(finish, 0.03, "%s ends in its idle pose (%.3f m off)" % [clip, finish])


# Given monster.glb's AnimationPlayer, when it's inspected, then it has idle (looping, 2-4 s), walk
# (looping, 0.6-1.5 s), attack (once, 1.0-1.6 s) and hit (once, 0.4-0.8 s).
func test_clips():
	var rig := _rig()
	if rig.is_empty() or not _has_clips(rig, ["idle", "walk", "attack", "hit"]):
		return
	var player: AnimationPlayer = rig[1]
	for spec in [["idle", true, 2.0, 4.0], ["walk", true, 0.6, 1.5], ["attack", false, 1.0, 1.6], ["hit", false, 0.4, 0.8]]:
		var clip := player.get_animation(spec[0])
		assert_between(clip.length, spec[2], spec[3], "%s lasts %.1f-%.1f s (%.2f s)" % [spec[0], spec[2], spec[3], clip.length])
		if spec[1]:
			assert_ne(clip.loop_mode, Animation.LOOP_NONE, "%s loops" % spec[0])
		else:
			assert_eq(clip.loop_mode, Animation.LOOP_NONE, "%s plays once" % spec[0])


# Given walk is sampled, when its feet are tracked, then every foot moves at least 0.08 m over the cycle,
# and at every moment at least half its feet are on the floor.
func test_it_scuttles_in_place():
	var rig := _rig()
	if rig.is_empty() or not _has_clips(rig, ["walk"]):
		return
	var skeleton: Skeleton3D = rig[2]
	var feet := _feet(skeleton)
	assert_gte(feet.size(), 4, "it has at least four feet")
	if feet.size() < 4:
		return
	var rest := {}
	for foot: int in feet:
		rest[foot] = (skeleton.global_transform * skeleton.get_bone_global_rest(foot)).origin.y
	var travel := {}
	var start := _pose_at(rig, "walk", 0.0)
	for i in SAMPLES:
		var pose := _pose_at(rig, "walk", _length(rig, "walk") * i / SAMPLES)
		var down := 0
		for foot: int in feet:
			var at: Vector3 = (pose[foot] as Transform3D).origin
			travel[foot] = maxf(travel.get(foot, 0.0), at.distance_to((start[foot] as Transform3D).origin))
			if at.y - rest[foot] <= 0.03:
				down += 1
		assert_gte(down * 2, feet.size(), "at sample %d at least half its feet are down (%d of %d)" % [i, down, feet.size()])
		if down * 2 < feet.size():
			return
	for foot: int in feet:
		assert_gte(travel[foot], 0.08, "%s moves over the walk (%.3f m)" % [skeleton.get_bone_name(foot), travel[foot]])


# Given attack is sampled, when its mandibles and head are measured, then the mandibles open at least 20
# degrees and close again, twice, and its head lunges at least 0.1 m forward; the clip starts and ends
# in its idle pose.
func test_it_lunges_and_snaps_twice():
	var rig := _rig()
	if rig.is_empty() or not _has_clips(rig, ["idle", "attack"]):
		return
	var left := _bone(rig, "mandible_l")
	var right := _bone(rig, "mandible_r")
	var head := _bone(rig, "head")
	if left < 0 or right < 0 or head < 0:
		return
	var idle := _pose_at(rig, "idle", 0.0)
	var shut := _mandible_angle(idle, left, right)
	var head_z: float = (idle[head] as Transform3D).origin.z
	var snaps := 0
	var open := false
	var lunge := 0.0
	for i in SAMPLES + 1:
		var pose := _pose_at(rig, "attack", _length(rig, "attack") * i / SAMPLES)
		var angle := _mandible_angle(pose, left, right) - shut
		if not open and angle >= 20.0:
			open = true
		elif open and angle <= 8.0:
			open = false
			snaps += 1
		lunge = maxf(lunge, (pose[head] as Transform3D).origin.z - head_z)
	assert_eq(snaps, 2, "its mandibles open and snap shut twice (%d)" % snaps)
	assert_gte(lunge, 0.1, "its head lunges forward (%.3f m)" % lunge)
	_starts_and_ends_idle(rig, "attack")


# Given hit is sampled, when its head is tracked, then it recoils at least 0.06 m backwards; the clip
# starts and ends in its idle pose.
func test_it_recoils_when_hit():
	var rig := _rig()
	if rig.is_empty() or not _has_clips(rig, ["idle", "hit"]):
		return
	var head := _bone(rig, "head")
	if head < 0:
		return
	var head_z: float = (_pose_at(rig, "idle", 0.0)[head] as Transform3D).origin.z
	var recoil := 0.0
	for i in SAMPLES + 1:
		var pose := _pose_at(rig, "hit", _length(rig, "hit") * i / SAMPLES)
		recoil = maxf(recoil, head_z - (pose[head] as Transform3D).origin.z)
	assert_gte(recoil, 0.06, "its head recoils backwards (%.3f m)" % recoil)
	_starts_and_ends_idle(rig, "hit")


# Given idle, attack or hit is playing, when its feet are measured, then they stay put (within 0.03 m).
func test_feet_stay_put():
	var rig := _rig()
	if rig.is_empty() or not _has_clips(rig, ["idle", "attack", "hit"]):
		return
	var skeleton: Skeleton3D = rig[2]
	var feet := _feet(skeleton)
	assert_gte(feet.size(), 4, "it has at least four feet")
	for clip in ["idle", "attack", "hit"]:
		var start := _pose_at(rig, clip, 0.0)
		for i in SAMPLES + 1:
			var pose := _pose_at(rig, clip, _length(rig, clip) * i / SAMPLES)
			for foot: int in feet:
				var moved := (pose[foot] as Transform3D).origin.distance_to((start[foot] as Transform3D).origin)
				assert_lt(moved, 0.03, "its feet stay put in %s (%s moved %.3f m)" % [clip, skeleton.get_bone_name(foot), moved])
				if moved >= 0.03:
					return
