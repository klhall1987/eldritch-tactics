extends GutTest
# The cultist's attack and hit animations (ticket #80): cultist.glb has `attack`, two fist swings (left
# arm, then right), and `hit`, a flinch backwards. Both play once and start and end in the pose idle
# starts in, with its feet staying put.
#
# Interface these tests choose: its rig's bones point along their own +Y. An arm (`arm_l`/`arm_r`,
# one bone from shoulder to wrist) "swings" by how far that direction turns. Its feet are where each
# leg bone (`leg_l`/`leg_r`) reaches the floor in the rest pose, followed along the leg's direction.
# Forward is its +Z.

const CULTIST_PATH := "res://assets/models/characters/cultist.glb"
const SAMPLES := 32
const TIP := 0.3  # metres along a bone, for comparing poses by more than where the bone starts


# [cultist, player, skeleton], or [] (after failing).
func _rig() -> Array:
	var packed: PackedScene = load(CULTIST_PATH)
	assert_not_null(packed, "%s loads" % CULTIST_PATH)
	if packed == null:
		return []
	var cultist := packed.instantiate() as Node3D
	add_child_autofree(cultist)
	var players := cultist.find_children("*", "AnimationPlayer", true, false)
	var skeletons := cultist.find_children("*", "Skeleton3D", true, false)
	assert_true(not players.is_empty() and not skeletons.is_empty(), "the cultist has an AnimationPlayer and a skeleton")
	if players.is_empty() or skeletons.is_empty():
		return []
	var player := players[0] as AnimationPlayer
	for clip in ["attack", "hit", "idle"]:
		assert_true(player.has_animation(clip), "it has a %s animation" % clip)
		if not player.has_animation(clip):
			return []
	return [cultist, player, skeletons[0]]


# Every bone's pose (in the cultist's space) at time `t` of `clip`, as Transform3Ds.
func _pose_at(rig: Array, clip: String, t: float) -> Array:
	var cultist: Node3D = rig[0]
	var player: AnimationPlayer = rig[1]
	var skeleton: Skeleton3D = rig[2]
	player.play(clip)
	player.seek(t, true)
	player.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	var to_cultist := cultist.global_transform.affine_inverse() * skeleton.global_transform
	var poses := []
	for b in skeleton.get_bone_count():
		poses.append(to_cultist * skeleton.get_bone_global_pose(b))
	return poses


# The largest distance between two poses, comparing where each bone starts and a point TIP along it.
func _largest_difference(a: Array, b: Array) -> float:
	var largest := 0.0
	for i in a.size():
		var pa: Transform3D = a[i]
		var pb: Transform3D = b[i]
		largest = maxf(largest, pa.origin.distance_to(pb.origin))
		largest = maxf(largest, (pa * Vector3(0, TIP, 0)).distance_to(pb * Vector3(0, TIP, 0)))
	return largest


# Where a leg reaches the floor in pose `p`: along the bone's direction, as far as its rest length to
# the floor.
func _foot(rig: Array, p: Transform3D, rest: Transform3D) -> Vector3:
	var down := rest.basis.y.normalized()
	var length := rest.origin.y / maxf(0.001, -down.y)
	return p.origin + p.basis.y.normalized() * length


func _bone(rig: Array, name: String) -> int:
	var skeleton: Skeleton3D = rig[2]
	var b := skeleton.find_bone(name)
	assert_gte(b, 0, "its skeleton has %s" % name)
	return b


# Given cultist.glb, when its AnimationPlayer is inspected, then it has attack (1.0-1.6 s) and hit
# (0.4-0.8 s), neither looping, and both start and end in the pose idle starts in, within 3 cm for
# every bone.
func test_attack_and_hit_start_and_end_in_its_idle_pose():
	var rig := _rig()
	if rig.is_empty():
		return
	var player: AnimationPlayer = rig[1]
	assert_between(player.get_animation("attack").length, 1.0, 1.6, "attack lasts 1.0-1.6 s (%.2f s)" % player.get_animation("attack").length)
	assert_between(player.get_animation("hit").length, 0.4, 0.8, "hit lasts 0.4-0.8 s (%.2f s)" % player.get_animation("hit").length)
	var rest := _pose_at(rig, "idle", 0.0)
	for clip in ["attack", "hit"]:
		var anim := player.get_animation(clip)
		assert_eq(anim.loop_mode, Animation.LOOP_NONE, "%s plays once" % clip)
		var start := _largest_difference(_pose_at(rig, clip, 0.0), rest)
		var finish := _largest_difference(_pose_at(rig, clip, anim.length), rest)
		assert_lte(start, 0.03, "%s starts in its idle pose (%.3f m off)" % [clip, start])
		assert_lte(finish, 0.03, "%s ends in its idle pose (%.3f m off)" % [clip, finish])


# Given attack is sampled, when its arms are measured, then each arm (arm_l, arm_r) swings up and
# forward once, at least 60 degrees from where it hangs at its peak. The left arm peaks in the first
# half of the clip and the right arm in the second half.
func test_attack_swings_left_then_right():
	var rig := _rig()
	if rig.is_empty():
		return
	var player: AnimationPlayer = rig[1]
	var length := player.get_animation("attack").length
	var rest := _pose_at(rig, "idle", 0.0)
	for arm in ["arm_l", "arm_r"]:
		var b := _bone(rig, arm)
		if b < 0:
			return
		var hanging: Vector3 = (rest[b] as Transform3D).basis.y.normalized()
		var best := 0.0
		var best_t := 0.0
		var best_dir := hanging
		for i in SAMPLES + 1:
			var t := length * i / SAMPLES
			var dir: Vector3 = (_pose_at(rig, "attack", t)[b] as Transform3D).basis.y.normalized()
			var angle := rad_to_deg(hanging.angle_to(dir))
			if angle > best:
				best = angle
				best_t = t
				best_dir = dir
		assert_gte(best, 60.0, "%s swings at least 60 degrees from where it hangs (%.0f)" % [arm, best])
		assert_gt(best_dir.z, hanging.z + 0.3, "%s swings forward" % arm)
		assert_gt(best_dir.y, hanging.y + 0.3, "%s swings up" % arm)
		if arm == "arm_l":
			assert_lt(best_t, length / 2.0, "the left arm peaks in the first half (at %.2f of %.2f s)" % [best_t, length])
		else:
			assert_gt(best_t, length / 2.0, "the right arm peaks in the second half (at %.2f of %.2f s)" % [best_t, length])


# Given hit is sampled, when its head is measured, then it rocks back at least 0.08 m from where it
# starts before returning.
func test_hit_rocks_its_head_back():
	var rig := _rig()
	if rig.is_empty():
		return
	var player: AnimationPlayer = rig[1]
	var head := _bone(rig, "head")
	if head < 0:
		return
	var length := player.get_animation("hit").length
	var start_z: float = (_pose_at(rig, "hit", 0.0)[head] as Transform3D).origin.z
	var furthest := 0.0
	for i in SAMPLES + 1:
		var z: float = (_pose_at(rig, "hit", length * i / SAMPLES)[head] as Transform3D).origin.z
		furthest = maxf(furthest, start_z - z)
	assert_gte(furthest, 0.08, "its head rocks back at least 0.08 m (%.2f m)" % furthest)


# Given attack or hit is playing, when its feet are measured, then they stay put (within 3 cm).
func test_its_feet_stay_put():
	var rig := _rig()
	if rig.is_empty():
		return
	var player: AnimationPlayer = rig[1]
	var rest := _pose_at(rig, "idle", 0.0)
	var legs := [_bone(rig, "leg_l"), _bone(rig, "leg_r")]
	if legs.has(-1):
		return
	for clip in ["attack", "hit"]:
		var length := player.get_animation(clip).length
		var start := _pose_at(rig, clip, 0.0)
		for i in SAMPLES + 1:
			var pose := _pose_at(rig, clip, length * i / SAMPLES)
			for leg: int in legs:
				var moved := _foot(rig, pose[leg], rest[leg]).distance_to(_foot(rig, start[leg], rest[leg]))
				assert_lt(moved, 0.03, "its feet stay put in %s (moved %.3f m)" % [clip, moved])
				if moved >= 0.03:
					return
