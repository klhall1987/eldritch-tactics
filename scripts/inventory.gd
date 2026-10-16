extends Node
## The clothes the player owns. Changing clothes goes through here: equipping a carried item puts it on
## (through the Outfit, #68) and moves whatever it replaced back into the inventory; unequipping a worn
## item moves it back. Items he doesn't own, and any change while combat runs, are refused.

## Emitted whenever what he carries or wears changes.
signal inventory_changed

## Every item he owns. Those the Outfit wears are worn; the rest are carried.
@export var items: Array[Resource] = []
## The Outfit that wears the clothes.
@export var outfit_path: NodePath
## The combat controller: no changing clothes while combat runs.
@export var controller_path: NodePath

@onready var _outfit := get_node(outfit_path)
@onready var _controller := get_node_or_null(controller_path)


## The items he owns but isn't wearing.
func carried() -> Array:
	return items.filter(func(item: Resource) -> bool: return not is_worn(item))


func is_worn(item: Resource) -> bool:
	return item != null and _outfit.worn(item.slot) == item.piece


## His item for the clothing glb at `piece_path`, or null if he has none.
func item_for(piece_path: String) -> Resource:
	for item in items:
		if item.piece == piece_path:
			return item
	return null


## Puts on a carried item (what it replaces goes back into the inventory). False if refused.
func equip(item: Resource) -> bool:
	if not _can_change(item) or is_worn(item) or not _outfit.wear(item.slot, item.piece):
		return false
	inventory_changed.emit()
	return true


## Takes off a worn item, back into the inventory. False if refused.
func unequip(item: Resource) -> bool:
	if not _can_change(item) or not is_worn(item):
		return false
	_outfit.take_off(item.slot)
	inventory_changed.emit()
	return true


func _can_change(item: Resource) -> bool:
	return item != null and items.has(item) and not (_controller != null and _controller.running)
