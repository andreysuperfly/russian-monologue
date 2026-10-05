class_name GraphNodePicker extends MonologueWindow

## What the description panel shows when nothing is picked yet.
const NO_SELECTION_HINT: String = "Pick a node type to read what it does."

@onready var node_tree: GraphNodeTree = %Tree
@onready var search_bar: LineEdit = %SearchBar
@onready var description_label: RichTextLabel = %Description

## The node a wire was dragged out of, by id, and the property it left by. Both empty
## when the picker was opened from a menu.
var from_node: String = ""
var from_property: String = ""
## Slot type of that port. The tree offers only the types it can reach.
var source_port_type_id: int = 0
## Where the wire was let go, in the graph's own coordinates. Only meaningful when the
## picker was dragged out of a port, which [method has_source_port] answers.
var graph_release: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	hide()
	force_native = true
	# a plain title bar: drawn under it, the search field sat beneath the window buttons
	extend_to_title = false
	EventBus.enable_picker_mode.connect(_on_enable_picker_mode)
	node_tree.type_highlighted.connect(_on_type_highlighted)
	_make_readable()
	_make_palette()
	_on_type_highlighted(null)


## Bigger and brighter than the theme's default (russian-monologue): the list is read, not
## skimmed — larger type, the categories in full white, roomier rows, «Add» in the accent colour.
func _make_readable() -> void:
	min_size = Vector2i(420, 420)
	search_bar.custom_minimum_size.y = 42
	search_bar.add_theme_font_size_override(&"font_size", 17)
	node_tree.add_theme_font_size_override(&"font_size", 17)
	node_tree.add_theme_color_override(&"font_color", ThemeLayout.text_primary_color)
	node_tree.add_theme_constant_override(&"v_separation", 10)
	node_tree.add_theme_constant_override(&"h_separation", 10)
	node_tree.add_theme_constant_override(&"icon_max_width", 16)
	description_label.add_theme_font_size_override(&"normal_font_size", 15)
	description_label.add_theme_font_size_override(&"bold_font_size", 16)
	description_label.add_theme_color_override(&"default_color", ThemeLayout.text_primary_color)
	var panel: Control = description_label.get_parent()
	if panel:
		panel.custom_minimum_size.y = 64
	var buttons: Array[Button] = [get_node("PanelContainer/VBox/HBox/CancelButton") as Button, %CreateButton as Button]
	for button: Button in buttons:
		button.custom_minimum_size = Vector2(130, 40)
		button.add_theme_font_size_override(&"font_size", 16)
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 1, 0.08)
		box.set_corner_radius_all(8)
		box.set_content_margin_all(8)
		var hover: StyleBoxFlat = box.duplicate()
		hover.bg_color = Color(1, 1, 1, 0.14)
		var off: StyleBoxFlat = box.duplicate()
		off.bg_color = Color(1, 1, 1, 0.04)
		if button.unique_name_in_owner:
			box.bg_color = ThemeLayout.accent_color
			hover.bg_color = ThemeLayout.accent_color.lightened(0.12)
		button.add_theme_stylebox_override(&"normal", box)
		button.add_theme_stylebox_override(&"hover", hover)
		button.add_theme_stylebox_override(&"pressed", hover)
		button.add_theme_stylebox_override(&"disabled", off)
		button.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
		button.add_theme_color_override(&"font_color", Color.WHITE)


# ---------- every kind of node at a glance (russian-monologue) ----------
# The tree showed one category per screen: «Flow» filled the window and lines and choices sat far
# below. Here each category is a heading with its kinds as tiles, several to a row, so the whole
# list fits. The tree stays underneath, hidden: it still filters, keeps the first match for Enter
# and knows which kinds a dragged wire can reach.
var _palette: ScrollContainer
var _tiles: VBoxContainer


func _make_palette() -> void:
	_palette = ScrollContainer.new()
	_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tiles = VBoxContainer.new()
	_tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tiles.add_theme_constant_override(&"separation", 6)
	_palette.add_child(_tiles)
	node_tree.get_parent().add_child(_palette)
	node_tree.get_parent().move_child(_palette, node_tree.get_index())
	node_tree.visible = false
	search_bar.text_changed.connect(func(_text: String) -> void: _fill_palette.call_deferred())


func _fill_palette() -> void:
	if _tiles == null:
		return
	for old: Node in _tiles.get_children():
		old.queue_free()
	var root: TreeItem = node_tree.get_root()
	if root == null:
		return
	var first: TreeItem = node_tree.get_selected()
	for category: TreeItem in root.get_children():
		if not category.visible:
			continue
		var kinds: Array[TreeItem] = []
		for kind: TreeItem in category.get_children():
			if kind.visible and kind.get_metadata(GraphNodeTree.NAME_COLUMN) != null:
				kinds.append(kind)
		if kinds.is_empty():
			if category.get_metadata(GraphNodeTree.NAME_COLUMN) == null and category.get_child_count() == 0:
				_tiles.add_child(_heading(category.get_text(GraphNodeTree.NAME_COLUMN)))  # «nothing accepts…»
			continue
		_tiles.add_child(_heading(category.get_text(GraphNodeTree.NAME_COLUMN)))
		var row: HFlowContainer = HFlowContainer.new()
		row.add_theme_constant_override(&"h_separation", 6)
		row.add_theme_constant_override(&"v_separation", 6)
		for kind: TreeItem in kinds:
			row.add_child(_tile(kind, kind == first))
		_tiles.add_child(row)


func _heading(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 13)
	label.add_theme_color_override(&"font_color", ThemeLayout.text_muted_color)
	label.uppercase = true
	return label


func _tile(kind: TreeItem, first: bool) -> Button:
	var type_name: String = String(kind.get_metadata(GraphNodeTree.NAME_COLUMN))
	var indexer: NodeIndexer = MonologueRegistry.get_instance().get_node(type_name)
	var tile: Button = Button.new()
	tile.text = kind.get_text(GraphNodeTree.NAME_COLUMN)
	tile.icon = kind.get_icon(GraphNodeTree.NAME_COLUMN)
	tile.expand_icon = false
	tile.add_theme_constant_override(&"icon_max_width", 16)
	tile.add_theme_color_override(&"icon_normal_color", kind.get_icon_modulate(GraphNodeTree.NAME_COLUMN))
	tile.add_theme_color_override(&"icon_hover_color", kind.get_icon_modulate(GraphNodeTree.NAME_COLUMN))
	tile.add_theme_color_override(&"font_color", ThemeLayout.text_primary_color)
	tile.add_theme_color_override(&"font_hover_color", Color.WHITE)
	tile.add_theme_font_size_override(&"font_size", 16)
	tile.custom_minimum_size = Vector2(0, 38)
	tile.alignment = HORIZONTAL_ALIGNMENT_LEFT
	tile.focus_mode = Control.FOCUS_NONE
	tile.tooltip_text = indexer.description if indexer else ""
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.06)
	box.set_corner_radius_all(7)
	box.content_margin_left = 10
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	if first:  # what Enter would add, after a search
		box.border_color = ThemeLayout.accent_color
		box.set_border_width_all(2)
	var hover: StyleBoxFlat = box.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.13)
	tile.add_theme_stylebox_override(&"normal", box)
	tile.add_theme_stylebox_override(&"hover", hover)
	tile.add_theme_stylebox_override(&"pressed", hover)
	tile.mouse_entered.connect(func() -> void: _on_type_highlighted(indexer))
	tile.pressed.connect(func() -> void:
		EventBus.add_graph_node.emit(type_name, self)
		close())
	return tile


## Shows what the highlighted type is for. The tree only carries names, so the reading
## matter lives here where there is room for it.
func _on_type_highlighted(indexer: NodeIndexer) -> void:
	if indexer == null:
		description_label.text = "[color=#%s]%s[/color]" % [
			ThemeLayout.text_muted_color.to_html(false), tr(NO_SELECTION_HINT)
		]
		return

	description_label.text = "[b]%s[/b]\n[color=#%s]%s[/color]" % [
		indexer.get_display_name(),
		ThemeLayout.text_primary_color.darkened(0.15).to_html(false),
		indexer.description,
	]


func _on_enable_picker_mode(
	from_node_id: String = "",
	from_property_name: String = "",
	port_type: int = 0,
	graph_release_pos: Vector2 = Vector2.ZERO
) -> void:
	open_for_node(from_node_id, from_property_name, port_type, graph_release_pos)


func close() -> void:
	hide()


func flush() -> void:
	from_node = ""
	from_property = ""
	source_port_type_id = 0
	graph_release = Vector2.ZERO


## True when the picker was dragged out of a port, in which case the created node is
## expected to come back wired.
func has_source_port() -> bool:
	return not from_node.is_empty() and not from_property.is_empty()


func open_for_node(
	from_node_id: String = "",
	from_property_name: String = "",
	port_type: int = 0,
	graph_release_pos: Vector2 = Vector2.ZERO
) -> void:
	flush()
	from_node = from_node_id
	from_property = from_property_name
	source_port_type_id = port_type
	graph_release = graph_release_pos

	if node_tree:
		node_tree.reload_tree()
	_fill_palette()

	popup()
	# the size in points, not pixels: on a retina screen 540 pixels came up as a small window
	await get_tree().process_frame
	oversampling_override = maxf(content_scale_factor, 1.0)
	size = Vector2i(Vector2(760, 760) * maxf(content_scale_factor, 1.0))
	move_to_center()

	var root_window: Window = get_tree().get_root()
	if root_window:
		current_screen = root_window.current_screen

	grab_focus()
	if search_bar:
		search_bar.clear()
		search_bar.grab_focus()


func _on_close_requested() -> void:
	close()


func _on_cancel_button_pressed() -> void:
	close()


func _on_create_button_pressed() -> void:
	if node_tree.create_selected_descriptor():
		close()


func _on_search_submitted(_text: String) -> void:
	if node_tree.create_selected_descriptor():
		close()


func _on_visibility_changed() -> void:
	super._on_visibility_changed()
	var root: Window = get_tree().get_root()
	if root:
		current_screen = root.current_screen
