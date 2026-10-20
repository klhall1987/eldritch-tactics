extends GutTest
# The Meshy white shirt as delivered, as a top (ticket #145): shirt_white.glb is the owner's Meshy
# shirt with its full mesh and texture, scaled and placed onto his body and skinned to his Meshy
# skeleton, as a `top` piece the Outfit can put on him.
#
# Interface these tests choose:
# - A piece names its slot with `slot` metadata on its root (#67, via scripts/clothing_import.gd).
# - The piece and his body are measured as the Outfit draws them: skinned onto character.glb's skeleton
#   at rest (tests/unit/meshy_clothes.gd), sampling up to 20,000 vertices of each.
# - "Fits loosely": of his body's vertices with a shirt vertex within 8 cm roughly along their normal
#   (within 30 degrees, in front or behind: the area it covers, agreed on #145), no more than 5% have
#   that shirt vertex behind them along the body's normal (poking out through it); and at least 90% of
#   the shirt's vertices are within 5 cm of one of his body's.
# - A vertex is "weighted mostly to" the bone with its largest weight. His chest is
#   `mixamorig_Spine2`, his upper arms `mixamorig_LeftArm` / `mixamorig_RightArm`, his forearms
#   `mixamorig_LeftForeArm` / `mixamorig_RightForeArm`, his hands `mixamorig_LeftHand` /
#   `mixamorig_RightHand`.
# - Its colour is the average of its colour texture where its (sampled) vertices' UVs land, times its
#   albedo colour.

const SHIRT_PATH := "res://assets/models/clothes/shirt_white.glb"
const Clothes := preload("res://tests/unit/meshy_clothes.gd")


# Loads and instantiates a glb, or returns null (after failing the test).
func _load(path: String) -> Node3D:
	var packed = load(path) if ResourceLoader.exists(path) else null
	assert_not_null(packed, "%s loads" % path)
	if packed == null:
		return null
	var node := (packed as PackedScene).instantiate() as Node3D
	add_child_autofree(node)
	return node


# [shirt root, shirt mesh, character, his body mesh, his skeleton], or [] (after failing).
func _pieces() -> Array:
	var shirt := _load(SHIRT_PATH)
	var character := _load(Clothes.CHARACTER_PATH)
	if shirt == null or character == null:
		return []
	var mesh := Clothes.mesh_of(shirt)
	var body := Clothes.mesh_of(character)
	var skeleton := Clothes.skeleton_of(character)
	assert_true(mesh != null and body != null and skeleton != null, "the shirt has a mesh; he has a body and a skeleton")
	if mesh == null or body == null or skeleton == null:
		return []
	return [shirt, mesh, character, body, skeleton]


# Given shirt_white.glb, when it's loaded, then its slot is `top`, its mesh is skinned to bones with the
# same names as character.glb's skeleton (`mixamorig_*`), and it's Meshy's full mesh and texture: at
# least 480,000 triangles (Meshy's ~535,000) and a colour texture of at least 4096 px.
func test_meshy_shirt_as_a_top():
	var pieces := _pieces()
	if pieces.is_empty():
		return
	var shirt: Node3D = pieces[0]
	var mesh: MeshInstance3D = pieces[1]
	var skeleton: Skeleton3D = pieces[4]
	assert_eq(str(shirt.get_meta("slot", "")), "top", "the shirt fills the top slot")
	assert_not_null(mesh.skin, "the shirt is skinned")
	if mesh.skin != null:
		assert_gt(mesh.skin.get_bind_count(), 0, "the shirt has binds")
		for b in mesh.skin.get_bind_count():
			var name := mesh.skin.get_bind_name(b)
			assert_true(str(name).begins_with("mixamorig_") and skeleton.find_bone(name) >= 0,
				"the shirt's bone %s is one of his" % name)
	var count := Clothes.triangles(mesh)
	assert_gte(count, 480000, "it's Meshy's full mesh (%d triangles)" % count)
	var size := Clothes.texture_size(mesh)
	assert_gte(size, 4096, "it has Meshy's colour texture (%d px)" % size)


# Given the shirt over character.glb in the rest pose, when they're compared, then it fits loosely: no
# more than 5% of the body vertices in the area it covers poke out through it, and at least 90% of its
# vertices are within 5 cm of his body.
func test_the_shirt_fits_loosely():
	var pieces := _pieces()
	if pieces.is_empty():
		return
	var fit := Clothes.fit(pieces[1], pieces[3], pieces[4])
	assert_gt(fit.covered, 100, "the shirt covers part of his body (%d body vertices)" % fit.covered)
	assert_lte(fit.poking, 0.05, "no more than 5%% of his body pokes through the shirt (%.1f%%)" % (fit.poking * 100.0))
	assert_gte(fit.near, 0.9, "at least 90%% of the shirt is within 5 cm of his body (%.1f%%)" % (fit.near * 100.0))


# Given the shirt, when its cut is inspected, then it covers his chest and upper arms, and its rolled
# sleeves end between his elbows and wrists: some vertices on each arm are weighted mostly to a forearm
# bone, and none to a hand bone.
func test_the_shirt_covers_chest_and_arms_to_mid_forearm():
	var pieces := _pieces()
	if pieces.is_empty():
		return
	var bones: PackedStringArray = Clothes.drawn(pieces[1], pieces[4]).bones
	for bone in ["mixamorig_Spine2", "mixamorig_LeftArm", "mixamorig_RightArm", "mixamorig_LeftForeArm", "mixamorig_RightForeArm"]:
		assert_gt(bones.count(bone), 0, "some of the shirt follows %s" % bone)
	for bone in ["mixamorig_LeftHand", "mixamorig_RightHand"]:
		assert_eq(bones.count(bone), 0, "none of the shirt follows %s (%d vertices)" % [bone, bones.count(bone)])


# Given the shirt, when its colour is inspected, then it's white: the average of its colour texture
# (sampled) times its albedo colour has brightness at least 0.65 and saturation at most 0.15.
func test_the_shirt_is_white():
	var pieces := _pieces()
	if pieces.is_empty():
		return
	var colour := Clothes.colour(pieces[1], pieces[4])
	assert_gte(colour.v, 0.65, "the shirt is light (brightness %.2f)" % colour.v)
	assert_lte(colour.s, 0.15, "the shirt is hardly coloured (saturation %.2f)" % colour.s)
