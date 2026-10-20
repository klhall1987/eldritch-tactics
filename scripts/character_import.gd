@tool
extends EditorScenePostImport
## Import script for the player character (assets/models/characters/character.glb): the owner's Meshy
## model, copied into the project exactly as Meshy delivered it (#142). The glb stays unchanged; this
## fits it to the game as it's imported. It drops Meshy's stray `Icosphere`, turns off the emission and
## metal on its material (so he's lit by the scene, not glowing), folds the 0.01 scale on
## Meshy's armature into the skeleton (its bones are in centimetres, cancelled out by its bind poses, so
## he's drawn the same but everything under him now measures in metres), names Meshy's clips for what
## the game plays (the stances and the walk loop), and cuts `hit` from the start of Block1, as his hands
## come up to cover, since Meshy made no hit reaction. It names his body type (#150) and splits his body
## into the regions clothes can hide (#151).

## Game clip -> [Meshy's clip, loops].
const CLIPS := {
	"idle": ["Idle_02", true],
	"walk": ["Walking", true],
	"combat_idle": ["Block1", true],
	"attack": ["Heavy_Hammer_Swing", false],
}
## `hit` is the first HIT_LENGTH seconds of HIT_FROM, played once.
const HIT_FROM := "Block1"
const HIT_LENGTH := 0.6
## His body type (#150, scripts/body_types.gd).
const BODY_TYPE := "male_average"
## His body's regions (#151): region -> the bones its triangles follow. The Outfit hides a region while a
## worn piece covers it (#153).
const REGIONS := {
	"head": ["mixamorig_Neck", "mixamorig_Head", "headfront"],
	"torso": ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_LeftShoulder", "mixamorig_RightShoulder"],
	"hips": ["mixamorig_Hips"],
	"upper_arms": ["mixamorig_LeftArm", "mixamorig_RightArm"],
	"forearms": ["mixamorig_LeftForeArm", "mixamorig_RightForeArm"],
	"hands": ["mixamorig_LeftHand", "mixamorig_RightHand"],
	"thighs": ["mixamorig_LeftUpLeg", "mixamorig_RightUpLeg"],
	"calves": ["mixamorig_LeftLeg", "mixamorig_RightLeg"],
	"feet": ["mixamorig_LeftFoot", "mixamorig_RightFoot", "mixamorig_LeftToeBase", "mixamorig_RightToeBase"],
}


func _post_import(scene: Node) -> Object:
	for node: Node in scene.find_children("Icosphere*", "", true, false):
		node.get_parent().remove_child(node)
		node.free()
	for skeleton: Skeleton3D in scene.find_children("*", "Skeleton3D", true, false):
		_unscale(scene, skeleton)
	# Meshy's material also feeds its colour texture into emission and is fully metallic, so he'd glow
	# in the dark garage rather than be lit by it: he's lit like everyone else (the texture is untouched).
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var material := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if material != null:
				material.emission_enabled = false
				material.metallic = 0.0
	scene.set_meta("body_type", BODY_TYPE)
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if mi.skin != null:
			_split_into_regions(scene, mi)
	for player: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
		var library := player.get_animation_library(&"")
		if library == null:
			continue
		if library.has_animation(HIT_FROM):
			var hit: Animation = library.get_animation(HIT_FROM).duplicate(true)
			hit.length = HIT_LENGTH
			hit.loop_mode = Animation.LOOP_NONE
			library.add_animation(&"hit", hit)
		for clip: String in CLIPS:
			var meshy: String = CLIPS[clip][0]
			if not library.has_animation(meshy):
				continue
			library.rename_animation(meshy, clip)
			library.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if CLIPS[clip][1] else Animation.LOOP_NONE
	return scene


## Folds the scale on `skeleton` and the nodes above it (Meshy's 0.01) into the skeleton itself: its
## bones' rest and pose positions, its meshes' bind poses and every animated bone position are scaled
## by it, and those nodes' scale is set to 1. He's drawn exactly as before.
func _unscale(scene: Node, skeleton: Skeleton3D) -> void:
	var chain: Array[Node3D] = []
	var to_scene := Transform3D()
	var node: Node = skeleton
	while node != scene and node is Node3D:
		chain.append(node)
		to_scene = (node as Node3D).transform * to_scene
		node = node.get_parent()
	var k := to_scene.basis.get_scale().x
	if is_equal_approx(k, 1.0):
		return
	for n: Node3D in chain:
		n.basis = n.basis.orthonormalized()
		n.position *= k
	for b in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(b)
		rest.origin *= k
		skeleton.set_bone_rest(b, rest)
		skeleton.set_bone_pose_position(b, skeleton.get_bone_pose_position(b) * k)
	var scaling := Transform3D(Basis.from_scale(Vector3.ONE * k), Vector3.ZERO)
	for mi: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null:
			continue
		var skin: Skin = mi.skin.duplicate()
		for i in skin.get_bind_count():
			skin.set_bind_pose(i, scaling * skin.get_bind_pose(i))
		mi.skin = skin
	for player: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
		for library_name in player.get_animation_library_list():
			var library := player.get_animation_library(library_name)
			for clip in library.get_animation_list():
				var animation := library.get_animation(clip)
				for t in animation.get_track_count():
					if animation.track_get_type(t) != Animation.TYPE_POSITION_3D:
						continue
					if skeleton.find_bone(animation.track_get_path(t).get_concatenated_subnames()) < 0:
						continue
					for key in animation.track_get_key_count(t):
						animation.track_set_key_value(t, key, animation.track_get_key_value(t, key) * k)


## Replaces his body mesh `mi` with one mesh per region (#151), `body_<region>`, each skinned to his
## skeleton like `mi` was: each triangle goes to the region of the bone most of its vertices follow
## most. Every vertex and the material stay as they were; only the triangles are sorted.
func _split_into_regions(scene: Node, mi: MeshInstance3D) -> void:
	var region_of_bind := {}  # bind index -> region
	for b in mi.skin.get_bind_count():
		for region: String in REGIONS:
			if str(mi.skin.get_bind_name(b)) in REGIONS[region]:
				region_of_bind[b] = region
	var meshes := {}  # region -> ArrayMesh
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var material := mi.get_active_material(s)
		var flags: int = mi.mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per_vertex: int = weights.size() / vertices.size()
		var strongest := PackedInt32Array()  # vertex -> the bind it follows most
		strongest.resize(vertices.size())
		for i in vertices.size():
			var best := 0
			for k in per_vertex:
				if weights[i * per_vertex + k] > weights[i * per_vertex + best]:
					best = k
			strongest[i] = bones[i * per_vertex + best]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var triangles := {}  # region -> PackedInt32Array of the surface's vertex indices
		for t in range(0, indices.size(), 3):
			var votes := {}
			for k in 3:
				var region: String = region_of_bind.get(strongest[indices[t + k]], "torso")
				votes[region] = votes.get(region, 0) + 1
			var region: String = votes.keys()[0]
			for candidate: String in votes:
				if votes[candidate] > votes[region]:
					region = candidate
			if not triangles.has(region):
				triangles[region] = PackedInt32Array()
			triangles[region].append_array([indices[t], indices[t + 1], indices[t + 2]])
		for region: String in triangles:
			if not meshes.has(region):
				meshes[region] = ArrayMesh.new()
			_add_part(meshes[region], arrays, triangles[region], material, flags)
	for region: String in REGIONS:
		if not meshes.has(region):
			continue
		var part := MeshInstance3D.new()
		part.name = "body_" + region
		part.mesh = meshes[region]
		part.skin = mi.skin
		part.transform = mi.transform
		mi.get_parent().add_child(part)
		part.owner = scene
		part.skeleton = part.get_path_to(mi.get_node(mi.skeleton))
	mi.get_parent().remove_child(mi)
	mi.free()


## Adds the triangles `triangles` (indices into `arrays`' vertices) to `mesh` as a surface of their own,
## carrying over only the vertices they use, with every per-vertex array.
func _add_part(mesh: ArrayMesh, arrays: Array, triangles: PackedInt32Array, material: Material, flags: int) -> void:
	var vertex_count: int = arrays[Mesh.ARRAY_VERTEX].size()
	var remap := PackedInt32Array()
	remap.resize(vertex_count)
	remap.fill(-1)
	var used := PackedInt32Array()
	for i in triangles:
		if remap[i] < 0:
			remap[i] = used.size()
			used.append(i)
	var part := []
	part.resize(Mesh.ARRAY_MAX)
	for a in Mesh.ARRAY_MAX:
		var source = arrays[a]
		if source == null or a == Mesh.ARRAY_INDEX:
			continue
		var stride: int = source.size() / vertex_count
		var copy = source.duplicate()
		copy.resize(used.size() * stride)
		for n in used.size():
			for k in stride:
				copy[n * stride + k] = source[used[n] * stride + k]
		part[a] = copy
	var indices := PackedInt32Array()
	indices.resize(triangles.size())
	for n in triangles.size():
		indices[n] = remap[triangles[n]]
	part[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part, [], {}, flags)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)
