extends FieldIndexer


func _init() -> void:
	name = "condition"
	display_name = "Condition"
	description = "Compares a project variable against a value."
	color = MonologuePalette.LOGIC
	scene_uid = "uid://b6bfebqeejpsg"
	default_value = {"join": "and", "checks": []}


## A condition points at a variable, so it must be visible to the reverse
## reference index even though its value is a Dictionary rather than a plain id.
func extract_references(value: Variant) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for check: Dictionary in MonologueCondition.checks_of(value):
		for key: String in ["variable", "node", "who", "item"]:
			var id: String = str(check.get(key, ""))
			if not id.is_empty() and not ids.has(id):
				ids.append(id)
	return ids
