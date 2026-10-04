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
			mark_lanes_dirty()

## When enabled, wires avoid cutting through intermediate cards between source and target,
## detouring smoothly around them (russian-monologue).
var avoid_card_obstacles: bool = true:
	set(value):
		if avoid_card_obstacles != value:
			avoid_card_obstacles = value
			mark_lanes_dirty()


func _ready() -> void:
	_hide_default_scrollbars()
	_wire_thickness = connection_lines_thickness

	var cfg: Node = get_node_or_null("/root/ConfigManager")
	if cfg and cfg.has_method("get_config"):
		var sw: Variant = cfg.get_config("graph/separate_wire_lanes", true)
		if sw != null:
			separate_wire_lanes = bool(sw)
		var ac: Variant = cfg.get_config("graph/avoid_card_obstacles", true)
		if ac != null:
			avoid_card_obstacles = bool(ac)

	connection_drag_started.connect(_on_connection_drag_started)
	connection_drag_ended.connect(_on_connection_drag_ended)

	child_entered_tree.connect(_on_child_entered_tree)
	child_exiting_tree.connect(_on_child_exiting_tree)
	for child: Node in get_children():
		_track_node_child(child)

	connection_request.connect(func(_f, _fp, _t, _tp): mark_lanes_dirty())
	disconnection_request.connect(func(_f, _fp, _t, _tp): mark_lanes_dirty())
	connection_to_empty.connect(func(_f, _fp, _p): mark_lanes_dirty())
	connection_from_empty.connect(func(_t, _tp, _p): mark_lanes_dirty())
	begin_node_move.connect(func(): mark_lanes_dirty())
	end_node_move.connect(func(): mark_lanes_dirty())


func mark_lanes_dirty() -> void:
	if not _lanes_dirty:
		_lanes_dirty = true
		queue_redraw()


func _track_node_child(child: Node) -> void:
	if child is GraphNode:
		if not child.position_offset_changed.is_connected(mark_lanes_dirty):
			child.position_offset_changed.connect(mark_lanes_dirty)
		if not child.item_rect_changed.is_connected(mark_lanes_dirty):
			child.item_rect_changed.connect(mark_lanes_dirty)


func _untrack_node_child(child: Node) -> void:
	if child is GraphNode:
		if child.position_offset_changed.is_connected(mark_lanes_dirty):
			child.position_offset_changed.disconnect(mark_lanes_dirty)
		if child.item_rect_changed.is_connected(mark_lanes_dirty):
			child.item_rect_changed.disconnect(mark_lanes_dirty)


func _on_child_entered_tree(child: Node) -> void:
	_track_node_child(child)
	mark_lanes_dirty()


func _on_child_exiting_tree(child: Node) -> void:
	_untrack_node_child(child)
	mark_lanes_dirty()




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
		var detour_pts: Array[Vector2] = _get_detour_points(from_position, to_position)
		if not detour_pts.is_empty():
			raw_points = detour_pts
		else:
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
var _lane_turns: Dictionary = {}  # key String -> float turn_x in canvas px
var _lane_list: Array[Dictionary] = []  # list of { "p1": Vector2, "p2": Vector2, "turn_x": float }
var _detour_routes: Dictionary = {}  # key String -> Array[Vector2] (canvas coords)
var _detour_list: Array[Dictionary] = []  # list of { "p1": Vector2, "p2": Vector2, "points": Array[Vector2] }


func _get_wire_mid_x(from_position: Vector2, to_position: Vector2) -> float:
	var base_mid: float = (from_position.x + to_position.x) * 0.5
	if not separate_wire_lanes:
		return base_mid
	if _lanes_dirty:
		_update_lane_offsets()
	var c_from: Vector2 = from_position / zoom
	var c_to: Vector2 = to_position / zoom
	var key: String = "%d,%d>%d,%d" % [roundi(c_from.x), roundi(c_from.y), roundi(c_to.x), roundi(c_to.y)]
	var turn: Variant = _lane_turns.get(key)
	if turn != null:
		return float(turn) * zoom
	# fallback: match by close canvas coordinates (within 4px)
	for rec: Dictionary in _lane_list:
		if rec.p1.distance_squared_to(c_from) <= 16.0 and rec.p2.distance_squared_to(c_to) <= 16.0:
			return float(rec.turn_x) * zoom
	return base_mid


func _get_detour_points(from_position: Vector2, to_position: Vector2) -> Array[Vector2]:
	if not avoid_card_obstacles:
		return []
	if _lanes_dirty:
		_update_lane_offsets()
	if _detour_routes.is_empty() and _detour_list.is_empty():
		return []

	var c_from: Vector2 = from_position / zoom
	var c_to: Vector2 = to_position / zoom
	var key: String = "%d,%d>%d,%d" % [roundi(c_from.x), roundi(c_from.y), roundi(c_to.x), roundi(c_to.y)]
	var pts_var: Variant = _detour_routes.get(key)
	if pts_var != null:
		var res: Array[Vector2] = []
		for pt: Vector2 in (pts_var as Array):
			res.append(pt * zoom)
		return res

	# fallback: match by close canvas coordinates (within 4px)
	for rec: Dictionary in _detour_list:
		if rec.p1.distance_squared_to(c_from) <= 16.0 and rec.p2.distance_squared_to(c_to) <= 16.0:
			var res: Array[Vector2] = []
			for pt: Vector2 in (rec.points as Array):
				res.append(pt * zoom)
			return res

	return []


## Recalculates parallel lane turn coordinates and obstacle detour paths (russian-monologue).
func _update_lane_offsets() -> void:
	_lane_turns.clear()
	_lane_list.clear()
	_detour_routes.clear()
	_detour_list.clear()
	_lanes_dirty = false

	var conns: Array[Dictionary] = get_connection_list()
	if conns.is_empty():
		return

	# Pre-collect all visible GraphNodes for fast obstacle testing
	var all_graph_nodes: Array[GraphNode] = []
	for child in get_children():
		if child is GraphNode and child.visible:
			all_graph_nodes.append(child as GraphNode)

	# Collect all forward connections
	var standard_wires: Array[Dictionary] = []
	var raw_detours: Array[Dictionary] = []

	for c: Dictionary in conns:
		var fn: GraphNode = get_node_or_null(NodePath(c.from_node)) as GraphNode
		var tn: GraphNode = get_node_or_null(NodePath(c.to_node)) as GraphNode
		if fn == null or tn == null:
			continue
		if c.from_port < 0 or c.from_port >= fn.get_output_port_count():
			continue
		if c.to_port < 0 or c.to_port >= tn.get_input_port_count():
			continue
		var p1: Vector2 = fn.position_offset + fn.get_output_port_position(c.from_port)
		var p2: Vector2 = tn.position_offset + tn.get_input_port_position(c.to_port)
		# Only forward wires
		if p2.x <= p1.x + 2.0:
			continue

		# Check for intermediate obstacle cards
		var obstacles: Array[GraphNode] = []
		if avoid_card_obstacles:
			var direct_y_min: float = minf(p1.y, p2.y) - 6.0
			var direct_y_max: float = maxf(p1.y, p2.y) + 6.0
			for obs: GraphNode in all_graph_nodes:
				if obs == fn or obs == tn:
					continue
				var obs_rect: Rect2 = Rect2(obs.position_offset, obs.size)
				# Does obstacle lie horizontally strictly between p1 and p2?
				if obs_rect.position.x < p2.x - 14.0 and obs_rect.end.x > p1.x + 14.0:
					# Does obstacle intersect the direct wire vertical span?
					if obs_rect.end.y > direct_y_min and obs_rect.position.y < direct_y_max:
						obstacles.append(obs)

		if not obstacles.is_empty():
			raw_detours.append({
				"fn": fn,
				"tn": tn,
				"p1": p1,
				"p2": p2,
				"obstacles": obstacles,
				"conn_key": "%d,%d>%d,%d" % [roundi(p1.x), roundi(p1.y), roundi(p2.x), roundi(p2.y)],
			})
		elif separate_wire_lanes and absf(p2.y - p1.y) > 4.0:
			standard_wires.append({
				"p1": p1,
				"p2": p2,
				"nominal_x": (p1.x + p2.x) * 0.5,
				"y_min": minf(p1.y, p2.y),
				"y_max": maxf(p1.y, p2.y),
				"down": p2.y >= p1.y,
			})

	# 1. Process obstacle detours (routing wires cleanly around cards)
	var detour_groups: Dictionary = {}
	for dw: Dictionary in raw_detours:
		var obstacles: Array = dw.obstacles
		var min_obs_left: float = INF
		var max_obs_right: float = -INF
		var min_obs_top: float = INF
		var max_obs_bottom: float = -INF
		for obs: GraphNode in obstacles:
			min_obs_left = minf(min_obs_left, obs.position_offset.x)
			max_obs_right = maxf(max_obs_right, obs.position_offset.x + obs.size.x)
			min_obs_top = minf(min_obs_top, obs.position_offset.y)
			max_obs_bottom = maxf(max_obs_bottom, obs.position_offset.y + obs.size.y)

		var mid_obs_y: float = (min_obs_top + max_obs_bottom) * 0.5
		var wire_center_y: float = (dw.p1.y + dw.p2.y) * 0.5
		var go_below: bool = (wire_center_y >= mid_obs_y)

		dw["min_obs_left"] = min_obs_left
		dw["max_obs_right"] = max_obs_right
		dw["min_obs_top"] = min_obs_top
		dw["max_obs_bottom"] = max_obs_bottom
		dw["go_below"] = go_below

		var g_key: String = "%d_%d_%d" % [roundi(min_obs_left / 40.0), roundi(max_obs_right / 40.0), 1 if go_below else 0]
		(detour_groups.get_or_add(g_key, []) as Array).append(dw)

	for g_key: String in detour_groups:
		var group: Array = detour_groups[g_key]
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a.go_below:
				return a.p1.y < b.p1.y
			else:
				return a.p1.y > b.p1.y
		)
		for idx: int in group.size():
			var dw: Dictionary = group[idx]
			var p1: Vector2 = dw.p1
			var p2: Vector2 = dw.p2
			var min_obs_left: float = dw.min_obs_left
			var max_obs_right: float = dw.max_obs_right
			var min_obs_top: float = dw.min_obs_top
			var max_obs_bottom: float = dw.max_obs_bottom
			var go_below: bool = dw.go_below

			var x1_min: float = p1.x + 8.0
			var x1_max: float = maxf(x1_min, min_obs_left - 8.0)
			var turn1_x: float = clampf((p1.x + min_obs_left) * 0.5, x1_min, x1_max)

			var x2_min: float = max_obs_right + 8.0
			var x2_max: float = maxf(x2_min, p2.x - 8.0)
			var turn2_x: float = clampf((max_obs_right + p2.x) * 0.5, x2_min, x2_max)

			var base_margin: float = 22.0 + float(idx) * 14.0
			var detour_y: float = (max_obs_bottom + base_margin) if go_below else (min_obs_top - base_margin)

			# Avoid any secondary obstacles across the detour span
			for other: GraphNode in all_graph_nodes:
				if other == dw.fn or other == dw.tn or (dw.obstacles as Array).has(other):
					continue
				var o_left: float = other.position_offset.x
				var o_right: float = other.position_offset.x + other.size.x
				if o_right > turn1_x and o_left < turn2_x:
					var o_top: float = other.position_offset.y
					var o_bottom: float = other.position_offset.y + other.size.y
					if go_below and detour_y >= o_top - 6.0 and detour_y <= o_bottom + 6.0:
						detour_y = maxf(detour_y, o_bottom + base_margin)
					elif not go_below and detour_y >= o_top - 6.0 and detour_y <= o_bottom + 6.0:
						detour_y = minf(detour_y, o_top - base_margin)

			# Stagger turns slightly if multiple wires detour together
			if idx > 0:
				turn1_x = clampf(turn1_x + float(idx) * 6.0, x1_min, x1_max)
				turn2_x = clampf(turn2_x - float(idx) * 6.0, x2_min, x2_max)

			var pts: Array[Vector2] = [
				p1,
				Vector2(turn1_x, p1.y),
				Vector2(turn1_x, detour_y),
				Vector2(turn2_x, detour_y),
				Vector2(turn2_x, p2.y),
				p2,
			]
			_detour_routes[dw.conn_key] = pts
			_detour_list.append({
				"p1": p1,
				"p2": p2,
				"points": pts,
			})

	# 2. Process standard vertical lane clustering
	if not separate_wire_lanes or standard_wires.is_empty():
		return

	var clusters: Array = []
	for w: Dictionary in standard_wires:
		var merged_into: Array = []
		for cl: Array in clusters:
			var overlaps: bool = false
			for other: Dictionary in cl:
				if absf(w.nominal_x - other.nominal_x) <= 40.0 \
						and absf(w.p1.x - other.p1.x) <= 70.0 \
						and absf(w.p2.x - other.p2.x) <= 90.0 \
						and w.y_max > other.y_min + 4.0 and other.y_max > w.y_min + 4.0:
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
		cl.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a.down != b.down:
				return a.down
			if a.down:
				return a.p2.y > b.p2.y
			else:
				return a.p2.y < b.p2.y
		)

		var left_bound: float = -INF
		var right_bound: float = INF
		for w: Dictionary in cl:
			left_bound = maxf(left_bound, w.p1.x + 20.0)
			right_bound = minf(right_bound, w.p2.x - 20.0)

		if right_bound <= left_bound + 20.0:
			left_bound = cl[0].p1.x + 10.0
			right_bound = cl[0].p2.x - 10.0

		var mid_x: float = (left_bound + right_bound) * 0.5
		var avail: float = maxf(24.0, right_bound - left_bound)
		var K: int = cl.size()
		var step_x: float = clampf(avail / float(K + 1), 14.0, 24.0)
		if (K - 1) * step_x > avail - 16.0:
			step_x = maxf(10.0, (avail - 16.0) / float(K - 1))

		for i: int in K:
			var item: Dictionary = cl[i]
			var lane_x: float = mid_x + (float(i) - float(K - 1) * 0.5) * step_x
			lane_x = clampf(lane_x, left_bound + 8.0, right_bound - 8.0)
			var conn_key: String = "%d,%d>%d,%d" % [roundi(item.p1.x), roundi(item.p1.y), roundi(item.p2.x), roundi(item.p2.y)]
			_lane_turns[conn_key] = lane_x
			_lane_list.append({
				"p1": item.p1,
				"p2": item.p2,
				"turn_x": lane_x,
			})



static func _append_wire_point(arr: PackedVector2Array, pt: Vector2) -> void:
	if arr.is_empty() or not arr[arr.size() - 1].is_equal_approx(pt):
		arr.append(pt)


## Wires thin out with the zoom like everything else; Godot keeps their width in screen pixels,
## so zoomed out they used to look fat (russian-monologue).
func _process(_delta: float) -> void:
	if is_equal_approx(zoom, _wire_zoom):
		return
	_wire_zoom = zoom
	connection_lines_thickness = maxf(1.0, _wire_thickness * minf(zoom, 1.0))
	queue_redraw()  # dashed back wires are drawn by hand and follow the zoom
