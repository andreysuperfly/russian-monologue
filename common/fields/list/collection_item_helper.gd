class_name CollectionItemHelper
enum MenuActions { EDIT, DUPLICATE, DELETE }


static func populate_item_view(
	owner: BaseListField, item_view: PanelContainer, item: CollectionItem, item_index: int
) -> void:
	_make_item_row(owner, item_view, item_index, item)


static func _create_drag_handle(external: bool = false) -> ListItemDragHandle:
	var drag_handle: ListItemDragHandle = ListItemDragHandle.new()
	drag_handle.custom_minimum_size = Vector2(24, 24)
	drag_handle.theme_type_variation = "ListItemIconButton"

	if not external:
		drag_handle.icon = preload("res://ui/assets/icons/drag_handle.svg")
		drag_handle.mouse_default_cursor_shape = Control.CURSOR_DRAG

	return drag_handle


static func _make_item_row(
	owner: BaseListField,
	content: PanelContainer,
	index: int,
	item: CollectionItem,
) -> void:
	var is_protected: bool = item.get_property_value("protected") == true

	var row: ListItemReorderRow = ListItemReorderRow.new()
	row.owner_field = owner
	row.item_index = index
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(row)

	var drag_handle: ListItemDragHandle = _create_drag_handle()
	row.drag_handle = drag_handle
	row.add_child(drag_handle)
	row.init_drag()

	# a face or an icon before the name, when there is one (russian-monologue)
	var badge: Control = Pictures.badge_for(ProjectManager.current_project, item._to_dict(), 22)
	if badge:
		row.add_child(badge)

	var preview_prop_name: String = item.get_preview_property_names()[0]
	var preview_prop: Property = item.get_property(preview_prop_name)
	var preview_field: Field = FieldWidgetFactory.create(preview_prop.type)
	preview_field.set_preview()
	preview_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	FieldWidgetFactory.bind_one(preview_prop, preview_field, item)
	row.add_child(preview_field)

	# a character, item or variable: a click on the name lists everywhere it is used (russian-monologue)
	if item.get_type() in ["character", "item", "variable"]:
		preview_field.mouse_filter = Control.MOUSE_FILTER_STOP
		preview_field.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		preview_field.tooltip_text = owner.tr("Where used")
		var item_id: String = str(item.get_property_value("id"))
		preview_field.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
				ProblemsWindow.show_usages(owner.get_tree().root, item_id))

	# the same «where used» behind a button, for those who would not think to click the name
	if item.get_type() in ["character", "item", "variable"]:
		var usages_button: Button = Button.new()
		usages_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		usages_button.icon = load("res://ui/assets/icons/link.svg")
		usages_button.tooltip_text = owner.tr("Where used")
		usages_button.theme_type_variation = "ListItemIconButton"
		var usage_id: String = str(item.get_property_value("id"))
		usages_button.pressed.connect(func() -> void: ProblemsWindow.show_usages(owner.get_tree().root, usage_id))
		row.add_child(usages_button)

	var edit_button: Button = Button.new()
	edit_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit_button.icon = preload("res://ui/assets/icons/pen.svg")
	edit_button.tooltip_text = "Edit item"
	edit_button.theme_type_variation = "ListItemIconButton"
	edit_button.pressed.connect(owner._on_edit_item.bind(index))
	row.add_child(edit_button)

	if not is_protected:
		var delete_button: Button = Button.new()
		delete_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		delete_button.icon = preload("res://ui/assets/icons/cross.svg")
		delete_button.tooltip_text = "Delete item"
		delete_button.theme_type_variation = "ListItemIconButton"
		delete_button.pressed.connect(owner._on_delete_item.bind(index))
		row.add_child(delete_button)


static func _on_menu_button_id_pressed(id: MenuActions, owner: BaseListField, index: int) -> void:
	match id:
		MenuActions.DUPLICATE:
			owner._on_duplicate_item(index)
		MenuActions.DELETE:
			owner._on_delete_item(index)


static func populate_external_item_view(content: PanelContainer, name: String) -> void:
	var row: ListItemReorderRow = ListItemReorderRow.new()
	row.external = true
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(row)

	var drag_handle: ListItemDragHandle = _create_drag_handle(true)
	row.drag_handle = drag_handle
	row.add_child(drag_handle)

	var ext_label: Label = Label.new()
	ext_label.text = name
	ext_label.theme_type_variation = "NoteLabel"
	ext_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ext_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The name is written with no thought for how wide the inspector is, and a Label with
	# nothing said about it is as wide as its text, panel or no panel.
	ext_label.clip_text = true
	ext_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(ext_label)
