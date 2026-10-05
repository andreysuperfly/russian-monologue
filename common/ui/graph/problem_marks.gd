class_name ProblemMarks
## Problems an add-on reports for the open project (a game that could not take the dialogues,
## a line it does not understand) on the cards themselves: a round mark at the card's corner,
## red for an error, amber for a warning, the words on hover (russian-monologue). The add-on
## gives them through [method MonologuePlugin.problems]; the graph asks once a second.

const ERROR: Color = Color("#d9534a")
const WARNING: Color = Color("#d9a35b")
const RADIUS: float = 10.0


## Every problem from every add-on, and the plaque line if any: {"list": [...], "headline": {...}}.
static func gather() -> Dictionary:
	var list: Array = []
	var headline: Dictionary = {}
	for plugin: MonologuePlugin in MonologueRegistry.get_instance().get_installed_plugins():
		for problem: Variant in plugin.problems():
			if problem is Dictionary:
				list.append(problem)
		var line: Dictionary = plugin.problems_headline()
		if headline.is_empty() and not line.is_empty():
			headline = line
	return {"list": list, "headline": headline}


## The problems of one card.
static func of(list: Array, node_id: String) -> Array:
	return list.filter(func(p: Dictionary) -> bool: return str(p.get("object_id", "")) == node_id)


## Puts the card's mark on, or takes it off.
static func apply(graph_node: GraphNode, node_id: String, list: Array) -> void:
	if not is_instance_valid(graph_node):
		return
	var own: Array = of(list, node_id)
	var was: Array = graph_node.get_meta(&"problems", [])
	if own == was:
		return
	graph_node.set_meta(&"problems", own)
	if not graph_node.has_meta(&"problems_hooked"):
		graph_node.set_meta(&"problems_hooked", true)
		graph_node.draw.connect(_draw.bind(graph_node))
	var words: PackedStringArray = PackedStringArray()
	for problem: Dictionary in own:
		words.append(("✖ " if problem.get("error", false) else "⚠ ") + str(problem.get("message", "")))
	graph_node.tooltip_text = "\n".join(words)
	graph_node.queue_redraw()


static func _draw(graph_node: GraphNode) -> void:
	var own: Array = graph_node.get_meta(&"problems", [])
	if own.is_empty():
		return
	var bad: bool = own.any(func(p: Dictionary) -> bool: return p.get("error", false))
	var colour: Color = ERROR if bad else WARNING
	var centre: Vector2 = Vector2(graph_node.size.x - 2.0, 2.0)
	graph_node.draw_circle(centre, RADIUS + 2.0, Color("#161616"))
	graph_node.draw_circle(centre, RADIUS, colour)
	var font: Font = graph_node.get_theme_default_font()
	var mark: String = "!" if own.size() == 1 else str(own.size())
	var size: int = 14
	var width: float = font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	graph_node.draw_string(font, centre + Vector2(-width / 2.0, size * 0.36), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color("#161616"))
