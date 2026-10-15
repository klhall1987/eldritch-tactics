extends Node
## Runs turn-based combat in the overworld, tabletop style: everyone rolls initiative (a d20 plus
## their bonus), turns go from the highest total to the lowest, and the first turn starts at once.
## Combatants keep their stats as node metadata (`initiative_bonus`).

## Emitted when a combatant's turn begins.
signal turn_started(combatant: Node3D)

## The detective's combatant (his Player body). He wins initiative ties that nothing else breaks.
@export var detective_path: NodePath

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

@onready var detective := get_node_or_null(detective_path) as Node3D


func _ready() -> void:
	rng.randomize()


## Starts combat between `fighters`: rolls initiative for each (in the order given), sets the turn
## order and starts the first turn.
func start_combat(fighters: Array) -> void:
	combatants.assign(fighters)
	rolls = {}
	for combatant in combatants:
		rolls[combatant] = roll_d20()
	turn_order.assign(order_by_initiative(rolls))
	running = true
	active = turn_order[0]
	turn_started.emit(active)


func roll_d20() -> int:
	return rng.randi_range(1, 20)


func initiative_bonus(combatant: Node) -> int:
	return combatant.get_meta("initiative_bonus", 0)


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
