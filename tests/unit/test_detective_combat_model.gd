extends GutTest
# The detective's combat model (ticket #32): a more detailed detective_combat.glb, built by the same
# script at a higher detail level, used by the combat screen, while the garage keeps detective.glb.

const GARAGE_MODEL := "res://assets/models/characters/detective.glb"
const COMBAT_MODEL := "res://assets/models/characters/detective_combat.glb"
const COMBAT_SCENE := "res://scenes/combat.tscn"
const NOT_CLOTHES := ["face", "skin", "eye", "hair"]


# Loads and instantiates a model, or returns null (after failing the test).
func _model(path: String) -> Node3D:
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the model %s loads" % path)
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	add_child_autofree(model)
	return model


# Every surface of a model as {"material": String, "emissive": bool, "texture": Texture2D or null,
# "triangles": int}.
func _surfaces(model: Node) -> Array:
	var surfaces := []
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var indices = arrays[Mesh.ARRAY_INDEX]
			var count: int = indices.size() if indices != null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
			var material := mi.get_active_material(s) as BaseMaterial3D
			surfaces.append({
				"material": material.resource_name if material != null else "",
				"emissive": material != null and material.emission_enabled,
				"texture": material.albedo_texture if material != null else null,
				"triangles": count / 3,
			})
	return surfaces


func _triangles(model: Node) -> int:
	var total := 0
	for surface in _surfaces(model):
		total += surface.triangles
	return total


func _height(model: Node) -> float:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.size.y


func _bone_names(model: Node) -> Array:
	var names := []
	for skeleton: Skeleton3D in model.find_children("*", "Skeleton3D", true, false):
		for i in skeleton.get_bone_count():
			names.append(skeleton.get_bone_name(i))
	names.sort()
	return names


func _texture_size(texture: Texture2D) -> int:
	return mini(texture.get_width(), texture.get_height()) if texture != null else 0


func _starts_with_any(text: String, prefixes: Array) -> bool:
	for prefix: String in prefixes:
		if text.begins_with(prefix):
			return true
	return false


# Given the project, when res://assets/models/characters/detective_combat.glb is loaded, then it
# loads, and has at least twice as many triangles as detective.glb and at most 60000.
func test_combat_model_is_twice_as_detailed():
	var garage := _model(GARAGE_MODEL)
	var combat := _model(COMBAT_MODEL)
	if garage == null or combat == null:
		return
	var garage_triangles := _triangles(garage)
	var combat_triangles := _triangles(combat)
	assert_gte(combat_triangles, 2 * garage_triangles,
		"the combat model has at least twice the garage model's %d triangles (has %d)" % [garage_triangles, combat_triangles])
	assert_lte(combat_triangles, 60000, "the combat model has at most 60000 triangles (has %d)" % combat_triangles)


# Given the combat model, when its textures are inspected, then its face texture is at least 1024 px
# and its clothing textures at least 512 px on their shorter sides.
func test_combat_model_has_sharper_textures():
	var combat := _model(COMBAT_MODEL)
	if combat == null:
		return
	var face := -1
	var coat := -1
	for surface in _surfaces(combat):
		var size := _texture_size(surface.texture)
		if surface.material.begins_with("face"):
			face = maxi(face, size)
		elif surface.texture != null and not surface.emissive and not _starts_with_any(surface.material, NOT_CLOTHES):
			if surface.material.begins_with("coat"):
				coat = size
			assert_gte(size, 512, "the clothing texture %s is at least 512 px (is %d)" % [surface.material, size])
	assert_gte(face, 1024, "the face texture is at least 1024 px (is %d)" % face)
	assert_gte(coat, 512, "the coat is textured at least 512 px (is %d)" % coat)


# Given the combat model, when it is compared with detective.glb, then it has the same height
# (within 2 cm), the same bone names, and looping idle and walk clips, and its only emissive
# material is the amulet.
func test_combat_model_matches_the_garage_model():
	var garage := _model(GARAGE_MODEL)
	var combat := _model(COMBAT_MODEL)
	if garage == null or combat == null:
		return
	assert_almost_eq(_height(combat), _height(garage), 0.02, "the combat model is as tall as the garage model")
	var bones := _bone_names(combat)
	assert_gt(bones.size(), 0, "the combat model has a skeleton")
	assert_eq(bones, _bone_names(garage), "the combat model has the same bones")
	var players := combat.find_children("*", "AnimationPlayer", true, false)
	assert_eq(players.size(), 1, "the combat model has one AnimationPlayer")
	if not players.is_empty():
		var player := players[0] as AnimationPlayer
		for clip in ["idle", "walk"]:
			assert_true(player.has_animation(clip), "the combat model has %s" % clip)
			if player.has_animation(clip):
				assert_ne(player.get_animation(clip).loop_mode, Animation.LOOP_NONE, "%s loops" % clip)
	var glowing := []
	for surface in _surfaces(combat):
		if surface.emissive:
			glowing.append(surface.material)
	assert_gt(glowing.size(), 0, "the amulet glows")
	for material: String in glowing:
		assert_true(material.begins_with("amulet"), "only the amulet glows (%s does too)" % material)


# Given the combat scene, when its Detective is inspected, then it is an instance of
# detective_combat.glb, while the garage's Detective is still an instance of detective.glb.
func test_combat_scene_uses_the_combat_model():
	var combat_scene: PackedScene = load(COMBAT_SCENE)
	assert_not_null(combat_scene, "the combat scene loads")
	if combat_scene != null:
		var combat := combat_scene.instantiate()
		add_child_autofree(combat)
		var detective := combat.find_child("Detective", true, false)
		assert_not_null(detective, "the combat scene has the Detective")
		if detective != null:
			assert_eq(detective.scene_file_path, COMBAT_MODEL, "the combat scene's Detective is the combat model")
	var main_scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var main := main_scene.instantiate()
	add_child_autofree(main)
	var garage_detective := main.find_child("Detective", true, false)
	assert_not_null(garage_detective, "the garage has the Detective")
	if garage_detective != null:
		assert_eq(garage_detective.scene_file_path, GARAGE_MODEL, "the garage's Detective is still detective.glb")
