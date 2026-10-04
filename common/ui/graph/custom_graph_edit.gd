## Represents the graph area which creates and connects MonologueGraphNodes.
class_name CustomGraphEdit extends GraphEdit

const SCROLLBAR_OVERRIDE_KEYS: Array[String] = ["grabber", "scroll"]

## True while the user is dragging a wire. Rebuilding a node during that window moves
## the ports out from under GraphEdit mid-drag, which is what used to leave a box
## selection behind instead of a connection.
var connecting_mode: bool
var mouse_hovering: bool = false


var _wire_thickness: float = 0.0
var _wire_zoom: float = -1.0
var _lane_offsets: Dictionary = {}  # key String -> float (lane offset in view px)

## When enabled, parallel wires in the same vertical corridor are routed in separate parallel
## lanes instead of merging into a single overlapping line (russian-monologue).
var separate_wire_lanes: bool = true:
	set(value):
		if separate_wire_lanes != value:
			separate_wire_lanes = value
			_update_lane_offsets()
			queue_redraw()


func _ready() -> void:
	_hide_default_scrollbars()
	_wire_thickness = connection_lines_thickness

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

	# everything is in view pixels, so the margins follow the zoom; only a wire that really goes
	# backwards takes the detour — a short forward one used to loop on itself
	var step: float = 24.0 * zoom
	if to_position.x > from_position.x + 2.0:
		var mid_x: float = _get_wire_mid_x(from_position, to_position)
		raw_points = [
			from_position,
			Vector2(mid_x, from_position.y),
			Vector2(mid_x, to_position.y),
			to_position,
		]
	else:
		var mid_y: float = (from_position.y + to_position.y) * 0.5
		if is_equal_approx(from_position.y, to_position.y):
			mid_y += 32.0 * zoom
		raw_points = [
			from_position,
			Vector2(from_position.x + step, from_position.y),
			Vector2(from_position.x + step, mid_y),
			Vector2(to_position.x - step, mid_y),
			Vector2(to_position.x - step, to_position.y),
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
	var CORNER_RADIUS: float = 8.0 * zoom
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


var _lanes_dirty: bool = true


func _get_wire_mid_x(from_position: Vector2, to_position: Vector2) -> float:
	var base_mid: float = (from_position.x + to_position.x) * 0.5
	if not separate_wire_lanes:
		return base_mid
	if _lanes_dirty or _lane_offsets.is_empty():
		_update_lane_offsets()
	var c_from: Vector2 = (from_position + scroll_offset) / zoom
	var c_to: Vector2 = (to_position + scroll_offset) / zoom
	var key: String = "%d,%d>%d,%d" % [roundi(c_from.x), roundi(c_from.y), roundi(c_to.x), roundi(c_to.y)]
	var offset: Variant = _lane_offsets.get(key)
	if offset != null:
		return base_mid + float(offset) * zoom
	# fallback: match by close canvas coordinates (within 3px)
	for k: String in _lane_offsets:
		var parts: PackedStringArray = k.split(">")
		if parts.size() != 2:
			continue
		var p1_s: PackedStringArray = parts[0].split(",")
		var p2_s: PackedStringArray = parts[1].split(",")
		if p1_s.size() == 2 and p2_s.size() == 2:
			if absf(float(p1_s[0]) - c_from.x) <= 3.0 and absf(float(p1_s[1]) - c_from.y) <= 3.0 \
					and absf(float(p2_s[0]) - c_to.x) <= 3.0 and absf(float(p2_s[1]) - c_to.y) <= 3.0:
				return base_mid + float(_lane_offsets[k]) * zoom
	return base_mid


## Recalculates parallel lane offsets so overlapping vertical wires in the same corridor
## do not merge into a single line (russian-monologue).
func _update_lane_offsets() -> void:
	_lane_offsets.clear()
	_lanes_dirty = false
	if not separate_wire_lanes:
		return
	var conns: Array[Dictionary] = get_connection_list()
	if conns.is_empty():
		return
	# Group wires into corridors between columns (in canvas space)
	var corridors: Dictionary = {}
	for c: Dictionary in conns:
		var fn: GraphNode = get_node_or_null(str(c.from_node)) as GraphNode
		var tn: GraphNode = get_node_or_null(str(c.to_node)) as GraphNode
		if fn == null or tn == null:
			continue
		var p1: Vector2 = fn.position_offset + fn.get_output_port_position(c.from_port)
		var p2: Vector2 = tn.position_offset + tn.get_input_port_position(c.to_port)
		# Only forward wires with vertical travel
		if p2.x <= p1.x + 2.0 or absf(p2.y - p1.y) <= 4.0:
			continue
		var key: String = "%d_%d_%d" % [roundi(p1.x / 40.0), roundi(p2.x / 40.0), 1 if p2.y > p1.y else -1]
		(corridors.get_or_add(key, []) as Array).append({
			"p1": p1,
			"p2": p2,
			"y_min": minf(p1.y, p2.y),
			"y_max": maxf(p1.y, p2.y),
			"dist": absf(p2.y - p1.y),
		})

	for corr_key: String in corridors:
		var wires: Array = corridors[corr_key]
		# Find connected clusters of wires whose vertical ranges overlap
		var clusters: Array = []
		for w: Dictionary in wires:
			var merged_into: Array = []
			for cl: Array in clusters:
				var overlaps: bool = false
				for other: Dictionary in cl:
					if w.y_max > other.y_min + 4.0 and other.y_max > w.y_min + 4.0:
						overlaps = true
						break
				if overlaps:
					merged_into.append(cl)
			if merged_into.is_empty():
				clusters.append([w])
			else:
				var target_cl: Array = merged_into[0]
				target_cl.append(w)
				for k: int in range(1, merged_into.size()):
					target_cl.append_array(merged_into[k])
					clusters.erase(merged_into[k])

		for cl: Array in clusters:
			if cl.size() <= 1:
				continue
			# Closest target peels off first -> needs largest X (outer lane, closest to target)
			# Furthest target peels off last -> needs smallest X (inner lane, closest to source)
			cl.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.dist < b.dist)
			var K: int = cl.size()
			var p1_s: Vector2 = cl[0].p1
			var p2_s: Vector2 = cl[0].p2
			var avail: float = maxf(16.0, (p2_s.x - p1_s.x) - 40.0)
			var step_x: float = clampf(avail / float(K), 12.0, 24.0)
			for i: int in K:
				var item: Dictionary = cl[i]
				var offset: float = ((float(K - 1) * 0.5) - float(i)) * step_x
				var conn_key: String = "%d,%d>%d,%d" % [roundi(item.p1.x), roundi(item.p1.y), roundi(item.p2.x), roundi(item.p2.y)]
				_lane_offsets[conn_key] = offset


static func _append_wire_point(arr: PackedVector2Array, pt: Vector2) -> void:
	if arr.is_empty() or not arr[arr.size() - 1].is_equal_approx(pt):
		arr.append(pt)


## Wires thin out with the zoom like everything else; Godot keeps their width in screen pixels,
## so zoomed out they used to look fat (russian-monologue).
func _process(_delta: float) -> void:
	_lanes_dirty = true
	if is_equal_approx(zoom, _wire_zoom):
		return
	_wire_zoom = zoom
	connection_lines_thickness = maxf(1.0, _wire_thickness * minf(zoom, 1.0))
	queue_redraw()  # dashed back wires are drawn by hand and follow the zoom
