extends GutTest
# The old player character's art tests are removed (ticket #139): the game is
# moving to the owner's Meshy models as Meshy delivers them, so the tests of the MPFB build's art
# (its triangle budget, separate eyes and brows, painted underwear, baked skin maps, hand-made poses
# and finger bones, and the four MakeHuman clothes) are deleted. Nothing else changes; every other
# test still runs and passes.
#
# Interface this test chooses: "listed" means the file names in res://tests/unit (not recursive), as
# test_play_as_character.gd lists folders.

const REMOVED := [
	"test_character_model.gd",
	"test_player_detail.gd",
	"test_closed_fists.gd",
	"test_natural_combat_pose.gd",
	"test_knife_guard.gd",
	"test_player_attack_anims.gd",
	"test_clothing_pieces.gd",
	"test_fabric_textures.gd",
]


# The names of the files in `dir` (not recursive), or [] if it doesn't exist.
func _files(dir: String) -> PackedStringArray:
	var access := DirAccess.open(dir)
	return access.get_files() if access != null else PackedStringArray()


# Given the project, when tests/unit/ is listed, then none of these test files (or their .uid files)
# are there: test_character_model.gd, test_player_detail.gd, test_closed_fists.gd,
# test_natural_combat_pose.gd, test_knife_guard.gd, test_player_attack_anims.gd,
# test_clothing_pieces.gd and test_fabric_textures.gd.
func test_the_old_art_tests_are_gone():
	var files := _files("res://tests/unit")
	assert_true(files.has("test_old_art_tests_removed.gd"), "tests/unit is listed (this test is in it)")
	for name: String in REMOVED:
		assert_false(files.has(name), "%s is deleted" % name)
		assert_false(files.has(name + ".uid"), "%s.uid is deleted" % name)
