extends Node
## Runs turn-based combat in the overworld, tabletop style: everyone rolls initiative (a d20 plus
## their bonus), turns go from the highest total to the lowest, and the first turn starts at once.
## On their turn a combatant has their movement (metres), one action and one bonus action. Ending
## the turn (End Turn, Space, on the detective's turn) passes play on; after the last combatant a
## new round begins. On his turn the detective moves by clicking the floor: the path under the mouse
## is previewed with its length, and a click walks him along it if it fits his movement left.
## Clicking an enemy within reach (1.5 m between their bodies' edges) spends his action on an attack:
## a d20 plus attack bonus against Armour Class, damage dice on a hit, a natural 20 a critical hit
## (double dice) and a natural 1 always a miss.
## A hit takes its damage off the target's hit points; at 0 a combatant is defeated and leaves the turn
## order. Combat ends in victory when no enemy is left standing, or in defeat if the detective falls.
## Combatants keep their stats as node metadata (`initiative_bonus`, `movement`, `attack_bonus`,
## `armour_class`, `damage_dice`, `damage_die`, `damage_bonus`, `body_radius`, `max_hit_points`).

## Emitted when a combatant's turn begins.
signal turn_started(combatant: Node3D)
## Emitted when an attack is resolved, with what `attack` returns.
signal attack_resolved(result: Dictionary)
## Emitted when a combatant's hit points change, with the new value.
signal hit_points_changed(combatant: Node3D, hit_points: int)
## Emitted when combat ends with every enemy defeated.
signal victory
## Emitted when combat ends with the detective defeated.
signal defeat

## How far an attack reaches, between the attacker's and the target's bodies' edges (metres).
const ATTACK_REACH := 1.5
## How tall a combatant's body is, for clicking on it (metres).
const BODY_HEIGHT := 1.8

## The detective's combatant (his Player body). He wins initiative ties that nothing else breaks.
@export var detective_path: NodePath
## Draws the previewed path (a MeshInstance3D, with a Label3D under it for the length).
@export var path_preview_node: NodePath
## The garage's NavigationRegion3D, whose map paths are found on.
@export var navigation_node: NodePath
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

## Each combatant's current hit points, and who has been defeated (at 0).
var hit_points := {}
var defeated: Array[Node3D] = []

## The path previewed under the mouse on the detective's turn: its points (from him), length in
## metres, and whether it fits his movement left.
var preview_path := PackedVector3Array()
var preview_length := 0.0
var preview_reachable := false

@onready var detective := get_node_or_null(detective_path) as Node3D
@onready var _preview := get_node_or_null(path_preview_node) as MeshInstance3D
@onready var _navigation := get_node_or_null(navigation_node) as NavigationRegion3D


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
		if _enemy_under(event.position) != null:
			_hide_preview()
		else:
			_update_preview(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# A click on an enemy is an attack (if allowed), never a move.
		var enemy := _enemy_under(event.position)
		if enemy != null:
			if can_attack(detective, enemy):
				attack(detective, enemy)
			return
		_update_preview(event.position)
		if preview_reachable and preview_path.size() > 1:
			movement_left -= preview_length
			detective.walk_path(preview_path)
			_hide_preview()


## Only on his own turn, and not while he's already walking somewhere.
func _detective_can_move() -> bool:
	return running and active == detective and detective != null and not detective.is_walking_path()


## The enemy combatant under `screen_position`, or null: the ray from the camera passes through its
## body, taken as an upright cylinder of its `body_radius`, from the floor to `BODY_HEIGHT`.
func _enemy_under(screen_position: Vector2) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	for enemy in combatants:
		if enemy == detective:
			continue
		var radius: float = enemy.get_meta("body_radius", 0.0)
		# Where the ray, seen from above, is within `radius` of the enemy's centre...
		var o := Vector2(origin.x - enemy.global_position.x, origin.z - enemy.global_position.z)
		var d := Vector2(direction.x, direction.z)
		var a := d.length_squared()
		var b := 2.0 * o.dot(d)
		var c := o.length_squared() - radius * radius
		var discriminant := b * b - 4.0 * a * c
		if a < 0.000001 or discriminant < 0.0:
			continue
		var t_in := (-b - sqrt(discriminant)) / (2.0 * a)
		var t_out := (-b + sqrt(discriminant)) / (2.0 * a)
		# ...and at a height between the floor and the top of its body.
		var y_in := origin.y + direction.y * t_in - enemy.global_position.y
		var y_out := origin.y + direction.y * t_out - enemy.global_position.y
		if maxf(y_in, y_out) >= 0.0 and minf(y_in, y_out) <= BODY_HEIGHT:
			return enemy
	return null


## Whether `attacker` may attack `target` now: on their turn, with their action, within reach.
func can_attack(attacker: Node3D, target: Node3D) -> bool:
	return running and active == attacker and actions_left > 0 and target != attacker and not is_defeated(target) \
		and _edge_gap(attacker, target) <= ATTACK_REACH


## The distance between two combatants' bodies, edge to edge, seen from above.
func _edge_gap(a: Node3D, b: Node3D) -> float:
	var centres := Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()
	return centres - float(a.get_meta("body_radius", 0.0)) - float(b.get_meta("body_radius", 0.0))


## Resolves one attack by `attacker` on `target` with the seeded dice, spending the attacker's action
## if it's their turn. Returns (and emits with `attack_resolved`) what happened: `attacker`,
## `target`, `roll` (the d20), `total`, `hit`, `critical`, `damage_rolls` and `damage`.
func attack(attacker: Node3D, target: Node3D) -> Dictionary:
	if active == attacker:
		actions_left = maxi(actions_left - 1, 0)
	var roll := roll_d20()
	var total := roll + attack_bonus(attacker)
	var critical := roll == 20
	var hit := critical or (roll != 1 and total >= armour_class(target))
	var damage_rolls: Array[int] = []
	var damage := 0
	if hit:
		var dice: int = attacker.get_meta("damage_dice", 1) * (2 if critical else 1)
		for i in dice:
			damage_rolls.append(rng.randi_range(1, attacker.get_meta("damage_die", 4)))
		damage = damage_rolls.reduce(func(sum: int, die: int) -> int: return sum + die, 0) + int(attacker.get_meta("damage_bonus", 0))
	var result := {
		"attacker": attacker, "target": target, "roll": roll, "total": total, "hit": hit,
		"critical": critical, "damage_rolls": damage_rolls, "damage": damage,
	}
	attack_resolved.emit(result)
	if hit:
		apply_damage(target, damage)
	return result


func max_hit_points(combatant: Node) -> int:
	return combatant.get_meta("max_hit_points", 1)


func is_defeated(combatant: Node3D) -> bool:
	return defeated.has(combatant)


## Takes `amount` off `target`'s hit points (never below 0). At 0 they are defeated, which can end
## combat.
func apply_damage(target: Node3D, amount: int) -> void:
	if not hit_points.has(target) or is_defeated(target):
		return
	hit_points[target] = maxi(hit_points[target] - amount, 0)
	hit_points_changed.emit(target, hit_points[target])
	if hit_points[target] == 0:
		_defeat(target)


func _defeat(combatant: Node3D) -> void:
	defeated.append(combatant)
	turn_order.erase(combatant)
	if combatant == detective:
		_end_combat(defeat)
	elif combatants.all(func(c: Node3D) -> bool: return c == detective or is_defeated(c)):
		_end_combat(victory)


func _end_combat(outcome: Signal) -> void:
	running = false
	_hide_preview()
	outcome.emit()


func attack_bonus(combatant: Node) -> int:
	return combatant.get_meta("attack_bonus", 0)


func armour_class(combatant: Node) -> int:
	return combatant.get_meta("armour_class", 10)


## Previews the path from the detective to the floor point under `screen_position`.
func _update_preview(screen_position: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	var origin := camera.project_ray_origin(screen_position)
	var normal := camera.project_ray_normal(screen_position)
	if absf(normal.y) < 0.0001:
		_hide_preview()
		return
	var point := origin - normal * (origin.y / normal.y)  # where the ray meets the floor (y = 0)
	var map := _navigation.get_navigation_map() if _navigation != null else detective.get_world_3d().navigation_map
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
	hit_points = {}
	defeated.clear()
	for combatant in combatants:
		rolls[combatant] = roll_d20()
		hit_points[combatant] = max_hit_points(combatant)
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
