extends GutTest
# The project boots: the main scene loads, is a 3D scene, and reports it's ready.


func test_main_scene_is_a_3d_scene():
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(path)
	assert_not_null(packed, "the main scene (%s) loads" % path)
	if packed == null:
		return
	var main := packed.instantiate()
	add_child_autofree(main)
	assert_true(main is Node3D, "the main scene's root is a Node3D")
