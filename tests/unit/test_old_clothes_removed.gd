extends GutTest
# The old MakeHuman clothes are removed (ticket #141): the purple tee, grey sweater, blue jeans and dark
# sneakers are shaped and skinned for the MPFB body and skeleton that the Meshy character replaces, so
# they go from the project. (Criteria 1 and 2, an empty outfit and inventory, are in test_outfit.gd,
# test_inventory.gd and test_inventory_screen.gd.)
#
# Interface these tests choose:
# - "Their glbs, textures and previews" are the files in res://assets/models/clothes and
#   res://art/previews whose names start with a piece's name (`tee_purple`, `sweater_grey`,
#   `jeans_blue`, `sneakers_dark`), and "their item resources" are res://assets/items/<piece>.tres.
# - Their rows in art/base/README.md named the MakeHuman clothes folder (`makehuman/clothes/`) and each
#   source folder (`toigo_basic_tucked_t-shirt`, `toigo_fisherman_sweater`, `toigo_wool_pants`,
#   `shoes02`).

const PIECES := ["tee_purple", "sweater_grey", "jeans_blue", "sneakers_dark"]
const SOURCES := ["makehuman/clothes/", "toigo_basic_tucked_t-shirt", "toigo_fisherman_sweater", "toigo_wool_pants", "shoes02"]


# The names of the files in `dir` (not recursive), or [] if it doesn't exist.
func _files(dir: String) -> PackedStringArray:
	var access := DirAccess.open(dir)
	return access.get_files() if access != null else PackedStringArray()


# Given the project, when its files are checked, then the four pieces are gone: their glbs, textures and
# previews (assets/models/clothes/, art/previews/), their item resources (assets/items/), the build
# script art/blender/clothes/outfit.py and the MakeHuman clothes under art/base/makehuman/clothes/ (and
# their rows in art/base/README.md).
func test_the_old_clothes_are_gone():
	assert_gt(_files("res://art/previews").size(), 0, "art/previews is listed")
	for dir in ["res://assets/models/clothes", "res://art/previews"]:
		var left := []
		for file in _files(dir):
			for piece: String in PIECES:
				if file.begins_with(piece):
					left.append(file)
		assert_eq(left, [], "nothing of the old pieces is left in %s" % dir)
	for piece: String in PIECES:
		var item := "res://assets/items/%s.tres" % piece
		assert_false(FileAccess.file_exists(item), "%s is deleted" % item)
	assert_false(FileAccess.file_exists("res://art/blender/clothes/outfit.py"), "art/blender/clothes/outfit.py is deleted")
	assert_false(DirAccess.dir_exists_absolute("res://art/base/makehuman/clothes"), "art/base/makehuman/clothes is deleted")
	var readme := FileAccess.get_file_as_string("res://art/base/README.md")
	assert_ne(readme, "", "art/base/README.md is there")
	for source: String in SOURCES:
		assert_false(source in readme, "art/base/README.md no longer lists %s" % source)
