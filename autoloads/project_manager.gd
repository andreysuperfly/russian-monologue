extends Node

signal project_loaded
signal file_prompt_done
## Another program changed the open project's file and its edits were merged in
## (russian-monologue): the editor notes where it stands before and goes back there after.
signal reloading_from_disk
signal reloaded_from_disk(changed: int)

## The file and the folder it is in: the whole path is too long to read, the folder tells which
## copy it is (russian-monologue).
const SAVE_PROMPT: String = "The file «%s» in the folder «%s» has changes that are not saved."

## Another program (a script, a second copy) wrote the open project's file (russian-monologue).
const MERGED: String = "External edits applied. Nodes changed: %d"
const CONFLICT_TITLE: String = "Conflicting nodes: %d"
const CONFLICT_PROMPT: String = "You and another program both changed the same fields here:\n%s\nYour version is kept. Take the version on disk for these instead?"

var current_project: MonologueProject
var _cancel_close: bool = false

# ---- watching the open file (russian-monologue) ----
## The file as it was last read or written here: where, its fingerprint, and its documents, the
## common ancestor a merge compares both edits against.
var _disk_path: String = ""
var _disk_print: String = ""
var _base: Dictionary = {}
## A change seen on the last look, acted on only once it holds still: a script writes the
## archive in more than one step.
var _seen_print: String = ""
## A version on disk that could not be read (half written?): left alone until it changes again.
var _unreadable: String = ""
var _merging: bool = false
var _prompt: Prompt


## A project's add-ons are scripts read from disk; let them go while the engine is still whole.
## Held on to until the very end, they took Godot down with them on quit (russian-monologue).
func _exit_tree() -> void:
	ProjectPlugins.unload()


func _ready() -> void:
	EventBus.load_project.connect(load_project_from_path)
	var watch: Timer = Timer.new()
	watch.wait_time = 1.0
	watch.timeout.connect(check_disk)
	add_child(watch)
	watch.start()
	get_window().focus_entered.connect(check_disk)


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
	var before: String = disk_print(path)  # before reading: a write after it is a change to see
	# the project's own add-ons first: its nodes cannot be read without their types
	await ProjectPlugins.prepare(path)
	var new_project: MonologueProject = await MonologueProject.from_path(path)
	if not new_project:
		Log.error("Can't load project from '%s'." % path)
		return

	await load_project(new_project)
	if current_project == new_project:
		_remember_disk(new_project, before if path == new_project.project_path else "")


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


# ---------- the file changed on disk (russian-monologue) ----------
# The open project is also written by other programs (a game's own scripts edit dialogues from
# the command line). The file is looked at every second; when someone else changed it, their
# edits are merged into the copy held here node by node (ProjectMerge), so neither theirs nor
# the unsaved ones here are lost. A save does the same right before it writes.


## What the project at [param path] holds on disk, as a string that changes when it does: an
## archive's checksum, or a folder's files and theirs. Empty when there is nothing (yet) to read.
static func disk_print(path: String) -> String:
	if path.is_empty():
		return ""
	if FileAccess.file_exists(path):
		return FileAccess.get_md5(path)
	if not DirAccess.dir_exists_absolute(path):
		return ""
	var parts: PackedStringArray = []
	var pending: PackedStringArray = [path]
	while not pending.is_empty():
		var folder: String = pending[pending.size() - 1]
		pending.remove_at(pending.size() - 1)
		for sub: String in DirAccess.get_directories_at(folder):
			if not sub.begins_with("."):
				pending.append(folder.path_join(sub))
		for file: String in DirAccess.get_files_at(folder):
			if not file.begins_with("."):
				parts.append("%s=%s" % [folder.path_join(file), FileAccess.get_md5(folder.path_join(file))])
	parts.sort()
	return "\n".join(parts).md5_text()


## Called after this editor wrote [param project], so its own save is not taken for someone else's.
func note_written(project: MonologueProject) -> void:
	if project == current_project:
		_remember_disk(project, disk_print(project.project_path))


func _remember_disk(project: MonologueProject, fingerprint: String, documents: Dictionary = {}) -> void:
	_disk_path = project.project_path
	_disk_print = fingerprint if not fingerprint.is_empty() else disk_print(project.project_path)
	_base = documents if not documents.is_empty() else _documents_of(project)
	_seen_print = ""
	_unreadable = ""


static func _documents_of(project: MonologueProject) -> Dictionary:
	return ProjectWriter.documents_of(project).duplicate(true)


## The fingerprint on disk, when it is not the one read or written here last; "" otherwise.
func _changed_on_disk() -> String:
	var project: MonologueProject = current_project
	if project == null or project.project_path.is_empty() or project.project_path != _disk_path:
		return ""
	if _disk_print.is_empty():
		return ""
	var now: String = disk_print(project.project_path)
	if now.is_empty() or now == _disk_print or now == _unreadable:
		return ""
	return now


## Looks at the open project's file and merges what changed there, once the change has held still.
func check_disk() -> void:
	if _merging or _prompt_open():
		return
	var now: String = _changed_on_disk()
	if now.is_empty() or now != _seen_print:
		_seen_print = now  # still being written, perhaps: wait one more look
		return
	_seen_print = ""
	await merge_from_disk()


## Brings [param project] up to date with its file before it is written over it. Returns the
## project to write: the merged one, which has taken [param project]'s place in the editor.
func catch_up_with_disk(project: MonologueProject) -> MonologueProject:
	if project != current_project or _merging or _changed_on_disk().is_empty():
		return project
	await merge_from_disk()
	return current_project


## Merges another program's edits on disk into the open project; keeps the unsaved ones here.
func merge_from_disk() -> void:
	var project: MonologueProject = current_project
	if project == null or _merging:
		return
	_merging = true
	var path: String = project.project_path
	var fingerprint: String = disk_print(path)
	var on_disk: MonologueProject = await MonologueProject.from_path(path)
	if on_disk == null or not on_disk.load_issues.is_valid():
		_unreadable = fingerprint  # tried again when it changes again
		_merging = false
		return
	var theirs: Dictionary = _documents_of(on_disk)

	var merge: ProjectMerge = ProjectMerge.merge(_base, _documents_of(project), theirs)
	if not merge.conflicts.is_empty():
		var take_theirs: bool = await _ask_about_conflicts(merge) == Prompt.CONFIRMED
		# what the writer did meanwhile counts too
		merge = ProjectMerge.merge(_base, _documents_of(project), theirs, take_theirs)

	if merge.is_same_as(_documents_of(project)):
		_remember_disk(project, fingerprint, theirs)  # nothing to show: theirs is already here
		_merging = false
		return

	var merged: MonologueProject = MonologueProject.new()
	await merged.ready
	var issues: ValidationResult = ValidationResult.ok()
	ProjectReader.read_into(merged, MonologueSource.of(merge.documents), issues)
	merged.observe_storylines()
	merged.compact = project.compact
	merged.project_path = path
	merged.name = project.name
	merged.load_issues = on_disk.load_issues

	var was_dirty: bool = project.is_dirty
	reloading_from_disk.emit()
	project.is_dirty = false  # its edits are in the merged copy: nothing to ask about
	await load_project(merged)
	_merging = false
	if current_project != merged:
		project.is_dirty = was_dirty
		return
	# unsaved edits here stay unsaved, so the next save writes them with theirs
	merged.is_dirty = was_dirty
	_remember_disk(merged, fingerprint, theirs)
	_update_window_title()
	Log.info(tr(MERGED) % merge.changed)
	reloaded_from_disk.emit(merge.changed)


func _ask_about_conflicts(merge: ProjectMerge) -> int:
	var count: int = merge.conflicts.size()
	var answer: Array = []
	var take: Callable = func(response: int) -> void: answer.append(response)
	EventBus.ask_dialog.emit(
		take,
		tr(CONFLICT_TITLE) % count,
		tr(CONFLICT_PROMPT) % merge.describe_conflicts(),
		tr("Take disk version"),
		tr("Keep mine"),
		tr("Cancel")
	)
	var prompt: Prompt = _find_prompt()
	while answer.is_empty():
		# no window to ask in (a script run), or another question took its place: keep what is here
		if prompt == null or prompt._callback != take:
			answer.append(Prompt.CANCELLED)
			break
		await get_tree().process_frame
	return answer[0]


## Another question on screen (save before closing, trust an add-on) is not interrupted.
func _prompt_open() -> bool:
	var prompt: Prompt = _find_prompt()
	return prompt != null and prompt.visible


func _find_prompt() -> Prompt:
	if _prompt == null or not is_instance_valid(_prompt):
		_prompt = null
		var pending: Array[Node] = [get_tree().root]
		while not pending.is_empty() and _prompt == null:
			var node: Node = pending.pop_back()
			if node is Prompt:
				_prompt = node
			pending.append_array(node.get_children())
	return _prompt
