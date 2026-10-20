extends GutTest
# The Outfit hides the body regions a worn piece covers (ticket #153): putting a piece on hides the
# regions it covers (#152's `covers`), so his skin can't show through it; taking it off shows them
# again, unless another worn piece still covers them.
#
# Interface these tests choose:
# - His regions are the `body_<region>` meshes under the main scene's Character (#151). "Shown" and
#   "hidden" are their `visible`.
# - The Outfit is the main scene's `Outfit` node (#68): `wear(slot, piece_path)`, `take_off(slot)`.
# - The pieces are placeholders: test_sleeves.glb (`top`, covers `upper_arms`, #152) and
#   test_arm_bands.glb (`bottom`, also covers `upper_arms`, only for these tests), both made for
#   `male_average`.

const SLEEVES := "res://assets/models/clothes/test_sleeves.glb"
const ARM_BANDS := "res://assets/models/clothes/test_arm_bands.glb"
const REGIONS := ["head", "torso", "hips", "upper_arms", "forearms", "hands", "thighs", "calves", "feet"]


# [outfit, character], from the main scene put into the tree and let settle, or [] (after failing).
func _scene() -> Array:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the main scene (%s) loads" % path)
	if packed == null:
		return []
	var main := packed.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	var outfit := main.find_child("Outfit", true, false)
	var character := main.find_child("Character", true, false) as Node3D
	assert_true(outfit != null and character != null, "the main scene has the Outfit and the Character")
	if outfit == null or character == null:
		return []
	return [outfit, character]


# region -> whether it's shown (missing regions are left out, after failing).
func _shown(character: Node3D) -> Dictionary:
	var shown := {}
	for region: String in REGIONS:
		var mi := character.find_child("body_" + region, true, false) as MeshInstance3D
		assert_not_null(mi, "he has the body_%s region" % region)
		if mi != null:
			shown[region] = mi.visible
	return shown


# Given he wears nothing, when his body is checked, then all nine regions are shown.
func test_all_regions_show_when_he_wears_nothing():
	var scene := await _scene()
	if scene.is_empty():
		return
	var shown := _shown(scene[1])
	for region: String in shown:
		assert_true(shown[region], "body_%s is shown" % region)


# Given the test piece (covering upper_arms) is put on, when his body is checked, then body_upper_arms is
# hidden and every other region is shown.
func test_a_worn_piece_hides_what_it_covers():
	var scene := await _scene()
	if scene.is_empty():
		return
	assert_true(scene[0].wear("top", SLEEVES), "the test sleeves go on")
	await wait_physics_frames(1)
	var shown := _shown(scene[1])
	for region: String in shown:
		if region == "upper_arms":
			assert_false(shown[region], "body_upper_arms is hidden under the sleeves")
		else:
			assert_true(shown[region], "body_%s is still shown" % region)


# Given the test piece is worn, when it's taken off, then body_upper_arms is shown again.
func test_taking_it_off_shows_it_again():
	var scene := await _scene()
	if scene.is_empty():
		return
	assert_true(scene[0].wear("top", SLEEVES), "the test sleeves go on")
	await wait_physics_frames(1)
	scene[0].take_off("top")
	await wait_physics_frames(1)
	var shown := _shown(scene[1])
	for region: String in shown:
		assert_true(shown[region], "body_%s is shown once the sleeves are off" % region)


# Given two worn pieces in different slots both cover a region, when one is taken off, then that region
# stays hidden until the other is taken off too.
func test_a_region_stays_hidden_while_any_piece_covers_it():
	var scene := await _scene()
	if scene.is_empty():
		return
	var outfit: Node = scene[0]
	assert_true(outfit.wear("top", SLEEVES), "the test sleeves go on")
	assert_true(outfit.wear("bottom", ARM_BANDS), "the test arm bands go on")
	await wait_physics_frames(1)
	outfit.take_off("top")
	await wait_physics_frames(1)
	assert_false(_shown(scene[1]).get("upper_arms", true), "body_upper_arms stays hidden under the arm bands")
	outfit.take_off("bottom")
	await wait_physics_frames(1)
	assert_true(_shown(scene[1]).get("upper_arms", false), "body_upper_arms is shown once nothing covers it")
