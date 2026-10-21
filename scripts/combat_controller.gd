extends Node
## Runs turn-based combat in the overworld, tabletop style: everyone rolls initiative (a d20 plus
## their bonus), turns go from the highest total to the lowest, and the first turn starts at once.
## On their turn a combatant has their movement (metres), one action and one bonus action. Ending
## the turn (End Turn, Space, on the player character's turn) passes play on; after the last combatant a
## new round begins. On his turn the player character moves by clicking the floor: the path under the mouse
## is previewed with its length, and a click walks him along it if it fits his movement left.
## Clicking an enemy within reach (1.5 m between their bodies' edges) spends his action on an attack:
## a pool of d6 (#120): each 4+ a success, a pair of 6s four (a critical), a hit when the successes reach
## the target's defence, and damage of the weapon's plus the successes beyond it.
## A hit takes its damage off the target's hit points; at 0 a combatant is defeated and leaves the turn
## order. Combat ends in victory when no enemy is left standing, or in defeat if the player character falls.
## Enemies play their own turns: after a short pause an enemy shambles along a path towards the
## player character (up to its movement, stopping at reach), attacks him if it can, then ends its turn.
## Combatants keep their stats as node metadata (`initiative_pool`, `movement`, `attack_pool`,
## `defence`, `weapon_damage`, `body_radius`, `max_hit_points`).

## Emitted when a combatant's turn begins.
## Emitted when combat starts, once initiative is rolled and the turn order set (before the first turn).
signal combat_started
signal turn_started(combatant: Node3D)
## Emitted when an attack is resolved, with what `attack` returns.
signal attack_resolved(result: Dictionary)
## Emitted when a combatant's hit points change, with the new value.
signal hit_points_changed(combatant: Node3D, hit_points: int)
## Emitted when combat ends with every enemy defeated.
signal victory
## Emitted when combat ends with the player character defeated.
signal defeat

## How far an attack reaches, between the attacker's and the target's bodies' edges (metres).
const ATTACK_REACH := 1.5
## How tall a combatant's body is, for clicking on it (metres).
const BODY_HEIGHT := 1.8
## How far through the attacker's `attack` clip the blow lands and the target flinches, unless the attacker
## says otherwise with `hit_at` metadata (the player's sword slash lands on its backhand, #158).
const HIT_AT := 0.7
## The body part that is a combatant's main pool (#122).
const BODY := "body"

const Wounds := preload("res://scripts/wounds.gd")
const Blood := preload("res://scripts/blood.gd")

## The player character's combatant (his Player body). He wins initiative ties that nothing else breaks.
@export var detective_path: NodePath
## Draws the previewed path (a MeshInstance3D, with a Label3D under it for the length).
@export var path_preview_node: NodePath
## The garage's NavigationRegion3D, whose map paths are found on.
@export var navigation_node: NodePath
## Path preview colours, within his movement and beyond it.
@export var reachable_colour := Color(0.95, 0.85, 0.45)
@export var out_of_reach_colour := Color(0.85, 0.2, 0.15)
## Enemy turns: how long an enemy pauses before acting, how fast it walks (metres per second), and
## how long it pauses before ending its turn.
@export var enemy_think_seconds := 1.5
@export var enemy_speed := 2.0
@export var enemy_end_seconds := 0.5

## Every die comes from here, so seeding it fixes the dice.
var rng := RandomNumberGenerator.new()
## The player character's knife tip through his current attack, [[clip seconds, position], ...] (#112):
## where the blade goes decides where it cuts.
var _blade_path := []
var _blade_tip := Vector3.ZERO  # the tip of his knife, in the knife's own space
var running := false
var combatants: Array[Node3D] = []
## Each combatant's initiative dice (their initiative pool of d6, #121).
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
## Each combatant's limbs' hit points (#122): combatant -> {part id: hit points}. Its body is its main
## pool, `hit_points`.
var part_health := {}
var defeated: Array[Node3D] = []

## The path previewed under the mouse on the player character's turn: its points (from him), length in
## metres, and whether it fits his movement left.
var preview_path := PackedVector3Array()
var preview_length := 0.0
var preview_reachable := false

enum EnemyStep { NONE, THINK, WALK, DONE }
var _enemy_step := EnemyStep.NONE
var _enemy_timer := 0.0
var _enemy_path := PackedVector3Array()  # the points the active enemy still has to walk to

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
## if it's their turn (#48). Since #120 it's a pool of d6, like Vampire: The Masquerade: the attacker
## rolls their attack pool, each die of 4+ is a success and each pair of 6s counts as four; it hits if
## the successes reach the target's defence (none at all is a total failure, a miss), with a pair of 6s
## making it a critical; the damage is the weapon's plus the successes beyond the defence, at least 1.
## Returns (and emits with `attack_resolved`) what happened: `attacker`, `target`, `dice`,
## `successes`, `defence`, `hit`, `critical` and `damage`.
func attack(attacker: Node3D, target: Node3D) -> Dictionary:
	if active == attacker:
		actions_left = maxi(actions_left - 1, 0)
	var dice := roll_pool(attack_pool(attacker))
	var successes := count_successes(dice)
	var against := defence(target)
	var hit := successes > 0 and successes >= against
	var critical := hit and dice.count(6) >= 2
	var damage := maxi(1, weapon_damage(attacker) + successes - against) if hit else 0
	var result := {
		"attacker": attacker, "target": target, "dice": dice, "successes": successes,
		"defence": against, "hit": hit, "critical": critical, "damage": damage,
	}
	attack_resolved.emit(result)
	_animate_attack(attacker, target, hit, critical)
	if hit:
		apply_damage(target, damage)
	return result


## `size` d6 from the seeded dice (#120).
func roll_pool(size: int) -> Array[int]:
	var dice: Array[int] = []
	for i in size:
		dice.append(rng.randi_range(1, 6))
	return dice


## The successes in a pool (#120): one per die of 4 or more, and each pair of 6s counts as four.
func count_successes(dice: Array) -> int:
	return dice.filter(func(die: int) -> bool: return die >= 4).size() + (dice.count(6) / 2) * 2


## A combatant's body parts (#122), from its `body_parts` metadata: Dictionaries with `id`, `name`,
## `bones` and `share` (of its maximum hit points). The part with id `body` is its main pool.
func body_parts(combatant: Node) -> Array:
	return combatant.get_meta("body_parts", [])


## A part's maximum hit points (#122): its share of the combatant's maximum (rounded, at least 1), or,
## for its body, its maximum.
func part_max_hit_points(combatant: Node, id: String) -> int:
	if id == BODY:
		return max_hit_points(combatant)
	for part: Dictionary in body_parts(combatant):
		if part.id == id:
			return maxi(1, roundi(max_hit_points(combatant) * float(part.share)))
	return 0


## A part's current hit points (#122); for its body, the combatant's main hit points.
func part_hit_points(combatant: Node, id: String) -> int:
	if id == BODY:
		return hit_points.get(combatant, max_hit_points(combatant))
	return part_health.get(combatant, {}).get(id, part_max_hit_points(combatant, id))


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


## How many d6 a combatant rolls to attack (#120).
func attack_pool(combatant: Node) -> int:
	return combatant.get_meta("attack_pool", 1)


## How many successes it takes to hit a combatant (#120).
func defence(combatant: Node) -> int:
	return combatant.get_meta("defence", 1)


## A combatant's weapon damage, before the successes beyond the defence are added (#120).
func weapon_damage(combatant: Node) -> int:
	return combatant.get_meta("weapon_damage", 1)


## Previews the path from the player character to the floor point under `screen_position`.
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


func _physics_process(delta: float) -> void:
	_record_blade()
	if Input.is_action_just_pressed("end_turn"):
		request_end_turn()
	if running and active != detective and _enemy_step != EnemyStep.NONE:
		_play_enemy_turn(delta)


## The player asking to end the turn (the End Turn key or button): ends it only on the player character's turn.
func request_end_turn() -> void:
	if running and active == detective:
		end_turn()


## Plays the active enemy's turn a tick at a time: think, walk towards the player character, attack, end.
func _play_enemy_turn(delta: float) -> void:
	match _enemy_step:
		EnemyStep.THINK:
			_enemy_timer -= delta
			if _enemy_timer <= 0.0:
				_enemy_path = _approach_path(active)
				if _enemy_path.is_empty():
					_finish_enemy_move()
				else:
					_enemy_step = EnemyStep.WALK
					_play_animation(active, "walk")
		EnemyStep.WALK:
			var step := enemy_speed * delta
			while step > 0.0 and not _enemy_path.is_empty():
				var to_next := _enemy_path[0] - active.global_position
				to_next.y = 0.0
				var distance := to_next.length()
				if distance > 0.0001:
					active.rotation.y = atan2(to_next.x, to_next.z)  # models face their +Z
				var moved := minf(step, distance)
				active.global_position += to_next.normalized() * moved if distance > 0.0001 else Vector3.ZERO
				movement_left = maxf(movement_left - moved, 0.0)
				step -= moved
				if moved >= distance:
					_enemy_path.remove_at(0)
			if _enemy_path.is_empty():
				_play_animation(active, "idle")
				_finish_enemy_move()
		EnemyStep.DONE:
			_enemy_timer -= delta
			if _enemy_timer <= 0.0:
				_enemy_step = EnemyStep.NONE
				end_turn()


## After moving: attack the player character if he's within reach, then pause before the turn ends.
func _finish_enemy_move() -> void:
	_enemy_step = EnemyStep.DONE
	_enemy_timer = enemy_end_seconds
	if can_attack(active, detective):
		attack(active, detective)
		_enemy_timer += _clip_length(active, &"attack")  # let its attack play out before the turn ends


## The points `enemy` walks through towards the player character (not counting where it stands): along a
## path round walls and props, stopping once it's comfortably within reach or out of movement.
## Empty if it's already within reach or can't move.
func _approach_path(enemy: Node3D) -> PackedVector3Array:
	var walk := PackedVector3Array()
	if _edge_gap(enemy, detective) <= ATTACK_REACH:
		return walk
	var map := _navigation.get_navigation_map() if _navigation != null else enemy.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, enemy.global_position, detective.global_position, true)
	# Aim a little inside reach, measured centre to centre.
	var stop_at := ATTACK_REACH - 0.25 + float(enemy.get_meta("body_radius", 0.0)) + float(detective.get_meta("body_radius", 0.0))
	var budget := movement_left
	var here := Vector3(enemy.global_position.x, 0, enemy.global_position.z)
	for i in range(1, path.size()):
		var target := Vector3(path[i].x, 0, path[i].z)
		var leg := here.distance_to(target)
		var travelled := 0.0
		var stopped := false
		# Walk the leg in small steps, stopping at reach or when the movement runs out.
		while travelled < leg:
			var next := minf(travelled + 0.05, leg)
			if next > budget:
				next = budget
				stopped = true
			var point := here.lerp(target, next / leg)
			if Vector2(point.x - detective.global_position.x, point.z - detective.global_position.z).length() <= stop_at:
				walk.append(point)
				return walk
			travelled = next
			if stopped:
				break
		budget -= travelled
		if stopped or budget <= 0.0:
			if travelled > 0.0:
				walk.append(here.lerp(target, travelled / leg))
			return walk
		walk.append(target)
		here = target
	return walk


## The attacker throws its `attack`; on a hit, the target flinches (`hit`) as the blow lands, its
## `hit_at` (or HIT_AT) of the way through the attack, and the player character's knife opens a cut on
## it where its slash meets the body (#93, #112) that sprays blood, much more on a critical hit (#94).
## Enemies settle back into `idle` when a clip finishes (the player's own script picks his stance).
func _animate_attack(attacker: Node3D, target: Node3D, hit: bool, critical: bool) -> void:
	if attacker == detective:
		_blade_path.clear()
	if not _perform(attacker, &"attack") or not hit:
		return
	var delay := _clip_length(attacker, &"attack") * float(attacker.get_meta("hit_at", HIT_AT))
	get_tree().create_timer(delay, false, true).timeout.connect(func():
		if is_instance_valid(target):
			_perform(target, &"hit")
			if attacker == detective and is_instance_valid(attacker):
				_record_blade()
				var wound := Wounds.cut(target, attacker, _blade_path, _clip_length(attacker, &"attack") / 2.0)
				if wound != null:
					Blood.spray(wound, target, attacker, critical))


## Plays `clip` on `combatant` from the start; returns false if it has no such clip.
func _perform(combatant: Node, clip: StringName) -> bool:
	var player := _animation_player(combatant)
	if player == null or not player.has_animation(clip):
		return false
	player.stop()
	player.play(clip)
	if combatant != detective:
		player.animation_finished.connect(func(_name: StringName):
			if is_instance_valid(player) and not player.is_playing():
				player.play(&"idle"), CONNECT_ONE_SHOT)
	return true


func _clip_length(combatant: Node, clip: StringName) -> float:
	var player := _animation_player(combatant)
	return player.get_animation(clip).length if player != null and player.has_animation(clip) else 0.0


func _animation_player(combatant: Node) -> AnimationPlayer:
	var players := combatant.find_children("*", "AnimationPlayer", true, false) if combatant != null else []
	return players[0] if not players.is_empty() else null


func _play_animation(combatant: Node, clip: StringName) -> void:
	var players := combatant.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty() and players[0].current_animation != clip:
		players[0].play(clip)


## Starts combat between `fighters`: rolls initiative for each (in the order given), sets the turn
## order and starts the first turn.
func start_combat(fighters: Array) -> void:
	combatants.assign(fighters)
	rolls = {}
	hit_points = {}
	part_health = {}
	defeated.clear()
	for combatant in combatants:
		rolls[combatant] = roll_pool(initiative_pool(combatant))
		hit_points[combatant] = max_hit_points(combatant)
		part_health[combatant] = {}
		for part: Dictionary in body_parts(combatant):
			if part.id != BODY:
				part_health[combatant][part.id] = part_max_hit_points(combatant, part.id)
	turn_order.assign(order_by_initiative(rolls))
	running = true
	round = 1
	combat_started.emit()
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
	_enemy_path = PackedVector3Array()
	_enemy_step = EnemyStep.NONE if combatant == detective else EnemyStep.THINK
	_enemy_timer = enemy_think_seconds
	turn_started.emit(active)


## How many d6 a combatant rolls for initiative (#121).
func initiative_pool(combatant: Node) -> int:
	return combatant.get_meta("initiative_pool", 1)



## A combatant's full movement per turn, in metres.
func movement(combatant: Node) -> float:
	return combatant.get_meta("movement", 0.0)


## The combatants in `initiative_rolls` (combatant -> their initiative dice), from most successes to
## fewest (#121). Ties go to the larger initiative pool, then to the player character.
func order_by_initiative(initiative_rolls: Dictionary) -> Array:
	var order := initiative_rolls.keys()
	order.sort_custom(func(a: Node, b: Node) -> bool:
		var successes_a := count_successes(initiative_rolls[a])
		var successes_b := count_successes(initiative_rolls[b])
		if successes_a != successes_b:
			return successes_a > successes_b
		if initiative_pool(a) != initiative_pool(b):
			return initiative_pool(a) > initiative_pool(b)
		return a == detective and b != detective)
	return order


## While the player character attacks, notes where his knife's tip is (for where it cuts, #112).
func _record_blade() -> void:
	if detective == null:
		return
	var player := _animation_player(detective)
	var knife := detective.find_child("Knife", true, false) as Node3D
	if player == null or knife == null or player.current_animation != &"attack":
		return
	if _blade_tip == Vector3.ZERO:
		for mi: MeshInstance3D in knife.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					var p := knife.global_transform.affine_inverse() * mi.global_transform * v
					if p.length() > _blade_tip.length():
						_blade_tip = p
	_blade_path.append([player.current_animation_position, knife.global_transform * _blade_tip])
