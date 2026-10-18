extends GutTest
# Enemy body parts with their own health (ticket #122): in combat each of the monster's limbs (four
# legs, two mandibles) has its own hit points, a share of the creature's maximum, apart from its main
# pool; its body is its main pool.
#
# Interface these tests choose, on the main scene's `CombatController`:
# - `body_parts(combatant)` lists its parts: Dictionaries with `id` (unique), `name` (readable, e.g.
#   "left front leg"), `bones` (its skeleton bones) and `share` (of its maximum hit points). The body
#   is the part with id `body`; it has no share of its own (it's the main pool).
# - `part_hit_points(combatant, id)` is a part's current hit points (the body's are its main hit
#   points), `part_max_hit_points(combatant, id)` its maximum. A limb's current hit points are kept in
#   `part_health[combatant][id]`.
# - The monster's legs are `leg_N_{upper,lower,foot}_S` (N 1 front, 2 back; S l/r), its mandibles
#   `mandible_S` (#106).

const MAX_HP := 12  # the cultist's (now the monster's) max_hit_points


func _fight() -> Array:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var main := (load(path) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	var controller := main.find_child("CombatController", true, false)
	var body := main.find_child("Player", true, false) as CharacterBody3D
	var monster := main.find_child("Cultist", true, false) as Node3D
	for method in ["body_parts", "part_hit_points", "part_max_hit_points"]:
		assert_true(controller.has_method(method), "CombatController has %s()" % method)
		if not controller.has_method(method):
			return []
	body.controllable = false
	controller.rng.seed = 122
	controller.start_combat([body, monster])
	return [main, controller, body, monster]


func _parts_by(controller: Node, monster: Node3D, kind: String) -> Array:
	return controller.body_parts(monster).filter(func(p: Dictionary) -> bool: return String(p.name).contains(kind))


# Given the monster in combat, when its parts are listed, then it has four legs, two mandibles and its
# body, each with a readable name (left/right, front/back for the legs).
func test_the_monster_has_legs_mandibles_and_a_body():
	var fight := await _fight()
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var monster: Node3D = fight[3]
	var parts: Array = controller.body_parts(monster)
	assert_eq(parts.size(), 7, "it has seven parts: four legs, two mandibles and its body (%d)" % parts.size())
	var ids := {}
	var names := {}
	for part: Dictionary in parts:
		ids[part.id] = true
		names[part.name] = true
		assert_ne(String(part.name), "", "part %s has a name" % part.id)
	assert_eq(ids.size(), parts.size(), "each part has its own id")
	assert_eq(names.size(), parts.size(), "each part has its own name")
	assert_true(ids.has("body"), "its body is a part")
	var legs := _parts_by(controller, monster, "leg")
	assert_eq(legs.size(), 4, "it has four legs")
	for name in ["left front leg", "right front leg", "left back leg", "right back leg"]:
		assert_true(names.has(name), "it has a %s" % name)
	assert_eq(_parts_by(controller, monster, "mandible").size(), 2, "it has two mandibles")
	for name in ["left mandible", "right mandible"]:
		assert_true(names.has(name), "it has a %s" % name)


# Given combat starts, when the parts' hit points are read, then each leg has 25% of its maximum and each
# mandible 15% (rounded, at least 1), and its body has its main hit points.
func test_limbs_start_with_their_share():
	var fight := await _fight()
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var monster: Node3D = fight[3]
	for part: Dictionary in controller.body_parts(monster):
		if part.id == "body":
			assert_eq(controller.part_hit_points(monster, "body"), controller.hit_points[monster], "its body is its main pool")
			assert_eq(controller.part_max_hit_points(monster, "body"), MAX_HP, "its body's maximum is its maximum hit points")
			continue
		var share := 0.25 if String(part.name).contains("leg") else 0.15
		var expected := maxi(1, roundi(MAX_HP * share))
		assert_almost_eq(float(part.share), share, 0.001, "%s has a %d%% share" % [part.name, int(share * 100)])
		assert_eq(controller.part_max_hit_points(monster, part.id), expected, "%s's maximum is %d" % [part.name, expected])
		assert_eq(controller.part_hit_points(monster, part.id), expected, "%s starts with %d hit points" % [part.name, expected])
	assert_eq(controller.hit_points[monster], MAX_HP, "its main pool is untouched by its limbs")


# Given a part, when its bones are listed, then they're the monster's bones for that limb.
func test_parts_know_their_bones():
	var fight := await _fight()
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var monster: Node3D = fight[3]
	var skeleton := monster.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var expected := {
		"left front leg": ["leg_1_upper_l", "leg_1_lower_l", "leg_1_foot_l"],
		"right front leg": ["leg_1_upper_r", "leg_1_lower_r", "leg_1_foot_r"],
		"left back leg": ["leg_2_upper_l", "leg_2_lower_l", "leg_2_foot_l"],
		"right back leg": ["leg_2_upper_r", "leg_2_lower_r", "leg_2_foot_r"],
		"left mandible": ["mandible_l"],
		"right mandible": ["mandible_r"],
	}
	for part: Dictionary in controller.body_parts(monster):
		if not expected.has(part.name):
			continue
		var bones: Array = part.bones
		var sorted := bones.duplicate()
		sorted.sort()
		var want: Array = expected[part.name].duplicate()
		want.sort()
		assert_eq(sorted, want, "%s's bones are %s" % [part.name, expected[part.name]])
		for bone: String in bones:
			assert_gte(skeleton.find_bone(bone), 0, "%s's bone %s is in its skeleton" % [part.name, bone])


# Given a new combat starts, when the parts are read again, then they're back at full health.
func test_parts_heal_for_a_new_combat():
	var fight := await _fight()
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var monster: Node3D = fight[3]
	var limbs: Array = controller.body_parts(monster).filter(func(p: Dictionary) -> bool: return p.id != "body")
	for part: Dictionary in limbs:
		controller.part_health[monster][part.id] = 0
	assert_eq(controller.part_hit_points(monster, limbs[0].id), 0, "its limbs were knocked to 0")
	controller.start_combat([body, monster])
	for part: Dictionary in controller.body_parts(monster):
		assert_eq(controller.part_hit_points(monster, part.id), controller.part_max_hit_points(monster, part.id), "%s is back at full health" % part.name)
