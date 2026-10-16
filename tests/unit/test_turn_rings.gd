extends GutTest
# Turn rings under the combatants (ticket #101): while combat runs, a ring on the floor under each
# combatant still standing shows whose turn it is: the active one's glows bright gold, everyone else's
# is dim blue (the player character) or dim red (enemies). Rings go when a combatant is defeated, and
# all go when combat ends.
#
# Interface these tests choose:
# - A ring is a MeshInstance3D in the group `turn_rings`, with metadata `combatant` (the combatant's
#   node). A ring that's hidden, or freed, is "gone".
# - Its size, seen from above, is half its mesh's world AABB width (x and z), and its height its
#   AABB's top.
# - Its colour is its material's `albedo_color`; brightness is the mean of red, green and blue.
#   "Gold": red at least 0.8, green at least 0.55, blue at most 0.35. "Blue": blue is its largest
#   channel; "red": red is its largest channel, and it isn't gold.

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


# [main, controller, body (Player), cultist], in combat on the player's turn, or [] (after failing).
func _fight() -> Array:
	var main := await _main()
	if main == null:
		return []
	var controller := main.find_child("CombatController", true, false)
	var body := main.find_child("Player", true, false) as CharacterBody3D
	var cultist := main.find_child("Cultist", true, false) as Node3D
	if controller == null or body == null or cultist == null:
		return []
	body.controllable = false
	assert_eq(_shown_rings().size(), 0, "no rings before combat")
	for attempt in 50:
		controller.rng.seed = 101 + attempt
		controller.start_combat([body, cultist])
		if controller.active == body:
			break
	assert_eq(controller.active, body, "it's the player's turn")
	await wait_physics_frames(3)
	return [main, controller, body, cultist]


func _shown_rings() -> Array:
	return get_tree().get_nodes_in_group("turn_rings").filter(func(r: Node) -> bool:
		return r is MeshInstance3D and (r as MeshInstance3D).is_visible_in_tree())


func _ring_of(combatant: Node3D) -> MeshInstance3D:
	for ring: MeshInstance3D in _shown_rings():
		if ring.get_meta("combatant", null) == combatant:
			return ring
	return null


func _colour(ring: MeshInstance3D) -> Color:
	var material := ring.get_active_material(0) as BaseMaterial3D
	return material.albedo_color if material != null else Color(0, 0, 0, 0)


func _brightness(c: Color) -> float:
	return (c.r + c.g + c.b) / 3.0


func _gold(c: Color) -> bool:
	return c.r >= 0.8 and c.g >= 0.55 and c.b <= 0.35


# Given combat has started, when the floor is checked, then every combatant has a ring under them:
# centred within 0.1 m, at most 0.05 m above the floor, with a radius of at least their body_radius
# + 0.05 m and at most 0.8 m.
func test_a_ring_under_each_combatant():
	var fight := await _fight()
	if fight.is_empty():
		return
	for combatant: Node3D in [fight[2], fight[3]]:
		var ring := _ring_of(combatant)
		assert_not_null(ring, "%s has a ring" % combatant.name)
		if ring == null:
			continue
		var box: AABB = ring.global_transform * ring.mesh.get_aabb()
		var centre := box.get_center()
		var off := Vector2(centre.x - combatant.global_position.x, centre.z - combatant.global_position.z).length()
		assert_lte(off, 0.1, "%s's ring is centred under them (%.3f m off)" % [combatant.name, off])
		assert_lte(box.end.y, 0.05, "%s's ring lies on the floor (top at %.3f m)" % [combatant.name, box.end.y])
		var radius := minf(box.size.x, box.size.z) / 2.0
		var body: float = combatant.get_meta("body_radius", 0.0)
		assert_between(radius, body + 0.05, 0.8, "%s's ring is wider than their body (radius %.2f m, body %.2f m)" % [combatant.name, radius, body])


# Given it's a combatant's turn, when the rings are compared, then the active one's is gold and at
# least 1.5 times as bright as the others; and given a combatant isn't active, their ring is dim blue
# (the player character) or dim red (an enemy).
func test_the_active_ring_glows_gold():
	var fight := await _fight()
	if fight.is_empty():
		return
	var body: Node3D = fight[2]
	var cultist: Node3D = fight[3]
	var mine := _ring_of(body)
	var theirs := _ring_of(cultist)
	assert_true(mine != null and theirs != null, "both have rings")
	if mine == null or theirs == null:
		return
	var active := _colour(mine)
	var idle := _colour(theirs)
	assert_true(_gold(active), "on his turn, his ring is gold (%s)" % active)
	assert_gte(_brightness(active), _brightness(idle) * 1.5, "his ring is much brighter than the cultist's (%.2f vs %.2f)" % [_brightness(active), _brightness(idle)])
	assert_true(idle.r > idle.g and idle.r > idle.b and not _gold(idle), "the waiting cultist's ring is dim red (%s)" % idle)


# Given the turn passes (End Turn), when the rings are checked, then the highlight moves to the new
# active combatant, and the player character's ring turns dim blue.
func test_the_highlight_moves_with_the_turn():
	var fight := await _fight()
	if fight.is_empty():
		return
	var controller: Node = fight[1]
	var body: Node3D = fight[2]
	var cultist: Node3D = fight[3]
	controller.end_turn()
	await wait_physics_frames(2)
	assert_eq(controller.active, cultist, "it's the cultist's turn")
	var mine := _ring_of(body)
	var theirs := _ring_of(cultist)
	assert_true(mine != null and theirs != null, "both still have rings")
	if mine == null or theirs == null:
		return
	var active := _colour(theirs)
	var idle := _colour(mine)
	assert_true(_gold(active), "on the cultist's turn, his ring is gold (%s)" % active)
	assert_gte(_brightness(active), _brightness(idle) * 1.5, "the cultist's ring is much brighter now (%.2f vs %.2f)" % [_brightness(active), _brightness(idle)])
	assert_true(idle.b > idle.r and idle.b > idle.g, "the waiting player character's ring is dim blue (%s)" % idle)


# Given a combatant is defeated, or combat ends, when the floor is checked, then that combatant's ring
# (or every ring, once combat ends) is gone.
func test_rings_go_with_defeat_and_combat_end():
	var fight := await _fight()
	if fight.is_empty():
		return
	var main: Node3D = fight[0]
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var cultist: Node3D = fight[3]
	# A second enemy, so defeating one doesn't end the fight.
	var second := cultist.duplicate() as Node3D
	main.add_child(second)
	second.global_position = cultist.global_position + Vector3(1.5, 0, 0)
	for attempt in 50:
		controller.rng.seed = 201 + attempt
		controller.start_combat([body, cultist, second])
		if controller.active == body:
			break
	await wait_physics_frames(3)
	assert_not_null(_ring_of(second), "the second cultist has a ring")
	controller.apply_damage(second, 100)
	await wait_physics_frames(2)
	assert_true(controller.running, "the fight goes on")
	assert_null(_ring_of(second), "the defeated cultist's ring is gone")
	assert_not_null(_ring_of(cultist), "the standing cultist keeps his ring")
	controller.apply_damage(cultist, 100)
	await wait_physics_frames(2)
	assert_false(controller.running, "combat ended in victory")
	assert_eq(_shown_rings().size(), 0, "once combat ends, every ring is gone")
