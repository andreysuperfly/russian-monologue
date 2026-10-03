class_name ConfigurationDocument extends InspectableDocument


func initialize_properties() -> void:
	define_property(Property.new("interface/language")
		.set_type("dropdown")
		.options(["System", "English", "Русский"])
		.default("System")
		.tooltip("Language of the editor itself. System follows your computer."))

	define_property(Property.new("interface/show_project_explorer")
		.set_type("bool")
		.default(true))

	define_property(Property.new("interface/show_inspector")
		.set_type("bool")
		.default(true))

	define_property(Property.new("interface/show_console")
		.set_type("bool"))

	define_property(Property.new("interface/show_status_bar")
		.set_type("bool")
		.default(true))

	define_property(Property.new("graph/snap")
		.set_type("bool"))

	define_property(Property.new("graph/show_grid")
		.set_type("bool")
		.default(true))


func set_property_value(pname: String, pvalue: Variant) -> void:
	super.set_property_value(pname, pvalue)
	ConfigManager.save_configuration()
	if pname == "interface/language":
		preload("res://i18n/locale.gd").apply(str(pvalue))


func get_type() -> String:
	return "preferences"
