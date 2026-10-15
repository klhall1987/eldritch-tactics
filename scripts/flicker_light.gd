extends Light3D
## Flickers the light like a cheap bulb on bad wiring: a restless shimmer around its base energy
## (as set in the scene), with brief dips every so often, but never going out.

## How far the shimmer swings above and below its centre, as a fraction of the base energy.
@export var shimmer := 0.12
## How fast the shimmer wanders.
@export var shimmer_speed := 8.0
## The energy during a dip, as a fraction of the base energy.
@export var dip_level := 0.6
## Seconds between dips (random within this range) and how long each lasts.
@export var dip_gap := Vector2(0.3, 1.2)
@export var dip_length := Vector2(0.05, 0.12)

var _base := 0.0
var _time := 0.0
var _noise := FastNoiseLite.new()
var _next_dip := 0.0
var _dip_left := 0.0


func _ready() -> void:
	_base = light_energy
	_noise.seed = randi()
	_noise.frequency = 1.0
	_next_dip = randf_range(dip_gap.x, dip_gap.y)


func _process(delta: float) -> void:
	_time += delta
	var level := 0.9 + shimmer * _noise.get_noise_1d(_time * shimmer_speed)
	if _dip_left > 0.0:
		_dip_left -= delta
		level = dip_level + randf() * 0.05
	elif _time >= _next_dip:
		_dip_left = randf_range(dip_length.x, dip_length.y)
		_next_dip = _time + _dip_left + randf_range(dip_gap.x, dip_gap.y)
	light_energy = _base * clampf(level, 0.55, 1.1)
