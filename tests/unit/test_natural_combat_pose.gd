extends GutTest
# A more natural combat pose (ticket #84): combat_idle has a clear silhouette (elbows clear of the
# torso), off-centre weight (pelvis lowered, feet angled about 45 degrees to the opponent), a
# contrapposto twist and zigzag lean, a light bounce, and an upper body that stays inside the Player's
# collision capsule.
#
# Interface these tests choose (positions are bone heads in the character's space; +X is his left,
# +Y up, +Z the way he faces):
# - His feet are the lowest bone on each side (as in #65's tests); the lead foot is the one further
#   forward.
# - A part's lean is its roll about the forward axis, positive when its top tips towards his left:
#   for the pelvis and rib cage, from the line across them (`thigh_r`->`thigh_l`,
#   `upperarm_r`->`upperarm_l`), whose left end then drops; for the head, from the head bone's up
#   direction.
# - "His upper body" is every bone from the pelvis up: all but the legs (`thigh_*`, `calf_*`, `foot_*`,
#   `ball_*`) and the `Root`.

const CHARACTER_PATH := "res://assets/models/characters/character.glb"
const CAPSULE_RADIUS := 0.27  # the Player's collision capsule (#68)
const SAMPLES := 24
const LEG_PREFIXES := ["thigh_", "calf_", "foot_", "ball_"]


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


# Every bone's pose (Transform3D in the character's space) at time `t` of `clip`.
func _pose_at(rig: Array, clip: String, t: float) -> Array:
	var character: Node3D = rig[0]
	var player: AnimationPlayer = rig[1]
	var skeleton: Skeleton3D = rig[2]
	player.play(clip)
	player.seek(t, true)
	player.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	var to_character := character.global_transform.affine_inverse() * skeleton.global_transform
	var poses := []
	for b in skeleton.get_bone_count():
		poses.append(to_character * skeleton.get_bone_global_pose(b))
	return poses


# The poses sampled over the whole of `clip`.
func _samples(rig: Array, clip: String) -> Array:
	var length := (rig[1] as AnimationPlayer).get_animation(clip).length
	var all := []
	for i in SAMPLES:
		all.append(_pose_at(rig, clip, length * i / SAMPLES))
	return all


func _bone(rig: Array, name: String) -> int:
	var b := (rig[2] as Skeleton3D).find_bone(name)
	assert_gte(b, 0, "his skeleton has %s" % name)
	return b


func _at(pose: Array, bone: int) -> Vector3:
	return (pose[bone] as Transform3D).origin


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


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


# The roll of the line from `right` to `left`, as a lean (positive: the top tips to his left, so the
# left end drops), in degrees.
func _line_lean(pose: Array, right: int, left: int) -> float:
	var across := _at(pose, left) - _at(pose, right)
	return -rad_to_deg(atan2(across.y, Vector2(across.x, across.z).length()))


func _head_lean(pose: Array, head: int) -> float:
	var up := (pose[head] as Transform3D).basis.y.normalized()
	return rad_to_deg(atan2(up.x, up.y))


# The angle (degrees, 0-90) between two horizontal lines.
func _turn_between(a: Vector2, b: Vector2) -> float:
	var angle := rad_to_deg(absf(a.angle_to(b)))
	return minf(angle, 180.0 - angle)


# Clear silhouette: Given combat_idle is sampled, when his arms are measured, then each elbow
# (lowerarm_*) stays at least 0.2 m (horizontally) from the line of his spine (spine_03), leaving a
# gap between his arms and torso.
func test_clear_silhouette():
	var rig := _rig()
	if rig.is_empty():
		return
	var spine := _bone(rig, "spine_03")
	var elbows := [_bone(rig, "lowerarm_l"), _bone(rig, "lowerarm_r")]
	if spine < 0 or elbows.has(-1):
		return
	for pose in _samples(rig, "combat_idle"):
		for elbow: int in elbows:
			var gap := _flat(_at(pose, elbow)).distance_to(_flat(_at(pose, spine)))
			assert_gte(gap, 0.2, "each elbow stays clear of his torso (%.3f m from the spine line)" % gap)
			if gap < 0.2:
				return


# Off-centre gravity: Given combat_idle is sampled, when his stance is measured, then his pelvis sits
# at least 0.04 m lower than in idle (knees bent, weight on the balls of his feet), and the line from
# his rear foot to his lead foot is turned 30-60 degrees from the way he faces (angled to his
# opponent).
func test_off_centre_gravity():
	var rig := _rig()
	if rig.is_empty():
		return
	var pelvis := _bone(rig, "pelvis")
	var feet := _feet(rig)
	if pelvis < 0 or feet.has(-1):
		return
	var relaxed := 0.0
	for pose in _samples(rig, "idle"):
		relaxed += _at(pose, pelvis).y
	relaxed /= SAMPLES
	var guard := 0.0
	var samples := _samples(rig, "combat_idle")
	for pose in samples:
		guard += _at(pose, pelvis).y
	guard /= SAMPLES
	assert_gte(relaxed - guard, 0.04, "his pelvis sits at least 0.04 m lower in his guard (%.3f m lower)" % (relaxed - guard))
	var pose: Array = samples[0]
	var a := _at(pose, feet[0])
	var b := _at(pose, feet[1])
	var lead := a if a.z > b.z else b
	var rear := b if a.z > b.z else a
	var stance := _flat(lead - rear)
	var angle := rad_to_deg(stance.angle_to(Vector2(0, 1)))
	angle = absf(angle)
	assert_between(angle, 30.0, 60.0, "his feet are set at 30-60 degrees to the way he faces (%.0f)" % angle)


# Contrapposto and twist: Given combat_idle is sampled, when his body is measured, then his shoulders
# (upperarm_r->upperarm_l) are turned at least 15 degrees relative to his hips (thigh_r->thigh_l), and
# his pelvis, rib cage (spine_03) and head lean in a zigzag: rib cage the opposite way to the pelvis,
# and the head the opposite way to the rib cage, each by at least 3 degrees.
func test_contrapposto_and_twist():
	var rig := _rig()
	if rig.is_empty():
		return
	var shoulders := [_bone(rig, "upperarm_r"), _bone(rig, "upperarm_l")]
	var hips := [_bone(rig, "thigh_r"), _bone(rig, "thigh_l")]
	var head := _bone(rig, "head")
	if shoulders.has(-1) or hips.has(-1) or head < 0:
		return
	var pose: Array = _pose_at(rig, "combat_idle", 0.0)
	var twist := _turn_between(_flat(_at(pose, shoulders[1]) - _at(pose, shoulders[0])), _flat(_at(pose, hips[1]) - _at(pose, hips[0])))
	assert_gte(twist, 15.0, "his shoulders are turned at least 15 degrees against his hips (%.0f)" % twist)
	var pelvis_lean := _line_lean(pose, hips[0], hips[1])
	var rib_lean := _line_lean(pose, shoulders[0], shoulders[1])
	var head_lean := _head_lean(pose, head)
	for pair in [["pelvis", pelvis_lean], ["rib cage", rib_lean], ["head", head_lean]]:
		assert_gte(absf(pair[1]), 3.0, "his %s leans at least 3 degrees (%.1f)" % [pair[0], pair[1]])
	assert_true(signf(rib_lean) != signf(pelvis_lean), "his rib cage leans the opposite way to his pelvis (%.1f vs %.1f)" % [rib_lean, pelvis_lean])
	assert_true(signf(head_lean) != signf(rib_lean), "his head leans the opposite way to his rib cage (%.1f vs %.1f)" % [head_lean, rib_lean])


# Exaggeration: Given combat_idle is sampled over its loop, when his pelvis is measured, then it bobs
# at least 0.03 m up and down: a light, bouncing guard, not a stiff one. His feet stay put on the floor
# (within 3 cm).
func test_light_bouncing_guard():
	var rig := _rig()
	if rig.is_empty():
		return
	var pelvis := _bone(rig, "pelvis")
	var feet := _feet(rig)
	if pelvis < 0 or feet.has(-1):
		return
	var samples := _samples(rig, "combat_idle")
	var low := INF
	var high := -INF
	for pose in samples:
		low = minf(low, _at(pose, pelvis).y)
		high = maxf(high, _at(pose, pelvis).y)
		for foot: int in feet:
			var moved := _at(pose, foot).distance_to(_at(samples[0], foot))
			assert_lt(moved, 0.03, "his feet stay put as he bounces (%.3f m)" % moved)
			if moved >= 0.03:
				return
	assert_gte(high - low, 0.03, "his pelvis bobs at least 0.03 m (%.3f m)" % (high - low))


# Collision capsule fit: Given combat_idle is sampled, when his upper body (everything from the pelvis
# up: arms, fists, head) is measured from above, then every bone stays within the Player's collision
# capsule radius (0.27 m, #68) of his origin.
# (Changed by #100, as its ticket says: his right arm, from `upperarm_r` down, is left out, since his
# knife arm reaches out of the capsule in the knife fighter's guard.)
func test_upper_body_fits_the_capsule():
	var rig := _rig()
	if rig.is_empty():
		return
	var skeleton: Skeleton3D = rig[2]
	var knife_arm := skeleton.find_bone("upperarm_r")
	var upper := []
	for b in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(b)
		var leg := false
		for prefix: String in LEG_PREFIXES:
			if name.begins_with(prefix):
				leg = true
		if not leg and name != "Root" and not _in_limb(skeleton, b, knife_arm):
			upper.append(b)
	assert_gt(upper.size(), 10, "his upper body has bones to measure")
	for pose in _samples(rig, "combat_idle"):
		for b: int in upper:
			var reach := _flat(_at(pose, b)).length()
			assert_lte(reach, CAPSULE_RADIUS, "%s stays inside his capsule (%.3f m from his origin)" % [skeleton.get_bone_name(b), reach])
			if reach > CAPSULE_RADIUS:
				return


# Whether bone `b` is `limb` or hangs below it.
func _in_limb(skeleton: Skeleton3D, b: int, limb: int) -> bool:
	while b >= 0:
		if b == limb:
			return true
		b = skeleton.get_bone_parent(b)
	return false
