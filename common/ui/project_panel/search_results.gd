## What the search box over the project list finds (russian-monologue). Takes the list's place
## while there is a query: storylines whose name fits first, then the places in the story, grouped
## by storyline — who speaks, and the words of the line with the query's words picked out.
## A click opens the place on the graph.
class_name SearchResults
extends ScrollContainer

const MAX_SHOWN: int = 200

var _list: VBoxContainer
var _query: String = ""


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	add_child(_list)
	hide()


func show_for(query: String) -> void:
	_query = query.strip_edges()
	for child: Node in _list.get_children():
		child.queue_free()
	if _query.is_empty():
		hide()
		return
	show()
	scroll_vertical = 0

	var words: PackedStringArray = ProjectSearch.words_of(_query)
	var found: Dictionary = ProjectSearch.run(ProjectManager.current_project, _query, MAX_SHOWN)
	var storylines: Array = found["storylines"]
	var hits: Array = found["hits"]

	if storylines.is_empty() and hits.is_empty():
		_add_note(tr("Nothing found. Every word must be somewhere in the line, the speaker or the storyline's name."))
		return

	_add_note(_summary(storylines.size(), hits.size()))

	for storyline: StorylineDocument in storylines:
		_list.add_child(_storyline_row(storyline, words))

	var current: StorylineDocument = null
	for hit: Dictionary in hits:
		if hit["storyline"] != current:
			current = hit["storyline"]
			_list.add_child(_group_header(current, hits.filter(func(h: Dictionary) -> bool: return h["storyline"] == current).size()))
		_list.add_child(_hit_card(hit, words))


func _summary(storyline_count: int, hit_count: int) -> String:
	var parts: PackedStringArray = []
	if storyline_count > 0:
		parts.append(tr("storylines: %d") % storyline_count)
	if hit_count > 0:
		parts.append((tr("places: %d+") if hit_count >= MAX_SHOWN else tr("places: %d")) % hit_count)
	return " · ".join(parts)


func _add_note(text: String) -> void:
	var note: Label = Label.new()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", ThemeLayout.text_muted_color)
	note.add_theme_font_size_override("font_size", ThemeLayout.font_size_sm)
	_list.add_child(note)


func _storyline_row(storyline: StorylineDocument, words: PackedStringArray) -> Control:
	var card: PanelContainer = _card()
	var text: RichTextLabel = _rich("▤  " + ProjectSearch.snippet(_short(storyline.name), words, ThemeLayout.accent_color.lightened(0.35)))
	card.add_child(text)
	card.gui_input.connect(_on_card_input.bind(storyline, null))
	return card


func _group_header(storyline: StorylineDocument, count: int) -> Control:
	var header: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = storyline.name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_color_override("font_color", ThemeLayout.text_muted_color)
	title.add_theme_font_size_override("font_size", ThemeLayout.font_size_sm)
	header.add_child(title)
	var pill: Label = Label.new()
	pill.text = str(count)
	pill.add_theme_color_override("font_color", ThemeLayout.text_muted_color)
	pill.add_theme_font_size_override("font_size", ThemeLayout.font_size_sm)
	header.add_child(pill)
	var gap: MarginContainer = MarginContainer.new()
	gap.add_theme_constant_override("margin_top", 6)
	gap.add_child(header)
	return gap


func _hit_card(hit: Dictionary, words: PackedStringArray) -> Control:
	var card: PanelContainer = _card()
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)

	var node: InspectableNode = hit["node"]
	var who: String = str(hit["speaker"])
	var head: String = who if not who.is_empty() else _type_name(node)
	if not str(hit["field"]).is_empty():
		head += "  ·  " + str(hit["field"])
	var title: RichTextLabel = _rich(ProjectSearch.snippet(head, words, ThemeLayout.accent_color.lightened(0.35), 60))
	title.add_theme_color_override("default_color", ThemeLayout.text_muted_color)
	title.add_theme_font_size_override("normal_font_size", ThemeLayout.font_size_sm)
	title.add_theme_font_size_override("bold_font_size", ThemeLayout.font_size_sm)
	box.add_child(title)

	var said: RichTextLabel = _rich(ProjectSearch.snippet(str(hit["text"]), words, ThemeLayout.accent_color.lightened(0.35)))
	box.add_child(said)

	card.gui_input.connect(_on_card_input.bind(hit["storyline"], node))
	return card


func _type_name(node: InspectableNode) -> String:
	match node.get_type():
		"choice":
			return tr("Choice")
		"condition":
			return tr("Condition")
	return tr(node.get_type().capitalize())


func _short(storyline_name: String) -> String:
	return storyline_name


func _card() -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = ThemeLayout.bg_elevated_color
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = ThemeLayout.bg_hover_color
	card.add_theme_stylebox_override("panel", normal)
	card.mouse_entered.connect(func() -> void: card.add_theme_stylebox_override("panel", hover))
	card.mouse_exited.connect(func() -> void: card.add_theme_stylebox_override("panel", normal))
	return card


func _rich(bbcode: String) -> RichTextLabel:
	var label: RichTextLabel = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.text = bbcode
	return label


func _on_card_input(event: InputEvent, storyline: StorylineDocument, node: InspectableNode) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	EventBus.request_storyline_inspection.emit(storyline)
	if node == null:
		return
	var selection: Array[InspectableObject] = [node]
	EventBus.request_nodes_selection.emit(selection, storyline.id, false)
	_center_on.call_deferred(node)


func _center_on(node: InspectableNode) -> void:
	await get_tree().process_frame
	if node == null or not is_instance_valid(node.graph_view):
		return
	var graph: MonologueGraphEdit = node.graph_view.get_parent() as MonologueGraphEdit
	if graph == null:
		return
	graph.jumped.emit()
	graph.scroll_offset = node.graph_view.position_offset * graph.zoom - graph.size / 2.0 + node.graph_view.size * graph.zoom / 2.0
