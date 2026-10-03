class_name BookmarksPanel
extends VBoxContainer

enum MenuId {
	NEW_FOLDER = 1,
	NEW_FOLDER_INSIDE = 2,
	RENAME = 3,
	DELETE_FOLDER = 4,
	REMOVE_ITEM = 5,
}

const FOLDER_ICON: Texture2D = preload("res://ui/assets/icons/folder.svg")
const PLUS_ICON: Texture2D = preload("res://ui/assets/icons/plus.svg")

var tree: Tree
## A folder just made: once the tree is rebuilt, its name is opened for typing.
var _rename_next: String = ""
var hint_label: Label
var popup_menu: PopupMenu

var _building: bool = false
var _context_target: TreeItem = null
var _connected_project: MonologueProject = null

static var _bold_font: FontVariation = null


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	hint_label = Label.new()
	hint_label.text = tr("Right-click to make a folder; add storylines and nodes with right-click on them.")
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.mouse_filter = Control.MOUSE_FILTER_PASS
	hint_label.add_theme_color_override("font_color", ThemeLayout.text_muted_color)
	hint_label.add_theme_font_size_override("font_size", ThemeLayout.font_size_sm)
	add_child(hint_label)

	tree = Tree.new()
	tree.hide_root = true
	tree.columns = 1
	tree.select_mode = Tree.SELECT_SINGLE
	tree.allow_rmb_select = true
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tree)

	popup_menu = PopupMenu.new()
	popup_menu.id_pressed.connect(_on_popup_menu_id_pressed)
	add_child(popup_menu)

	tree.item_selected.connect(_on_item_selected)
	tree.item_activated.connect(_on_item_activated)
	tree.item_collapsed.connect(_on_item_collapsed)
	tree.item_edited.connect(_on_item_edited)
	tree.item_mouse_selected.connect(_on_item_mouse_selected)
	tree.empty_clicked.connect(_on_empty_clicked)
	tree.gui_input.connect(_on_tree_gui_input)
	tree.button_clicked.connect(_on_folder_plus)
	# drop storylines from the list below onto a folder; drag folders and entries about
	tree.set_drag_forwarding(_drag_from_tree, _can_drop, _drop)
	hint_label.set_drag_forwarding(Callable(), _can_drop, _drop)

	ProjectManager.project_loaded.connect(_on_project_loaded)
	EventBus.storylines_changed.connect(rebuild)
	EventBus.bookmarks_changed.connect(rebuild, CONNECT_DEFERRED)
	EventBus.storyline_deleted.connect(rebuild)

	_connect_project()
	rebuild()


func rebuild() -> void:
	_building = true
	tree.clear()
	var root: TreeItem = tree.create_item()

	var folders: Array = Bookmarks.tree()
	hint_label.visible = folders.is_empty()

	var project: MonologueProject = ProjectManager.current_project
	for folder: Variant in folders:
		if folder is Dictionary:
			_build_folder_tree(root, folder, project)

	_building = false
	_fit_height()
	if not _rename_next.is_empty():
		_rename_folder_by_id.call_deferred(_rename_next)
		_rename_next = ""


## The tree sits in the scrolling project list, which gives it no height of its own: it is made
## exactly as tall as the rows that show.
func _fit_height() -> void:
	var rows: int = 0
	var stack: Array = [tree.get_root()]
	while not stack.is_empty():
		var at: TreeItem = stack.pop_back()
		if at == null:
			continue
		for child: TreeItem in at.get_children():
			rows += 1
			if not child.collapsed:
				stack.append(child)
	tree.visible = rows > 0
	tree.custom_minimum_size.y = rows * (ThemeLayout.font_size_sm + 16) + 6
	tree.scroll_vertical_enabled = false


func _build_folder_tree(parent_item: TreeItem, folder: Dictionary, project: MonologueProject) -> void:
	var folder_item: TreeItem = tree.create_item(parent_item)
	var folder_id: String = str(folder.get("id", ""))
	var folder_name: String = str(folder.get("name", ""))
	var is_open: bool = folder.get("open", true)

	folder_item.set_text(0, folder_name)
	folder_item.set_custom_font(0, _get_bold_font())
	folder_item.set_custom_color(0, ThemeLayout.text_primary_color)
	folder_item.set_meta("type", "folder")
	folder_item.set_meta("folder_id", folder_id)
	folder_item.set_meta("folder", folder)
	folder_item.collapsed = not is_open
	# a folder glyph exactly one step wide: the folder's name then starts where its contents do,
	# so what lies in it reads straight under its name, not pushed further in
	folder_item.set_icon(0, FOLDER_ICON)
	folder_item.set_icon_max_width(0, maxi(8, tree.get_theme_constant("item_margin") - tree.get_theme_constant("h_separation")))
	folder_item.set_icon_modulate(0, Color(1, 1, 1, 0.55))
	folder_item.add_button(0, _small_plus(), 0, false, tr("New folder inside"))
	folder_item.set_button_color(0, 0, Color(1, 1, 1, 0.45))

	for subfolder: Variant in folder.get("folders", []):
		if subfolder is Dictionary:
			_build_folder_tree(folder_item, subfolder, project)

	var items: Array = folder.get("items", [])
	for i in range(items.size()):
		var item_data: Variant = items[i]
		if item_data is Dictionary:
			_build_item_row(folder_item, folder_id, i, item_data, project)


func _build_item_row(
	parent_item: TreeItem,
	folder_id: String,
	index: int,
	data: Dictionary,
	project: MonologueProject
) -> void:
	var item_node: TreeItem = tree.create_item(parent_item)
	item_node.set_meta("type", "item")
	item_node.set_meta("folder_id", folder_id)
	item_node.set_meta("item_index", index)
	item_node.set_meta("item_data", data)

	var kind: String = str(data.get("kind", ""))
	var storyline_id: String = str(data.get("storyline", ""))
	var storyline_name: String = storyline_id
	if project:
		var storyline: StorylineDocument = project.get_storyline(storyline_id)
		if storyline:
			storyline_name = storyline.name

	var short_name: String = _storyline_short_name(storyline_name)
	var label_text: String = ""
	if kind == "storyline":
		label_text = short_name
	elif kind == "node":
		var node_id: String = str(data.get("node", ""))
		var node_lbl: String = _node_text(project, storyline_id, node_id)
		label_text = "%s › %s" % [short_name, node_lbl]
	else:
		label_text = short_name

	item_node.set_text(0, label_text)
	item_node.set_tooltip_text(0, storyline_name if kind == "storyline" else "%s › %s" % [storyline_name, label_text])
	item_node.set_custom_color(0, ThemeLayout.text_muted_color)


func _on_item_selected() -> void:
	if _building:
		return
	var selected: TreeItem = tree.get_selected()
	if not selected:
		return
	if selected.get_meta("type", "") == "item":
		_activate_item(selected)


func _on_item_activated() -> void:
	var selected: TreeItem = tree.get_selected()
	if not selected:
		return
	if selected.get_meta("type", "") == "folder":
		_start_folder_rename(selected)
	elif selected.get_meta("type", "") == "item":
		_activate_item(selected)


func _activate_item(item: TreeItem) -> void:
	var project: MonologueProject = ProjectManager.current_project
	if not project:
		return
	var data: Dictionary = item.get_meta("item_data", {})
	var storyline_id: String = str(data.get("storyline", ""))
	var storyline: StorylineDocument = project.get_storyline(storyline_id)
	if not storyline:
		return
	EventBus.request_storyline_inspection.emit(storyline)
	if str(data.get("kind", "")) == "node":
		var node_id: String = str(data.get("node", ""))
		var node: InspectableNode = storyline.get_node(node_id)
		if node:
			var selection: Array[InspectableObject] = [node]
			EventBus.request_nodes_selection.emit(selection, storyline.id, false)


func _on_item_collapsed(item: TreeItem) -> void:
	if _building:
		return
	if item.get_meta("type", "") == "folder":
		var folder_id: String = item.get_meta("folder_id", "")
		if not folder_id.is_empty():
			Bookmarks.set_open(folder_id, not item.collapsed)


func _start_folder_rename(item: TreeItem) -> void:
	if not item or item.get_meta("type", "") != "folder":
		return
	item.set_editable(0, true)
	tree.edit_selected(true)


func _on_item_edited() -> void:
	var item: TreeItem = tree.get_edited()
	if not item:
		return
	if item.get_meta("type", "") == "folder":
		var folder_id: String = item.get_meta("folder_id", "")
		var new_name: String = item.get_text(0).strip_edges()
		item.set_editable(0, false)
		if not new_name.is_empty() and not folder_id.is_empty():
			Bookmarks.rename_folder(folder_id, new_name)
		else:
			rebuild()


func _on_item_mouse_selected(_mouse_pos: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var item: TreeItem = tree.get_selected()
	if not item:
		return
	_show_context_menu_for_item(item)


func _on_empty_clicked(_mouse_pos: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	tree.deselect_all()
	_show_context_menu_empty()


func _on_tree_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			var selected: TreeItem = tree.get_selected()
			if selected and selected.get_meta("type", "") == "folder":
				_start_folder_rename(selected)
				tree.accept_event()
		elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			var selected: TreeItem = tree.get_selected()
			if selected:
				var type: String = selected.get_meta("type", "")
				if type == "folder":
					var folder_id: String = selected.get_meta("folder_id", "")
					_confirm_delete_folder(folder_id)
					tree.accept_event()
				elif type == "item":
					var folder_id: String = selected.get_meta("folder_id", "")
					var item_index: int = int(selected.get_meta("item_index", -1))
					Bookmarks.remove_item(folder_id, item_index)
					rebuild()
					tree.accept_event()


func _show_context_menu_empty() -> void:
	_context_target = null
	popup_menu.clear()
	popup_menu.add_item(tr("New folder"), MenuId.NEW_FOLDER)
	popup_menu.position = Vector2i(get_global_mouse_position())
	popup_menu.popup()


func _show_context_menu_for_item(item: TreeItem) -> void:
	_context_target = item
	popup_menu.clear()
	var type: String = item.get_meta("type", "")
	if type == "folder":
		popup_menu.add_item(tr("New folder inside"), MenuId.NEW_FOLDER_INSIDE)
		popup_menu.add_item(tr("Rename"), MenuId.RENAME)
		popup_menu.add_item(tr("Delete"), MenuId.DELETE_FOLDER)
	elif type == "item":
		popup_menu.add_item(tr("Remove from collection"), MenuId.REMOVE_ITEM)
	popup_menu.position = Vector2i(get_global_mouse_position())
	popup_menu.popup()


func _on_popup_menu_id_pressed(id: int) -> void:
	match id:
		MenuId.NEW_FOLDER:
			var new_id: String = Bookmarks.add_folder("", tr("New folder"))
			rebuild()
			_start_rename_by_id(new_id)
		MenuId.NEW_FOLDER_INSIDE:
			if _context_target and _context_target.get_meta("type", "") == "folder":
				var parent_id: String = _context_target.get_meta("folder_id", "")
				var new_id: String = Bookmarks.add_folder(parent_id, tr("New folder"))
				Bookmarks.set_open(parent_id, true)
				rebuild()
				_start_rename_by_id(new_id)
		MenuId.RENAME:
			if _context_target and _context_target.get_meta("type", "") == "folder":
				_start_folder_rename(_context_target)
		MenuId.DELETE_FOLDER:
			if _context_target and _context_target.get_meta("type", "") == "folder":
				var folder_id: String = _context_target.get_meta("folder_id", "")
				_confirm_delete_folder(folder_id)
		MenuId.REMOVE_ITEM:
			if _context_target and _context_target.get_meta("type", "") == "item":
				var folder_id: String = _context_target.get_meta("folder_id", "")
				var item_index: int = int(_context_target.get_meta("item_index", -1))
				Bookmarks.remove_item(folder_id, item_index)
				rebuild()


func _confirm_delete_folder(folder_id: String) -> void:
	EventBus.ask_dialog.emit(
		func(response: int) -> void:
			if response == Prompt.CONFIRMED:
				Bookmarks.delete_folder(folder_id)
				rebuild(),
		tr("Delete"),
		tr("Delete this folder and everything in it?"),
		tr("Delete"),
		tr("Cancel"),
		""
	)


func _start_rename_by_id(folder_id: String) -> void:
	call_deferred(&"_deferred_start_rename", folder_id)


func _deferred_start_rename(folder_id: String) -> void:
	var item: TreeItem = _find_tree_item(tree.get_root(), folder_id)
	if item:
		tree.set_selected(item, 0)
		_start_folder_rename(item)


func _find_tree_item(parent: TreeItem, folder_id: String) -> TreeItem:
	if not parent:
		return null
	for child: TreeItem in parent.get_children():
		if child.get_meta("type", "") == "folder" and child.get_meta("folder_id", "") == folder_id:
			return child
		var found: TreeItem = _find_tree_item(child, folder_id)
		if found:
			return found
	return null


func _storyline_short_name(name: String) -> String:
	var cut: int = name.find(" · ")
	return name.substr(cut + 3) if cut >= 0 else name


func _connect_project() -> void:
	var project: MonologueProject = ProjectManager.current_project
	if _connected_project == project:
		return
	if _connected_project and is_instance_valid(_connected_project):
		if _connected_project.content_changed.is_connected(rebuild):
			_connected_project.content_changed.disconnect(rebuild)
	_connected_project = project
	if _connected_project:
		if not _connected_project.content_changed.is_connected(rebuild):
			_connected_project.content_changed.connect(rebuild)
		# an undo or redo of a collection change comes back through the settings
		_connected_project.settings.property_changed.connect(func(name: String) -> void:
			if name == Bookmarks.SETTING: rebuild.call_deferred())


func _on_project_loaded() -> void:
	_connect_project()
	rebuild()


static func _get_bold_font() -> FontVariation:
	if _bold_font == null:
		_bold_font = FontVariation.new()
		_bold_font.base_font = ThemeLayout.font_main
		_bold_font.variation_embolden = 0.6
	return _bold_font


## What a node says, briefly: a sentence's line, a choice's first option, else its label.
static func _node_text(project: MonologueProject, storyline_id: String, node_id: String) -> String:
	if project == null:
		return node_id
	var storyline: StorylineDocument = project.get_storyline(storyline_id)
	var node: InspectableNode = storyline.get_node(node_id) if storyline else null
	if node == null:
		return node_id
	var language: String = project.active_language_code
	match node.get_type():
		"sentence":
			return NodePreview.trim(Util.to_label(node.get_property_value("line"), language), 34)
		"choice":
			var options: Variant = node.get_property_value("choices")
			if options is Array and not (options as Array).is_empty():
				return "» " + NodePreview.trim(Util.to_label((options as Array)[0].get("text", {}), language), 32)
		"genius_scene":
			return "сцена " + str(node.get_property_value("key"))
	return NodePreview.node_label(project, node_id)


# ---------- drag and drop ----------

func _drag_from_tree(at: Vector2) -> Variant:
	var item: TreeItem = tree.get_item_at_position(at)
	if item == null:
		return null
	var tag: Label = Label.new()
	tag.text = item.get_text(0)
	set_drag_preview(tag)
	if item.get_meta("type", "") == "folder":
		return {"bookmark_folder": str(item.get_meta("folder_id", ""))}
	return {
		"bookmark": item.get_meta("item_data", {}),
		"from_folder": str(item.get_meta("folder_id", "")),
		"from_index": int(item.get_meta("item_index", -1)),
	}


func _can_drop(at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and (data.has("bookmark") or data.has("bookmark_folder"))):
		return false
	tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM
	return true


## The folder under the pointer, or the folder of the entry under it; "" for empty space.
func _folder_at(at: Vector2) -> String:
	if not tree.visible:
		return ""
	var item: TreeItem = tree.get_item_at_position(at)
	if item == null:
		return ""
	return str(item.get_meta("folder_id", ""))


func _drop(at: Vector2, data: Variant) -> void:
	var into: String = _folder_at(at)
	if data.has("bookmark_folder"):
		Bookmarks.move_folder(str(data["bookmark_folder"]), into)
		return
	var entry: Dictionary = data["bookmark"]
	if into.is_empty():
		into = Bookmarks.add_folder("", tr("New folder"))
	if data.has("from_folder") and str(data["from_folder"]) == into:
		return
	if not data.has("from_folder"):
		Bookmarks.add_item(into, entry)
		return
	# one undo step for the move
	var history: CommandManager = ProjectManager.current_project.command_manager
	var step: CommandTransaction = history.begin("Move in a collection")
	Bookmarks.add_item(into, entry)
	Bookmarks.remove_item(str(data["from_folder"]), int(data["from_index"]))
	step.commit()


## + on a folder's row: a folder inside it, named right away.
func _on_folder_plus(item: TreeItem, _column: int, _id: int, _button: int) -> void:
	var parent_id: String = str(item.get_meta("folder_id", ""))
	Bookmarks.set_open(parent_id, true)
	_rename_next = Bookmarks.add_folder(parent_id, tr("New folder"))


## So a new folder from the + in the panel's header is named right away too.
func name_new_folder(folder_id: String) -> void:
	_rename_next = folder_id


func _rename_folder_by_id(folder_id: String) -> void:
	var stack: Array = [tree.get_root()]
	while not stack.is_empty():
		var at: TreeItem = stack.pop_back()
		if at == null:
			continue
		if str(at.get_meta("folder_id", "")) == folder_id and at.get_meta("type", "") == "folder":
			at.select(0)
			tree.scroll_to_item(at)
			_start_folder_rename(at)
			return
		stack.append_array(at.get_children())


static var _plus: Texture2D = null

## The + of a folder row, at the size of the text rather than of a toolbar button.
static func _small_plus() -> Texture2D:
	if _plus == null:
		var image: Image = PLUS_ICON.get_image()
		var side: int = int(ThemeLayout.font_size_sm * 1.1)
		image.resize(side, side, Image.INTERPOLATE_LANCZOS)
		_plus = ImageTexture.create_from_image(image)
	return _plus
