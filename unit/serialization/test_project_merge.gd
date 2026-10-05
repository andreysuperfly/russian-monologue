extends GdUnitTestSuite

## Merging another program's edits on disk into the editor's copy (russian-monologue).
##
## Every case starts from one base project; "mine" is what the editor did to it, "theirs" what
## was written to disk meanwhile. The documents are laid out the way ProjectWriter.documents_of
## does, by hand, so the merge is checked on its own.

const STORY: String = "storylines/Story.mnlf"
const PEOPLE: String = "collections/characters.mnlf"


static func _node(id: String, line: String, extra: Dictionary = {}) -> Dictionary:
	var node: Dictionary = {"$type": "sentence", "id": id, "line": {"en": line}, "editor_position": [0.0, 0.0]}
	node.merge(extra, true)
	return node


static func _wire(from: String, to: String) -> Dictionary:
	return {"from_node_id": from, "from_property": "sentence", "to_node_id": to, "to_property": "sentence"}


func _base() -> Dictionary:
	return {
		"manifest.mnlf": {"$type": "manifest", "id": "manifest-1", "entry_point": "storyline-1"},
		PEOPLE: {"$type": "collection", "id": "collection-1", "characters": [
			{"$type": "character", "id": "character-1", "name": "Ann", "color": "#ffffff"},
		]},
		STORY: {
			"$type": "storyline", "id": "storyline-1", "name": "Story", "root_node_id": "a",
			"nodes": [_node("a", "one"), _node("b", "two"), _node("c", "three")],
			"connections": [_wire("a", "b"), _wire("b", "c")],
			"sections": [],
		},
	}


static func _story(documents: Dictionary) -> Dictionary:
	return documents[STORY]


static func _find(documents: Dictionary, id: String) -> Dictionary:
	for node: Dictionary in _story(documents)["nodes"]:
		if node["id"] == id:
			return node
	return {}


static func _line(documents: Dictionary, id: String) -> String:
	var node: Dictionary = _find(documents, id)
	return str(node["line"]["en"]) if not node.is_empty() else "<gone>"


func test_a_change_on_disk_only_is_taken() -> void:
	var base: Dictionary = _base()
	var mine: Dictionary = _base()
	var theirs: Dictionary = _base()
	_find(theirs, "b")["line"]["en"] = "TWO"
	var merge: ProjectMerge = ProjectMerge.merge(base, mine, theirs)
	assert_str(_line(merge.documents, "b")).is_equal("TWO")
	assert_array(merge.conflicts).is_empty()
	assert_int(merge.changed).is_equal(1)
	assert_bool(merge.is_same_as(theirs)).is_true()


func test_a_change_in_the_editor_only_is_kept() -> void:
	var base: Dictionary = _base()
	var mine: Dictionary = _base()
	_find(mine, "a")["line"]["en"] = "ONE"
	var merge: ProjectMerge = ProjectMerge.merge(base, mine, _base())
	assert_str(_line(merge.documents, "a")).is_equal("ONE")
	assert_int(merge.changed).is_equal(0)
	assert_bool(merge.is_same_as(mine)).is_true()


func test_changes_to_different_nodes_both_land() -> void:
	var mine: Dictionary = _base()
	var theirs: Dictionary = _base()
	_find(mine, "a")["line"]["en"] = "ONE"
	_find(theirs, "c")["line"]["en"] = "THREE"
	var merge: ProjectMerge = ProjectMerge.merge(_base(), mine, theirs)
	assert_str(_line(merge.documents, "a")).is_equal("ONE")
	assert_str(_line(merge.documents, "c")).is_equal("THREE")
	assert_array(merge.conflicts).is_empty()
	assert_int(merge.changed).is_equal(1)


func test_different_fields_of_one_node_both_land() -> void:
	var mine: Dictionary = _base()
	var theirs: Dictionary = _base()
	_find(mine, "b")["editor_position"] = [100.0, 40.0]
	_find(theirs, "b")["line"]["en"] = "TWO"
	var merge: ProjectMerge = ProjectMerge.merge(_base(), mine, theirs)
	assert_str(_line(merge.documents, "b")).is_equal("TWO")
	assert_array(_find(merge.documents, "b")["editor_position"]).is_equal([100.0, 40.0])
	assert_array(merge.conflicts).is_empty()


func test_the_same_change_on_both_sides_is_no_conflict() -> void:
	var mine: Dictionary = _base()
	var theirs: Dictionary = _base()
	_find(mine, "b")["line"]["en"] = "TWO"
	_find(theirs, "b")["line"]["en"] = "TWO"
	var merge: ProjectMerge = ProjectMerge.merge(_base(), mine, theirs)
	assert_str(_line(merge.documents, "b")).is_equal("TWO")
	assert_array(merge.conflicts).is_empty()


func test_one_field_changed_two_ways_is_a_conflict_the_editor_wins() -> void:
	var mine: Dictionary = _base()
	var theirs: Dictionary = _base()
	_find(mine, "b")["line"]["en"] = "mine"
	_find(theirs, "b")["line"]["en"] = "theirs"
	_find(theirs, "c")["line"]["en"] = "THREE"
	var merge: ProjectMerge = ProjectMerge.merge(_base(), mine, theirs)
	assert_str(_line(merge.documents, "b")).is_equal("mine")
	assert_str(_line(merge.documents, "c")).is_equal("THREE")
	assert_int(merge.conflicts.size()).is_equal(1)
	assert_str(merge.conflicts[0]["id"]).is_equal("b")
	assert_str(merge.conflicts[0]["document"]).is_equal("Story")
	assert_str(merge.describe_conflicts()).contains("mine")


func test_a_conflict_can_go_to_the_disk_version() -> void:
	var mine: Dictionary = _base()
	var theirs: Dictionary = _base()
	_find(mine, "b")["line"]["en"] = "mine"
	_find(mine, "a")["line"]["en"] = "ONE"
	_find(theirs, "b")["line"]["en"] = "theirs"
	var merge: ProjectMerge = ProjectMerge.merge(_base(), mine, theirs, true)
	assert_str(_line(merge.documents, "b")).is_equal("theirs")
	assert_str(_line(merge.documents, "a")).is_equal("ONE")  # not a conflict: still mine
	assert_int(merge.conflicts.size()).is_equal(1)


func test_a_node_deleted_on_disk_goes_and_its_wires_are_rejoined_as_disk_says() -> void:
	var mine: Dictionary = _base()
	var theirs: Dictionary = _base()
	_find(mine, "a")["line"]["en"] = "ONE"
	_story(theirs)["nodes"] = [_node("a", "one"), _node("c", "three")]
	_story(theirs)["connections"] = [_wire("a", "c")]
	var merge: ProjectMerge = ProjectMerge.merge(_base(), mine, theirs)
	assert_str(_line(merge.documents, "b")).is_equal("<gone>")
	assert_str(_line(merge.documents, "a")).is_equal("ONE")
	assert_array(_story(merge.documents)["connections"]).is_equal([_wire("a", "c")])
	assert_array(merge.conflicts).is_empty()


func test_a_node_deleted_on_disk_but_edited_here_is_kept_as_a_conflict() -> void:
	var mine: Dictionary = _base()
	var theirs: Dictionary = _base()
	_find(mine, "b")["line"]["en"] = "kept"
	_story(theirs)["nodes"] = [_node("a", "one"), _node("c", "three")]
	_story(theirs)["connections"] = [_wire("a", "c")]
	var merge: ProjectMerge = ProjectMerge.merge(_base(), mine, theirs)
	assert_str(_line(merge.documents, "b")).is_equal("kept")
	assert_int(merge.conflicts.size()).is_equal(1)


func test_a_node_added_on_disk_arrives_wired_in_after_its_neighbour() -> void:
	var mine: Dictionary = _base()
	var theirs: Dictionary = _base()
	_find(mine, "c")["line"]["en"] = "THREE"
	_story(theirs)["nodes"].insert(2, _node("n", "new"))
	_story(theirs)["connections"] = [_wire("a", "b"), _wire("b", "n"), _wire("n", "c")]
	var merge: ProjectMerge = ProjectMerge.merge(_base(), mine, theirs)
	var ids: Array = (_story(merge.documents)["nodes"] as Array).map(func(n: Dictionary) -> String: return n["id"])
	assert_array(ids).is_equal(["a", "b", "n", "c"])
	assert_str(_line(merge.documents, "c")).is_equal("THREE")
	assert_array(_story(merge.documents)["connections"]).contains_exactly_in_any_order(
		[_wire("a", "b"), _wire("b", "n"), _wire("n", "c")]
	)
	assert_int(merge.changed).is_equal(2)  # n added, b rewired; c was already mine


func test_nodes_added_on_both_sides_are_all_there() -> void:
	var mine: Dictionary = _base()
	var theirs: Dictionary = _base()
	_story(mine)["nodes"].append(_node("m", "mine"))
	_story(mine)["connections"].append(_wire("c", "m"))
	_story(theirs)["nodes"].append(_node("t", "theirs"))
	_story(theirs)["connections"].append(_wire("a", "t"))
	var merge: ProjectMerge = ProjectMerge.merge(_base(), mine, theirs)
	assert_str(_line(merge.documents, "m")).is_equal("mine")
	assert_str(_line(merge.documents, "t")).is_equal("theirs")
	assert_int((_story(merge.documents)["connections"] as Array).size()).is_equal(4)


func test_a_wire_to_a_node_deleted_on_disk_does_not_dangle() -> void:
	var mine: Dictionary = _base()
	var theirs: Dictionary = _base()
	_story(mine)["connections"].append(_wire("a", "c"))
	_story(theirs)["nodes"] = [_node("a", "one"), _node("b", "two")]
	_story(theirs)["connections"] = [_wire("a", "b")]
	var merge: ProjectMerge = ProjectMerge.merge(_base(), mine, theirs)
	assert_array(_story(merge.documents)["connections"]).is_equal([_wire("a", "b")])


func test_characters_merge_record_by_record() -> void:
	var mine: Dictionary = _base()
	var theirs: Dictionary = _base()
	mine[PEOPLE]["characters"][0]["color"] = "#000000"
	theirs[PEOPLE]["characters"].append({"$type": "character", "id": "character-2", "name": "Bob", "color": "#ff0000"})
	var merge: ProjectMerge = ProjectMerge.merge(_base(), mine, theirs)
	var people: Array = merge.documents[PEOPLE]["characters"]
	assert_int(people.size()).is_equal(2)
	assert_str(people[0]["color"]).is_equal("#000000")
	assert_str(people[1]["name"]).is_equal("Bob")


func test_a_storyline_renamed_on_disk_is_the_same_storyline() -> void:
	var mine: Dictionary = _base()
	var theirs: Dictionary = _base()
	_find(mine, "a")["line"]["en"] = "ONE"
	var story: Dictionary = theirs[STORY]
	theirs.erase(STORY)
	story["name"] = "Renamed"
	theirs["storylines/Renamed.mnlf"] = story
	var merge: ProjectMerge = ProjectMerge.merge(_base(), mine, theirs)
	assert_bool(merge.documents.has(STORY)).is_false()
	assert_bool(merge.documents.has("storylines/Renamed.mnlf")).is_true()
	assert_str(str(merge.documents["storylines/Renamed.mnlf"]["nodes"][0]["line"]["en"])).is_equal("ONE")


func test_a_storyline_added_on_disk_arrives() -> void:
	var theirs: Dictionary = _base()
	theirs["storylines/New.mnlf"] = {"$type": "storyline", "id": "storyline-2", "name": "New", "nodes": [], "connections": [], "sections": []}
	var merge: ProjectMerge = ProjectMerge.merge(_base(), _base(), theirs)
	assert_bool(merge.documents.has("storylines/New.mnlf")).is_true()


func test_game_fields_of_an_add_on_merge_like_any_other() -> void:
	# fields an add-on defines (here: a skill check and its costs) are plain values to the merge
	var mine: Dictionary = _base()
	var theirs: Dictionary = _base()
	_find(mine, "a")["need"] = {"kultura": 15}
	_find(theirs, "a")["tint"] = "kultura"
	_find(theirs, "b")["cost"] = {"health": 10}
	var merge: ProjectMerge = ProjectMerge.merge(_base(), mine, theirs)
	assert_dict(_find(merge.documents, "a")["need"]).is_equal({"kultura": 15})
	assert_str(_find(merge.documents, "a")["tint"]).is_equal("kultura")
	assert_dict(_find(merge.documents, "b")["cost"]).is_equal({"health": 10})
	assert_array(merge.conflicts).is_empty()
