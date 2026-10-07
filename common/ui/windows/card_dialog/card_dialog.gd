class_name CardDialog
extends Control

@onready var dimmer: ColorRect = %Dimmer
@onready var frame: PanelContainer = %Frame
@onready var inspector: InspectorPanel = %Inspector

var _node: InspectableNode


func _ready() -> void:
	visible = false
	dimmer.gui_input.connect(_on_dimmer_gui_input)
	EventBus.open_card_dialog.connect(open)
	EventBus.close_card_dialog.connect(close)
	# the right dock is gone: a collection, a record of one or the languages list asked for from the
	# project panel or a list field shows here too, or it would load into a hidden window (russian-monologue)
	EventBus.request_objects_inspection.connect(_on_inspection_requested)
	inspector.hidden.connect(close)
	inspector.field_container.resized.connect(_on_fields_resized)
	frame.gui_input.connect(_on_frame_gui_input)


func open(node: InspectableNode) -> void:
	_node = node
	if node == null:
		return

	visible = true
	frame.custom_minimum_size.x = 640.0
	inspector.show()
	inspector._closed_on = []
	ConfigManager.set_config("show_inspector", true)
	inspector.inspect([node])
	inspector.focus_line_field()
	_show_settled()


func _on_inspection_requested(objects: Array[InspectableObject]) -> void:
	if visible or objects.is_empty():
		return
	for object: InspectableObject in objects:
		if not (object is CollectionDocument or object is CollectionItem):
			return
	_node = null
	visible = true
	frame.custom_minimum_size.x = 640.0
	inspector.show()
	inspector._closed_on = []
	_show_settled()


func close() -> void:
	if not visible:
		return
	visible = false
	_node = null
	if inspector.visible:
		inspector.close()


func _on_dimmer_gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			accept_event()
			close()


func _on_fields_resized() -> void:
	_update_height()


# ---------- size and place (russian-monologue): the window opens whole, in the middle of the
# screen, no growing from the bottom; it can be dragged by its top strip and edges, and keeps the
# place it was dragged to; a section unfolding makes it longer downwards at once

var _placed: bool = false
var _dragging: bool = false
const MARGIN: float = 16.0


func _desired_height() -> float:
	var vp_h: float = get_viewport_rect().size.y
	var header_node: Control = inspector.get_node_or_null(^"VBox/Header") as Control
	var header_h: float = header_node.size.y if header_node else 50.0
	var fields_h: float = inspector.field_container.get_combined_minimum_size().y
	return clampf(fields_h + header_h + 36.0, 260.0, maxf(320.0, vp_h * 0.86))


## Opens hidden for two frames while the fields are laid out, then shows at its full size.
func _show_settled() -> void:
	modulate.a = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	if not visible:
		return
	frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var h: float = _desired_height()
	frame.custom_minimum_size = Vector2(640.0, h)
	frame.size = Vector2(640.0, h)
	var screen: Vector2 = get_viewport_rect().size
	if not _placed:
		frame.position = ((screen - frame.size) / 2.0).floor()
	_keep_on_screen()
	modulate.a = 1.0


func _update_height() -> void:
	if not visible or not is_inside_tree() or modulate.a < 1.0:
		return
	await get_tree().process_frame
	if not visible:
		return
	var h: float = _desired_height()
	if absf(h - frame.size.y) > 2.0:
		frame.custom_minimum_size.y = h
		frame.size.y = h
		_keep_on_screen()


func _keep_on_screen() -> void:
	var screen: Vector2 = get_viewport_rect().size
	frame.position.x = clampf(frame.position.x, MARGIN - frame.size.x + 120.0, screen.x - 120.0)
	frame.position.y = clampf(frame.position.y, MARGIN, maxf(MARGIN, screen.y - frame.size.y - MARGIN))


func _on_frame_gui_input(event: InputEvent) -> void:
	var press: InputEventMouseButton = event as InputEventMouseButton
	if press and press.button_index == MOUSE_BUTTON_LEFT:
		if press.pressed:
			# the top strip (search row and the id under it) and the window's own edges move it
			var header_node: Control = inspector.get_node_or_null(^"VBox/Header") as Control
			var top: float = (header_node.get_global_rect().end.y - frame.global_position.y) if header_node else 90.0
			_dragging = press.position.y <= top + 6.0 or press.position.x < 14.0 or press.position.x > frame.size.x - 14.0 or press.position.y > frame.size.y - 14.0
		else:
			_dragging = false
		if _dragging:
			frame.accept_event()
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion and _dragging:
		frame.position += motion.relative
		_placed = true
		_keep_on_screen()
		frame.accept_event()


## Enter closes the card window wherever it is pressed in it — a one-line field (its value taken
## first), a list, nothing focused at all; Shift+Enter stays a new line, the search keeps searching.
## A text area does the same in its own field (russian-monologue).
func _input(event: InputEvent) -> void:
	if not visible or modulate.a < 1.0:
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or key.shift_pressed:
		return
	if key.keycode != KEY_ENTER and key.keycode != KEY_KP_ENTER:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is TextEdit and frame.is_ancestor_of(focus):
		return  # its field takes the text and closes the window itself
	if focus is LineEdit and focus.name == &"SearchBar":
		return
	if focus is LineEdit and frame.is_ancestor_of(focus):
		close.call_deferred()  # after the line edit has taken the value
		return
	get_viewport().set_input_as_handled()
	if focus:
		focus.release_focus()
	close()
