extends GutTest
## Unit tests for ExportDataRow's file handling. The export must be
## saved exactly as the server sent it: Godot's JSON parser turns
## every number into a float, so re-encoding the parsed export would
## write 1500.0 for a score of 1500 and round long ids.


const _SERVER_JSON := "{\n  \"format_version\": 2,\n  \"score\": 1500\n}"
const _TEST_FILE_NAME := "test_export_data_row.json"


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(
		"%s/%s" % [ExportDataRow.EXPORT_DIR, _TEST_FILE_NAME]))


func test_export_text_is_the_servers_json() -> void:
	var parsed: Variant = JSON.parse_string(_SERVER_JSON)

	assert_eq(ExportDataRow.export_text(_SERVER_JSON, parsed), _SERVER_JSON)


func test_export_text_falls_back_to_encoding_the_data() -> void:
	# An SDK that doesn't keep the text still exports every field.
	# String values only: numbers would come back as floats.
	var data := {"generated_at": "now", "account": {"user_id": "u"}}

	var text := ExportDataRow.export_text("", data)

	assert_eq(JSON.parse_string(text), data)


func test_save_export_writes_the_text_verbatim() -> void:
	var path := ExportDataRow.save_export(_SERVER_JSON, _TEST_FILE_NAME)

	assert_eq(path, "%s/%s" % [ExportDataRow.EXPORT_DIR, _TEST_FILE_NAME])
	assert_eq(FileAccess.get_file_as_string(path), _SERVER_JSON)


func test_export_file_name_carries_the_time() -> void:
	assert_eq(
		ExportDataRow.export_file_name(1760000000),
		"hopnbop_export_1760000000.json",
	)
