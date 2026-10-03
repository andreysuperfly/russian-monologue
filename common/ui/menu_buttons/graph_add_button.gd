extends EditorMenuButton

var graph_dict: Dictionary = {}


func _build_menu() -> void:
	var registry: MonologueRegistry = MonologueRegistry.get_instance()
	var id: int = 0
	for category: String in registry.list_categories(MonologueObjectType.NODE):
		var submenu: PopupMenu = add_submenu_row(category, _on_add_node)

		for node: MonologueIndexer in registry.list_by_category(MonologueObjectType.NODE, category):
			# A storyline creates its own singletons. There is never a second one to add.
			if (node as NodeIndexer).is_singleton:
				continue
			submenu.add_item(node.get_display_name(), id)
			graph_dict[id] = node.name
			id += 1

	# Templates saved in this project (russian-monologue)
	var project: MonologueProject = ProjectManager.current_project
	var saved: PackedStringArray = GraphTemplates.names(project) if project else PackedStringArray()
	var templates: PopupMenu = add_submenu_row("Templates", _on_add_template, not saved.is_empty())
	for template_name: String in saved:
		templates.add_item(template_name)


func _on_add_template(item_id: int) -> void:
	var project: MonologueProject = ProjectManager.current_project
	var saved: PackedStringArray = GraphTemplates.names(project)
	var graph: MonologueGraphEdit = _find_graph(get_tree().root)
	var storyline_id: String = graph.storyline_id if graph else ""
	var storyline: StorylineDocument = project.get_storyline(storyline_id) if not storyline_id.is_empty() else project.storylines[0]
	if item_id >= 0 and item_id < saved.size():
		GraphTemplates.insert(project, storyline, saved[item_id])


func _find_graph(node: Node) -> MonologueGraphEdit:
	if node is MonologueGraphEdit:
		return node
	for child: Node in node.get_children():
		var found: MonologueGraphEdit = _find_graph(child)
		if found:
			return found
	return null


func _on_add_node(item_id: int) -> void:
	var node_name: String = graph_dict[item_id]
	EventBus.add_graph_node.emit(node_name)  # FIXME signal doesn't work
