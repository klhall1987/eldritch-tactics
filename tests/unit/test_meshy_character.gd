extends GutTest
# The player character is the Meshy character as delivered (ticket #142): character.glb is the owner's
# Meshy model unchanged (his full-detail mesh, texture and 23-bone rig), its clips named for what the
# game plays, and the old MPFB build is gone. (Criterion 3, the knife in his right hand, is in
# test_knife_in_hand.gd; criterion 5 is the whole suite.)
#
# Interface these tests choose:
# - Meshy's bones are MESHY_BONES. Height is the vertical extent of his drawn mesh's vertices, in the
#   character's space.
# - "His body is the only mesh drawn": exactly one MeshInstance3D under the character is visible, and
#   none named `Icosphere` is.
# - Each clip is told by its length as Meshy made it: Idle_02 2.33 s, Walking 1.04 s, Block1 3.50 s,
#   Heavy_Hammer_Swing 1.83 s (each within 0.1 s); `hit` is 0.6 s (within 0.05 s) and starts in Block1's
#   first pose (every bone within 1 cm of combat_idle's at 0 s).
# - Over walk, his hips (`mixamorig:Hips`) "travel" the horizontal distance between where they are at
#   the start of the clip and at its end.

const CHARACTER_PATH := "res://assets/models/characters/character.glb"
const MESHY_BONES := [
	"mixamorig:Hips", "mixamorig:Spine", "mixamorig:Spine1", "mixamorig:Spine2", "mixamorig:Neck",
	"mixamorig:Head", "mixamorig:LeftShoulder", "mixamorig:LeftArm", "mixamorig:LeftForeArm",
	"mixamorig:LeftHand", "mixamorig:RightShoulder", "mixamorig:RightArm", "mixamorig:RightForeArm",
	"mixamorig:RightHand", "mixamorig:LeftUpLeg", "mixamorig:LeftLeg", "mixamorig:LeftFoot",
	"mixamorig:LeftToeBase", "mixamorig:RightUpLeg", "mixamorig:RightLeg", "mixamorig:RightFoot",
	"mixamorig:RightToeBase",
]
# clip -> [Meshy's length in seconds, loops]
const CLIPS := {
	"idle": [2.33, true],
	"walk": [1.04, true],
	"combat_idle": [3.5, true],
	"attack": [1.83, false],
	"hit": [0.6, false],
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
# bones (mixamorig:Hips through mixamorig:RightHand), at least 200,000 triangles, 1.70-1.80 m tall with
# his lowest point at y = 0, and his body is the only mesh drawn (Meshy's stray Icosphere isn't).
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
	assert_eq(drawn.size(), 1, "one mesh is drawn, his body (%s)" % [drawn.map(func(mi): return mi.name)])
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
	assert_gte(triangles, 200000, "his full-detail mesh, at least 200,000 triangles (has %d)" % triangles)
	assert_between(highest - lowest, 1.70, 1.80, "he's 1.70-1.80 m tall (is %.3f m)" % (highest - lowest))
	assert_almost_eq(lowest, 0.0, 0.01, "his lowest point is at y = 0 (is %.3f)" % lowest)


# Given his AnimationPlayer, when its clips are inspected, then it has idle (Meshy's Idle_02), walk
# (Walking), combat_idle (Block1), attack (Heavy_Hammer_Swing) and hit (the first 0.6 s of Block1): idle,
# walk and combat_idle loop, attack and hit play once, and over walk his hips travel no more than 0.05 m
# horizontally (he walks in place; game code moves him).
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
		var tolerance := 0.05 if clip == "hit" else 0.1
		assert_almost_eq(animation.length, expected, tolerance, "%s is Meshy's clip (%.2f s, Meshy's is %.2f s)" % [clip, animation.length, expected])
		if CLIPS[clip][1]:
			assert_ne(animation.loop_mode, Animation.LOOP_NONE, "%s loops" % clip)
		else:
			assert_eq(animation.loop_mode, Animation.LOOP_NONE, "%s plays once" % clip)
	if not (player.has_animation("hit") and player.has_animation("combat_idle") and player.has_animation("walk")):
		return
	var guard := _pose_at(character, player, skeleton, "combat_idle", 0.0)
	var flinch := _pose_at(character, player, skeleton, "hit", 0.0)
	var furthest := 0.0
	for b in skeleton.get_bone_count():
		furthest = maxf(furthest, (guard[b] as Vector3).distance_to(flinch[b]))
	assert_lt(furthest, 0.01, "hit starts in Block1's first pose (bones up to %.3f m apart)" % furthest)
	var hips := skeleton.find_bone("mixamorig:Hips")
	assert_ne(hips, -1, "his skeleton has mixamorig:Hips")
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
