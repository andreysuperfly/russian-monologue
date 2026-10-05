## Puts two edits of one project together (russian-monologue): the one held in the editor and
## the one another program wrote to disk since the file was last read or written here.
##
## Three versions go in, as [method ProjectWriter.documents_of] lays them out: [i]base[/i], the
## file as it was read or written last; [i]mine[/i], the editor's copy; [i]theirs[/i], the file as
## it is now. Whatever changed on one side only is taken from that side — a node, a field of a
## node, a wire, a character — so neither edit is lost. A field both sides changed, each its own
## way, is a conflict: one side wins (the editor's, unless asked otherwise) and it is listed.
class_name ProjectMerge extends RefCounted

## Stands for "not there": null is a value a field can hold.
const ABSENT: StringName = &"<absent>"
const STORYLINE_KEY: String = "storyline:"

## The merged documents, laid out the way [method ProjectWriter.documents_of] does.
var documents: Dictionary = {}
## One entry per node or record both sides changed differently:
## {"id", "document", "label"}, in the order they were met.
var conflicts: Array[Dictionary] = []
## How many nodes and records came out different from the editor's copy.
var changed: int = 0

var _prefer_theirs: bool = false
var _conflict_ids: Dictionary = {}


static func merge(
	base: Dictionary, mine: Dictionary, theirs: Dictionary, prefer_theirs: bool = false
) -> ProjectMerge:
	var result: ProjectMerge = ProjectMerge.new()
	result._prefer_theirs = prefer_theirs
	var b: Dictionary = _by_identity(base)
	var m: Dictionary = _by_identity(mine)
	var t: Dictionary = _by_identity(theirs)

	var merged: Dictionary = {}
	for key: String in _union_in_order(m.keys(), t.keys()):
		var document: Variant = result._merge3(
			b.get(key, ABSENT), m.get(key, ABSENT), t.get(key, ABSENT), "", {}, _title_of(key, m, t)
		)
		if not _same(document, ABSENT):
			merged[key] = document

	for key: String in merged:
		_drop_loose_wires(merged[key])
		result.documents[_entry_of(key, merged[key])] = merged[key]
	result.changed = _count_changed(mine, result.documents)
	return result


## True when the result holds exactly what the editor already has.
func is_same_as(mine: Dictionary) -> bool:
	return _same(documents, mine)


## The conflicts as lines a person can read: where, and which card.
func describe_conflicts(limit: int = 6) -> String:
	var lines: PackedStringArray = []
	for conflict: Dictionary in conflicts.slice(0, limit):
		lines.append("%s · %s" % [conflict["document"], conflict["label"]])
	if conflicts.size() > limit:
		lines.append("…")
	return "\n".join(lines)


# ---------- the merge itself ----------


func _merge3(
	base: Variant, mine: Variant, theirs: Variant, owner: String, owner_data: Dictionary,
	document: String
) -> Variant:
	if _same(mine, theirs):
		return mine
	if _same(base, mine):
		return theirs
	if _same(base, theirs):
		return mine
	if base is Dictionary and mine is Dictionary and theirs is Dictionary:
		return _merge_dicts(base, mine, theirs, owner, owner_data, document)
	if base is Array and mine is Array and theirs is Array and _all_have_ids([base, mine, theirs]):
		return _merge_lists(base, mine, theirs, owner, owner_data, document)

	# both changed it, differently
	var data: Dictionary = owner_data
	if data.is_empty():
		data = mine if mine is Dictionary else (theirs if theirs is Dictionary else {})
	var id: String = owner if not owner.is_empty() else str(data.get("id", document))
	if not _conflict_ids.has(id):
		_conflict_ids[id] = true
		conflicts.append({"id": id, "document": document, "label": _label_of(data, id)})
	return theirs if _prefer_theirs else mine


func _merge_dicts(
	base: Dictionary, mine: Dictionary, theirs: Dictionary, owner: String, owner_data: Dictionary,
	document: String
) -> Dictionary:
	if mine.has("id"):
		owner = str(mine["id"])
		owner_data = mine
	var merged: Dictionary = {}
	for key: Variant in _union_in_order(mine.keys(), theirs.keys()):
		var b: Variant = base.get(key, ABSENT)
		var m: Variant = mine.get(key, ABSENT)
		var t: Variant = theirs.get(key, ABSENT)
		var value: Variant
		if str(key) == "connections" and b is Array and m is Array and t is Array:
			value = _merge_sets(b, m, t)
		else:
			value = _merge3(b, m, t, owner, owner_data, document)
		if not _same(value, ABSENT):
			merged[key] = value
	return merged


## A list of things that each carry an id (nodes, sections, records): merged item by item.
func _merge_lists(
	base: Array, mine: Array, theirs: Array, owner: String, owner_data: Dictionary,
	document: String
) -> Array:
	var b: Dictionary = _index(base)
	var m: Dictionary = _index(mine)
	var t: Dictionary = _index(theirs)
	var merged: Array = []
	for id: String in _order(b.keys(), m.keys(), t.keys()):
		var item: Variant = _merge3(
			b.get(id, ABSENT), m.get(id, ABSENT), t.get(id, ABSENT), id,
			m.get(id, t.get(id, {})), document
		)
		if not _same(item, ABSENT):
			merged.append(item)
	return merged


## Wires have no id: a wire is what it joins. Kept if both sides have it, or if one side added it;
## gone if either side took it away.
static func _merge_sets(base: Array, mine: Array, theirs: Array) -> Array:
	var in_base: Dictionary = _keys_of(base)
	var in_mine: Dictionary = _keys_of(mine)
	var in_theirs: Dictionary = _keys_of(theirs)
	var merged: Array = []
	var taken: Dictionary = {}
	for item: Variant in mine + theirs:
		var key: String = JSON.stringify(item)
		if taken.has(key):
			continue
		var keep: bool = (
			(in_mine.has(key) and in_theirs.has(key))
			or (in_mine.has(key) and not in_base.has(key))
			or (in_theirs.has(key) and not in_base.has(key))
		)
		if keep:
			taken[key] = true
			merged.append(item)
	return merged


## The order of a merged list: the side that reordered wins, and what the other side added is
## put right after whatever it followed there.
static func _order(base: Array, mine: Array, theirs: Array) -> Array:
	var primary: Array = theirs if mine == base else mine
	var secondary: Array = mine if mine == base else theirs
	var out: Array = primary.duplicate()
	for i: int in secondary.size():
		var id: Variant = secondary[i]
		if id in out:
			continue
		var at: int = out.find(secondary[i - 1]) + 1 if i > 0 else 0
		out.insert(at, id)
	return out


# ---------- helpers ----------


## Storylines are known by their id, not their file name: a renamed storyline is the same one.
static func _by_identity(documents: Dictionary) -> Dictionary:
	var keyed: Dictionary = {}
	for entry: String in documents:
		var data: Dictionary = documents[entry]
		if entry.begins_with(MonologueSource.STORYLINES + "/") and data.has("id"):
			keyed[STORYLINE_KEY + str(data["id"])] = data
		else:
			keyed[entry] = data
	return keyed


static func _entry_of(key: String, data: Dictionary) -> String:
	if key.begins_with(STORYLINE_KEY):
		return MonologueSource.document_path(MonologueSource.STORYLINES, str(data.get("name", "")))
	return key


static func _title_of(key: String, mine: Dictionary, theirs: Dictionary) -> String:
	var data: Variant = mine.get(key, theirs.get(key, {}))
	if data is Dictionary and (data as Dictionary).has("name"):
		return str(data["name"])
	return key.get_file().get_basename()


## A wire left pointing at a node one side deleted goes with it.
static func _drop_loose_wires(data: Variant) -> void:
	if data is Array:
		for item: Variant in data:
			_drop_loose_wires(item)
		return
	if data is not Dictionary:
		return
	var graph: Dictionary = data
	if graph.get("nodes") is Array and graph.get("connections") is Array:
		var ids: Dictionary = _index(graph["nodes"])
		graph["connections"] = (graph["connections"] as Array).filter(
			func(wire: Variant) -> bool:
				return (
					wire is Dictionary
					and ids.has(str(wire.get("from_node_id", "")))
					and ids.has(str(wire.get("to_node_id", "")))
				)
		)
	for value: Variant in graph.values():
		if value is Array:
			_drop_loose_wires(value)


## Nodes (with the wires leaving them) and records that differ between two layouts.
static func _count_changed(before: Dictionary, after: Dictionary) -> int:
	var a: Dictionary = _signatures(before)
	var b: Dictionary = _signatures(after)
	var count: int = 0
	for id: String in _union_in_order(a.keys(), b.keys()):
		if a.get(id, "") != b.get(id, ""):
			count += 1
	return count


static func _signatures(documents: Dictionary) -> Dictionary:
	var found: Dictionary = {}
	for entry: String in documents:
		var data: Dictionary = documents[entry]
		if entry.begins_with(MonologueSource.COLLECTIONS + "/"):
			var records: Variant = data.get(entry.get_file().get_basename(), [])
			if records is Array:
				for record: Variant in records:
					if record is Dictionary and record.has("id"):
						found[str(record["id"])] = JSON.stringify(record)
		elif entry.begins_with(MonologueSource.STORYLINES + "/"):
			_graph_signatures(data, found)
			for section: Variant in data.get(MonologueSource.SECTIONS, []):
				if section is Dictionary:
					_graph_signatures(section, found)
	return found


static func _graph_signatures(graph: Dictionary, found: Dictionary) -> void:
	var leaving: Dictionary = {}
	for wire: Variant in graph.get("connections", []):
		if wire is Dictionary:
			var from: String = str(wire.get("from_node_id", ""))
			if not leaving.has(from):
				leaving[from] = []
			leaving[from].append(JSON.stringify(wire))
	for node: Variant in graph.get("nodes", []):
		if node is Dictionary and node.has("id"):
			var id: String = str(node["id"])
			var wires: Array = leaving.get(id, [])
			wires.sort()
			var data: Dictionary = node
			# a label nobody gave is made up anew on every read: not a change anyone made
			if _auto_label().search(str(data.get("label", ""))) != null:
				data = data.duplicate()
				data.erase("label")
			found[id] = JSON.stringify(data) + JSON.stringify(wires)


static var _auto_label_regex: RegEx


static func _auto_label() -> RegEx:
	if _auto_label_regex == null:
		_auto_label_regex = RegEx.create_from_string("^[a-z_]+-[A-Z0-9]{8}$")
	return _auto_label_regex


static func _label_of(data: Dictionary, id: String) -> String:
	for key: String in ["line", "title", "text", "name", "label"]:
		var value: Variant = data.get(key)
		if value is Dictionary and not (value as Dictionary).is_empty():
			value = (value as Dictionary).values()[0]
		if value is String and not (value as String).strip_edges().is_empty():
			var text: String = (value as String).strip_edges().replace("\n", " ")
			return text if text.length() <= 40 else text.left(39) + "…"
	return id


static func _index(items: Array) -> Dictionary:
	var by_id: Dictionary = {}
	for item: Variant in items:
		if item is Dictionary and (item as Dictionary).has("id"):
			by_id[str(item["id"])] = item
	return by_id


static func _keys_of(items: Array) -> Dictionary:
	var keys: Dictionary = {}
	for item: Variant in items:
		keys[JSON.stringify(item)] = true
	return keys


static func _all_have_ids(lists: Array) -> bool:
	for list: Array in lists:
		for item: Variant in list:
			if item is not Dictionary or not (item as Dictionary).has("id"):
				return false
	return true


static func _union_in_order(first: Array, second: Array) -> Array:
	var out: Array = first.duplicate()
	for key: Variant in second:
		if key not in out:
			out.append(key)
	return out


## Equal and of the same type: a field that is a number on one side and a word on the other
## is not the same field, and comparing the two would be an error.
static func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b
