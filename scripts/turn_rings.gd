extends Node3D
## Turn rings (#101): while combat runs, a flat ring on the floor under each combatant still standing
## shows whose turn it is. The active combatant's glows bright gold; everyone else's is dim blue (the
## player character) or dim red (enemies). A defeated combatant's ring goes, and all go when combat
## ends. Each ring is a MeshInstance3D in the `turn_rings` group with `combatant` metadata, kept here
## (not under the combatant, whose own meshes other code measures) and moved under them every frame.

const GROUP := &"turn_rings"
const ACTIVE := Color(1.0, 0.78, 0.2)
const PLAYER := Color(0.15, 0.25, 0.6)
const ENEMY := Color(0.55, 0.12, 0.1)
const WIDTH := 0.07  # the ring's band, outside the body
const LIFT := 0.01  # above the floor, so it doesn't flicker into it

## The combat controller whose turns to show.
@export var controller_path: NodePath

@onready var _controller := get_node(controller_path)

var _rings := {}  # combatant -> ring


func _process(_delta: float) -> void:
	var standing: Array = []
	if _controller.running:
		standing = _controller.combatants.filter(func(c: Node3D) -> bool: return is_instance_valid(c) and not _controller.is_defeated(c))
	for combatant in _rings.keys():
		if not standing.has(combatant):
			_rings[combatant].queue_free()
			_rings.erase(combatant)
	for combatant: Node3D in standing:
		var ring: MeshInstance3D = _rings.get(combatant)
		if ring == null:
			ring = _ring(combatant)
			_rings[combatant] = ring
		ring.global_position = Vector3(combatant.global_position.x, LIFT, combatant.global_position.z)
		var colour := ACTIVE if combatant == _controller.active else (PLAYER if combatant == _controller.detective else ENEMY)
		(ring.material_override as StandardMaterial3D).albedo_color = colour


func _ring(combatant: Node3D) -> MeshInstance3D:
	var inner: float = float(combatant.get_meta("body_radius", 0.25)) + 0.05
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = inner + WIDTH
	torus.rings = 48
	torus.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ring := MeshInstance3D.new()
	ring.name = "TurnRing"
	ring.mesh = torus
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1, 0.15, 1)  # flattened onto the floor
	ring.set_meta("combatant", combatant)
	ring.add_to_group(GROUP)
	add_child(ring)
	return ring
