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
var _usage_target: OptionButton
var _usages: Tree
var _path_target: OptionButton
var _paths: Tree


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
	tabs.add_child(usages_page)
	_usage_target = OptionButton.new()
	_usage_target.item_selected.connect(func(_i: int) -> void: _fill_usages())
	usages_page.add_child(_usage_target)
	_usages = _make_tree(["Where", "Field"])
	_usages.item_activated.connect(_on_row_activated.bind(_usages))
	usages_page.add_child(_usages)

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
	_usage_target.clear()
	var project: MonologueProject = ProjectManager.current_project
	if project == null:
		return
	for collection: String in ["variables", "items", "characters"]:
		for record: Variant in project.get_collection_value(collection):
			if record is Dictionary:
				_usage_target.add_item("%s: %s" % [tr(collection), str(record.get("name", record.get("id", "")))])
				_usage_target.set_item_metadata(_usage_target.item_count - 1, str(record.get("id", "")))
	_fill_usages()


func _fill_usages() -> void:
	_usages.clear()
	var root: TreeItem = _usages.create_item()
	var project: MonologueProject = ProjectManager.current_project
	if project == null or _usage_target.selected < 0:
		return
	var target: String = str(_usage_target.get_item_metadata(_usage_target.selected))
	var sites: Array[ReferenceSite] = project.get_object_registry().get_referrers(target)
	for site: ReferenceSite in sites:
		_add_row(root, [_where(project, site.owner_id, site.document_name), tr(site.property_name)], site.owner_id)
	if sites.is_empty():
		_add_row(root, [tr("Not used anywhere."), ""], "")


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


func _on_row_activated(tree: Tree) -> void:
	var item: TreeItem = tree.get_selected()
	if item == null:
		return
	_jump_to_object(str(item.get_metadata(0)))
