@tool
extends EditorScenePostImport
## Import script for the player character (assets/models/characters/character.glb): the owner's Meshy
## model, copied into the project exactly as Meshy delivered it (#142). The glb stays unchanged; this
## fits it to the game as it's imported. It drops Meshy's stray `Icosphere`, turns off the emission and
## metal on its material (so he's lit by the scene, not glowing), folds the 0.01 scale on
## Meshy's armature into the skeleton (its bones are in centimetres, cancelled out by its bind poses, so
## he's drawn the same but everything under him now measures in metres), names Meshy's clips for what
## the game plays (the stances and the walk loop), and cuts `hit` from the start of Block1, as his hands
## come up to cover, since Meshy made no hit reaction.

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
