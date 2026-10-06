class_name MonologueEditor extends Control

const STORYLINE_EXTENSIONS: Array = ["*.mnlg,*.json;Storyline Document"]

@export var welcome_window: WelcomeWindow
@export var graph_container: GraphContainer
@export var file_dialog: GlobalFileDialog

@onready var graph_node_picker: GraphNodePicker = %GraphNodePicker
@onready var inspector_panel_node: InspectorPanel = %Inspector
@onready var project_panel_node: Control = %ProjectPanel

## Roughly how far a node's first port sits below its corner. A wire is let go at the
## cursor, so the node is placed above it by this much and the wire lands straight.
const PORT_FROM_CORNER: Vector2 = Vector2(0.0, 28.0)

var _run_window: MonologueRunWindow


func _ready() -> void:
	get_tree().auto_accept_quit = false

	DisplayServer.window_set_drop_files_callback(_on_window_drop_file)
	EventBus.add_graph_node.connect(add_node_from_global)
	EventBus.select_new_node.connect(_select_new_node)
	EventBus.test_trigger.connect(test_project)
	EventBus.toggle_side_panels.connect(toggle_side_panels)
	_keep_clear_of_window_buttons()
	_drag_window_by_top_bar()
	_add_history_buttons()

	var args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var to_open: String = ""
	for arg: String in args:
		if arg.ends_with(".mnlp") and FileAccess.file_exists(arg):
			to_open = arg

	# nothing asked for: carry on where you left off — the last project, at its last storyline
	# (russian-monologue)
	if to_open.is_empty():
		var recent: PackedStringArray = ProjectManager.get_history()
		if not recent.is_empty() and FileAccess.file_exists(recent[0]):
			to_open = recent[0]

	ProjectManager.load_project(MonologueProject.new())
	# файл из командной строки (open -a Monologue --args путь.mnlp) — открыть сразу
	if not to_open.is_empty():
		EventBus.load_project.emit.call_deferred(to_open)
	EventBus.request_storyline_inspection.connect(_remember_place)
	ProjectManager.project_loaded.connect(_return_to_place)
	ProjectManager.reloading_from_disk.connect(_note_view_before_reload)
	ProjectManager.reloaded_from_disk.connect(func(changed: int) -> void:
		_toast(tr(ProjectManager.MERGED) % changed))


func _select_new_node() -> void:
	graph_node_picker.open_for_node()


#func _input(event: InputEvent) -> void:
#if event.is_action_pressed("Save"):
#ProjectManager.current_project.save()

#if event.is_action_pressed("ui_undo"):
#var focus_owner: Control = get_viewport().gui_get_focus_owner()
#if focus_owner:
#focus_owner.release_focus()
#ProjectManager.current_project.command_manager.undo()
#
#if event.is_action_pressed("ui_redo"):
#ProjectManager.current_project.command_manager.redo()


## Function callback for when th e user wants to add a node from global context.
## Used by header menu and graph node selector (picker).
func add_node_from_global(node_type: String, picker: GraphNodePicker = null) -> void:
	var storyline_id: String = graph_container.graph.storyline_id
	var storyline: StorylineDocument = ProjectManager.current_project.get_storyline(storyline_id)

	if storyline == null:
		Log.error("No active storyline available to add node.")
		return

	var indexer: NodeIndexer = MonologueRegistry.get_instance().get_node(node_type)
	if indexer and indexer.is_singleton:
		Log.warn("A storyline already has its own '%s' node." % node_type)
		return

	var node: InspectableNode = storyline.create_node(node_type)
	if node == null:
		Log.error("Unable to create node of type '%s'." % node_type)
		return

	# A section node with nothing to run does nothing, and making the document it runs by
	# hand is a second step with no decision in it. One gesture makes both.
	if node_type == "section":
		var section: StorylineDocument = ProjectManager.current_project.add_section(storyline_id)
		if section:
			node.get_property("target").set_value(section.id)

	var graph_edit: MonologueGraphEdit = graph_container.graph
	var target_position: Vector2 = graph_edit.middle_of_view()
	if picker and picker.has_source_port():
		target_position = picker.graph_release - PORT_FROM_CORNER
	elif picker and picker.graph_release != Vector2.ZERO:
		target_position = picker.graph_release  # a right click: where it was asked for (russian-monologue)

	# A pair of numbers and not a Vector2, which is what every other writer stores and the only
	# shape JSON can carry.
	var position_property: Property = node.get_property("editor_position")
	if position_property:
		position_property.set_value([target_position.x, target_position.y])

	# One transaction, so a node dragged out of a port and its wire are undone together
	# rather than in two steps.
	var transaction: CommandTransaction = storyline.history.begin("Add %s node" % node_type)
	storyline.history.execute(AddNodesCommand.new(storyline.id, [node]))
	_connect_to_source_port(graph_edit, node, picker)
	transaction.commit()

	graph_edit.refresh()


## Wires the new node to the port the picker was dragged out of. Does nothing when the
## picker was opened from a menu, or when nothing on the node accepts that port.
func _connect_to_source_port(
	graph_edit: MonologueGraphEdit, node: InspectableNode, picker: GraphNodePicker
) -> void:
	if picker == null or not picker.has_source_port():
		return

	var to_property: Property = _first_accepting_property(node, picker.source_port_type_id)
	if to_property == null:
		Log.warn(
			tr("A '%s' has nothing that takes what was dragged into it.") % tr(Util.to_readable_name(node.get_type()))
		)
		return

	# The port has to exist before a wire can land on it. Through the object, so that
	# undoing the whole thing closes it again.
	node.set_property_settings_value(to_property.name, PropertySettings.KEY_EXPOSED, true)
	graph_edit.get_storyline().history.execute(
		NodeConnectionCommand.new(
			graph_edit,
			picker.from_node,
			node.get_id(),
			picker.from_property,
			to_property.name
		)
	)


## The first property of [param node] that could take a wire of this type.
func _first_accepting_property(node: InspectableNode, source_type_id: int) -> Property:
	var registry: MonologueRegistry = MonologueRegistry.get_instance()
	for property: Property in node.get_properties():
		if not property.get_settings_value(PropertySettings.KEY_EXPOSABLE, false):
			continue
		var type_id: int = registry.get_field_type_id(property.type)
		if type_id > 0 and registry.is_compatible(source_type_id, type_id):
			return property
	return null


func load_project(path: String) -> void:
	ProjectManager.load_project_from_path(path)


## Plays the project as it stands, unsaved edits included. One window, reused: pressing Run
## again restarts the story rather than stacking another copy of it.
func test_project(from_node: Variant = null) -> void:
	var project: MonologueProject = ProjectManager.current_project
	if project == null:
		Log.error("There is no project to run.")
		return

	if _run_window == null or not is_instance_valid(_run_window):
		_run_window = MonologueRunWindow.new()
		add_child(_run_window)

	var storyline_id: String = ""
	if graph_container and graph_container.graph:
		storyline_id = graph_container.graph.storyline_id

	_run_window.play(project, storyline_id, str(from_node) if from_node != null else "")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_viewport().gui_release_focus()

		if await ProjectManager.close_current_project():
			get_tree().quit()


func _on_window_drop_file(paths: PackedStringArray) -> void:
	Log.info("%s file(s) have been dragged into the editor." % paths.size())
	if paths.size() > 1:
		Log.warn("Can't open multiple files.")
	var path: String = paths[0]

	if not path.ends_with(".%s" % MonologueProject.FILE_FORMAT):
		Log.error("Can't open file at '%s'. (wrong file format)" % path)
		return

	ProjectManager.load_project_from_path(path)


## macOS draws its red/yellow/green buttons over the top bar (the window extends into the title),
## so the menus start after them; gone in full screen, where the buttons are (russian-monologue).
func _keep_clear_of_window_buttons() -> void:
	var bar: HBoxContainer = get_node_or_null("VBox/Header/HBoxContainer")
	if bar == null:
		return
	var gap: Control = Control.new()
	gap.name = "WindowButtonsGap"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(gap)
	bar.move_child(gap, 0)
	var fit: Callable = func() -> void:
		var margins: Vector3i = DisplayServer.window_get_safe_title_margins()
		gap.custom_minimum_size.x = margins.x / maxf(get_window().content_scale_factor, 1.0)
		gap.visible = margins.x > 0
	fit.call()
	get_tree().root.size_changed.connect(fit)


## The top bar stands where the title bar would be, so it moves the window like one: drag an
## empty part of it, double-click to fill the screen or come back (russian-monologue).
func _drag_window_by_top_bar() -> void:
	var header: Control = get_node_or_null("VBox/Header")
	if header == null:
		return
	header.gui_input.connect(func(event: InputEvent) -> void:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
			return
		if DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
			return
		header.accept_event()
		if click.double_click:
			var big: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if big else DisplayServer.WINDOW_MODE_MAXIMIZED)
		else:
			DisplayServer.window_start_drag())


# ---------- back / forward through the storylines looked at (russian-monologue) ----------

var _history: Array[String] = []
var _history_at: int = -1
var _views: Array[Dictionary] = []
var _walking: bool = false
var _back_button: Button
var _forward_button: Button


func _add_history_buttons() -> void:
	var bar: HBoxContainer = get_node_or_null("VBox/Header/HBoxContainer")
	if bar == null:
		return
	var run: Node = bar.get_node_or_null("RunButton")
	_back_button = _history_button("←", "Back (⌘[)", -1)
	_forward_button = _history_button("→", "Forward (⌘])", 1)
	for b: Button in [_back_button, _forward_button]:
		bar.add_child(b)
		if run:
			bar.move_child(b, run.get_index())
	EventBus.request_storyline_inspection.connect(_remember_storyline)
	graph_container.graph.scroll_offset_changed.connect(_on_view_moved)
	graph_container.graph.jumped.connect(_on_graph_jump)
	ProjectManager.project_loaded.connect(func() -> void:
		if _view_before_reload.get("path", "") == ProjectManager.current_project.project_path:
			return  # the same project read again: its storylines are the same ones
		_views.clear()
		_history.clear()
		_history_at = -1
		_refresh_history_buttons())
	_refresh_history_buttons()


func _history_button(arrow: String, tip: String, step: int) -> Button:
	var b: Button = Button.new()
	b.text = arrow
	b.tooltip_text = tip
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(_walk_history.bind(step))
	return b


## A place is a storyline and where the view stood in it, so stepping back after a jump inside
## one storyline (a ↩ link, «where used») returns to the spot, not just to the storyline.
func _remember_storyline(storyline: StorylineDocument) -> void:
	if _walking or storyline == null:
		return
	if _history_at >= 0 and _history[_history_at] == storyline.id:
		return
	_push_place(storyline.id)


## Called by the graph right before it moves the view somewhere else in the same storyline.
func _on_graph_jump() -> void:
	var graph: MonologueGraphEdit = graph_container.graph
	if _walking or _history_at < 0 or graph.storyline_id != _history[_history_at]:
		return
	# just arrived here and not looked around yet: the jump is part of arriving
	if _views[_history_at].is_empty():
		return
	# before the view moves, so the move is written into the new place, not the old one
	_push_place(graph.storyline_id)


func _push_place(storyline_id: String) -> void:
	_history.resize(_history_at + 1)  # going somewhere new forgets the way forward
	_views.resize(_history_at + 1)
	_history.append(storyline_id)
	_views.append({})
	_history_at = _history.size() - 1
	_refresh_history_buttons()


## Keeps the current place's view up to date as the user scrolls and zooms.
func _on_view_moved(_offset: Vector2 = Vector2.ZERO) -> void:
	var graph: MonologueGraphEdit = graph_container.graph
	if _walking or _history_at < 0 or graph.storyline_id != _history[_history_at]:
		return
	_views[_history_at] = {"offset": graph.scroll_offset, "zoom": graph.zoom}


func _walk_history(step: int) -> void:
	var project: MonologueProject = ProjectManager.current_project
	var at: int = _history_at + step
	while project and at >= 0 and at < _history.size():
		var storyline: StorylineDocument = project.get_storyline(_history[at])
		if storyline:
			_history_at = at
			_walking = true
			var graph: MonologueGraphEdit = graph_container.graph
			if graph.storyline_id != storyline.id:
				EventBus.request_storyline_inspection.emit(storyline)
				await get_tree().process_frame
				await get_tree().process_frame
			var place: Dictionary = _views[at]
			if not place.is_empty():
				graph.zoom = place["zoom"]
				graph.scroll_offset = place["offset"]
			await get_tree().process_frame
			_walking = false
			break
		_history.remove_at(at)  # a storyline that was deleted since
		_views.remove_at(at)
		if step < 0:
			at -= 1
	_refresh_history_buttons()


func _refresh_history_buttons() -> void:
	if _back_button:
		_back_button.disabled = _history_at <= 0
		_forward_button.disabled = _history_at >= _history.size() - 1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_XBUTTON1:
			_walk_history(-1)
		elif event.button_index == MOUSE_BUTTON_XBUTTON2:
			_walk_history(1)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.is_command_or_control_pressed():
			if event.keycode == KEY_BRACKETLEFT:
				_walk_history(-1)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_BRACKETRIGHT:
				_walk_history(1)
				get_viewport().set_input_as_handled()
		elif not event.alt_pressed and not event.shift_pressed:
			if event.keycode == KEY_X or event.physical_keycode == KEY_X:
				if _can_trigger_panel_toggle():
					toggle_side_panels()
					get_viewport().set_input_as_handled()
			elif event.keycode == KEY_ESCAPE:
				get_viewport().gui_release_focus()
				get_viewport().set_input_as_handled()


func _can_trigger_panel_toggle() -> bool:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit or focus_owner is TextEdit or focus_owner is CodeEdit:
		return false
	if graph_node_picker and graph_node_picker.visible:
		return false
	if welcome_window and welcome_window.visible:
		return false
	if file_dialog and file_dialog.visible:
		return false
	for child: Node in get_tree().root.get_children():
		if child is Window and child != get_tree().root and (child as Window).visible:
			return false
	return true


## Toggles left (project) and right (inspector) side panels:
## If either panel is open, hides both. If both are hidden, restores them.
func toggle_side_panels() -> void:
	var left: Control = project_panel_node
	var right: Control = inspector_panel_node
	if left == null or right == null:
		return

	var left_is_open: bool = left.visible
	var right_is_open: bool = right.visible

	if left_is_open or right_is_open:
		ConfigManager.set_config("show_project_explorer", false)
		left.visible = false
		EventBus.show_project_explorer.emit(false)

		ConfigManager.set_config("show_inspector", false)
		if right is InspectorPanel:
			(right as InspectorPanel).close()
		else:
			right.visible = false
		EventBus.show_inspector.emit(false)
	else:
		ConfigManager.set_config("show_project_explorer", true)
		left.visible = true
		EventBus.show_project_explorer.emit(true)

		ConfigManager.set_config("show_inspector", true)
		if right is InspectorPanel:
			var insp: InspectorPanel = right as InspectorPanel
			insp._closed_on = []
			insp.show()
			EventBus.show_inspector.emit(true)
			if not insp.current_objects.is_empty():
				insp.inspect(insp.current_objects)
			elif graph_container and graph_container.graph:
				var selected: Array[InspectableObject] = graph_container.graph.get_selected_nodes()
				if not selected.is_empty():
					insp.inspect(selected)
				else:
					var storyline: StorylineDocument = graph_container.graph.get_storyline()
					if storyline:
						insp.inspect([storyline])
					else:
						insp.show()
			else:
				insp.show()
		else:
			right.visible = true
			EventBus.show_inspector.emit(true)


# ---------- where you were (russian-monologue) ----------

const PLACE_PATH: String = "user://last_place.json"


## Remembers, per project file, the storyline last looked at.
func _remember_place(storyline: StorylineDocument) -> void:
	var project: MonologueProject = ProjectManager.current_project
	if project == null or project.project_path.is_empty() or storyline == null:
		return
	if ProjectManager.is_scratch(project.project_path):
		return
	var places: Dictionary = _places()
	places[project.project_path] = storyline.id
	var file: FileAccess = FileAccess.open(PLACE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(places))


## On opening a project, goes back to the storyline it was left at.
func _return_to_place() -> void:
	var project: MonologueProject = ProjectManager.current_project
	if project == null or project.project_path.is_empty():
		return
	var view: Dictionary = _view_before_reload
	_view_before_reload = {}
	if view.get("path", "") == project.project_path:
		_return_to_view(project, view)
		return
	var storyline: StorylineDocument = project.get_storyline(str(_places().get(project.project_path, "")))
	if storyline == null:
		return
	# after the project list has opened its first storyline, which it does on load
	await get_tree().process_frame
	await get_tree().process_frame
	if ProjectManager.current_project == project:
		EventBus.request_storyline_inspection.emit(storyline)


# ---------- another program's edits merged in (russian-monologue) ----------

var _view_before_reload: Dictionary = {}


## Where the writer stood when another program changed the file: the same storyline, spot, zoom
## and selected cards once its edits are merged in.
func _note_view_before_reload() -> void:
	var project: MonologueProject = ProjectManager.current_project
	var graph: MonologueGraphEdit = graph_container.graph if graph_container else null
	if project == null or graph == null:
		return
	var selected: PackedStringArray = []
	for object: Variant in graph_container._selected_nodes.get(graph.storyline_id, []):
		if object is InspectableNode and is_instance_valid(object):
			selected.append((object as InspectableNode).get_id())
	_view_before_reload = {
		"path": project.project_path,
		"storyline": graph.storyline_id,
		"offset": graph.scroll_offset,
		"zoom": graph.zoom,
		"selected": selected,
	}


func _return_to_view(project: MonologueProject, view: Dictionary) -> void:
	var storyline: StorylineDocument = project.get_storyline(str(view["storyline"]))
	if storyline == null:
		return  # gone in the new version: the project opens where it opens
	# after the project list has opened its first storyline, which it does on load
	await get_tree().process_frame
	await get_tree().process_frame
	if ProjectManager.current_project != project:
		return
	var graph: MonologueGraphEdit = graph_container.graph
	if graph.storyline_id != storyline.id:
		EventBus.request_storyline_inspection.emit(storyline)
		await get_tree().process_frame
	graph.zoom = view["zoom"]
	graph.scroll_offset = view["offset"]
	var selection: Array[InspectableObject] = []
	for id: String in view["selected"]:
		var node: InspectableNode = storyline.get_node(id)
		if node:
			selection.append(node)
	if not selection.is_empty():
		EventBus.request_nodes_selection.emit(selection, storyline.id, true)


## A short note over the graph that goes away by itself.
func _toast(text: String) -> void:
	var note: PanelContainer = PanelContainer.new()
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.72)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(10)
	note.add_theme_stylebox_override(&"panel", box)
	var label: Label = Label.new()
	label.text = text
	note.add_child(label)
	add_child(note)
	note.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	note.position.y = 56
	var fade: Tween = note.create_tween()
	fade.tween_interval(2.5)
	fade.tween_property(note, "modulate:a", 0.0, 0.6)
	fade.tween_callback(note.queue_free)


func _places() -> Dictionary:
	if not FileAccess.file_exists(PLACE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLACE_PATH))
	return parsed if parsed is Dictionary else {}
