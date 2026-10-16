extends GutTest
# Playing as the new character (ticket #66): the Player body carries the new character model
# (character.glb, from #65) as `Character`, the camera follows him and the HUD calls him "Player".
# The detective is deleted from the project (model, textures, previews, script and tests), and so is
# the old combat screen, which combat in the overworld (#45) replaced.
# (Criterion 4, "the existing movement, collision, camera, encounter, combat and HUD tests pass",
# is covered by those test files, updated to find `Character`.)

const CHARACTER_PATH := "res://assets/models/characters/character.glb"


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


# The names of the files in `dir` (not recursive), or [] if it doesn't exist.
func _files(dir: String) -> PackedStringArray:
	var access := DirAccess.open(dir)
	return access.get_files() if access != null else PackedStringArray()


# Given the main scene, when its nodes are inspected, then the Player body carries an instance of
# character.glb named Character, there's no node named Detective, the camera follows Character, and
# the HUD and dice log call him "Player".
func test_player_carries_the_new_character():
	var main := await _main()
	if main == null:
		return
	var player := main.find_child("Player", true, false)
	assert_not_null(player, "the main scene has the Player body")
	if player == null:
		return
	var character := player.get_node_or_null("Character") as Node3D
	assert_not_null(character, "the Player carries a node named Character")
	if character != null:
		assert_eq(character.scene_file_path, CHARACTER_PATH, "Character is an instance of %s" % CHARACTER_PATH)
	assert_null(main.find_child("Detective", true, false), "there's no node named Detective")
	var cameras := main.find_children("*", "Camera3D", true, false)
	assert_eq(cameras.size(), 1, "the main scene has one camera")
	if not cameras.is_empty() and character != null:
		var camera := cameras[0] as Camera3D
		assert_true("target_path" in camera, "the camera follows a target")
		if "target_path" in camera:
			assert_eq(camera.get_node_or_null(camera.target_path), character, "the camera follows Character")
	assert_eq(player.get_meta("display_name", ""), "Player", "the HUD and dice log call him Player")


# Given the project, when its files are checked, then the detective is gone: there's no
# detective.glb, detective_combat.glb, art/blender/characters/detective.py, detective textures or
# previews, and no detective test files.
func test_the_detective_is_deleted():
	for path in ["res://assets/models/characters/detective.glb",
			"res://assets/models/characters/detective_combat.glb",
			"res://art/blender/characters/detective.py"]:
		assert_false(FileAccess.file_exists(path), "%s is deleted" % path)
	for dir in ["res://assets/models/characters", "res://art/previews", "res://tests/unit"]:
		var left := []
		for file in _files(dir):
			if "detective" in file.to_lower():
				left.append(file)
		assert_eq(left, [], "nothing about the detective is left in %s" % dir)


# Given the project, when its files are checked, then the old combat screen is gone
# (scenes/combat.tscn, scripts/combat.gd and their tests), since combat happens in the overworld
# since #45.
func test_the_old_combat_screen_is_deleted():
	for path in ["res://scenes/combat.tscn", "res://scripts/combat.gd", "res://tests/unit/test_combat_screen.gd"]:
		assert_false(FileAccess.file_exists(path), "%s is deleted" % path)
