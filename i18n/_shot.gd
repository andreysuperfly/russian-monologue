extends Node
func _ready() -> void:
	await get_tree().create_timer(6.0).timeout
	EventBus.load_project.emit("/private/tmp/claude-501/-Users-superfly-Desktop-GeniusInsaint-petersburg/913c90c9-c49a-4dea-b8be-4ce70dbf84fe/scratchpad/uxgodot/dialogues.mnlp")
	await get_tree().create_timer(8.0).timeout
	var p := ProjectManager.current_project
	var pw = ProblemsWindow.new()
	for v in p.get_collection_value("variables"):
		if str(v.get("name","")) in ["ПОНЯТИЯ","КУЛЬТУРА","ДЕТЕКТИВНОСТЬ","ДЕНЬГИ","code_known"]:
			var sites = p.get_object_registry().get_referrers(str(v["id"]))
			var extra = pw._addon_sites(p, str(v["id"]))
			print("USES ", v["name"], " refs=", sites.size(), " addon=", extra.size())
	pw.free()
	get_tree().quit()
