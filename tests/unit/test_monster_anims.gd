extends GutTest
# The monster's animations (ticket #107; since #161 the Meshy monster's, made in Blender on its Meshy
# rig): monster.glb idles, scuttles in place on its four legs, strikes with its claw, and recoils when
# hit. (Replaced by #161, as its ticket says: the mandible snaps became the claw strike, and the bones
# are #160's.)
#
# Interface these tests choose (positions are bone heads in the monster's space: +Y up, +Z the way it
# faces):
# - Its feet are the last bone of each `leg*` chain (#160's legs): the `leg*` bone with no `leg*`
#   child. A foot is "on the floor" when it's within 0.03 m of its rest height.
# - Its claw's tips are its `claw*` bones with no children (the ends of #160's three `claw_finger_*`
#   chains); how far forward the claw reaches is the furthest +Z any tip is at.
# - Its head is the average of its `head_*` bones (#160). Its body is its `body` bone.
# - Its "idle pose" is `idle`'s first frame; a clip ends in it when every bone is within 0.03 m of it.

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


func _bones_named(skeleton: Skeleton3D, prefix: String, tips_only: bool) -> Array:
	var found := []
	for b in skeleton.get_bone_count():
		if skeleton.get_bone_name(b).begins_with(prefix) and (not tips_only or skeleton.get_bone_children(b).is_empty()):
			found.append(b)
	return found


func _bone(rig: Array, name: String) -> int:
	var b := (rig[2] as Skeleton3D).find_bone(name)
	assert_gte(b, 0, "it has a %s bone" % name)
	return b


func _average(pose: Array, bones: Array) -> Vector3:
	var sum := Vector3.ZERO
	for b: int in bones:
		sum += (pose[b] as Transform3D).origin
	return sum / bones.size()


func _largest_difference(a: Array, b: Array) -> float:
	var largest := 0.0
	for i in a.size():
		largest = maxf(largest, (a[i] as Transform3D).origin.distance_to((b[i] as Transform3D).origin))
	return largest


func _ends_idle(rig: Array, clip: String) -> void:
	var finish := _largest_difference(_pose_at(rig, clip, _length(rig, clip)), _pose_at(rig, "idle", 0.0))
	assert_lte(finish, 0.03, "%s ends in its idle pose (%.3f m off)" % [clip, finish])


# Given monster.glb's AnimationPlayer, when it's inspected, then it has idle (loops, 2-4 s), walk (loops,
# 0.6-1.5 s), attack (plays once, 1.0-1.6 s) and hit (plays once, 0.4-0.8 s).
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
# at every moment at least half its feet are on the floor, and its body ends within 0.05 m
# (horizontally) of where it starts and never moves more than 0.15 m away.
func test_it_scuttles_in_place():
	var rig := _rig()
	if rig.is_empty() or not _has_clips(rig, ["walk"]):
		return
	var skeleton: Skeleton3D = rig[2]
	var feet := _feet(skeleton)
	var body := _bone(rig, "body")
	assert_gte(feet.size(), 4, "it has at least four feet")
	if feet.size() < 4 or body < 0:
		return
	var rest := {}
	for foot: int in feet:
		rest[foot] = (rig[0] as Node3D).global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_rest(foot).origin
	var travel := {}
	var start := _pose_at(rig, "walk", 0.0)
	var body_start: Vector3 = (start[body] as Transform3D).origin
	var wander := 0.0
	for i in SAMPLES + 1:
		var pose := _pose_at(rig, "walk", _length(rig, "walk") * i / SAMPLES)
		var at_body: Vector3 = (pose[body] as Transform3D).origin
		wander = maxf(wander, Vector2(at_body.x - body_start.x, at_body.z - body_start.z).length())
		if i == SAMPLES:
			var end := Vector2(at_body.x - body_start.x, at_body.z - body_start.z).length()
			assert_lte(end, 0.05, "its body ends where it started (%.3f m off)" % end)
			continue
		var down := 0
		for foot: int in feet:
			var at: Vector3 = (pose[foot] as Transform3D).origin
			travel[foot] = maxf(travel.get(foot, 0.0), at.distance_to((start[foot] as Transform3D).origin))
			if at.y - (rest[foot] as Vector3).y <= 0.03:
				down += 1
		assert_gte(down * 2, feet.size(), "at sample %d at least half its feet are down (%d of %d)" % [i, down, feet.size()])
		if down * 2 < feet.size():
			return
	assert_lte(wander, 0.15, "its body stays in place (up to %.3f m away)" % wander)
	for foot: int in feet:
		assert_gte(travel[foot], 0.08, "%s moves over the walk (%.3f m)" % [skeleton.get_bone_name(foot), travel[foot]])


# Given attack is sampled, when its claw is tracked, then its tip reaches at least 0.3 m further forward
# than in idle, and the clip ends in its idle pose.
func test_it_strikes_with_its_claw():
	var rig := _rig()
	if rig.is_empty() or not _has_clips(rig, ["idle", "attack"]):
		return
	var tips := _bones_named(rig[2], "claw", true)
	assert_gt(tips.size(), 0, "its claw has tips")
	if tips.is_empty():
		return
	var idle := _pose_at(rig, "idle", 0.0)
	var idle_reach := -INF
	for tip: int in tips:
		idle_reach = maxf(idle_reach, (idle[tip] as Transform3D).origin.z)
	var reach := 0.0
	for i in SAMPLES + 1:
		var pose := _pose_at(rig, "attack", _length(rig, "attack") * i / SAMPLES)
		for tip: int in tips:
			reach = maxf(reach, (pose[tip] as Transform3D).origin.z - idle_reach)
	assert_gte(reach, 0.3, "its claw strikes forward (%.3f m beyond idle)" % reach)
	_ends_idle(rig, "attack")


# Given hit is sampled, when its head is tracked, then it recoils at least 0.06 m backwards, and the clip
# ends in its idle pose.
func test_it_recoils_when_hit():
	var rig := _rig()
	if rig.is_empty() or not _has_clips(rig, ["idle", "hit"]):
		return
	var head := _bones_named(rig[2], "head", false)
	assert_gt(head.size(), 0, "it has a head")
	if head.is_empty():
		return
	var head_z := _average(_pose_at(rig, "idle", 0.0), head).z
	var recoil := 0.0
	for i in SAMPLES + 1:
		var pose := _pose_at(rig, "hit", _length(rig, "hit") * i / SAMPLES)
		recoil = maxf(recoil, head_z - _average(pose, head).z)
	assert_gte(recoil, 0.06, "its head recoils backwards (%.3f m)" % recoil)
	_ends_idle(rig, "hit")


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
