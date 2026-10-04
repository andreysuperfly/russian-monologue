extends Node

signal project_loaded
signal file_prompt_done

## The file and the folder it is in: the whole path is too long to read, the folder tells which
## copy it is (russian-monologue).
const SAVE_PROMPT: String = "The file «%s» in the folder «%s» has changes that are not saved."

var current_project: MonologueProject
var _cancel_close: bool = false


## A project's add-ons are scripts read from disk; let them go while the engine is still whole.
## Held on to until the very end, they took Godot down with them on quit (russian-monologue).
func _exit_tree() -> void:
	ProjectPlugins.unload()


func _ready() -> void:
	EventBus.load_project.connect(load_project_from_path)


func close_current_project() -> bool:
	if not current_project:
		_update_window_title()
		return true

	if current_project and current_project.is_dirty:
		EventBus.ask_dialog.emit(
			_on_close_project_dialog_response,
			"Save change before closing?",
			tr(SAVE_PROMPT) % [current_project.project_path.get_file(), current_project.project_path.get_base_dir().get_file()],
			"Save",
			"Don't Save",
			"Cancel"
		)
		await file_prompt_done

		if _cancel_close:
			return false

	_update_window_title()
	return true


func load_project(project: MonologueProject) -> void:
	if not await close_current_project():
		return

	Log.info("Project loaded!")
	if project.project_path.is_empty():
		ProjectPlugins.unload()  # a new project starts with Monologue's own types only
	current_project = project
	project_loaded.emit.call_deferred()
	EventBus.hide_welcome.emit()

	if not project.project_path.is_empty():
		add_path_to_history(project.project_path)

	_update_window_title()


func save_project(project: MonologueProject) -> void:
	project.save()


## Opens a project from an archive, from the folder an unpacked one lives in, or from any
## file inside that folder, since that is what a file dialog lets the user point at.
func load_project_from_path(path: String) -> void:
	# the project's own add-ons first: its nodes cannot be read without their types
	await ProjectPlugins.prepare(path)
	var new_project: MonologueProject = await MonologueProject.from_path(path)
	if not new_project:
		Log.error("Can't load project from '%s'." % path)
		return

	load_project(new_project)


func add_path_to_history(path: String) -> void:
	var entry: String = path.simplify_path()
	if is_scratch(entry):
		return
	var paths: Array = get_history() as Array
	paths.erase(entry)
	paths.push_front(entry)

	_ensure_history_file()
	var file: FileAccess = FileAccess.open(Constants.HISTORY_PATH, FileAccess.WRITE)
	var content: String = JSON.stringify(paths)
	file.store_string(content)
	file.close()


func get_history() -> PackedStringArray:
	if not FileAccess.file_exists(Constants.HISTORY_PATH):
		FileAccess.open(Constants.HISTORY_PATH, FileAccess.WRITE)

	var file: FileAccess = FileAccess.open(Constants.HISTORY_PATH, FileAccess.READ)
	var content: String = file.get_as_text()
	file.close()

	# _parse_history() already drops paths that no longer exist. The loop that used to
	# repeat that check here erased from the array it was iterating, which skipped the
	# entry after every removal.
	var paths: Array = []
	for path: String in _parse_history(content):
		if path not in paths:
			paths.append(path)

	return paths as PackedStringArray


## A history file that is empty or unreadable is one to start over from rather than an
## error to report: an empty one is what a first run leaves behind, and this is read on
## every input event, so JSON.parse_string() printed a failure on every keystroke.
func _parse_history(text: String) -> Array:
	var reader: JSON = JSON.new()
	if text.strip_edges().is_empty() or reader.parse(text) != OK:
		return []

	var data: Variant = reader.data
	if data is Array:
		return data.filter(func(p: Variant) -> bool: return _still_there(str(p)) and not is_scratch(str(p)))
	return []


## A copy in a temporary folder (a test run, a file opened from an archive) is not a project to
## come back to: kept in the recent list, it opened at start instead of the real one and edits
## went into a copy nothing reads (russian-monologue).
static func is_scratch(path: String) -> bool:
	for root: String in ["/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/"]:
		if path.begins_with(root):
			return true
	return false


## An unpacked project is a folder, not a file, and FileAccess.file_exists() says no to a
## folder, which is what dropped every unpacked project out of the recent list.
static func _still_there(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)


func _ensure_history_file() -> void:
	if not FileAccess.file_exists(Constants.HISTORY_PATH):
		FileAccess.open(Constants.HISTORY_PATH, FileAccess.WRITE)


func _on_close_project_dialog_response(response: int) -> void:
	_cancel_close = false
	if response == Prompt.DENIED:
		file_prompt_done.emit()
		return
	if response == Prompt.CONFIRMED:
		await current_project.save()
		file_prompt_done.emit()
		return

	_cancel_close = true
	file_prompt_done.emit()
	return


func _update_window_title() -> void:
	var base_title: String = (
		"Russian Monologue %s" % ProjectSettings.get_setting("application/config/version")
	)

	if not current_project:
		DisplayServer.window_set_title(base_title)
		return

	var title: String = "<unsaved>"
	if current_project.project_path:
		title = current_project.project_path.get_file().get_basename()

	if current_project.is_dirty:
		title = "* " + title

	DisplayServer.window_set_title("%s - %s" % [title, base_title])
