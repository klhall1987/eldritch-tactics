extends RefCounted
## Cuts on a combatant (#93): a dark red gash opened on the torso where a blade lands, on the side
## facing the attacker. It is put on the bone that moves that bit of skin, so it stays on him as he
## moves. Each wound is a Node3D in the `wounds` group, under the wounded combatant.

const GROUP := &"wounds"
const LENGTH := 0.11
const SPACING := 0.06  # cuts stay at least this far apart
const FLESH := Color(0.55, 0.06, 0.05)  # the cut's lips
const DEPTH := Color(0.3, 0.01, 0.01)  # inside the cut

## The torso: from the waist bone up to the bone at the neck.
const WAIST_BONE := "spine"
const NECK_BONE := "head"


## Opens a wound on `target`'s torso, on the side facing `attacker`. Returns it, or null if `target`
## has no skinned body to cut.
static func open(target: Node3D, attacker: Node3D, rng: RandomNumberGenerator) -> Node3D:
	var skeleton := _skeleton(target)
	if skeleton == null or skeleton.find_bone(WAIST_BONE) < 0 or skeleton.find_bone(NECK_BONE) < 0:
		return null
	var points := _skin(target, skeleton)
	if points.is_empty():
		return null
	var centre := target.global_position
	var toward := Vector3(attacker.global_position.x - centre.x, 0, attacker.global_position.z - centre.z).normalized()
	var across := toward.cross(Vector3.UP)
	var waist := _bone_position(skeleton, WAIST_BONE).y
	var neck := _bone_position(skeleton, NECK_BONE).y
	var taken := (target.get_tree().get_nodes_in_group(GROUP) as Array).filter(func(w: Node) -> bool: return target.is_ancestor_of(w))
	var best := []
	for attempt in 12:
		# A spot on his front: somewhere up his torso and a little either side of his middle.
		var height := lerpf(waist, neck, rng.randf_range(0.2, 0.75))
		var side := rng.randf_range(-0.09, 0.09)
		var found := _front_point(points, centre, toward, across, height, side)
		if found.is_empty():
			continue
		best = found
		if taken.all(func(w: Node3D) -> bool: return w.global_position.distance_to(found[0]) >= SPACING):
			break
	if best.is_empty():
		return null
	return _place(target, skeleton, best[0], best[1], toward, rng.randf_range(-35.0, 35.0))


## The front-most skin point near (`height`, `side`): [position, bone], or [] if none is there.
static func _front_point(points: Array, centre: Vector3, toward: Vector3, across: Vector3, height: float, side: float) -> Array:
	var best := []
	var best_reach := -INF
	for point: Array in points:
		var at: Vector3 = point[0]
		var offset := at - centre
		if absf(at.y - height) > 0.04 or absf(offset.dot(across) - side) > 0.04:
			continue
		var reach := offset.dot(toward)
		if reach > best_reach:
			best_reach = reach
			best = point
	return best


## The wound node, on `bone`, at `at` (just proud of the skin), facing `toward`, the cut slanted
## `slant` degrees.
static func _place(target: Node3D, skeleton: Skeleton3D, at: Vector3, bone: int, toward: Vector3, slant: float) -> Node3D:
	var attachment := BoneAttachment3D.new()
	attachment.use_external_skeleton = true
	target.add_child(attachment)
	attachment.external_skeleton = attachment.get_path_to(skeleton)
	attachment.bone_idx = bone
	var wound := Node3D.new()
	wound.name = "Wound"
	wound.add_to_group(GROUP)
	var facing := Basis.looking_at(-toward, Vector3.UP).rotated(toward, deg_to_rad(slant))
	var bone_now := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	wound.transform = bone_now.affine_inverse() * Transform3D(facing, at + toward * 0.006)
	attachment.add_child(wound)
	wound.add_child(_gash("Lips", Vector3(LENGTH, 0.022, 0.004), FLESH, 0.0))
	wound.add_child(_gash("Depth", Vector3(LENGTH * 0.85, 0.008, 0.004), DEPTH, 0.002))
	return wound


static func _gash(name: String, size: Vector3, colour: Color, lift: float) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.35
	box.material = material
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = box
	mi.position = Vector3(0, 0, lift)
	return mi


## Every vertex of `target`'s skinned meshes as it's drawn now: [[position, bone it follows most], ...].
static func _skin(target: Node3D, skeleton: Skeleton3D) -> Array:
	var points := []
	for mi: MeshInstance3D in target.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.get_node_or_null(mi.skeleton) != skeleton:
			continue
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null or vertices.is_empty():
				continue
			var per_vertex: int = weights.size() / vertices.size()
			for i in vertices.size():
				var at := Vector3.ZERO
				var main_bone := -1
				var main_weight := 0.0
				for k in per_vertex:
					var w: float = weights[i * per_vertex + k]
					if w <= 0.0:
						continue
					var bind: int = bones[i * per_vertex + k]
					var bone := mi.skin.get_bind_bone(bind)
					if mi.skin.get_bind_name(bind) != StringName():
						bone = skeleton.find_bone(mi.skin.get_bind_name(bind))
					at += (skeleton.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind) * vertices[i]) * w
					if w > main_weight:
						main_weight = w
						main_bone = bone
				if main_bone >= 0:
					points.append([skeleton.global_transform * at, main_bone])
	return points


static func _skeleton(target: Node) -> Skeleton3D:
	var skeletons := target.find_children("*", "Skeleton3D", true, false)
	return skeletons[0] if not skeletons.is_empty() else null


static func _bone_position(skeleton: Skeleton3D, name: String) -> Vector3:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(name))).origin
