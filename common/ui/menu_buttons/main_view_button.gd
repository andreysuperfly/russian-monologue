extends EditorMenuButton


func _build_menu() -> void:
	add_check_row("Show Inspector", ConfigManager.get_config("show_inspector"), _on_show_inspector)
	add_check_row(
		"Show Project Explorer",
		ConfigManager.get_config("show_project_explorer"),
		_on_show_project_explorer
	)
	add_check_row("Show Console", ConfigManager.get_config("show_console"), _on_show_console)
	add_check_row(
		"Show Status Bar", ConfigManager.get_config("show_status_bar"), _on_show_status_bar
	)
	add_check_row("Show Pictures", Pictures.enabled(), _on_show_pictures)
	add_check_row("Compact Cards", ConfigManager.get_config("compact_cards", false) == true, _on_compact_cards)
	add_separator()
	add_row("Bigger", func() -> void: App.step_ui_scale(1), true, ["mnl_ui_bigger"])
	add_row("Smaller", func() -> void: App.step_ui_scale(-1), true, ["mnl_ui_smaller"])
	add_row("Actual Size", func() -> void: ConfigManager.set_config("ui_scale", "100%"), true, ["mnl_ui_reset"])
	add_separator()
	add_row("Regenerate theme", _on_regenerate_theme, true, ["mnl_regenerate_theme"])


func _on_show_inspector(enabled: bool) -> void:
	ConfigManager.set_config("show_inspector", enabled)
	EventBus.show_inspector.emit(enabled)


func _on_show_project_explorer(enabled: bool) -> void:
	ConfigManager.set_config("show_project_explorer", enabled)
	EventBus.show_project_explorer.emit(enabled)


func _on_show_console(enabled: bool) -> void:
	ConfigManager.set_config("show_console", enabled)
	EventBus.show_console.emit(enabled)


func _on_show_status_bar(enabled: bool) -> void:
	ConfigManager.set_config("show_status_bar", enabled)
	EventBus.show_status_bar.emit(enabled)


## Cards with only their title, wired rows and preview (russian-monologue).
func _on_compact_cards(enabled: bool) -> void:
	ConfigManager.set_config("compact_cards", enabled)
	EventBus.refresh_graph.emit()


## Faces and item icons beside names (russian-monologue); see Pictures.
func _on_show_pictures(enabled: bool) -> void:
	ConfigManager.set_config(Pictures.SETTING, enabled)


func _on_regenerate_theme() -> void:
	ThemeLayout.generate_and_apply_theme()
