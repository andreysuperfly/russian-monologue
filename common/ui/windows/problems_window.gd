## Problems and usages (russian-monologue), Edit → "Problems and usages…".
##
## Problems: everything the project validation finds, plus checks for things that make a large
## script confusing — a variable written but never read (or read but never written), an item given
## but never checked, notes marked TODO. Usages: pick a variable, item or character and see every
## place that points at it. Double-click any row to jump to the node.
class_name ProblemsWindow extends Window

const TODO_MARKS: Array = ["TODO", "ДОДЕЛАТЬ", "FIXME"]
## Node types that write a variable rather than read it.
const WRITERS: Array = ["variable", "input"]

static var _instance: ProblemsWindow

var _errors_pill: Label
var _warnings_pill: Label
var _problems_container: VBoxContainer
var _usage_search: LineEdit
var _usage_target: OptionButton
var _usage_filter: OptionButton
var _usages_container: VBoxContainer
var _all_usage_targets: Array[Dictionary] = []
var _path_target: OptionButton
var _paths: Tree


var _tabs: TabContainer


## Opens straight on «Where used» for one character, item or variable (russian-monologue):
## clicking a name in a collection list comes here.
static func show_usages(parent: Node, target_id: String) -> void:
	open_for(parent)
	_instance._tabs.current_tab = 1
	if _instance._usage_search != null and not _instance._usage_search.text.is_empty():
		_instance._usage_search.text = ""
		_instance._filter_targets("")
	for index: int in _instance._usage_target.item_count:
		if str(_instance._usage_target.get_item_metadata(index)) == target_id:
			_instance._usage_target.select(index)
			_instance._fill_usages()
			return


static func open_for(parent: Node) -> void:
	if _instance == null or not is_instance_valid(_instance):
		_instance = ProblemsWindow.new()
		parent.add_child(_instance)
	_instance.open()


func _init() -> void:
	hide()
	force_native = true
	title = "Problems and usages"
	size = Vector2i(640, 560)
	close_requested.connect(hide)

	var background: PanelContainer = PanelContainer.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var tabs: TabContainer = TabContainer.new()
	_tabs = tabs
	background.add_child(tabs)

	# --- problems ---
	var problems_page: VBoxContainer = VBoxContainer.new()
	problems_page.name = "Problems"
	tabs.add_child(problems_page)

	var pill_bar: HBoxContainer = HBoxContainer.new()
	pill_bar.add_theme_constant_override("separation", 8)
	problems_page.add_child(pill_bar)

	_errors_pill = _make_pill(Color(0.85, 0.22, 0.22))
	pill_bar.add_child(_errors_pill)
	_warnings_pill = _make_pill(Color(0.88, 0.60, 0.12))
	pill_bar.add_child(_warnings_pill)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	problems_page.add_child(scroll)

	_problems_container = VBoxContainer.new()
	_problems_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_problems_container.add_theme_constant_override("separation", 8)
	scroll.add_child(_problems_container)

	var recheck: Button = Button.new()
	recheck.text = tr("↻ Check again")
	recheck.pressed.connect(_fill_problems)
	problems_page.add_child(recheck)

	# --- usages ---
	var usages_page: VBoxContainer = VBoxContainer.new()
	usages_page.name = "Where used"
	usages_page.add_theme_constant_override("separation", 8)
	tabs.add_child(usages_page)

	_usage_search = LineEdit.new()
	_usage_search.placeholder_text = tr("Search variable, item or character…")
	_usage_search.clear_button_enabled = true
	_usage_search.text_changed.connect(func(query: String) -> void: _filter_targets(query.strip_edges()))
	usages_page.add_child(_usage_search)

	_usage_target = OptionButton.new()
	_usage_target.item_selected.connect(func(_i: int) -> void: _fill_usages())
	usages_page.add_child(_usage_target)

	# which places: all, those that give or take it, those that need or check it (russian-monologue)
	_usage_filter = OptionButton.new()
	_usage_filter.add_item(tr("All places"))
	_usage_filter.add_item(tr("Where it is given or taken away"))
	_usage_filter.add_item(tr("Where it is needed or checked"))
	_usage_filter.item_selected.connect(func(_i: int) -> void: _fill_usages())
	usages_page.add_child(_usage_filter)

	var usages_scroll: ScrollContainer = ScrollContainer.new()
	usages_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	usages_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	usages_page.add_child(usages_scroll)

	_usages_container = VBoxContainer.new()
	_usages_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_usages_container.add_theme_constant_override("separation", 6)
	usages_scroll.add_child(_usages_container)

	var usage_hint: Label = Label.new()
	usage_hint.text = tr("Click a place: the graph opens there and its card flashes red.")
	usage_hint.modulate = Color(1, 1, 1, 0.5)
	usages_page.add_child(usage_hint)

	# --- path to an ending: read backwards ---
	var path_page: VBoxContainer = VBoxContainer.new()
	path_page.name = "Path to an ending"
	tabs.add_child(path_page)
	var hint: Label = Label.new()
	hint.text = "Pick an ending (or any node): every way to reach it, and what each one needs."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.65)
	path_page.add_child(hint)
	_path_target = OptionButton.new()
	_path_target.item_selected.connect(func(_i: int) -> void: _fill_paths())
	path_page.add_child(_path_target)
	_paths = _make_tree(["Path", "Needs"])
	_paths.item_activated.connect(_on_row_activated.bind(_paths))
	path_page.add_child(_paths)


func open() -> void:
	_fill_problems()
	_fill_targets()
	_fill_path_targets()
	popup_centered()


func _make_tree(columns: Array) -> Tree:
	var tree: Tree = Tree.new()
	tree.columns = columns.size()
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for index: int in columns.size():
		tree.set_column_title(index, tr(columns[index]))
		tree.set_column_expand(index, columns[index] != "")
	tree.set_column_custom_minimum_width(0, 30 if columns[0] == "" else 260)
	return tree


# ---------- problems ----------

func _fill_problems() -> void:
	for child: Node in _problems_container.get_children():
		child.queue_free()

	var project: MonologueProject = ProjectManager.current_project
	if project == null:
		_errors_pill.text = _count_label(0, true)
		_warnings_pill.text = _count_label(0, false)
		return

	var errors_count: int = 0
	var warnings_count: int = 0

	# what add-ons report first — a game that could not take the story matters most (russian-monologue)
	for problem: Dictionary in ProblemMarks.gather()["list"]:
		var bad: bool = problem.get("error", false)
		if bad:
			errors_count += 1
		else:
			warnings_count += 1
		var object_id: String = str(problem.get("object_id", ""))
		_problems_container.add_child(_make_card(bad, str(problem.get("message", "")),
			_where(project, object_id, "") if not object_id.is_empty() else "", object_id))

	for issue: ValidationIssue in ValidationService.validate_project(project).issues:
		var is_err: bool = (issue.severity == ValidationIssue.Severity.ERROR)
		if is_err:
			errors_count += 1
		else:
			warnings_count += 1
		var card: PanelContainer = _make_card(
			is_err,
			_translated(issue.message),
			_where(project, issue.object_id, issue.document_name),
			issue.object_id
		)
		_problems_container.add_child(card)

	for extra: Array in _extra_checks(project):
		warnings_count += 1
		var card: PanelContainer = _make_card(
			false,
			str(extra[2]),
			_where(project, extra[1], ""),
			str(extra[1])
		)
		_problems_container.add_child(card)

	_errors_pill.text = _count_label(errors_count, true)
	_warnings_pill.text = _count_label(warnings_count, false)
	# a pill with nothing to report steps back
	_errors_pill.modulate.a = 1.0 if errors_count > 0 else 0.35
	_warnings_pill.modulate.a = 1.0 if warnings_count > 0 else 0.35


func _make_pill(bg_color: Color) -> Label:
	var pill: Label = Label.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(10)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	pill.add_theme_stylebox_override("normal", style)
	pill.add_theme_color_override("font_color", Color.WHITE)
	pill.add_theme_font_size_override("font_size", 12)
	return pill


func _make_card(is_error: bool, message: String, location: String, object_id: String) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14)
	var border_color: Color = Color(0.85, 0.22, 0.22) if is_error else Color(0.88, 0.60, 0.12)
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	# the whole card is the link (russian-monologue): one click goes to the place
	if not object_id.is_empty():
		var hover: StyleBoxFlat = style.duplicate()
		hover.bg_color = Color(0.17, 0.17, 0.21)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.tooltip_text = tr("Open this place on the graph")
		card.mouse_entered.connect(func() -> void: card.add_theme_stylebox_override("panel", hover))
		card.mouse_exited.connect(func() -> void: card.add_theme_stylebox_override("panel", style))
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_jump_to_object(object_id)
		)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var tag: Label = Label.new()
	tag.text = tr("ERROR") if is_error else tr("WARNING")
	tag.add_theme_color_override("font_color", border_color)
	tag.add_theme_font_size_override("font_size", 11)
	vbox.add_child(tag)

	var msg: Label = Label.new()
	msg.text = message
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(msg)

	var loc_label: Label = Label.new()
	loc_label.text = location
	loc_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	loc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loc_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(loc_label)

	return card


## «3 errors», «3 ошибки». The words come from the translation as «one|few|many».
func _count_label(count: int, errors: bool) -> String:
	var forms: PackedStringArray = tr("error|errors|errors" if errors else "warning|warnings|warnings").split("|")
	return _format_plural(count, forms)


## Picks «one|few|many»: Russian counts 1, 2–4 and 5+ apart (21 ошибка, 22 ошибки), English only 1.
static func _format_plural(count: int, forms: PackedStringArray) -> String:
	while forms.size() < 3:
		forms.append(forms[forms.size() - 1] if not forms.is_empty() else "")
	if not TranslationServer.get_locale().begins_with("ru"):
		return "%d %s" % [count, forms[0] if count == 1 else forms[1]]
	var c: int = abs(count) % 100
	var c1: int = c % 10
	if c > 10 and c < 20:
		return "%d %s" % [count, forms[2]]
	if c1 > 1 and c1 < 5:
		return "%d %s" % [count, forms[1]]
	if c1 == 1:
		return "%d %s" % [count, forms[0]]
	return "%d %s" % [count, forms[2]]


## Messages built from a field name («Image is required.») are translated piece by piece.
func _translated(message: String) -> String:
	const REQUIRED: String = " is required."
	if message.ends_with(REQUIRED):
		return tr("%s is required.") % tr(message.trim_suffix(REQUIRED).to_lower())
	return tr(message)


## Checks Monologue's own validation does not make: values nobody reads, items nobody checks,
## notes left with TODO. [mark, object id, text].
func _extra_checks(project: MonologueProject) -> Array:
	var found: Array = []
	var registry: ProjectObjectRegistry = project.get_object_registry()
	# what add-on fields read and write (e.g. a game's "gives" on an option), by record id
	var extra_reads: Dictionary = {}
	var extra_writes: Dictionary = {}
	var plugins: Array[MonologuePlugin] = MonologueRegistry.get_instance().get_installed_plugins()
	var count_usage: Callable = func(object: InspectableObject) -> void:
		for plugin: MonologuePlugin in plugins:
			var report: Dictionary = plugin.usage(object)
			for id: Variant in report.get("reads", []):
				extra_reads[str(id)] = int(extra_reads.get(str(id), 0)) + 1
			for id: Variant in report.get("writes", []):
				extra_writes[str(id)] = int(extra_writes.get(str(id), 0)) + 1
	for storyline: StorylineDocument in project.storylines:
		for node: InspectableNode in storyline.nodes:
			count_usage.call(node)
			for children: Variant in node.get_all_property_children():
				for child: Variant in children:
					if child is InspectableObject:
						count_usage.call(child)
	for record: Variant in project.get_collection_value("variables"):
		if record is not Dictionary:
			continue
		var id: String = str(record.get("id", ""))
		var writes: int = int(extra_writes.get(id, 0))
		var reads: int = int(extra_reads.get(id, 0))
		for site: ReferenceSite in registry.get_referrers(id):
			var owner: InspectableObject = registry.get_object(site.owner_id)
			if owner is InspectableNode and (owner as InspectableNode).get_type() in WRITERS:
				writes += 1
			else:
				reads += 1
		var name: String = str(record.get("name", id))
		if writes > 0 and reads == 0:
			found.append(["ℹ", id, tr("Variable «%s» is changed but never checked.") % name])
		elif reads > 0 and writes == 0:
			found.append(["ℹ", id, tr("Variable «%s» is checked but never changed — only its start value counts.") % name])
		elif reads == 0 and writes == 0:
			found.append(["ℹ", id, tr("Variable «%s» is not used anywhere.") % name])
	for record: Variant in project.get_collection_value("items"):
		if record is not Dictionary:
			continue
		var id: String = str(record.get("id", ""))
		var given: int = int(extra_writes.get(id, 0))
		var checked: int = int(extra_reads.get(id, 0))
		for site: ReferenceSite in registry.get_referrers(id):
			var owner: InspectableObject = registry.get_object(site.owner_id)
			if owner is InspectableNode and (owner as InspectableNode).get_type() == "inventory":
				given += 1
			else:
				checked += 1
		if given > 0 and checked == 0:
			found.append(["ℹ", id, tr("Item «%s» is given but never checked.") % str(record.get("name", id))])
	for storyline: StorylineDocument in project.storylines:
		for node: InspectableNode in storyline.nodes:
			var notes: String = str(node.get_property_value("notes")) if node.get_property("notes") != null else ""
			for mark: String in TODO_MARKS:
				if notes.to_upper().contains(mark):
					found.append(["✎", node.get_id(), notes.strip_edges().split("\n")[0]])
					break
	return found


# ---------- usages ----------

func _fill_targets() -> void:
	_all_usage_targets.clear()
	var project: MonologueProject = ProjectManager.current_project
	if project == null:
		_usage_target.clear()
		_fill_usages()
		return
	for collection: String in ["variables", "items", "characters"]:
		for record: Variant in project.get_collection_value(collection):
			if record is Dictionary:
				var label: String = "%s: %s" % [tr(collection), str(record.get("name", record.get("id", "")))]
				var id: String = str(record.get("id", ""))
				_all_usage_targets.append({"text": label, "id": id})
	var current_query: String = _usage_search.text.strip_edges() if _usage_search != null else ""
	_filter_targets(current_query)


func _filter_targets(query: String) -> void:
	var prev_id: String = ""
	if _usage_target.selected >= 0 and _usage_target.item_count > 0:
		prev_id = str(_usage_target.get_item_metadata(_usage_target.selected))
	_usage_target.clear()
	var select_idx: int = -1
	for entry: Dictionary in _all_usage_targets:
		if query.is_empty() or entry["text"].to_lower().contains(query.to_lower()):
			_usage_target.add_item(entry["text"])
			var idx: int = _usage_target.item_count - 1
			_usage_target.set_item_metadata(idx, entry["id"])
			if entry["id"] == prev_id:
				select_idx = idx
	if _usage_target.item_count > 0:
		_usage_target.select(select_idx if select_idx >= 0 else 0)
	_fill_usages()


func _fill_usages() -> void:
	for child: Node in _usages_container.get_children():
		child.queue_free()

	var project: MonologueProject = ProjectManager.current_project
	if project == null or _usage_target.selected < 0 or _usage_target.item_count == 0:
		_show_empty_usages(tr("No target selected."))
		return

	var target: String = str(_usage_target.get_item_metadata(_usage_target.selected))
	var entries: Array[Dictionary] = []
	for site: ReferenceSite in project.get_object_registry().get_referrers(target):
		var found: Array = _find_node(project, site.owner_id)
		if found.is_empty():
			entries.append({"group": tr("Collections"), "kind": "", "said": _where(project, site.owner_id, site.document_name), "what": tr(site.property_name), "jump": site.owner_id, "change": false, "check": false})
			continue
		var node: InspectableNode = found[1]
		var what: String = tr(site.property_name)
		if node.get_type() == "condition":
			what = tr("the story goes on one way if this is so, another if not")
		entries.append({"group": (found[0] as StorylineDocument).name, "kind": _kind(project, node, site.owner_id),
			"said": _said(project, node, site.owner_id), "what": what, "jump": node.get_id(),
			"change": node.get_type() in WRITERS, "check": not node.get_type() in WRITERS})
	entries.append_array(_addon_entries(project, target))
	# one card per place: what an answer needs and what it gives go on the same card, and the
	# same thing told twice (an option seen inside its choice and on its own) once
	var seen: Dictionary = {}
	var unique: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var key: String = "%s|%s|%s" % [entry["jump"], entry["kind"], entry["said"]]
		if not seen.has(key):
			entry["whats"] = [entry["what"]]
			seen[key] = entry
			unique.append(entry)
		elif not entry["what"] in seen[key]["whats"]:
			seen[key]["whats"].append(entry["what"])
		seen[key]["change"] = seen[key]["change"] or entry["change"]
		seen[key]["check"] = seen[key]["check"] or entry["check"]
	# only where it is given or taken, or only where it is needed or checked
	match _usage_filter.selected if _usage_filter else 0:
		1:
			unique.assign(unique.filter(func(e: Dictionary) -> bool: return e["change"]))
		2:
			unique.assign(unique.filter(func(e: Dictionary) -> bool: return e["check"]))
	if unique.is_empty():
		_show_empty_usages(tr("Not used anywhere."))
		return

	var groups: Dictionary = {}
	var order: Array = []
	for entry: Dictionary in unique:
		var group: String = entry["group"]
		if not groups.has(group):
			groups[group] = []
			order.append(group)
		groups[group].append(entry)
	order.sort()

	for group: String in order:
		var group_header: HBoxContainer = HBoxContainer.new()
		group_header.add_theme_constant_override("separation", 8)

		var title_label: Label = Label.new()
		title_label.text = tr("Storyline «%s»") % group if group != tr("Collections") else group
		title_label.add_theme_font_size_override("font_size", 13)
		title_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
		group_header.add_child(title_label)

		var count_pill: Label = _make_pill(Color(0.22, 0.23, 0.27))
		count_pill.text = str(groups[group].size())
		count_pill.add_theme_font_size_override("font_size", 11)
		group_header.add_child(count_pill)

		_usages_container.add_child(group_header)

		for entry: Dictionary in groups[group]:
			_usages_container.add_child(_make_usage_card(entry))


## One place, so that someone who has never seen the graph knows what it is: what kind of step
## (a line and who says it, the player's answer, a check), its words, what happens to the thing
## there, and a button that opens it on the graph, where its card flashes.
func _make_usage_card(entry: Dictionary) -> PanelContainer:
	var object_id: String = entry["jump"]
	var card: PanelContainer = PanelContainer.new()
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = tr("Open this place on the graph")

	var style_normal: StyleBoxFlat = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.12, 0.12, 0.15)
	style_normal.set_corner_radius_all(8)
	style_normal.set_content_margin_all(10)

	var style_hover: StyleBoxFlat = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.16, 0.17, 0.21)
	style_hover.set_corner_radius_all(8)
	style_hover.set_content_margin_all(10)

	card.set_meta("style_normal", style_normal)
	card.set_meta("style_hover", style_hover)
	card.set_meta("style_selected", style_hover)
	card.add_theme_stylebox_override("panel", style_normal)

	card.mouse_entered.connect(func() -> void: card.add_theme_stylebox_override("panel", style_hover))
	card.mouse_exited.connect(func() -> void: card.add_theme_stylebox_override("panel", style_normal))
	# one click is enough: a list of places is for going to them
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_jump_to_object(object_id)
	)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hbox)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vbox)

	var kind: String = entry.get("kind", "")
	if not kind.is_empty():
		var kind_label: Label = Label.new()
		kind_label.text = kind
		kind_label.add_theme_font_size_override("font_size", 12)
		kind_label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
		kind_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(kind_label)

	var text_label: Label = Label.new()
	var said: String = entry.get("said", "")
	text_label.text = "«%s»" % said if not said.is_empty() and not kind.is_empty() else said
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.add_theme_color_override("font_color", Color.WHITE)
	text_label.add_theme_font_size_override("font_size", 15)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(text_label)

	var what: Label = Label.new()
	what.text = "\n".join((entry.get("whats", [entry.get("what", "")]) as Array).map(func(w: Variant) -> String: return "→ %s" % w))
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.add_theme_font_size_override("font_size", 14)
	what.add_theme_color_override("font_color", Color(0.95, 0.78, 0.45))
	what.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(what)

	return card


func _show_empty_usages(message: String) -> void:
	var empty_box: CenterContainer = CenterContainer.new()
	empty_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	empty_box.custom_minimum_size = Vector2(0, 160)

	var empty_label: Label = Label.new()
	empty_label.text = message
	empty_label.modulate = Color(1, 1, 1, 0.5)
	empty_label.add_theme_font_size_override("font_size", 15)
	empty_box.add_child(empty_label)

	_usages_container.add_child(empty_box)


## What is said at a node: the line of a sentence, the text of an option, else the node's label.
func _said(project: MonologueProject, node: InspectableNode, object_id: String) -> String:
	var language: String = project.active_language_code
	if node.get_type() == "sentence":
		return NodePreview.trim(Util.to_label(node.get_property_value("line"), language), 400)
	if node.get_type() == "choice":
		for option: Variant in node.get_property_value("choices"):
			if option is Dictionary and str(option.get("id", "")) == object_id:
				return NodePreview.trim(Util.to_label(option.get("text", {}), language), 400)
	return _summary(project, node)


## What kind of step a place is, in words: «Line — Баба Нюра», «Player's answer», «Check».
func _kind(project: MonologueProject, node: InspectableNode, object_id: String) -> String:
	match node.get_type():
		"sentence":
			var speaker: String = ""
			if node.get_property("speaker") != null:
				speaker = ReferenceResolver.resolve_label(project, "characters", str(node.get_property_value("speaker")))
			return tr("A line — %s") % speaker if not speaker.is_empty() else tr("A line")
		"choice":
			return tr("Player's answer") if object_id != node.get_id() else tr("Player's choice")
		"condition":
			return tr("A check")
	return tr(Util.to_readable_name(node.get_type()))


## A node without words of its own (a check, a set variable, a game step) as its card reads, not
## its id: the title it gives itself, else the text of its preview.
func _summary(project: MonologueProject, node: InspectableNode) -> String:
	if node.has_method("card_title"):
		var title: String = str(node.call("card_title"))
		if not title.is_empty():
			return title
	var label: String = str(node.get_property_value("label")) if node.get_property("label") != null else ""
	if not label.is_empty() and label != node.get_id() and not label.begins_with(node.get_type() + "-"):
		return label
	if node.has_method("_build_preview"):
		var preview: Variant = node.call("_build_preview", project.active_language_code)
		if preview is Control:
			var text: String = _text_in(preview as Control).strip_edges()
			(preview as Control).free()
			if not text.is_empty():
				return NodePreview.trim(text, 400)
	return ""


func _text_in(control: Node) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if control is RichTextLabel:
		parts.append((control as RichTextLabel).get_parsed_text())
	elif control is Label:
		parts.append((control as Label).text)
	elif control is Button:
		parts.append((control as Button).text)
	for child: Node in control.get_children():
		var inner: String = _text_in(child)
		if not inner.is_empty():
			parts.append(inner)
	return " ".join(parts)


# ---------- path to an ending ----------

## Endings first (■), then every other node a story passes through.
func _fill_path_targets() -> void:
	_path_target.clear()
	var project: MonologueProject = ProjectManager.current_project
	if project == null:
		return
	var others: Array = []
	for storyline: StorylineDocument in project.storylines:
		for node: InspectableNode in storyline.nodes:
			var type: String = node.get_type()
			if type in ["root", "reroute", "int", "float", "bool", "text", "option"]:
				continue
			var label: String = "%s · %s" % [storyline.name, NodePreview.node_label(project, node.get_id())]
			if type == "end":
				_path_target.add_item("■ " + label)
				_path_target.set_item_metadata(_path_target.item_count - 1, [storyline, node.get_id()])
			else:
				others.append([label, storyline, node.get_id()])
	for other: Array in others:
		_path_target.add_item(other[0])
		_path_target.set_item_metadata(_path_target.item_count - 1, [other[1], other[2]])
	_fill_paths()


func _fill_paths() -> void:
	_paths.clear()
	var root: TreeItem = _paths.create_item()
	var project: MonologueProject = ProjectManager.current_project
	if project == null or _path_target.selected < 0:
		return
	var target: Array = _path_target.get_item_metadata(_path_target.selected)
	var paths: Array = PathFinder.paths_to(project, target[0], target[1])
	if paths.is_empty():
		_add_row(root, [tr("No way leads here."), ""], "")
		return
	var always: PackedStringArray = PathFinder.common_needs(paths)
	var head: TreeItem = _paths.create_item(root)
	head.set_text(0, tr("Needed on every path"))
	head.set_text(1, tr("nothing") if always.is_empty() else "; ".join(always))
	for index: int in paths.size():
		var path: Array = paths[index]
		var needs: PackedStringArray = PathFinder.needs_of(path)
		var item: TreeItem = _paths.create_item(root)
		item.set_text(0, tr("Path %d — %d steps") % [index + 1, path.size()])
		item.set_text(1, tr("no conditions") if needs.is_empty() else "; ".join(needs))
		item.collapsed = true
		for step: Dictionary in path:
			var node: InspectableNode = step["node"]
			var row: TreeItem = _paths.create_item(item)
			row.set_text(0, "%s · %s" % [(step["storyline"] as StorylineDocument).name, NodePreview.node_label(project, node.get_id())])
			row.set_text(1, str(step.get("need", "")))
			row.set_metadata(0, node.get_id())
	if paths.size() >= PathFinder.MAX_PATHS:
		_add_row(root, [tr("Showing the first %d paths.") % PathFinder.MAX_PATHS, ""], "")


# ---------- rows and jumping ----------

func _add_row(root: TreeItem, cells: Array, object_id: String) -> void:
	var item: TreeItem = root.get_tree().create_item(root)
	for index: int in cells.size():
		item.set_text(index, str(cells[index]))
	item.set_metadata(0, object_id)


## «storyline · node label» for a node; the record's name for a collection entry.
func _where(project: MonologueProject, object_id: String, document_name: String) -> String:
	var found: Array = _find_node(project, object_id)
	if not found.is_empty():
		var card: InspectableNode = found[1]
		var label: String = NodePreview.node_label(project, card.get_id())
		if label == card.get_id():  # a line has no label of its own: who says what instead of its id
			label = NodePreview.plain(BranchCut.name_of(card))
		return "%s · %s" % [(found[0] as StorylineDocument).name, label]
	for collection: String in ["variables", "items", "characters", "locations"]:
		for record: Variant in project.get_collection_value(collection):
			if record is Dictionary and str(record.get("id", "")) == object_id:
				return "%s: %s" % [tr(collection), str(record.get("name", object_id))]
	return document_name if not document_name.is_empty() else object_id


## Places an add-on's own fields name the record (a skill a choice needs, raises or spends),
## which plain references do not see, told in words where the add-on can (russian-monologue).
func _addon_entries(project: MonologueProject, target: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var plugins: Array[MonologuePlugin] = MonologueRegistry.get_instance().get_installed_plugins()
	if plugins.is_empty():
		return found
	var look: Callable = func(storyline: StorylineDocument, node: InspectableNode, object: InspectableObject) -> void:
		var object_id: String = object.get_id() if object.has_method("get_id") else node.get_id()
		for plugin: MonologuePlugin in plugins:
			var places: Array = plugin.usage_places(object, target)
			for place: Variant in places:
				if not place is Dictionary:
					continue
				var option: String = str(place.get("option", ""))
				var said: String = str(place.get("said", ""))
				var at: String = option if not option.is_empty() else object_id
				found.append({"group": storyline.name, "kind": _kind(project, node, at),
					"said": NodePreview.trim(said, 400) if not said.is_empty() else _said(project, node, at),
					"what": str(place.get("what", "")), "jump": node.get_id(),
					"change": not place.get("reads", false), "check": place.get("reads", false)})
			if not places.is_empty():
				continue
			# an add-on that does not say it in words: what it reads and writes
			var report: Dictionary = plugin.usage(object)
			for kind: String in ["reads", "writes"]:
				if str(target) in (report.get(kind, []) as Array).map(func(x: Variant) -> String: return str(x)):
					found.append({"group": storyline.name, "kind": _kind(project, node, object_id),
						"said": _said(project, node, object_id),
						"what": tr("needs or checks" if kind == "reads" else "changes"), "jump": node.get_id(),
						"change": kind == "writes", "check": kind == "reads"})
	for storyline: StorylineDocument in project.storylines:
		for node: InspectableNode in storyline.nodes:
			look.call(storyline, node, node)
			for children: Variant in node.get_all_property_children():
				for child: Variant in children:
					if child is InspectableObject:
						look.call(storyline, node, child)
	return found


## [storyline, node] holding [param object_id] — the node itself, or the node an embedded option
## belongs to. Empty when it is not on any graph.
func _find_node(project: MonologueProject, object_id: String) -> Array:
	if object_id.is_empty():
		return []
	for storyline: StorylineDocument in project.storylines:
		var node: InspectableNode = storyline.get_node(object_id)
		if node != null:
			return [storyline, node]
	for storyline: StorylineDocument in project.storylines:
		for node: InspectableNode in storyline.nodes:
			if JSON.stringify(node._to_dict()).contains(object_id):
				return [storyline, node]
	return []


func _jump_to_object(object_id: String) -> void:
	var project: MonologueProject = ProjectManager.current_project
	var found: Array = _find_node(project, object_id)
	if found.is_empty():
		return
	var storyline: StorylineDocument = found[0]
	var selection: Array[InspectableObject] = [found[1]]
	EventBus.request_storyline_inspection.emit(storyline)
	EventBus.request_nodes_selection.emit(selection, storyline.id, false)
	_center_on(found[1] as InspectableNode)
	# went there: the window has done its job
	hide()


## Brings the node into view on the graph, not just selects it somewhere off screen.
func _center_on(node: InspectableNode) -> void:
	MonologueGraphEdit.reveal(node)


func _on_row_activated(tree: Tree) -> void:
	var item: TreeItem = tree.get_selected()
	if item == null:
		return
	_jump_to_object(str(item.get_metadata(0)))
