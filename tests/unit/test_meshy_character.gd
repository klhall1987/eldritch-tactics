extends GutTest
# The player character is the Meshy character as delivered (ticket #142): character.glb is the owner's
# Meshy model unchanged (his full-detail mesh, texture and 23-bone rig), its clips named for what the
# game plays, and the old MPFB build is gone. (Criterion 3, the knife in his right hand, is in
# test_knife_in_hand.gd; criterion 5 is the whole suite.)
#
# Interface these tests choose:
# - Meshy's bones are MESHY_BONES: since #157 the dressed character's rig (`Hips` ... `RightToeBase`,
#   `head_end`, `headfront`). Height is the vertical extent of his drawn mesh's vertices, in the
#   character's space.
# - "His body is the only mesh drawn": every visible MeshInstance3D under the character is one of his
#   body's region meshes, named `body_<region>` (since #151), and none named `Icosphere` is.
# - Each clip is told by its length as Meshy made it (#157): Idle_3 10.00 s (a relaxed idle, agreed on
#   #157), the rig's walking clip 1.04 s, Combat_Stance 1.67 s, Right_Hand_Sword_Slash 1.50 s,
#   Hit_Reaction 1.63 s (each within 0.1 s).
# - Over walk, his hips (`Hips`) "travel" the horizontal distance between where they are at
#   the start of the clip and at its end.

const CHARACTER_PATH := "res://assets/models/characters/character.glb"
const MESHY_BONES := [
	"Hips", "Spine02", "Spine01", "Spine", "neck", "Head", "head_end", "headfront",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
]
# clip -> [Meshy's length in seconds, loops]
const CLIPS := {
	"idle": [10.0, true],
	"walk": [1.04, true],
	"combat_idle": [1.67, true],
	"attack": [1.5, false],
	"hit": [1.63, false],
}
const OLD_TEXTURES := [
	"character_brown_eye.png", "character_eyebrow001.png", "character_eyelashes01.png",
	"character_short02_diffuse_dark.png", "character_skin_normal.png", "character_skin_roughness.png",
	"character_young_lightskinned_male_diffuse.png",
]


# Loads and instantiates the character, or returns null (after failing the test).
func _character() -> Node3D:
	var packed: PackedScene = load(CHARACTER_PATH)
	assert_not_null(packed, "the character model (%s) loads" % CHARACTER_PATH)
	if packed == null:
		return null
	var character := packed.instantiate() as Node3D
	add_child_autofree(character)
	return character


func _drawn(character: Node3D) -> Array:
	var drawn := []
	for mi: MeshInstance3D in character.find_children("*", "MeshInstance3D", true, false):
		if mi.is_visible_in_tree() and mi.mesh != null:
			drawn.append(mi)
	return drawn


# Every bone's position (in the character's space) at time `t` of `clip`.
func _pose_at(character: Node3D, player: AnimationPlayer, skeleton: Skeleton3D, clip: String, t: float) -> Array:
	player.play(clip)
	player.seek(t, true)
	player.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	var to_character := character.global_transform.affine_inverse() * skeleton.global_transform
	var positions := []
	for b in skeleton.get_bone_count():
		positions.append(to_character * skeleton.get_bone_global_pose(b).origin)
	return positions


# The names of the files in `dir` (not recursive), or [] if it doesn't exist.
func _files(dir: String) -> PackedStringArray:
	var access := DirAccess.open(dir)
	return access.get_files() if access != null else PackedStringArray()


# Given character.glb, when it's loaded, then it's the Meshy model as delivered: a skeleton with Meshy's
# bones (Hips through RightToeBase, plus head_end and headfront), at least 300,000 triangles, 1.70-1.80 m tall with
# his lowest point at y = 0, and his body is the only mesh drawn (Meshy's stray Icosphere isn't).
# (Changed by #151, as its ticket says: his body is now nine region meshes, `body_<region>`, so only
# those are drawn, and the triangles are counted over all of them.)
func test_the_meshy_model_as_delivered():
	var character := _character()
	if character == null:
		return
	var skeletons := character.find_children("*", "Skeleton3D", true, false)
	assert_eq(skeletons.size(), 1, "he has one Skeleton3D")
	if skeletons.is_empty():
		return
	var skeleton: Skeleton3D = skeletons[0]
	for bone: String in MESHY_BONES:
		assert_ne(skeleton.find_bone(bone), -1, "his skeleton has Meshy's %s" % bone)
	var drawn := _drawn(character)
	assert_gt(drawn.size(), 0, "his body is drawn")
	for mi: MeshInstance3D in drawn:
		assert_true(str(mi.name).begins_with("body_"), "only his body's region meshes are drawn (found %s)" % mi.name)
	for mi: MeshInstance3D in character.find_children("*", "MeshInstance3D", true, false):
		assert_false(mi.name.begins_with("Icosphere") and mi.is_visible_in_tree(), "Meshy's Icosphere isn't drawn")
	if drawn.is_empty():
		return
	var triangles := 0
	var lowest := INF
	var highest := -INF
	for mi: MeshInstance3D in drawn:
		var to_character := character.global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices = arrays[Mesh.ARRAY_INDEX]
			triangles += (indices.size() if indices != null and not indices.is_empty() else vertices.size()) / 3
			for v in vertices:
				var y := (to_character * v).y
				lowest = minf(lowest, y)
				highest = maxf(highest, y)
	assert_gte(triangles, 300000, "his full-detail mesh, at least 300,000 triangles (has %d)" % triangles)
	assert_between(highest - lowest, 1.70, 1.80, "he's 1.70-1.80 m tall (is %.3f m)" % (highest - lowest))
	assert_almost_eq(lowest, 0.0, 0.01, "his lowest point is at y = 0 (is %.3f)" % lowest)


# Given his AnimationPlayer, when its clips are inspected, then it has idle (Meshy's relaxed Idle_3,
# 10.00 s), walk (the rig's walking clip, about 1.04 s), combat_idle (Combat_Stance, 1.67 s), attack
# (Right_Hand_Sword_Slash, 1.50 s) and hit (Hit_Reaction, 1.63 s), each within 0.1 s: idle, walk and combat_idle loop, attack and hit
# play once. (Changed by #157, as its ticket says. Staying in place is checked for every clip in
# test_dressed_character.gd; walk's hips travel is kept here.)
func test_meshy_clips_for_what_the_game_plays():
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
	for clip: String in CLIPS:
		assert_true(player.has_animation(clip), "he has the %s clip" % clip)
		if not player.has_animation(clip):
			continue
		var animation := player.get_animation(clip)
		var expected: float = CLIPS[clip][0]
		var tolerance := 0.1
		assert_almost_eq(animation.length, expected, tolerance, "%s is Meshy's clip (%.2f s, Meshy's is %.2f s)" % [clip, animation.length, expected])
		if CLIPS[clip][1]:
			assert_ne(animation.loop_mode, Animation.LOOP_NONE, "%s loops" % clip)
		else:
			assert_eq(animation.loop_mode, Animation.LOOP_NONE, "%s plays once" % clip)
	if not player.has_animation("walk"):
		return
	var hips := skeleton.find_bone("Hips")
	assert_ne(hips, -1, "his skeleton has Hips")
	if hips < 0:
		return
	var length := player.get_animation("walk").length
	var start: Vector3 = _pose_at(character, player, skeleton, "walk", 0.0)[hips]
	var end: Vector3 = _pose_at(character, player, skeleton, "walk", length - 0.001)[hips]
	var travel := Vector2(end.x - start.x, end.z - start.z).length()
	assert_lte(travel, 0.05, "he walks in place: his hips travel %.3f m over walk" % travel)


# Given the project, when its files are checked, then the MPFB build is gone:
# art/blender/characters/character.py, art/blender/lib/human.py, art/base/makehuman/, the old
# character's extracted textures in assets/models/characters/ and its previews
# (art/previews/character_*.png).
func test_the_mpfb_build_is_gone():
	assert_gt(_files("res://assets/models/characters").size(), 0, "assets/models/characters is listed")
	for path in ["res://art/blender/characters/character.py", "res://art/blender/lib/human.py"]:
		assert_false(FileAccess.file_exists(path), "%s is deleted" % path)
	assert_false(DirAccess.dir_exists_absolute("res://art/base/makehuman"), "art/base/makehuman is deleted")
	var characters := _files("res://assets/models/characters")
	for texture: String in OLD_TEXTURES:
		assert_false(characters.has(texture), "%s is deleted" % texture)
	var previews := []
	for file in _files("res://art/previews"):
		if file.begins_with("character_"):
			previews.append(file)
	assert_eq(previews, [], "the old character's previews are deleted")
