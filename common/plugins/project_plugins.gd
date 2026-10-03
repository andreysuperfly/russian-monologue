## Add-ons that travel with a project (russian-monologue).
##
## A project may keep its own node types, fields and collections in a folder beside its file:
## [codeblock]
## my_story.mnlp
## monologue-plugins/
##     my_game/
##         plugin.gd        extends MonologuePlugin, like the core plugin
##         score_node.gd    whatever plugin.gd loads, by path relative to itself
## [/codeblock]
## They are installed when the project opens, before its nodes are read, and removed when another
## project opens — so a game's own nodes never leak into other stories, and the game's code
## never has to live in Monologue's repository.
##
## An add-on is code. The first time a folder offers some, Monologue asks whether to trust it and
## remembers the answer, so a project downloaded from somewhere cannot run anything unasked.
##
## Inside an add-on: no [code]class_name[/code] (it is not part of Monologue's own scripts) and no
## [code]preload("res://…")[/code] of its own files; load them by path from the script's folder:
## [code]load(get_script().resource_path.get_base_dir().path_join("score_node.gd"))[/code].
class_name ProjectPlugins

const FOLDER: String = "monologue-plugins"
const ENTRY: String = "plugin.gd"
const TRUST_PATH: String = "user://trusted_plugin_folders.json"

## Names of the add-ons installed for the open project.
static var _installed: PackedStringArray = PackedStringArray()


## The plugin.gd of every add-on beside [param project_path], sorted.
static func found(project_path: String) -> PackedStringArray:
	var entries: PackedStringArray = PackedStringArray()
	var folder: String = folder_of(project_path)
	if not DirAccess.dir_exists_absolute(folder):
		return entries
	for sub: String in DirAccess.get_directories_at(folder):
		var entry: String = folder.path_join(sub).path_join(ENTRY)
		if FileAccess.file_exists(entry):
			entries.append(entry)
	entries.sort()
	return entries


static func folder_of(project_path: String) -> String:
	return project_path.get_base_dir().path_join(FOLDER)


## Swaps the add-ons over to [param project_path]'s, asking first about a folder not yet trusted.
## Awaited by the loader before it reads the project.
static func prepare(project_path: String) -> void:
	unload()
	var entries: PackedStringArray = found(project_path)
	if entries.is_empty():
		return
	var folder: String = folder_of(project_path)
	if not is_trusted(folder):
		if not await _ask(folder, entries):
			Log.warn(TranslationServer.translate("Add-ons not loaded: %s") % folder)
			return
		trust(folder)
	for entry: String in entries:
		install_from(entry)


## Installs one add-on from its plugin.gd; returns its name, or "" when it could not be loaded.
static func install_from(entry: String) -> String:
	var script: Variant = ResourceLoader.load(entry, "", ResourceLoader.CACHE_MODE_REPLACE)
	if script is not GDScript or not (script as GDScript).can_instantiate():
		Log.error("Add-on %s could not be loaded." % entry)
		return ""
	var plugin: Variant = (script as GDScript).new()
	if plugin is not MonologuePlugin:
		Log.error("Add-on %s does not extend MonologuePlugin." % entry)
		return ""
	var plugin_name: String = (plugin as MonologuePlugin).get_plugin_name()
	MonologueRegistry.get_instance().install(plugin)
	_installed.append(plugin_name)
	Log.info(TranslationServer.translate("Add-on loaded: %s") % plugin_name)
	return plugin_name


static func unload() -> void:
	for plugin_name: String in _installed:
		MonologueRegistry.get_instance().uninstall(plugin_name)
	_installed.clear()


static func installed() -> PackedStringArray:
	return _installed.duplicate()


static func is_trusted(folder: String) -> bool:
	return _trusted().has(folder.simplify_path())


static func trust(folder: String) -> void:
	var folders: Array = _trusted()
	if not folders.has(folder.simplify_path()):
		folders.append(folder.simplify_path())
	var file: FileAccess = FileAccess.open(TRUST_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(folders))


static func _trusted() -> Array:
	if not FileAccess.file_exists(TRUST_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TRUST_PATH))
	return parsed if parsed is Array else []


static func _ask(folder: String, entries: PackedStringArray) -> bool:
	var names: PackedStringArray = PackedStringArray()
	for entry: String in entries:
		names.append(entry.get_base_dir().get_file())
	var answer: Array = []
	EventBus.ask_dialog.emit(
		func(response: int) -> void: answer.append(response),
		TranslationServer.translate("Load this project's add-ons?"),
		TranslationServer.translate("This project brings its own node types: %s.\nAn add-on is code that runs inside Monologue. Load it only if you trust where the project came from.\n\n%s") % [", ".join(names), folder],
		TranslationServer.translate("Load"), TranslationServer.translate("Don't load"), TranslationServer.translate("Cancel")
	)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	while answer.is_empty():
		await tree.process_frame
	return answer[0] == Prompt.CONFIRMED
