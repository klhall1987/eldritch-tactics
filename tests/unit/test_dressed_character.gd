extends GutTest
# The player character is the dressed Meshy character (ticket #157): character.glb is the owner's fully
# dressed Meshy model as delivered, his clips named for what the game plays, each in place. (Criteria 1
# and 2, the model and its clips, are in test_meshy_character.gd.)
#
# Interface these tests choose:
# - "In place": over each clip, sampled 24 times, his hips (`Hips`) end within 0.05 m (horizontally, in
#   the character's space) of where they start, and are never more than 0.15 m from there.
# - The README check reads art/base/README.md's Meshy section (from its "## Meshy" heading to the next
#   "## " heading, or the end).

const CHARACTER_PATH := "res://assets/models/characters/character.glb"
const CLIPS := ["idle", "walk", "combat_idle", "attack", "hit"]
const SAMPLES := 24
const SOURCES := ["dressed_character_animations.glb", "dressed_character_walking.glb"]


# Loads and instantiates the character, or returns null (after failing the test).
func _character() -> Node3D:
	var packed: PackedScene = load(CHARACTER_PATH)
	assert_not_null(packed, "the character model (%s) loads" % CHARACTER_PATH)
	if packed == null:
		return null
	var character := packed.instantiate() as Node3D
	add_child_autofree(character)
	return character


# Where bone `bone` is (in the character's space) at time `t` of `clip`.
func _bone_at(character: Node3D, player: AnimationPlayer, skeleton: Skeleton3D, clip: String, t: float, bone: int) -> Vector3:
	player.play(clip)
	player.seek(t, true)
	player.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	var to_character := character.global_transform.affine_inverse() * skeleton.global_transform
	return to_character * skeleton.get_bone_global_pose(bone).origin


# Given each clip, when it's sampled, then he stays in place: his hips end within 0.05 m (horizontally)
# of where they start, and never move more than 0.15 m away in between.
func test_every_clip_stays_in_place():
	var character := _character()
	if character == null:
		return
	var players := character.find_children("*", "AnimationPlayer", true, false)
	var skeletons := character.find_children("*", "Skeleton3D", true, false)
	assert_true(players.size() == 1 and skeletons.size() == 1, "he has one AnimationPlayer and one Skeleton3D")
	if players.size() != 1 or skeletons.size() != 1:
		return
	var player: AnimationPlayer = players[0]
	var skeleton: Skeleton3D = skeletons[0]
	var hips := skeleton.find_bone("Hips")
	assert_ne(hips, -1, "his skeleton has Hips")
	if hips < 0:
		return
	for clip: String in CLIPS:
		assert_true(player.has_animation(clip), "he has the %s clip" % clip)
		if not player.has_animation(clip):
			continue
		var length := player.get_animation(clip).length
		var start := _bone_at(character, player, skeleton, clip, 0.0, hips)
		var furthest := 0.0
		for i in range(1, SAMPLES + 1):
			var at := _bone_at(character, player, skeleton, clip, minf(length * i / SAMPLES, length - 0.001), hips)
			furthest = maxf(furthest, Vector2(at.x - start.x, at.z - start.z).length())
		var end := _bone_at(character, player, skeleton, clip, length - 0.001, hips)
		var travel := Vector2(end.x - start.x, end.z - start.z).length()
		assert_lte(travel, 0.05, "%s ends where it starts (hips %.3f m away)" % [clip, travel])
		assert_lte(furthest, 0.15, "%s stays in place (hips up to %.3f m away)" % [clip, furthest])


# Given art/base/README.md's Meshy section, when it's read, then it names the dressed character's two
# files as the player character's source.
func test_the_readme_names_his_source_files():
	var readme := FileAccess.get_file_as_string("res://art/base/README.md")
	assert_ne(readme, "", "art/base/README.md is there")
	var start := readme.find("## Meshy")
	assert_ne(start, -1, "art/base/README.md has a Meshy section")
	if start < 0:
		return
	var rest := readme.substr(start + 1)
	var next := rest.find("\n## ")
	var section := rest if next < 0 else rest.substr(0, next)
	for source: String in SOURCES:
		assert_true(source in section, "the Meshy section names %s" % source)
