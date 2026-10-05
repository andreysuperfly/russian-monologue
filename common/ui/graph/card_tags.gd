class_name CardTags
## Under a card's text, what decides whether it happens: short coloured tags in a box with a
## dashed edge — «may not happen» (russian-monologue). The tags come from add-ons
## ([method MonologuePlugin.card_tags]); a click on one opens a small editor for just that
## condition, and «+» adds one of those the add-on offers. Every change is one undo step.
##
## A tag: {"text", "color": Color, "tip", "fields": [field…], "clear": {property: value}}.
## A field: {"prop", "label", "kind": "choice" | "int" | "text", "options": [[value, label]…],
## "min", "max"}. An offer: {"text", "tag": a tag whose "start" holds the values to begin with}.

const NAME: String = "CardTags"
const DASH: Color = Color(1, 1, 1, 0.22)


static func tags_of(node: InspectableNode) -> Array:
	for plugin: MonologuePlugin in MonologueRegistry.get_instance().get_installed_plugins():
		var tags: Array = plugin.card_tags(node)
		if not tags.is_empty():
			return tags
	return []


static func offers_of(node: InspectableNode) -> Array:
	var offers: Array = []
	for plugin: MonologuePlugin in MonologueRegistry.get_instance().get_installed_plugins():
		offers.append_array(plugin.card_tag_offers(node))
	return offers


## Adds the box under the card's text, when there is anything to say.
static func add_to(graph_node: GraphNode, node: InspectableNode) -> void:
	var tags: Array = tags_of(node)
	if tags.is_empty():
		return
	var box: PanelContainer = PanelContainer.new()
	box.name = NAME
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var room: StyleBoxEmpty = StyleBoxEmpty.new()
	room.content_margin_left = 6
	room.content_margin_right = 6
	room.content_margin_top = 6
	room.content_margin_bottom = 6
	box.add_theme_stylebox_override(&"panel", room)
	box.draw.connect(_draw_dashes.bind(box))

	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", 5)
	flow.add_theme_constant_override(&"v_separation", 5)
	flow.mouse_filter = Control.MOUSE_FILTER_PASS
	for tag: Dictionary in tags:
		var chip: Button = _chip(str(tag.get("text", "")), tag.get("color", Color("#9a9a9a")))
		chip.tooltip_text = str(tag.get("tip", ""))
		chip.pressed.connect(func() -> void: open_editor(chip, node, tag))
		flow.add_child(chip)
	var offers: Array = offers_of(node)
	if not offers.is_empty():
		var plus: Button = _chip("+", Color("#8a8a8a"))
		plus.tooltip_text = TranslationServer.translate("Add a condition")
		plus.pressed.connect(func() -> void: offer_menu(plus, node, offers))
		flow.add_child(plus)
	box.add_child(flow)
	graph_node.add_child(box)

	# undo, redo and the inspector change the fields too: redraw the tags then, once per frame
	if not graph_node.has_meta(&"card_tags_hooked"):
		graph_node.set_meta(&"card_tags_hooked", true)
		node.property_changed.connect(func(_property: String) -> void:
			if not is_instance_valid(graph_node) or graph_node.has_meta(&"card_tags_pending"):
				return
			graph_node.set_meta(&"card_tags_pending", true)
			(func() -> void:
				if is_instance_valid(graph_node):
					graph_node.remove_meta(&"card_tags_pending")
					node.refresh_preview()).call_deferred())


static func _chip(text: String, colour: Color) -> Button:
	var chip: Button = Button.new()
	chip.text = text
	chip.focus_mode = Control.FOCUS_NONE
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.add_theme_font_size_override(&"font_size", 12)
	for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		chip.add_theme_color_override(state, colour if state != &"font_hover_color" else colour.lightened(0.2))
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color("#1c1c1c").lerp(colour, 0.13)
	box.border_color = Color(colour, 0.3)
	box.set_border_width_all(1)
	box.set_corner_radius_all(20)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	var hover: StyleBoxFlat = box.duplicate()
	hover.bg_color = Color("#1c1c1c").lerp(colour, 0.22)
	chip.add_theme_stylebox_override(&"normal", box)
	chip.add_theme_stylebox_override(&"hover", hover)
	chip.add_theme_stylebox_override(&"pressed", hover)
	chip.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	return chip


static func _draw_dashes(box: Control) -> void:
	var r: Rect2 = Rect2(Vector2(0.5, 0.5), box.size - Vector2.ONE)
	var dash: float = 4.0
	for side: Array in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end],
			[r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
		box.draw_dashed_line(side[0], side[1], DASH, 1.0, dash, false)


## The conditions that can be added, as a menu; the chosen one opens its editor.
static func offer_menu(anchor: Control, node: InspectableNode, offers: Array) -> void:
	var menu: PopupMenu = PopupMenu.new()
	for index: int in offers.size():
		menu.add_item(str(offers[index].get("text", "")), index)
	menu.id_pressed.connect(func(index: int) -> void: open_editor(anchor, node, offers[index].get("tag", {})))
	menu.popup_hide.connect(menu.queue_free)
	anchor.get_tree().root.add_child(menu)
	menu.position = Vector2i(anchor.get_screen_position() + Vector2(0, anchor.get_global_rect().size.y + 4))
	menu.popup()


## A small window for one condition: its fields, «Remove» and «Done».
static func open_editor(anchor: Control, node: InspectableNode, tag: Dictionary) -> void:
	var fields: Array = tag.get("fields", [])
	if fields.is_empty():
		return
	var start: Dictionary = tag.get("start", {})
	var popup: PopupPanel = PopupPanel.new()
	var frame: StyleBoxFlat = StyleBoxFlat.new()
	frame.bg_color = Color("#262626")
	frame.border_color = Color("#3a3a3a")
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(8)
	frame.set_content_margin_all(14)
	popup.add_theme_stylebox_override(&"panel", frame)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	column.custom_minimum_size.x = 300
	var heading: Label = Label.new()
	heading.text = str(tag.get("title", tag.get("text", "")))
	heading.add_theme_font_size_override(&"font_size", 16)
	heading.add_theme_color_override(&"font_color", tag.get("color", ThemeLayout.text_primary_color))
	column.add_child(heading)
	var tip: String = str(tag.get("tip", ""))
	if not tip.is_empty():
		var said: Label = Label.new()
		said.text = tip
		said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		said.add_theme_font_size_override(&"font_size", 13)
		said.add_theme_color_override(&"font_color", Color("#9a9a9a"))
		column.add_child(said)

	var read: Dictionary = {}  # property → Callable giving the value in the window
	var apply: Callable = func(values: Dictionary) -> void:
		_apply(node, values, heading.text)
		popup.hide()
	for field: Dictionary in fields:
		var prop: String = str(field.get("prop", ""))
		var now: Variant = start.get(prop, node.get_property_value(prop))
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		var label: Label = Label.new()
		label.text = str(field.get("label", ""))
		label.custom_minimum_size.x = 96
		label.add_theme_color_override(&"font_color", Color("#c8c8c8"))
		row.add_child(label)
		match str(field.get("kind", "text")):
			"choice":
				var options: Array = field.get("options", [])
				var pick: OptionButton = OptionButton.new()
				pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				for index: int in options.size():
					pick.add_item(str(options[index][1]), index)
					if str(options[index][0]) == str(now):
						pick.select(index)
				read[prop] = func() -> Variant: return options[maxi(pick.selected, 0)][0]
				row.add_child(pick)
			"int":
				var number: SpinBox = SpinBox.new()
				number.min_value = float(field.get("min", 0))
				number.max_value = float(field.get("max", 100))
				number.value = float(now) if now != null else 0.0
				number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				read[prop] = func() -> Variant: return int(number.value)
				row.add_child(number)
			_:
				var line: LineEdit = LineEdit.new()
				line.text = str(now) if now != null else ""
				line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				read[prop] = func() -> Variant: return line.text.strip_edges()
				line.text_submitted.connect(func(_t: String) -> void: apply.call(_values(read)))
				row.add_child(line)
		column.add_child(row)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var clear: Dictionary = tag.get("clear", {})
	if not clear.is_empty() and start.is_empty():
		var remove: Button = _button(TranslationServer.translate("Remove the condition"), false)
		remove.pressed.connect(func() -> void: apply.call(clear))
		buttons.add_child(remove)
	var done: Button = _button(TranslationServer.translate("Done"), true)
	done.pressed.connect(func() -> void: apply.call(_values(read)))
	buttons.add_child(done)
	column.add_child(buttons)

	popup.add_child(column)
	popup.popup_hide.connect(popup.queue_free)
	anchor.get_tree().root.add_child(popup)
	popup.popup(Rect2i(Vector2i(anchor.get_screen_position() + Vector2(0, anchor.get_global_rect().size.y + 4)), Vector2i.ZERO))


static func _values(read: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	for prop: String in read:
		values[prop] = (read[prop] as Callable).call()
	return values


static func _button(text: String, main: bool) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(100, 34)
	button.focus_mode = Control.FOCUS_NONE
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = ThemeLayout.accent_color if main else Color(1, 1, 1, 0.08)
	box.set_corner_radius_all(7)
	box.set_content_margin_all(6)
	var hover: StyleBoxFlat = box.duplicate()
	hover.bg_color = box.bg_color.lightened(0.12) if main else Color(1, 1, 1, 0.14)
	button.add_theme_stylebox_override(&"normal", box)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"pressed", hover)
	button.add_theme_color_override(&"font_color", Color.WHITE)
	return button


## Writes the values in one undo step.
static func _apply(node: InspectableNode, values: Dictionary, what: String) -> void:
	var project: MonologueProject = ProjectManager.current_project
	var storyline: StorylineDocument = project.get_storyline(node.storyline_id) if project else null
	if storyline == null:
		return
	var changes: Array = []
	for prop: String in values:
		var old: Variant = node.get_property_value(prop)
		if str(old) != str(values[prop]) or typeof(old) != typeof(values[prop]):
			changes.append([prop, old, values[prop]])
	if changes.is_empty():
		return
	var step: CommandTransaction = storyline.history.begin("Condition: %s" % what)
	for change: Array in changes:
		storyline.history.execute(PropertyChangeCommand.new(node, change[0], change[1], change[2]))
	step.commit()
	node.refresh_preview()
