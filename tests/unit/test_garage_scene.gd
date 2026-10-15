extends GutTest
# The garage in the main scene (ticket #9): the main scene shows the garage room through an
# orthographic camera at the isometric angle (30 degrees down, 45 degrees around). (Its light test
# was removed by ticket #16: the scene has no sun.)

const GARAGE_PATH := "res://assets/models/environments/garage.glb"
const ANGLE_TOLERANCE := 1.0  # degrees


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


func _garage(main: Node) -> Node3D:
	var garage := main.find_child("Garage", true, false) as Node3D
	assert_not_null(garage, "the main scene has a Node3D named Garage")
	return garage


func _camera(main: Node) -> Camera3D:
	var cameras := main.find_children("*", "Camera3D", true, false)
	assert_eq(cameras.size(), 1, "the main scene has one Camera3D")
	return cameras[0] if cameras.size() > 0 else null


# Given the main scene, when it is instantiated, then it contains an instance of
# res://assets/models/environments/garage.glb named Garage, placed at the origin with no rotation
# or scale.
func test_main_scene_has_garage_at_origin():
	var main := _main()
	if main == null:
		return
	var garage := _garage(main)
	if garage == null:
		return
	assert_eq(garage.scene_file_path, GARAGE_PATH, "Garage is an instance of the garage model")
	var relative := main.global_transform.affine_inverse() * garage.global_transform
	assert_true(relative.is_equal_approx(Transform3D.IDENTITY),
		"Garage is at the origin with no rotation or scale (got %s)" % relative)


# Given the main scene, when it is instantiated, then it has a Camera3D that is the current camera,
# uses orthogonal projection, and is tilted 30 degrees down and turned 45 degrees, looking at the
# room from its open +X/+Z corner.
func test_main_scene_has_isometric_orthographic_camera():
	var main := _main()
	if main == null:
		return
	var camera := _camera(main)
	if camera == null:
		return
	assert_true(camera.is_current(), "the camera is the current camera")
	assert_eq(camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "the camera is orthographic")

	var forward := -camera.global_transform.basis.z.normalized()
	var pitch := rad_to_deg(asin(-forward.y))
	assert_almost_eq(pitch, 30.0, ANGLE_TOLERANCE, "the camera looks 30 degrees down")
	var flat := Vector3(forward.x, 0, forward.z).normalized()
	var towards_room := Vector3(-1, 0, -1).normalized()  # from the +X/+Z corner towards -X/-Z
	assert_almost_eq(rad_to_deg(flat.angle_to(towards_room)), 0.0, ANGLE_TOLERANCE,
		"the camera is turned 45 degrees, looking from the +X/+Z corner towards -X/-Z")
	var right := camera.global_transform.basis.x.normalized()
	assert_almost_eq(right.y, 0.0, 0.02, "the camera isn't rolled")
