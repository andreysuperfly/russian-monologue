extends Node

# Reference DPI for a 23.8" 1920x1080 display
const BASE_SCALE_DPI: float = 92.56
const BASE_SCREEN_SIZE: Vector2i = Vector2i(1920, 1080)
## Interface sizes the user can pick (russian-monologue), on top of the screen's own scale.
const SCALES: Array[String] = ["75%", "85%", "100%", "110%", "125%", "150%", "175%", "200%"]


func _ready() -> void:
	_add_scale_shortcuts()
	# deferred: the size picked in Preferences is only known once ConfigManager has loaded
	_update_window.call_deferred(get_window(), true)
	get_window().size_changed.connect(_on_window_size_changed)


func _shortcut_input(event: InputEvent) -> void:
	if event.is_action_pressed("mnl_add_node"):
		EventBus.enable_picker_mode.emit("", "", 0, Vector2.ZERO)
	elif event.is_action_pressed("mnl_ui_bigger"):
		step_ui_scale(1)
	elif event.is_action_pressed("mnl_ui_smaller"):
		step_ui_scale(-1)
	elif event.is_action_pressed("mnl_ui_reset"):
		ConfigManager.set_config("ui_scale", "100%")


func _on_window_size_changed() -> void:
	_update_window(get_window())


func _update_window(window: Window, update_size: bool = false) -> void:
	var window_id: int = max(0, window.get_window_id())
	var scale_factor: float = _get_auto_display_scale(window_id) * user_scale()
	window.content_scale_factor = scale_factor
	if update_size:
		var window_size: Vector2i = DisplayServer.window_get_size(window_id)
		var screen_id: int = DisplayServer.window_get_current_screen(window_id)
		var screen_size: Vector2 = DisplayServer.screen_get_size(screen_id) as Vector2
		var window_scale: Vector2 = screen_size / (BASE_SCREEN_SIZE as Vector2)
		DisplayServer.window_set_size(Vector2i(window_size as Vector2 * window_scale))
		window.move_to_center()


## The size picked in Preferences, as a multiplier (1.0 for 100%).
func user_scale() -> float:
	var picked: String = str(ConfigManager.get_config("ui_scale", "100%")) if ConfigManager.current_configuration else "100%"
	return clampf(picked.trim_suffix("%").to_float() / 100.0, 0.5, 3.0) if picked.ends_with("%") else 1.0


func apply_ui_scale() -> void:
	_update_window(get_window())


## One size up or down the list in [constant SCALES].
func step_ui_scale(direction: int) -> void:
	var at: int = SCALES.find(str(ConfigManager.get_config("ui_scale", "100%")))
	if at < 0:
		at = SCALES.find("100%")
	ConfigManager.set_config("ui_scale", SCALES[clampi(at + direction, 0, SCALES.size() - 1)])


## ⌘+ / ⌘− / ⌘0 (Ctrl on other systems); "=" counts as "+" so no Shift is needed.
func _add_scale_shortcuts() -> void:
	var keys: Dictionary = {
		"mnl_ui_bigger": [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD],
		"mnl_ui_smaller": [KEY_MINUS, KEY_KP_SUBTRACT],
		"mnl_ui_reset": [KEY_0, KEY_KP_0],
	}
	for action: String in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode: Key in keys[action]:
			var key: InputEventKey = InputEventKey.new()
			key.keycode = keycode
			key.command_or_control_autoremap = true
			InputMap.action_add_event(action, key)


## Returns the optimal window scale factor for the current screen.
## Logic adapted from Godot editor/editor_settings.cpp#L1974.
func _get_auto_display_scale(window_id: int = 0) -> float:
	var os_name: String = OS.get_name()
	if os_name in ["Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]:
		if DisplayServer.get_name() == "Wayland":
			var main_window_scale: float = DisplayServer.screen_get_scale(
				DisplayServer.SCREEN_OF_MAIN_WINDOW
			)
			if DisplayServer.get_screen_count() == 1 or fmod(main_window_scale, 1.0) != 0.0:
				return main_window_scale
			return DisplayServer.screen_get_max_scale()

	if os_name in ["macOS", "Android"]:
		return DisplayServer.screen_get_max_scale()

	var screen: int = DisplayServer.window_get_current_screen(window_id)
	if DisplayServer.screen_get_size(screen) == Vector2i.ZERO:
		return 1.0

	if os_name == "Windows":
		return DisplayServer.screen_get_dpi(screen) / 96.0

	var screen_size: Vector2i = DisplayServer.screen_get_size(screen)
	var smallest_dimension: int = min(screen_size.x, screen_size.y)

	var dpi: float = DisplayServer.screen_get_dpi(screen)
	if dpi >= 192.0 and smallest_dimension >= 1440:
		return 2.0  # hiDPI display
	if smallest_dimension >= 1700:
		return 1.5  # likely hiDPI
	if smallest_dimension <= 800:
		return 0.75  # small loDPI display
	return 1.0
