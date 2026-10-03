@abstract class_name ProjectTemplate extends RefCounted

@abstract func setup_collection(project: MonologueProject) -> void
@abstract func setup_default_storyline(storyline: StorylineDocument) -> void


## The language a new project's lines are written in: the interface's (russian-monologue), so a
## Russian editor starts a Russian story. {code: name}.
static func interface_language() -> Dictionary:
	return {"ru": "Русский"} if TranslationServer.get_locale().begins_with("ru") else {"en": "English"}
