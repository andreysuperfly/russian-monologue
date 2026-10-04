## The only text widget. `text` and `textarea` both use it.
##
## A translated property holds {language_code: text}, a plain one a String. Never guessed
## from the value. The property says so. Which language is shown is the project's business,
## set once in the header rather than once per field.
class_name TextField
extends Field

var _is_multiline: bool = false
var _is_preview: bool = false
var _is_translatable: bool = false
## One entry under "" when the property is plain, so the widget has one shape to work
## with.
var _values: Dictionary = {}

@onready var line_edit: LineEdit = %LineEdit
@onready var text_edit: TextEdit = %TextEdit


func _ready() -> void:
	super._ready()
	line_edit.text_changed.connect(_on_text_changed)
	line_edit.text_submitted.connect(_on_text_submitted)
	line_edit.focus_exited.connect(_on_focus_exited)
	text_edit.text_changed.connect(_on_textarea_changed)
	text_edit.focus_exited.connect(_on_textarea_focus_exited)
	EventBus.language_changed.connect(_on_language_changed)


func _on_initialize() -> void:
	_is_multiline = settings.get(PropertySettings.KEY_MULTILINE, false)
	_is_translatable = settings.get(PropertySettings.KEY_TRANSLATABLE, false) == true

	var placeholder: String = str(settings.get(PropertySettings.KEY_PLACEHOLDER, ""))
	text_edit.placeholder_text = placeholder
	line_edit.placeholder_text = placeholder

	var rows: int = settings.get(PropertySettings.KEY_ROWS, 4)
	if _is_multiline or _is_preview:
		_apply_textarea_height.call_deferred(text_edit, rows)

	if not _is_preview:
		line_edit.visible = false
		text_edit.visible = true
		if not _is_multiline:
			_wrap_one_line()


## A one-line field that is longer than the panel is wide wraps and grows downwards instead of
## hiding its start (russian-monologue). Still one line of text: Enter ends the edit, a pasted
## line break becomes a space.
func _wrap_one_line() -> void:
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.scroll_fit_content_height = true
	text_edit.custom_minimum_size.y = 0
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not text_edit.gui_input.is_connected(_on_one_line_key):
		text_edit.gui_input.connect(_on_one_line_key)


func _on_one_line_key(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key and key.pressed and key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		text_edit.accept_event()
		text_edit.release_focus()


func _apply_textarea_height(te: TextEdit, rows: int) -> void:
	var reset_te: bool = not te.text
	if reset_te:
		te.text = " "

	var sb: StyleBox = te.get_theme_stylebox("normal")
	var padding: float = (sb.content_margin_bottom + sb.content_margin_top) if sb else 8.0
	te.custom_minimum_size.y = te.get_line_height() * rows + padding

	if reset_te:
		te.text = ""


func set_value(value: Variant) -> void:
	if not is_node_ready():
		await ready

	if _is_translatable:
		_values = (value as Dictionary).duplicate() if value is Dictionary else {}
	else:
		_values = {"": str(value) if value != null else ""}
	_refresh_text()


func get_value() -> Variant:
	if _is_translatable:
		return _values.duplicate()
	return _values.get("", "")


func set_editable(is_editable: bool) -> void:
	line_edit.editable = is_editable
	text_edit.editable = is_editable


func set_preview() -> void:
	_is_preview = true
	if not is_node_ready():
		await ready

	line_edit.show()
	text_edit.hide()
	line_edit.theme_type_variation = "LineEditListItemPreview"


func display_issues(issues: Array[ValidationIssue]) -> void:
	super.display_issues(issues)
	if issues.is_empty():
		line_edit.remove_theme_color_override("font_color")
		text_edit.remove_theme_color_override("font_color")
		return

	var color: Color = ThemeLayout.fail_color
	line_edit.add_theme_color_override("font_color", color)
	text_edit.add_theme_color_override("font_color", color)


func prefers_vertical_layout(p_settings: Dictionary) -> bool:
	return p_settings.get(PropertySettings.KEY_MULTILINE, false)


## The project's active language, or the unnamed slot for a plain property.
func _current_key() -> String:
	if not _is_translatable:
		return ""
	var project: MonologueProject = ProjectManager.current_project
	var code: String = project.active_language_code if project else "en"
	return code if not code.is_empty() else "en"


func _refresh_text() -> void:
	var text: String = str(_values.get(_current_key(), ""))
	if line_edit.text != text:
		line_edit.text = text
	if text_edit.text != text:
		text_edit.text = text


func _write(text: String) -> void:
	_values[_current_key()] = text


func _on_language_changed(_code: String) -> void:
	_refresh_text()


func _on_text_changed(new_text: String) -> void:
	_write(new_text)
	emit_value_changed(get_value())


func _on_text_submitted(submitted_text: String) -> void:
	_write(submitted_text)
	emit_value_committed(get_value())


func _on_focus_exited() -> void:
	if not is_inside_tree():
		return
	_write(line_edit.text)
	emit_value_committed(get_value())


func _on_textarea_changed() -> void:
	if not _is_multiline and text_edit.text.contains("\n"):
		var column: int = text_edit.get_caret_column()
		text_edit.text = text_edit.text.replace("\r", "").replace("\n", " ")
		text_edit.set_caret_column(column)
		return  # setting the text calls this again
	_write(text_edit.text)
	emit_value_changed(get_value())


func _on_textarea_focus_exited() -> void:
	if not is_inside_tree():
		return
	_write(text_edit.text)
	emit_value_committed(get_value())
