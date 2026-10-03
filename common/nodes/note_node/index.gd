extends NodeIndexer
## A sticky note on the graph (russian-monologue): text for whoever writes the story. No ports,
## never reached by the story, ignored by the runtime.


func _init() -> void:
	name = "note"
	display_name = "Note"
	description = "A sticky note for whoever writes the story. Has no wires and never plays."
	category = "Notes"
	enterable = false
	icon_path = "res://ui/assets/icons/text.svg"
	node_script = preload("note_node.gd")
