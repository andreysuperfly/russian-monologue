extends GdUnitTestSuite

## i18n/ru.csv is written by i18n/make_ru.py and read by Godot as the Russian interface. A key
## Godot sees twice, an empty translation or a lost "%s" shows up only on screen, so it is
## checked here.

const TABLE: String = "res://i18n/ru.csv"
## Cyrillic in a string literal is allowed only here: language names written in their own
## language, the writer's TODO mark, and the ё → е folding of the search.
const ALLOWED_CYRILLIC: Array[String] = ["Русский", "ДОДЕЛАТЬ", "ё", "е"]
const SKIPPED_DIRS: Array[String] = [".godot", "addons/gdUnit4", "unit", "i18n", "reports"]

var _locale: String


func before() -> void:
	_locale = TranslationServer.get_locale()


func after() -> void:
	TranslationServer.set_locale(_locale)


func _rows() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var file: FileAccess = FileAccess.open(TABLE, FileAccess.READ)
	assert_object(file).override_failure_message("%s cannot be opened." % TABLE).is_not_null()
	if file == null:
		return rows
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() == 1 and row[0].is_empty():
			continue
		rows.append(row)
	return rows


static func _specifiers(text: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var regex: RegEx = RegEx.create_from_string("%[-+0-9.]*[sdif]")
	for m: RegExMatch in regex.search_all(text):
		found.append(m.get_string())
	return found


func test_the_table_has_a_header_and_two_columns() -> void:
	var rows: Array[PackedStringArray] = _rows()
	assert_int(rows.size()).is_greater(100)
	assert_array(Array(rows[0])).is_equal(["keys", "ru"])
	for row: PackedStringArray in rows:
		assert_int(row.size()).override_failure_message("Row %s has %d columns." % [row, row.size()]).is_equal(2)


func test_no_key_is_empty_or_repeated() -> void:
	var seen: Dictionary = {}
	for row: PackedStringArray in _rows().slice(1):
		assert_str(row[0].strip_edges()).override_failure_message("A row has no English key.").is_not_empty()
		assert_bool(seen.has(row[0])).override_failure_message("Key repeated: %s" % row[0]).is_false()
		seen[row[0]] = true


func test_no_translation_is_empty() -> void:
	for row: PackedStringArray in _rows().slice(1):
		assert_str(row[1].strip_edges()).override_failure_message("No Russian for: %s" % row[0]).is_not_empty()


func test_every_translation_keeps_the_placeholders() -> void:
	for row: PackedStringArray in _rows().slice(1):
		var key: String = row[0]
		var value: String = row[1]
		if key.contains("|"):
			# plural: each form carries what the first English one does
			for form: String in value.split("|"):
				assert_array(Array(_specifiers(form))).override_failure_message(
					"«%s» lost a placeholder of %s" % [form, key]
				).is_equal(Array(_specifiers(key.get_slice("|", 0))))
			continue
		assert_array(Array(_specifiers(value))).override_failure_message(
			"«%s» does not carry the placeholders of «%s»" % [value, key]
		).is_equal(Array(_specifiers(key)))


func test_the_imported_translation_is_the_one_in_use() -> void:
	TranslationServer.set_locale("ru")
	assert_str(TranslationServer.translate("File")).is_equal("Файл")
	assert_str(TranslationServer.translate("Interface")).is_equal("Интерфейс")
	TranslationServer.set_locale("en")
	assert_str(TranslationServer.translate("File")).is_equal("File")


func test_no_russian_is_written_into_the_interface_code() -> void:
	var quoted: RegEx = RegEx.create_from_string("\"([^\"]*[А-Яа-яЁё][^\"]*)\"")
	var found: PackedStringArray = []
	for path: String in _sources("res://"):
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for index: int in lines.size():
			if lines[index].strip_edges().begins_with("#"):
				continue
			for m: RegExMatch in quoted.search_all(lines[index]):
				if not ALLOWED_CYRILLIC.has(m.get_string(1)):
					found.append("%s:%d %s" % [path, index + 1, m.get_string(1)])
	assert_array(Array(found)).override_failure_message(
		"Russian in the code, not in i18n/make_ru.py:\n%s" % "\n".join(found)
	).is_empty()


static func _sources(dir_path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for dir_name: String in DirAccess.get_directories_at(dir_path):
		var child: String = dir_path.path_join(dir_name)
		if SKIPPED_DIRS.has(child.trim_prefix("res://")) or dir_name.begins_with("."):
			continue
		found.append_array(_sources(child))
	for file_name: String in DirAccess.get_files_at(dir_path):
		if file_name.get_extension() in ["gd", "tscn"]:
			found.append(dir_path.path_join(file_name))
	return found
