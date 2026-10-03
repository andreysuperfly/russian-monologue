extends GdUnitTestSuite

## Pictures beside names (russian-monologue): cut to shape, and gone when switched off.

var _was: Variant


func before_test() -> void:
	_was = ConfigManager.get_config(Pictures.SETTING, true)


func after_test() -> void:
	ConfigManager.set_config(Pictures.SETTING, _was)
	Pictures.clear()


func test_a_face_is_cut_round_and_a_thing_square() -> void:
	var path: String = OS.get_cache_dir().path_join("monologue_pictures_test.png")
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	image.save_png(path)

	var face: Image = Pictures.thumb(null, path, 20, true).get_image()
	var thing: Image = Pictures.thumb(null, path, 20, false).get_image()

	assert_float(face.get_pixel(0, 0).a).is_equal(0.0)
	assert_float(face.get_pixel(20, 20).a).is_greater(0.8)
	assert_float(thing.get_pixel(0, 0).a).is_equal(0.0)
	assert_float(thing.get_pixel(20, 2).a).is_greater(0.8)


func test_switched_off_shows_nothing() -> void:
	ConfigManager.set_config(Pictures.SETTING, false)
	assert_bool(Pictures.enabled()).is_false()
	assert_object(Pictures.badge_for(null, {"$type": "item", "icon": "x.png"})).is_null()
