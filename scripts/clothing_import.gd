@tool
extends EditorScenePostImport
## Import script for the clothing pieces (assets/models/clothes/*.glb): each glb carries, as glTF extras
## on its mesh (which Godot imports as an `extras` dictionary), the slot it fills (`top`, `bottom` or
## `feet`), the body type it was made for (`body_type`, #150) and the body regions it covers
## (`covers`, #151-#152). This lifts them to metadata on the piece's root, where game code reads them.


func _post_import(scene: Node) -> Object:
	for node: Node in [scene] + scene.find_children("*", "", true, false):
		var extras = node.get_meta("extras", {})
		if not extras is Dictionary:
			continue
		if extras.has("slot"):
			scene.set_meta("slot", str(extras["slot"]))
		if extras.has("body_type"):
			scene.set_meta("body_type", str(extras["body_type"]))
		if extras.has("covers"):
			var covers := []
			for region in (extras["covers"] if extras["covers"] is Array else [extras["covers"]]):
				covers.append(str(region))
			scene.set_meta("covers", covers)
	return scene
