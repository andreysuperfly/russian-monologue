## Templates (russian-monologue): a group of nodes with the wires between them, saved under a name
## in the project and dropped into any storyline later — "meeting a character", "finding an item".
##
## Stored in the project settings under "templates": name → {"nodes": [node dicts],
## "connections": [wire dicts]}. Inserting gives every node (and every option inside a choice) a
## fresh id, so a template can go in many times.
class_name GraphTemplates

const SETTING: String = "templates"
const ID_PATTERN: String = "^[a-z_]+-[0-9A-Z]{8}$"
## Inserted this far right of the rightmost node already there.
const GAP: float = 320.0


static func names(project: MonologueProject) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray(_all(project).keys())
	found.sort()
	return found


static func save(project: MonologueProject, storyline: StorylineDocument, nodes: Array[InspectableNode], template_name: String) -> void:
	var ids: Dictionary = {}
	var data: Array = []
	for node: InspectableNode in nodes:
		ids[node.get_id()] = true
		data.append(node._to_dict())
	var wires: Array = []
	for connection: NodeConnection in storyline.connections:
		if ids.has(connection.from_node_id) and ids.has(connection.to_node_id):
			wires.append({
				"from": connection.from_node_id, "from_property": connection.from_property,
				"from_item": connection.from_item_id, "to": connection.to_node_id,
				"to_property": connection.to_property, "to_item": connection.to_item_id,
			})
	var all: Dictionary = _all(project)
	all[template_name] = {"nodes": data, "connections": wires}
	project.settings.get_property(SETTING).set_value(all)


static func remove(project: MonologueProject, template_name: String) -> void:
	var all: Dictionary = _all(project)
	all.erase(template_name)
	project.settings.get_property(SETTING).set_value(all)


## Adds a fresh copy to [param storyline] (undoable for the nodes) and returns the new nodes.
static func insert(project: MonologueProject, storyline: StorylineDocument, template_name: String) -> Array:
	var template: Dictionary = _all(project).get(template_name, {})
	if template.is_empty():
		return []
	# Fresh ids for every node and every item inside one, then the same swap through the wires.
	var text: String = JSON.stringify(template)
	var swap: Dictionary = {}
	_collect_ids(template.get("nodes", []), swap)
	for old: String in swap:
		text = text.replace("\"%s\"" % old, "\"%s\"" % swap[old])
	var fresh: Dictionary = JSON.parse_string(text)

	var shift: Vector2 = _placement(storyline, fresh.get("nodes", []))
	var made: Array = []
	for node_data: Dictionary in fresh.get("nodes", []):
		var node: InspectableNode = MonologueRegistry.get_instance().create_node(str(node_data.get("$type", "")), storyline.history)
		if node == null:
			continue
		node._from_dict(node_data)
		var at: Vector2 = node.get_editor_position() + shift
		node.get_property("editor_position").value = [at.x, at.y]
		made.append(node)
	storyline.history.execute(AddNodesCommand.new(storyline.id, made))
	for wire: Dictionary in fresh.get("connections", []):
		var connection: NodeConnection = NodeConnection.create(
			str(wire["from"]), str(wire["from_property"]), str(wire["to"]), str(wire["to_property"]))
		connection.from_item_id = str(wire.get("from_item", ""))
		connection.to_item_id = str(wire.get("to_item", ""))
		storyline.add_connection(connection)
	EventBus.refresh_graph.emit()
	return made


static func _all(project: MonologueProject) -> Dictionary:
	var value: Variant = project.settings.get_property_value(SETTING) if project else {}
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


## Every "id" inside the node dicts, nested ones too, mapped to a new one of the same kind.
static func _collect_ids(value: Variant, swap: Dictionary) -> void:
	var pattern: RegEx = RegEx.create_from_string(ID_PATTERN)
	if value is Dictionary:
		for key: Variant in value:
			if str(key) == "id" and value[key] is String and pattern.search(value[key]) and not swap.has(value[key]):
				var kind: String = str(value[key]).get_slice("-", 0)
				swap[value[key]] = IDGen.generate_object_id(kind)
			else:
				_collect_ids(value[key], swap)
	elif value is Array:
		for entry: Variant in value:
			_collect_ids(entry, swap)


## Puts the copy to the right of everything already in the storyline, top-aligned.
static func _placement(storyline: StorylineDocument, nodes: Array) -> Vector2:
	var right: float = 0.0
	var top: float = INF
	for node: InspectableNode in storyline.nodes:
		right = maxf(right, node.get_editor_position().x)
	var left: float = INF
	for node_data: Dictionary in nodes:
		var at: Array = node_data.get("editor_position", [0.0, 0.0])
		left = minf(left, float(at[0]))
		top = minf(top, float(at[1]))
	if left == INF:
		return Vector2.ZERO
	return Vector2(right + GAP - left, -top)
