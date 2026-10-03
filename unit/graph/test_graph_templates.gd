extends GdUnitTestSuite

## Templates (russian-monologue): nodes and the wires between them, saved and inserted again.

func before_test() -> void:
	MonologueRegistry.reset_instance()


func after_test() -> void:
	ProjectManager.current_project = null
	MonologueRegistry.reset_instance()


func test_a_template_comes_back_with_its_wires_and_new_ids() -> void:
	var project: MonologueProject = auto_free(MonologueProject.new())
	await project.ready
	ProjectManager.current_project = project
	var storyline: StorylineDocument = project.storylines[0]
	var ask: InspectableNode = storyline.create_node("sentence")
	ask.get_property("line").set_value({"en": "Who are you?"})
	var choice: InspectableNode = storyline.create_node("choice")
	storyline.add_connection(NodeConnection.create(ask.get_id(), "sentence", choice.get_id(), "choice"))
	var picked: Array[InspectableNode] = [ask, choice]
	GraphTemplates.save(project, storyline, picked, "meeting")

	var before_nodes: int = storyline.nodes.size()
	var before_wires: int = storyline.connections.size()
	var first: Array = GraphTemplates.insert(project, storyline, "meeting")
	var second: Array = GraphTemplates.insert(project, storyline, "meeting")

	assert_int(first.size()).is_equal(2)
	assert_int(storyline.nodes.size()).is_equal(before_nodes + 4)
	assert_int(storyline.connections.size()).is_equal(before_wires + 2)
	var ids: Array = []
	for node: InspectableNode in storyline.nodes:
		ids.append(node.get_id())
	var unique: Dictionary = {}
	for id: String in ids:
		unique[id] = true
	assert_int(unique.size()).override_failure_message("Inserted nodes share ids.").is_equal(ids.size())
	assert_str(str((first[0] as InspectableNode).get_property_value("line").values()[0])).is_equal("Who are you?")
	assert_array(GraphTemplates.names(project)).contains(["meeting"])
