extends RefCounted
## Blood spray (#94): a one-shot burst of dark red droplets from a fresh cut, flying away from the
## attacker; a critical hit sprays far more, faster and wider. Each spray is a CPUParticles3D in the
## `blood_sprays` group, added to the scene beside the wounded combatant (so it outlives nothing it
## depends on), and frees itself once its droplets have fallen.

const GROUP := &"blood_sprays"
const COLOUR := Color(0.5, 0.03, 0.03)
const LIFETIME := 0.6
const FLING := 50.0  # degrees the spray swings off straight-away, along the blade's path

## [amount, speed min, speed max, spread degrees] for a normal hit and a critical one.
const NORMAL := [24, 1.2, 2.0, 22.0]
const CRITICAL := [96, 2.2, 3.4, 38.0]


## Sprays blood from `wound` (a Node3D on `target`), away from `attacker`. Returns the spray.
static func spray(wound: Node3D, target: Node3D, attacker: Node3D, critical: bool) -> CPUParticles3D:
	var style: Array = CRITICAL if critical else NORMAL
	var particles := CPUParticles3D.new()
	particles.name = "BloodSpray"
	particles.add_to_group(GROUP)
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.amount = style[0]
	particles.lifetime = LIFETIME
	particles.initial_velocity_min = style[1]
	particles.initial_velocity_max = style[2]
	particles.spread = style[3]
	# Flung along the blade's path: away from the attacker, swung round towards where his backhand
	# follows through (his right), so it flies off the front of the cut rather than into the body.
	var away := target.global_position - attacker.global_position
	away.y = 0.0
	var his_right := attacker.global_basis * Vector3.LEFT  # he faces his +Z, so -X is his right
	his_right.y = 0.0
	var flung := away.normalized()
	flung = flung * cos(deg_to_rad(FLING)) + (his_right.normalized() - flung * flung.dot(his_right.normalized())).normalized() * sin(deg_to_rad(FLING))
	particles.direction = (flung + Vector3(0, 0.35, 0)).normalized()
	particles.gravity = Vector3(0, -9.8, 0)
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.4
	particles.color = COLOUR
	var drop := SphereMesh.new()
	drop.radius = 0.018
	drop.height = 0.036
	drop.radial_segments = 6
	drop.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOUR
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.3
	drop.material = material
	particles.mesh = drop
	target.get_parent().add_child(particles)
	particles.global_transform = Transform3D(Basis(), wound.global_position)
	particles.emitting = true
	particles.get_tree().create_timer(LIFETIME + 0.25, false).timeout.connect(particles.queue_free)
	return particles
