## The single entry point for adding types to Monologue. A plugin registers indexers and
## nothing else:
## [codeblock]
## class_name MyPlugin extends MonologuePlugin
##
## func get_plugin_name() -> String:
##     return "my.plugin"
##
## func register(registry: MonologueRegistry) -> void:
##     registry.register(preload("res://my_plugin/duration/index.gd").new())
## [/codeblock]
@abstract
class_name MonologuePlugin extends RefCounted

## Stable identifier, conventionally "vendor.name". Tags every type this plugin registers,
## so uninstalling removes them all.
@abstract func get_plugin_name() -> String


func get_plugin_version() -> String:
	return "1.0.0"


## Called once on install.
@abstract func register(registry: MonologueRegistry) -> void


## What [param object] reads and writes through this add-on's own fields, as Monologue record ids:
## {"reads": [...], "writes": [...]}. The Problems window counts these too, so a variable an
## add-on field changes is not reported as never changed (russian-monologue).
func usage(_object: InspectableObject) -> Dictionary:
	return {}


## Each place in [param object] where this add-on's fields use the record [param target_id],
## in words, for «Where used»: [{"said": the option's or line's text ("" for the object itself),
## "what": what it does there, "reads": true when it needs or checks rather than changes}]
## (russian-monologue). Empty: the generic «needs or checks» / «changes» from [method usage].
func usage_places(_object: InspectableObject, _target_id: String) -> Array:
	return []


## A line of explanation for [param node]'s card, in plain words, shown under its rows when the
## node draws no preview of its own (russian-monologue). "" for none.
func card_note(_node: InspectableNode) -> String:
	return ""


## Tags under [param node]'s text: what decides whether it happens, each editable with a click
## (russian-monologue). The shape is in [CardTags]. Empty: no tags.
func card_tags(_node: InspectableNode) -> Array:
	return []


## Conditions that can be added to [param node]: [{"text", "tag"}], see [CardTags].
func card_tag_offers(_node: InspectableNode) -> Array:
	return []


## Tags under one item of [param node]'s list [param property] — an answer of a choice —
## given as its stored [param item]. Their keys are the item's keys. See [CardTags].
func card_item_tags(_node: InspectableNode, _property: String, _item: Dictionary) -> Array:
	return []


## Conditions that can be added to that item: [{"text", "tag"}].
func card_item_tag_offers(_node: InspectableNode, _property: String, _item: Dictionary) -> Array:
	return []


## Called on uninstall. Types registered through [param registry] are removed automatically.
## Override only for extra teardown.
func unregister(_registry: MonologueRegistry) -> void:
	pass
