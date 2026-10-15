extends GutTest
# The detective and cultist in the garage (ticket #10): when the game starts, both stand facing
# each other on the garage floor, clear of the props, in view of the camera, playing idle.

const DETECTIVE_PATH := "res://assets/models/characters/detective.glb"
const CULTIST_PATH := "res://assets/models/characters/cultist.glb"
const PROPS := ["garage_door", "workbench", "couch", "shelves", "fridge", "mattress"]


# Instantiates the main scene into the tree, or returns null (after failing the test).
func _main() -> Node3D:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the main scene (%s) loads" % path)
	if packed == null:
		return null
	var main := packed.instantiate()
	add_child_autofree(main)
	return main as Node3D


# The detective and the cultist, or an empty array (after failing the test) if either is missing.
func _characters(main: Node) -> Array[Node3D]:
	var detective := main.find_child("Detective", true, false) as Node3D
	var cultist := main.find_child("Cultist", true, false) as Node3D
	assert_not_null(detective, "the main scene has a Node3D named Detective")
	assert_not_null(cultist, "the main scene has a Node3D named Cultist")
	if detective == null or cultist == null:
		return []
	return [detective, cultist]


# The world-space bounds of every mesh at or under `node`.
func _world_bounds(node: Node) -> AABB:
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in meshes:
		for s in mi.mesh.get_surface_count():
			for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = mi.global_transform * v
				box = AABB(p, Vector3.ZERO) if first else box.expand(p)
				first = false
	assert_false(first, "%s has geometry" % node.name)
	return box


func _overlap_horizontally(a: AABB, b: AABB) -> bool:
	return (a.position.x < b.end.x and b.position.x < a.end.x
		and a.position.z < b.end.z and b.position.z < a.end.z)


func _animation_player(character: Node) -> AnimationPlayer:
	var players := character.find_children("*", "AnimationPlayer", true, false)
	assert_eq(players.size(), 1, "%s has one AnimationPlayer" % character.name)
	return players[0] if players.size() > 0 else null


# Given the main scene, when it is instantiated, then it contains an instance of
# res://assets/models/characters/detective.glb named Detective and an instance of
# res://assets/models/characters/cultist.glb named Cultist.
func test_main_scene_has_detective_and_cultist():
	var main := _main()
	if main == null:
		return
	var characters := _characters(main)
	if characters.is_empty():
		return
	assert_eq(characters[0].scene_file_path, DETECTIVE_PATH, "Detective is an instance of the detective model")
	assert_eq(characters[1].scene_file_path, CULTIST_PATH, "Cultist is an instance of the cultist model")


# Given the main scene, when the characters' positions are measured, then both stand on the floor
# (y = 0), inside the garage's footprint, at least 1.5 m apart, and neither overlaps
# (horizontally) the bounds of any of the garage's props.
func test_characters_stand_on_the_floor_apart_and_clear_of_props():
	var main := _main()
	if main == null:
		return
	var characters := _characters(main)
	var garage := main.find_child("Garage", true, false)
	assert_not_null(garage, "the main scene has the Garage")
	if characters.is_empty() or garage == null:
		return
	var footprint := _world_bounds(garage)
	for character in characters:
		var at := character.global_position
		assert_almost_eq(at.y, 0.0, 0.01, "%s stands on the floor (y = 0)" % character.name)
		var inside := (at.x > footprint.position.x and at.x < footprint.end.x
			and at.z > footprint.position.z and at.z < footprint.end.z)
		assert_true(inside, "%s stands inside the garage's footprint" % character.name)
		var body := _world_bounds(character)
		for prop: String in PROPS:
			var prop_node := garage.find_child(prop, true, false)
			assert_not_null(prop_node, "the garage has its %s" % prop)
			if prop_node == null:
				continue
			assert_false(_overlap_horizontally(body, _world_bounds(prop_node)),
				"%s doesn't overlap the %s" % [character.name, prop])
	var apart := Vector2(characters[0].global_position.x - characters[1].global_position.x,
		characters[0].global_position.z - characters[1].global_position.z).length()
	assert_gte(apart, 1.5, "the detective and the cultist are at least 1.5 m apart")


# Given the main scene, when each character's facing (Vector3.MODEL_FRONT in its own space) is
# compared with the direction to the other, then each faces the other within 30 degrees.
func test_characters_face_each_other():
	var main := _main()
	if main == null:
		return
	var characters := _characters(main)
	if characters.is_empty():
		return
	for i in 2:
		var me := characters[i]
		var other := characters[1 - i]
		var facing := me.global_transform.basis * Vector3.MODEL_FRONT
		var to_other := other.global_position - me.global_position
		var flat_facing := Vector3(facing.x, 0, facing.z)
		var flat_to_other := Vector3(to_other.x, 0, to_other.z)
		assert_gt(flat_facing.length(), 0.0, "%s faces somewhere horizontal" % me.name)
		assert_gt(flat_to_other.length(), 0.0, "%s and %s aren't in the same spot" % [me.name, other.name])
		if flat_facing.is_zero_approx() or flat_to_other.is_zero_approx():
			continue
		assert_lte(rad_to_deg(flat_facing.angle_to(flat_to_other)), 30.0,
			"%s faces %s within 30 degrees" % [me.name, other.name])


# Given the main scene has run its first frame, when each character's AnimationPlayer is
# inspected, then it is playing idle.
func test_characters_play_idle():
	var main := _main()
	if main == null:
		return
	await wait_frames(1)
	var characters := _characters(main)
	if characters.is_empty():
		return
	for character in characters:
		var player := _animation_player(character)
		if player == null:
			continue
		assert_true(player.is_playing(), "%s's AnimationPlayer is playing" % character.name)
		assert_eq(player.current_animation, "idle", "%s is playing idle" % character.name)


# Given the main scene running in the default window size, when each character's feet and head
# are tested against the camera, then both points are inside the camera's view.
func test_camera_sees_both_characters():
	var main := _main()
	if main == null:
		return
	var characters := _characters(main)
	var cameras := main.find_children("*", "Camera3D", true, false)
	assert_eq(cameras.size(), 1, "the main scene has one Camera3D")
	if characters.is_empty() or cameras.is_empty():
		return
	var camera: Camera3D = cameras[0]
	for character in characters:
		var feet := character.global_position
		var head := Vector3(feet.x, _world_bounds(character).end.y, feet.z)
		assert_true(camera.is_position_in_frustum(feet), "%s's feet are in view" % character.name)
		assert_true(camera.is_position_in_frustum(head), "%s's head is in view" % character.name)
