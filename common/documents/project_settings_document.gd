class_name ProjectSettingsDocument extends InspectableDocument


func initialize_properties() -> void:
	define_property(Property.new("display_response_in_the_flow")
		.set_type("bool"))

	# Saved routes (russian-monologue): name → {"storyline", "node", "steps": [{kind, value}]}.
	# Recorded and replayed by the Run window; kept in the project so they travel with it.
	# Templates (russian-monologue): see GraphTemplates.
	define_property(Property.new("templates")
		.set_type("any")
		.default({})
		.hidden_in_inspector())

	define_property(Property.new("journeys")
		.set_type("any")
		.default({})
		.hidden_in_inspector())


func get_type() -> String:
	return "settings"
