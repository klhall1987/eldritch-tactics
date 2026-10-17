extends GutTest
# A richer render for the garage (ticket #114): filmic tone mapping, screen-space ambient occlusion and
# indirect light, 3D anti-aliasing, and a dim rim light behind the fight, as seen from the camera,
# while the garage stays dark (#16's tests, in test_dark_scene.gd, still apply).
#
# Interface these tests choose:
# - The Environment is the main scene's WorldEnvironment's (#16).
# - The camera is the main scene's Camera3D, where it is once the scene has settled; the fight's spot is
#   where the `Cultist` node stands.
# - The bulb is `BulbLight`; its energy is its base energy as saved in the scene (before it flickers).
# - The rim light is any other OmniLight3D or SpotLight3D that meets the ticket's rules.

const BULB_ENERGY := 1.6  # BulbLight's saved base energy (#16)


func _main() -> Node3D:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the main scene (%s) loads" % path)
	if packed == null:
		return null
	var main := packed.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(3)
	return main as Node3D


# Given the main scene's Environment, when it's inspected, then it uses a filmic tone mapper (AgX or
# ACES), and SSAO and SSIL are on.
func test_filmic_tone_mapping_ao_and_bounce_light():
	var main := await _main()
	if main == null:
		return
	var environments := main.find_children("*", "WorldEnvironment", true, false)
	assert_eq(environments.size(), 1, "the main scene has one WorldEnvironment")
	if environments.is_empty():
		return
	var environment: Environment = (environments[0] as WorldEnvironment).environment
	assert_true(environment.tonemap_mode in [Environment.TONE_MAPPER_AGX, Environment.TONE_MAPPER_ACES],
		"it uses a filmic tone mapper, AgX or ACES (mode %d)" % environment.tonemap_mode)
	assert_true(environment.ssao_enabled, "screen-space ambient occlusion is on")
	assert_true(environment.ssil_enabled, "screen-space indirect lighting is on")


# Given the project settings, when they're inspected, then 3D anti-aliasing is on: MSAA at 4x or more,
# or TAA.
func test_anti_aliasing():
	var msaa: int = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0)
	var taa: bool = ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa", false)
	assert_true(msaa >= Viewport.MSAA_4X or taa, "3D anti-aliasing is on (MSAA %d, TAA %s)" % [msaa, taa])


# Given the main scene, when its lights are inspected, then it has a rim light (an OmniLight3D or
# SpotLight3D) behind the fight as seen from the camera (further from the camera than the cultist's
# spot, and within 3 m of it), at most half the bulb's energy.
func test_a_dim_rim_light_behind_the_fight():
	var main := await _main()
	if main == null:
		return
	var camera := main.find_child("Camera3D", true, false) as Camera3D
	var cultist := main.find_child("Cultist", true, false) as Node3D
	assert_true(camera != null and cultist != null, "the main scene has its Camera3D and Cultist")
	if camera == null or cultist == null:
		return
	var spot := cultist.global_position
	var to_spot := camera.global_position.distance_to(spot)
	var found := []
	for light: Light3D in main.find_children("*", "Light3D", true, false):
		if light.name == "BulbLight" or light is DirectionalLight3D:
			continue
		var behind := camera.global_position.distance_to(light.global_position) > to_spot
		var near := light.global_position.distance_to(spot) <= 3.0
		var dim := light.light_energy <= BULB_ENERGY / 2.0
		if behind and near and dim:
			found.append(light.name)
	assert_gt(found.size(), 0, "a dim rim light stands behind the fight, as seen from the camera")
