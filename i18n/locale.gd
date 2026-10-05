class_name InterfaceLocale extends Node
## Interface language (russian-monologue): English is the source text, other languages come from
## i18n/<lang>.csv. Chosen in Preferences → "Interface language" or in the header's language
## list; "System" follows the OS.

const SYSTEM: String = "System"
const CHOICES: Dictionary = {"English": "en", "Русский": "ru"}


func _ready() -> void:
	apply(str(ConfigManager.get_config("language", SYSTEM)))


static func apply(choice: String) -> void:
	TranslationServer.set_locale(code_of(choice))


## The locale a choice from Preferences stands for; "System" and anything unknown follow the OS.
static func code_of(choice: String) -> String:
	var code: String = CHOICES.get(choice, "")
	if code.is_empty():
		code = "ru" if OS.get_locale_language() == "ru" else "en"
	return code


## The interface language on screen right now, as its choice name ("English", "Русский").
static func current_choice() -> String:
	var language: String = TranslationServer.get_locale().get_slice("_", 0)
	for choice: String in CHOICES:
		if CHOICES[choice] == language:
			return choice
	return "English"


## Switches the interface and remembers it, the same as picking it in Preferences.
static func choose(choice: String) -> void:
	if not CHOICES.has(choice):
		return
	if ConfigManager.current_configuration:
		ConfigManager.set_config("language", choice)
	# set_config already applies it; this covers a missing configuration and an unchanged value
	apply(choice)


## "3 errors" / «3 ошибки». [param key] holds the forms split by "|": English has two
## ("%d error|%d errors"), its Russian translation three («%d ошибка|%d ошибки|%d ошибок»).
static func plural(key: String, count: int) -> String:
	var forms: PackedStringArray = TranslationServer.translate(key).split("|")
	var form: String = forms[0]
	if forms.size() >= 3:
		var tens: int = absi(count) % 100
		var ones: int = tens % 10
		if tens > 10 and tens < 20:
			form = forms[2]
		elif ones == 1:
			form = forms[0]
		elif ones > 1 and ones < 5:
			form = forms[1]
		else:
			form = forms[2]
	elif forms.size() == 2 and absi(count) != 1:
		form = forms[1]
	return form % count if form.contains("%d") else form
