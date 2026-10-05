class_name MonologueGraphEdit extends CustomGraphEdit

const WIRE_REACH: float = 8.0
const OFFER_EXTRACT: int = 0
const OFFER_BRIDGE_OUT: int = 1
const OFFER_TEMPLATE: int = 2
const OFFER_ADD_NODE: int = 3

signal node_view_selected(node: InspectableNode)
signal selection_changed(nodes: Array[InspectableObject])

var storyline_id: String
var connection_manager: ConnectionManager

var _node_map: Dictionary = {}  # Maps GraphNode -> InspectableNode
var _selected_nodes: Dictionary = {}
var _selected_wires: Array[NodeConnection] = []
var _copied_nodes: Array = []
var _pending_positions: Dictionary = {}  # GraphNode -> Vector2 captured during drag
var _is_applying_position: bool = false
var _refresh_deferred: bool = false
var _disconnecting: bool = false
var _nodes_to_refresh: Array[InspectableObject] = []
var _selection_snapshot: Array[StringName] = []
var _announced_selection: Array[StringName] = []


func _ready() -> void:
	super._ready()
	_use_scalable_font()
	connection_request.connect(_on_connection_request)
	connection_to_empty.connect(_on_connection_to_empty)
	copy_nodes_request.connect(_on_copy_nodes_request)
	cut_nodes_request.connect(_on_cut_nodes_request)
	delete_nodes_request.connect(_on_delete_nodes_request)
	disconnection_request.connect(_on_disconnection_request)
	end_node_move.connect(_on_end_node_move)
	node_deselected.connect(_on_node_deselected)
	node_selected.connect(_on_node_selected)
	paste_nodes_request.connect(_on_paste_nodes_request)

	# GraphEdit refuses a drag between differing slot types before it ever emits
	# connection_request, so every compatible pair has to be declared up front.
	MonologueRegistry.get_instance().apply_connection_types(self)

	EventBus.refresh_graph.connect(refresh)
	# Every preview on the canvas is written in the active language, so a change of
	# language is a change of what every node says.
	EventBus.language_changed.connect(_on_language_changed)
	connection_drag_ended.connect(_flush_deferred_refresh)
	popup_request.connect(_on_popup_request)
	gui_input.connect(_on_graph_gui_input)

	add_theme_color_override("activity", ThemeLayout.accent_color)
	add_to_group(&"monologue_graph")


func _on_language_changed(_code: String) -> void:
	refresh()


## True while GraphEdit is in the middle of a gesture and its ports must stay put.
##
## Rebuilding a view now throws its rows away and builds new ones that have not been laid
## out yet, so every port reads as being somewhere it is not. GraphEdit re-reads them the
## instant it hands the event back, finds no port under the cursor, and takes the press for
## a click on the canvas: a box selection, on top of the wire being dragged.
func views_are_busy() -> bool:
	return connecting_mode or _disconnecting


func get_storyline() -> StorylineDocument:
	return ProjectManager.current_project.get_storyline(storyline_id)


func refresh() -> void:
	if views_are_busy():
		_refresh_deferred = true
		return

	var storyline: StorylineDocument = get_storyline()
	if not storyline:
		return

	if not connection_manager:
		connection_manager = ConnectionManager.new(storyline)

	_node_map.clear()
	_pending_positions.clear()
	clear_connections()

	MonologueRegistry.get_instance().apply_connection_types(self)

	# Out of the tree before the new ones go in, and not merely queued: a freeing node keeps
	# its name until the end of the frame, so its replacement would be renamed around it. A
	# view's name is the node's id, and everything that looks a view up by id needs that to
	# stay true.
	for child: GraphElement in get_all_graph_nodes():
		remove_child(child)
		child.queue_free()

	for node: InspectableNode in storyline.nodes:
		add_graph_node_view(node)

	_reconnect_all_slots()
	_repaint_wire_selection()


func refresh_node(node: InspectableNode) -> void:
	if not node or not is_instance_valid(node.graph_view):
		return

	if views_are_busy():
		if node not in _nodes_to_refresh:
			_nodes_to_refresh.append(node)
		return

	clear_connections()
	GraphNodeViewFactory.apply_metadata(node.graph_view, node)
	GraphNodeViewFactory.populate(node.graph_view, node)
	_sync_position_from_property(node)
	_reconnect_all_slots()
	_repaint_wire_selection()


func add_graph_node_view(node: InspectableNode) -> GraphNode:
	var graph_node: GraphNode = GraphNodeViewFactory.build(node)

	_node_map[graph_node] = node
	node.graph_view = graph_node

	if not graph_node.position_offset_changed.is_connected(
		_on_graph_node_position_changed.bind(graph_node)
	):
		graph_node.position_offset_changed.connect(_on_graph_node_position_changed.bind(graph_node))

	if node is SectionNode and not graph_node.gui_input.is_connected(_on_section_view_input):
		graph_node.gui_input.connect(_on_section_view_input.bind(node))

	graph_node.gui_input.connect(_on_card_input.bind(graph_node, node))

	add_child(graph_node)
	if not node.property_changed.is_connected(_on_inspectable_node_property_changed):
		node.property_changed.connect(_on_inspectable_node_property_changed.bind(node))

	_sync_position_from_property(node)
	return graph_node


func _on_section_view_input(event: InputEvent, node: InspectableNode) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.double_click or click.button_index != MOUSE_BUTTON_LEFT:
		return

	var project: MonologueProject = ProjectManager.current_project
	var section: StorylineDocument = (
		project.get_storyline(str(node.get_property_value("target"))) if project else null
	)
	if section == null:
		return

	# GraphElement starts dragging in its own _gui_input, which runs after this signal. Taking
	# the event here means opening a section does not also pick it up and carry it.
	accept_event()
	EventBus.request_storyline_inspection.emit.call_deferred(section)


## Set while a press on the graph is being handled (russian-monologue): a selection made with
## the mouse leaves the inspector shut until a double click. Read by the graph container.
var pressed_on_text: bool = false
## The view is about to move to another spot of the same storyline; back/forward remember it.
signal jumped


## One click picks a card, nothing more. A double click on its frame opens its fields on the
## right; on a line's text it writes the line right there (russian-monologue).
func _on_card_input(event: InputEvent, graph_node: GraphNode, node: InspectableNode) -> void:
	var press: InputEventMouseButton = event as InputEventMouseButton
	if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT:
		return
	# a press in the graph: whatever it selects, the inspector waits for a double click
	pressed_on_text = true
	get_tree().create_timer(0.3).timeout.connect(func() -> void: pressed_on_text = false)
	if not press.double_click or node is SectionNode:
		return
	var text: Control = graph_node.get_node_or_null(NodePath(GraphNodeViewFactory.PREVIEW_NAME))
	var on_text: bool = text != null and text.visible and Rect2(text.position, text.size).has_point(press.position)
	accept_event()
	if on_text and node.get_type() == "sentence":
		CardTextEditor.open.call_deferred(graph_node, node)
		return
	var selection: Array[InspectableObject] = [node]
	# the same double click puts the fields away again (russian-monologue)
	var panel: Node = get_tree().get_first_node_in_group(&"inspector_panel")
	if panel:
		panel.toggle.call_deferred(selection)
	else:
		EventBus.request_objects_inspection.emit.call_deferred(selection)


func _on_inspectable_node_property_changed(property_name: String, node: InspectableNode) -> void:
	if property_name == "editor_position":
		if not _is_applying_position:
			_sync_position_from_property(node)
	else:
		refresh_node(node)


func _sync_position_from_property(node: InspectableNode) -> void:
	if not node or not is_instance_valid(node.graph_view):
		return

	# Don't overwrite a position that hasn't been committed yet (active drag)
	if _pending_positions.has(node.graph_view):
		return

	var desired_position: Vector2 = node.get_editor_position()
	if node.graph_view.position_offset == desired_position:
		return

	_is_applying_position = true
	node.graph_view.position_offset = desired_position
	_is_applying_position = false
	mark_lanes_dirty()


func _on_graph_node_position_changed(graph_node: GraphNode) -> void:
	if _is_applying_position:
		return

	_pending_positions[graph_node] = graph_node.position_offset
	mark_lanes_dirty()


func _on_node_selected(graph_node: Node) -> void:
	select_wires([])
	_selected_nodes[graph_node] = true
	var node: InspectableNode = _node_map.get(graph_node)
	if node:
		node_view_selected.emit(node)
	_announce_selection()


func _on_node_deselected(graph_node: Node) -> void:
	_selected_nodes[graph_node] = false
	_announce_selection()


## Every node currently selected, in the order they appear in the graph.
##
## Read from GraphNode.selected, not from a dictionary kept in step with the signals.
## Box-selecting updates the nodes directly, and bookkeeping runs a frame or two behind.
func get_selected_nodes() -> Array[InspectableObject]:
	var nodes: Array[InspectableObject] = []
	for graph_node: Node in get_all_graph_nodes():
		if not (graph_node as GraphNode).selected:
			continue
		var node: InspectableNode = _node_map.get(graph_node)
		if node:
			nodes.append(node)
	return nodes


## Waits for the selection to stop changing before announcing it.
##
## Godot selects nodes one at a time as the rubber band sweeps over them, across several
## frames. Announcing on the first reports a rectangle of ten as a selection of one.
## Announcing on every one rebuilds the inspector ten times.
func _announce_selection() -> void:
	_paint_picked_cards_wires.call_deferred()
	_selection_snapshot = _selected_view_names()
	_settle_selection.call_deferred()


func _settle_selection() -> void:
	var current: Array[StringName] = _selected_view_names()

	# Still growing: come back once it holds still.
	if current != _selection_snapshot:
		_announce_selection()
		return

	if current == _announced_selection:
		return

	_announced_selection = current
	selection_changed.emit(get_selected_nodes())


func _selected_view_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for graph_node: Node in get_all_graph_nodes():
		if (graph_node as GraphNode).selected:
			names.append(graph_node.name)
	return names


## A wire let go over nothing. The property it came from is worked out here, while the
## view is still live: a port index only means something against the row set of the
## moment, and a choice or a section rebuilds its rows as it is edited.
func _on_connection_to_empty(
	from_view_name: StringName, from_port: int, release: Vector2
) -> void:
	var from_node: InspectableNode = get_node_from_view_name(String(from_view_name))
	var from_property: String = get_property_name_at_port(
		String(from_view_name), from_port, true
	)
	if from_node == null or from_property.is_empty():
		Log.warn(
			"Nothing to wire from: port %d of '%s' names no property."
			% [from_port, from_view_name]
		)
		return

	EventBus.enable_picker_mode.emit(
		from_node.get_id(),
		from_property,
		(from_node.graph_view as GraphNode).get_output_port_type(from_port),
		(release + scroll_offset) / zoom
	)


func _on_connection_request(
	from_view_name: StringName, from_port: int, to_view_name: StringName, to_port: int
) -> void:
	var from_node: InspectableNode = get_node_from_view_name(from_view_name)
	var to_node: InspectableNode = get_node_from_view_name(to_view_name)
	var from_graph_node: GraphNode = get_node(from_view_name as String)
	var to_graph_node: GraphNode = get_node(to_view_name as String)
	var from_port_type: int = from_graph_node.get_output_port_type(from_port)
	var to_port_type: int = to_graph_node.get_input_port_type(to_port)

	if not MonologueRegistry.get_instance().is_compatible(from_port_type, to_port_type):
		return

	var from_property_name: String = get_property_name_at_port(
		String(from_view_name), from_port, true
	)
	var to_property_name: String = get_property_name_at_port(String(to_view_name), to_port, false)

	if from_property_name.is_empty() or to_property_name.is_empty():
		push_warning("Cannot create connection: property not found at port")
		return

	var storyline: StorylineDocument = get_storyline()
	var command: NodeConnectionCommand = NodeConnectionCommand.new(
		self,
		str(from_node.get_property_value("id")),
		str(to_node.get_property_value("id")),
		from_property_name,
		to_property_name
	)
	storyline.history.execute(command)


func _has_connection_at_slot(node_name: StringName, port_index: int, is_output: bool) -> bool:
	var node_key: String = "from_node" if is_output else "to_node"
	var port_key: String = "from_port" if is_output else "to_port"
	var target_name: String = String(node_name)

	for connection: Dictionary in get_connection_list():
		if str(connection.get(node_key, "")) != target_name:
			continue
		if str(connection.get(port_key, -1)).to_int() == port_index:
			return true

	return false


## Replays whatever was asked for while a wire was in flight. Deferred a frame so GraphEdit
## has finished with the drop. connection_request fires around the same time, and rebuilding
## underneath it undoes the drop.
func _flush_deferred_refresh() -> void:
	if not _refresh_deferred and _nodes_to_refresh.is_empty():
		return
	_do_flush_deferred_refresh.call_deferred()


func _do_flush_deferred_refresh() -> void:
	var nodes: Array[InspectableObject] = _nodes_to_refresh.duplicate()
	var needs_full_refresh: bool = _refresh_deferred
	_nodes_to_refresh.clear()
	_refresh_deferred = false

	if needs_full_refresh:
		refresh()
		return

	for node: InspectableObject in nodes:
		refresh_node(node as InspectableNode)


func get_all_graph_nodes() -> Array:
	return get_children().filter(func(child: Node) -> bool: return child is GraphNode)


func _reconnect_all_slots() -> void:
	if not connection_manager:
		return

	var storyline: StorylineDocument = get_storyline()
	var all_connections: Array[Dictionary] = connection_manager.get_all_connections()
	_back_wires.clear()
	queue_redraw.call_deferred()
	for view: GraphNode in get_all_graph_nodes():
		for child: Node in view.get_children():
			if child.has_meta(&"jump_link"):
				view.remove_child(child)
				child.queue_free()

	for conn: Dictionary in all_connections:
		var from_node_id: String = conn["from_node_id"]
		var from_property: String = conn["from_property"]
		var to_node_id: String = conn["to_node_id"]
		var to_property: String = conn["to_property"]

		var from_node: InspectableNode = storyline.get_node(from_node_id)
		var to_node: InspectableNode = storyline.get_node(to_node_id)

		if not from_node or not to_node:
			continue

		var from_view_name: String = from_node.graph_view.name
		var to_view_name: String = to_node.graph_view.name

		var from_port: int = get_port_index_for_property(from_view_name, from_property, true)
		var to_port: int = get_port_index_for_property(to_view_name, to_property, false)

		if from_port >= 0 and to_port >= 0:
			# a wire back to the left (to a hub, a scene above) reads as a link on the card
			# instead of a line across the whole graph; the model keeps it (russian-monologue)
			if to_node.graph_view.position_offset.x < from_node.graph_view.position_offset.x - 40.0:
				# a button on the card to go there, and — unless switched off — a dashed arc showing it
				_add_jump_link(from_node, from_property, to_node)
				if ConfigManager.get_config("back_links_as_buttons", false) != true:
					_back_wires.append([from_node.graph_view, from_port, to_node.graph_view, to_port])
			else:
				connect_node(from_view_name, from_port, to_view_name, to_port)
				mark_lanes_dirty()


func _get_visible_properties(node: InspectableNode) -> Array[Property]:
	return node.get_visible_properties()


## is_output counts export ports, otherwise exposed ports. Takes composite names like
## "choices:item_id" for sub-ports.
func get_port_index_for_property(
	node_name: String, property_name: String, is_output: bool = false
) -> int:
	var node: InspectableNode = get_node_from_view_name(node_name)
	if not node:
		return -1

	var rows: Array[GraphNodeRow] = GraphNodeViewFactory._build_rows(node)
	var count: int = 0
	for row: GraphNodeRow in rows:
		var has_port: bool = row._enable_right_port if is_output else row._enable_left_port
		if not has_port:
			continue
		if row.get_connection_name() == property_name:
			return count
		count += 1

	return -1


func get_node_from_view_name(graph_view_name: String) -> InspectableNode:
	var storyline: StorylineDocument = get_storyline()

	for node: InspectableNode in storyline.nodes:
		if node.graph_view.name == graph_view_name:
			return node
	return null


## Composite, as "choices:item_id", for a sub-port.
func get_property_name_at_port(node_name: String, port_index: int, is_output: bool) -> String:
	var node: InspectableNode = get_node_from_view_name(node_name)
	if not node:
		return ""

	var rows: Array[GraphNodeRow] = GraphNodeViewFactory._build_rows(node)
	var count: int = 0
	for row: GraphNodeRow in rows:
		var has_port: bool = row._enable_right_port if is_output else row._enable_left_port
		if not has_port:
			continue
		if count == port_index:
			return row.get_connection_name()
		count += 1
	return ""


func _on_end_node_move() -> void:
	if _pending_positions.is_empty():
		return

	# One node let go on a wire joins the chain there, which a whole selection dropped at
	# once would not say clearly enough.
	var dropped: InspectableNode = null
	if _pending_positions.size() == 1:
		dropped = _node_map.get(_pending_positions.keys()[0])

	_is_applying_position = true

	var storyline: StorylineDocument = get_storyline()
	var history: CommandManager = storyline.history if storyline else null
	if not history:
		_is_applying_position = false
		_pending_positions.clear()
		return

	# One step for the whole gesture. Dragging ten nodes and pressing undo once should put
	# all ten back, not the last one.
	var moved: CommandTransaction = history.begin(
		"Move %d nodes" % _pending_positions.size()
	)

	for graph_node: Variant in _pending_positions.keys():
		if not is_instance_valid(graph_node):
			continue

		var node: InspectableNode = _node_map.get(graph_node)
		if not node:
			continue

		var target_position: Array = [
			_pending_positions[graph_node].x, _pending_positions[graph_node].y
		]
		var position_property: Property = node.get_property("editor_position")
		if not position_property:
			continue
		if not position_property.get_value() is Array:
			position_property.set_value([0.0, 0.0])
		var positon_value: Array = position_property.get_value()
		if positon_value == target_position:
			continue

		var command: PropertyChangeCommand = PropertyChangeCommand.new(
			node, "editor_position", positon_value, target_position
		)
		history.execute(command)

	moved.commit()
	_is_applying_position = false
	_pending_positions.clear()

	# Its own step, so a first undo gives back the wires and a second the drop itself.
	if dropped != null:
		GraphChain.take_drop(self, dropped)


func _on_disconnection_request(
	from_view_name: StringName, from_port: int, to_view_name: StringName, to_port: int
) -> void:
	if not connection_manager:
		return

	var from_node: InspectableNode = get_node_from_view_name(from_view_name)
	var to_node: InspectableNode = get_node_from_view_name(to_view_name)

	# No port-type check here on purpose. Connecting only requires the two types to be
	# *compatible*, so requiring them to be equal here would leave links that cannot be
	# undone.
	var from_property_name: String = get_property_name_at_port(
		String(from_view_name), from_port, true
	)
	var to_property_name: String = get_property_name_at_port(String(to_view_name), to_port, false)

	if from_property_name.is_empty() or to_property_name.is_empty():
		push_warning("Cannot remove connection: property not found at port")
		return

	# The last argument is what makes this a disconnection. Without it the command connects
	# instead, and pulling a wire off an input port reattaches it. The command unregisters
	# from the model itself, so there is deliberately no unregister_connection() call.
	var storyline: StorylineDocument = get_storyline()
	var command: NodeConnectionCommand = NodeConnectionCommand.new(
		self,
		str(from_node.get_property_value("id")),
		str(to_node.get_property_value("id")),
		from_property_name,
		to_property_name,
		true
	)

	_disconnecting = true
	storyline.history.execute(command)

	# GraphEdit filed this wire under the very names and ports it just handed us. The
	# command works those out again from the property names, which is what undo needs but
	# can miss here, and a wire it misses stays drawn for the whole drag.
	if is_node_connected(from_view_name, from_port, to_view_name, to_port):
		disconnect_node(from_view_name, from_port, to_view_name, to_port)
		mark_lanes_dirty()

	_finish_disconnect.call_deferred()


## Run once GraphEdit has had its say. Whatever the disconnect asked to redraw happens
## now, or waits again when it started a drag, since a rebuild mid-drag has the same cost.
func _finish_disconnect() -> void:
	_disconnecting = false
	_flush_deferred_refresh()


## A right click takes the wire it is aimed at, and offers what can be done to the
## selection when it is aimed at nothing.
func _on_popup_request(at_position: Vector2) -> void:
	var wire: NodeConnection = wire_at(at_position)
	if wire != null:
		_cut_wires([wire])
		return

	# a right click on a card is about that card: it becomes the selection (russian-monologue)
	var card: GraphNode = _card_at(at_position)
	if card and not card.selected:
		set_selected(card)
	_offer_on_selection(at_position, card)


## The card under a point of the graph, or null over empty canvas.
func _card_at(at_position: Vector2) -> GraphNode:
	var point: Vector2 = get_global_transform() * at_position
	for child: Node in get_children():
		if child is GraphNode and (child as GraphNode).visible and (child as GraphNode).get_global_rect().has_point(point):
			return child as GraphNode
	return null


## «Add a node…» from a right click (russian-monologue). On a card, the new card stands to its
## right, wired to the card's first output that leads nowhere yet; on empty canvas, where clicked.
func _add_node_from(card: GraphNode, at_position: Vector2) -> void:
	var node: InspectableNode = get_node_from_view_name(String(card.name)) if card else null
	if node == null:
		EventBus.enable_picker_mode.emit("", "", 0, (at_position + scroll_offset) / zoom)
		return
	var storyline: StorylineDocument = get_storyline()
	for port: int in card.get_output_port_count():
		var property: String = get_property_name_at_port(String(card.name), port, true)
		if property.is_empty():
			continue
		var taken: bool = false
		for wire: NodeConnection in storyline.connections:
			if wire.from_node_id == node.get_id() and wire.get_from_name() == property:
				taken = true
				break
		if not taken:
			var port_at: Vector2 = card.position_offset + card.get_output_port_position(port)
			EventBus.enable_picker_mode.emit(node.get_id(), property, card.get_output_port_type(port),
				port_at + Vector2(110, 0))
			return
	EventBus.enable_picker_mode.emit("", "", 0, card.position_offset + Vector2(card.size.x + 110, 0))


## The wire under a point, or null when the point is aimed at none. GraphEdit answers in
## view names and port numbers, which is not what a wire is stored as.
func wire_at(at_position: Vector2, reach: float = WIRE_REACH) -> NodeConnection:
	var found: Dictionary = get_closest_connection_at_point(at_position, reach)
	var storyline: StorylineDocument = get_storyline()
	if found.is_empty() or storyline == null:
		return null

	var from_node: InspectableNode = get_node_from_view_name(str(found["from_node"]))
	var to_node: InspectableNode = get_node_from_view_name(str(found["to_node"]))
	if from_node == null or to_node == null:
		return null

	var from_property: String = get_property_name_at_port(
		str(found["from_node"]), int(found["from_port"]), true
	)
	var to_property: String = get_property_name_at_port(
		str(found["to_node"]), int(found["to_port"]), false
	)
	if from_property.is_empty() or to_property.is_empty():
		return null

	for wire: NodeConnection in storyline.connections:
		if wire.from_node_id != from_node.get_id() or wire.to_node_id != to_node.get_id():
			continue
		if wire.get_from_name() == from_property and wire.get_to_name() == to_property:
			return wire
	return null


## Wires the user picked, in the order they picked them.
func get_selected_wires() -> Array[NodeConnection]:
	return _selected_wires.duplicate()


## Picks these wires and drops whatever was picked before.
##
## Drawn with GraphEdit's activity tint, the one per-wire colour it lets anyone set. A
## badge or an icon would need a layer of our own, and that is a road already walked.
func select_wires(wires: Array[NodeConnection]) -> void:
	for wire: NodeConnection in _selected_wires:
		_paint_wire(wire, 0.0)

	_selected_wires.assign(wires)
	for wire: NodeConnection in _selected_wires:
		_paint_wire(wire, 1.0)


## A left click takes the wire under it, and mnl_delete cuts whatever is taken.
##
## Caught on the gui_input signal, which Godot emits before GraphEdit's own handling, so
## a taken press never reaches the box selection.
func _on_graph_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("mnl_delete") and not _selected_wires.is_empty():
		_cut_wires(_selected_wires)
		accept_event()
		return

	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	# Not while a wire is in flight, and not over a node: there the press means the node,
	# whatever happens to pass behind it.
	if views_are_busy() or _over_a_node(click.position):
		return

	var wire: NodeConnection = wire_at(click.position)
	# a double click on empty canvas puts the fields panel away (russian-monologue)
	if click.double_click and wire == null:
		var panel: Node = get_tree().get_first_node_in_group(&"inspector_panel")
		if panel and panel.visible:
			panel.close()
			accept_event()
			return
	if wire == null:
		select_wires([])
		return

	select_wires(_picked_with(click, wire))
	set_selected(null)
	accept_event()


## What the picked set becomes. Holding the modifier adds a wire or takes it back out,
## the way it already does for nodes.
func _picked_with(
	click: InputEventMouseButton, wire: NodeConnection
) -> Array[NodeConnection]:
	if not click.is_command_or_control_pressed():
		return [wire]

	var taken: Array[NodeConnection] = _selected_wires.duplicate()
	if taken.has(wire):
		taken.erase(wire)
	else:
		taken.append(wire)
	return taken


## True when a point is over a node.
func _over_a_node(at_position: Vector2) -> bool:
	for view: GraphNode in get_all_graph_nodes():
		if Rect2(view.position, view.size * zoom).has_point(at_position):
			return true
	return false


func _paint_wire(wire: NodeConnection, amount: float) -> void:
	var from_port: int = get_port_index_for_property(
		wire.from_node_id, wire.get_from_name(), true
	)
	var to_port: int = get_port_index_for_property(wire.to_node_id, wire.get_to_name(), false)
	if from_port < 0 or to_port < 0:
		Log.warn("No port answers to '%s' or '%s'." % [wire.get_from_name(), wire.get_to_name()])
		return

	# set_connection_activity walks its own list and gives up in silence when nothing
	# matches, which looks exactly like a wire that refuses to light up.
	if not is_node_connected(wire.from_node_id, from_port, wire.to_node_id, to_port):
		Log.warn(
			"The canvas holds no wire from '%s' port %d to '%s' port %d."
			% [wire.from_node_id, from_port, wire.to_node_id, to_port]
		)
		return

	set_connection_activity(wire.from_node_id, from_port, wire.to_node_id, to_port, amount)


## Rebuilding the canvas makes every wire afresh, so the picked ones have to be drawn
## again. One that went with the rebuild is not picked any more.
func _repaint_wire_selection() -> void:
	var storyline: StorylineDocument = get_storyline()
	var still_here: Array[NodeConnection] = []
	if storyline != null:
		for wire: NodeConnection in _selected_wires:
			if storyline.connections.has(wire):
				still_here.append(wire)

	_selected_wires.assign(still_here)
	for wire: NodeConnection in _selected_wires:
		_paint_wire(wire, 1.0)
	_paint_picked_cards_wires()


## The wires into and out of the picked cards are drawn red, both sides (russian-monologue);
## the rest go back to plain, except the wires picked on their own.
func _paint_picked_cards_wires() -> void:
	var storyline: StorylineDocument = get_storyline()
	if storyline == null:
		return
	var picked: Dictionary = {}
	for name: StringName in _selected_view_names():
		picked[String(name)] = true
	for wire: NodeConnection in storyline.connections:
		var lit: bool = picked.has(wire.from_node_id) or picked.has(wire.to_node_id) or _selected_wires.has(wire)
		var from_port: int = get_port_index_for_property(wire.from_node_id, wire.get_from_name(), true)
		var to_port: int = get_port_index_for_property(wire.to_node_id, wire.get_to_name(), false)
		if from_port >= 0 and to_port >= 0 and is_node_connected(wire.from_node_id, from_port, wire.to_node_id, to_port):
			set_connection_activity(wire.from_node_id, from_port, wire.to_node_id, to_port, 1.0 if lit else 0.0)


## Wires named by both their ends, so the ones aimed at are the ones that go even when
## they share a port with others. One step for the lot.
func _cut_wires(wires: Array[NodeConnection]) -> void:
	var storyline: StorylineDocument = get_storyline()
	if storyline == null or wires.is_empty():
		return

	# Copied first: dropping the picked set below empties the very array being walked.
	var going: Array[NodeConnection] = wires.duplicate()
	# Dropped before the cut, so the tint comes off wires that are still there to take it.
	select_wires([])

	var cut: CommandTransaction = storyline.history.begin("Cut %d wires" % going.size())
	for wire: NodeConnection in going:
		storyline.history.execute(
			NodeConnectionCommand.new(
				self,
				wire.from_node_id,
				wire.to_node_id,
				wire.get_from_name(),
				wire.get_to_name(),
				true
			)
		)
	cut.commit()
	refresh()


## A right-click menu a size up from the theme's (russian-monologue): larger type, roomier rows,
## and the same for every submenu in it.
static func roomy_menu(menu: PopupMenu) -> void:
	menu.add_theme_font_size_override(&"font_size", 16)
	menu.add_theme_constant_override(&"v_separation", 12)
	menu.add_theme_constant_override(&"item_start_padding", 14)
	menu.add_theme_constant_override(&"item_end_padding", 18)
	for child: Node in menu.get_children():
		if child is PopupMenu:
			roomy_menu(child as PopupMenu)


## Built each time and freed with the popup, since what it offers depends on the selection.
func _offer_on_selection(at_position: Vector2, card: GraphNode = null) -> void:
	var selection: Array[InspectableNode] = _user_owned(_selected_model_nodes())
	var menu: PopupMenu = PopupMenu.new()
	menu.add_item(tr("Add a node…"), OFFER_ADD_NODE)
	# a condition on the card under the pointer, as its add-on offers them (russian-monologue)
	var under: InspectableNode = get_node_from_view_name(String(card.name)) if card else null
	var offers: Array = CardTags.offers_of(under) if under else []
	if not offers.is_empty():
		var conditions: PopupMenu = PopupMenu.new()
		for index: int in offers.size():
			conditions.add_item(str(offers[index].get("text", "")), index)
		conditions.id_pressed.connect(func(index: int) -> void:
			get_tree().create_timer(0.08).timeout.connect(func() -> void:
				if is_instance_valid(card):
					CardTags.open_editor(card, under, offers[index].get("tag", {}))))
		menu.add_child(conditions)
		menu.add_submenu_node_item(tr("Add a condition"), conditions)
	# and to each answer of a choice: «Условие ответа» › «1. Кто такой Пушкин?» › …
	if under and card:
		var answers: PopupMenu = PopupMenu.new()
		var number: int = 0
		for list_property: Property in under.get_properties():
			if list_property.type != "collection" or not list_property.get_value() is Array:
				continue
			for item: Variant in list_property.get_value():
				if not item is Dictionary:
					continue
				var item_offers: Array = CardTags.item_offers(under, list_property.name, str(item.get("id", "")))
				if item_offers.is_empty():
					continue
				number += 1
				var one: PopupMenu = PopupMenu.new()
				CardTags.fill_offer_menu(one, card, under, item_offers)
				answers.add_child(one)
				answers.add_submenu_node_item("%d. %s" % [number, NodePreview.trim(Util.to_label(item.get("text", "")), 40)], one)
		if number > 0:
			menu.add_child(answers)
			menu.add_submenu_node_item(tr("Add a condition to an answer"), answers)
	if selection.is_empty():
		menu.id_pressed.connect(func(_offer: int) -> void: _add_node_from(card, at_position))
		menu.popup_hide.connect(menu.queue_free)
		add_child(menu)
		roomy_menu(menu)
		menu.position = Vector2i(get_screen_position() + at_position)
		menu.popup()
		return
	menu.add_separator()
	menu.add_item("Extract into a Section", OFFER_EXTRACT)
	menu.add_item("Remove, Keeping the Chain", OFFER_BRIDGE_OUT)
	menu.add_item("Save as template…", OFFER_TEMPLATE)
	# colour the card, or the whole branch that runs on from it (russian-monologue)
	menu.add_separator()
	# a submenu must be the menu's own child before it is attached, or Godot falls over
	for whole: bool in [false, true]:
		var colours: PopupMenu = _colour_menu(selection, whole)
		menu.add_child(colours)
		menu.add_submenu_node_item(tr("Branch colour") if whole else tr("Card colour"), colours)
	# into one of the writer's collections (russian-monologue)
	var folders: Array = Bookmarks.folder_paths()
	if not folders.is_empty():
		var into: PopupMenu = PopupMenu.new()
		into.name = "into"
		for index: int in folders.size():
			into.add_item(str(folders[index][1]), index)
		into.id_pressed.connect(func(index: int) -> void:
			for node: InspectableNode in selection:
				Bookmarks.add_item(str(folders[index][0]), {"kind": "node", "storyline": storyline_id, "node": node.get_id()}))
		menu.add_child(into)
		menu.add_submenu_node_item(tr("Add to a collection"), into)
	menu.id_pressed.connect(func(offer: int) -> void:
		if offer == OFFER_ADD_NODE:
			_add_node_from(card, at_position)
		else:
			_on_offer_chosen(offer, selection))
	menu.popup_hide.connect(menu.queue_free)
	add_child(menu)
	roomy_menu(menu)

	menu.position = Vector2i(get_screen_position() + at_position)
	menu.popup()


func _on_offer_chosen(offer: int, selection: Array[InspectableNode]) -> void:
	if offer == OFFER_EXTRACT:
		_extract_into_section(selection)
	elif offer == OFFER_BRIDGE_OUT:
		_remove_keeping_chain(selection)
	elif offer == OFFER_TEMPLATE:
		_ask_template_name(selection)


## A small dialog for the template's name (russian-monologue); saved into the project.
func _ask_template_name(selection: Array[InspectableNode]) -> void:
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = tr("Save as template…")
	var name_edit: LineEdit = LineEdit.new()
	name_edit.placeholder_text = tr("Template name")
	name_edit.custom_minimum_size.x = 320
	dialog.add_child(name_edit)
	dialog.register_text_enter(name_edit)
	dialog.confirmed.connect(func() -> void:
		var template_name: String = name_edit.text.strip_edges()
		if not template_name.is_empty():
			GraphTemplates.save(ProjectManager.current_project, get_storyline(), selection, template_name)
			Log.info(tr("Template saved: %s") % template_name))
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
	name_edit.grab_focus()


## Takes the nodes out and joins what fed them to what they fed. Asks first when a section
## would go with them, the same as an outright delete.
func _remove_keeping_chain(selection: Array[InspectableNode]) -> void:
	var going: Array[StorylineDocument] = DeleteNodesCommand.sections_run_by(selection)
	if going.is_empty():
		GraphChain.bridge_out(self, selection, going)
		return

	EventBus.ask_dialog.emit(
		_on_bridge_out_confirmed.bind(selection, going),
		"Are you sure?",
		_what_goes_too(going)
	)


func _on_bridge_out_confirmed(
	response: int, selection: Array[InspectableNode], going: Array[StorylineDocument]
) -> void:
	if response == Prompt.CONFIRMED:
		GraphChain.bridge_out(self, selection, going)


func _extract_into_section(selection: Array[InspectableNode]) -> void:
	var storyline: StorylineDocument = get_storyline()
	if storyline == null:
		return

	var refused: String = ExtractSectionCommand.refuse_reason(storyline, selection)
	if not refused.is_empty():
		Log.warn(refused)
		return

	storyline.history.execute(ExtractSectionCommand.new(storyline_id, selection))
	refresh()


## The nodes of a selection the user actually owns. A storyline creates its own root and
## keeps it. Copying it would make a second one, deleting it would leave no way in.
func _user_owned(nodes: Array[InspectableNode]) -> Array[InspectableNode]:
	var owned: Array[InspectableNode] = []
	for node: InspectableNode in nodes:
		if node and not NodeIndexer.is_permanent(node):
			owned.append(node)
	return owned


## Every node currently selected, whatever the graph's own bookkeeping says.
func _selected_model_nodes() -> Array[InspectableNode]:
	var nodes: Array[InspectableNode] = []
	for graph_node: Node in get_children():
		if graph_node is GraphNode and _selected_nodes.get(graph_node, false):
			var node: InspectableNode = _node_map.get(graph_node)
			if node:
				nodes.append(node)
	return nodes


func _on_copy_nodes_request() -> void:
	_copied_nodes.clear()

	for source_node: InspectableNode in _user_owned(_selected_model_nodes()):
		_copied_nodes.append(source_node.duplicate(true))


## Copied again on every paste, so pasting twice makes two nodes rather than handing the
## same one back. What was pasted becomes the clipboard, so a run of pastes walks away
## from the original instead of stacking in one place.
func _on_paste_nodes_request() -> void:
	var storyline: StorylineDocument = get_storyline()
	if storyline == null or _copied_nodes.is_empty():
		return

	var pasted: Array = []
	for copied: InspectableNode in _copied_nodes:
		pasted.append(copied.duplicate(true))

	storyline.history.execute(AddNodesCommand.new(storyline_id, pasted))
	_copied_nodes = pasted


func _on_cut_nodes_request() -> void:
	_copied_nodes.clear()

	var nodes_to_delete: Array[InspectableNode] = _user_owned(_selected_model_nodes())
	if nodes_to_delete.is_empty():
		return

	for source_node: InspectableNode in nodes_to_delete:
		_copied_nodes.append(source_node.duplicate(true))

	var storyline: StorylineDocument = get_storyline()
	storyline.history.execute(DeleteNodesCommand.new(storyline_id, nodes_to_delete))


func _on_delete_nodes_request(graph_nodes: Array[StringName]) -> void:
	var nodes: Array[InspectableNode] = []
	for node_name: StringName in graph_nodes:
		var graph_node: GraphNode = get_node("%s" % node_name)
		var node: InspectableNode = _node_map.get(graph_node)
		if node:
			nodes.append(node)

	var removable: Array[InspectableNode] = _user_owned(nodes)
	if removable.is_empty():
		return

	# A section is a graph of its own, so losing one is worth a question. Anything else
	# goes on the spot, undo being the answer to a delete one did not mean.
	var going: Array[StorylineDocument] = DeleteNodesCommand.sections_run_by(removable)
	if going.is_empty():
		_delete_nodes(removable, going)
		return

	EventBus.ask_dialog.emit(
		_on_delete_confirmed.bind(removable, going),
		"Are you sure?",
		_what_goes_too(going)
	)


func _on_delete_confirmed(
	response: int, removable: Array[InspectableNode], going: Array[StorylineDocument]
) -> void:
	if response == Prompt.CONFIRMED:
		_delete_nodes(removable, going)


func _delete_nodes(
	removable: Array[InspectableNode], going: Array[StorylineDocument]
) -> void:
	var storyline: StorylineDocument = get_storyline()
	storyline.history.execute(DeleteNodesCommand.new(storyline_id, removable, going))
	refresh()


## What a delete costs beyond the nodes picked, so the question can be answered.
static func _what_goes_too(sections: Array[StorylineDocument]) -> String:
	var named: PackedStringArray = []
	var held: int = 0
	for section: StorylineDocument in sections:
		named.append("'%s'" % section.name)
		held += section.nodes.size()

	if named.size() == 1:
		return TranslationServer.translate("The section %s goes too, with the nodes in it: %d.") % [named[0], held]
	return TranslationServer.translate("The sections %s go too, with the nodes in them: %d.") % [", ".join(named), held]


## «↩ hub» (or «Уйти. ↩ hub» for an option) at the bottom of the card; pressing it goes there.
func _add_jump_link(from_node: InspectableNode, from_property: String, to_node: InspectableNode) -> void:
	# the scene's key, «end» for an end node, else the node's own label — never a bare id
	var target: String = str(to_node.get_property_value("label"))
	if to_node.get_type() == "genius_scene":
		target = str(to_node.call("card_title")) if to_node.has_method("card_title") else str(to_node.get_property_value("key"))
	elif to_node.get_type() == "end":
		target = tr("End")
	elif target.is_empty() or target == to_node.get_id():
		target = tr(Util.to_readable_name(to_node.get_type()))
	var prefix: String = ""
	if from_property.contains(NodeConnection.ITEM_SEPARATOR):
		var item_id: String = from_property.get_slice(NodeConnection.ITEM_SEPARATOR, 1).trim_prefix(NodeConnection.EXTERNAL_PREFIX)
		var options: Variant = from_node.get_property_value("choices")
		if options is Array:
			for option: Variant in options:
				if option is Dictionary and str(option.get("id", "")) == item_id:
					prefix = NodePreview.trim(Util.to_label(option.get("text", {}), ProjectManager.current_project.active_language_code), 22) + "  "
	var link: Button = Button.new()
	link.set_meta(&"jump_link", true)
	link.text = "%s↩ %s" % [prefix, target]
	link.tooltip_text = tr("Go to %s") % target
	link.flat = true
	link.alignment = HORIZONTAL_ALIGNMENT_LEFT
	link.focus_mode = Control.FOCUS_NONE
	link.mouse_filter = Control.MOUSE_FILTER_STOP
	link.add_theme_font_size_override("font_size", 12)
	link.add_theme_color_override("font_color", Color("#d77a6a"))
	var target_view: GraphNode = to_node.graph_view
	link.pressed.connect(go_to.bind(target_view))
	from_node.graph_view.add_child(link)


## Text on the cards drawn from a distance field (russian-monologue): it stays sharp at any
## zoom, where a plain font is a picture of letters stretched with the canvas. The GPU does
## the work; each glyph is prepared once. Only the graph: panels keep the hinted font.
func _use_scalable_font() -> void:
	var source: FontFile = load("res://ui/assets/fonts/sources/Inter-Regular.ttf").duplicate()
	source.multichannel_signed_distance_field = true
	source.msdf_pixel_range = 16
	source.msdf_size = 64
	var font: FontVariation = FontVariation.new()
	font.base_font = source
	font.fallbacks = ThemeLayout.font_main.fallbacks
	var scalable: Theme = Theme.new()
	scalable.default_font = font
	theme = scalable


# ---------- colouring cards and branches (russian-monologue) ----------

const CARD_COLOURS: Array = [
	["Red", "#c0504d"], ["Orange", "#d9822b"], ["Yellow", "#c9b03a"], ["Green", "#5a9e4b"],
	["Teal", "#3a9e9a"], ["Blue", "#4a78c2"], ["Purple", "#8a5cc2"], ["Pink", "#c25c95"],
	["Grey", "#8a8a8a"],
]


func _colour_menu(selection: Array[InspectableNode], whole_branch: bool) -> PopupMenu:
	var menu: PopupMenu = PopupMenu.new()
	for index: int in CARD_COLOURS.size():
		var swatch: Image = Image.create(14, 14, false, Image.FORMAT_RGBA8)
		swatch.fill(Color(CARD_COLOURS[index][1]))
		menu.add_icon_item(ImageTexture.create_from_image(swatch), tr(CARD_COLOURS[index][0]), index)
	menu.add_separator()
	menu.add_item(tr("No colour"), CARD_COLOURS.size())
	menu.id_pressed.connect(func(id: int) -> void:
		var colour: String = "#00000000" if id >= CARD_COLOURS.size() else str(CARD_COLOURS[id][1])
		var targets: Array[InspectableNode] = _branch_of(selection) if whole_branch else selection
		var history: CommandManager = get_storyline().history
		var step: CommandTransaction = history.begin("Colour %d cards" % targets.size())
		for node: InspectableNode in targets:
			node.set_property_value("node_color", colour)
		step.commit())
	return menu


## The cards that run on from these: everything after them that is reached only through them,
## up to where the story joins something else (a card with a way in from outside).
func _branch_of(start: Array[InspectableNode]) -> Array[InspectableNode]:
	var storyline: StorylineDocument = get_storyline()
	var inside: Dictionary = {}
	for node: InspectableNode in start:
		inside[node.get_id()] = node
	var grew: bool = true
	while grew:
		grew = false
		for c: NodeConnection in storyline.connections:
			if not inside.has(c.from_node_id) or inside.has(c.to_node_id):
				continue
			var ways_in: Array = storyline.connections.filter(
				func(k: NodeConnection) -> bool: return k.to_node_id == c.to_node_id)
			if ways_in.all(func(k: NodeConnection) -> bool: return inside.has(k.from_node_id)):
				var next: InspectableNode = storyline.get_node(c.to_node_id)
				if next:
					inside[next.get_id()] = next
					grew = true
	var found: Array[InspectableNode] = []
	found.assign(inside.values())
	return found


# ---------- wires back to the left, drawn as thin dashed arcs (russian-monologue) ----------
# A real wire back across the graph would cross every card on the way. These are drawn under the
# cards instead, faint, with an arrow at the end; the selected card's own ones light up.

## [from_view, from_port, to_view, to_port] for each wire drawn this way.
var _back_wires: Array = []
var _back_wires_hooked: bool = false


func _hook_back_wire_redraws() -> void:
	if _back_wires_hooked:
		return
	_back_wires_hooked = true
	scroll_offset_changed.connect(func(_o: Vector2) -> void: queue_redraw())
	node_selected.connect(func(_n: Node) -> void: queue_redraw())
	node_deselected.connect(func(_n: Node) -> void: queue_redraw())
	gui_input.connect(_on_arc_input)
	child_entered_tree.connect(func(child: Node) -> void:
		if child is GraphNode:
			(child as GraphNode).position_offset_changed.connect(queue_redraw))


## Each drawn arc's points, with its two ends, for clicking on it: [points, from_view, to_view].
var _arcs: Array = []


func _draw() -> void:
	_hook_back_wire_redraws()
	_arcs.clear()
	if _back_wires.is_empty():
		return
	for wire: Array in _back_wires:
		var from_view: GraphNode = wire[0]
		var to_view: GraphNode = wire[2]
		if not is_instance_valid(from_view) or not is_instance_valid(to_view):
			continue
		if wire[1] >= from_view.get_output_port_count() or wire[3] >= to_view.get_input_port_count():
			continue
		var start: Vector2 = from_view.position + from_view.get_output_port_position(wire[1]) * zoom
		var end: Vector2 = to_view.position + to_view.get_input_port_position(wire[3]) * zoom
		var lit: bool = from_view.selected or to_view.selected
		var colour: Color = ThemeLayout.accent_color.lightened(0.25) if lit else Color(1, 1, 1, 0.22)
		_arcs.append([_dashed_arc(start, end, colour, (2.0 if lit else 1.2) * zoom), from_view, to_view])


## An S-shaped arc out of the right of one card and into the left of another, dashed, with
## an arrowhead at the card it leads to.
func _dashed_arc(start: Vector2, end: Vector2, colour: Color, width: float) -> PackedVector2Array:
	var reach: float = maxf(80.0 * zoom, absf(start.y - end.y) * 0.25)
	var c1: Vector2 = start + Vector2(reach, 0)
	var c2: Vector2 = end - Vector2(reach, 0)
	var points: PackedVector2Array = PackedVector2Array()
	var steps: int = 48
	for i: int in steps + 1:
		var t: float = float(i) / steps
		var u: float = 1.0 - t
		points.append(u * u * u * start + 3.0 * u * u * t * c1 + 3.0 * u * t * t * c2 + t * t * t * end)
	# dashes laid along the curve's length
	var dash: float = 7.0 * zoom
	var gap: float = 5.0 * zoom
	var drawing: bool = true
	var left: float = dash
	for i: int in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var length: float = a.distance_to(b)
		var done: float = 0.0
		while done < length:
			var step: float = minf(left, length - done)
			var p: Vector2 = a.lerp(b, done / length)
			var q: Vector2 = a.lerp(b, (done + step) / length)
			if drawing:
				draw_line(p, q, colour, width, true)
			done += step
			left -= step
			if left <= 0.0:
				drawing = not drawing
				left = dash if drawing else gap
	# the arrow, pointing into the card it leads to
	var tip: Vector2 = end
	var back: Vector2 = (points[points.size() - 3] - tip).normalized()
	var side: Vector2 = Vector2(-back.y, back.x)
	var size: float = 7.0 * zoom
	draw_colored_polygon(PackedVector2Array([tip, tip + back * size + side * size * 0.55, tip + back * size - side * size * 0.55]), colour)
	return points


## The arc under the pointer, as [points, from_view, to_view, where along it 0..1], or [].
func _arc_at(at: Vector2) -> Array:
	var reach: float = 7.0
	for arc: Array in _arcs:
		var points: PackedVector2Array = arc[0]
		for i: int in points.size() - 1:
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(at, points[i], points[i + 1])
			if near.distance_to(at) <= reach:
				return [points, arc[1], arc[2], float(i) / maxf(1.0, points.size() - 1)]
	return []


## A click on a dashed arc goes to its far end: the card it leads to, or, clicked near the
## arrow, back to where it starts. The hand cursor says it can be clicked.
func _on_arc_input(event: InputEvent) -> void:
	if _arcs.is_empty():
		return
	# an arc that runs under a card is not there to be clicked: the card is (a click on a card's
	# title used to jump far away along the arc beneath it)
	if event is InputEventMouseMotion:
		var over_arc: bool = _card_at(event.position) == null and not _arc_at(event.position).is_empty()
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over_arc else Control.CURSOR_ARROW
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if _card_at(click.position) != null:
		return
	var hit: Array = _arc_at(click.position)
	if hit.is_empty():
		return
	accept_event()
	go_to(hit[2] if hit[3] < 0.85 else hit[1])


## Brings a card to the middle of the view and picks it; back/forward remember where we were.
func go_to(view: GraphNode) -> void:
	if not is_instance_valid(view):
		return
	jumped.emit()
	# a pick on the graph: the fields stay shut, as for any single click
	pressed_on_text = true
	get_tree().create_timer(0.3).timeout.connect(func() -> void: pressed_on_text = false)
	set_selected(view)
	_glide_to(view)
	flash(view)


## How close a jump brings the card: its own size, never further in than the user already is.
const JUMP_ZOOM: float = 1.0
var _glide_tween: Tween


## Slides and zooms the view gently onto [param view]'s card, rather than snapping
## (russian-monologue).
func _glide_to(view: GraphNode) -> void:
	var centre: Vector2 = view.position_offset + view.size / 2.0
	var from_zoom: float = zoom
	var to_zoom: float = clampf(maxf(zoom, JUMP_ZOOM), zoom_min, zoom_max)
	# the point of the graph now in the middle of the view, in graph coordinates
	var from_centre: Vector2 = (scroll_offset + size / 2.0) / zoom
	if _glide_tween:
		_glide_tween.kill()
	_glide_tween = create_tween()
	_glide_tween.tween_method(func(t: float) -> void:
		zoom = lerpf(from_zoom, to_zoom, t)
		scroll_offset = from_centre.lerp(centre, t) * zoom - size / 2.0,
		0.0, 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## The card jumped to, marked in red like a selected card until the next click on the graph
## elsewhere (russian-monologue). It used to blink; a steady mark is easier to find again.
const MARK_RED: Color = Color("#d9534a")
var _marked: GraphNode


func flash(view: GraphNode) -> void:
	_unmark()
	if not is_instance_valid(view):
		return
	_marked = view
	for style_name: StringName in [&"panel", &"panel_selected"]:
		var base: StyleBox = view.get_theme_stylebox(style_name)
		if base is StyleBoxFlat:
			var box: StyleBoxFlat = (base as StyleBoxFlat).duplicate()
			box.border_color = MARK_RED
			box.set_border_width_all(2)
			view.add_theme_stylebox_override(style_name, box)
	view.set_meta(&"marked", true)


## Gives the card back its own edge: the tint it was given, or the theme's.
func _unmark() -> void:
	if is_instance_valid(_marked) and _marked.has_meta(&"marked"):
		_marked.remove_meta(&"marked")
		var node: InspectableNode = get_node_from_view_name(String(_marked.name))
		if node:
			refresh_node(node)
	_marked = null


## A click anywhere on the graph but the marked card takes the mark away.
func _input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or not is_instance_valid(_marked) or not is_visible_in_tree():
		return
	if not get_global_rect().has_point(click.global_position):
		return
	if _marked.get_global_rect().has_point(click.global_position):
		return
	_unmark.call_deferred()


## Brings [param node]'s card into view and flashes it, once its storyline is on the graph:
## for jumps from search, «where used» and problems, where the storyline may still be loading.
static func reveal(node: InspectableNode) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for _i: int in 30:
		await tree.process_frame
		if node == null or not is_instance_valid(node.graph_view) or not node.graph_view.is_inside_tree():
			continue
		var graph: MonologueGraphEdit = node.graph_view.get_parent() as MonologueGraphEdit
		if graph == null or graph.size.x <= 0.0 or node.graph_view.size.x <= 0.0:
			continue
		graph.go_to(node.graph_view)
		return


# ---------- laying the cards out (russian-monologue) ----------
# Left to right in the order the story goes: each column one step further. The cards a card's
# rows lead to stand in a column in the order of those rows, each level with its row where there
# is room, so the first answer's card is on top. Wires back to an earlier card do not count as a
# step. «Tight» packs the columns close; «roomy» leaves wide lanes so the wires run between the
# cards instead of in one bundle. One undo step.

func lay_out(roomy: bool) -> void:
	var storyline: StorylineDocument = get_storyline()
	if storyline == null:
		return
	var gap_x: float = 150.0 if roomy else 60.0
	var gap_y: float = 70.0 if roomy else 22.0
	var cards: Array[InspectableNode] = []
	for node: InspectableNode in storyline.nodes:
		if node.get_type() != "note" and is_instance_valid(node.graph_view):
			cards.append(node)
	if cards.is_empty():
		return
	var ids: Dictionary = {}
	for node: InspectableNode in cards:
		ids[node.get_id()] = node
	# the wires out of each card, in the order of its rows: [to_id, port]
	var outs: Dictionary = {}
	for c: NodeConnection in storyline.connections:
		if not ids.has(c.from_node_id) or not ids.has(c.to_node_id):
			continue
		var from_view: GraphNode = (ids[c.from_node_id] as InspectableNode).graph_view
		var port: int = get_port_index_for_property(from_view.name, c.get_from_name(), true)
		(outs.get_or_add(c.from_node_id, []) as Array).append([c.to_node_id, port])
	for list: Variant in outs.values():
		(list as Array).sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	# starts: the root first, then cards nothing leads to (reached from the game's code), top down
	var has_in: Dictionary = {}
	for list: Variant in outs.values():
		for edge: Array in list:
			has_in[edge[0]] = true
	var starts: Array[InspectableNode] = []
	starts.assign(cards.filter(func(n: InspectableNode) -> bool: return not has_in.has(n.get_id())))
	starts.sort_custom(func(a: InspectableNode, b: InspectableNode) -> bool:
		if (a.get_type() == "root") != (b.get_type() == "root"):
			return a.get_type() == "root"
		return a.graph_view.position_offset.y < b.graph_view.position_offset.y)
	# walk the story; a wire back to a card still on the way is a loop, not a step
	var state: Dictionary = {}
	var order: Array[String] = []
	var back: Dictionary = {}
	var walk: Callable = func(this: Callable, id: String) -> void:
		state[id] = 1
		for edge: Array in outs.get(id, []):
			var to: String = edge[0]
			if state.get(to, 0) == 1:
				back["%s>%s" % [id, to]] = true
			elif state.get(to, 0) == 0:
				this.call(this, to)
		state[id] = 2
		order.push_front(id)
	for start: InspectableNode in starts:
		if state.get(start.get_id(), 0) == 0:
			walk.call(walk, start.get_id())
	for node: InspectableNode in cards:  # a loop with no way in from outside
		if state.get(node.get_id(), 0) == 0:
			walk.call(walk, node.get_id())
	# each card's column: one past the furthest card leading to it
	var column: Dictionary = {}
	for id: String in order:
		column[id] = column.get(id, 0)
		for edge: Array in outs.get(id, []):
			if not back.has("%s>%s" % [id, edge[0]]):
				column[edge[0]] = maxi(column.get(edge[0], 0), column[id] + 1)
	var columns: Array = []
	for id: String in order:
		while columns.size() <= column[id]:
			columns.append([])
	# who leads to each card, through which row: the first such parent places it
	var parents: Dictionary = {}
	for id: String in order:
		for edge: Array in outs.get(id, []):
			if not back.has("%s>%s" % [id, edge[0]]):
				(parents.get_or_add(edge[0], []) as Array).append([id, edge[1]])
	var place: Dictionary = {}  # id -> Vector2
	var rank_in_column: Dictionary = {}
	var x: float = 0.0
	for c: int in columns.size():
		var here: Array = []
		for id: String in order:
			if column[id] == c:
				here.append(id)
		# in the order of the parents above them, then of the rows they hang from
		here.sort_custom(func(a: String, b: String) -> bool: return _lay_key(a, parents, rank_in_column, starts) < _lay_key(b, parents, rank_in_column, starts))
		var width: float = 0.0
		var bottom: float = -INF
		for i: int in here.size():
			var id: String = here[i]
			rank_in_column[id] = i
			var view: GraphNode = (ids[id] as InspectableNode).graph_view
			var want: float = bottom + gap_y if bottom > -INF else 0.0
			# level with the row it hangs from
			var from: Array = (parents.get(id, []) as Array)
			if not from.is_empty() and place.has(from[0][0]):
				var parent_view: GraphNode = (ids[from[0][0]] as InspectableNode).graph_view
				var row_y: float = place[from[0][0]].y
				if from[0][1] >= 0 and from[0][1] < parent_view.get_output_port_count():
					row_y += parent_view.get_output_port_position(from[0][1]).y
				var into: float = view.get_input_port_position(0).y if view.get_input_port_count() > 0 else 0.0
				want = maxf(want, row_y - into)
			place[id] = Vector2(x, want)
			bottom = want + view.size.y
			width = maxf(width, view.size.x)
		x += width + gap_x
	# keep the start where it was, so the view does not jump
	var anchor_id: String = starts[0].get_id() if not starts.is_empty() else order[0]
	var shift: Vector2 = (ids[anchor_id] as InspectableNode).graph_view.position_offset - place[anchor_id]
	var history: CommandManager = storyline.history
	var step: CommandTransaction = history.begin("Lay out %d cards" % place.size())
	for id: String in place:
		var node: InspectableNode = ids[id]
		var to: Vector2 = (place[id] + shift).snapped(Vector2(10, 10))
		var was: Variant = node.get_property_value("editor_position")
		var now: Array = [to.x, to.y]
		if was == now:
			continue
		history.execute(PropertyChangeCommand.new(node, "editor_position", was if was is Array else [0.0, 0.0], now))
	step.commit()
	queue_redraw()


## Where a card goes in its column: under the parent placed highest, by the row it hangs from;
## a start by its turn among the starts.
static func _lay_key(id: String, parents: Dictionary, rank: Dictionary, starts: Array[InspectableNode]) -> int:
	var best: int = 1 << 30
	for p: Array in parents.get(id, []):
		if rank.has(p[0]):
			best = mini(best, int(rank[p[0]]) * 1000 + maxi(int(p[1]), 0))
	if best == 1 << 30:
		for i: int in starts.size():
			if starts[i].get_id() == id:
				return (1 << 29) + i
	return best
