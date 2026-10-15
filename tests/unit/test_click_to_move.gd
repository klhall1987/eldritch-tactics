extends GutTest
# Click to move in combat (ticket #47): on the detective's turn, the mouse over the floor previews a
# path from him to that point, with its length in metres; clicking a point within his remaining
# movement walks him there along the path (around walls and props) and takes the distance off his
# movement. Nothing happens on anyone else's turn, or outside combat.
#
# Interface these tests choose, on the main scene's `CombatController` (#45, #46):
# - The preview: `preview_path` (PackedVector3Array, from him to the point), `preview_length`
#   (metres) and `preview_reachable` (false when longer than his `movement_left`).
# - It's drawn by a `PathPreview` node (a MeshInstance3D, visible only while previewing; its
#   `material_override` colour changes when out of reach), with a Label3D under it showing the
#   length as "<metres to one decimal> m".
# - Mouse events reach the scene as normal input (`_unhandled_input`), at screen positions in the
#   scene's viewport.

const PHYSICS_FPS := 60
const START := Vector3(-1.2, 0, 0.6)  # clear floor, where he starts the game
const NEAR := Vector3(0.2, 0, -0.8)  # clear floor, 2 m from START
# Either side of the prop against the east side of the room: the straight line between them
# runs through it.
const SOUTH_OF_PROP := Vector3(3.0, 0, 1.4)
const NORTH_OF_PROP := Vector3(3.0, 0, -2.2)

var _window: SubViewport


func after_each():
	_window = null


# Instantiates the main scene inside a viewport the size of the project's default window, so
# screen positions are judged at the game's real size rather than the tiny headless test viewport.
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


# The physics body that carries the Detective (#28).
func _body(main: Node) -> CharacterBody3D:
	var node := main.find_child("Detective", true, false)
	while node != null and not node is CharacterBody3D:
		node = node.get_parent()
	assert_not_null(node, "the Detective is carried by a CharacterBody3D")
	return node as CharacterBody3D


func _animation(body: Node) -> AnimationPlayer:
	var players := body.find_children("*", "AnimationPlayer", true, false)
	assert_gt(players.size(), 0, "the detective has an AnimationPlayer")
	return players[0] if not players.is_empty() else null


func _preview_node(main: Node) -> MeshInstance3D:
	var node := main.find_child("PathPreview", true, false) as MeshInstance3D
	assert_not_null(node, "the main scene has a PathPreview MeshInstance3D")
	return node


func _preview_label(preview: Node) -> Label3D:
	var labels := preview.find_children("*", "Label3D", true, false)
	assert_eq(labels.size(), 1, "the PathPreview has a Label3D for the length")
	return labels[0] if not labels.is_empty() else null


func _colour(preview: MeshInstance3D) -> Color:
	var material := preview.material_override as BaseMaterial3D
	assert_not_null(material, "the PathPreview has a material_override with a colour")
	return material.albedo_color if material != null else Color()


# Main scene with the detective standing at `at`, in combat with the cultist, on his turn, with the
# camera settled on him. Returns [main, controller, body], or [] (after failing).
func _combat(at: Vector3) -> Array:
	var main := await _main()
	if main == null:
		return []
	var controller := main.find_child("CombatController", true, false)
	assert_not_null(controller, "the main scene has CombatController")
	var body := _body(main)
	var cultist := main.find_child("Cultist", true, false) as Node3D
	if controller == null or body == null or cultist == null:
		return []
	body.global_position = at
	body.velocity = Vector3.ZERO
	body.controllable = false  # as when an encounter starts (#31)
	controller.rng.seed = 47
	controller.start_combat([body, cultist])
	if controller.active != body:
		controller.end_turn()
	assert_eq(controller.active, body, "it's the detective's turn")
	await wait_physics_frames(3)  # the camera follows him there
	return [main, controller, body]


func _screen(main: Node, point: Vector3) -> Vector2:
	return _window.get_camera_3d().unproject_position(point)


func _hover(main: Node, point: Vector3) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = _screen(main, point)
	motion.global_position = motion.position
	_window.push_input(motion)
	await wait_physics_frames(2)


func _click(main: Node, point: Vector3) -> void:
	await _hover(main, point)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = _screen(main, point)
		click.global_position = click.position
		_window.push_input(click)
	await wait_physics_frames(1)


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += _flat(path[i]).distance_to(_flat(path[i - 1]))
	return total


# Waits (up to `seconds`) for him to stop walking, summing how far he walked, seen from above.
func _walk_distance(body: CharacterBody3D, animation: AnimationPlayer, seconds := 8.0, track := []) -> float:
	var walked := 0.0
	var last := body.global_position
	var still := 0
	for tick in int(seconds * PHYSICS_FPS):
		await get_tree().physics_frame
		walked += _flat(body.global_position).distance_to(_flat(last))
		last = body.global_position
		track.append(body.global_position)
		still = still + 1 if body.velocity.length() < 0.01 else 0
		if still > 5 and tick > 10:
			break
	return walked


# The footprints (seen from above) of the room's collision boxes (#29).
func _blockers(main: Node) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var room := main.find_child("RoomCollision", true, false)
	assert_not_null(room, "the main scene has RoomCollision")
	if room == null:
		return rects
	for shape: CollisionShape3D in room.find_children("*", "CollisionShape3D", true, false):
		if shape.shape is BoxShape3D:
			var size: Vector3 = shape.shape.size
			rects.append(Rect2(shape.global_position.x - size.x / 2, shape.global_position.z - size.z / 2, size.x, size.z))
	return rects


func _blocked(rects: Array[Rect2], point: Vector3) -> bool:
	for rect in rects:
		if rect.has_point(_flat(point)):
			return true
	return false


# Given it's the detective's turn, when the mouse is over a floor point, then a path preview from
# him to that point is shown with its length in metres, and it is marked as out of reach if it's
# longer than his remaining movement.
func test_hovering_the_floor_previews_the_path():
	var fight := await _combat(START)
	if fight.is_empty():
		return
	var main: Node3D = fight[0]
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var preview := _preview_node(main)
	if preview == null:
		return
	var label := _preview_label(preview)
	await _hover(main, NEAR)
	var path: PackedVector3Array = controller.preview_path
	assert_gt(path.size(), 1, "a path is previewed")
	if path.size() < 2:
		return
	assert_lt(_flat(path[0]).distance_to(_flat(body.global_position)), 0.3, "it starts at him")
	assert_lt(_flat(path[-1]).distance_to(_flat(NEAR)), 0.3, "it ends at the point under the mouse")
	assert_almost_eq(controller.preview_length, _length(path), 0.05, "preview_length is the path's length")
	assert_almost_eq(controller.preview_length, START.distance_to(NEAR), 0.3, "across clear floor it's about the straight distance")
	assert_true(controller.preview_reachable, "within his 9 m, it's reachable")
	assert_true(preview.visible, "the path preview is shown")
	if label != null:
		assert_string_contains(label.text, "%.1f m" % controller.preview_length, "the label shows the length in metres")
	var reachable_colour := _colour(preview)

	controller.movement_left = 1.0  # as if he had already walked most of his 9 m
	await _hover(main, NEAR + Vector3(0.05, 0, 0))
	assert_false(controller.preview_reachable, "a 2 m path with 1 m of movement left is out of reach")
	assert_true(preview.visible, "the out-of-reach path is still shown")
	assert_ne(_colour(preview), reachable_colour, "an out-of-reach path is drawn in a different colour")
	if label != null:
		assert_string_contains(label.text, "%.1f m" % controller.preview_length, "the label still shows the length")


# Given it's the detective's turn, when the player clicks a reachable floor point, then he walks
# there (playing `walk`, ending in `idle`), and his remaining movement goes down by the length of
# the path he walked, within 0.1 m.
func test_clicking_a_reachable_point_walks_him_there():
	var fight := await _combat(START)
	if fight.is_empty():
		return
	var main: Node3D = fight[0]
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var animation := _animation(body)
	if animation == null:
		return
	var before: float = controller.movement_left
	var clicked_at := body.global_position
	await _click(main, NEAR)
	await wait_physics_frames(5)
	assert_eq(animation.current_animation, "walk", "he plays walk on the way")
	# Count from the click: add what he covered (in a straight line, on the first leg) before counting.
	var walked := _flat(body.global_position).distance_to(_flat(clicked_at))
	walked += await _walk_distance(body, animation)
	assert_lt(_flat(body.global_position).distance_to(_flat(NEAR)), 0.3, "he ends at the clicked point")
	assert_eq(animation.current_animation, "idle", "he ends in idle")
	assert_gt(walked, 1.5, "he walked the 2 m there (%.2f m)" % walked)
	assert_almost_eq(before - controller.movement_left, walked, 0.1, "his movement went down by the distance walked")


# Given a clicked point is further than his remaining movement, when the player clicks it, then he
# doesn't move and his movement is unchanged.
func test_clicking_out_of_reach_does_nothing():
	var fight := await _combat(START)
	if fight.is_empty():
		return
	var main: Node3D = fight[0]
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	controller.movement_left = 1.0
	await _click(main, NEAR)
	assert_true("preview_length" in controller, "the controller measures the clicked path")
	if not "preview_length" in controller:
		return
	assert_gt(controller.preview_length, 1.5, "the clicked point is a real 2 m path away")
	await wait_physics_frames(60)
	assert_lt(_flat(body.global_position).distance_to(_flat(START)), 0.01, "he doesn't move")
	assert_almost_eq(controller.movement_left, 1.0, 0.001, "his movement is unchanged")


# Given the path to a point would go through a wall or a prop, when it is previewed or walked, then
# it goes around them (the walls and props from #29 still block him), and its length is the length
# around.
func test_paths_go_around_props():
	var fight := await _combat(SOUTH_OF_PROP)
	if fight.is_empty():
		return
	var main: Node3D = fight[0]
	var controller: Node = fight[1]
	var body: CharacterBody3D = fight[2]
	var blockers := _blockers(main)
	var straight := SOUTH_OF_PROP.distance_to(NORTH_OF_PROP)
	assert_true(_blocked(blockers, (SOUTH_OF_PROP + NORTH_OF_PROP) / 2.0), "a prop stands on the straight line between the points")
	assert_false(_blocked(blockers, SOUTH_OF_PROP) or _blocked(blockers, NORTH_OF_PROP), "both points are clear floor")
	await _hover(main, NORTH_OF_PROP)
	var path: PackedVector3Array = controller.preview_path
	assert_gt(path.size(), 2, "the path bends")
	if path.size() < 2:
		return
	assert_lt(_flat(path[-1]).distance_to(_flat(NORTH_OF_PROP)), 0.3, "it ends at the point")
	for i in range(1, path.size()):
		for step in 20:
			var point := path[i - 1].lerp(path[i], step / 20.0)
			assert_false(_blocked(blockers, point), "the path stays clear of walls and props (at %s)" % point)
			if _blocked(blockers, point):
				return
	assert_gt(controller.preview_length, straight + 0.5, "its length is the way around (%.2f m vs %.2f m straight)" % [controller.preview_length, straight])
	assert_almost_eq(controller.preview_length, _length(path), 0.05, "preview_length is the path's length")

	var before: float = controller.movement_left
	var animation := _animation(body)
	var track := []
	var clicked_at := body.global_position
	await _click(main, NORTH_OF_PROP)
	# Count from the click: add what he covered (in a straight line, on the first leg) before counting.
	var walked := _flat(body.global_position).distance_to(_flat(clicked_at))
	walked += await _walk_distance(body, animation, 8.0, track)
	assert_lt(_flat(body.global_position).distance_to(_flat(NORTH_OF_PROP)), 0.3, "he walks around to the point")
	for point: Vector3 in track:
		assert_false(_blocked(blockers, point), "he never walks into a wall or prop (at %s)" % point)
		if _blocked(blockers, point):
			break
	assert_gt(walked, straight + 0.5, "he walked the way around (%.2f m)" % walked)
	assert_almost_eq(before - controller.movement_left, walked, 0.1, "his movement went down by the distance around")


# Given it isn't the detective's turn, or combat isn't running, when the player clicks the floor,
# then nothing happens.
func test_clicks_do_nothing_off_his_turn_or_out_of_combat():
	# Out of combat.
	var main := await _main()
	if main == null:
		return
	var body := _body(main)
	var controller := main.find_child("CombatController", true, false)
	var preview := _preview_node(main)
	if body == null or controller == null or preview == null:
		return
	body.global_position = START
	await wait_physics_frames(3)
	await _click(main, NEAR)
	await wait_physics_frames(60)
	assert_false(controller.running, "combat isn't running")
	assert_lt(_flat(body.global_position).distance_to(_flat(START)), 0.01, "out of combat, a click doesn't move him")
	assert_false(preview.visible, "out of combat, no path is previewed")

	# On the cultist's turn.
	var fight := await _combat(START)
	if fight.is_empty():
		return
	main = fight[0]
	controller = fight[1]
	body = fight[2]
	preview = _preview_node(main)
	controller.end_turn()
	assert_ne(controller.active, body, "it's the cultist's turn")
	var movement_before: float = controller.movement_left
	await _click(main, NEAR)
	await wait_physics_frames(60)
	assert_lt(_flat(body.global_position).distance_to(_flat(START)), 0.01, "on the cultist's turn, a click doesn't move him")
	assert_almost_eq(controller.movement_left, movement_before, 0.001, "nobody's movement is spent")
	if preview != null:
		assert_false(preview.visible, "on the cultist's turn, no path is previewed")
