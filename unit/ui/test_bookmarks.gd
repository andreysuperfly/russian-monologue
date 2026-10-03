extends GdUnitTestSuite

## Collections (russian-monologue): nested folders of storylines and nodes, kept in the project.

var _project: MonologueProject


func before_test() -> void:
	_project = auto_free(MonologueProject.new())
	await _project.ready
	ProjectManager.current_project = _project


func after_test() -> void:
	ProjectManager.current_project = null


func test_folders_nest_hold_items_once_and_forget_deleted_storylines() -> void:
	var quest: String = Bookmarks.add_folder("", "Квест: детекция")
	var code: String = Bookmarks.add_folder(quest, "Код домофона")
	Bookmarks.add_item(code, {"kind": "storyline", "storyline": "door"})
	Bookmarks.add_item(code, {"kind": "storyline", "storyline": "door"})
	Bookmarks.add_item(code, {"kind": "node", "storyline": "alkashi", "node": "sentence-1"})

	var paths: Array = Bookmarks.folder_paths()
	assert_int(paths.size()).is_equal(2)
	assert_str(str(paths[1][1])).is_equal("Квест: детекция · Код домофона")
	assert_int((Bookmarks.find_folder(code)["items"] as Array).size()).is_equal(2)

	# a folder cannot go inside itself or its own child
	Bookmarks.move_folder(quest, code)
	assert_int(Bookmarks.tree().size()).is_equal(1)

	Bookmarks.forget_storyline("door")
	assert_int((Bookmarks.find_folder(code)["items"] as Array).size()).is_equal(1)

	Bookmarks.delete_folder(quest)
	assert_array(Bookmarks.tree()).is_empty()
