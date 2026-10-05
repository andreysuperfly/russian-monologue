extends GdUnitTestSuite

## The header's language list. A writer with a Russian one-language project saw «Русский»
## there and could not get to English: the list held the story's languages only.

var _locale: String
var _saved_choice: String
var _project: MonologueProject
var _switcher: LanguageSwitcher


func before() -> void:
	_locale = TranslationServer.get_locale()
	_saved_choice = str(ConfigManager.get_config("language", InterfaceLocale.SYSTEM))


func after() -> void:
	ConfigManager.set_config("language", _saved_choice)
	TranslationServer.set_locale(_locale)


func before_test() -> void:
	# a new project is written in the interface language: Russian here, and nothing else
	TranslationServer.set_locale("ru")
	_project = auto_free(MonologueProject.new())
	await _project.ready
	ProjectManager.current_project = _project
	_project.active_language_code = "ru"

	_switcher = auto_free(LanguageSwitcher.new())
	add_child(_switcher)
	_switcher.load_languages(_project.get_collection_value("languages"))


func after_test() -> void:
	ProjectManager.current_project = null


func _index_of(meta: String) -> int:
	for index: int in _switcher.item_count:
		if str(_switcher.get_item_metadata(index)) == meta:
			return index
	return -1


func _pick(meta: String) -> void:
	var index: int = _index_of(meta)
	assert_int(index).override_failure_message("No entry for %s." % meta).is_not_equal(-1)
	_switcher.select(index)
	_switcher.item_selected.emit(index)


func test_a_one_language_project_still_offers_both_interface_languages() -> void:
	assert_int(_index_of(LanguageSwitcher.INTERFACE + "English")).is_not_equal(-1)
	assert_int(_index_of(LanguageSwitcher.INTERFACE + "Русский")).is_not_equal(-1)
	assert_int(_index_of("ru")).is_not_equal(-1)
	assert_str(_switcher.text).is_equal("Русский")


func test_picking_english_switches_the_interface_and_remembers_it() -> void:
	_pick(LanguageSwitcher.INTERFACE + "English")

	assert_str(TranslationServer.get_locale()).is_equal("en")
	assert_str(str(ConfigManager.get_config("language"))).is_equal("English")
	assert_str(_switcher.text).is_equal("English")
	# the story is still read in the language it is written in
	assert_str(_project.active_language_code).is_equal("ru")


func test_and_back_to_russian() -> void:
	_pick(LanguageSwitcher.INTERFACE + "English")
	_pick(LanguageSwitcher.INTERFACE + "Русский")

	assert_str(TranslationServer.get_locale()).is_equal("ru")
	assert_str(str(ConfigManager.get_config("language"))).is_equal("Русский")
	assert_str(_switcher.text).is_equal("Русский")


func test_the_story_language_is_still_chosen_from_the_same_list() -> void:
	var items: Array = _project.get_collection_value("languages").duplicate(true)
	items.append({"id": "lang-en", "name": "English", "code": "en"})
	_switcher.load_languages(items)

	_pick("en")

	assert_str(_project.active_language_code).is_equal("en")
	# the interface stays where it was
	assert_str(TranslationServer.get_locale()).is_equal("ru")
	assert_str(_switcher.text).is_equal("Русский · English")


func test_both_choices_are_ticked() -> void:
	var popup: PopupMenu = _switcher.get_popup()
	assert_bool(popup.is_item_checked(_index_of(LanguageSwitcher.INTERFACE + "Русский"))).is_true()
	assert_bool(popup.is_item_checked(_index_of("ru"))).is_true()
	assert_bool(popup.is_item_checked(_index_of(LanguageSwitcher.INTERFACE + "English"))).is_false()
