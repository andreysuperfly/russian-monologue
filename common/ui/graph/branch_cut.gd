class_name BranchCut
## Deleting an answer — or any list item with a wire of its own — and, if asked, the branch that
## runs on from it (russian-monologue). The branch is only the cards that nothing else reaches:
## a card another way still leads into stays, with everything after it, so no other path is
## broken. Before it goes, what matters in it is listed with links to those cards — what it
## remembers, gives, runs, records, what other places point at. One undo step for the lot.


## The cards the item's wire leads to and that only this wire reaches.
static func branch_of(storyline: StorylineDocument, owner: InspectableNode, property: String, item_id: String) -> Array[InspectableNode]:
	var reached: Dictionary = {}
	var queue: Array[String] = []
	for wire: NodeConnection in storyline.connections:
		if _is_item_wire(wire, owner, property, item_id):
			queue.append(wire.to_node_id)
	while not queue.is_empty():
		var id: String = queue.pop_front()
		if reached.has(id) or id == owner.get_id():
			continue
		reached[id] = true
		for wire: NodeConnection in storyline.connections:
			if wire.from_node_id == id:
				queue.append(wire.to_node_id)
	# take out every card something outside the branch leads into, until none is left
	var changed: bool = true
	while changed:
		changed = false
		for id: String in reached.keys():
			for wire: NodeConnection in storyline.connections:
				if wire.to_node_id != id or reached.has(wire.from_node_id) or _is_item_wire(wire, owner, property, item_id):
					continue
				reached.erase(id)
				changed = true
				break
	var nodes: Array[InspectableNode] = []
	for id: String in reached:
		var node: InspectableNode = storyline.get_node(id)
		if node and node.get_type() != "root":
			nodes.append(node)
	return nodes


static func _is_item_wire(wire: NodeConnection, owner: InspectableNode, property: String, item_id: String) -> bool:
	return wire.from_node_id == owner.get_id() and wire.from_property == property and wire.from_item_id == item_id


static func has_wire(storyline: StorylineDocument, owner: InspectableNode, property: String, item_id: String) -> bool:
	for wire: NodeConnection in storyline.connections:
		if _is_item_wire(wire, owner, property, item_id):
			return true
	return false


## A card in words: who says what, or its own title, or its kind.
static func name_of(node: InspectableNode) -> String:
	if node.get_type() == "sentence":
		var who: String = GraphNodeViewFactory._speaker_name(node)
		var said: String = NodePreview.trim(Util.to_label(node.get_property_value("line")), 50)
		if said.strip_edges().is_empty():  # a new, empty line: its kind, not «»
			return who if not who.is_empty() else TranslationServer.translate("A line")
		return ("%s: «%s»" % [who, said]) if not who.is_empty() else "«%s»" % said
	if node.has_method("card_title"):
		var own: String = str(node.call("card_title"))
		if not own.is_empty():
			return own
	var indexer: NodeIndexer = MonologueRegistry.get_instance().get_node(node.get_type())
	var kind: String = TranslationServer.translate(indexer.get_display_name()) if indexer else node.get_type()
	# what the card says on itself: «запомнить: дверь осмотрена»
	var preview: Control = node._build_preview("")
	if preview:
		var said: String = ""
		for label: Node in preview.find_children("*", "RichTextLabel", true, false) + ([preview] if preview is RichTextLabel else []):
			said += " " + (label as RichTextLabel).get_parsed_text()
		preview.free()
		said = said.strip_edges()
		if not said.is_empty():
			return "%s: %s" % [kind, NodePreview.trim(said, 50)]
	return kind


## What in [param nodes] would be missed: [[node, why]…].
static func important(nodes: Array[InspectableNode]) -> Array:
	var found: Array = []
	var project: MonologueProject = ProjectManager.current_project
	var going: Dictionary = {}
	for node: InspectableNode in nodes:
		going[node.get_id()] = true
	for node: InspectableNode in nodes:
		var why: PackedStringArray = PackedStringArray()
		match node.get_type():
			"variable":
				why.append(TranslationServer.translate("changes a variable"))
			"inventory":
				why.append(TranslationServer.translate("gives or takes an item"))
			"section":
				why.append(TranslationServer.translate("runs a section"))
			"action", "event":
				why.append(TranslationServer.translate("does something in the game"))
		for plugin: MonologuePlugin in MonologueRegistry.get_instance().get_installed_plugins():
			var note: String = plugin.important_note(node)
			if not note.is_empty():
				why.append(note)
		if project:
			var outside: int = 0
			for site: ReferenceSite in project.get_object_registry().get_referrers(node.get_id()):
				if not going.has(site.owner_id):
					outside += 1
			if outside > 0:
				why.append(TranslationServer.translate("%d other place(s) point at it") % outside)
		if not why.is_empty():
			found.append([node, ", ".join(why)])
	return found


## Asks what to delete: the item alone, or with its branch; [param delete_item] takes the item
## out the usual way. Returns false when there is no branch to ask about.
static func ask(anchor: Control, owner: InspectableNode, property: String, item_id: String, item_name: String, delete_item: Callable) -> bool:
	var project: MonologueProject = ProjectManager.current_project
	var storyline: StorylineDocument = project.get_storyline(owner.storyline_id) if project and not owner.storyline_id.is_empty() else null
	if storyline == null or not has_wire(storyline, owner, property, item_id):
		return false
	var branch: Array[InspectableNode] = branch_of(storyline, owner, property, item_id)
	if branch.is_empty():
		return false
	var notes: Array = important(branch)

	var popup: PopupPanel = PopupPanel.new()
	var frame: StyleBoxFlat = StyleBoxFlat.new()
	frame.bg_color = Color("#262626")
	frame.border_color = Color("#3a3a3a")
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(8)
	frame.set_content_margin_all(16)
	popup.add_theme_stylebox_override(&"panel", frame)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 12)
	column.custom_minimum_size.x = 440
	var heading: Label = Label.new()
	heading.text = TranslationServer.translate("Delete «%s»?") % NodePreview.trim(item_name, 60)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.custom_minimum_size.x = 440
	heading.add_theme_font_size_override(&"font_size", 17)
	column.add_child(heading)

	var text: RichTextLabel = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.custom_minimum_size.x = 440
	text.add_theme_font_size_override(&"normal_font_size", 14)
	text.add_theme_color_override(&"default_color", Color("#b8b8b8"))
	var words: String = TranslationServer.translate("After it come %d card(s) nothing else leads to. Cards another way still reaches stay.") % branch.size()
	if not notes.is_empty():
		words += "\n\n[color=#e0a06a]%s[/color]" % TranslationServer.translate("What matters in that branch — click to look:")
		for note: Array in notes:
			var node: InspectableNode = note[0]
			words += "\n• [url=%s]%s[/url] — %s" % [node.get_id(), NodePreview.plain(name_of(node)), note[1]]
	text.text = words
	text.meta_clicked.connect(func(meta: Variant) -> void:
		var node: InspectableNode = storyline.get_node(str(meta))
		if node:
			MonologueGraphEdit.reveal(node))
	column.add_child(text)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var cancel: Button = CardTags._button(TranslationServer.translate("Cancel"), false)
	cancel.pressed.connect(popup.hide)
	var only: Button = CardTags._button(TranslationServer.translate("Only the answer"), false)
	only.pressed.connect(func() -> void:
		popup.hide()
		delete_item.call())
	var all: Button = CardTags._button(TranslationServer.translate("With the branch (%d)") % branch.size(), true)
	all.pressed.connect(func() -> void:
		popup.hide()
		delete_with_branch(storyline, owner, property, item_id, branch))
	for button: Button in [cancel, only, all]:
		button.custom_minimum_size.x = 0
		buttons.add_child(button)
	column.add_child(buttons)
	popup.add_child(column)
	popup.popup_hide.connect(popup.queue_free)
	anchor.get_tree().root.add_child(popup)
	popup.popup_centered()
	(func() -> void:
		if is_instance_valid(popup):
			popup.size = Vector2i(popup.get_contents_minimum_size())
			popup.move_to_center()).call_deferred()
	return true


## The item and its branch, in one undo step.
static func delete_with_branch(storyline: StorylineDocument, owner: InspectableNode, property: String, item_id: String, branch: Array[InspectableNode]) -> void:
	var old_list: Variant = owner.get_property_value(property)
	if not old_list is Array:
		return
	var new_list: Array = (old_list as Array).duplicate(true).filter(func(item: Variant) -> bool:
		return not (item is Dictionary and str((item as Dictionary).get("id", "")) == item_id))
	var step: CommandTransaction = storyline.history.begin("Delete an answer and its branch")
	storyline.history.execute(PropertyChangeCommand.new(owner, property, old_list, new_list))
	storyline.history.execute(DeleteNodesCommand.new(storyline.id, branch, DeleteNodesCommand.sections_run_by(branch)))
	step.commit()
	var graph: MonologueGraphEdit = (Engine.get_main_loop() as SceneTree).get_first_node_in_group(&"monologue_graph") as MonologueGraphEdit
	if graph:
		graph.refresh()
