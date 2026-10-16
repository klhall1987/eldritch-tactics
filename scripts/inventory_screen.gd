extends CanvasLayer
## The inventory screen: outside combat, the `inventory` key (I) opens it, and I again or Escape
## (`ui_cancel`) closes it. It lists what he wears in each slot and the clothes he carries, in the
## combat HUD's dark parchment style (#51). Clicking a carried item puts it on; clicking a worn one
## takes it off. While it's open he doesn't walk.

const SLOTS := ["top", "bottom", "feet"]
const INK := Color(0.9, 0.84, 0.7)  # parchment-coloured text, as in the combat HUD
const DIM_INK := Color(0.6, 0.55, 0.45)
const PANEL := Color(0.09, 0.07, 0.05, 0.94)
const BORDER := Color(0.55, 0.43, 0.27)

## The Inventory (#69), the Outfit it dresses (#68), the Player body and the combat controller.
@export var inventory_path: NodePath
@export var outfit_path: NodePath
@export var player_path: NodePath
@export var controller_path: NodePath

@onready var _inventory := get_node(inventory_path)
@onready var _outfit := get_node(outfit_path)
@onready var _player := get_node(player_path)
@onready var _controller := get_node_or_null(controller_path)

var _worn_list: VBoxContainer
var _carried_list: VBoxContainer
var _player_was_controllable := true


func _ready() -> void:
	_build()
	_inventory.inventory_changed.connect(_refresh)
	visible = false


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("inventory"):
		if visible:
			close()
		elif not (_controller != null and _controller.running):
			open()
	elif visible and Input.is_action_just_pressed("ui_cancel"):
		close()


func open() -> void:
	_refresh()
	visible = true
	_player_was_controllable = _player.controllable
	_player.controllable = false  # no walking while he's choosing clothes


func close() -> void:
	visible = false
	_player.controllable = _player_was_controllable


## Redraws both lists from the inventory and the outfit.
func _refresh() -> void:
	for list in [_worn_list, _carried_list]:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
	for slot: String in SLOTS:
		var item: Resource = _inventory.item_for(_outfit.worn(slot))
		var button := _button("%s: %s" % [slot.capitalize(), item.display_name if item != null else "empty"])
		button.disabled = item == null
		if item != null:
			button.pressed.connect(func(): _inventory.unequip(item))
		_worn_list.add_child(button)
	for item: Resource in _inventory.carried():
		var button := _button(item.display_name)
		button.pressed.connect(func(): _inventory.equip(item))
		_carried_list.add_child(button)


## A centred panel with a "Wearing" list (one entry per slot) and a "Carrying" list. The panel takes
## the mouse, so clicks on it never reach the floor behind.
func _build() -> void:
	var panel := PanelContainer.new()
	var style := _box(PANEL)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(340, 0)
	var centre := CenterContainer.new()  # keeps the panel in the middle of the screen at any size
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(_heading("Inventory"))
	column.add_child(_label("Wearing", DIM_INK))
	_worn_list = VBoxContainer.new()
	_worn_list.name = "WornList"
	column.add_child(_worn_list)
	column.add_child(_label("Carrying", DIM_INK))
	_carried_list = VBoxContainer.new()
	_carried_list.name = "CarriedList"
	column.add_child(_carried_list)
	column.add_child(_label("I or Esc to close", DIM_INK))


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE  # keys stay with the game (I, Esc), not the buttons
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := _box(BORDER.darkened(0.3 if state == "hover" else 0.6))
		box.set_content_margin_all(6)
		box.content_margin_left = 12
		button.add_theme_stylebox_override(state, box)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_disabled_color", DIM_INK)
	return button


func _box(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.border_color = BORDER
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	return box


func _heading(text: String) -> Label:
	var label := _label(text, INK)
	label.add_theme_font_size_override("font_size", 22)
	return label


func _label(text: String, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	return label
