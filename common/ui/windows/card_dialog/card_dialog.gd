class_name CardDialog
extends Control

@onready var dimmer: ColorRect = %Dimmer
@onready var frame: PanelContainer = %Frame
@onready var inspector: InspectorPanel = %Inspector

var _node: InspectableNode
var _target_height: float = 0.0


func _ready() -> void:
	visible = false
	dimmer.gui_input.connect(_on_dimmer_gui_input)
	EventBus.open_card_dialog.connect(open)
	EventBus.close_card_dialog.connect(close)
	inspector.hidden.connect(close)
	inspector.field_container.resized.connect(_on_fields_resized)


func open(node: InspectableNode) -> void:
	_node = node
	if node == null:
		return

	inspector.category_states.clear()
	visible = true
	frame.custom_minimum_size.x = 640.0
	inspector.show()
	inspector._closed_on = []
	ConfigManager.set_config("show_inspector", true)
	inspector.inspect([node])
	inspector.focus_line_field()
	_update_height()


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


func _update_height() -> void:
	if not visible or not is_inside_tree():
		return
	await get_tree().process_frame
	if not visible or not is_instance_valid(inspector):
		return

	var vp_h: float = get_viewport_rect().size.y
	var max_h: float = maxf(320.0, vp_h * 0.82)
	var header_node: Control = inspector.get_node_or_null(^"VBox/Header") as Control
	var header_h: float = header_node.size.y if header_node else 50.0
	var fields_h: float = inspector.field_container.get_combined_minimum_size().y
	var desired_h: float = clampf(fields_h + header_h + 36.0, 260.0, max_h)

	if absf(desired_h - _target_height) > 4.0:
		_target_height = desired_h
		var tween: Tween = create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(frame, "custom_minimum_size:y", desired_h, 0.22)
		tween.parallel().tween_property(frame, "size:y", desired_h, 0.22)
