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
var _usages_container: VBoxContainer
var _all_usage_targets: Array[Dictionary] = []
var _selected_usage_card: PanelContainer = null
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
	size = Vector2i(900, 560)
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

	var usages_scroll: ScrollContainer = ScrollContainer.new()
	usages_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	usages_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	usages_page.add_child(usages_scroll)

	_usages_container = VBoxContainer.new()
	_usages_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_usages_container.add_theme_constant_override("separation", 6)
	usages_scroll.add_child(_usages_container)

	var usage_hint: Label = Label.new()
	usage_hint.text = tr("Double-click a place to open it on the graph.")
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

	var vbox: VBoxContainer = VBoxContainer.new()
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

	var bottom_row: HBoxContainer = HBoxContainer.new()
	bottom_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(bottom_row)

	var loc_label: Label = Label.new()
	loc_label.text = location
	loc_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	loc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loc_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bottom_row.add_child(loc_label)

	var link_btn: Button = Button.new()
	link_btn.flat = true
	link_btn.text = tr("Go to →")
	link_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not object_id.is_empty():
		link_btn.pressed.connect(_jump_to_object.bind(object_id))
	else:
		link_btn.visible = false
	bottom_row.add_child(link_btn)

	return card


## «3 ошибки» in Russian, «3 errors» otherwise.
func _count_label(count: int, errors: bool) -> String:
	if TranslationServer.get_locale().begins_with("ru"):
		return _format_plural(count, "ошибка", "ошибки", "ошибок") if errors else _format_plural(count, "предупреждение", "предупреждения", "предупреждений")
	return "%d %s" % [count, ("error" if count == 1 else "errors") if errors else ("warning" if count == 1 else "warnings")]


func _format_plural(count: int, form1: String, form2: String, form5: String) -> String:
	var c: int = abs(count) % 100
	var c1: int = c % 10
	if c > 10 and c < 20:
		return "%d %s" % [count, form5]
	if c1 > 1 and c1 < 5:
		return "%d %s" % [count, form2]
	if c1 == 1:
		return "%d %s" % [count, form1]
	return "%d %s" % [count, form5]


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
	_selected_usage_card = null

	var project: MonologueProject = ProjectManager.current_project
	if project == null or _usage_target.selected < 0 or _usage_target.item_count == 0:
		_show_empty_usages(tr("No target selected."))
		return

	var target: String = str(_usage_target.get_item_metadata(_usage_target.selected))
	var sites: Array[ReferenceSite] = project.get_object_registry().get_referrers(target)
	sites.append_array(_addon_sites(project, target))
	if sites.is_empty():
		_show_empty_usages(tr("Not used anywhere."))
		return

	var groups: Dictionary = {}
	var order: Array = []
	for site: ReferenceSite in sites:
		var found: Array = _find_node(project, site.owner_id)
		var group: String = (found[0] as StorylineDocument).name if not found.is_empty() else tr("Collections")
		if not groups.has(group):
			groups[group] = []
			order.append(group)
		groups[group].append([site, found])
	order.sort()

	for group: String in order:
		var group_header: HBoxContainer = HBoxContainer.new()
		group_header.add_theme_constant_override("separation", 8)

		var title_label: Label = Label.new()
		title_label.text = group
		title_label.add_theme_font_size_override("font_size", 13)
		title_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
		group_header.add_child(title_label)

		var count_pill: Label = _make_pill(Color(0.22, 0.23, 0.27))
		count_pill.text = str(groups[group].size())
		count_pill.add_theme_font_size_override("font_size", 11)
		group_header.add_child(count_pill)

		_usages_container.add_child(group_header)

		for entry: Array in groups[group]:
			var site: ReferenceSite = entry[0]
			var found: Array = entry[1]
			var storyline_name: String = (found[0] as StorylineDocument).name if not found.is_empty() else tr("Collections")
			var said_text: String = _said(project, found[1] as InspectableNode, site.owner_id) if not found.is_empty() else _where(project, site.owner_id, site.document_name)
			var field_name: String = tr(site.property_name)
			var card: PanelContainer = _make_usage_card(storyline_name, said_text, field_name, site.owner_id)
			_usages_container.add_child(card)


func _make_usage_card(storyline_name: String, said_text: String, field_name: String, object_id: String) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var style_normal: StyleBoxFlat = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.12, 0.12, 0.15)
	style_normal.set_corner_radius_all(8)
	style_normal.set_content_margin_all(10)

	var style_hover: StyleBoxFlat = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.16, 0.17, 0.21)
	style_hover.set_corner_radius_all(8)
	style_hover.set_content_margin_all(10)

	var style_selected: StyleBoxFlat = StyleBoxFlat.new()
	style_selected.bg_color = Color(0.17, 0.20, 0.26)
	style_selected.border_color = Color(0.35, 0.55, 0.90)
	style_selected.set_border_width_all(1)
	style_selected.set_corner_radius_all(8)
	style_selected.set_content_margin_all(10)

	card.set_meta("style_normal", style_normal)
	card.set_meta("style_hover", style_hover)
	card.set_meta("style_selected", style_selected)
	card.add_theme_stylebox_override("panel", style_normal)

	card.mouse_entered.connect(func() -> void:
		if _selected_usage_card != card:
			card.add_theme_stylebox_override("panel", style_hover)
	)
	card.mouse_exited.connect(func() -> void:
		if _selected_usage_card != card:
			card.add_theme_stylebox_override("panel", style_normal)
	)

	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if event.double_click:
				_jump_to_object(object_id)
			else:
				_select_usage_card(card)
	)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	card.add_child(hbox)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(vbox)

	var text_label: Label = Label.new()
	text_label.text = said_text
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.add_theme_color_override("font_color", Color.WHITE)
	text_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(text_label)

	var pill: Label = _make_pill(Color(0.20, 0.23, 0.29))
	pill.text = field_name
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(pill)

	return card


func _select_usage_card(card: PanelContainer) -> void:
	if _selected_usage_card != null and is_instance_valid(_selected_usage_card):
		_selected_usage_card.add_theme_stylebox_override("panel", _selected_usage_card.get_meta("style_normal"))
	_selected_usage_card = card
	if _selected_usage_card != null:
		_selected_usage_card.add_theme_stylebox_override("panel", _selected_usage_card.get_meta("style_selected"))


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
				return "» " + NodePreview.trim(Util.to_label(option.get("text", {}), language), 400)
	return NodePreview.node_label(project, node.get_id())


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
		return "%s · %s" % [(found[0] as StorylineDocument).name, NodePreview.node_label(project, (found[1] as InspectableNode).get_id())]
	for collection: String in ["variables", "items", "characters", "locations"]:
		for record: Variant in project.get_collection_value(collection):
			if record is Dictionary and str(record.get("id", "")) == object_id:
				return "%s: %s" % [tr(collection), str(record.get("name", object_id))]
	return document_name if not document_name.is_empty() else object_id


## [storyline, node] holding [param object_id] — the node itself, or the node an embedded option
## belongs to. Empty when it is not on any graph.
## Places an add-on's own fields name the record (a skill a choice needs, raises or spends),
## which plain references do not see (russian-monologue).
func _addon_sites(project: MonologueProject, target: String) -> Array[ReferenceSite]:
	var found: Array[ReferenceSite] = []
	var plugins: Array[MonologuePlugin] = MonologueRegistry.get_instance().get_installed_plugins()
	if plugins.is_empty():
		return found
	var look: Callable = func(object: InspectableObject) -> void:
		for plugin: MonologuePlugin in plugins:
			var report: Dictionary = plugin.usage(object)
			for kind: String in ["reads", "writes"]:
				if str(target) in (report.get(kind, []) as Array).map(func(x: Variant) -> String: return str(x)):
					var site: ReferenceSite = ReferenceSite.new()
					site.owner_id = object.get_id() if object.has_method("get_id") else ""
					site.target_id = target
					site.property_name = "needs or checks" if kind == "reads" else "changes"
					found.append(site)
	for storyline: StorylineDocument in project.storylines:
		for node: InspectableNode in storyline.nodes:
			look.call(node)
			for children: Variant in node.get_all_property_children():
				for child: Variant in children:
					if child is InspectableObject:
						look.call(child)
	return found


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
	await get_tree().process_frame
	if node == null or node.graph_view == null or not is_instance_valid(node.graph_view):
		return
	var graph: GraphEdit = node.graph_view.get_parent() as GraphEdit
	if graph is MonologueGraphEdit:
		(graph as MonologueGraphEdit).jumped.emit()
	if graph:
		graph.scroll_offset = node.graph_view.position_offset * graph.zoom - graph.size / 2.0 + node.graph_view.size * graph.zoom / 2.0


func _on_row_activated(tree: Tree) -> void:
	var item: TreeItem = tree.get_selected()
	if item == null:
		return
	_jump_to_object(str(item.get_metadata(0)))
