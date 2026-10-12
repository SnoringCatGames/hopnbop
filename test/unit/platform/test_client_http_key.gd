extends GutTest
## Guards against the Nakama runtime HTTP key shipping in a client.
##
## The HTTP key authenticates game servers and operator tools as
## trusted callers of every runtime RPC. Clients up to 0.47.0 embedded
## it in global.gd for one pre-sign-in call (version_check), which
## handed it to anyone who unpacked a build or read this public repo.
## The version check now uses the runtime's unauthenticated route, and
## dedicated servers read the key from their NAKAMA_HTTP_KEY
## environment variable at runtime.
##
## The scans below cover what an export packs (the presets export
## all resources), minus vendored and test code.

## Directories the scans skip besides dot-directories (.godot, .git,
## .claude) and test directories: vendored third-party addons
## (nakama-godot's API code builds `http_key=` generically) and the
## submodule source, which is mirrored into res://addons.
const _SKIPPED_DIRECTORIES: Array[String] = [
	"res://addons/gut",
	"res://addons/nakama",
	"res://third_party",
]
## A directory name that marks test code.
const _TEST_DIRECTORY_NAME := "test"
const _SCRIPT_EXTENSIONS: Array[String] = ["gd"]
const _RESOURCE_EXTENSIONS: Array[String] = [
	"tscn", "tres", "cfg", "godot", "json",
]
## How shipped code may obtain the key: from the server's own
## environment, which is empty on players' machines.
const _ENVIRONMENT_READ := "OS.get_environment(\"NAKAMA_HTTP_KEY\")"
const _QUERY_PARAMETER := "http_key="
## A `nakama_http_key` config entry, or an assignment to the SDK's
## deprecated Platform.nakama_http_key (`==` comparisons and the
## typed declaration don't match).
const _SCRIPT_KEY_PATTERN := (
	"[\"']nakama_http_key[\"']\\s*:|\\bnakama_http_key\\s*=(?!=)")
const _RESOURCE_PROPERTY_PATTERN := "(?mi)^\\s*nakama_http_key\\s*="


func test_platform_holds_no_http_key() -> void:
	# The SDK keeps the property only so old game code compiles;
	# Platform.initialize ignores the config entry.
	assert_eq(
		Platform.nakama_http_key,
		"",
		"Platform must not carry the runtime HTTP key",
	)


func test_version_check_url_carries_no_credential() -> void:
	var url: String = G.backend_api_client.get_version_check_url()
	assert_true(
		url.ends_with(Platform.VERSION_CHECK_PATH),
		"version check should use the unauthenticated route: %s" % url,
	)
	assert_false(url.contains("http_key"), url)
	assert_false(url.contains("/v2/rpc/"), url)
	assert_false(url.contains("?"), url)


func test_version_check_body_carries_no_credential() -> void:
	var body: String = G.backend_api_client.build_version_check_body(
		1, "0.0.0")
	var parsed: Variant = JSON.parse_string(body)
	assert_true(parsed is Dictionary, body)
	var keys: Array = (parsed as Dictionary).keys()
	keys.sort()
	assert_eq(
		keys,
		["client_game_version", "client_protocol_version", "game_id"],
	)


func test_no_shipped_script_sets_an_http_key() -> void:
	var pattern := RegEx.create_from_string(_SCRIPT_KEY_PATTERN)
	var scripts := _collect_files("res://", _SCRIPT_EXTENSIONS)
	assert_gt(scripts.size(), 0, "the scan found no scripts")
	var offenders: Array[String] = []
	for path in scripts:
		if pattern.search(FileAccess.get_file_as_string(path)) != null:
			offenders.append(path)
	assert_true(
		offenders.is_empty(),
		"scripts that configure or assign nakama_http_key: %s"
		% [offenders],
	)


func test_shipped_http_key_query_comes_from_the_environment() -> void:
	var offenders: Array[String] = []
	for path in _collect_files("res://", _SCRIPT_EXTENSIONS):
		var text := FileAccess.get_file_as_string(path)
		if (
			text.contains(_QUERY_PARAMETER)
			and not text.contains(_ENVIRONMENT_READ)
		):
			offenders.append(path)
	assert_true(
		offenders.is_empty(),
		(
			"scripts that send %s without reading it from %s: %s"
			% [_QUERY_PARAMETER, _ENVIRONMENT_READ, offenders]
		),
	)


func test_no_shipped_resource_mentions_an_http_key() -> void:
	var property := RegEx.create_from_string(_RESOURCE_PROPERTY_PATTERN)
	var offenders: Array[String] = []
	for path in _collect_files("res://", _RESOURCE_EXTENSIONS):
		var text := FileAccess.get_file_as_string(path)
		if (
			text.containsn(_QUERY_PARAMETER)
			or property.search(text) != null
		):
			offenders.append(path)
	assert_true(
		offenders.is_empty(),
		"resources that carry an HTTP key: %s" % [offenders],
	)


## Returns every file under `directory` with one of `extensions`,
## skipping dot-directories, test directories and
## _SKIPPED_DIRECTORIES.
func _collect_files(
	directory: String,
	extensions: Array[String],
) -> Array[String]:
	var base := directory if directory.ends_with("/") else directory + "/"
	var found: Array[String] = []
	for file_name in DirAccess.get_files_at(base):
		if file_name.get_extension() in extensions:
			found.append(base + file_name)
	for child in DirAccess.get_directories_at(base):
		var child_path := base + child
		if (
			child.begins_with(".")
			or child == _TEST_DIRECTORY_NAME
			or child_path in _SKIPPED_DIRECTORIES
		):
			continue
		found.append_array(_collect_files(child_path, extensions))
	return found
