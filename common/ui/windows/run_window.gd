## Plays the project as it stands, in a window of its own.
##
## Nothing is written to disk first: the documents go straight from the live project into the
## addon, so an unsaved edit is what you watch. It is the shipped runtime doing the playing,
## not an editor-side imitation of it. What runs here is what a game
## running the same story would do.
##
## russian-monologue adds two things:
## - It remembers the path: every answer is recorded, and when the project is edited while the
##   window is open, the story restarts and fast-forwards along the same answers to where you
##   were (like Inky). Where the edit changed the options, it stops and waits for you.
## - A "State" panel on the right: variables (editable — a change lasts for this run and for the
##   replays after it), what everyone carries, how many nodes were passed. Nothing in it touches
##   the project itself.
class_name MonologueRunWindow extends Window

const DEFAULT_SIZE: Vector2i = Vector2i(960, 540)
const PANEL_WIDTH: int = 280
## After an edit, wait this long for typing to settle before replaying.
const REPLAY_DELAY: float = 0.6

var runtime: MonologueRuntime

var _player: MonologueDefaultPlayer
var _project: MonologueProject
var _storyline_id: String = ""
var _node_id: String = ""

## [{kind, value}] — every answer given in this run, in order.
var _journey: Array = []
## While replaying: how far along the journey; -1 when not replaying.
var _replay_at: int = -1
## Variable name → value set by hand in the State panel; put back on every replay.
var _overrides: Dictionary = {}
var _replay_timer: Timer

## Name of the saved route being checked, "" for a plain run.
var _route_name: String = ""
var _route_name_edit: LineEdit
var _routes: OptionButton

var _panel: PanelContainer
var _state_box: VBoxContainer
var _status: Label


func _init() -> void:
	hide()
	force_native = true
	title = "Run"
	size = DEFAULT_SIZE + Vector2i(PANEL_WIDTH, 0)
	content_scale_size = DEFAULT_SIZE + Vector2i(PANEL_WIDTH, 0)
	content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

	_player = MonologueDefaultPlayer.create()
	_player.autopilot = _autopilot
	_player.request_answered.connect(_on_request_answered)
	add_child(_player)

	runtime = MonologueRuntime.new()
	runtime.player = _player
	runtime.problem_reported.connect(_on_problem_reported)
	runtime.story_ended.connect(_on_story_ended)
	runtime.node_entered.connect(_on_node_entered)
	add_child(runtime)

	_replay_timer = Timer.new()
	_replay_timer.one_shot = true
	_replay_timer.wait_time = REPLAY_DELAY
	_replay_timer.timeout.connect(_replay)
	add_child(_replay_timer)

	_build_panel()


func _ready() -> void:
	close_requested.connect(_on_close_requested)


## Restarts from the top every time, so pressing Run twice does what it looks like.
func play(project: MonologueProject, storyline_id: String = "", node_id: String = "") -> void:
	if not is_node_ready():
		await ready

	_watch(project)
	_storyline_id = storyline_id
	_node_id = node_id
	_journey.clear()
	_overrides.clear()
	_replay_at = -1
	_set_status("")
	if not runtime.load_documents(ProjectWriter.documents_of(project)):
		Log.error(tr("This story cannot be played; see the problems above."))
		return

	popup_centered()
	_route_name = ""
	_fill_routes()
	runtime.start(storyline_id, node_id)
	_refresh_state()


# ---------- saved routes ----------

func _saved() -> Dictionary:
	if _project == null:
		return {}
	var value: Variant = _project.settings.get_property_value("journeys")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _fill_routes() -> void:
	_routes.clear()
	var names: Array = _saved().keys()
	names.sort()
	for route: String in names:
		_routes.add_item(route)


func _save_route() -> void:
	var route: String = _route_name_edit.text.strip_edges()
	if route.is_empty() or _project == null:
		_set_status("Name the route first.")
		return
	var routes: Dictionary = _saved()
	routes[route] = {"storyline": _storyline_id, "node": _node_id, "steps": _journey.duplicate(true)}
	_project.settings.get_property("journeys").set_value(routes)
	_fill_routes()
	_set_status(tr("Route saved: %s") % route)


func _delete_route() -> void:
	if _routes.selected < 0 or _project == null:
		return
	var routes: Dictionary = _saved()
	routes.erase(_routes.get_item_text(_routes.selected))
	_project.settings.get_property("journeys").set_value(routes)
	_fill_routes()


## Replays a saved route from its start; the status says whether it still gets through.
func _check_route() -> void:
	if _routes.selected < 0 or _project == null:
		return
	var route: String = _routes.get_item_text(_routes.selected)
	var saved: Dictionary = _saved().get(route, {})
	runtime.stop()
	if not runtime.load_documents(ProjectWriter.documents_of(_project)):
		_set_status("This story cannot be played; see the problems above.")
		return
	_storyline_id = str(saved.get("storyline", ""))
	_node_id = str(saved.get("node", ""))
	_journey = (saved.get("steps", []) as Array).duplicate(true)
	_route_name = route
	_replay_at = 0 if not _journey.is_empty() else -1
	_set_status(tr("Checking route: %s…") % route)
	runtime.start(_storyline_id, _node_id)
	_refresh_state()


# ---------- the path: record, replay ----------

func _on_request_answered(kind: String, value: Variant) -> void:
	if _replay_at >= 0:
		return
	_journey.append({"kind": kind, "value": value})


## The player asks before showing anything. During a replay: the recorded answer while the story
## still asks the same thing; null as soon as it differs, and the reader takes over from there.
func _autopilot(kind: String, options: Variant) -> Variant:
	if _replay_at < 0:
		return null
	if _replay_at >= _journey.size():
		_stop_replay(tr("Route «%s» gets through.") % _route_name if not _route_name.is_empty() else "Back where you were.")
		return null
	var step: Dictionary = _journey[_replay_at]
	if str(step.get("kind")) != kind:
		_stop_replay("The edit changed the story here; carry on yourself.")
		return null
	if kind == "offer":
		var keys: Array = []
		for option: Dictionary in options:
			keys.append(str(option.get("key", "")))
		if not keys.has(str(step.get("value"))):
			_stop_replay("That answer is gone after the edit; pick again.")
			return null
	_replay_at += 1
	return step.get("value")


func _stop_replay(why: String) -> void:
	if not _route_name.is_empty() and _replay_at < _journey.size():
		why = tr("Route «%s» breaks at step %d: %s") % [_route_name, _replay_at + 1, tr(why)]
	# What came after the point the edit changed no longer belongs to this path.
	_journey.resize(clampi(_replay_at, 0, _journey.size()))
	_replay_at = -1
	_route_name = ""
	_set_status(why)


func _watch(project: MonologueProject) -> void:
	if _project == project:
		return
	if _project and _project.content_changed.is_connected(_on_project_changed):
		_project.content_changed.disconnect(_on_project_changed)
	_project = project
	if _project:
		_project.content_changed.connect(_on_project_changed)


func _on_project_changed() -> void:
	if visible:
		_replay_timer.start()


## Restart with the edited project and run the recorded answers again.
func _replay() -> void:
	if not visible or _project == null:
		return
	runtime.stop()
	if not runtime.load_documents(ProjectWriter.documents_of(_project)):
		_set_status("This story cannot be played; see the problems above.")
		return
	_replay_at = 0 if not _journey.is_empty() else -1
	_set_status("Edited — replaying your path…")
	runtime.start(_storyline_id, _node_id)
	_apply_overrides()
	_refresh_state()


# ---------- the State panel ----------

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -PANEL_WIDTH
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	var title_label: Label = Label.new()
	title_label.text = "State"
	title_label.tooltip_text = "Changes here last for this run only. The project is not touched."
	title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(title_label)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.65)
	column.add_child(_status)
	var restart: Button = Button.new()
	restart.text = "Restart from the top"
	restart.pressed.connect(func() -> void:
		if _project:
			play(_project, _storyline_id, _node_id))
	column.add_child(restart)

	# saved routes: record this path under a name, check one later
	var save_row: HBoxContainer = HBoxContainer.new()
	_route_name_edit = LineEdit.new()
	_route_name_edit.placeholder_text = "Route name"
	_route_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_route_name_edit)
	var save: Button = Button.new()
	save.text = "Save route"
	save.tooltip_text = "Keep the answers given so far under this name, in the project."
	save.pressed.connect(_save_route)
	save_row.add_child(save)
	column.add_child(save_row)
	var play_row: HBoxContainer = HBoxContainer.new()
	_routes = OptionButton.new()
	_routes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_routes.clip_text = true
	_routes.fit_to_longest_item = false
	play_row.add_child(_routes)
	var check: Button = Button.new()
	check.text = "Check"
	check.tooltip_text = "Replay the saved route and say whether it still gets through."
	check.pressed.connect(_check_route)
	play_row.add_child(check)
	var forget: Button = Button.new()
	forget.text = "✕"
	forget.tooltip_text = "Delete this route."
	forget.pressed.connect(_delete_route)
	play_row.add_child(forget)
	column.add_child(play_row)

	_state_box = VBoxContainer.new()
	column.add_child(_state_box)
	# Above the player, which draws on its own canvas layer.
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 100
	layer.add_child(_panel)
	add_child(layer)


func _set_status(text: String) -> void:
	if _status:
		_status.text = tr(text) if not text.is_empty() else ""


func _on_node_entered(_storyline: String, _node: String) -> void:
	_refresh_state.call_deferred()


func _refresh_state() -> void:
	if _state_box == null:
		return
	for child: Node in _state_box.get_children():
		child.queue_free()
	var session: MonologueSession = runtime.session
	if session == null or runtime.graph == null:
		return

	_heading("Variables")
	# Every declared variable, not only the ones the run has written yet.
	var named: Dictionary = {}
	var declared: Dictionary = runtime.graph.collections.get("variables", {})
	for variable_id: String in declared:
		var record: Dictionary = declared[variable_id]
		var variable_name: String = str(record.get("name", ""))
		if not variable_name.is_empty():
			named[variable_name] = session.state.variables.get(variable_id, record.get("value"))
	var names: Array = named.keys()
	names.sort()
	for variable_name: String in names:
		_state_box.add_child(_variable_row(variable_name, named[variable_name]))

	_heading("Pockets")
	var any: bool = false
	for character_id: String in session.state.inventory:
		var who: String = str(runtime.graph.record("characters", character_id).get("name", character_id))
		var held: Dictionary = session.state.inventory[character_id]
		for item_id: String in held:
			if int(held[item_id]) <= 0:
				continue
			var item: String = str(runtime.graph.record("items", item_id).get("name", item_id))
			_line("%s: %s × %d" % [who, item, int(held[item_id])])
			any = true
	if not any:
		_line(tr("empty"))

	_heading("Passed")
	_line(tr("%d nodes, %d answers recorded") % [session.state.visited.size(), _journey.size()])


func _heading(text: String) -> void:
	var label: Label = Label.new()
	label.text = tr(text)
	label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.45))
	_state_box.add_child(label)


func _line(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state_box.add_child(label)


## Name and an editor matching the value's type. Editing writes into this run only.
func _variable_row(variable_name: String, value: Variant) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = variable_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	if value is bool:
		var box: CheckBox = CheckBox.new()
		box.button_pressed = value
		box.toggled.connect(func(on: bool) -> void: _override(variable_name, on))
		row.add_child(box)
	elif value is int or value is float:
		var spin: SpinBox = SpinBox.new()
		spin.min_value = -100000
		spin.max_value = 100000
		spin.step = 1 if value is int else 0.1
		spin.value = value
		spin.value_changed.connect(func(v: float) -> void: _override(variable_name, int(v) if value is int else v))
		row.add_child(spin)
	else:
		var edit: LineEdit = LineEdit.new()
		edit.text = str(value)
		edit.custom_minimum_size.x = 110
		edit.text_submitted.connect(func(t: String) -> void: _override(variable_name, t))
		row.add_child(edit)
	return row


func _override(variable_name: String, value: Variant) -> void:
	_overrides[variable_name] = value
	runtime.set_var(variable_name, value)
	_set_status(tr("Set by hand: %s") % variable_name)


func _apply_overrides() -> void:
	for variable_name: String in _overrides:
		runtime.set_var(variable_name, _overrides[variable_name])


func _on_story_ended(reason: String) -> void:
	Log.info(tr("The story stopped: %s.") % reason)
	if not _route_name.is_empty():
		var reached: int = _replay_at
		var finished: bool = reached < 0 or reached >= _journey.size()
		_replay_at = -1
		_set_status(tr("Route «%s» gets through.") % _route_name if finished else tr("Route «%s» ends early, at step %d.") % [_route_name, reached + 1])
		_route_name = ""
		_refresh_state()
		return
	_replay_at = -1
	_set_status("The story stopped.")
	_refresh_state()


func _on_problem_reported(problem: MonologueProblem) -> void:
	if problem.is_error():
		Log.error(problem.message)
		return
	Log.warn(problem.message)


func _on_close_requested() -> void:
	runtime.stop()
	_replay_timer.stop()
	hide()
