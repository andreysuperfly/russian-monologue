## Search across the whole project (russian-monologue): every word of the query must be found,
## in any order, case and ё/е ignored. Looks at what a writer would remember: the lines, the
## options of a choice, who speaks, the storyline's name, notes, flags and conditions.
class_name ProjectSearch
extends RefCounted

## Stored values that are machinery, never something to find.
const SKIP: Array[String] = ["id", "editor_position", "extra/node_color", "node_color", "editor_size"]
## «sentence-1T0RPQ9E», «storyline-7S72CHTN»: ids, not words.
static var _id_like: RegEx = RegEx.create_from_string("^[a-z_]+-[A-Z0-9]{6,}$")


## What to compare: lower case, ё as е, spaces squeezed.
static func normalize(text: String) -> String:
	return " ".join(text.to_lower().replace("ё", "е").split(" ", false))


static func words_of(query: String) -> PackedStringArray:
	return normalize(query).split(" ", false)


static func has_all(haystack: String, words: PackedStringArray) -> bool:
	for word: String in words:
		if not haystack.contains(word):
			return false
	return true


## {storylines: [StorylineDocument], hits: [{storyline, node, speaker, text, field}]}, hits in
## story order. A node is a hit when all words are found in it and its storyline's name together,
## and at least one of them in the node itself — so «толян код» finds Tolyan's lines about the
## code, while «толян» alone lists the storyline, not each of its hundred cards.
static func run(project: MonologueProject, query: String, limit: int = 300) -> Dictionary:
	var words: PackedStringArray = words_of(query)
	var found_storylines: Array[StorylineDocument] = []
	var hits: Array[Dictionary] = []
	if project == null or words.is_empty():
		return {"storylines": found_storylines, "hits": hits}

	var language: String = project.active_language_code
	for storyline: StorylineDocument in project.storylines:
		var title: String = normalize(storyline.name)
		if has_all(title, words):
			found_storylines.append(storyline)
		for node: InspectableNode in storyline.nodes:
			if hits.size() >= limit:
				break
			var parts: Array[Dictionary] = _texts_of(node, language)
			var own: String = ""
			for part: Dictionary in parts:
				own += " " + normalize(part["text"])
			if not _any_in(own, words) or not has_all(own + " " + title, words):
				continue
			var shown: Dictionary = _best_part(parts, words)
			hits.append({
				"storyline": storyline,
				"node": node,
				"speaker": GraphNodeViewFactory._speaker_name(node) if node.get_property("speaker") else "",
				"text": shown["text"],
				"field": shown["field"],
			})
	return {"storylines": found_storylines, "hits": hits}


static func _any_in(haystack: String, words: PackedStringArray) -> bool:
	for word: String in words:
		if haystack.contains(word):
			return true
	return false


## Every readable piece of a node, with the field it came from ("" for the node's main text).
static func _texts_of(node: InspectableNode, language: String) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var speaker: String = GraphNodeViewFactory._speaker_name(node) if node.get_property("speaker") else ""
	if not speaker.is_empty():
		parts.append({"text": speaker, "field": "speaker"})
	for prop: Property in node.get_properties():
		if prop.name in SKIP or prop.name == "speaker":
			continue
		var main: bool = prop.name in ["line", "text", "choices", "options"]
		var label: String = "" if main else prop.get_display_name()
		_collect(prop.get_value(), language, label, parts)
	return parts


static func _collect(value: Variant, language: String, field: String, into: Array[Dictionary]) -> void:
	if value is String:
		var text: String = (value as String).strip_edges()
		if not text.is_empty() and not _id_like.search(text):
			into.append({"text": text, "field": field})
	elif value is Dictionary:
		var dict: Dictionary = value
		# a translated text: the active language, else whichever has something
		if not dict.is_empty() and dict.keys().all(func(k: Variant) -> bool: return k is String and (k as String).length() <= 3):
			var text: String = Util.to_label(dict, language)
			if not text.is_empty():
				into.append({"text": text, "field": field})
			return
		for key: Variant in dict:
			if str(key) in SKIP:
				continue
			_collect(dict[key], language, field, into)
	elif value is Array:
		for entry: Variant in value:
			_collect(entry, language, field, into)


## The piece to show: the one holding most of the words, the main text on a tie.
static func _best_part(parts: Array[Dictionary], words: PackedStringArray) -> Dictionary:
	var best: Dictionary = {"text": "", "field": ""}
	var best_score: int = -1
	for part: Dictionary in parts:
		if part["field"] == "speaker":
			continue
		var text: String = normalize(part["text"])
		var score: int = 0
		for word: String in words:
			if text.contains(word):
				score += 2
		if part["field"] == "":
			score += 1
		if score > best_score:
			best_score = score
			best = part
	return best


## The text cut around the first word found, with every word made to stand out.
static func snippet(text: String, words: PackedStringArray, color: Color, room: int = 120) -> String:
	var plain: String = " ".join(text.replace("\n", " ").split(" ", false))
	# same length as plain, so positions found in one hold in the other
	var low: String = plain.to_lower().replace("ё", "е")
	var first: int = plain.length()
	for word: String in words:
		var at: int = low.find(word)
		if at >= 0:
			first = mini(first, at)
	var start: int = 0
	if first < plain.length() and first > room / 3:
		start = first - room / 3
	var cut: String = plain.substr(start, room)
	var prefix: String = "…" if start > 0 else ""
	var suffix: String = "…" if start + room < plain.length() else ""
	var low_cut: String = cut.to_lower().replace("ё", "е")
	# mark the found stretches, then build the bbcode once
	var marked: Array[bool] = []
	marked.resize(cut.length())
	marked.fill(false)
	for word: String in words:
		var from: int = 0
		while true:
			var at: int = low_cut.find(word, from)
			if at < 0:
				break
			for i: int in range(at, mini(at + word.length(), cut.length())):
				marked[i] = true
			from = at + 1
	var out: String = prefix
	var on: bool = false
	var hex: String = color.to_html(false)
	for i: int in cut.length():
		if marked[i] and not on:
			out += "[color=#%s][b]" % hex
			on = true
		elif not marked[i] and on:
			out += "[/b][/color]"
			on = false
		var ch: String = cut[i]
		out += "[lb]" if ch == "[" else ch
	if on:
		out += "[/b][/color]"
	return out + suffix
