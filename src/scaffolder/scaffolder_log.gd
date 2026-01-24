class_name ScaffolderLog
extends Node

signal on_message(message: String)

enum Verbosity {
	NORMAL,
	VERBOSE,
}

const CATEGORY_DEFAULT := StringName("Default")
const CATEGORY_SYSTEM_INITIALIZATION := StringName("SysInit")
const CATEGORY_CORE_SYSTEMS := StringName("CoreSystems")
const CATEGORY_PLAYER_ACTIONS := StringName("PlayerActions")
const CATEGORY_NETWORK_CONNECTIONS := StringName("NetworkConnections")
const CATEGORY_NETWORK_SYNC := StringName("NetworkSync")
const CATEGORY_INTERACTION := StringName("PlayerInteraction")
const CATEGORY_GAME_STATE := StringName("GameState")

const _RAINBOW_BAR = (
    "[color=red]=[/color][color=orange]=[/color][color=yellow]=[/color]"
	+ "[color=green]=[/color][color=blue]=[/color][color=purple]=[/color]"
)
const _REVERSE_RAINBOW_BAR = (
    "[color=purple]=[/color][color=blue]=[/color][color=green]=[/color]"
	+ "[color=yellow]=[/color][color=orange]=[/color][color=red]=[/color]"
)

# Dictionary<StringName, StringName>
var _parsed_category_prefixes := { }

var is_queuing_messages := true

var _print_queue: Array[String] = []

# Dictionary<StringName, bool>
var _excluded_log_categories := { }
var _force_include_log_warnings := true

# Cache for test environment detection - only cache positive results
# because GUT may not be in tree yet during early initialization
var _is_test_env_cached: Variant = null

var is_verbose: bool:
	get:
		return G.settings.verbosity >= Verbosity.VERBOSE


func _ready() -> void:
	_print_front_matter()

	self.print(
		"ScaffolderLog._ready",
		ScaffolderLog.CATEGORY_SYSTEM_INITIALIZATION,
	)


func _format_message(message: String, category: StringName) -> String:
	var play_time: float = (
		G.time.get_play_time() if is_instance_valid(G) and is_instance_valid(G.time) else -1.0
	)

	var category_token := (
		"[%s]" % get_category_prefix(category) if G.settings.include_category_in_logs else ""
	)

	var multiplayer_id_value: String
	if G.settings.include_multiplayer_id_in_logs and G.network.is_preview:
		if G.network.is_client:
			if G.network.is_connected_to_server:
				# Client, connected to server.
				multiplayer_id_value = "C%d" % G.network.local_id
			else:
				# Client, not yet connected to server.
				if G.network.is_preview:
					multiplayer_id_value = "C%d" % G.network.preview_client_number
				else:
					multiplayer_id_value = "C-"
		else:
			# Server.
			multiplayer_id_value = "S"
	else:
		# Omit token.
		multiplayer_id_value = ""
	var multiplayer_id_token = (
		"[%s]" % multiplayer_id_value if G.settings.include_multiplayer_id_in_logs else ""
	)

	return (
        "[%8.3f]%s%s %s"
		% [
			play_time,
			category_token,
			multiplayer_id_token,
			message,
		]
	)


func print(
		message = "",
		category := CATEGORY_DEFAULT,
		verbosity := Verbosity.NORMAL,
) -> void:
	if _is_running_in_test_env():
		return

	if not _is_category_enabled(category):
		return
	if verbosity > G.settings.verbosity:
		return

	if !(message is String):
		message = str(message)

	message = _format_message(message, category)

	if is_queuing_messages:
		_print_queue.append(message)
	else:
		on_message.emit(message)

	print(message)


# -   Using this function instead of `push_error` directly enables us to render
#     the console output in environments like a mobile device.
# -   This requires an explicit error message in order to disambiguate where
#     the error actually happened.
#     -   This is needed because stack traces are not available on non-main
#         threads.
func error(
		message: String,
		_category := CATEGORY_DEFAULT,
		should_crash := true,
) -> void:
	if _is_running_in_test_env():
		return

	message = "ERROR  : %s" % message
	if should_crash:
		message = "FATAL %s" % message

	push_error(message)
	print_stack()
	self.print(message, _category)
	breakpoint
	if should_crash:
		if not OS.has_feature("editor"):
			# If we're not running in the editor in preview mode, let the player
			# know why we're quitting.
			OS.alert(message)
		get_tree().quit()


# -   Using this function instead of `push_error` directly enables us to render
#     the console output in environments like a mobile device.
# -   This requires an explicit error message in order to disambiguate where
#     the error actually happened.
#     -   This is needed because stack traces are not available on non-main
#         threads.
func warning(
		message: String,
		category := CATEGORY_DEFAULT,
) -> void:
	if _is_running_in_test_env():
		return

	if _is_category_enabled(category) or _force_include_log_warnings:
		message = "WARNING: %s" % message

		push_warning(message)

		self.print(message, category)


func alert_user(message: String, _category := CATEGORY_DEFAULT) -> void:
	if _is_running_in_test_env():
		return

	if _is_category_enabled(_category) or _force_include_log_warnings:
		var formatted_message := "ALERT: %s" % message

		push_warning(formatted_message)

		self.print(formatted_message, _category)

	OS.alert(message)


func ensure(condition: bool, message: String) -> bool:
	if _is_running_in_test_env():
		return condition

	if not condition:
		var formatted_message := "FAILED ENSURE: %s" % message
		error(formatted_message, CATEGORY_CORE_SYSTEMS, false)
		breakpoint

	return condition


func check(condition: bool, message: String) -> bool:
	if _is_running_in_test_env():
		return condition

	if not condition:
		var formatted_message := "FATAL ERROR: %s" % message
		error(formatted_message, CATEGORY_CORE_SYSTEMS, true)

	return condition


func set_log_filtering(
		p_excluded_log_categories: Array[StringName],
		p_force_include_log_warnings: bool,
) -> void:
	_excluded_log_categories = Utils.array_to_set(p_excluded_log_categories)
	_force_include_log_warnings = p_force_include_log_warnings


func _is_category_enabled(category: StringName) -> bool:
	return not _excluded_log_categories.has(category)


func _is_running_in_test_env() -> bool:
	# Only cache positive results because GUT may not be in tree yet during
	# early initialization (autoloads run before GUT is added)
	if _is_test_env_cached == true:
		return true

	_calculate_is_running_in_test_env()
	return bool(_is_test_env_cached)


func _calculate_is_running_in_test_env() -> void:
	# Check multiple indicators that we're running in a test environment

	# Method 1: Check if running with gut_cmdln.gd (command line tests)
	# The SceneTree script will be gut_cmdln.gd when running tests
	var tree = get_tree()
	if tree:
		var script = tree.get_script()
		if script:
			var script_path = script.resource_path
			if "gut_cmdln" in script_path or "gut_cli" in script_path:
				_is_test_env_cached = true
				return

	# Method 2: Check if GUT is in the scene tree
	var root = tree.root if tree else null
	if root:
		for child in root.get_children():
			var child_class = child.get_class()
			# Check for GutMain or RunFromEditor (editor test runner)
			if (
				child_class == "GutMain"
				or child.has_method("get_test_count")
				or child.name == "RunFromEditor"
			):
				_is_test_env_cached = true
				return

	# Method 3: Check command-line arguments for GUT-specific flags
	# or if loading GUT scenes
	for arg in OS.get_cmdline_args():
		if (
			(arg.begins_with("-g") and ("test" in arg or "dir" in arg or "exit" in arg))
			or "addons/gut" in arg
		):
			_is_test_env_cached = true
			return

	_is_test_env_cached = false


func get_category_prefix(category: StringName) -> StringName:
	if not _parsed_category_prefixes.has(category):
		_parsed_category_prefixes[category] = _parse_category_prefix(category)
	return _parsed_category_prefixes[category]


func _parse_category_prefix(category: StringName) -> StringName:
	var category_str := String(category)
	var capitals := ""

	# Extract all capital letters.
	for i in range(category_str.length()):
		var c := category_str[i]
		if c >= "A" and c <= "Z":
			capitals += c

	var prefix: StringName
	var capitals_count := capitals.length()

	if capitals_count == 2:
		# 2 capitals: perfect.
		prefix = capitals
	elif capitals_count > 2:
		# >2 capitals: trim to first 2.
		prefix = capitals.substr(0, 2)
	elif capitals_count == 1:
		# 1 capital: pad with space at the end.
		prefix = capitals + " "
	elif capitals_count == 0:
		# 0 capitals: use first character from category.
		if category_str.length() > 0:
			prefix = category_str[0] + " "
		else:
			prefix = "  "

	return prefix


func log_system_ready(system_name: String) -> void:
	self.print("%s ready" % system_name, ScaffolderLog.CATEGORY_SYSTEM_INITIALIZATION)


func _print_front_matter() -> void:
	var local_datetime := Time.get_datetime_dict_from_system(false)
	var local_datetime_string := (
        "[Local] %s-%s-%s_%s.%s.%s"
		% [
			local_datetime.year,
			local_datetime.month,
			local_datetime.day,
			local_datetime.hour,
			local_datetime.minute,
			local_datetime.second,
		]
	)

	var utc_datetime := Time.get_datetime_dict_from_system(true)
	var utc_datetime_string := (
        "[UTC  ] %s-%s-%s_%s.%s.%s"
		% [
			utc_datetime.year,
			utc_datetime.month,
			utc_datetime.day,
			utc_datetime.hour,
			utc_datetime.minute,
			utc_datetime.second,
		]
	)

	var device_info_string := (
		("%s " + "%s " + "(%4d,%4d) " + "")
		% [
			OS.get_name(),
			OS.get_model_name(),
			get_viewport().get_visible_rect().size.x,
			get_viewport().get_visible_rect().size.y,
		]
	)

	# Only print the art when in preview mode, and only once then.
	if G.network.is_preview and G.network.is_server:
		#_print_cat()

		var app_name = ProjectSettings.get_setting("application/config/name")
		print_rich("%s %s %s\n" % [_RAINBOW_BAR, app_name, _REVERSE_RAINBOW_BAR])

	self.print(local_datetime_string, CATEGORY_CORE_SYSTEMS)
	self.print(utc_datetime_string, CATEGORY_CORE_SYSTEMS)

	self.print(device_info_string, CATEGORY_CORE_SYSTEMS)
	self.print("", CATEGORY_CORE_SYSTEMS)


func _print_cat() -> void:
	const ASCII_CAT := """
               ######
               ####  ##
               #   #   ##
               #    ##   ###############
               #      ##                ##########
               #       #                          ####
            ### #######                               ##
          ## ##                                         ##
         #   #                                            #
       ##   #                     #                        #
     ##    #    ##               ##                         #
    #     #    #                ##                           #
   #      #   #                ##                             #
  #      ##                ####                 ##            ##
  #     #  ##            ##                    #               #
 #     #     ############                    ##                #
##     #                                   ##                  #
#      ##                              ####                    #
#     #  ###                ###########                        #
#           ################    #                              #
#                                #                             #
##                               ##                            #
 #                                #                           ##
 ##                                #                          #
  #                                #                         #
   #                                #                       ##
    #                               #                       #
    ##                              #                      #
     ##                                                   #
       ##                                               ##
         ##                                           ##
           #                                         #
            ####                                 ####
                #####                        ####
                     ########################
"""
	const PADDING := 8
	var padded_cat := ASCII_CAT.replace("\n", "\n".rpad(PADDING + 1))
	print(padded_cat)
