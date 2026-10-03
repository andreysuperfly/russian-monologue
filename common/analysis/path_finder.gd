## Paths to a node, read backwards (russian-monologue): "what does it take to reach this ending?"
##
## Walks the flow wires from the target back to a start, crossing into other storylines where a
## storyline, jump or section node leads into the one being walked. Along the way it notes what the
## story needs: the option to pick, a condition to pass (or to fail), an event to fire.
## A path is complete when it reaches a root nothing leads into.
class_name PathFinder extends RefCounted

const MAX_PATHS: int = 30
const MAX_STEPS: int = 400
## Node types whose "target" leads into another storyline's root.
const ENTRY_TYPES: Array = ["storyline", "jump", "section"]


## Every path into [param node_id] (up to [constant MAX_PATHS]), each from its start to the target:
## [{"storyline": StorylineDocument, "node": InspectableNode, "need": String}]. "need" is what
## leaving that step towards the target takes — empty when nothing is asked.
static func paths_to(project: MonologueProject, storyline: StorylineDocument, node_id: String) -> Array:
	var found: Array = []
	_walk(project, storyline, node_id, [], {}, found)
	return found


## Needs every path shares — what is required no matter how you get there.
static func common_needs(paths: Array) -> PackedStringArray:
	var shared: PackedStringArray = PackedStringArray()
	if paths.is_empty():
		return shared
	for need: String in needs_of(paths[0]):
		var everywhere: bool = true
		for path: Array in paths:
			if not needs_of(path).has(need):
				everywhere = false
				break
		if everywhere and not shared.has(need):
			shared.append(need)
	return shared


static func needs_of(path: Array) -> PackedStringArray:
	var needs: PackedStringArray = PackedStringArray()
	for step: Dictionary in path:
		var need: String = str(step.get("need", ""))
		if not need.is_empty() and not needs.has(need):
			needs.append(need)
	return needs


static func _walk(
	project: MonologueProject, storyline: StorylineDocument, node_id: String,
	after: Array, seen: Dictionary, found: Array, need: String = ""
) -> void:
	if found.size() >= MAX_PATHS or after.size() > MAX_STEPS:
		return
	var key: String = "%s/%s" % [storyline.id, node_id]
	if seen.has(key):
		return
	var node: InspectableNode = storyline.get_node(node_id)
	if node == null:
		return
	# [param need] is what leaving this node towards the target asks of the story.
	var here: Array = after.duplicate()
	here.push_front({"storyline": storyline, "node": node, "need": need})
	var next_seen: Dictionary = seen.duplicate()
	next_seen[key] = true

	if node.get_type() == "root":
		var entries: Array = _entries_into(project, storyline)
		if entries.is_empty():
			found.append(here)
			return
		for entry: Array in entries:
			_walk(project, entry[0], (entry[1] as InspectableNode).get_id(), here, next_seen, found)
		return

	var incoming: Array[NodeConnection] = storyline.get_incoming(node_id, node.get_type())
	if incoming.is_empty():
		# Nothing leads here: still a path — it shows where the chain is cut.
		found.append(here)
		return
	for connection: NodeConnection in incoming:
		var from_node: InspectableNode = storyline.get_node(connection.from_node_id)
		if from_node != null:
			_walk(project, storyline, from_node.get_id(), here, next_seen, found, _need(project, from_node, connection))


## Storyline / jump / section nodes anywhere whose target is [param storyline].
static func _entries_into(project: MonologueProject, storyline: StorylineDocument) -> Array:
	var entries: Array = []
	for other: StorylineDocument in project.storylines:
		for node: InspectableNode in other.nodes:
			if node.get_type() in ENTRY_TYPES and node.get_property("target") != null:
				if str(node.get_property_value("target")) == storyline.id:
					entries.append([other, node])
	return entries


## What leaving [param from_node] along [param connection] asks of the story.
static func _need(project: MonologueProject, from_node: InspectableNode, connection: NodeConnection) -> String:
	match from_node.get_type():
		"condition":
			var phrase: String = NodePreview.condition(from_node.get_property_value("test"), project)
			if phrase.is_empty():
				return ""
			if connection.from_property == "fail":
				return "%s (%s)" % [TranslationServer.translate("NOT"), phrase]
			return phrase
		"event":
			var phrase: String = NodePreview.condition(from_node.get_property_value("test"), project)
			return "%s: %s" % [TranslationServer.translate("Event"), phrase] if not phrase.is_empty() else ""
		"choice":
			return _option_need(project, from_node, connection.from_item_id)
	return ""


static func _option_need(project: MonologueProject, choice: InspectableNode, item_id: String) -> String:
	var option_id: String = item_id.trim_prefix("ext_")
	var option: Dictionary = {}
	for entry: Variant in choice.get_property_value("choices"):
		if entry is Dictionary and str(entry.get("id", "")) == option_id:
			option = entry
	if option.is_empty():
		for storyline: StorylineDocument in project.storylines:
			var wired: InspectableNode = storyline.get_node(option_id)
			if wired != null:
				option = wired._to_dict()
	var text: Variant = option.get("text", {})
	var label: String = ""
	if text is Dictionary and not (text as Dictionary).is_empty():
		label = str((text as Dictionary).values()[0])
	var need: String = "%s «%s»" % [TranslationServer.translate("Pick"), NodePreview.trim(label)]
	if option.get("enable_condition", false) == true:
		var phrase: String = NodePreview.condition(option.get("condition"), project)
		if not phrase.is_empty():
			need += " — %s %s" % [TranslationServer.translate("shown if"), phrase]
	return need
