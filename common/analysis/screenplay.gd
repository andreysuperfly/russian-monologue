## The whole project as a script to read (russian-monologue): File → Export → Screenplay.
##
## Each storyline in story order from its root. Every step gets a number; branches point at
## numbers («→ [12]»), so the text reads top to bottom and still shows every way through.
## Nodes nothing leads to come last, under their own heading.
class_name Screenplay


static func text(project: MonologueProject, language: String = "") -> String:
	var out: PackedStringArray = PackedStringArray()
	var title: String = project.project_path.get_file().get_basename() if not project.project_path.is_empty() else TranslationServer.translate("Screenplay")
	out.append("# %s" % title)
	out.append("")
	for storyline: StorylineDocument in project.storylines:
		out.append_array(_storyline(project, storyline, language))
		out.append("")
	return "\n".join(out)


static func _storyline(project: MonologueProject, storyline: StorylineDocument, language: String) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("## %s" % storyline.name)
	lines.append("")
	# Story order: depth first from the root, following the flow wires.
	var order: Array = []
	var number: Dictionary = {}
	var root: InspectableNode = storyline.get_root()
	if root:
		_visit(storyline, root, order, number)
	var loose: Array = []
	for node: InspectableNode in storyline.nodes:
		if not number.has(node.get_id()) and _readable(node):
			loose.append(node)
	for node: InspectableNode in loose:
		_visit(storyline, node, order, number)
	var loose_ids: Dictionary = {}
	for node: InspectableNode in loose:
		loose_ids[node.get_id()] = true

	var heading_done: bool = false
	for node: InspectableNode in order:
		if loose_ids.has(node.get_id()) and not heading_done:
			lines.append("")
			lines.append("### %s" % TranslationServer.translate("Not connected to the start"))
			heading_done = true
		var step: String = _step(project, storyline, node, number, language)
		if step.is_empty():
			continue
		# a straight step names where it goes only when that is not simply the next line
		if not node.get_type() in ["choice", "condition", "end"]:
			var outs: Array = _flow_out(storyline, node)
			if outs.size() == 1:
				var next: int = int(number.get(_through_reroutes(storyline, (outs[0] as NodeConnection).to_node_id), 0))
				if next > 0 and next != int(number[node.get_id()]) + 1:
					step += "  → [%d]" % next
		lines.append("[%d] %s" % [number[node.get_id()], step])
	return lines


static func _visit(storyline: StorylineDocument, node: InspectableNode, order: Array, number: Dictionary) -> void:
	if number.has(node.get_id()) or not _readable(node):
		return
	number[node.get_id()] = order.size() + 1
	order.append(node)
	for connection: NodeConnection in _flow_out(storyline, node):
		var next: InspectableNode = storyline.get_node(connection.to_node_id)
		if next:
			_visit(storyline, next, order, number)


static func _readable(node: InspectableNode) -> bool:
	return not node.get_type() in ["reroute", "int", "float", "bool", "text"]


## Flow wires only: the ones arriving at the next node's own port, not at one of its values.
static func _flow_out(storyline: StorylineDocument, node: InspectableNode) -> Array:
	var flow: Array = []
	for connection: NodeConnection in storyline.get_outgoing(node.get_id()):
		var next: InspectableNode = storyline.get_node(connection.to_node_id)
		if next and connection.to_property == next.get_type():
			flow.append(connection)
	return flow


static func _target(storyline: StorylineDocument, node: InspectableNode, number: Dictionary, port: String = "", item: String = "") -> String:
	for connection: NodeConnection in _flow_out(storyline, node):
		if not port.is_empty() and connection.from_property != port:
			continue
		if not item.is_empty() and connection.from_item_id.trim_prefix("ext_") != item:
			continue
		var landing: String = _through_reroutes(storyline, connection.to_node_id)
		if number.has(landing):
			return "→ [%d]" % number[landing]
	return "→ " + TranslationServer.translate("nowhere")


## A reroute only bends a wire: where it really goes is wherever the bends end.
static func _through_reroutes(storyline: StorylineDocument, node_id: String) -> String:
	var seen: Dictionary = {}
	var current: String = node_id
	while not seen.has(current):
		seen[current] = true
		var node: InspectableNode = storyline.get_node(current)
		if node == null or node.get_type() != "reroute":
			return current
		var outs: Array = _flow_out(storyline, node)
		if outs.is_empty():
			return current
		current = (outs[0] as NodeConnection).to_node_id
	return current


static func _step(project: MonologueProject, storyline: StorylineDocument, node: InspectableNode, number: Dictionary, language: String) -> String:
	var t: Callable = func(key: String) -> String: return TranslationServer.translate(key)
	match node.get_type():
		"root":
			return "— %s —" % t.call("start")
		"sentence":
			var who: String = ReferenceResolver.resolve_label(project, "characters", str(node.get_property_value("speaker")))
			var said: String = Util.to_label(node.get_property_value("line"), language)
			return "%s: %s" % [who.to_upper() if not who.is_empty() else "—", said]
		"choice":
			var parts: PackedStringArray = PackedStringArray(["%s:" % t.call("Choice").to_upper()])
			var index: int = 1
			for option: Variant in node.get_property_value("choices"):
				if option is not Dictionary:
					continue
				var label: String = Util.to_label(option.get("text", {}), language)
				var condition: String = ""
				if option.get("enable_condition", false) == true:
					condition = " (%s %s)" % [t.call("shown if"), NodePreview.condition(option.get("condition"), project)]
				parts.append("    %d) «%s»%s %s" % [index, label, condition, _target(storyline, node, number, "choices", str(option.get("id", "")))])
				index += 1
			# options wired in as nodes of their own
			for connection: NodeConnection in storyline.get_incoming(node.get_id(), "choices"):
				var wired: InspectableNode = storyline.get_node(connection.from_node_id)
				if wired == null or wired.get_type() != "option":
					continue
				var label: String = Util.to_label(wired.get_property_value("text"), language)
				parts.append("    %d) «%s» %s" % [index, label, _target(storyline, node, number, "choices", wired.get_id())])
				index += 1
			return "\n".join(parts)
		"condition":
			return "%s %s — %s %s, %s %s" % [t.call("IF"), NodePreview.condition(node.get_property_value("test"), project),
				t.call("yes"), _target(storyline, node, number, "pass"), t.call("no"), _target(storyline, node, number, "fail")]
		"variable":
			var variable: String = ReferenceResolver.resolve_label(project, "variables", str(node.get_property_value("target")))
			return "%s %s %s" % [variable, str(node.get_property_value("operator")), str(node.get_property_value("value"))]
		"inventory":
			var who: String = ReferenceResolver.resolve_label(project, "characters", str(node.get_property_value("who")))
			var item: String = ReferenceResolver.resolve_label(project, "items", str(node.get_property_value("item")))
			return "%s: %s «%s» × %s (%s)" % [t.call(str(node.get_property_value("operation"))), who, item, str(node.get_property_value("quantity")), t.call("pockets")]
		"end":
			return "■ %s" % t.call("End")
		"storyline", "jump", "section":
			var into: String = ""
			for other: StorylineDocument in project.storylines:
				if other.id == str(node.get_property_value("target")):
					into = other.name
			return "%s «%s»" % [t.call(node.get_type().capitalize()), into]
		"action":
			return "%s: %s %s" % [t.call("Action"), str(node.get_property_value("name")), str(node.get_property_value("arguments"))]
		"note":
			return "// %s" % str(node.get_property_value("note")).replace("\n", " ")
	var label: String = NodePreview.node_label(project, node.get_id())
	return "[%s] %s" % [t.call(node.get_type().capitalize()), label]
