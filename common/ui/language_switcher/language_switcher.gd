## The languages in the header: the editor's own, and the one the story is being read in.
##
## A translated value holds every language at once and shows one of them, so the story's
## choice belongs to the project rather than to each field that happens to display text.
##
## The interface languages sit at the top of the same list (russian-monologue). A writer sees
## «Русский» in the header and takes it for the editor's language; with a one-language project
## the list used to hold that single entry, and there was no way to English from here.
class_name LanguageSwitcher extends OptionButton

const ADD_LANGUAGE: String = "<add>"
## Metadata prefix of the interface entries, so they never collide with a story language code.
const INTERFACE: String = "ui:"

## True while this switcher is the one making the change, so its own echo is ignored.
var _is_applying: bool = false
var _languages: Array = []


func _ready() -> void:
	item_selected.connect(_on_item_selected)
	ProjectManager.project_loaded.connect(_on_project_loaded)
	EventBus.language_changed.connect(_on_language_changed)
	load_languages([])


func _notification(what: int) -> void:
	# picked here or in Preferences: section titles and the caption follow the new language
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_rebuild.call_deferred()


func _on_project_loaded() -> void:
	var languages: CollectionDocument = ProjectManager.current_project.get_collection("languages")
	if languages == null:
		Log.error("The project carries no languages, so there is nothing to switch between.")
		return

	if not languages.content_changed.is_connected(_on_languages_content_changed):
		languages.content_changed.connect(_on_languages_content_changed)
	_on_languages_content_changed()


## Fills the list and keeps the language already being read.
##
## Adding or renaming a language used to send the editor back to the first one: the list was
## rebuilt and its first entry applied, whatever was on screen.
func load_languages(languages: Array) -> void:
	_languages = languages
	clear()

	add_separator(tr("Interface"))
	for choice: String in InterfaceLocale.CHOICES:
		add_item(choice)
		set_item_metadata(item_count - 1, INTERFACE + choice)
		set_item_tooltip(item_count - 1, tr("Language of the editor itself."))

	var project: MonologueProject = ProjectManager.current_project
	var reading: String = project.active_language_code if project else ""

	var first_story: int = -1
	var seen: PackedStringArray = []
	for index: int in languages.size():
		var language: Dictionary = languages[index]
		var code: String = str(language.get("code", "en"))
		if seen.has(code):
			continue

		if seen.is_empty():
			add_separator(tr("Story text"))
		seen.append(code)
		add_item(str(language.get("name", tr("Language %d") % (index + 1))))
		set_item_metadata(item_count - 1, code)
		set_item_tooltip(item_count - 1, tr("Language the lines of the story are shown in."))
		if first_story < 0:
			first_story = item_count - 1

	if first_story < 0:
		_show_choices()
		return
	# the way to more languages, right where they are chosen (russian-monologue)
	add_separator()
	add_item(tr("+ Add language…"))
	set_item_metadata(item_count - 1, ADD_LANGUAGE)

	if _index_of(reading) < 0:
		# What was being read is gone, so the editor has to move to something that is left.
		_apply_selection(first_story)
	_show_choices()


func _rebuild() -> void:
	load_languages(_languages)


func _index_of(code: String) -> int:
	for index: int in item_count:
		if get_item_metadata(index) == code:
			return index
	return -1


## Ticks the interface language and the story language, and says both on the button.
func _show_choices() -> void:
	var interface: int = _index_of(INTERFACE + InterfaceLocale.current_choice())
	var project: MonologueProject = ProjectManager.current_project
	var story: int = _index_of(project.active_language_code) if project else -1

	select(story if story >= 0 else interface)
	for index: int in item_count:
		if not is_item_separator(index):
			get_popup().set_item_checked(index, index == interface or index == story)

	var caption: String = get_item_text(interface) if interface >= 0 else ""
	# with a single story language there is nothing to tell apart, so only the editor's is shown
	if story >= 0 and _story_language_count() > 1:
		caption = "%s · %s" % [caption, tr(get_item_text(story))]
	text = caption


func _story_language_count() -> int:
	var count: int = 0
	for index: int in item_count:
		var meta: Variant = get_item_metadata(index)
		if meta is String and not (meta as String).begins_with(INTERFACE) and meta != ADD_LANGUAGE:
			count += 1
	return count


func _on_languages_content_changed() -> void:
	load_languages(ProjectManager.current_project.get_collection_value("languages"))


func _on_item_selected(index: int) -> void:
	var meta: String = str(get_item_metadata(index))
	if meta.begins_with(INTERFACE):
		InterfaceLocale.choose(meta.trim_prefix(INTERFACE))
		_rebuild()
		return
	if meta == ADD_LANGUAGE:
		# back to the language being read, and open the list of languages to add one
		_show_choices()
		var project: MonologueProject = ProjectManager.current_project
		if project:
			var languages: CollectionDocument = project.get_collection("languages")
			EventBus.request_objects_inspection.emit([languages] as Array[InspectableObject])
		return
	_apply_selection(index)
	_show_choices()


## Somebody else moved the language on. The list catches up without saying it again.
func _on_language_changed(_code: String) -> void:
	if _is_applying:
		return
	_show_choices()


func _apply_selection(index: int) -> void:
	if index < 0 or index >= item_count:
		return

	var code: String = str(get_item_metadata(index))
	if code.begins_with(INTERFACE) or code == ADD_LANGUAGE:
		return
	var project: MonologueProject = ProjectManager.current_project
	if project == null or project.active_language_code == code:
		return

	_is_applying = true
	project.active_language_code = code
	EventBus.language_changed.emit(code)
	_is_applying = false
