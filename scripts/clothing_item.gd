extends Resource
## A piece of clothing the player can own: its name for the inventory screen, the clothing glb
## (assets/models/clothes, #67) and the slot it fills.

@export var display_name := ""
## The clothing glb's path.
@export_file("*.glb") var piece := ""
## `top`, `bottom` or `feet`.
@export var slot := ""
