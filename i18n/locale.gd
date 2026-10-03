extends Node
## Interface language (russian-monologue): English is the source text, other languages come from
## i18n/<lang>.csv. Chosen in Preferences → "Interface language"; "System" follows the OS.

const SYSTEM: String = "System"
const CHOICES: Dictionary = {"English": "en", "Русский": "ru"}


func _ready() -> void:
	apply(str(ConfigManager.get_config("language", SYSTEM)))


static func apply(choice: String) -> void:
	var code: String = CHOICES.get(choice, "")
	if code.is_empty():
		code = "ru" if OS.get_locale_language() == "ru" else "en"
	TranslationServer.set_locale(code)
