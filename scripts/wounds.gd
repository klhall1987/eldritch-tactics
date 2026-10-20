extends RefCounted
## Cuts on a combatant (#93, #112): a dark red gash opened where a blade's slash meets the body, on the
## side facing the attacker, at the height the blade's tip was at when the blow landed (or the nearest
## height the body has), running the way the tip was moving and as long as the stretch of the slash
## that crossed the body. It is put on the bone that moves that bit of skin, so it stays on him as he
## moves. A second cut in the same place goes just below the first. Each wound is a Node3D in the
## `wounds` group, under the wounded combatant, its long axis its +X.

const GROUP := &"wounds"
const SHORTEST := 0.08
const SPACING := 0.06  # cuts stay at least this far apart
const FLESH := Color(0.55, 0.06, 0.05)  # the cut's lips
const DEPTH := Color(0.3, 0.01, 0.01)  # inside the cut
const MOVING_OVER := 0.1  # seconds of the slash that give the way the tip was moving at the blow
const RIBBON_POINTS := 12  # points along a gash, each on the skin


## Cuts `target` where `attacker`'s slash meets it. `slash` is the blade tip's path through the attack
## so far, [[clip seconds, position], ...], ending at the blow; the slash itself is the part from
## `slash_from` seconds on. Returns the wound, or null if `target` has no skinned body to cut.
static func cut(target: Node3D, attacker: Node3D, slash: Array, slash_from: float) -> Node3D:
	var skeleton := _skeleton(target)
	if skeleton == null or slash.size() < 2:
		return null
	var points := _skin(target, skeleton)
	if points.is_empty():
		return null
	var centre := target.global_position
	var toward := Vector3(attacker.global_position.x - centre.x, 0, attacker.global_position.z - centre.z).normalized()
	var across := toward.cross(Vector3.UP).normalized()
	# Its body, legs aside, seen from him: how high and how wide it is.
	var body := points.filter(func(p: Array) -> bool: return not skeleton.get_bone_name(p[1]).begins_with("leg"))
	var low := INF
	var high := -INF
	var left := INF
	var right := -INF
	for point: Array in points:
		if skeleton.get_bone_name(point[1]).begins_with("leg"):
			continue
		var at: Vector3 = point[0]
		low = minf(low, at.y)
		high = maxf(high, at.y)
		left = minf(left, at.dot(across))
		right = maxf(right, at.dot(across))
	# The blow: where the tip was, and the way it was moving.
	var tip: Vector3 = slash[-1][1]
	var earlier: Vector3 = slash[0][1]
	for i in range(slash.size() - 1, -1, -1):
		if float(slash[-1][0]) - float(slash[i][0]) >= MOVING_OVER:
			earlier = slash[i][1]
			break
	var moving := Vector2((tip - earlier).dot(across), tip.y - earlier.y)
	if moving.length() < 1e-4:
		moving = Vector2(1, 0)
	# The stretch of the slash that crossed its body (seen from him): how long, and where across.
	var swept := 0.0
	var crossed_lo := INF
	var crossed_hi := -INF
	var path := slash.filter(func(p: Array) -> bool: return float(p[0]) >= slash_from)
	for i in path.size() - 1:
		var a := Vector2((path[i][1] as Vector3).dot(across), (path[i][1] as Vector3).y)
		var b := Vector2((path[i + 1][1] as Vector3).dot(across), (path[i + 1][1] as Vector3).y)
		if absf(b.x - a.x) < 1e-6:
			continue
		var t0 := clampf((left - a.x) / (b.x - a.x), 0.0, 1.0)
		var t1 := clampf((right - a.x) / (b.x - a.x), 0.0, 1.0)
		if absf(t1 - t0) < 1e-6:
			continue
		swept += a.distance_to(b) * absf(t1 - t0)
		crossed_lo = minf(crossed_lo, lerpf(a.x, b.x, minf(t0, t1)))
		crossed_hi = maxf(crossed_hi, lerpf(a.x, b.x, maxf(t0, t1)))
	var side := (crossed_lo + crossed_hi) / 2.0 if swept > 0.0 else tip.dot(across)
	side = clampf(side, left, right) - centre.dot(across)
	var height := clampf(tip.y, low, high)
	# A second cut in the same place steps just below the last.
	var taken := (target.get_tree().get_nodes_in_group(GROUP) as Array).filter(func(w: Node) -> bool: return target.is_ancestor_of(w))
	var found := []
	for step in 6:
		found = _front_point(points, centre, toward, across, height - step * SPACING * 1.2, side)
		if found.is_empty() or taken.all(func(w: Node3D) -> bool: return w.global_position.distance_to(found[0]) >= SPACING):
			break
	if found.is_empty():
		found = _front_point(points, centre, toward, across, height, side)
	if found.is_empty():
		return null
	var along := (across * moving.x + Vector3.UP * moving.y).normalized()
	var length := maxf(swept, SHORTEST)
	var wound := _place(target, skeleton, found[0], found[1], toward, along)
	# The gash follows its skin along the cut, rather than standing off a curved body as a flat bar.
	var x := wound.global_basis.x.normalized()
	var to_wound := wound.global_transform.affine_inverse()
	var ribbon := PackedVector3Array()
	for i in RIBBON_POINTS:
		var on_line: Vector3 = found[0] + x * (float(i) / (RIBBON_POINTS - 1) - 0.5) * length
		if on_line.dot(across) < left or on_line.dot(across) > right:
			continue  # past the edge of its body
		var skin := _front_point(body, centre, toward, across, on_line.y, (on_line - centre).dot(across))
		var surface: Vector3 = skin[0] if not skin.is_empty() else on_line
		# Along the line exactly, out from the skin by where the skin is.
		ribbon.append(to_wound * (on_line + toward * ((surface - on_line).dot(toward) + 0.006)))
	# The slash only grazed its edge (what's left of the line on its body is shorter than SHORTEST): a
	# short straight cut there.
	if ribbon.size() < 2 or ribbon[-1].distance_to(ribbon[0]) < SHORTEST:
		ribbon = PackedVector3Array([Vector3(-SHORTEST / 2.0, 0, 0), Vector3(SHORTEST / 2.0, 0, 0)])
	wound.add_child(_gash("Lips", ribbon, 0.022, FLESH, 0.0))
	wound.add_child(_gash("Depth", _inset(ribbon, 0.85), 0.008, DEPTH, 0.002))
	return wound


## The front-most skin point near (`height`, `side`): [position, bone], or [] if none is there.
static func _front_point(points: Array, centre: Vector3, toward: Vector3, across: Vector3, height: float, side: float) -> Array:
	for reach_out in [0.04, 0.08, 0.16]:
		var best := []
		var best_reach := -INF
		for point: Array in points:
			var at: Vector3 = point[0]
			var offset := at - centre
			if absf(at.y - height) > reach_out or absf(offset.dot(across) - side) > reach_out:
				continue
			var reach := offset.dot(toward)
			if reach > best_reach:
				best_reach = reach
				best = point
		if not best.is_empty():
			return best
	return []


## The wound node, on `bone`, at `at` (just proud of the skin), facing `toward`, its long axis (+X)
## along `along`; its gash is added by the caller.
static func _place(target: Node3D, skeleton: Skeleton3D, at: Vector3, bone: int, toward: Vector3, along: Vector3) -> Node3D:
	var attachment := BoneAttachment3D.new()
	attachment.use_external_skeleton = true
	target.add_child(attachment)
	attachment.external_skeleton = attachment.get_path_to(skeleton)
	attachment.bone_idx = bone
	var wound := Node3D.new()
	wound.name = "Wound"
	wound.add_to_group(GROUP)
	var x := (along - toward * along.dot(toward)).normalized()
	var facing := Basis(x, toward.cross(x), toward)
	var bone_now := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	wound.transform = bone_now.affine_inverse() * Transform3D(facing, at + toward * 0.006)
	attachment.add_child(wound)
	return wound


## A strip `width` wide through `line` (points in the wound's space, along its +X), facing its +Z,
## lifted `lift` towards the attacker.
static func _gash(name: String, line: PackedVector3Array, width: float, colour: Color, lift: float) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in line.size():
		var at := line[i] + Vector3(0, 0, lift)
		vertices.append(at + Vector3(0, width / 2.0, 0))
		vertices.append(at - Vector3(0, width / 2.0, 0))
		if i > 0:
			var a := (i - 1) * 2
			indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.35
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	return mi


## The middle `share` of `line`.
static func _inset(line: PackedVector3Array, share: float) -> PackedVector3Array:
	var trim := int(round(line.size() * (1.0 - share) / 2.0))
	return line.slice(trim, line.size() - trim) if line.size() - 2 * trim >= 2 else line


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
