extends Node
## Runs turn-based combat in the overworld, tabletop style: everyone rolls initiative (a d20 plus
## their bonus), turns go from the highest total to the lowest, and the first turn starts at once.
## On their turn a combatant has their movement (metres), one action and one bonus action. Ending
## the turn (End Turn, Space, on the detective's turn) passes play on; after the last combatant a
## new round begins. On his turn the detective moves by clicking the floor: the path under the mouse
## is previewed with its length, and a click walks him along it if it fits his movement left.
## Combatants keep their stats as node metadata (`initiative_bonus`, `movement`).

## Emitted when a combatant's turn begins.
signal turn_started(combatant: Node3D)

## The detective's combatant (his Player body). He wins initiative ties that nothing else breaks.
@export var detective_path: NodePath
## Draws the previewed path (a MeshInstance3D, with a Label3D under it for the length).
@export var path_preview_node: NodePath
## Path preview colours, within his movement and beyond it.
@export var reachable_colour := Color(0.95, 0.85, 0.45)
@export var out_of_reach_colour := Color(0.85, 0.2, 0.15)

## Every die comes from here, so seeding it fixes the dice.
var rng := RandomNumberGenerator.new()
var running := false
var combatants: Array[Node3D] = []
## Each combatant's initiative roll (the d20 alone, without their bonus).
var rolls := {}
## Who acts when, first to act first.
var turn_order: Array[Node3D] = []
## The combatant whose turn it is.
var active: Node3D
## The round number, from 1.
var round := 0

## What the active combatant has left this turn.
var movement_left := 0.0
var actions_left := 0
var bonus_actions_left := 0

## The path previewed under the mouse on the detective's turn: its points (from him), length in
## metres, and whether it fits his movement left.
var preview_path := PackedVector3Array()
var preview_length := 0.0
var preview_reachable := false

@onready var detective := get_node_or_null(detective_path) as Node3D
@onready var _preview := get_node_or_null(path_preview_node) as MeshInstance3D


func _ready() -> void:
	rng.randomize()
	if _preview != null:
		_preview.mesh = ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_preview.material_override = material
		_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_preview.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _detective_can_move():
		return
	if event is InputEventMouseMotion:
		_update_preview(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_update_preview(event.position)
		if preview_reachable and preview_path.size() > 1:
			movement_left -= preview_length
			detective.walk_path(preview_path)
			_hide_preview()


## Only on his own turn, and not while he's already walking somewhere.
func _detective_can_move() -> bool:
	return running and active == detective and detective != null and not detective.is_walking_path()


## Previews the path from the detective to the floor point under `screen_position`.
func _update_preview(screen_position: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	var origin := camera.project_ray_origin(screen_position)
	var normal := camera.project_ray_normal(screen_position)
	if absf(normal.y) < 0.0001:
		_hide_preview()
		return
	var point := origin - normal * (origin.y / normal.y)  # where the ray meets the floor (y = 0)
	var map := detective.get_world_3d().navigation_map
	preview_path = NavigationServer3D.map_get_path(map, detective.global_position, point, true)
	preview_length = 0.0
	for i in range(1, preview_path.size()):
		var step := preview_path[i] - preview_path[i - 1]
		preview_length += Vector2(step.x, step.z).length()
	preview_reachable = preview_path.size() > 1 and preview_length <= movement_left
	_draw_preview()


## Draws the previewed path as a flat ribbon just above the floor, with its length at the end.
func _draw_preview() -> void:
	if _preview == null:
		return
	if preview_path.size() < 2:
		_hide_preview()
		return
	var colour := reachable_colour if preview_reachable else out_of_reach_colour
	(_preview.material_override as StandardMaterial3D).albedo_color = colour
	var mesh := _preview.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var lift := Vector3.UP * 0.02
	for i in range(1, preview_path.size()):
		var from := preview_path[i - 1]
		var to := preview_path[i]
		var side := Vector3(to.z - from.z, 0, from.x - to.x).normalized() * 0.03
		for corner in [from - side, from + side, to + side, from - side, to + side, to - side]:
			mesh.surface_add_vertex(Vector3(corner.x, 0, corner.z) + lift)
	mesh.surface_end()
	_preview.global_transform = Transform3D.IDENTITY
	for label: Label3D in _preview.find_children("*", "Label3D", true, false):
		label.text = "%.1f m" % preview_length
		label.modulate = colour
		label.global_position = Vector3(preview_path[-1].x, 0.4, preview_path[-1].z)
	_preview.visible = true


func _hide_preview() -> void:
	preview_path = PackedVector3Array()
	preview_length = 0.0
	preview_reachable = false
	if _preview != null:
		_preview.visible = false


func _physics_process(_delta: float) -> void:
	if running and active == detective and Input.is_action_just_pressed("end_turn"):
		end_turn()


## Starts combat between `fighters`: rolls initiative for each (in the order given), sets the turn
## order and starts the first turn.
func start_combat(fighters: Array) -> void:
	combatants.assign(fighters)
	rolls = {}
	for combatant in combatants:
		rolls[combatant] = roll_d20()
	turn_order.assign(order_by_initiative(rolls))
	running = true
	round = 1
	_start_turn(turn_order[0])


## Ends the active combatant's turn and starts the next one's, beginning a new round after the last.
func end_turn() -> void:
	if not running:
		return
	var next := turn_order.find(active) + 1
	if next >= turn_order.size():
		next = 0
		round += 1
	_start_turn(turn_order[next])


func _start_turn(combatant: Node3D) -> void:
	active = combatant
	movement_left = movement(combatant)
	actions_left = 1
	bonus_actions_left = 1
	_hide_preview()
	turn_started.emit(active)


func roll_d20() -> int:
	return rng.randi_range(1, 20)


func initiative_bonus(combatant: Node) -> int:
	return combatant.get_meta("initiative_bonus", 0)


## A combatant's full movement per turn, in metres.
func movement(combatant: Node) -> float:
	return combatant.get_meta("movement", 0.0)


## The combatants in `initiative_rolls` (combatant -> d20 roll), by roll plus bonus from highest
## to lowest. Ties go to the higher bonus, then to the detective.
func order_by_initiative(initiative_rolls: Dictionary) -> Array:
	var order := initiative_rolls.keys()
	order.sort_custom(func(a: Node, b: Node) -> bool:
		var total_a: int = initiative_rolls[a] + initiative_bonus(a)
		var total_b: int = initiative_rolls[b] + initiative_bonus(b)
		if total_a != total_b:
			return total_a > total_b
		if initiative_bonus(a) != initiative_bonus(b):
			return initiative_bonus(a) > initiative_bonus(b)
		return a == detective and b != detective)
	return order
