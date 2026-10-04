extends EditorMenuButton


func _build_menu() -> void:
	add_check_row("Snap", ConfigManager.get_config("snap"), _on_snap, true, ["mnl_graph_snap"])
	add_check_row(
		"Show Grid",
		ConfigManager.get_config("show_grid"),
		_on_show_grid,
		true,
		["mnl_graph_show_grid"]
	)
	add_check_row(
		"Separate Parallel Wires",
		_is_separate_wires_enabled(),
		_on_toggle_separate_wires,
		true
	)
	add_check_row(
		"Avoid Cards",
		_is_avoid_cards_enabled(),
		_on_toggle_avoid_cards,
		true
	)
	# lay the cards out in story order (russian-monologue)
	add_separator()
	add_row("Lay Out Tight", func() -> void: _lay_out(false))
	add_row("Lay Out Roomy", func() -> void: _lay_out(true))


func _is_separate_wires_enabled() -> bool:
	var graph: Node = get_tree().get_first_node_in_group(&"monologue_graph")
	if graph and "separate_wire_lanes" in graph:
		return graph.separate_wire_lanes
	return ConfigManager.get_config("graph/separate_wire_lanes", true)


func _on_toggle_separate_wires(enabled: bool) -> void:
	ConfigManager.set_config("graph/separate_wire_lanes", enabled)
	var graph: Node = get_tree().get_first_node_in_group(&"monologue_graph")
	if graph and "separate_wire_lanes" in graph:
		graph.separate_wire_lanes = enabled


func _is_avoid_cards_enabled() -> bool:
	var graph: Node = get_tree().get_first_node_in_group(&"monologue_graph")
	if graph and "avoid_card_obstacles" in graph:
		return graph.avoid_card_obstacles
	return ConfigManager.get_config("graph/avoid_card_obstacles", true)


func _on_toggle_avoid_cards(enabled: bool) -> void:
	ConfigManager.set_config("graph/avoid_card_obstacles", enabled)
	var graph: Node = get_tree().get_first_node_in_group(&"monologue_graph")
	if graph and "avoid_card_obstacles" in graph:
		graph.avoid_card_obstacles = enabled


func _lay_out(roomy: bool) -> void:
	var graph: Node = get_tree().get_first_node_in_group(&"monologue_graph")
	if graph and graph.has_method("lay_out"):
		graph.lay_out(roomy)


func _on_snap(enabled: bool) -> void:
	ConfigManager.set_config("snap", enabled)
	EventBus.graph_snap.emit(enabled)


func _on_show_grid(enabled: bool) -> void:
	ConfigManager.set_config("show_grid", enabled)
	EventBus.graph_show_grid.emit(enabled)
