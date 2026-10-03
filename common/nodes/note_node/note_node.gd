class_name NoteNode extends InspectableNode
## A sticky note (russian-monologue): wrapped text on a coloured card, no wires.

const COLORS: Dictionary = {
	"Yellow": Color("#e8c547"), "Red": Color("#d9534f"), "Green": Color("#5cb85c"),
	"Blue": Color("#5b8fd9"), "Grey": Color("#9a9a9a"),
}


func initialize_properties() -> void:
	define_property(Property.new("note")
		.set_type("textarea")
		.main_property()
		.editable()
		.exposed(false)
		.exported(false)
		.tooltip("What to remember here. Seen only in the editor."))

	define_property(Property.new("color")
		.set_type("dropdown")
		.options(COLORS.keys())
		.default("Yellow")
		.hidden_in_graph())


func get_type() -> String:
	return "note"


## The note itself, wrapped, on its colour.
func _build_preview(_language: String = "") -> Control:
	var text: String = str(get_property_value("note")).strip_edges()
	if text.is_empty():
		return null
	var tint: Color = COLORS.get(str(get_property_value("color")), COLORS["Yellow"])
	return NodePreview.paragraph(NodePreview.plain(NodePreview.trim(text, 300)), 7, tint)
