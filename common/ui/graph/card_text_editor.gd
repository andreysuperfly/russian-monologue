## Edits a sentence's line right on its card (russian-monologue): double-click the card, type,
## Enter or a click elsewhere keeps it, Esc throws it away, Shift+Enter starts a new line.
## The card grows with the text while it is edited. Written through the node, so it is one
## undo step like any change made in the inspector.
class_name CardTextEditor
extends TextEdit

const PROPERTY: String = "line"

var _node: InspectableNode
var _preview: Control
var _done: bool = false


static func open(graph_node: GraphNode, node: InspectableNode) -> void:
	if graph_node.get_node_or_null(^"CardTextEditor"):
		return
	var editor: CardTextEditor = CardTextEditor.new()
	editor.name = "CardTextEditor"
	editor._node = node
	editor._preview = graph_node.get_node_or_null(NodePath(GraphNodeViewFactory.PREVIEW_NAME))
	editor.text = Util.to_label(node.get_property_value(PROPERTY), _language())
	var width: float = maxf(260.0, editor._preview.size.x if editor._preview else 0.0)
	editor.custom_minimum_size = Vector2(width, 0)
	graph_node.add_child(editor)
	if editor._preview:
		graph_node.move_child(editor, editor._preview.get_index())
		editor._preview.hide()
	editor.grab_focus.call_deferred()
	editor.select_all.call_deferred()


func _ready() -> void:
	wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	scroll_fit_content_height = true
	context_menu_enabled = false
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(0.09, 0.09, 0.1)
	box.border_color = Color(0.85, 0.42, 0.38)
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	add_theme_stylebox_override("normal", box)
	add_theme_stylebox_override("focus", box)
	add_theme_constant_override("line_spacing", 4)
	focus_exited.connect(_finish.bind(true))


func _gui_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode in [KEY_ENTER, KEY_KP_ENTER] and not key.shift_pressed:
		accept_event()
		_finish(true)
	elif key.keycode == KEY_ESCAPE:
		accept_event()
		_finish(false)


func _finish(keep: bool) -> void:
	if _done:
		return
	_done = true
	var typed: String = text.strip_edges()
	var graph_node: Node = get_parent()
	if is_instance_valid(_preview):
		_preview.show()
	queue_free()
	if graph_node is GraphNode:
		(graph_node as GraphNode).reset_size.call_deferred()
	if not keep or not is_instance_valid(_node):
		return
	var stored: Variant = _node.get_property_value(PROPERTY)
	if typed == Util.to_label(stored, _language()):
		return
	var value: Variant = typed
	if stored is Dictionary:
		value = (stored as Dictionary).duplicate()
		value[_language()] = typed
	_node.set_property_value(PROPERTY, value)


static func _language() -> String:
	var project: MonologueProject = ProjectManager.current_project
	return project.active_language_code if project else ""
