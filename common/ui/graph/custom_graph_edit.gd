## Represents the graph area which creates and connects MonologueGraphNodes.
class_name CustomGraphEdit extends GraphEdit

const SCROLLBAR_OVERRIDE_KEYS: Array[String] = ["grabber", "scroll"]

## True while the user is dragging a wire. Rebuilding a node during that window moves
## the ports out from under GraphEdit mid-drag, which is what used to leave a box
## selection behind instead of a connection.
var connecting_mode: bool
var mouse_hovering: bool = false


func _ready() -> void:
	_hide_default_scrollbars()

	connection_drag_started.connect(_on_connection_drag_started)
	connection_drag_ended.connect(_on_connection_drag_ended)


## Where the eye is, in the graph's own coordinates. A new node belongs here, not in the
## corner that scroll_offset alone points at.
func middle_of_view() -> Vector2:
	return (scroll_offset + get_rect().size / 2.0) / zoom


func scroll_to_node(graph_node: GraphNode) -> void:
	for child: Node in get_children():
		if child is GraphNode:
			(child as GraphNode).selected = false
	graph_node.selected = true

	var node_center: Vector2 = graph_node.position_offset + graph_node.size / 2.0
	scroll_offset = node_center * zoom - get_rect().size / 2.0


func _hide_default_scrollbars() -> void:
	for child: Node in get_children(true):
		if child is GraphNode:
			continue
		for subchild: Node in child.get_children(true):
			if not subchild is ScrollBar:
				continue
			for key: String in SCROLLBAR_OVERRIDE_KEYS:
				subchild.add_theme_stylebox_override(key, StyleBoxEmpty.new())


func _on_gui_input(_event: InputEvent) -> void:
	if mouse_hovering:
		var cursor_drag: bool = Input.is_action_pressed("Spacebar")
		var cursor_hand_closed: bool = (
			cursor_drag and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			cursor_hand_closed = true
		if cursor_hand_closed:
			DisplayServer.cursor_set_custom_image(Cursor.CLOSED_HAND)
		elif cursor_drag:
			DisplayServer.cursor_set_custom_image(Cursor.HAND)
		else:
			DisplayServer.cursor_set_custom_image(Cursor.ARROW)


func _on_connection_drag_started(_from_node: StringName, _from_port: int, _is_output: bool) -> void:
	connecting_mode = true


func _on_connection_drag_ended() -> void:
	connecting_mode = false


func _on_mouse_entered() -> void:
	mouse_hovering = true


func _on_mouse_exited() -> void:
	DisplayServer.cursor_set_custom_image(null)
	mouse_hovering = false


## Wires go in right angles with rounded corners, along the way the story reads, instead of
## loose curves (russian-monologue). Godot calls this for every wire it draws.
func _get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var raw_points: Array[Vector2] = []

	if to_position.x >= from_position.x + 48.0:
		var mid_x: float = (from_position.x + to_position.x) * 0.5
		raw_points = [
			from_position,
			Vector2(mid_x, from_position.y),
			Vector2(mid_x, to_position.y),
			to_position,
		]
	else:
		var mid_y: float = (from_position.y + to_position.y) * 0.5
		if is_equal_approx(from_position.y, to_position.y):
			mid_y += 32.0
		raw_points = [
			from_position,
			Vector2(from_position.x + 24.0, from_position.y),
			Vector2(from_position.x + 24.0, mid_y),
			Vector2(to_position.x - 24.0, mid_y),
			Vector2(to_position.x - 24.0, to_position.y),
			to_position,
		]

	# Удаление дубликатов и коллинеарных промежуточных точек
	var clean: Array[Vector2] = []
	for p: Vector2 in raw_points:
		if clean.is_empty() or not clean[-1].is_equal_approx(p):
			clean.append(p)

	var filtered: Array[Vector2] = []
	for i: int in range(clean.size()):
		if i > 0 and i < clean.size() - 1:
			var v1: Vector2 = clean[i] - clean[i - 1]
			var v2: Vector2 = clean[i + 1] - clean[i]
			if (is_zero_approx(v1.x) and is_zero_approx(v2.x)) or (is_zero_approx(v1.y) and is_zero_approx(v2.y)):
				continue
		filtered.append(clean[i])

	if filtered.size() < 3:
		return PackedVector2Array(filtered)

	# Скругление углов: радиус 8px, аппроксимация дуги 3 точками
	const CORNER_RADIUS: float = 8.0
	var result: PackedVector2Array = PackedVector2Array()
	result.append(filtered[0])

	for i: int in range(1, filtered.size() - 1):
		var p_prev: Vector2 = filtered[i - 1]
		var p_curr: Vector2 = filtered[i]
		var p_next: Vector2 = filtered[i + 1]

		var v_in: Vector2 = p_curr - p_prev
		var v_out: Vector2 = p_next - p_curr
		var len_in: float = v_in.length()
		var len_out: float = v_out.length()
		var r: float = minf(CORNER_RADIUS, minf(len_in, len_out) * 0.5)

		var d_in: Vector2 = v_in / len_in
		var d_out: Vector2 = v_out / len_out

		var p_start: Vector2 = p_curr - d_in * r
		var p_end: Vector2 = p_curr + d_out * r
		var center: Vector2 = p_start + d_out * r
		var p_mid: Vector2 = center + (p_curr - center).normalized() * r

		_append_wire_point(result, p_start)
		_append_wire_point(result, p_mid)
		_append_wire_point(result, p_end)

	_append_wire_point(result, filtered[-1])
	return result


static func _append_wire_point(arr: PackedVector2Array, pt: Vector2) -> void:
	if arr.is_empty() or not arr[arr.size() - 1].is_equal_approx(pt):
		arr.append(pt)
