extends Node3D
## The game's root scene: the garage, with the detective and a cultist standing in it.


func _ready() -> void:
	for character: Node in [$Detective, $Cultist]:
		var player := character.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		player.play("idle")
	# BulbLight sits inside the bulb mesh: if the bulb (or its cord) cast shadows, they would
	# block the light completely.
	for mesh_name in ["bulb", "bulb_cord"]:
		var mesh := $Garage.find_child(mesh_name, true, false) as GeometryInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	print("SMOKE_MARKER: main scene ready")
