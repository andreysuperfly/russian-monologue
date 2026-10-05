class_name CardTags
## What decides whether something happens, as short coloured tags with a dashed edge — «may not
## happen» (russian-monologue): under a line's text and under each answer of a choice. The tags come from add-ons ([method MonologuePlugin.card_tags],
## [method MonologuePlugin.card_item_tags]); a click on one opens a small editor for just that
## condition, «+» or a right click adds one the add-on offers. Every change is one undo step.
##
## A tag: {"text", "color": Color, "title", "tip", "fields": [field…], "clear": {key: value},
## "start": {key: value}}. Keys are the node's properties, or for an answer the keys of its item.
## A field: {"prop", "label", "kind": "choice" | "int" | "text" | "entry", "options": [[value,
## label]…], "min", "max"}; an «entry» is one key of a {key: number} map — «КУЛЬТУРА 25» — and
## carries "key", the one it edits ("" for a new one). An offer: {"text", "tag"}.

const NAME: String = "CardTags"
## In a value: take this key out of the map, or put this one in place of "old".
const ERASE: String = "__erase"
const ENTRY: String = "__entry"


static func _plugins() -> Array[MonologuePlugin]:
	return MonologueRegistry.get_instance().get_installed_plugins()


static func tags_of(node: InspectableNode) -> Array:
	for plugin: MonologuePlugin in _plugins():
		var tags: Array = plugin.card_tags(node)
		if not tags.is_empty():
			return tags
	return []


static func offers_of(node: InspectableNode) -> Array:
	var offers: Array = []
	for plugin: MonologuePlugin in _plugins():
		offers.append_array(plugin.card_tag_offers(node))
	return offers


## The item of a list property by its id: an answer of a choice. Empty when there is none.
static func item_of(node: InspectableNode, property: String, item_id: String) -> Dictionary:
	var list: Variant = node.get_property_value(property)
	if list is Array:
		for item: Variant in list:
			if item is Dictionary and str((item as Dictionary).get("id", "")) == item_id:
				return item
	return {}


static func item_tags(node: InspectableNode, property: String, item_id: String) -> Array:
	var item: Dictionary = item_of(node, property, item_id)
	if item.is_empty():
		return []
	for plugin: MonologuePlugin in _plugins():
		var tags: Array = plugin.card_item_tags(node, property, item)
		if not tags.is_empty():
			return _for_item(tags, property, item_id)
	return []


static func item_offers(node: InspectableNode, property: String, item_id: String) -> Array:
	var item: Dictionary = item_of(node, property, item_id)
	if item.is_empty():
		return []
	var offers: Array = []
	for plugin: MonologuePlugin in _plugins():
		for offer: Dictionary in plugin.card_item_tag_offers(node, property, item):
			offer["tag"] = _for_item([offer.get("tag", {})], property, item_id)[0]
			offers.append(offer)
	return offers


static func _for_item(tags: Array, property: String, item_id: String) -> Array:
	for tag: Dictionary in tags:
		tag["item"] = [property, item_id]
	return tags


## Adds the box under the card's text, when there is anything to say.
static func add_to(graph_node: GraphNode, node: InspectableNode) -> void:
	_hook(graph_node, node)
	var tags: Array = tags_of(node)
	if tags.is_empty():
		return
	var box: PanelContainer = PanelContainer.new()
	box.name = NAME
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var room: StyleBoxEmpty = StyleBoxEmpty.new()
	room.set_content_margin_all(6)
	room.content_margin_left = 0
	room.content_margin_top = 4
	box.add_theme_stylebox_override(&"panel", room)
	box.add_child(flow(node, tags, offers_of(node)))
	graph_node.add_child(box)


## The tags under one answer, or null when it has none.
static func for_item(graph_node: GraphNode, node: InspectableNode, property: String, item_id: String) -> Control:
	_hook(graph_node, node)
	var tags: Array = item_tags(node, property, item_id)
	if tags.is_empty():
		return null
	# in the answer's own line, on its right: the conditions as small marks, then what it gives
	# as coloured words; no «+» on every answer — a right click adds one. A plain row, not a
	# wrapping one: a wrapping row sized itself against the card and the card shook on hover.
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var effects: Array = tags.filter(func(tag: Dictionary) -> bool: return tag.get("effect", false))
	for tag: Dictionary in tags:
		if not tag.get("effect", false):
			row.add_child(_wired(_chip(str(tag.get("text", "")), tag.get("color", Color("#9a9a9a")), true), node, tag))
	if not effects.is_empty():
		var gap: Control = Control.new()
		gap.custom_minimum_size.x = 4
		row.add_child(gap)
	for tag: Dictionary in effects:
		row.add_child(_wired(_word(str(tag.get("text", "")), tag.get("color", Color("#9a9a9a"))), node, tag))
	return row


static func _wired(button: Button, node: InspectableNode, tag: Dictionary) -> Button:
	button.tooltip_text = str(tag.get("tip", ""))
	button.pressed.connect(func() -> void: open_editor(button, node, tag))
	return button


## What an answer gives, as coloured words without a frame: it happens, it is not a condition.
static func _word(text: String, colour: Color) -> Button:
	var word: Button = Button.new()
	word.text = text
	word.flat = true
	word.focus_mode = Control.FOCUS_NONE
	word.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	word.add_theme_font_size_override(&"font_size", 13)
	for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		word.add_theme_color_override(state, colour if state != &"font_hover_color" else colour.lightened(0.25))
	var none: StyleBoxEmpty = StyleBoxEmpty.new()
	none.content_margin_left = 2
	none.content_margin_right = 2
	for style: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		word.add_theme_stylebox_override(style, none)
	return word


static func flow(node: InspectableNode, tags: Array, offers: Array) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	for tag: Dictionary in tags:
		var chip: Button = _chip(str(tag.get("text", "")), tag.get("color", Color("#9a9a9a")))
		chip.tooltip_text = str(tag.get("tip", ""))
		chip.pressed.connect(func() -> void: open_editor(chip, node, tag))
		row.add_child(chip)
	if not offers.is_empty():
		var plus: Button = _chip("+", Color("#8a8a8a"))
		plus.tooltip_text = TranslationServer.translate("Add a condition")
		plus.pressed.connect(func() -> void: offer_menu(plus, node, offers))
		row.add_child(plus)
	return row


## Undo, redo and the inspector change the fields too: redraw the tags then, once per frame. A
## list's items are drawn with the rows, so a change to the list rebuilds the card.
static func _hook(graph_node: GraphNode, node: InspectableNode) -> void:
	if graph_node.has_meta(&"card_tags_hooked"):
		return
	graph_node.set_meta(&"card_tags_hooked", true)
	node.property_changed.connect(func(property: String) -> void:
		if not is_instance_valid(graph_node) or graph_node.has_meta(&"card_tags_pending"):
			return
		var prop: Property = node.get_property(property)
		var whole: bool = prop != null and prop.type == "collection"
		graph_node.set_meta(&"card_tags_pending", true)
		(func() -> void:
			if is_instance_valid(graph_node):
				graph_node.remove_meta(&"card_tags_pending")
				if whole:
					node.rebuild_preview()
				else:
					node.refresh_preview()).call_deferred())


static func _chip(text: String, colour: Color, small: bool = false) -> Button:
	var chip: Button = Button.new()
	chip.text = text
	chip.focus_mode = Control.FOCUS_NONE
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_font_size_override(&"font_size", 11 if small else 12)
	for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		chip.add_theme_color_override(state, colour if state != &"font_hover_color" else colour.lightened(0.2))
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color("#1c1c1c").lerp(colour, 0.13)
	box.set_corner_radius_all(20)
	box.content_margin_left = 6 if small else 8
	box.content_margin_right = 6 if small else 8
	box.content_margin_top = 1 if small else 3
	box.content_margin_bottom = 1 if small else 3
	var hover: StyleBoxFlat = box.duplicate()
	hover.bg_color = Color("#1c1c1c").lerp(colour, 0.22)
	chip.add_theme_stylebox_override(&"normal", box)
	chip.add_theme_stylebox_override(&"hover", hover)
	chip.add_theme_stylebox_override(&"pressed", hover)
	chip.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	chip.draw.connect(_draw_dashed_pill.bind(chip, Color("#5c5c5c")))
	return chip


## A fine grey dashed edge around the tag itself, rounded like it, one screen pixel thin at any
## zoom so it stays sharp (a 1-unit line grew blurry as the graph zoomed in): the straight sides in dashes, the round
## ends in short arcs with gaps.
static func _draw_dashed_pill(chip: Control, colour: Color) -> void:
	var r: Rect2 = Rect2(Vector2(0.5, 0.5), chip.size - Vector2.ONE)
	var radius: float = r.size.y * 0.5
	var left: float = r.position.x + radius
	var right: float = r.end.x - radius
	if right > left:
		chip.draw_dashed_line(Vector2(left, r.position.y), Vector2(right, r.position.y), colour, -1.0, 2.0, false)
		chip.draw_dashed_line(Vector2(left, r.end.y), Vector2(right, r.end.y), colour, -1.0, 2.0, false)
	var centre_y: float = r.position.y + radius
	var steps: int = maxi(4, int(PI * radius / 2.0))
	var piece: float = PI / steps
	for i: int in steps:
		if i % 2 == 1:
			continue
		var a: float = PI * 0.5 + i * piece
		chip.draw_arc(Vector2(left, centre_y), radius, a, a + piece, 4, colour, -1.0)
		chip.draw_arc(Vector2(right, centre_y), radius, a + PI, a + PI + piece, 4, colour, -1.0)


## The conditions that can be added, as a menu; the chosen one opens its editor.
static func offer_menu(anchor: Control, node: InspectableNode, offers: Array) -> void:
	var menu: PopupMenu = PopupMenu.new()
	fill_offer_menu(menu, anchor, node, offers)
	menu.popup_hide.connect(menu.queue_free)
	anchor.get_tree().root.add_child(menu)
	MonologueGraphEdit.roomy_menu(menu)
	menu.position = Vector2i(anchor.get_screen_position() + Vector2(0, anchor.get_global_rect().size.y + 4))
	menu.popup()


static func fill_offer_menu(menu: PopupMenu, anchor: Control, node: InspectableNode, offers: Array) -> void:
	for index: int in offers.size():
		menu.add_item(str(offers[index].get("text", "")), index)
	# opened once the menu is gone: opened while it closes, the window went with it
	menu.id_pressed.connect(func(index: int) -> void:
		var tag: Dictionary = offers[index].get("tag", {})
		anchor.get_tree().create_timer(0.08).timeout.connect(func() -> void:
			if is_instance_valid(anchor):
				open_editor(anchor, node, tag)))


## The value of [param key] now: on the node, or on its answer for a tag of one.
static func _current(node: InspectableNode, tag: Dictionary, key: String) -> Variant:
	if tag.has("item"):
		return item_of(node, tag["item"][0], tag["item"][1]).get(key)
	return node.get_property_value(key)


## A small window for one condition: its fields, «Remove» and «Done».
static func open_editor(anchor: Control, node: InspectableNode, tag: Dictionary) -> void:
	var fields: Array = tag.get("fields", [])
	var start: Dictionary = tag.get("start", {})
	var clear: Dictionary = tag.get("clear", {})
	if fields.is_empty() and start.is_empty() and clear.is_empty():
		return
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
	# what is checked can be changed right here: a language barrier into a skill check, and so on
	var others: Array = []
	if not tag.get("clear", {}).is_empty() and tag.get("start", {}).is_empty():
		others = item_offers(node, tag["item"][0], tag["item"][1]) if tag.has("item") else offers_of(node)
	if not others.is_empty():
		var kind: OptionButton = OptionButton.new()
		kind.add_item(str(tag.get("title", tag.get("text", ""))), 0)
		for index: int in others.size():
			kind.add_item(str(others[index].get("text", "")), index + 1)
		kind.select(0)
		kind.item_selected.connect(func(index: int) -> void:
			if index == 0:
				return
			var other: Dictionary = (others[index - 1].get("tag", {}) as Dictionary).duplicate(true)
			other["replaces"] = tag.get("clear", {})
			popup.hide()
			open_editor(anchor, node, other))
		var kind_row: HBoxContainer = HBoxContainer.new()
		kind_row.add_theme_constant_override(&"separation", 10)
		var kind_label: Label = Label.new()
		kind_label.text = TranslationServer.translate("What is checked")
		kind_label.custom_minimum_size.x = 96
		kind_label.add_theme_color_override(&"font_color", Color("#c8c8c8"))
		kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kind.fit_to_longest_item = false
		kind.clip_text = true
		kind_row.add_child(kind_label)
		kind_row.add_child(kind)
		column.add_child(kind_row)
	var tip: String = str(tag.get("tip", ""))
	if not tip.is_empty():
		var said: Label = Label.new()
		said.text = tip
		said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		said.custom_minimum_size.x = 300
		said.add_theme_font_size_override(&"font_size", 13)
		said.add_theme_color_override(&"font_color", Color("#9a9a9a"))
		column.add_child(said)

	var read: Dictionary = {}  # key → Callable giving the value in the window
	var values: Callable = func() -> Dictionary:
		var out: Dictionary = start.duplicate(true)
		for key: String in read:
			out[key] = (read[key] as Callable).call()
		return out
	var apply: Callable = func(chosen: Dictionary) -> void:
		var all: Dictionary = (tag.get("replaces", {}) as Dictionary).duplicate(true)
		all.merge(chosen, true)
		_apply(node, tag, all, heading.text)
		popup.hide()
	for field: Dictionary in fields:
		var key: String = str(field.get("prop", ""))
		var now: Variant = start.get(key, _current(node, tag, key))
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
				var pick: OptionButton = _pick(options, now)
				read[key] = func() -> Variant: return options[maxi(pick.selected, 0)][0]
				row.add_child(pick)
			"int":
				var number: SpinBox = _number(field, now)
				read[key] = func() -> Variant: return int(number.value)
				row.add_child(number)
			"entry":
				# one key of a map: which key and its number
				var options: Array = field.get("options", [])
				var old_key: String = str(field.get("key", ""))
				var map: Dictionary = now if now is Dictionary else {}
				var pick: OptionButton = _pick(options, old_key if not old_key.is_empty() else options[0][0])
				var number: SpinBox = _number(field, map.get(old_key, field.get("value", 0)))
				read[key] = func() -> Variant:
					return {ENTRY: true, "old": old_key, "key": options[maxi(pick.selected, 0)][0], "value": int(number.value)}
				row.add_child(pick)
				row.add_child(number)
			_:
				var line: LineEdit = LineEdit.new()
				line.text = str(now) if now != null else ""
				line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				read[key] = func() -> Variant: return line.text.strip_edges()
				line.text_submitted.connect(func(_t: String) -> void: apply.call(values.call()))
				row.add_child(line)
		column.add_child(row)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	if not clear.is_empty() and start.is_empty():
		var remove: Button = _button(TranslationServer.translate("Remove the condition"), false)
		remove.pressed.connect(func() -> void: apply.call(clear))
		buttons.add_child(remove)
	var done: Button = _button(TranslationServer.translate("Done"), true)
	done.pressed.connect(func() -> void: apply.call(values.call()))
	buttons.add_child(done)
	column.add_child(buttons)

	popup.add_child(column)
	popup.popup_hide.connect(popup.queue_free)
	anchor.get_tree().root.add_child(popup)
	popup.popup(Rect2i(Vector2i(anchor.get_screen_position() + Vector2(0, anchor.get_global_rect().size.y + 4)), Vector2i.ZERO))
	# a wrapped label first measures as a narrow column, tall as a tower: fit once it has its width
	(func() -> void:
		if is_instance_valid(popup):
			popup.size = Vector2i(popup.get_contents_minimum_size())).call_deferred()


static func _pick(options: Array, now: Variant) -> OptionButton:
	var pick: OptionButton = OptionButton.new()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index: int in options.size():
		pick.add_item(str(options[index][1]), index)
		if str(options[index][0]) == str(now):
			pick.select(index)
	return pick


static func _number(field: Dictionary, now: Variant) -> SpinBox:
	var number: SpinBox = SpinBox.new()
	number.min_value = float(field.get("min", 0))
	number.max_value = float(field.get("max", 100))
	number.value = float(now) if now != null and str(now).is_valid_float() else 0.0
	number.custom_minimum_size.x = 90
	return number


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


## The new value of a key: a map entry put in or taken out, or the value as given.
static func _resolve(now: Variant, given: Variant) -> Variant:
	if given is Dictionary and (given as Dictionary).has(ENTRY):
		var map: Dictionary = (now as Dictionary).duplicate() if now is Dictionary else {}
		if not str(given["old"]).is_empty():
			map.erase(given["old"])
		map[given["key"]] = given["value"]
		return map
	if given is Dictionary and (given as Dictionary).has(ERASE):
		var map: Dictionary = (now as Dictionary).duplicate() if now is Dictionary else {}
		map.erase(given[ERASE])
		return map
	return given


static func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and str(a) == str(b)


## Writes the values in one undo step: on the node, or on its answer — the whole list then
## changes at once, so undo puts it back as it was.
static func _apply(node: InspectableNode, tag: Dictionary, values: Dictionary, what: String) -> void:
	var project: MonologueProject = ProjectManager.current_project
	var storyline: StorylineDocument = project.get_storyline(node.storyline_id) if project else null
	if storyline == null:
		return
	var changes: Array = []
	if tag.has("item"):
		var property: String = tag["item"][0]
		var old_list: Variant = node.get_property_value(property)
		if not old_list is Array:
			return
		var new_list: Array = (old_list as Array).duplicate(true)
		var touched: bool = false
		for item: Variant in new_list:
			if item is Dictionary and str((item as Dictionary).get("id", "")) == str(tag["item"][1]):
				for key: String in values:
					var next: Variant = _resolve(item.get(key), values[key])
					if not _same(item.get(key), next):
						item[key] = next
						touched = true
		if touched:
			changes.append([property, old_list, new_list])
	else:
		for key: String in values:
			var old: Variant = node.get_property_value(key)
			var next: Variant = _resolve(old, values[key])
			if not _same(old, next):
				changes.append([key, old, next])
	if changes.is_empty():
		return
	var step: CommandTransaction = storyline.history.begin("Condition: %s" % what)
	for change: Array in changes:
		storyline.history.execute(PropertyChangeCommand.new(node, change[0], change[1], change[2]))
	step.commit()
	if tag.has("item"):
		node.rebuild_preview()
	else:
		node.refresh_preview()
