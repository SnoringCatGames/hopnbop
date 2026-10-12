class_name TranslationCsvChecker
extends RefCounted
## Finds corruption in the translation CSVs under res://translations/.
##
## Godot's CSV translation importer assigns cells to locales by
## position. A cell with an unquoted comma splits in two, and every
## later cell in its row moves one locale to the right: Japanese
## players saw half a Russian sentence for PARTY.EMPTY_STATE_HINT. An
## unbalanced quote is worse, because the parser then reads on into
## the following lines and merges them into one record.
##
## Each check returns its problems, one line each, and an empty list
## when the file is sound. The UI table is parsed with
## FileAccess.get_csv_line, the parser the importer itself uses. The
## adjective and name lists are read by LocalizedNameConfig, which
## splits a line at its first comma and knows nothing of quotes, so
## they may hold neither quotes nor extra commas.
##
## The writing-system checks are a heuristic. A cell must not contain
## letters of a script that its locale does not use: Cyrillic in the
## Japanese column, kana in the Chinese one, or anything but Latin in
## a Latin-script column. In a column whose locale does not write in
## Latin letters, a cell with Latin letters and none of the locale's
## own must equal the English cell, which allows brand names such as
## "Google". A shift between two Latin-script columns needs the
## column-count and placeholder checks to catch it.

enum WritingSystem {
	NONE,
	LATIN,
	GREEK,
	CYRILLIC,
	ARABIC,
	DEVANAGARI,
	THAI,
	HANGUL,
	KANA,
	HAN,
}

const TRANSLATIONS_DIR := "res://translations"
const UI_TABLE_PATH := "res://translations/ui_translations.csv"
const UI_TABLE_KEY_HEADER := "keys"
const ADJECTIVES_DIR := "res://translations/adjectives"
const ADJECTIVES_FILE_PREFIX := "adjectives_"
const ADJECTIVES_HEADER := "category,adjective"
const NAMES_DIR := "res://translations/names"
const NAMES_FILE_PREFIX := "names_"
const CSV_EXTENSION := ".csv"
const ENGLISH := "en"

## The writing systems each supported locale writes in. A locale that
## is missing here fails the checks until someone adds it.
const LOCALE_WRITING_SYSTEMS := {
	"en": [WritingSystem.LATIN],
	"es": [WritingSystem.LATIN],
	"fr": [WritingSystem.LATIN],
	"pt": [WritingSystem.LATIN],
	"de": [WritingSystem.LATIN],
	"it": [WritingSystem.LATIN],
	"ru": [WritingSystem.CYRILLIC],
	"ar": [WritingSystem.ARABIC],
	"hi": [WritingSystem.DEVANAGARI],
	"th": [WritingSystem.THAI],
	"ko": [WritingSystem.HANGUL],
	"ja": [WritingSystem.KANA, WritingSystem.HAN],
	"zh": [WritingSystem.HAN],
}

## Inclusive code point ranges, outside ASCII, of the letters of each
## writing system. Code points in none of them, such as digits,
## punctuation, and CJK symbols, belong to no writing system.
const _LETTER_RANGES := [
	# ª, º, and the Latin-1 letters around × and ÷.
	[0x00AA, 0x00AA, WritingSystem.LATIN],
	[0x00BA, 0x00BA, WritingSystem.LATIN],
	[0x00C0, 0x00D6, WritingSystem.LATIN],
	[0x00D8, 0x00F6, WritingSystem.LATIN],
	[0x00F8, 0x024F, WritingSystem.LATIN],
	[0x1E00, 0x1EFF, WritingSystem.LATIN],
	[0x0370, 0x03FF, WritingSystem.GREEK],
	[0x0400, 0x052F, WritingSystem.CYRILLIC],
	[0x0600, 0x06FF, WritingSystem.ARABIC],
	[0x0750, 0x077F, WritingSystem.ARABIC],
	[0x08A0, 0x08FF, WritingSystem.ARABIC],
	[0xFB50, 0xFDFF, WritingSystem.ARABIC],
	[0xFE70, 0xFEFF, WritingSystem.ARABIC],
	[0x0900, 0x097F, WritingSystem.DEVANAGARI],
	[0x0E00, 0x0E7F, WritingSystem.THAI],
	[0x1100, 0x11FF, WritingSystem.HANGUL],
	[0x3130, 0x318F, WritingSystem.HANGUL],
	[0xA960, 0xA97F, WritingSystem.HANGUL],
	[0xAC00, 0xD7FF, WritingSystem.HANGUL],
	[0x3040, 0x30FF, WritingSystem.KANA],
	[0x31F0, 0x31FF, WritingSystem.KANA],
	[0xFF66, 0xFF9F, WritingSystem.KANA],
	# The iteration mark 々 and its neighbors 〆 and 〇.
	[0x3005, 0x3007, WritingSystem.HAN],
	[0x3400, 0x4DBF, WritingSystem.HAN],
	[0x4E00, 0x9FFF, WritingSystem.HAN],
	[0xF900, 0xFAFF, WritingSystem.HAN],
	[0x20000, 0x3134F, WritingSystem.HAN],
]
const _FIRST_NON_ASCII := 0x80
## A format placeholder as GDScript's % operator reads it, including
## the literal "%%".
const _PLACEHOLDER_PATTERN := "%[-+0-9.*]*[scdoxXfv%]"
const _LITERAL_PERCENT := "%%"
## A backslash escape such as \n, which the importer unescapes.
const _ESCAPE_PATTERN := "\\\\."

static var _placeholder_regex := RegEx.create_from_string(
	_PLACEHOLDER_PATTERN)
static var _escape_regex := RegEx.create_from_string(_ESCAPE_PATTERN)


## Returns the problems in a translation table: the UI table's shape,
## with a key column and one column per locale. expected_locales are
## the locales the game supports, which must each have a column.
static func check_ui_table(
	path: String,
	expected_locales: PackedStringArray,
) -> Array[String]:
	var problems: Array[String] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		problems.append("%s: cannot open (%s)" % [
			path,
			error_string(FileAccess.get_open_error()),
		])
		return problems

	var header := file.get_csv_line()
	if header.is_empty() or header[0] != UI_TABLE_KEY_HEADER:
		problems.append("%s: the first header cell must be '%s', not %s" % [
			path,
			UI_TABLE_KEY_HEADER,
			JSON.stringify(header[0] if not header.is_empty() else ""),
		])
		return problems
	var locales := header.slice(1)
	problems.append_array(_check_locales(path, locales, expected_locales))
	var english_column := locales.find(ENGLISH) + 1

	var seen_keys := {}
	var record := 1
	while not file.eof_reached():
		var cells := file.get_csv_line()
		record += 1
		if cells.size() == 1 and cells[0].is_empty():
			# A blank line, which the importer skips.
			continue
		var key := cells[0]
		var where := "%s record %d (%s)" % [path, record, JSON.stringify(key)]
		var spans_lines := false
		for cell in cells:
			if cell.contains("\n") or cell.contains("\r"):
				spans_lines = true
		if spans_lines:
			problems.append(
				"%s: a cell spans lines, so a quote is unbalanced and the"
				% where
				+ " lines after it merged into this record"
			)
			continue
		if cells.size() != header.size():
			problems.append(
				"%s: %d cells, but the header has %d. Quote any cell"
				% [where, cells.size(), header.size()]
				+ " that contains a comma."
			)
			continue
		if key.is_empty():
			problems.append("%s: no key, so the importer drops it" % where)
			continue
		if seen_keys.has(key):
			problems.append(
				"%s: duplicate key, first in record %d"
				% [where, seen_keys[key]]
			)
		seen_keys[key] = record

		var english := cells[english_column] if english_column > 0 else ""
		var english_placeholders := _placeholders(english)
		for column in range(1, cells.size()):
			var locale := header[column]
			var cell := cells[column]
			var cell_where := "%s [%s]" % [where, locale]
			if cell.is_empty():
				problems.append("%s: empty" % cell_where)
				continue
			if cell != cell.strip_edges():
				problems.append(
					"%s: leading or trailing whitespace, as a split cell"
					% cell_where
					+ " leaves: %s" % JSON.stringify(cell)
				)
			var placeholders := _placeholders(cell)
			if english_column > 0 and placeholders != english_placeholders:
				problems.append(
					"%s: placeholders %s, but English has %s: %s" % [
						cell_where,
						placeholders,
						english_placeholders,
						JSON.stringify(cell),
					]
				)
			problems.append_array(
				_check_writing_system(cell_where, locale, cell, english))
	return problems


## Returns the problems in one locale's adjective list: a
## "category,adjective" header, then one category and adjective per
## line. known_categories are the categories LocalizedNameConfig
## asks for.
static func check_adjectives(
	path: String,
	locale: String,
	known_categories: PackedStringArray,
) -> Array[String]:
	var problems: Array[String] = []
	if not FileAccess.file_exists(path):
		problems.append("%s: missing" % path)
		return problems
	var lines := FileAccess.get_file_as_string(path).split("\n")
	if lines[0].strip_edges() != ADJECTIVES_HEADER:
		problems.append("%s: the header must be '%s'" % [
			path,
			ADJECTIVES_HEADER,
		])
	if not LOCALE_WRITING_SYSTEMS.has(locale):
		problems.append(_unknown_locale_problem(path, locale))
		return problems
	for index in range(1, lines.size()):
		var line := lines[index].strip_edges()
		if line.is_empty():
			continue
		var where := "%s line %d" % [path, index + 1]
		if line.contains("\""):
			problems.append(
				"%s: a quote, which the game would show as part of the"
				% where
				+ " adjective: %s" % JSON.stringify(line)
			)
			continue
		if line.count(",") != 1:
			problems.append(
				"%s: %d commas, but a line holds one category and one"
				% [where, line.count(",")]
				+ " adjective: %s" % JSON.stringify(line)
			)
			continue
		var parts := line.split(",")
		var category := parts[0].strip_edges()
		var adjective := parts[1].strip_edges()
		if not known_categories.has(category):
			problems.append(
				"%s: unknown category %s" % [where, JSON.stringify(category)]
			)
		if adjective.is_empty():
			problems.append("%s: no adjective" % where)
			continue
		problems.append_array(
			_check_writing_system(where, locale, adjective, ""))
	return problems


## Returns the problems in one locale's name list: one bunny name per
## line.
static func check_names(path: String, locale: String) -> Array[String]:
	var problems: Array[String] = []
	if not FileAccess.file_exists(path):
		problems.append("%s: missing" % path)
		return problems
	if not LOCALE_WRITING_SYSTEMS.has(locale):
		problems.append(_unknown_locale_problem(path, locale))
		return problems
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for index in range(lines.size()):
		var line := lines[index].strip_edges()
		if line.is_empty():
			continue
		var where := "%s line %d" % [path, index + 1]
		if line.contains(",") or line.contains("\""):
			problems.append(
				"%s: a comma or quote in a name: %s"
				% [where, JSON.stringify(line)]
			)
			continue
		problems.append_array(_check_writing_system(where, locale, line, ""))
	return problems


## Returns every record of a CSV file as Godot's importer reads it,
## the header first, skipping blank lines.
static func read_csv_records(path: String) -> Array[PackedStringArray]:
	var records: Array[PackedStringArray] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return records
	while not file.eof_reached():
		var cells := file.get_csv_line()
		if cells.size() == 1 and cells[0].is_empty():
			continue
		records.append(cells)
	return records


## Returns every .csv file under dir, recursively.
static func find_csv_files(dir: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file_name in DirAccess.get_files_at(dir):
		if file_name.ends_with(CSV_EXTENSION):
			found.append(dir.path_join(file_name))
	for subdir in DirAccess.get_directories_at(dir):
		found.append_array(find_csv_files(dir.path_join(subdir)))
	return found


## Returns the locale an adjective or name list is for, read from its
## file name, or "" when path is neither.
static func get_list_locale(path: String) -> String:
	var file_name := path.get_file()
	if not file_name.ends_with(CSV_EXTENSION):
		return ""
	var base := file_name.trim_suffix(CSV_EXTENSION)
	var dir := path.get_base_dir()
	if dir == ADJECTIVES_DIR and base.begins_with(ADJECTIVES_FILE_PREFIX):
		return base.trim_prefix(ADJECTIVES_FILE_PREFIX)
	if dir == NAMES_DIR and base.begins_with(NAMES_FILE_PREFIX):
		return base.trim_prefix(NAMES_FILE_PREFIX)
	return ""


## Returns the writing system a code point's letter belongs to, or
## NONE for anything that is not a letter.
static func get_writing_system(code_point: int) -> WritingSystem:
	if code_point < _FIRST_NON_ASCII:
		var character := char(code_point)
		if (
			(character >= "A" and character <= "Z")
			or (character >= "a" and character <= "z")
		):
			return WritingSystem.LATIN
		return WritingSystem.NONE
	for letter_range: Array in _LETTER_RANGES:
		if code_point >= letter_range[0] and code_point <= letter_range[1]:
			return letter_range[2]
	return WritingSystem.NONE


static func _check_locales(
	path: String,
	locales: PackedStringArray,
	expected_locales: PackedStringArray,
) -> Array[String]:
	var problems: Array[String] = []
	var seen := {}
	for locale in locales:
		if seen.has(locale):
			problems.append("%s: two columns for %s" % [path, locale])
		seen[locale] = true
		if not LOCALE_WRITING_SYSTEMS.has(locale):
			problems.append(_unknown_locale_problem(path, locale))
		if not expected_locales.has(locale):
			problems.append(
				"%s: a column for %s, which the game does not offer"
				% [path, locale]
			)
	for locale in expected_locales:
		if not seen.has(locale):
			problems.append("%s: no column for %s" % [path, locale])
	if not seen.has(ENGLISH):
		problems.append("%s: no English column to compare to" % path)
	return problems


## Checks text against the writing systems of its locale. english is
## the same entry's English text, or "" when there is none to allow.
static func _check_writing_system(
	where: String,
	locale: String,
	text: String,
	english: String,
) -> Array[String]:
	var problems: Array[String] = []
	if not LOCALE_WRITING_SYSTEMS.has(locale):
		problems.append(_unknown_locale_problem(where, locale))
		return problems
	var native: Array = LOCALE_WRITING_SYSTEMS[locale]
	var letters := _strip_markup(text)
	var counts := {}
	for index in range(letters.length()):
		var system := get_writing_system(letters.unicode_at(index))
		if system != WritingSystem.NONE:
			counts[system] = int(counts.get(system, 0)) + 1
	var foreign: Array[String] = []
	var native_count := 0
	for system: WritingSystem in counts:
		if native.has(system):
			native_count += counts[system]
		elif system != WritingSystem.LATIN:
			foreign.append(WritingSystem.find_key(system))
	if not foreign.is_empty():
		problems.append(
			"%s: letters of %s, which %s does not use: %s"
			% [where, ", ".join(foreign), locale, JSON.stringify(text)]
		)
	elif (
		not native.has(WritingSystem.LATIN)
		and native_count == 0
		and int(counts.get(WritingSystem.LATIN, 0)) > 0
		and text != english
	):
		problems.append(
			"%s: Latin letters and none of %s's own, and not the English"
			% [where, locale]
			+ " text either: %s" % JSON.stringify(text)
		)
	return problems


static func _placeholders(text: String) -> Array[String]:
	var found: Array[String] = []
	for regex_match in _placeholder_regex.search_all(text):
		var placeholder := regex_match.get_string()
		if placeholder != _LITERAL_PERCENT:
			found.append(placeholder)
	return found


## Drops placeholders and backslash escapes, whose letters (the d of
## %d, the n of \n) belong to no language.
static func _strip_markup(text: String) -> String:
	return _escape_regex.sub(
		_placeholder_regex.sub(text, " ", true), " ", true)


static func _unknown_locale_problem(where: String, locale: String) -> String:
	return (
		"%s: no writing system is known for %s. Add it to"
		% [where, JSON.stringify(locale)]
		+ " TranslationCsvChecker.LOCALE_WRITING_SYSTEMS."
	)
