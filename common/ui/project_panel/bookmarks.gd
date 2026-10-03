## The writer's own collections (russian-monologue): nested folders of storylines and nodes, kept in
## the project settings under "bookmarks". Every change goes through the settings property, so it
## is saved with the project and can be undone.
class_name Bookmarks

const SETTING: String = "bookmarks"
const ID_CHARS: String = "0123456789abcdefghijklmnopqrstuvwxyz"


static func tree() -> Array:
	var project: MonologueProject = ProjectManager.current_project
	if not project or not project.settings:
		return []
	var val: Variant = project.settings.get_property_value(SETTING)
	if val is Array:
		return (val as Array).duplicate(true)
	return []


static func add_folder(parent_id: String, name: String) -> String:
	var data: Array = tree()
	var new_id: String = _generate_folder_id()
	var new_folder: Dictionary = {
		"id": new_id,
		"name": name,
		"open": true,
		"folders": [],
		"items": []
	}
	if parent_id.is_empty():
		data.append(new_folder)
	else:
		var target: Dictionary = _find_folder_recursive(data, parent_id)
		if target.is_empty():
			return ""
		if not target.has("folders") or target["folders"] is not Array:
			target["folders"] = []
		(target["folders"] as Array).append(new_folder)
	_save(data)
	return new_id


static func rename_folder(id: String, name: String) -> void:
	var data: Array = tree()
	var target: Dictionary = _find_folder_recursive(data, id)
	if target.is_empty():
		return
	target["name"] = name
	_save(data)


static func delete_folder(id: String) -> void:
	var data: Array = tree()
	if _remove_folder_recursive(data, id):
		_save(data)


static func set_open(id: String, is_open: bool) -> void:
	var data: Array = tree()
	var target: Dictionary = _find_folder_recursive(data, id)
	if target.is_empty():
		return
	target["open"] = is_open
	_save_quietly(data)


static func add_item(folder_id: String, item: Dictionary) -> void:
	var data: Array = tree()
	var target: Dictionary = _find_folder_recursive(data, folder_id)
	if target.is_empty():
		return
	if not target.has("items") or target["items"] is not Array:
		target["items"] = []
	var items: Array = target["items"]
	for existing: Variant in items:
		if existing is Dictionary and _items_match(existing, item):
			return
	items.append(item.duplicate(true))
	_save(data)


static func remove_item(folder_id: String, index: int) -> void:
	var data: Array = tree()
	var target: Dictionary = _find_folder_recursive(data, folder_id)
	if target.is_empty():
		return
	var items: Array = target.get("items", [])
	if index >= 0 and index < items.size():
		items.remove_at(index)
		_save(data)


static func move_folder(id: String, new_parent_id: String) -> void:
	if id.is_empty() or id == new_parent_id:
		return
	var data: Array = tree()
	var folder_to_move: Dictionary = _find_folder_recursive(data, id)
	if folder_to_move.is_empty():
		return
	if not new_parent_id.is_empty() and _is_descendant(folder_to_move, new_parent_id):
		return
	_remove_folder_recursive(data, id)
	if new_parent_id.is_empty():
		data.append(folder_to_move)
	else:
		var new_parent: Dictionary = _find_folder_recursive(data, new_parent_id)
		if new_parent.is_empty():
			return
		if not new_parent.has("folders") or new_parent["folders"] is not Array:
			new_parent["folders"] = []
		(new_parent["folders"] as Array).append(folder_to_move)
	_save(data)


static func find_folder(id: String) -> Dictionary:
	return _find_folder_recursive(tree(), id)


static func forget_storyline(storyline_id: String) -> void:
	if storyline_id.is_empty():
		return
	var data: Array = tree()
	if _forget_storyline_recursive(data, storyline_id):
		_save(data)


static func folder_paths() -> Array:
	var result: Array = []
	_collect_folder_paths(tree(), "", result)
	return result


static func _save(tree_data: Array) -> void:
	var project: MonologueProject = ProjectManager.current_project
	if not project or not project.settings:
		return
	var prop: Property = project.settings.get_property(SETTING)
	if prop == null:
		prop = project.settings.define_property(
			Property.new(SETTING)
			.set_type("any")
			.default([])
			.hidden_in_inspector()
		)
	# through the settings' history, so Cmd+Z takes it back; the panel hears it either way
	project.settings.set_property_value(SETTING, tree_data.duplicate(true))
	EventBus.bookmarks_changed.emit()


## For what is not worth an undo step, such as a folder folded or unfolded.
static func _save_quietly(tree_data: Array) -> void:
	var project: MonologueProject = ProjectManager.current_project
	if project and project.settings and project.settings.get_property(SETTING):
		project.settings.get_property(SETTING).set_value(tree_data.duplicate(true))


static func _find_folder_recursive(folders: Array, target_id: String) -> Dictionary:
	for f: Variant in folders:
		if f is Dictionary:
			if str(f.get("id", "")) == target_id:
				return f
			var found: Dictionary = _find_folder_recursive(f.get("folders", []), target_id)
			if not found.is_empty():
				return found
	return {}


static func _remove_folder_recursive(folders: Array, target_id: String) -> bool:
	for i in range(folders.size()):
		var entry: Variant = folders[i]
		if entry is Dictionary:
			if str(entry.get("id", "")) == target_id:
				folders.remove_at(i)
				return true
			if _remove_folder_recursive(entry.get("folders", []), target_id):
				return true
	return false


static func _is_descendant(parent_folder: Dictionary, target_id: String) -> bool:
	for child: Variant in parent_folder.get("folders", []):
		if child is Dictionary:
			if str(child.get("id", "")) == target_id:
				return true
			if _is_descendant(child, target_id):
				return true
	return false


static func _items_match(a: Dictionary, b: Dictionary) -> bool:
	var kind_a: String = str(a.get("kind", ""))
	var kind_b: String = str(b.get("kind", ""))
	if kind_a != kind_b:
		return false
	if kind_a == "storyline":
		return str(a.get("storyline", "")) == str(b.get("storyline", ""))
	if kind_a == "node":
		return (
			str(a.get("storyline", "")) == str(b.get("storyline", ""))
			and str(a.get("node", "")) == str(b.get("node", ""))
		)
	return a == b


static func _forget_storyline_recursive(folders: Array, storyline_id: String) -> bool:
	var changed: bool = false
	for f: Variant in folders:
		if f is Dictionary:
			var items: Array = f.get("items", [])
			var i: int = items.size() - 1
			while i >= 0:
				var item: Variant = items[i]
				if item is Dictionary and str(item.get("storyline", "")) == storyline_id:
					items.remove_at(i)
					changed = true
				i -= 1
			if _forget_storyline_recursive(f.get("folders", []), storyline_id):
				changed = true
	return changed


static func _collect_folder_paths(folders: Array, prefix: String, result: Array) -> void:
	for f: Variant in folders:
		if f is Dictionary:
			var fid: String = str(f.get("id", ""))
			var fname: String = str(f.get("name", ""))
			var full_path: String = (prefix + " · " + fname) if not prefix.is_empty() else fname
			result.append([fid, full_path])
			_collect_folder_paths(f.get("folders", []), full_path, result)


static func _generate_folder_id() -> String:
	var suffix: String = ""
	for _i in range(8):
		suffix += ID_CHARS[randi() % ID_CHARS.length()]
	return "folder-" + suffix
