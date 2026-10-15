extends GutTest
# No god light (ticket #16): the main scene has no sun, and is lit only by its light sources, over
# a dim (but not black) ambient light and a near-black background, with no ray-traced or baked
# global illumination.

const MIN_AMBIENT := 0.05
const MAX_AMBIENT := 0.2
const MAX_BACKGROUND := 0.05


# Instantiates the main scene into the tree, or returns null (after failing the test).
func _main() -> Node3D:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the main scene (%s) loads" % path)
	if packed == null:
		return null
	var main := packed.instantiate()
	add_child_autofree(main)
	return main as Node3D


# The main scene's environment, or null (after failing the test).
func _environment(main: Node) -> Environment:
	var world_environments := main.find_children("*", "WorldEnvironment", true, false)
	assert_eq(world_environments.size(), 1, "the main scene has one WorldEnvironment")
	if world_environments.is_empty():
		return null
	var environment: Environment = world_environments[0].environment
	assert_not_null(environment, "the WorldEnvironment has an Environment")
	return environment


# Given the main scene, when its nodes are inspected, then it has no DirectionalLight3D.
func test_main_scene_has_no_sun():
	var main := _main()
	if main == null:
		return
	assert_gt(main.get_child_count(), 0, "the main scene has nodes to inspect")
	assert_eq(main.find_children("*", "DirectionalLight3D", true, false).size(), 0,
		"the main scene has no DirectionalLight3D")


# Given the main scene's WorldEnvironment, when its ambient light is inspected, then it uses a flat
# colour, and its strength (ambient energy times the colour's brightest channel) is between 0.05
# and 0.2: dim, but not black.
func test_ambient_light_is_dim_but_not_black():
	var main := _main()
	if main == null:
		return
	var environment := _environment(main)
	if environment == null:
		return
	assert_eq(environment.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR,
		"the ambient light is a flat colour")
	var c := environment.ambient_light_color
	var strength := environment.ambient_light_energy * maxf(c.r, maxf(c.g, c.b))
	assert_between(strength, MIN_AMBIENT, MAX_AMBIENT,
		"the ambient light's strength (%.3f) is dim but not black" % strength)


# Given the main scene's WorldEnvironment, when its background is inspected, then it is a solid
# colour with every channel at 0.05 or below.
func test_background_is_near_black():
	var main := _main()
	if main == null:
		return
	var environment := _environment(main)
	if environment == null:
		return
	assert_eq(environment.background_mode, Environment.BG_COLOR, "the background is a solid colour")
	var c := environment.background_color
	assert_lte(maxf(c.r, maxf(c.g, c.b)), MAX_BACKGROUND, "the background (%s) is near black" % c)


# Given the main scene, when its environment and nodes are inspected, then it uses no ray-traced
# or baked global illumination: SDFGI is off, and there are no VoxelGI or LightmapGI nodes.
func test_no_ray_traced_or_baked_global_illumination():
	var main := _main()
	if main == null:
		return
	var environment := _environment(main)
	if environment == null:
		return
	assert_false(environment.sdfgi_enabled, "SDFGI is off")
	assert_eq(main.find_children("*", "VoxelGI", true, false).size(), 0, "there are no VoxelGI nodes")
	assert_eq(main.find_children("*", "LightmapGI", true, false).size(), 0, "there are no LightmapGI nodes")
