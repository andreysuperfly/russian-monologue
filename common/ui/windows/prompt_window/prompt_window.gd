class_name Prompt extends MonologueWindow

enum { CONFIRMED, DENIED, CANCELLED }

signal confirmed
signal denied
signal cancelled

@onready var title_label: Label = %TitleLabel
@onready var description_label: Label = %DescriptionLabel
@onready var confirm_button: Button = %ConfirmButton
@onready var deny_button: Button = %DenyButton
@onready var cancel_button: Button = %CancelButton

var _callback: Callable


func _ready() -> void:
	EventBus.ask_dialog.connect(_on_ask_request)
	EventBus.window_out.connect(_on_cancel_button_pressed)
	_make_compact()


## A smaller window with bigger buttons (russian-monologue): the question is short, the choice
## is what matters, and «Save» stands out as the usual answer.
func _make_compact() -> void:
	size = Vector2i(560, 190)
	var panel: Control = get_node_or_null("PanelContainer")
	if panel:
		panel.offset_left = -270
		panel.offset_right = 270
		panel.offset_top = -85
		panel.offset_bottom = 85
	var margins: MarginContainer = get_node_or_null("PanelContainer/MarginContainer")
	if margins:
		for side: String in ["left", "top", "right", "bottom"]:
			margins.add_theme_constant_override("margin_" + side, 20)
	var picture: Control = get_node_or_null("PanelContainer/MarginContainer/HBox/TextureRect")
	if picture:
		picture.custom_minimum_size.x = 52
	var row: HBoxContainer = get_node_or_null("PanelContainer/MarginContainer/HBox")
	if row:
		row.add_theme_constant_override("separation", 18)
	description_label.custom_minimum_size = Vector2(360, 0)
	for button: Button in [confirm_button, deny_button, cancel_button]:
		button.custom_minimum_size = Vector2(124, 42)
		button.add_theme_font_size_override("font_size", 16)
		button.flat = false
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 1, 0.08)
		box.set_corner_radius_all(8)
		box.set_content_margin_all(8)
		var hover: StyleBoxFlat = box.duplicate()
		hover.bg_color = Color(1, 1, 1, 0.14)
		if button == confirm_button:
			box.bg_color = ThemeLayout.accent_color
			hover.bg_color = ThemeLayout.accent_color.lightened(0.12)
		button.add_theme_stylebox_override(&"normal", box)
		button.add_theme_stylebox_override(&"hover", hover)
		button.add_theme_stylebox_override(&"pressed", hover)
		button.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())


func _on_confirm_button_pressed() -> void:
	hide()
	confirmed.emit()
	_callback_handler(Prompt.CONFIRMED)


func _on_deny_button_pressed() -> void:
	hide()
	denied.emit()
	_callback_handler(Prompt.DENIED)


func _on_cancel_button_pressed() -> void:
	if not visible:
		return

	hide()
	cancelled.emit()
	_callback_handler(Prompt.CANCELLED)


func _callback_handler(response: int) -> void:
	if not _callback:
		Log.error("Prompt window has no callback.")
		return

	if _callback.get_argument_count() < 1:
		Log.error("Invalid callback.")
		return

	_callback.call(response)


func _on_ask_request(
	callback: Callable,
	header: String,
	description: String,
	confirm_text: String = "Yes",
	deny_text: String = "No",
	cancel_text: String = "Cancel"
) -> void:
	_callback = callback

	title_label.text = header
	description_label.text = description
	confirm_button.text = confirm_text
	deny_button.text = deny_text
	cancel_button.text = cancel_text

	show()
