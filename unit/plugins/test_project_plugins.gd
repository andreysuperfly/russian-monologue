extends GdUnitTestSuite

## Add-ons beside a project (russian-monologue): found, installed, gone again on unload.

const PLUGIN := """extends MonologuePlugin

func get_plugin_name() -> String:
	return "test.addon"

func register(registry: MonologueRegistry) -> void:
	var here: String = get_script().resource_path.get_base_dir()
	registry.register(load(here.path_join("score_index.gd")).new())
"""

const INDEX := """extends NodeIndexer

func _init() -> void:
	name = "addon_score"
	display_name = "Score"
	category = "Add-on"
	node_script = load(get_script().resource_path.get_base_dir().path_join("score_node.gd"))
"""

const NODE := """extends InspectableNode

func initialize_properties() -> void:
	define_property(Property.new("points").set_type("int").main_property())

func get_type() -> String:
	return "addon_score"
"""

var _root: String


func before_test() -> void:
	MonologueRegistry.reset_instance()
	_root = OS.get_cache_dir().path_join("monologue_addon_test_%d" % Time.get_ticks_usec())
	var folder: String = _root.path_join(ProjectPlugins.FOLDER).path_join("scores")
	DirAccess.make_dir_recursive_absolute(folder)
	for pair: Array in [["plugin.gd", PLUGIN], ["score_index.gd", INDEX], ["score_node.gd", NODE]]:
		var file: FileAccess = FileAccess.open(folder.path_join(pair[0]), FileAccess.WRITE)
		file.store_string(pair[1])
		file.close()


func after_test() -> void:
	ProjectPlugins.unload()
	MonologueRegistry.reset_instance()


func test_an_add_on_beside_the_project_brings_its_node_and_takes_it_away() -> void:
	var project_path: String = _root.path_join("story.mnlp")
	var entries: PackedStringArray = ProjectPlugins.found(project_path)
	assert_int(entries.size()).is_equal(1)

	assert_str(ProjectPlugins.install_from(entries[0])).is_equal("test.addon")
	var registry: MonologueRegistry = MonologueRegistry.get_instance()
	assert_object(registry.get_node("addon_score")).is_not_null()
	var node: InspectableNode = registry.create_node("addon_score", CommandManager.new())
	assert_object(node).is_not_null()
	assert_str(node.get_type()).is_equal("addon_score")

	ProjectPlugins.unload()
	assert_object(registry.get_node("addon_score")).is_null()
	# Monologue's own types stay
	assert_object(registry.get_node("sentence")).is_not_null()


func test_no_folder_means_no_add_ons() -> void:
	assert_int(ProjectPlugins.found(OS.get_cache_dir().path_join("nowhere/story.mnlp")).size()).is_equal(0)
