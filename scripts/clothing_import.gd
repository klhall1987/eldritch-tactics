@tool
extends EditorScenePostImport
## Import script for the clothing pieces (assets/models/clothes/*.glb): each glb carries the slot it
## fills (`top`, `bottom` or `feet`) as glTF extras on its mesh, which Godot imports as an `extras`
## dictionary. This lifts it to `slot` metadata on the piece's root, where game code reads it.


func _post_import(scene: Node) -> Object:
	for node: Node in [scene] + scene.find_children("*", "", true, false):
		var extras = node.get_meta("extras", {})
		if extras is Dictionary and extras.has("slot"):
			scene.set_meta("slot", str(extras["slot"]))
	return scene
