extends GutTest
# The Outfit keeps its loaded clothes (ticket #130): once a clothing piece has been loaded to put it on,
# it stays loaded (in Godot's resource cache) for the rest of the run, so taking it off and putting it
# back on, or loading the main scene again, reuses it rather than reading it from disk.
#
# Interface these tests choose:
# - "Still loaded" is `ResourceLoader.has_cached(path)`. "The same loaded piece" is the same
#   PackedScene instance (compared by instance id, so these tests never hold a piece themselves and
#   keep it cached by accident).
# - The main scene's `Player/Outfit` (#68) with its default pieces; `wear(slot, path)`,
#   `take_off(slot)` and `slot_of(path)`.

const DEFAULT_PIECES := [
	"res://assets/models/clothes/tee_purple.glb",
	"res://assets/models/clothes/jeans_blue.glb",
	"res://assets/models/clothes/sneakers_dark.glb",
]
const SWEATER := "res://assets/models/clothes/sweater_grey.glb"


func _main_scene() -> Node3D:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var main := (load(path) as PackedScene).instantiate()
	add_child(main)
	await wait_physics_frames(2)
	return main as Node3D


func _drop(main: Node) -> void:
	main.queue_free()
	await wait_process_frames(3)


# The instance id of the piece at `path` as loaded now (0 if it isn't loaded), without keeping it.
func _loaded_id(path: String) -> int:
	if not ResourceLoader.has_cached(path):
		return 0
	return ResourceLoader.load(path).get_instance_id()


# Given the main scene has been loaded and freed, when it's loaded again, then each default piece is
# still loaded, and the second scene uses the same loaded piece as the first.
func test_the_default_clothes_stay_loaded():
	var main := await _main_scene()
	var ids := {}
	for path: String in DEFAULT_PIECES:
		ids[path] = _loaded_id(path)
		assert_ne(ids[path], 0, "%s is loaded while he wears it" % path.get_file())
	await _drop(main)
	for path: String in DEFAULT_PIECES:
		assert_true(ResourceLoader.has_cached(path), "%s stays loaded after the scene is gone" % path.get_file())
	main = await _main_scene()
	for path: String in DEFAULT_PIECES:
		assert_eq(_loaded_id(path), ids[path], "the second scene reuses the same loaded %s" % path.get_file())
	await _drop(main)


# Given a piece is worn, when it's taken off and later worn again, then it stays loaded throughout.
func test_a_piece_taken_off_stays_loaded():
	var main := await _main_scene()
	var outfit := main.get_node("Player/Outfit")
	var tee: String = DEFAULT_PIECES[0]
	var id := _loaded_id(tee)
	outfit.take_off(outfit.slot_of(tee))
	await wait_process_frames(3)
	assert_true(ResourceLoader.has_cached(tee), "the tee stays loaded after he takes it off")
	assert_true(outfit.wear(outfit.slot_of(tee), tee), "he puts it back on")
	assert_eq(_loaded_id(tee), id, "putting it back on reuses the same loaded tee")
	await _drop(main)


# Given a piece he hasn't worn yet, when it's put on for the first time, then it's loaded once and kept
# from then on.
func test_a_new_piece_is_kept_once_worn():
	var main := await _main_scene()
	var outfit := main.get_node("Player/Outfit")
	assert_true(outfit.wear(outfit.slot_of(SWEATER), SWEATER), "he puts the sweater on")
	var id := _loaded_id(SWEATER)
	assert_ne(id, 0, "the sweater is loaded")
	outfit.take_off(outfit.slot_of(SWEATER))
	await _drop(main)
	assert_true(ResourceLoader.has_cached(SWEATER), "the sweater stays loaded after he takes it off and the scene is gone")
	assert_eq(_loaded_id(SWEATER), id, "it's the same loaded sweater")
