extends Node3D
## The game's root scene: the garage, with the detective (moved by Player) and a cultist in it.
## Walking the detective into an enemy (moving towards it inside its touch area) starts an
## encounter, and turn-based combat begins right there (CombatController).

## Emitted once, when the detective first bumps into an enemy.
signal encounter_started(enemy: Node3D)

var _encounter_running := false
var _touch_areas := {}  # enemy -> its touch Area3D


func _ready() -> void:
	for character: Node in [$Player/Detective, $Cultist]:
		var player := character.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		player.play("idle")
	# BulbLight sits inside the bulb mesh: if the bulb (or its cord) cast shadows, they would
	# block the light completely.
	for mesh_name in ["bulb", "bulb_cord"]:
		var mesh := $Garage.find_child(mesh_name, true, false) as GeometryInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if is_ancestor_of(enemy):
			_touch_areas[enemy] = enemy.find_children("*", "Area3D", true, false)[0]
	print("SMOKE_MARKER: main scene ready")


func _physics_process(_delta: float) -> void:
	if _encounter_running:
		return
	var player := $Player as CharacterBody3D
	for enemy: Node3D in _touch_areas:
		var touch := _touch_areas[enemy] as Area3D
		if touch.overlaps_body(player) and _walking_towards(player, enemy):
			_start_encounter(enemy)
			return


## A bump is walking into the enemy: being in its touch area while walking away (or standing
## still) doesn't count.
func _walking_towards(player: CharacterBody3D, enemy: Node3D) -> bool:
	var towards := enemy.global_position - player.global_position
	towards.y = 0.0
	var walking := Vector3(player.velocity.x, 0.0, player.velocity.z)
	return walking.length() > 0.1 and walking.dot(towards) > 0.0


func _start_encounter(enemy: Node3D) -> void:
	_encounter_running = true
	$Player.controllable = false
	encounter_started.emit(enemy)
	$CombatController.start_combat([$Player, enemy])
