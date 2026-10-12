extends GutTest
## Keeps every translation CSV under res://translations/ readable the
## way the game reads it. See TranslationCsvChecker for the checks.
##
## The first group checks the committed files. The second feeds the
## checker small broken files, so a checker that stopped finding
## anything would fail here instead of passing every real file.


const _LOCALE_FILTER_SETTING := "internationalization/locale/locale_filter"
const _TRANSLATIONS_SETTING := "internationalization/locale/translations"
const _COMPILED_TABLE_PATH_FORMAT := (
	"res://translations/ui_translations.%s.translation")
const _FIXTURE_DIR := "user://translation_csv_checker_fixtures"
## Locales for the hand-written tables below: one per writing-system
## family the heuristic treats differently.
const _FIXTURE_LOCALES := ["en", "ru", "ja", "zh", "ko", "de"]
const _FIXTURE_HEADER := "keys,en,ru,ja,zh,ko,de"
const _GOOD_ROW := (
	"GREETING,Hello there,Привет,こんにちは,你好,안녕하세요,Hallo")
const _QUOTED_COMMA_ROW := (
	"HINT,\"Invite a friend, then play.\","
	+ "\"Пригласите друга, затем играйте.\","
	+ "フレンドを招待して遊ぼう。,邀请好友，然后开始游戏。,"
	+ "친구를 초대하고 플레이하세요.,"
	+ "\"Lade einen Freund ein, dann spiele.\"")
const _BRAND_ROW := "AUTH.GOOGLE,Google,Google,Google,Google,Google,Google"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(_FIXTURE_DIR)


func after_each() -> void:
	for file_name in DirAccess.get_files_at(_FIXTURE_DIR):
		DirAccess.remove_absolute(_FIXTURE_DIR.path_join(file_name))
	DirAccess.remove_absolute(_FIXTURE_DIR)


# ------------------------------------------------------------------
# The committed files
# ------------------------------------------------------------------


func test_ui_table_is_sound() -> void:
	var problems := TranslationCsvChecker.check_ui_table(
		TranslationCsvChecker.UI_TABLE_PATH,
		_get_supported_locales(),
	)
	assert_true(problems.is_empty(), "\n".join(problems))


func test_adjective_lists_are_sound() -> void:
	var paths := _find_lists(TranslationCsvChecker.ADJECTIVES_DIR)
	assert_gt(paths.size(), 0, "no adjective lists found")
	var problems: Array[String] = []
	for path in paths:
		problems.append_array(TranslationCsvChecker.check_adjectives(
			path,
			TranslationCsvChecker.get_list_locale(path),
			_get_adjective_categories(),
		))
	assert_true(problems.is_empty(), "\n".join(problems))


func test_name_lists_are_sound() -> void:
	var paths := _find_lists(TranslationCsvChecker.NAMES_DIR)
	assert_gt(paths.size(), 0, "no name lists found")
	var problems: Array[String] = []
	for path in paths:
		problems.append_array(TranslationCsvChecker.check_names(
			path, TranslationCsvChecker.get_list_locale(path)))
	assert_true(problems.is_empty(), "\n".join(problems))


## A CSV the checker does not know would go unchecked, so it fails
## until the checker learns its format.
func test_every_translation_csv_is_checked() -> void:
	var unchecked: Array[String] = []
	var paths := TranslationCsvChecker.find_csv_files(
		TranslationCsvChecker.TRANSLATIONS_DIR)
	assert_gt(paths.size(), 0, "no CSV files found")
	for path in paths:
		if path == TranslationCsvChecker.UI_TABLE_PATH:
			continue
		if TranslationCsvChecker.get_list_locale(path).is_empty():
			unchecked.append(path)
	assert_true(
		unchecked.is_empty(),
		"TranslationCsvChecker has no check for: %s" % ", ".join(unchecked),
	)


## The game reads the compiled tables that project.godot lists, not
## the CSV. Every supported locale needs one, and each must say what
## the CSV says.
func test_compiled_translations_match_the_table() -> void:
	var records := TranslationCsvChecker.read_csv_records(
		TranslationCsvChecker.UI_TABLE_PATH)
	assert_gt(records.size(), 1, "the UI table has no rows")
	var header := records[0]
	var listed: PackedStringArray = ProjectSettings.get_setting(
		_TRANSLATIONS_SETTING, PackedStringArray())
	var mismatches: Array[String] = []
	for column in range(1, header.size()):
		var locale := header[column]
		var path := _COMPILED_TABLE_PATH_FORMAT % locale
		if not listed.has(path):
			mismatches.append("%s is not in %s" % [path, _TRANSLATIONS_SETTING])
			continue
		var translation: Translation = load(path)
		if translation == null:
			mismatches.append("cannot load %s" % path)
			continue
		for row in range(1, records.size()):
			var cells := records[row]
			if cells.size() != header.size():
				# test_ui_table_is_sound reports it.
				continue
			var expected := cells[column].c_unescape()
			var actual := String(translation.get_message(cells[0]))
			if actual != expected:
				mismatches.append("%s [%s]: compiled %s, CSV %s" % [
					cells[0],
					locale,
					JSON.stringify(actual),
					JSON.stringify(expected),
				])
	assert_true(
		mismatches.is_empty(),
		"Re-import the project (godot --headless --import) and commit the"
		+ " .translation files:\n" + "\n".join(mismatches),
	)


# ------------------------------------------------------------------
# The checker on broken tables
# ------------------------------------------------------------------


func test_checker_passes_a_sound_table() -> void:
	var problems := _check_table([_GOOD_ROW, _QUOTED_COMMA_ROW, _BRAND_ROW])

	assert_true(problems.is_empty(), "\n".join(problems))


## The bug this file exists for: an unquoted comma splits its cell,
## and every cell after it moves one locale right.
func test_checker_flags_an_unquoted_comma() -> void:
	var problems := _check_table([
		_GOOD_ROW,
		_QUOTED_COMMA_ROW.replace("\"", ""),
	])

	assert_eq(problems.size(), 1, "\n".join(problems))
	assert_string_contains(problems[0], "\"HINT\"")
	assert_string_contains(problems[0], "10 cells, but the header has 7")


## The parser reads past the line with the open quote, so the rows
## after it vanish into one cell.
func test_checker_flags_an_unbalanced_quote() -> void:
	var problems := _check_table([
		"HINT,\"Invite a friend,Привет,こんにちは,你好,안녕하세요,Hallo",
		_GOOD_ROW,
		_BRAND_ROW,
	])

	assert_eq(problems.size(), 1, "\n".join(problems))
	assert_string_contains(problems[0], "a quote is unbalanced")
	assert_engine_error("Reached end of file before closing")


func test_checker_flags_another_scripts_text() -> void:
	var problems := _check_table([
		"GREETING,Hello there,Привет,Привет,こんにちは,안녕하세요,こんにちは",
	])

	assert_eq(problems.size(), 3, "\n".join(problems))
	assert_string_contains(problems[0], "[ja]: letters of CYRILLIC")
	assert_string_contains(problems[1], "[zh]: letters of KANA")
	assert_string_contains(problems[2], "[de]: letters of KANA")


func test_checker_flags_latin_text_in_a_non_latin_column() -> void:
	var problems := _check_table([
		"GREETING,Hello there,Привет,こんにちは,你好,Hallo zusammen,Hallo",
		_BRAND_ROW,
	])

	assert_eq(problems.size(), 1, "\n".join(problems))
	assert_string_contains(problems[0], "[ko]: Latin letters")


func test_checker_flags_mismatched_placeholders() -> void:
	var problems := _check_table([
		"LIMIT,%d of %d,%d из %d,%d / %d,%d / %d,%d / %d,%d",
	])

	assert_eq(problems.size(), 1, "\n".join(problems))
	assert_string_contains(problems[0], "[de]: placeholders")


func test_checker_flags_an_empty_cell_and_a_duplicate_key() -> void:
	var problems := _check_table([
		_GOOD_ROW,
		_GOOD_ROW.replace("Hallo", ""),
	])

	assert_eq(problems.size(), 2, "\n".join(problems))
	assert_string_contains(problems[0], "duplicate key")
	assert_string_contains(problems[1], "[de]: empty")


func test_checker_flags_missing_and_unknown_locale_columns() -> void:
	var path := _write_fixture(
		"locales.csv",
		"keys,en,xx\nGREETING,Hello,Hello\n",
	)

	var problems := TranslationCsvChecker.check_ui_table(
		path, PackedStringArray(["en", "fr"]))

	var text := "\n".join(problems)
	assert_string_contains(text, "no writing system is known for \"xx\"")
	assert_string_contains(text, "a column for xx, which the game")
	assert_string_contains(text, "no column for fr")


func test_adjective_checker_flags_bad_lines() -> void:
	var path := _write_fixture(
		"adjectives_de.csv",
		(
			"category,adjective\n"
			+ "soft,Flauschig\n"
			+ "soft,Groß, stark\n"
			+ "soft,\"Weich\"\n"
			+ "fluffy,Weich\n"
			+ "hard,ふわふわ\n"
		),
	)

	var problems := TranslationCsvChecker.check_adjectives(
		path, "de", PackedStringArray(["soft", "hard"]))

	assert_eq(problems.size(), 4, "\n".join(problems))
	assert_string_contains(problems[0], "line 3: 2 commas")
	assert_string_contains(problems[1], "line 4: a quote")
	assert_string_contains(problems[2], "line 5: unknown category")
	assert_string_contains(problems[3], "line 6: letters of KANA")


func test_adjective_checker_flags_latin_in_a_non_latin_list() -> void:
	var path := _write_fixture(
		"adjectives_ja.csv",
		"category,adjective\nsoft,ふわふわ\nsoft,堂々たる\nsoft,Fluffy\n",
	)

	var problems := TranslationCsvChecker.check_adjectives(
		path, "ja", PackedStringArray(["soft"]))

	assert_eq(problems.size(), 1, "\n".join(problems))
	assert_string_contains(problems[0], "line 4: Latin letters")


func test_name_checker_flags_bad_lines() -> void:
	var path := _write_fixture(
		"names_ru.csv",
		"Пушок\nИван, Петров\nFluffy\n",
	)

	var problems := TranslationCsvChecker.check_names(path, "ru")

	assert_eq(problems.size(), 2, "\n".join(problems))
	assert_string_contains(problems[0], "line 2: a comma or quote")
	assert_string_contains(problems[1], "line 3: Latin letters")


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------


func _get_supported_locales() -> PackedStringArray:
	return PackedStringArray(
		ProjectSettings.get_setting(_LOCALE_FILTER_SETTING, []))


## The category names LocalizedNameConfig looks up, one per adjective
## list.
func _get_adjective_categories() -> PackedStringArray:
	var categories := PackedStringArray()
	for list_id: int in DynamicAdjectiveConfig.AdjectiveListType.values():
		categories.append(LocalizedNameConfig._list_id_to_category(list_id))
	return categories


func _find_lists(dir: String) -> PackedStringArray:
	var paths := PackedStringArray()
	for path in TranslationCsvChecker.find_csv_files(dir):
		if not TranslationCsvChecker.get_list_locale(path).is_empty():
			paths.append(path)
	return paths


func _check_table(rows: Array) -> Array[String]:
	var path := _write_fixture(
		"table.csv",
		_FIXTURE_HEADER + "\n" + "\n".join(PackedStringArray(rows)) + "\n",
	)
	return TranslationCsvChecker.check_ui_table(
		path, PackedStringArray(_FIXTURE_LOCALES))


func _write_fixture(file_name: String, text: String) -> String:
	var path := _FIXTURE_DIR.path_join(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path
