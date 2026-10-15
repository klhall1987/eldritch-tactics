extends GutTest
# The bulb light (ticket #15): the garage's hanging bulb is a real light, an OmniLight3D at the
# bulb that casts warm light and shadows, and everything but the bulb itself casts shadows.

const MAX_DISTANCE := 0.15  # metres from the bulb mesh's centre
const MIN_RANGE := 6.0  # metres
const NO_SHADOW := ["bulb", "bulb_cord"]


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


# The centre of the garage's bulb mesh in world space, or null (after failing the test).
func _bulb_centre(main: Node) -> Variant:
	var garage := main.find_child("Garage", true, false)
	assert_not_null(garage, "the main scene has the Garage")
	if garage == null:
		return null
	var bulb := garage.find_child("bulb", true, false) as MeshInstance3D
	assert_not_null(bulb, "the garage has its bulb mesh")
	if bulb == null:
		return null
	return (bulb.global_transform * bulb.get_aabb()).get_center()


# The OmniLight3D nearest the bulb, if it's within MAX_DISTANCE; otherwise null (after failing).
func _bulb_light(main: Node) -> OmniLight3D:
	var centre: Variant = _bulb_centre(main)
	if centre == null:
		return null
	var lights := main.find_children("*", "OmniLight3D", true, false)
	assert_gt(lights.size(), 0, "the main scene has an OmniLight3D")
	var nearest: OmniLight3D = null
	for light: OmniLight3D in lights:
		if nearest == null or light.global_position.distance_to(centre) < nearest.global_position.distance_to(centre):
			nearest = light
	if nearest == null:
		return null
	var distance := nearest.global_position.distance_to(centre)
	assert_lte(distance, MAX_DISTANCE, "an OmniLight3D is at the bulb (nearest is %.2f m away)" % distance)
	return nearest if distance <= MAX_DISTANCE else null


# Given the main scene, when its lights are inspected, then it has an OmniLight3D within 0.15 m of
# the centre of the garage's bulb mesh, visible, with energy above 0.
func test_bulb_has_an_omni_light():
	var main := _main()
	if main == null:
		return
	var light := _bulb_light(main)
	if light == null:
		return
	assert_true(light.is_visible_in_tree(), "the bulb light is visible")
	assert_gt(light.light_energy, 0.0, "the bulb light has energy")


# Given that bulb light, when its settings are inspected, then it casts shadows and its range is at
# least 6 m (enough to reach every corner of the room).
func test_bulb_light_casts_shadows_across_the_room():
	var main := _main()
	if main == null:
		return
	var light := _bulb_light(main)
	if light == null:
		return
	assert_true(light.shadow_enabled, "the bulb light casts shadows")
	assert_gte(light.omni_range, MIN_RANGE, "the bulb light reaches at least %.0f m" % MIN_RANGE)


# Given that bulb light, when its colour is inspected, then it is warm: red is at least green,
# green is at least blue, and blue is below 80% of red.
func test_bulb_light_is_warm():
	var main := _main()
	if main == null:
		return
	var light := _bulb_light(main)
	if light == null:
		return
	var c := light.light_color
	assert_gte(c.r, c.g, "the bulb light's red is at least its green (%s)" % c)
	assert_gte(c.g, c.b, "the bulb light's green is at least its blue (%s)" % c)
	assert_lt(c.b, 0.8 * c.r, "the bulb light's blue is below 80%% of its red (%s)" % c)


# Given the main scene, when the meshes of the detective, the cultist and the garage are
# inspected, then every one casts shadows, except the garage's bulb (and its bulb_cord), which
# must not, so the bulb doesn't shadow its own light.
func test_everything_but_the_bulb_casts_shadows():
	var main := _main()
	if main == null:
		return
	var found_no_shadow := []
	for owner_name in ["Detective", "Cultist", "Garage"]:
		var node := main.find_child(owner_name, true, false)
		assert_not_null(node, "the main scene has %s" % owner_name)
		if node == null:
			continue
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		assert_gt(meshes.size(), 0, "%s has meshes" % owner_name)
		for mi: MeshInstance3D in meshes:
			var casts := mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if owner_name == "Garage" and String(mi.name) in NO_SHADOW:
				found_no_shadow.append(String(mi.name))
				assert_false(casts, "the garage's %s doesn't cast shadows" % mi.name)
			else:
				assert_true(casts, "%s's %s casts shadows" % [owner_name, mi.name])
	for mesh_name in NO_SHADOW:
		assert_has(found_no_shadow, mesh_name, "the garage has its %s mesh" % mesh_name)
