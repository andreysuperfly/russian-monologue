## The pieces a node's preview is built from.
##
## A preview is any [Control] the node cares to build, so this is not the only way to make
## one. It is the set of parts most of them need.
##
## Everything that reads a value trims it. A reference pointing at nothing reads as nothing.
## Nothing here reports an id.
class_name NodePreview

## How tall one line of preview is, and the shortest the view will draw one.
const LINE_HEIGHT: float = 18.0
## How much of one piece of free text survives, leaving room for what frames it.
const MAX_PIECE: int = 26


## One line of BBCode. Runs off its own edge instead of wrapping, and the view clips it.
static func line(bbcode: String) -> RichTextLabel:
	var label: RichTextLabel = RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = bbcode
	label.fit_content = false
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_contents = true
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.theme_type_variation = "GraphNodeViewPreviewLabel"
	label.custom_minimum_size.y = LINE_HEIGHT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## Several wrapped lines (russian-monologue): reading a card without opening it, like Yarn
## Spinner's graph. Cut after [param max_lines]; on a coloured card when [param tint] is given.
static func paragraph(bbcode: String, max_lines: int = 3, tint: Color = Color(0, 0, 0, 0)) -> Control:
	var label: RichTextLabel = RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = bbcode
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.theme_type_variation = "GraphNodeViewPreviewLabel"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# ~38 characters a line at a usual node width; longer text was already cut by the caller
	label.custom_minimum_size.y = LINE_HEIGHT * mini(max_lines, maxi(1, ceili(float(label.get_parsed_text().length()) / 32.0)))
	if tint.a <= 0.0:
		return label
	var card: PanelContainer = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(tint, 0.22)
	style.border_color = tint
	style.border_width_left = 3
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	card.add_theme_stylebox_override("panel", style)
	card.add_child(label)
	# the view sizes a preview by its minimum height, so the card carries the label's
	card.custom_minimum_size.y = label.custom_minimum_size.y + 8.0
	return card


## [param preview] with the picture of what [param property] names in front of it (a speaker's
## face, an item's icon); the preview alone when pictures are off or there is none.
static func with_picture(node: InspectableNode, property: String, scope: String, preview: Control, size: int = 22) -> Control:
	if preview == null:
		return null
	var badge: Control = Pictures.badge(ProjectManager.current_project, scope, str(node.get_property_value(property)), size)
	if badge == null:
		return preview
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var box: HBoxContainer = HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_theme_constant_override("separation", 7)
	box.add_child(badge)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(preview)
	box.custom_minimum_size.y = maxf(preview.custom_minimum_size.y, size)
	return box


static func row(pieces: Array) -> HBoxContainer:
	var box: HBoxContainer = HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.custom_minimum_size.y = LINE_HEIGHT
	for piece: Variant in pieces:
		if piece is Control:
			box.add_child(piece)
	return box


## The stage seen from above. One mark per place, the taken one lit.
static func stage(taken: String, places: Array, mark_tint: Color) -> Control:
	var strip: HBoxContainer = HBoxContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_PASS
	strip.add_theme_constant_override("separation", 2)

	for place: Variant in places:
		var mark: ColorRect = ColorRect.new()
		mark.mouse_filter = Control.MOUSE_FILTER_PASS
		mark.custom_minimum_size = Vector2(8.0, LINE_HEIGHT - 8.0)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.color = mark_tint if str(place) == taken else Color(mark_tint, 0.2)
		strip.add_child(mark)

	return strip


## A line the author wrote is not markup, however many brackets are in it.
static func plain(text: String) -> String:
	return text.replace("[", "[lb]")


## One line, no longer than [param budget], ending in an ellipsis when it was cut.
static func trim(text: String, budget: int = MAX_PIECE) -> String:
	var flat: String = text.strip_edges().replace("\n", " ")
	if flat.length() <= budget:
		return flat
	return "%s…" % flat.substr(0, budget - 1).strip_edges(false, true)


## What a reference property points at, by name. Pointing at nothing, or at something gone,
## reads as nothing. A property that is not a reference reads as its own value.
static func named(node: InspectableNode, property_name: String) -> String:
	var property: Property = node.get_property(property_name)
	if property == null:
		return ""

	var scope: String = _scope_of(property)
	if scope.is_empty():
		return trim(str(property.get_value()))

	var project: MonologueProject = ProjectManager.current_project
	if project == null:
		return ""
	return trim(ReferenceResolver.resolve_label(project, scope, str(property.get_value()), node))


## The same name, wearing the colour whatever it points at carries. Ready for [method line].
static func tinted(node: InspectableNode, property_name: String) -> String:
	var written: String = named(node, property_name)
	if written.is_empty():
		return ""
	return "[color=#%s]%s[/color]" % [tint(node, property_name).to_html(false), plain(written)]


## The colour of whatever a reference points at, white when it carries none.
static func tint(node: InspectableNode, property_name: String) -> Color:
	var property: Property = node.get_property(property_name)
	var project: MonologueProject = ProjectManager.current_project
	if property == null or project == null:
		return Color.WHITE

	var written: String = ReferenceResolver.resolve_property(
		project, _scope_of(property), str(property.get_value()), "color", node
	)
	return Color(written) if written.is_valid_html_color() else Color.WHITE


## A translated property as the reader sees it in [param language].
static func said(node: InspectableNode, property_name: String, language: String) -> String:
	return trim(Util.to_label(node.get_property_value(property_name), language))


## A condition as it reads, such as "gold >= 3". Empty when it names no variable.
## What a variable means in plain words, from its «In plain words» field; "" when it has none.
static func human(project: MonologueProject, variable_id: String) -> String:
	if project == null or variable_id.is_empty():
		return ""
	for record: Variant in project.get_collection_value("variables"):
		if record is Dictionary and str((record as Dictionary).get("id", "")) == variable_id:
			return Util.to_label((record as Dictionary).get("human", ""))
	return ""


static func condition(test: Variant, in_project: MonologueProject = null) -> String:
	var project: MonologueProject = in_project if in_project != null else ProjectManager.current_project
	if project == null:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for check: Dictionary in MonologueCondition.checks_of(test):
		parts.append(_check_phrase(project, check))
	var glue: String = " %s " % TranslationServer.translate("OR" if MonologueCondition.joins_with_or(test) else "AND")
	return glue.join(parts)


## One check as a phrase (russian-monologue): «Детективность ≥ 12», «был в «Нюра» »,
## «у Джиниуса есть «Кассета»», with «НЕ» in front when it is negated.
static func _check_phrase(project: MonologueProject, check: Dictionary) -> String:
	var op: String = str(check.get("operator", ">="))
	var value: Variant = check.get("value", 1)
	var phrase: String
	match str(check.get("kind", "variable")):
		"visited":
			phrase = "%s «%s»" % [TranslationServer.translate("was at"), trim(node_label(project, str(check.get("node", ""))))]
			if not (op == ">=" and int(value) == 1):
				phrase += " %s %s" % [symbol(op), str(value)]
		"item":
			var who: String = ReferenceResolver.resolve_label(project, "characters", str(check.get("who", "")))
			var item: String = ReferenceResolver.resolve_label(project, "items", str(check.get("item", "")))
			phrase = "%s %s «%s»" % [trim(who), TranslationServer.translate("carries"), trim(item)]
			if not (op == ">=" and int(value) == 1):
				phrase += " %s %s" % [symbol(op), str(value)]
		_:
			var variable: String = ReferenceResolver.resolve_label(project, "variables", str(check.get("variable", "")))
			var said: String = human(project, str(check.get("variable", "")))
			var yes_no: Variant = check.get("value")
			# «дверь выбита» / «НЕ дверь выбита» for a yes/no flag that has words (russian-monologue)
			if not said.is_empty() and yes_no is bool and str(check.get("operator", "==")) in ["==", "="]:
				phrase = said if yes_no else "%s %s" % [TranslationServer.translate("NOT"), said]
			else:
				phrase = "%s %s %s" % [trim(said if not said.is_empty() else variable), symbol(str(check.get("operator", "=="))), literal(check.get("value"))]
	if check.get("not", false) == true:
		phrase = "%s %s" % [TranslationServer.translate("NOT"), phrase]
	return phrase


## Comparison signs as people write them.
static func symbol(op: String) -> String:
	return {">=": "≥", "<=": "≤", "!=": "≠", "==": "="}.get(op, op)


## A node by its label, looked up across every storyline; its id when it has no label.
static func node_label(project: MonologueProject, node_id: String) -> String:
	for storyline: StorylineDocument in project.storylines:
		var node: InspectableNode = storyline.get_node(node_id)
		if node != null:
			var label: String = str(node.get_property_value("label")) if node.get_property("label") != null else ""
			return label if not label.is_empty() else node_id
	return node_id


## A stored value as it would be written. A string in quotes, a boolean as a word.
static func literal(value: Variant) -> String:
	if value is String:
		return '"%s"' % trim(value)
	if value is bool:
		return TranslationServer.translate("yes") if value else TranslationServer.translate("no")
	# 15, not 15.0 (russian-monologue)
	if value is float and value == floorf(value) and absf(value) < 1e15:
		return str(int(value))
	return str(value)


static func file(path: String) -> String:
	return trim(path.get_file())


## A duration written as short as it reads: "2s", "0.5s".
static func seconds(value: float) -> String:
	var written: String = String.num(value, 2)
	if written.contains("."):
		written = written.rstrip("0").rstrip(".")
	return "%ss" % written


## [param count] of [param thing], named in the plural when there is not exactly one.
static func counted(count: int, thing: String) -> String:
	return "%d %s%s" % [count, thing, "" if count == 1 else "s"]


static func _scope_of(property: Property) -> String:
	return str(property.get_settings_value(PropertySettings.KEY_REFERENCE_SCOPE, ""))
