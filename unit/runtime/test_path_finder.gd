extends GdUnitTestSuite

## Paths read backwards (russian-monologue): every way into an ending and what each one needs.

func before_test() -> void:
	MonologueRegistry.reset_instance()


func after_test() -> void:
	MonologueRegistry.reset_instance()


func _example() -> MonologueProject:
	var project: MonologueProject = auto_free(MonologueProject.new(ExampleTemplate.new()))
	await project.ready
	return project


func _end_in(project: MonologueProject, storyline_name: String) -> Array:
	for storyline: StorylineDocument in project.storylines:
		if storyline.name != storyline_name:
			continue
		for node: InspectableNode in storyline.nodes:
			if node.get_type() == "end":
				return [storyline, node.get_id()]
	return []


func test_every_branch_into_an_ending_is_its_own_path() -> void:
	var project: MonologueProject = await _example()
	var target: Array = _end_in(project, "epilogue")
	var paths: Array = PathFinder.paths_to(project, target[0], target[1])
	assert_int(paths.size()).is_greater_equal(3)
	var all_needs: Array = []
	for path: Array in paths:
		all_needs.append("; ".join(PathFinder.needs_of(path)))
	assert_bool(all_needs.any(func(n: String) -> bool: return n.contains("≥ 3") and not n.contains("("))).override_failure_message(
		"No path asked for the condition to pass: %s" % [all_needs]).is_true()
	assert_bool(all_needs.any(func(n: String) -> bool: return n.contains("(") and n.contains("≥ 3"))).override_failure_message(
		"No path asked for the condition to fail: %s" % [all_needs]).is_true()


func test_paths_cross_into_the_storyline_that_leads_here() -> void:
	var project: MonologueProject = await _example()
	var target: Array = _end_in(project, "epilogue")
	var first: Dictionary = PathFinder.paths_to(project, target[0], target[1])[0][0]
	assert_str((first["storyline"] as StorylineDocument).name).is_equal("main")
	assert_str((first["node"] as InspectableNode).get_type()).is_equal("root")
