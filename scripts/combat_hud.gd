extends CanvasLayer
## The tabletop combat HUD, shown only while combat runs: the turn order along the top (each
## combatant's hit points, the active one marked "▶"), the active combatant's movement, action and
## bonus action with an End Turn button along the bottom, and a dice log of every roll at the side,
## hidden when each combat starts and shown or hidden with the `dice_log` key (L, #102).
## Combatants are named by their `display_name` metadata.

## The combat controller to show.
@export var controller_path: NodePath
## How many lines the dice log keeps.
@export var log_lines := 12

const INK := Color(0.9, 0.84, 0.7)  # parchment-coloured text
const DIM_INK := Color(0.6, 0.55, 0.45)
const PANEL := Color(0.09, 0.07, 0.05, 0.88)
const BORDER := Color(0.55, 0.43, 0.27)

@onready var _controller := get_node(controller_path)

var _turn_order: HBoxContainer
var _movement: Label
var _action: Label
var _bonus_action: Label
var _dice_log: VBoxContainer
var _dice_log_panel: Control  # the dice log's panel, shown and hidden with the `dice_log` key


func _ready() -> void:
	_build()
	_controller.combat_started.connect(func(): _dice_log_panel.visible = false)  # each combat starts with it hidden
	_controller.combat_started.connect(_log_initiative)
	_controller.attack_resolved.connect(_log_attack)
	visible = false


func _process(_delta: float) -> void:
	visible = _controller.running
	if not visible:
		return
	if Input.is_action_just_pressed("dice_log"):
		_dice_log_panel.visible = not _dice_log_panel.visible
	_refresh_turn_order()
	_movement.text = "Movement: %.1f m" % _controller.movement_left
	_action.text = "Action: %s" % ("ready" if _controller.actions_left > 0 else "used")
	_bonus_action.text = "Bonus action: %s" % ("ready" if _controller.bonus_actions_left > 0 else "used")


func _refresh_turn_order() -> void:
	var order: Array = _controller.turn_order
	while _turn_order.get_child_count() < order.size():
		_turn_order.add_child(_label(""))
	while _turn_order.get_child_count() > order.size():
		var extra := _turn_order.get_child(_turn_order.get_child_count() - 1)
		_turn_order.remove_child(extra)
		extra.queue_free()
	for i in order.size():
		var combatant: Node3D = order[i]
		var entry := _turn_order.get_child(i) as Label
		var active: bool = combatant == _controller.active
		entry.text = "%s%s %d/%d" % ["▶ " if active else "", _name(combatant),
			_controller.hit_points.get(combatant, 0), _controller.max_hit_points(combatant)]
		entry.add_theme_color_override("font_color", INK if active else DIM_INK)


func _log_initiative() -> void:
	for combatant: Node3D in _controller.turn_order:
		var dice: Array = _controller.rolls[combatant]
		_log("%s initiative: %d dice %s = %d successes" % [_name(combatant), dice.size(), str(dice),
			_controller.count_successes(dice)])


func _log_attack(result: Dictionary) -> void:
	var attacker: Node3D = result.attacker
	var line := "%s attacks: %d dice %s = %d successes vs defence %d, %s" % [_name(attacker), result.dice.size(),
		str(result.dice), result.successes, result.defence,
		("critical hit" if result.critical else "hit") if result.hit else "miss"]
	if result.hit:
		line += "; damage %d" % result.damage
	_log(line)


## Adds a line to the bottom of the dice log, dropping the oldest beyond `log_lines`.
func _log(text: String) -> void:
	var line := _label(text)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dice_log.add_child(line)
	while _dice_log.get_child_count() > log_lines:
		var oldest := _dice_log.get_child(0)
		_dice_log.remove_child(oldest)
		oldest.queue_free()


func _name(combatant: Node) -> String:
	return combatant.get_meta("display_name", combatant.name)


## Lays out the three panels: turn order (top), resources and End Turn (bottom), dice log (bottom
## right, growing upwards as lines are added).
func _build() -> void:
	var top := _panel(Vector2(0.5, 0), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END, Vector2(0, 12))
	_turn_order = HBoxContainer.new()
	_turn_order.name = "TurnOrder"
	_turn_order.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_order.add_theme_constant_override("separation", 24)
	top.add_child(_turn_order)

	var bottom := _panel(Vector2(0.5, 1), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN, Vector2(0, -12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(row)
	_movement = _label("")
	_movement.name = "Movement"
	_action = _label("")
	_action.name = "Action"
	_bonus_action = _label("")
	_bonus_action.name = "BonusAction"
	var end_turn := Button.new()
	end_turn.name = "EndTurn"
	end_turn.text = "End Turn"
	end_turn.focus_mode = Control.FOCUS_NONE  # Space must stay the end_turn key, not "press button"
	for state in ["normal", "hover", "pressed"]:
		var style := _box(BORDER.darkened(0.55) if state == "normal" else BORDER.darkened(0.3))
		style.set_content_margin_all(6)
		style.content_margin_left = 14
		style.content_margin_right = 14
		end_turn.add_theme_stylebox_override(state, style)
	end_turn.add_theme_color_override("font_color", INK)
	end_turn.add_theme_color_override("font_hover_color", INK)
	end_turn.pressed.connect(func(): _controller.request_end_turn())
	for part in [_movement, _action, _bonus_action, end_turn]:
		row.add_child(part)

	var side := _panel(Vector2(1, 1), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN, Vector2(-12, -76))
	_dice_log_panel = side
	side.visible = false
	side.custom_minimum_size = Vector2(330, 0)
	_dice_log = VBoxContainer.new()
	_dice_log.name = "DiceLog"
	_dice_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(_dice_log)


## A panel pinned at `anchor` (fractions of the screen), `offset` pixels from it, growing in the
## given directions as its contents grow.
func _panel(anchor: Vector2, grow_h: Control.GrowDirection, grow_v: Control.GrowDirection, offset: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := _box(PANEL)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # clicks pass through to the floor; only buttons catch them
	add_child(panel)
	panel.anchor_left = anchor.x
	panel.anchor_right = anchor.x
	panel.anchor_top = anchor.y
	panel.anchor_bottom = anchor.y
	panel.offset_left = offset.x
	panel.offset_right = offset.x
	panel.offset_top = offset.y
	panel.offset_bottom = offset.y
	panel.grow_horizontal = grow_h
	panel.grow_vertical = grow_v
	return panel


func _box(colour: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.border_color = BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", INK)
	return label
