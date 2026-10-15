extends Node3D
## The game's root scene: the garage, with the detective and a cultist standing in it.


func _ready() -> void:
	for character: Node in [$Detective, $Cultist]:
		var player := character.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		player.play("idle")
	print("SMOKE_MARKER: main scene ready")
