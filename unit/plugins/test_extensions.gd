extends GdUnitTestSuite

## Fields an add-on puts on Monologue's own objects (russian-monologue), and that they survive a
## round trip through a Monologue that does not have the add-on.

class TapePlugin extends MonologuePlugin:
	func get_plugin_name() -> String:
		return "test.tape"

	func register(registry: MonologueRegistry) -> void:
		registry.extend("sentence", func(node: InspectableObject) -> void:
			node.define_property(Property.new("tape").set_type("text")))


func before_test() -> void:
	MonologueRegistry.reset_instance()


func after_test() -> void:
	MonologueRegistry.reset_instance()


func test_an_add_on_gives_the_sentence_a_field_and_takes_it_back() -> void:
	var registry: MonologueRegistry = MonologueRegistry.get_instance()
	registry.install(TapePlugin.new())
	var sentence: InspectableNode = registry.create_node("sentence", CommandManager.new())
	assert_object(sentence.get_property("tape")).is_not_null()
	sentence.get_property("tape").set_value("kurekhin")
	assert_str(str(sentence._to_dict().get("tape"))).is_equal("kurekhin")
	# other kinds of node are untouched
	assert_object(registry.create_node("choice", CommandManager.new()).get_property("tape")).is_null()

	registry.uninstall("test.tape")
	assert_object(registry.create_node("sentence", CommandManager.new()).get_property("tape")).is_null()


func test_a_field_nobody_knows_is_kept_on_save() -> void:
	var registry: MonologueRegistry = MonologueRegistry.get_instance()
	var sentence: InspectableNode = registry.create_node("sentence", CommandManager.new())
	var saved: Dictionary = sentence._to_dict()
	saved["tape"] = "kurekhin"

	var reopened: InspectableNode = registry.create_node("sentence", CommandManager.new())
	reopened._from_dict(saved)
	assert_object(reopened.get_property("tape")).is_null()
	assert_str(str(reopened._to_dict().get("tape"))).is_equal("kurekhin")
