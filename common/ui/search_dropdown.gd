## A long dropdown opens with a search box on top (russian-monologue): type part of a name and
## the list narrows to it; Up/Down move, Enter picks, Esc closes. Works on any OptionButton —
## the pick goes through the button's own select + item_selected, so the code that listens to it
## does not change. Short lists keep the usual popup.
extends RefCounted

## Fewer items than this — the plain popup is quicker.
const MIN_ITEMS: int = 9


static func attach(button: OptionButton) -> void:
	if button == null or button.has_meta("search_dropdown"):
		return
	button.set_meta("search_dropdown", true)
	button.gui_input.connect(func(event: InputEvent) -> void:
		if button.disabled or button.item_count < MIN_ITEMS:
			return
		var click: bool = event is InputEventMouseButton and event.pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		if click or event.is_action_pressed("ui_accept"):
			button.accept_event()
			_open(button))


static func _open(button: OptionButton) -> void:
	var popup: PopupPanel = PopupPanel.new()
	var box: VBoxContainer = VBoxContainer.new()
	popup.add_child(box)
	var search: LineEdit = LineEdit.new()
	search.placeholder_text = button.tr("Search...")
	search.clear_button_enabled = true
	box.add_child(search)
	var list: ItemList = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size.y = 120
	box.add_child(list)

	var fill: Callable = func(query: String) -> void:
		list.clear()
		var needle: String = query.strip_edges().to_lower()
		for index: int in button.item_count:
			if button.is_item_separator(index):
				continue
			var text: String = button.get_item_text(index)
			if not needle.is_empty() and not text.to_lower().contains(needle):
				continue
			var row: int = list.add_item(text)
			list.set_item_metadata(row, index)
			list.set_item_disabled(row, button.is_item_disabled(index))
			if index == button.selected:
				list.select(row)
		if list.get_selected_items().is_empty():
			for row: int in list.item_count:
				if not list.is_item_disabled(row):
					list.select(row)
					break
		var picked: PackedInt32Array = list.get_selected_items()
		if not picked.is_empty():
			list.ensure_current_is_visible()

	var pick: Callable = func(row: int) -> void:
		if row < 0 or row >= list.item_count or list.is_item_disabled(row):
			return
		var index: int = int(list.get_item_metadata(row))
		popup.hide()
		if index != button.selected:
			button.select(index)
			button.item_selected.emit(index)

	search.text_changed.connect(fill)
	search.text_submitted.connect(func(_t: String) -> void:
		var picked: PackedInt32Array = list.get_selected_items()
		if not picked.is_empty():
			pick.call(picked[0]))
	search.gui_input.connect(func(event: InputEvent) -> void:
		var step: int = 0
		if event.is_action_pressed("ui_down", true):
			step = 1
		elif event.is_action_pressed("ui_up", true):
			step = -1
		if step == 0 or list.item_count == 0:
			return
		search.accept_event()
		var picked: PackedInt32Array = list.get_selected_items()
		var row: int = picked[0] if not picked.is_empty() else -step
		row = clampi(row + step, 0, list.item_count - 1)
		list.select(row)
		list.ensure_current_is_visible())
	list.item_clicked.connect(func(row: int, _at: Vector2, mouse: int) -> void:
		if mouse == MOUSE_BUTTON_LEFT:
			pick.call(row))
	list.item_activated.connect(pick)
	popup.popup_hide.connect(popup.queue_free)

	button.add_child(popup)
	fill.call("")
	# placed the way OptionButton places its own popup
	var scale: Vector2 = button.get_global_transform().get_scale()
	var at: Vector2 = button.get_screen_position() + Vector2(0, button.size.y * scale.y)
	var width: int = int(maxf(button.size.x * scale.x, 260.0))
	var height: int = clampi(list.item_count * 28 + 60, 160, 420)
	popup.popup(Rect2i(Vector2i(at), Vector2i(width, height)))
	search.grab_focus()
	list.ensure_current_is_visible()
