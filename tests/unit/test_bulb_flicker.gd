extends GutTest
# The flickering bulb (ticket #17): while the game runs, the bulb light's energy flickers
# irregularly around its base energy (as set in the scene), but never goes out.

const SAMPLE_SECONDS := 2.0
const TEST_FPS := 60  # frames are capped while sampling, so "every frame" means the same everywhere
const MIN_SWING := 0.15  # of base energy, between the highest and lowest sample
const MIN_ENERGY := 0.5  # of base energy
const MAX_ENERGY := 1.2  # of base energy
const MIN_CHANGING_FRAMES := 0.25  # fraction of frames in which the energy changes

var _saved_max_fps := 0


func before_each():
	_saved_max_fps = Engine.max_fps
	Engine.max_fps = TEST_FPS


func after_each():
	Engine.max_fps = _saved_max_fps


# Runs the main scene for SAMPLE_SECONDS and returns {"base": float, "samples": Array[float]}:
# the bulb light's energy as set in the scene (read before it enters the tree, so before any
# flicker), then its energy at the start of every frame. Returns {} (after failing) if it can't.
func _sample_bulb() -> Dictionary:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the main scene (%s) loads" % path)
	if packed == null:
		return {}
	var main := packed.instantiate()
	var light := main.find_child("BulbLight", true, false) as OmniLight3D
	assert_not_null(light, "the main scene has an OmniLight3D named BulbLight")
	if light == null:
		main.free()
		return {}
	var base := light.light_energy
	assert_gt(base, 0.0, "the bulb light has a base energy")
	add_child_autofree(main)

	var samples: Array[float] = []
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < SAMPLE_SECONDS * 1000.0:
		await get_tree().process_frame
		samples.append(light.light_energy)
	assert_gte(samples.size(), int(SAMPLE_SECONDS * TEST_FPS * 0.5), "enough frames were sampled (%d)" % samples.size())
	return {"base": base, "samples": samples}


# Given the main scene is running, when the bulb light's energy is sampled every frame for 2
# seconds, then it changes: the difference between the highest and lowest sample is at least 15%
# of its base energy.
func test_bulb_energy_varies():
	var result := await _sample_bulb()
	if result.is_empty():
		return
	var samples: Array = result.samples
	var swing: float = samples.max() - samples.min()
	assert_gte(swing, MIN_SWING * result.base,
		"the bulb's energy swings by at least 15%% of its base (%.3f of %.3f)" % [swing, result.base])


# Given the same 2 seconds of samples, when they are compared with the base energy, then none is
# below 50% or above 120% of it: the bulb flickers but never goes out.
func test_bulb_never_goes_out_or_flares():
	var result := await _sample_bulb()
	if result.is_empty():
		return
	var samples: Array = result.samples
	assert_gte(samples.min(), MIN_ENERGY * result.base,
		"the bulb never drops below 50%% of its base (lowest %.3f of %.3f)" % [samples.min(), result.base])
	assert_lte(samples.max(), MAX_ENERGY * result.base,
		"the bulb never rises above 120%% of its base (highest %.3f of %.3f)" % [samples.max(), result.base])


# Given the same 2 seconds of samples, when consecutive samples are compared, then the energy
# changes in at least a quarter of the frames, so it flickers rather than switching once.
func test_bulb_flickers_often():
	var result := await _sample_bulb()
	if result.is_empty():
		return
	var samples: Array = result.samples
	var changes := 0
	for i in range(1, samples.size()):
		if not is_equal_approx(samples[i], samples[i - 1]):
			changes += 1
	var steps := samples.size() - 1
	assert_gte(changes, ceili(MIN_CHANGING_FRAMES * steps),
		"the energy changes in at least a quarter of the frames (%d of %d)" % [changes, steps])
