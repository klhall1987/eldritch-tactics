extends GutTest
# The combat screen (ticket #30): scenes/combat.tscn shows the detective and the cultist squared off
# in a small, dark arena, close to the camera, lit by shadow-casting light with no sun.
# (Combatants are found by name, not model path: tickets #32 and #33 swap in more detailed models.)

const COMBAT_PATH := "res://scenes/combat.tscn"
const COMBATANTS := ["Detective", "Cultist"]


# Instantiates the combat scene into the tree, or returns null (after failing the test).
func _combat() -> Node3D:
	var packed: PackedScene = load(COMBAT_PATH)
	assert_not_null(packed, "the combat scene (%s) loads" % COMBAT_PATH)
	if packed == null:
		return null
	var combat := packed.instantiate()
	add_child_autofree(combat)
	return combat as Node3D


# Instantiates the combat scene inside a viewport the size of the project's default window, so
# what's on screen is judged at the game's real size rather than the tiny headless test viewport.
func _combat_in_game_window() -> Node3D:
	var packed: PackedScene = load(COMBAT_PATH)
	assert_not_null(packed, "the combat scene (%s) loads" % COMBAT_PATH)
	if packed == null:
		return null
	var window := SubViewport.new()
	window.size = Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	add_child_autofree(window)
	var combat := packed.instantiate()
	window.add_child(combat)
	return combat as Node3D


# The two combatants, or [] (after failing the test) if either is missing.
func _combatants(combat: Node) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for combatant_name in COMBATANTS:
		var node := combat.find_child(combatant_name, true, false) as Node3D
		assert_not_null(node, "the combat scene has a Node3D named %s" % combatant_name)
		if node != null:
			found.append(node)
	return found if found.size() == COMBATANTS.size() else []


# The top of a combatant: the highest point of its meshes' world bounds.
func _top(combatant: Node3D) -> float:
	var top := -INF
	for mi: MeshInstance3D in combatant.find_children("*", "MeshInstance3D", true, false):
		top = maxf(top, (mi.global_transform * mi.get_aabb()).end.y)
	return top


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


# Given the project, when res://scenes/combat.tscn is loaded and instantiated, then it loads without
# errors, its root is a Node3D, and it contains a detective named Detective and a cultist named
# Cultist.
func test_combat_scene_has_both_combatants():
	var combat := _combat()
	if combat == null:
		return
	assert_true(combat is Node3D, "the combat scene's root is a Node3D")
	var combatants := _combatants(combat)
	for combatant in combatants:
		assert_gt(combatant.find_children("*", "MeshInstance3D", true, false).size(), 0,
			"%s has a model" % combatant.name)


# Given the combat scene, when the two combatants are measured, then they stand on the floor 2-4 m
# apart and face each other within 15 degrees.
func test_combatants_face_off():
	var combat := _combat()
	if combat == null:
		return
	var combatants := _combatants(combat)
	if combatants.is_empty():
		return
	for combatant in combatants:
		assert_almost_eq(combatant.global_position.y, 0.0, 0.01, "%s stands on the floor" % combatant.name)
	var apart := _flat(combatants[1].global_position - combatants[0].global_position).length()
	assert_between(apart, 2.0, 4.0, "they stand 2-4 m apart (%.2f m)" % apart)
	for i in 2:
		var me := combatants[i]
		var other := combatants[1 - i]
		var facing := _flat(me.global_transform.basis * Vector3.MODEL_FRONT)
		var towards := _flat(other.global_position - me.global_position)
		if facing.is_zero_approx() or towards.is_zero_approx():
			assert_true(false, "%s has a facing and a direction to %s" % [me.name, other.name])
			continue
		var off := rad_to_deg(facing.angle_to(towards))
		assert_lte(off, 15.0, "%s faces %s within 15 degrees (%.1f off)" % [me.name, other.name, off])


# Given the combat scene running at the default window size, when the camera is checked, then it is
# the current camera, both combatants' feet and heads are in view, and each combatant is at least
# 40% of the screen's height tall.
func test_camera_frames_the_standoff():
	var combat := _combat_in_game_window()
	if combat == null:
		return
	var cameras := combat.find_children("*", "Camera3D", true, false)
	assert_eq(cameras.size(), 1, "the combat scene has one Camera3D")
	var combatants := _combatants(combat)
	if cameras.is_empty() or combatants.is_empty():
		return
	var camera: Camera3D = cameras[0]
	assert_true(camera.is_current(), "the camera is the current camera")
	var screen_height := float(camera.get_viewport().get_visible_rect().size.y)
	for combatant in combatants:
		var feet := combatant.global_position
		var head := Vector3(feet.x, _top(combatant), feet.z)
		assert_true(camera.is_position_in_frustum(feet), "%s's feet are in view" % combatant.name)
		assert_true(camera.is_position_in_frustum(head), "%s's head is in view" % combatant.name)
		var tall := absf(camera.unproject_position(feet).y - camera.unproject_position(head).y)
		assert_gte(tall, 0.4 * screen_height,
			"%s is at least 40%% of the screen tall (%.0f of %.0f px)" % [combatant.name, tall, screen_height])


# Given the combat scene, when its lighting is inspected, then it has at least one light that casts
# shadows and no DirectionalLight3D, and its ambient light is dim (as in the garage, #16).
func test_combat_is_lit_dark_with_shadows():
	var combat := _combat()
	if combat == null:
		return
	var shadow_lights := 0
	for light: Light3D in combat.find_children("*", "Light3D", true, false):
		if light.shadow_enabled and light.light_energy > 0.0 and light.is_visible_in_tree():
			shadow_lights += 1
	assert_gt(shadow_lights, 0, "the combat scene has a visible light that casts shadows")
	assert_eq(combat.find_children("*", "DirectionalLight3D", true, false).size(), 0, "there is no sun")
	# Dim, as #16 measures it: a flat ambient colour with strength 0.05-0.2.
	var world_environments := combat.find_children("*", "WorldEnvironment", true, false)
	assert_eq(world_environments.size(), 1, "the combat scene has one WorldEnvironment")
	if world_environments.is_empty() or world_environments[0].environment == null:
		return
	var environment: Environment = world_environments[0].environment
	assert_eq(environment.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR, "the ambient light is a flat colour")
	var c := environment.ambient_light_color
	var strength := environment.ambient_light_energy * maxf(c.r, maxf(c.g, c.b))
	assert_between(strength, 0.05, 0.2, "the ambient light is dim (strength %.3f)" % strength)
