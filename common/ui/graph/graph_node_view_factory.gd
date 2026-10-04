class_name GraphNodeViewFactory extends RefCounted

const SLOT_IN_TEXTURE: Texture2D = preload("res://ui/assets/icons/slot_in.svg")
const SLOT_OUT_TEXTURE: Texture2D = preload("res://ui/assets/icons/slot_out.svg")
## The preview panel, named so that a value changing can replace it without the rest of the
## view being torn down around it.
const PREVIEW_NAME: StringName = &"Preview"
## As tall as a preview is ever drawn, whatever it decided to build.
const PREVIEW_MAX_HEIGHT: float = 180.0
## How much of a list item's name a node shows. The whole of it, wrapped onto more lines
## (russian-monologue); the cap only guards against a pasted page.
const MAX_LIST_LABEL: int = 400
## Titles longer than this wrap onto a second line, at about this width.
const TITLE_WRAP_AT: int = 24
const TITLE_WRAP_WIDTH: float = 210.0
## Any other row longer than this wraps too, at this width, instead of pushing the card wider
## and wider or being cut off (russian-monologue).
const ROW_WRAP_AT: int = 34
const ROW_WRAP_WIDTH: float = 300.0
## How far a list item's type is faded behind the properties framing it.
const LIST_LABEL_ALPHA: float = 0.5


static func build(node: InspectableNode) -> GraphNode:
	var graph_node: GraphNode = GraphNode.new()
	graph_node.custom_minimum_size.x = 192
	graph_node.draggable = true
	graph_node.selectable = true
	graph_node.resizable = false
	apply_metadata(graph_node, node)
	populate(graph_node, node)
	return graph_node


static func populate(graph_node: GraphNode, node: InspectableNode) -> void:
	if not is_instance_valid(graph_node):
		return

	apply_metadata(graph_node, node)

	for child: Control in graph_node.get_children():
		graph_node.remove_child(child)
		child.queue_free()

	if graph_node.has_method("clear_all_slots"):
		graph_node.clear_all_slots()

	var title_bar: HBoxContainer = graph_node.get_titlebar_hbox()
	if title_bar:
		title_bar.hide()

	# the card's own colour, if one was picked: the whole card in a dark tone of it, so the light
	# text stays readable whatever was picked, and a band of the colour itself on top
	var tint_value: Variant = node.get_property_value("node_color")
	var tint: Color = Color(str(tint_value)) if tint_value != null and str(tint_value) != "" else Color(0, 0, 0, 0)
	for style_name: StringName in [&"panel", &"panel_selected"]:
		graph_node.remove_theme_stylebox_override(style_name)
		if tint.a > 0.0:
			var base: StyleBox = graph_node.get_theme_stylebox(style_name)
			if base is StyleBoxFlat:
				var tinted: StyleBoxFlat = base.duplicate()
				tinted.bg_color = readable_fill(tint, (base as StyleBoxFlat).bg_color)
				if style_name == &"panel":
					tinted.border_color = tint
				tinted.border_width_top = maxi(tinted.border_width_top, 3)
				graph_node.add_theme_stylebox_override(style_name, tinted)

	var rows: Array[GraphNodeRow] = _build_rows(node)
	for idx: int in rows.size():
		var row: GraphNodeRow = rows[idx]
		var container: HBoxContainer = HBoxContainer.new()
		container.mouse_filter = Control.MOUSE_FILTER_PASS
		container.theme_type_variation = "GraphNodeViewRownHBox"

		var key_label: Label = Label.new()
		key_label.mouse_filter = Control.MOUSE_FILTER_PASS
		key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key_label.text = row.get_key()
		# a sentence's card is headed by who speaks — «БАБА НЮРА», «РАССКАЗЧИК» — rather than by
		# «Sentence»; the narrator's lines then read as description at a glance (russian-monologue)
		if idx == 0 and node.get_type() == "sentence":
			var who: String = _speaker_name(node)
			if not who.is_empty():
				key_label.text = who
		# a node can name its own card, as an episode does with its title
		elif idx == 0 and node.has_method("card_title"):
			var own: String = str(node.call("card_title"))
			if not own.is_empty():
				key_label.text = own
		# a long title goes onto a second line instead of stretching the card (russian-monologue)
		if idx == 0 and key_label.text.length() > TITLE_WRAP_AT:
			key_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			key_label.custom_minimum_size.x = TITLE_WRAP_WIDTH
		elif idx > 0 and key_label.text.length() > ROW_WRAP_AT:
			key_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			key_label.custom_minimum_size.x = ROW_WRAP_WIDTH

		var value_label: Label = Label.new()
		value_label.mouse_filter = Control.MOUSE_FILTER_PASS
		# What a row gives back is the informative half when the two differ: an empty reroute
		# reads "any", and one with something plugged in reads what it is carrying.
		var shown_label: String = (
			row.output_type_label if not row.output_type_label.is_empty()
			else row.get_type_label()
		)
		# The port's type is for whoever wires things, not for whoever reads the card: the flow
		# («ход») is said by the dot alone, and an unwired field says nothing. A wired one keeps
		# its type, which then tells what came in (russian-monologue).
		var says_type: bool = shown_label and shown_label != "context" and _row_has_wire(row, node)
		if says_type:
			var port_word: String = TranslationServer.translate("port " + shown_label)
			value_label.text = "[%s]" % (port_word if port_word != "port " + shown_label else shown_label)

		var slot_color: Color = NodePort.color_of(row.get_type())

		value_label.label_settings = LabelSettings.new()
		value_label.label_settings.font_color = slot_color
		# a field nothing is wired into says what it holds, «кто говорит  РАССКАЗЧИК», instead of
		# its port type (russian-monologue)
		var value_text: String = _row_value_text(row, node)
		if not value_text.is_empty():
			value_label.text = value_text
			value_label.label_settings.font_color = Color(slot_color, 0.85)

		if idx == 0:
			key_label.theme_type_variation = "GraphNodeViewTitleLabel"
			if tint.a > 0.0:
				var dot: Panel = Panel.new()
				dot.custom_minimum_size = Vector2(8, 8)
				dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				dot.mouse_filter = Control.MOUSE_FILTER_PASS
				var dot_style: StyleBoxFlat = StyleBoxFlat.new()
				dot_style.bg_color = tint
				dot_style.set_corner_radius_all(4)
				dot.add_theme_stylebox_override(&"panel", dot_style)
				container.add_child(dot)
		value_label.theme_type_variation = "GraphNodeViewValueLabel"

		# What a list holds is the node's contents rather than its shape, so it reads
		# behind the properties that frame it.
		if not row.sub_property_id.is_empty():
			key_label.theme_type_variation = "GraphNodeViewListLabel"
			value_label.label_settings.font_color = Color(slot_color, LIST_LABEL_ALPHA)

		# how the card reads (russian-monologue): the title on a band of its own, each answer or
		# branch on a plate of its own, «если:» in colour, the fallback row set apart
		var is_item: bool = not row.sub_property_id.is_empty()
		var own_prop: Property = node.get_property(row.get_connection_name())
		var is_fallback: bool = idx > 0 and not is_item and node.has_method("numbered_rows") \
			and row.get_connection_name() in (node.call("numbered_rows") as Array) \
			and own_prop != null and own_prop.type != "collection"
		var shown: Control = key_label
		if is_item or is_fallback:
			shown = _coloured_row_label(key_label, is_fallback)
		# the title is told apart by one fine line under it, nothing more: hierarchy by type and
		# colour, not by boxes (russian-monologue)
		if idx == 0 and rows.size() > 1:
			container.draw.connect(_draw_title_rule.bind(container, graph_node))
		if idx == 0 and tint.a <= 0.0 and type_hue(node.get_type()).a > 0.0:
			container.draw.connect(_draw_type_strip.bind(container, graph_node, type_hue(node.get_type())))

		container.add_child(shown)
		# a small «→» on a wired answer or branch: goes to the card it leads to, however far
		# (russian-monologue)
		if (is_item or is_fallback) and _row_has_wire(row, node):
			var go: Button = _go_button(node, row.get_connection_name())
			container.add_child(go)
			# shown while the pointer is over its row: a clean card until you reach for it
			go.modulate.a = 0.0
			container.mouse_entered.connect(func() -> void: go.modulate.a = 1.0)
			container.mouse_exited.connect(func() -> void:
				if not Rect2(Vector2.ZERO, container.size).has_point(container.get_local_mouse_position()):
					go.modulate.a = 0.0)
		container.add_child(value_label)
		graph_node.add_child(container)

		if row.port_size == "large":
			container.custom_minimum_size.y = 32

		var type_id: int = row.port_type_id
		if type_id == 0:
			type_id = MonologueRegistry.get_instance().get_field_type_id(row.get_type())
		# The two sides are typed apart so that a reroute can take in anything and still give
		# back only what it was given.
		var out_type_id: int = row.output_type_id if row.output_type_id != 0 else type_id
		var out_color: Color = (
			row.output_color if row.output_color != Color.TRANSPARENT else slot_color
		)
		graph_node.set_slot(
			idx,
			row._enable_left_port,
			type_id,
			slot_color,
			row._enable_right_port,
			out_type_id,
			out_color,
			SLOT_IN_TEXTURE,
			SLOT_OUT_TEXTURE,
			true
		)

		graph_node.set_slot_custom_icon_left(idx, SLOT_IN_TEXTURE)
		graph_node.set_slot_custom_icon_right(idx, SLOT_OUT_TEXTURE)

	_add_preview(graph_node, node)

	# reset_size() shrinks to the minimum size directly. set_size(Vector2.ZERO) got
	# there too, but left the node at zero until the next layout pass, and any port
	# position read during that window was meaningless.
	graph_node.reset_size()


## Replaces the preview without touching anything else. The ports keep their indices, so
## the wires hanging off them are never disturbed.
static func refresh_preview(graph_node: GraphNode, node: InspectableNode) -> void:
	if not is_instance_valid(graph_node):
		return

	var showing: Node = graph_node.get_node_or_null(NodePath(PREVIEW_NAME))
	if showing:
		graph_node.remove_child(showing)
		showing.queue_free()

	_add_preview(graph_node, node)
	graph_node.reset_size()


## Draws what the node holds under its ports, when it has anything to show.
##
## Clipped rather than fitted: the preview gets whatever width the ports above it already
## gave the node and is cut where that runs out, so no node is ever made wider by one, nor
## taller than [constant PREVIEW_MAX_HEIGHT] however much its preview decided to draw.
static func _add_preview(graph_node: GraphNode, node: InspectableNode) -> void:
	var preview: Control = node._build_preview(_language())
	if preview == null:
		return

	var panel: PanelContainer = PanelContainer.new()
	panel.name = PREVIEW_NAME
	panel.theme_type_variation = "GraphNodeViewPreviewPanel"
	# a line is written on the card itself; every other kind of step shows its box in a dark tone
	# of its own, so it reads at a glance as «not a line» and as which step it is (russian-monologue)
	if node.get_type() != "sentence":
		var box: StyleBox = panel.get_theme_stylebox(&"panel", &"GraphNodeViewPreviewPanel")
		if box is StyleBoxFlat:
			var tinted: StyleBoxFlat = box.duplicate()
			tinted.bg_color = preview_tone(node.get_type())
			panel.add_theme_stylebox_override(&"panel", tinted)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS

	# A plain Control rather than a container: it does not grow to hold what is inside it,
	# which is the whole of how a preview is kept from deciding how big its node is.
	var window: Control = Control.new()
	window.clip_contents = true
	window.mouse_filter = Control.MOUSE_FILTER_PASS
	window.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	window.custom_minimum_size.y = clampf(
		preview.custom_minimum_size.y, NodePreview.LINE_HEIGHT, PREVIEW_MAX_HEIGHT
	)

	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	window.add_child(preview)
	panel.add_child(window)
	graph_node.add_child(panel)
	# wrapped text knows its height only once it has the card's width: the window then grows to
	# show all of it, still never wider than the card (russian-monologue)
	var fit: Callable = func() -> void:
		if not is_instance_valid(preview) or not is_instance_valid(window):
			return
		# before the card has its width the text measures as a narrow column; wait for it
		if window.size.x < 40.0:
			return
		var tall: float = clampf(preview.get_combined_minimum_size().y, NodePreview.LINE_HEIGHT, PREVIEW_MAX_HEIGHT)
		if not is_equal_approx(tall, window.custom_minimum_size.y):
			var shrinks: bool = tall < window.custom_minimum_size.y
			window.custom_minimum_size.y = tall
			# a card grows by itself but never gives height back: hand it back
			if shrinks and is_instance_valid(graph_node):
				graph_node.reset_size.call_deferred()
	window.resized.connect(fit, CONNECT_DEFERRED)
	preview.minimum_size_changed.connect(fit, CONNECT_DEFERRED)


static func _language() -> String:
	var project: MonologueProject = ProjectManager.current_project
	return project.active_language_code if project else ""


## Names the view after the node's id and titles it with the node's own title,
## falling back to the type name when the title is blank.
static func apply_metadata(graph_node: GraphNode, node: InspectableNode) -> void:
	if not is_instance_valid(graph_node):
		return
	graph_node.title = str(node.get_property_value("label"))
	var id_prop: Property = node.get_property("id")
	graph_node.name = str(id_prop.get_value()) if id_prop else _derive_node_name(node)


static func _build_rows(node: InspectableNode) -> Array[GraphNodeRow]:
	var rows: Array[GraphNodeRow] = []
	# compact cards (russian-monologue): the title, what is wired and the preview — no idle rows.
	# Ports are counted from these same rows, so wires stay on the right ports.
	var is_compact: bool = ConfigManager.get_config("compact_cards", false) == true
	var filled: bool = _is_filled(node)
	for prop: Property in node.get_properties():
		if not prop.is_visible_in_graph():
			continue

		var row: GraphNodeRow = _build_property_row(prop, node)
		# a node can word a row itself, as a fork's «иначе» says where it leads (russian-monologue)
		if node.has_method("row_text"):
			var own: String = str(node.call("row_text", prop.name))
			if not own.is_empty():
				row._key = own
		if prop.get_settings_value("is_main_property"):
			rows.push_front(row)
			continue
		# A row that only takes a wire in is a hint for a blank card — what can go here. Once the
		# card holds something, it goes; rows a wire leaves from, and wired rows, always stay
		# (russian-monologue). Compact cards drop every idle row.
		var wired: bool = _row_has_wire(row, node)
		var hint_only: bool = not row._enable_right_port and filled
		if wired or (not is_compact and not hint_only):
			rows.append(row)

		if prop.type == "collection":
			for sub_row: GraphNodeRow in _build_list_sub_rows(node, prop):
				if not is_compact or _row_has_wire(sub_row, node):
					rows.append(sub_row)

	_number_rows(rows, node)
	return rows


## Rows that are tried or offered in order get their place written in front: a choice's answers
## as the player sees them, 1. 2. 3., a fork's branches in the order they are tried, «иначе»
## last (russian-monologue). A node lists the properties to number with [code]numbered_rows()[/code].
static func _number_rows(rows: Array[GraphNodeRow], node: InspectableNode) -> void:
	var numbered: Array = ["choices"] if node.get_type() == "choice" else []
	if node.has_method("numbered_rows"):
		numbered = node.call("numbered_rows")
	if numbered.is_empty():
		return
	var number: int = 0
	for row: GraphNodeRow in rows:
		var is_item: bool = not row.sub_property_id.is_empty()
		var name: String = row.sub_property_id.get_slice(NodeConnection.ITEM_SEPARATOR, 0) if is_item else row.get_connection_name()
		if not name in numbered:
			continue
		var prop: Property = node.get_property(name)
		# a list's own heading row is not one of its items
		if not is_item and prop != null and prop.type == "collection":
			continue
		number += 1
		row._key = "%d. %s" % [number, row._key.strip_edges()]


static func _row_has_wire(row: GraphNodeRow, node: InspectableNode) -> bool:
	if node == null or node.storyline_id.is_empty() or ProjectManager.current_project == null:
		return false
	var storyline: StorylineDocument = ProjectManager.current_project.get_storyline(node.storyline_id)
	if storyline == null:
		return false
	var node_id: String = node.get_id()
	var name: String = row.get_connection_name()
	for connection: NodeConnection in storyline.connections:
		if connection.from_node_id == node_id and connection.get_from_name() == name:
			return true
		if connection.to_node_id == node_id and connection.get_to_name() == name:
			return true
	return false


static func _build_property_row(prop: Property, owner: InspectableNode) -> GraphNodeRow:
	var enable_left: bool = prop.get_settings_value("exposed", false) == true
	var enable_right: bool = prop.get_settings_value("export", false) == true
	# a label given with .label() is how the field wants to be called, here too (russian-monologue)
	var has_label: bool = not str(prop.get_settings_value(PropertySettings.KEY_LABEL, "")).is_empty()
	var label: String = (
		prop.get_display_name() if prop.get_settings_value("is_main_property") or has_label else prop.name
	)
	# A collection port accepts whatever its items' main property exports, so that an
	# option node can be plugged into a choice node's option list.
	# TODO: do the same for `list` properties, whose port type is still just "list".
	var row_type: String = prop.type
	if prop.type == "collection":
		var collection_name: String = prop.get_settings_value(PropertySettings.KEY_COLLECTION, "")
		var indexer: CollectionIndexer = MonologueRegistry.get_instance().get_collection(
			collection_name
		)
		if indexer and not indexer.port_type.is_empty():
			row_type = indexer.port_type
	var row: GraphNodeRow = GraphNodeRow.new(label, row_type, enable_left, enable_right)
	row._property_name = prop.name
	row.port_size = prop.get_settings_value(PropertySettings.KEY_PORT_SIZE, "normal")

	# What a node takes in is what it declares. What it gives back may be something it is
	# only carrying. The two are one row for every node but a reroute.
	var taken: Dictionary = NodePort.declared(owner, prop)
	var given: Dictionary = NodePort.of(owner, prop)
	row.port_type_id = int(taken["type_id"])
	row.type_label = str(taken["label"])

	if int(given["type_id"]) != int(taken["type_id"]):
		row.output_type_id = int(given["type_id"])
		row.output_type_label = str(given["label"])
		row.output_color = given["color"]
	return row


static func _build_list_sub_rows(node: InspectableNode, prop: Property) -> Array[GraphNodeRow]:
	var sub_rows: Array[GraphNodeRow] = []
	var coll_name: String = prop.get_settings_value(PropertySettings.KEY_COLLECTION, "")
	if coll_name.is_empty():
		return sub_rows

	var probe: CollectionItem = MonologueRegistry.get_instance().create_collection_item(
		coll_name, CommandManager.new()
	)
	if not probe or not probe.has_main_property():
		return sub_rows

	var indexer: CollectionIndexer = MonologueRegistry.get_instance().get_collection(coll_name)
	var label_property: String = indexer.label_property if indexer else "name"

	# Internal items from the property value
	var list_value: Variant = prop.get_value()
	if list_value is Array:
		for item_index: int in list_value.size():
			var item_data: Variant = list_value[item_index]
			if not item_data is Dictionary:
				continue
			var item_id: String = _extract_dict_string(item_data, "id")
			if item_id.is_empty():
				continue
			var sub_label: String = "  %s" % _shorten(
				_item_label(item_data, label_property, probe.get_type(), item_index)
			)
			var sub_row: GraphNodeRow = GraphNodeRow.new(sub_label, "context", false, true)
			sub_row.sub_property_id = "%s%s%s" % [
				prop.name, NodeConnection.ITEM_SEPARATOR, item_id
			]
			sub_rows.append(sub_row)

	# External items (e.g. connected OptionNodes)
	var externals: Array[Dictionary] = node.get_external_list_items(prop.name)
	for ext_index: int in externals.size():
		var ext_data: Dictionary = externals[ext_index]
		var ext_name: String = ext_data.get("name", "")
		var ext_src_id: String = ext_data.get("source_node_id", "")
		if ext_src_id.is_empty():
			continue
		if ext_name.is_empty():
			# numbered on from the options the node holds itself
			var held: int = (prop.get_value() as Array).size() if prop.get_value() is Array else 0
			ext_name = "%s %d" % [tr_type(probe.get_type()), held + ext_index + 1]
		var sub_label: String = "  %s" % _shorten(ext_name)
		var sub_row: GraphNodeRow = GraphNodeRow.new(sub_label, "context", false, true)
		sub_row.sub_property_id = "%s%s%s%s" % [
			prop.name, NodeConnection.ITEM_SEPARATOR, NodeConnection.EXTERNAL_PREFIX, ext_src_id
		]
		sub_rows.append(sub_row)

	return sub_rows


## «→»: brings the card that [param from_name] on [param node] is wired to into view and
## flashes it; ← in the top bar comes back.
static func _go_button(node: InspectableNode, from_name: String) -> Button:
	var go: Button = Button.new()
	go.text = "→"
	go.flat = true
	go.focus_mode = Control.FOCUS_NONE
	go.mouse_filter = Control.MOUSE_FILTER_STOP
	go.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.custom_minimum_size = Vector2(20, 18)
	go.tooltip_text = TranslationServer.translate("Go to the card this leads to")
	go.add_theme_font_size_override(&"font_size", 13)
	go.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.35))
	go.add_theme_color_override(&"font_hover_color", Color(ROW_HOVER_COLOUR))
	go.pressed.connect(func() -> void:
		var view: GraphNode = node.graph_view
		var graph: MonologueGraphEdit = view.get_parent() as MonologueGraphEdit if is_instance_valid(view) else null
		var storyline: StorylineDocument = ProjectManager.current_project.get_storyline(node.storyline_id) if ProjectManager.current_project else null
		if graph == null or storyline == null:
			return
		for connection: NodeConnection in storyline.connections:
			if connection.from_node_id == node.get_id() and connection.get_from_name() == from_name:
				var target: InspectableNode = storyline.get_node(connection.to_node_id)
				if target and is_instance_valid(target.graph_view):
					graph.go_to(target.graph_view)
				return)
	return go


## The colours of a card's rows (russian-monologue).
## Three steps of light grey, as dark interfaces do it: what the row says ~65% white, its
## bookkeeping (number, «если:») ~40%. Red is kept for what can be pressed or is picked.
const ROW_NUMBER_COLOUR: String = "#6c6c6c"
const ROW_IF_COLOUR: String = "#7a7a7a"
const ROW_TEXT_COLOUR: Color = Color("#a8a8a8")
const ROW_FALLBACK_COLOUR: Color = Color("#858585")
const ROW_HOVER_COLOUR: String = "#d77a6a"


## A row's words with its number brighter and «если:» in colour; wraps as the plain label did.
static func _coloured_row_label(plain_label: Label, fallback: bool) -> RichTextLabel:
	var text: String = plain_label.text
	var number: String = ""
	var cut: int = text.find(". ")
	if cut > 0 and cut <= 3 and text.substr(0, cut).is_valid_int():
		number = text.substr(0, cut + 1)
		text = text.substr(cut + 2)
	var words: String = NodePreview.plain(text)
	for lead: String in ["если:", "иначе:"]:
		if text.begins_with(lead):
			words = "[color=%s]%s[/color]%s" % [ROW_IF_COLOUR, lead, NodePreview.plain(text.substr(lead.length()))]
	if fallback:
		words = "[i]%s[/i]" % words
	var label: RichTextLabel = RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = ("[color=%s]%s[/color] " % [ROW_NUMBER_COLOUR, number] if not number.is_empty() else "") + words
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_color_override(&"default_color", ROW_FALLBACK_COLOUR if fallback else ROW_TEXT_COLOUR)
	for size_name: StringName in [&"normal_font_size", &"italics_font_size"]:
		label.add_theme_font_size_override(size_name, ThemeLayout.font_size_md)
	if plain_label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = plain_label.custom_minimum_size.x
	else:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
	plain_label.free()
	return label


## A fine line under the title, across the row, halfway into the gap below it.
static func _draw_title_rule(row: Control, graph_node: GraphNode) -> void:
	var y: float = row.size.y + float(graph_node.get_theme_constant(&"separation")) / 2.0
	row.draw_line(Vector2(0, y), Vector2(row.size.x, y), Color(1, 1, 1, 0.08), 1.0)


## What kind of step a card is, at a glance: a thin strip of its muted hue along the top edge,
## as node editors colour a node's header by its kind. Lines have none: they are the story itself.
static func _draw_type_strip(row: Control, graph_node: GraphNode, hue: Color) -> void:
	var titlebar: Control = graph_node.get_titlebar_hbox()
	var top: float = -row.position.y + (titlebar.size.y if titlebar else 0.0)
	var inset: float = float(ThemeLayout.radius_md)
	row.draw_rect(Rect2(-row.position.x + inset, top + 1.0, graph_node.size.x - inset * 2.0, 2.0), hue)


## A kind's hue for the strip: the same hue its box is shown in, lighter and quieter.
static func type_hue(type_name: String) -> Color:
	if not PREVIEW_HUES.has(type_name):
		return Color(0, 0, 0, 0)
	return Color.from_hsv(float(PREVIEW_HUES[type_name]), 0.38, 0.62, 0.9)


## Cuts a list item's name down to what a node has room for, since the name is written
## with no thought for how wide the node it lands in is.
static func _shorten(label: String) -> String:
	if label.length() <= MAX_LIST_LABEL:
		return label
	return "%s…" % label.substr(0, MAX_LIST_LABEL - 1).strip_edges(false, true)


static func _extract_dict_string(data: Dictionary, key: String) -> String:
	return str(data.get(key, ""))


## How one list item is named in the graph. Falls back to its type and position rather
## than its id: an id says nothing to the person reading the node.
static func _item_label(
	item_data: Dictionary, label_property: String, type_name: String, item_index: int
) -> String:
	var project: MonologueProject = ProjectManager.current_project
	var value: Variant = item_data.get(label_property)
	# a condition reads as itself, «если: дверь выбита», not as its first field (russian-monologue)
	if value is Dictionary and (value as Dictionary).has("checks"):
		var test: String = NodePreview.condition(value, project)
		return TranslationServer.translate("if: %s") % test if not test.is_empty() else TranslationServer.translate("if: —")
	var label: String = Util.to_label(value, project.active_language_code if project else "")
	if not label.is_empty():
		return label
	return "%s %d" % [tr_type(type_name), item_index + 1]


## A type's readable name in the interface language, in the short form a numbered label wants
## ("Option #" → "Вариант"), else the plain one.
static func tr_type(type_name: String) -> String:
	var readable: String = Util.to_readable_name(type_name)
	var short: String = TranslationServer.translate(readable + " #")
	return short if short != readable + " #" else TranslationServer.translate(readable)


## Returns the node's id, allocating one when it somehow has none.
static func _derive_node_name(node: InspectableNode) -> String:
	var id_value: String = ""
	var id_property: Property = node.get_property("id")
	if id_property:
		id_value = str(id_property.get_value())
	if id_value.is_empty():
		id_value = IDGen.generate_object_id(node.get_type())
	return id_value


## What an unwired field holds, for its row on the card; "" keeps the port type showing.
## Text is left to the preview, which shows it whole.
static func _row_value_text(row: GraphNodeRow, node: InspectableNode) -> String:
	if node == null or row == null or not row.sub_property_id.is_empty() or _row_has_wire(row, node):
		return ""
	var prop: Property = node.get_property(row._property_name if not row._property_name.is_empty() else row.get_key())
	if prop == null or prop.is_main_property():
		return ""
	var value: Variant = prop.get_value()
	match prop.type:
		"reference":
			var scope: String = str(prop.get_settings_value(PropertySettings.KEY_REFERENCE_SCOPE, ""))
			var label_property: String = str(prop.get_settings_value(PropertySettings.KEY_LABEL_PROPERTY, ReferenceResolver.DEFAULT_LABEL_PROPERTY))
			var label: String = ReferenceResolver.resolve_label(ProjectManager.current_project, scope, str(value) if value != null else "", node, label_property)
			return NodePreview.trim(label, 20) if not label.is_empty() else "—"
		"dropdown":
			return TranslationServer.translate(str(value)) if value != null and str(value) != "" else "—"
		"int":
			return str(int(value)) if value != null else ""
		"float":
			return str(snappedf(float(value), 0.01)) if value != null else ""
		"bool":
			return TranslationServer.translate("yes") if bool(value) else TranslationServer.translate("no")
	return ""


static func _speaker_name(node: InspectableNode) -> String:
	var prop: Property = node.get_property("speaker")
	if prop == null:
		return ""
	var scope: String = str(prop.get_settings_value(PropertySettings.KEY_REFERENCE_SCOPE, "characters"))
	return ReferenceResolver.resolve_label(ProjectManager.current_project, scope, str(prop.get_value()), node)


## Whether a node holds anything yet: a field drawn on the card with a non-empty value. A fresh
## node says no, and so shows every row as a hint.
static func _is_filled(node: InspectableNode) -> bool:
	for prop: Property in node.get_properties():
		if not prop.is_visible_in_graph() or prop.is_main_property():
			continue
		var value: Variant = prop.get_value()
		# what a new node starts with is not something written into it
		if prop.default_value != null and value == prop.default_value:
			continue
		match typeof(value):
			TYPE_NIL:
				continue
			TYPE_STRING, TYPE_STRING_NAME:
				if not str(value).is_empty():
					return true
			TYPE_DICTIONARY:
				if not Util.to_label(value, "").is_empty() and not (value as Dictionary).is_empty():
					return true
			TYPE_ARRAY:
				if not (value as Array).is_empty():
					return true
			TYPE_BOOL:
				if value:
					return true
			TYPE_INT, TYPE_FLOAT:
				if value != 0:
					return true
	return false


## A colour turned into a card's background: same hue, toned down to a dark shade, so the
## light text on it reads as well as on an uncoloured card.
static func readable_fill(tint: Color, base: Color) -> Color:
	var fill: Color = base.lerp(tint, 0.32)
	var limit: float = maxf(base.get_luminance() + 0.1, 0.24)
	while fill.get_luminance() > limit:
		fill = fill.darkened(0.08)
	fill.a = 1.0
	return fill


## Hues for kinds of step that are not lines; any other kind gets one from its name.
const PREVIEW_HUES: Dictionary = {
	"genius_code": 0.75, "action": 0.75, "event": 0.75,
	"variable": 0.47, "inventory": 0.08,
	"genius_scene": 0.6, "genius_fork": 0.11, "condition": 0.11,
	"genius_after": 0.33, "genius_phase": 0.9, "choice": 0.16,
}


## The dark tone a kind of step's box is shown in: its hue, kept dark enough for light text.
static func preview_tone(type_name: String) -> Color:
	var hue: float = float(PREVIEW_HUES[type_name]) if PREVIEW_HUES.has(type_name) else fmod(absf(float(type_name.hash())) / 1000.0, 1.0)
	return Color.from_hsv(hue, 0.42, 0.2)
