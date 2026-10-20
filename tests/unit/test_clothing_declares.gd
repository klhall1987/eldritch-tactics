extends GutTest
# Clothing pieces say what they cover and which body type they fit (ticket #152): besides its slot, a
# piece carries `body_type` and `covers` from its glTF extras, and its skeleton is that body type's
# shared skeleton. A placeholder test piece, test_sleeves.glb, shows it.
#
# Interface these tests choose:
# - Godot's glTF import puts a node's glTF extras in its `extras` metadata. The clothing pieces' import
#   script (scripts/clothing_import.gd) lifts `slot`, `body_type` and `covers` from there to metadata on
#   the piece's root: `slot` and `body_type` as Strings, `covers` as an Array of region names. Every
#   glb in res://assets/models/clothes is a clothing piece.
# - The test piece is res://assets/models/clothes/test_sleeves.glb. Its body type's skeleton is the one
#   in that body type's model (scripts/body_types.gd, #150).
# - The piece and his `body_upper_arms` region (#151) are measured as the Outfit draws them: skinned with
#   their own bind poses onto his skeleton at rest, in the skeleton's space.

const CLOTHES_DIR := "res://assets/models/clothes"
const BODY_TYPES_PATH := "res://scripts/body_types.gd"
const SLEEVES_PATH := "res://assets/models/clothes/test_sleeves.glb"
const CELL := 0.03


# Loads and instantiates a glb, or returns null (after failing the test).
func _load(path: String) -> Node3D:
	var packed = load(path) if path != "" and ResourceLoader.exists(path) else null
	assert_not_null(packed, "%s loads" % path)
	if packed == null:
		return null
	var node := (packed as PackedScene).instantiate() as Node3D
	add_child_autofree(node)
	return node


# Every vertex of `mi` as drawn on `skeleton` at rest, in the skeleton's space.
func _drawn(mi: MeshInstance3D, skeleton: Skeleton3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var binds := []
	for b in mi.skin.get_bind_count():
		var bone := skeleton.find_bone(mi.skin.get_bind_name(b))
		binds.append(skeleton.get_bone_global_rest(bone) * mi.skin.get_bind_pose(b) if bone >= 0 else null)
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var per_vertex: int = weights.size() / vertices.size() if weights != null and vertices.size() > 0 else 0
		for i in vertices.size():
			var at := Vector3.ZERO
			var total := 0.0
			for k in per_vertex:
				var w: float = weights[i * per_vertex + k]
				var xf = binds[bones[i * per_vertex + k]]
				if w > 0.0 and xf != null:
					at += ((xf as Transform3D) * vertices[i]) * w
					total += w
			out.append(at / total if total > 0.0 else vertices[i])
	return out


func _cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))


# Given a clothing piece's glb, when it's imported, then besides its slot it carries body_type (a body
# type name) and covers (a list of region names), read from its glTF extras like slot is.
func test_every_piece_carries_its_extras():
	var pieces := []
	var dir := DirAccess.open(CLOTHES_DIR)
	if dir != null:
		for file in dir.get_files():
			if file.ends_with(".glb"):
				pieces.append(CLOTHES_DIR + "/" + file)
	assert_gt(pieces.size(), 0, "there are clothing pieces in %s" % CLOTHES_DIR)
	for path: String in pieces:
		var piece := _load(path)
		if piece == null:
			continue
		var extras := {}
		for node: Node in [piece] + piece.find_children("*", "", true, false):
			var found = node.get_meta("extras", {})
			if found is Dictionary and found.has("slot"):
				extras = found
		assert_true(extras.has("slot"), "%s has glTF extras naming its slot" % path.get_file())
		if not extras.has("slot"):
			continue
		assert_eq(str(piece.get_meta("slot", "")), str(extras["slot"]), "%s's slot is lifted from its extras" % path.get_file())
		if extras.has("body_type"):
			assert_eq(str(piece.get_meta("body_type", "")), str(extras["body_type"]), "%s's body type is lifted from its extras" % path.get_file())
		if extras.has("covers"):
			var covers = piece.get_meta("covers", null)
			assert_true(covers is Array, "%s's covers is a list" % path.get_file())
			if covers is Array:
				assert_eq(Array(covers).map(func(c): return str(c)), Array(extras["covers"]).map(func(c): return str(c)),
					"%s's covered regions are lifted from its extras" % path.get_file())


# Given the test piece test_sleeves.glb, when it's loaded, then its slot is `top`, its body type is
# `male_average`, it covers `upper_arms`, and its mesh is skinned to bones of the male_average shared
# skeleton (each bind naming one of its bones).
func test_the_test_sleeves_declare_themselves():
	var sleeves := _load(SLEEVES_PATH)
	var types = load(BODY_TYPES_PATH) if ResourceLoader.exists(BODY_TYPES_PATH) else null
	assert_not_null(types, "the body types load")
	if sleeves == null or types == null:
		return
	assert_eq(str(sleeves.get_meta("slot", "")), "top", "the test sleeves fill the top slot")
	assert_eq(str(sleeves.get_meta("body_type", "")), "male_average", "the test sleeves are made for male_average")
	var covers = sleeves.get_meta("covers", [])
	assert_eq(Array(covers).map(func(c): return str(c)) if covers is Array else [], ["upper_arms"], "the test sleeves cover his upper arms")
	var model := _load(types.model("male_average"))
	if model == null:
		return
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var meshes := sleeves.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0, "the test sleeves have a mesh")
	for mi: MeshInstance3D in meshes:
		assert_not_null(mi.skin, "%s is skinned" % mi.name)
		if mi.skin == null:
			continue
		assert_gt(mi.skin.get_bind_count(), 0, "%s has binds" % mi.name)
		for b in mi.skin.get_bind_count():
			var name := mi.skin.get_bind_name(b)
			assert_ne(skeleton.find_bone(name), -1, "the sleeves' bone %s is one of the male_average skeleton's" % name)


# Given the test piece over character.glb at rest, when they're compared, then it sits over his upper
# arms: at least 90% of its vertices are within 3 cm of his body_upper_arms region, and it has at most
# 2,000 triangles.
func test_the_test_sleeves_sit_over_his_upper_arms():
	var sleeves := _load(SLEEVES_PATH)
	var character := _load("res://assets/models/characters/character.glb")
	if sleeves == null or character == null:
		return
	var skeleton: Skeleton3D = character.find_children("*", "Skeleton3D", true, false)[0]
	var arms := character.find_child("body_upper_arms", true, false) as MeshInstance3D
	assert_not_null(arms, "he has the body_upper_arms region")
	var meshes := sleeves.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0, "the test sleeves have a mesh")
	if arms == null or meshes.is_empty():
		return
	var cells := {}
	var skin := _drawn(arms, skeleton)
	for i in skin.size():
		var c := _cell(skin[i])
		if not cells.has(c):
			cells[c] = PackedInt32Array()
		cells[c].append(i)
	var triangles := 0
	var near := 0
	var count := 0
	for mi: MeshInstance3D in meshes:
		for s in mi.mesh.get_surface_count():
			var indices = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
			triangles += (indices.size() if indices != null and not indices.is_empty() else mi.mesh.surface_get_array_len(s)) / 3
		if mi.skin == null:
			continue
		for p: Vector3 in _drawn(mi, skeleton):
			count += 1
			var c := _cell(p)
			var found := false
			for x in range(-1, 2):
				for y in range(-1, 2):
					for z in range(-1, 2):
						for j: int in cells.get(c + Vector3i(x, y, z), PackedInt32Array()):
							if skin[j].distance_to(p) <= 0.03:
								found = true
								break
			if found:
				near += 1
	assert_gt(count, 0, "the test sleeves have vertices")
	var share := float(near) / maxi(1, count)
	assert_gte(share, 0.9, "at least 90%% of the sleeves are within 3 cm of his upper arms (%.1f%%)" % (share * 100.0))
	assert_lte(triangles, 2000, "the test sleeves are a small placeholder (%d triangles)" % triangles)
