extends Node3D
## The combat screen: the detective and the cultist squared off in a small, dark arena. No combat
## rules yet; for now it just stages the standoff, both combatants idling.


func _ready() -> void:
	for combatant: Node in [$Detective, $Cultist]:
		var player := combatant.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		player.play("idle")
