## Consists of a TabBar which allows the user to switch between GraphEdits.
## Saving and loading of GraphEdit data is handled by MonologueEditor.
class_name GraphContainer extends PanelContainer

var prompt_scene: PackedScene = preload("uid://bkreq3xdr7gxw")

@export var inspector_panel: InspectorPanel
@onready var graph: MonologueGraphEdit = %GraphEdit
@onready var snap_button: Button = %SnapButton
@onready var grid_button: Button = %GridButton
@onready var trail_container: PanelContainer = %TrailContainer
@onready var trail: HBoxContainer = %Trail

var _selected_nodes: Dictionary = {}
var _graph_offset: Dictionary = {}
var _is_applying_selection: bool = false


func _ready() -> void:
	_lay_header_in_a_row()
	graph.selection_changed.connect(_on_graph_selection_changed)
	snap_button.pressed.connect(_on_snap_button_pressed)
	grid_button.pressed.connect(_on_grid_button_pressed)
	snap_button.button_pressed = ConfigManager.get_config("snap")
	grid_button.button_pressed = ConfigManager.get_config("show_grid")
	_on_snap_button_pressed()
	_on_grid_button_pressed()

	EventBus.request_nodes_selection.connect(_on_request_nodes_selection)
	EventBus.request_storyline_inspection.connect(_on_request_storyline_inspection)
	EventBus.storylines_changed.connect(_refresh_trail)
	EventBus.graph_snap.connect(_on_event_graph_snap)
	EventBus.graph_show_grid.connect(_on_event_show_grid)

	ProjectManager.project_loaded.connect(_on_project_loaded)


func _on_project_loaded() -> void:
	await get_tree().process_frame

	var storyline: StorylineDocument = ProjectManager.current_project.top_level_storylines()[0]
	load_storyline(storyline)
	EventBus.request_storyline_inspection.emit(storyline)


func load_storyline(storyline: StorylineDocument) -> void:
	_graph_offset[graph.storyline_id] = graph.scroll_offset

	_show_trail(storyline)
	graph.storyline_id = storyline.id
	graph.connection_manager = ConnectionManager.new(storyline)
	graph.refresh()
	graph.scroll_offset = _graph_offset.get(storyline.id, Vector2.ZERO)

	var selection: Array[InspectableObject] = []
	selection.assign(_selected_nodes.get(storyline.id, []))

	var restored: Array[InspectableObject] = []
	for object: InspectableObject in selection:
		var node: InspectableNode = object as InspectableNode
		if node and is_instance_valid(node) and is_instance_valid(node.graph_view):
			graph.set_selected(node.graph_view)
			restored.append(node)

	EventBus.request_objects_inspection.emit(restored)


func _refresh_trail() -> void:
	var project: MonologueProject = ProjectManager.current_project
	var open_document: StorylineDocument = (
		project.get_storyline(graph.storyline_id) if project else null
	)
	if open_document:
		_show_trail(open_document)


func is_section() -> bool:
	var storyline: StorylineDocument = ProjectManager.current_project.get_storyline(graph.storyline_id)
	var path: Array[StorylineDocument] = _path_to(storyline)
	return path.size() > 1


## Hidden for a storyline at the top, which has nowhere to go back to.
var _title: Label


func _show_trail(document: StorylineDocument) -> void:
	if _title:
		var names: PackedStringArray = PackedStringArray()
		for step: StorylineDocument in _path_to(document):
			names.append(step.name)
		_title.text = " › ".join(names)
		_title.tooltip_text = _title.text
	for child: Node in trail.get_children():
		trail.remove_child(child)
		child.queue_free()

	var path: Array[StorylineDocument] = _path_to(document)
	trail_container.visible = path.size() > 1
	if not trail.visible:
		return

	for step: StorylineDocument in path:
		if trail.get_child_count() > 0:
			var separator: Label = Label.new()
			separator.text = "/"
			trail.add_child(separator)

		var crumb: Control
		crumb = Button.new()
		crumb.text = step.name
		crumb.disabled = step == document
		crumb.pressed.connect(EventBus.request_storyline_inspection.emit.bind(step))
		trail.add_child(crumb)


## Remembers where it has been, so a parent pointing back down the tree stops the walk.
func _path_to(document: StorylineDocument) -> Array[StorylineDocument]:
	var project: MonologueProject = ProjectManager.current_project
	var path: Array[StorylineDocument] = []
	var walked: Dictionary[String, bool] = {}
	var step: StorylineDocument = document

	while step != null and not walked.has(step.id):
		walked[step.id] = true
		path.push_front(step)
		step = project.get_storyline(step.parent) if project else null
	return path


## Hands the whole selection to the inspector. One node is not a special case, just a
## selection of one, so there is nothing here to branch on.
func _on_graph_selection_changed(nodes: Array[InspectableObject]) -> void:
	if _is_applying_selection:
		return

	# Several nodes go straight to the inspector. A single one also records an undo
	# step, so stepping back through the graph works.
	if nodes.size() > 1:
		EventBus.request_objects_inspection.emit(nodes)
		return

	request_node_selection(nodes)


func _on_request_nodes_selection(
	nodes: Array[InspectableObject], storyline_id: String, skip_history: bool = false
) -> void:
	if storyline_id != graph.storyline_id:
		return
	request_node_selection(nodes, skip_history)


func _on_request_storyline_inspection(storyline: StorylineDocument) -> void:
	if graph.storyline_id == storyline.id:
		return

	load_storyline(storyline)


func request_node_selection(nodes: Array[InspectableObject], skip_history: bool = false) -> void:
	if _is_applying_selection:
		return

	var current_nodes: Array[InspectableObject] = []
	current_nodes.assign(_selected_nodes.get(graph.storyline_id, []))

	var needs_selection_update: bool = current_nodes != nodes
	if not needs_selection_update:
		# Same set, but the graph may have lost the highlight. Put it back.
		for object: InspectableObject in nodes:
			var node: InspectableNode = object as InspectableNode
			if node and is_instance_valid(node.graph_view) and not node.graph_view.selected:
				needs_selection_update = true
				break

	if inspector_panel == null:
		inspector_panel = get_tree().get_first_node_in_group(&"inspector_panel") as InspectorPanel
	if not needs_selection_update and inspector_panel and inspector_panel.current_objects == nodes:
		return

	var history: CommandManager = ProjectManager.current_project.command_manager
	if skip_history or not history:
		_apply_selection(nodes, graph.storyline_id)
		return

	history.execute(
		NodeSelectionCommand.new(graph.storyline_id, current_nodes, nodes, _apply_selection)
	)


func _apply_selection(nodes: Array[InspectableObject], storyline_id: String) -> void:
	_is_applying_selection = true

	if nodes.is_empty():
		_selected_nodes.erase(storyline_id)
	else:
		_selected_nodes[storyline_id] = nodes

	# set_selected() deselects everything else, so only the first call may use it. The
	# rest add to the selection.
	var is_first: bool = true
	for object: InspectableObject in nodes:
		var node: InspectableNode = object as InspectableNode
		if not node or not is_instance_valid(node.graph_view):
			continue
		if is_first:
			graph.set_selected(node.graph_view)
			is_first = false
		else:
			node.graph_view.selected = true

	# picked with the mouse on the graph: selected only, the fields open on a double click
	# (russian-monologue); picked from search, where-used or undo: shown as before
	if graph.pressed_on_text:
		EventBus.request_objects_inspection.emit([] as Array[InspectableObject])
	else:
		EventBus.request_objects_inspection.emit(nodes)
	_is_applying_selection = false


func _on_add_node_btn_pressed() -> void:
	EventBus.enable_picker_mode.emit("", "", 0, Vector2.ZERO)


func _on_snap_button_pressed() -> void:
	graph.snapping_enabled = snap_button.button_pressed
	ConfigManager.set_config("snap", snap_button.button_pressed)


func _on_grid_button_pressed() -> void:
	graph.show_grid = grid_button.button_pressed
	ConfigManager.set_config("show_grid", grid_button.button_pressed)


func _on_event_graph_snap(enabled: bool) -> void:
	graph.snapping_enabled = enabled
	snap_button.button_pressed = enabled


func _on_event_show_grid(grid_visible: bool) -> void:
	graph.show_grid = grid_visible
	grid_button.button_pressed = grid_visible



## The header's three parts used to lie on top of each other, so in a narrow window (or with a
## big interface scale) the search ran over the menus. In a row, the search narrows instead.
func _lay_header_in_a_row() -> void:
	var header: Control = get_node_or_null("VBoxContainer/Header")
	if header == null or not header.has_node("HeaderCenter"):
		return
	var row: HBoxContainer = HBoxContainer.new()
	header.add_child(row)
	var center: Control = header.get_node("HeaderCenter")
	# the open storyline's name, so it is always clear which one is on the graph (russian-monologue)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_stretch_ratio = 2.0
	_title.custom_minimum_size.x = 60
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_PASS
	_title.add_theme_font_size_override("font_size", 17)
	_title.add_theme_color_override("font_color", Color(0.93, 0.9, 0.84))
	# the search stands at the right, by the snap and grid buttons
	var parts: Array = [header.get_node("HeaderLeft"), _title, center, header.get_node("HeaderRight")]
	for part: Control in parts:
		if part.get_parent():
			part.reparent(row, false)
		else:
			row.add_child(part)
	center.custom_minimum_size.x = 120
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # a third of the spare room, with the two springs
	center.size_flags_stretch_ratio = 1.0



static func _spring() -> Control:
	var spring: Control = Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spring
