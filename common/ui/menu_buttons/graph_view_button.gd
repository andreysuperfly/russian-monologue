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
	# lay the cards out in story order (russian-monologue)
	add_separator()
	add_row("Lay Out Tight", func() -> void: _lay_out(false))
	add_row("Lay Out Roomy", func() -> void: _lay_out(true))


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
