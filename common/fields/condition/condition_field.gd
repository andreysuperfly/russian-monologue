class_name ConditionField extends Field
## A condition as a list of checks joined by AND / OR (russian-monologue).
##
## Each row is one check: a variable compared with a value, "was at" a node (how many times the
## story passed through it — tracked by the runtime, no flag needed), or "carries" an item. Any row
## can be negated with NOT. Values written by the original single-check field still load: they
## become the first row. Storage format: see MonologueCondition.checks_of.

const VARIABLES_COLLECTION: String = "variables"
const OPERATORS_BY_TYPE: Dictionary = {
	"bool": ["==", "!="],
	"int": ["==", "!=", ">", ">=", "<", "<="],
	"float": ["==", "!=", ">", ">=", "<", "<="],
	"string": ["==", "!=", "contains", "fuzzy"],
}
const COUNT_OPERATORS: Array = [">=", "==", "<=", ">", "<", "!="]
const FIELD_TYPE_BY_VARIABLE_TYPE: Dictionary = {
	"bool": "bool",
	"int": "int",
	"float": "float",
	"string": "text",
}
const KINDS: Array = ["variable", "visited", "item"]
const KIND_LABELS: Dictionary = {"variable": "Variable", "visited": "Was at", "item": "Carries"}
const MISSING_LABEL: String = "⚠ Missing (%s)"

var _join: String = "and"
var _checks: Array = []
var _editable: bool = true
var _rows: VBoxContainer
var _join_dropdown: OptionButton
var _add_button: Button


func _on_initialize() -> void:
	if _rows != null:
		return
	_rows = VBoxContainer.new()
	add_child(_rows)

	var footer: HBoxContainer = HBoxContainer.new()
	_join_dropdown = _narrow(OptionButton.new())
	_join_dropdown.add_item("All of them (AND)")
	_join_dropdown.add_item("Any of them (OR)")
	_join_dropdown.tooltip_text = "How the checks combine."
	_join_dropdown.item_selected.connect(_on_join_selected)
	footer.add_child(_join_dropdown)
	_add_button = Button.new()
	_add_button.text = "+ Check"
	_add_button.tooltip_text = "Add one more check."
	_add_button.pressed.connect(_on_add_pressed)
	footer.add_child(_add_button)
	add_child(footer)


func set_value(value: Variant) -> void:
	if not is_node_ready():
		await ready
	_on_initialize()
	_checks = []
	_join = "and"
	if value is Dictionary:
		var data: Dictionary = value
		if data.has("checks"):
			_join = str(data.get("join", "and"))
			for check: Variant in data.get("checks", []):
				if check is Dictionary:
					_checks.append((check as Dictionary).duplicate(true))
		elif not str(data.get("variable", "")).is_empty():
			var old: Dictionary = data.duplicate(true)
			old["kind"] = "variable"
			_checks.append(old)
	_rebuild()


## Label above, rows at full width: a narrow inspector cannot fit a label beside them.
func prefers_vertical_layout(_settings: Dictionary) -> bool:
	return true


func get_value() -> Variant:
	return {"join": _join, "checks": _checks.duplicate(true)}


func set_editable(is_editable: bool) -> void:
	_editable = is_editable
	_rebuild()


## Dropdowns shrink with a narrow inspector and clip long names instead of pushing past the edge.
static func _narrow(box: OptionButton) -> OptionButton:
	box.clip_text = true
	box.fit_to_longest_item = false
	box.custom_minimum_size.x = 40
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	return box


func _commit() -> void:
	emit_value_committed(get_value())


func _on_join_selected(index: int) -> void:
	_join = "or" if index == 1 else "and"
	_rebuild()
	_commit()


func _on_add_pressed() -> void:
	_checks.append({"kind": "variable", "variable": "", "operator": ">=", "value": 0, "not": false})
	_rebuild()
	_commit()


# ---------- rows ----------

func _rebuild() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		child.queue_free()
	for index: int in _checks.size():
		_rows.add_child(_build_row(index))
	_join_dropdown.selected = 1 if _join == "or" else 0
	_join_dropdown.visible = _checks.size() > 1
	_join_dropdown.disabled = not _editable
	_add_button.disabled = not _editable


func _build_row(index: int) -> Control:
	var check: Dictionary = _checks[index]
	var box: VBoxContainer = VBoxContainer.new()
	if index > 0:
		# «— И —» между условиями: связка видна, но не отнимает места у выбора
		var divider: HBoxContainer = HBoxContainer.new()
		var left: HSeparator = HSeparator.new()
		left.size_flags_horizontal = SIZE_EXPAND_FILL
		var right: HSeparator = HSeparator.new()
		right.size_flags_horizontal = SIZE_EXPAND_FILL
		var glue: Label = Label.new()
		glue.text = "OR" if _join == "or" else "AND"
		glue.modulate = Color(1, 1, 1, 0.6)
		divider.add_child(left)
		divider.add_child(glue)
		divider.add_child(right)
		box.add_child(divider)
	var line: HBoxContainer = HBoxContainer.new()
	box.add_child(line)

	var negate: Button = Button.new()
	negate.text = "NOT"
	negate.toggle_mode = true
	negate.button_pressed = check.get("not", false) == true
	negate.tooltip_text = "Turn this check around: true becomes false."
	negate.disabled = not _editable
	negate.toggled.connect(func(on: bool) -> void:
		check["not"] = on
		_commit())
	line.add_child(negate)

	var kind: OptionButton = _narrow(OptionButton.new())
	for k: String in KINDS:
		kind.add_item(KIND_LABELS[k])
	var current_kind: String = str(check.get("kind", "variable"))
	kind.selected = maxi(0, KINDS.find(current_kind))
	kind.size_flags_horizontal = SIZE_EXPAND_FILL
	kind.disabled = not _editable
	kind.item_selected.connect(func(i: int) -> void:
		_checks[index] = _fresh_check(KINDS[i], check.get("not", false) == true)
		_rebuild()
		_commit())
	line.add_child(kind)

	var remove: Button = Button.new()
	remove.text = "✕"
	remove.tooltip_text = "Remove this check."
	remove.disabled = not _editable
	remove.pressed.connect(func() -> void:
		_checks.remove_at(index)
		_rebuild()
		_commit())
	line.add_child(remove)

	# каждый выбор — своей строкой во всю ширину: инспектор узкий, в одну линию не помещается
	match current_kind:
		"visited":
			box.add_child(_picker(_node_entries(), str(check.get("node", "")), func(id: String) -> void: check["node"] = id))
			_add_count(box, check)
		"item":
			box.add_child(_picker(_collection_entries("characters"), str(check.get("who", "")), func(id: String) -> void: check["who"] = id))
			box.add_child(_picker(_collection_entries("items"), str(check.get("item", "")), func(id: String) -> void: check["item"] = id))
			_add_count(box, check)
		_:
			_build_variable_body(box, check)
	return box


func _fresh_check(kind: String, negated: bool) -> Dictionary:
	match kind:
		"visited": return {"kind": "visited", "node": "", "operator": ">=", "value": 1, "not": negated}
		"item": return {"kind": "item", "who": "", "item": "", "operator": ">=", "value": 1, "not": negated}
	return {"kind": "variable", "variable": "", "operator": ">=", "value": 0, "not": negated}


## Dropdown of [id, label] entries; picking one writes the id through [param assign] and commits.
func _picker(entries: Array, selected_id: String, assign: Callable) -> OptionButton:
	var box: OptionButton = _narrow(OptionButton.new())
	box.add_item("—")
	box.set_item_metadata(0, "")
	var found: bool = selected_id.is_empty()
	for entry: Array in entries:
		box.add_item(entry[1])
		box.set_item_metadata(box.item_count - 1, entry[0])
		if entry[0] == selected_id:
			box.selected = box.item_count - 1
			found = true
	if not found:
		box.add_item(tr(MISSING_LABEL) % selected_id)
		box.set_item_metadata(box.item_count - 1, selected_id)
		box.set_item_disabled(box.item_count - 1, true)
		box.selected = box.item_count - 1
	box.disabled = not _editable
	box.item_selected.connect(func(i: int) -> void:
		assign.call(str(box.get_item_metadata(i)))
		_rebuild()
		_commit())
	return box


## «≥ 1»: comparison and a whole number, for visits and item counts.
func _add_count(parent: VBoxContainer, check: Dictionary) -> void:
	var body: HBoxContainer = HBoxContainer.new()
	parent.add_child(body)
	var op: OptionButton = OptionButton.new()
	op.fit_to_longest_item = false
	for o: String in COUNT_OPERATORS:
		op.add_item(NodePreview.symbol(o))
	op.selected = maxi(0, COUNT_OPERATORS.find(str(check.get("operator", ">="))))
	op.disabled = not _editable
	op.item_selected.connect(func(i: int) -> void:
		check["operator"] = COUNT_OPERATORS[i]
		_commit())
	body.add_child(op)
	var count: SpinBox = SpinBox.new()
	count.min_value = 0
	count.max_value = 999
	count.value = int(check.get("value", 1))
	count.editable = _editable
	count.value_changed.connect(func(v: float) -> void:
		check["value"] = int(v)
		_commit())
	body.add_child(count)


func _build_variable_body(parent: VBoxContainer, check: Dictionary) -> void:
	var variables: Dictionary = _variables()
	var entries: Array = []
	for id: String in variables:
		entries.append([id, variables[id]["name"]])
	var variable_id: String = str(check.get("variable", ""))
	parent.add_child(_picker(entries, variable_id, func(id: String) -> void:
		check["variable"] = id
		check["value"] = _default_value_for_type(variables.get(id, {}).get("type", "string"))))
	if variable_id.is_empty():
		return
	var body: HBoxContainer = HBoxContainer.new()
	parent.add_child(body)

	var var_type: String = variables.get(variable_id, {}).get("type", "string")
	var operators: Array = OPERATORS_BY_TYPE.get(var_type, OPERATORS_BY_TYPE["string"])
	var op: OptionButton = OptionButton.new()
	op.fit_to_longest_item = false
	for o: String in operators:
		op.add_item(NodePreview.symbol(o))
	var current: String = str(check.get("operator", operators[0]))
	if not operators.has(current):
		current = operators[0]
		check["operator"] = current
	op.selected = operators.find(current)
	op.disabled = not _editable
	op.item_selected.connect(func(i: int) -> void:
		check["operator"] = operators[i]
		_commit())
	body.add_child(op)

	var widget: Control = FieldWidgetFactory.create_or_placeholder(FIELD_TYPE_BY_VARIABLE_TYPE.get(var_type, "text"))
	if widget == null:
		return
	widget.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(widget)
	if widget is Field:
		var field: Field = widget
		# No binding on purpose: the widget belongs to this check, not to a property of its own.
		# Set up once it is in the tree — its own child controls exist only then.
		var setup: Callable = func() -> void:
			field.initialize()
			field.set_value(check.get("value") if check.get("value") != null else _default_value_for_type(var_type))
			field.set_editable(_editable)
			field.value_committed.connect(func(v: Variant) -> void:
				check["value"] = v
				_commit())
		if field.is_node_ready():
			setup.call()
		else:
			field.ready.connect(setup, CONNECT_ONE_SHOT)


# ---------- what can be picked ----------

func _variables() -> Dictionary:
	var found: Dictionary = {}
	var project: MonologueProject = ProjectManager.current_project
	if project == null:
		return found
	for entry: Variant in project.get_collection_value(VARIABLES_COLLECTION):
		if entry is Dictionary and not str(entry.get("name", "")).is_empty():
			found[str(entry.get("id", ""))] = {"name": str(entry.get("name")), "type": str(entry.get("type", "string"))}
	return found


func _collection_entries(collection: String) -> Array:
	var entries: Array = []
	var project: MonologueProject = ProjectManager.current_project
	if project == null:
		return entries
	for entry: Variant in project.get_collection_value(collection):
		if entry is Dictionary:
			entries.append([str(entry.get("id", "")), str(entry.get("name", entry.get("id", "")))])
	return entries


## Every node that can be passed through, as «storyline · label». Roots, reroutes and values are left out.
func _node_entries() -> Array:
	var entries: Array = []
	var project: MonologueProject = ProjectManager.current_project
	if project == null:
		return entries
	for storyline: StorylineDocument in project.storylines:
		for node: InspectableNode in storyline.nodes:
			if node.get_type() in ["root", "reroute", "int", "float", "bool", "text", "option"]:
				continue
			entries.append([node.get_id(), "%s · %s" % [storyline.name, NodePreview.node_label(project, node.get_id())]])
	return entries


func _default_value_for_type(variable_type: String) -> Variant:
	match variable_type:
		"bool": return false
		"int": return 0
		"float": return 0.0
		"string": return ""
	return null
