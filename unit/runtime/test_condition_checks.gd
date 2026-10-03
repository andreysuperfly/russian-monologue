extends GdUnitTestSuite

## Conditions as several checks (russian-monologue): AND / OR, NOT, "was at" a node,
## "carries" an item, and the old single check still deciding the same way.

var _project: MonologueProject
var _path: String
var _player: ScriptedPlayer
var _storyline: StorylineDocument


func before_test() -> void:
	MonologueRegistry.reset_instance()
	_path = "%s/conditions_%d.mnlp" % [create_temp_dir("mnlp"), randi()]
	_project = auto_free(MonologueProject.new())
	await _project.ready
	_player = ScriptedPlayer.new()
	add_child(_player)
	_storyline = _project.storylines[0]
	for node: InspectableNode in _storyline.nodes.duplicate():
		if node.get_type() != "root":
			_storyline.remove_node(node)


func after_test() -> void:
	MonologueRegistry.reset_instance()


func _node(type_name: String) -> InspectableNode:
	return _storyline.create_node(type_name)


func _wire(from_node: InspectableNode, to_node: InspectableNode, from_port: String = "") -> void:
	_storyline.add_connection(NodeConnection.create(
		from_node.get_id(), from_port if not from_port.is_empty() else from_node.get_type(),
		to_node.get_id(), to_node.get_type()))


func _say(text: String) -> InspectableNode:
	var line: InspectableNode = _node("sentence")
	line.get_property("line").set_value({"en": text})
	return line


func _variable(variable_name: String, initial: int) -> String:
	var item: CollectionItem = MonologueRegistry.get_instance().create_collection_item("variables", _project.command_manager)
	item.set_property_value("name", variable_name)
	item.set_property_value("type", "int")
	item.set_property_value("value", initial)
	var document: CollectionDocument = _project.get_collection("variables")
	var records: Array = document.get_value().duplicate(true)
	records.append(item._to_dict())
	document.set_property_value("variables", records)
	return str(item.get_property_value("id"))


func _play() -> MonologueSession:
	ProjectWriter.write_project(_project, _path)
	var graph: MonologueStoryGraph = MonologueStoryGraph.of(MonologueSource.open(_path))
	var session: MonologueSession = auto_free(MonologueSession.new(graph, _player, "en"))
	session.play()
	return session


## root → [give the key] → seen → branch(test) → "Yes." / "No."
func _branch_on(test: Dictionary, give_key: bool) -> Array:
	var cast: String = str((_project.get_collection_value("characters")[0] as Dictionary).get("id", ""))
	var seen: InspectableNode = _say("Seen.")
	var start: InspectableNode = _storyline.get_root()
	if give_key:
		var give: InspectableNode = _node("inventory")
		give.get_property("who").set_value(cast)
		give.get_property("item").set_value("item-KEY")
		give.get_property("operation").set_value("Give")
		give.get_property("quantity").set_value(1)
		_wire(start, give)
		_wire(give, seen)
	else:
		_wire(start, seen)
	var branch: InspectableNode = _node("condition")
	var filled: Dictionary = test.duplicate(true)
	for check: Dictionary in filled.get("checks", []):
		if check.get("node") == "SEEN": check["node"] = seen.get_id()
		if check.get("who") == "CAST": check["who"] = cast
	branch.get_property("test").set_value(filled)
	_wire(seen, branch)
	_wire(branch, _say("Yes."), "pass")
	_wire(branch, _say("No."), "fail")
	_play()
	return _player.said


func test_all_checks_must_hold_with_and() -> void:
	var detective: String = _variable("detective", 15)
	var said: Array = _branch_on({"join": "and", "checks": [
		{"kind": "variable", "variable": detective, "operator": ">=", "value": 12},
		{"kind": "visited", "node": "SEEN", "operator": ">=", "value": 1},
		{"kind": "item", "who": "CAST", "item": "item-KEY", "operator": ">=", "value": 1}]}, true)
	assert_array(said).is_equal(["Seen.", "Yes."])


func test_one_failing_check_fails_and() -> void:
	var detective: String = _variable("detective", 10)
	var said: Array = _branch_on({"join": "and", "checks": [
		{"kind": "variable", "variable": detective, "operator": ">=", "value": 12},
		{"kind": "visited", "node": "SEEN", "operator": ">=", "value": 1}]}, false)
	assert_array(said).is_equal(["Seen.", "No."])


func test_or_needs_only_one() -> void:
	var detective: String = _variable("detective", 10)
	var said: Array = _branch_on({"join": "or", "checks": [
		{"kind": "variable", "variable": detective, "operator": ">=", "value": 12},
		{"kind": "item", "who": "CAST", "item": "item-KEY", "operator": ">=", "value": 1}]}, true)
	assert_array(said).is_equal(["Seen.", "Yes."])


func test_not_turns_a_check_around() -> void:
	var said: Array = _branch_on({"join": "and", "checks": [
		{"kind": "item", "who": "CAST", "item": "item-KEY", "operator": ">=", "value": 1, "not": true}]}, false)
	assert_array(said).is_equal(["Seen.", "Yes."])


func test_the_old_single_check_still_decides() -> void:
	var gold: String = _variable("gold", 5)
	var said: Array = _branch_on({"variable": gold, "operator": ">=", "value": 5}, false)
	assert_array(said).is_equal(["Seen.", "Yes."])


func test_half_built_checks_are_left_out() -> void:
	var gold: String = _variable("gold", 0)
	var said: Array = _branch_on({"join": "and", "checks": [
		{"kind": "variable", "variable": "", "operator": ">=", "value": 99},
		{"kind": "variable", "variable": gold, "operator": "==", "value": 0}]}, false)
	assert_array(said).is_equal(["Seen.", "Yes."])
