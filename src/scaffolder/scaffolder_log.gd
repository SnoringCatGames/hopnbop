class_name ScaffolderLog
extends NetworkLogger

signal on_message(message: String)

const _RAINBOW_BAR = (
    "[color=red]=[/color][color=orange]=[/color][color=yellow]=[/color]"
	+"[color=green]=[/color][color=blue]=[/color][color=purple]=[/color]"
)
const _REVERSE_RAINBOW_BAR = (
    "[color=purple]=[/color][color=blue]=[/color][color=green]=[/color]"
	+"[color=yellow]=[/color][color=orange]=[/color][color=red]=[/color]"
)

# Dictionary<StringName, StringName>
var _parsed_category_prefixes := {}

var is_queuing_messages := true

var _print_queue: Array[String] = []

# Dictionary<StringName, bool>
var _excluded_log_categories := {}
var _force_include_log_warnings := true


func _ready() -> void:
	_print_front_matter()

	_print_internal(
		"ScaffolderLog._ready",
		NetworkLogger.CATEGORY_SYSTEM_INITIALIZATION,
	)


func _format_message(message: String, category: StringName) -> String:
	var play_time: float = (
		Netcode.time.get_time() if is_instance_valid(G) and is_instance_valid(Netcode.time) else -1.0
	)

	var category_token := (
		"[%s]" % get_category_prefix(category) if G.settings.include_category_in_logs else ""
	)

	var peer_id_value: String
	if G.settings.include_peer_id_in_logs and Netcode.is_preview:
		if Netcode.is_client:
			if Netcode.is_connected_to_server:
				# Client, connected to server.
				peer_id_value = "C%d" % Netcode.local_peer_id
			else:
				# Client, not yet connected to server.
				if Netcode.is_preview:
					peer_id_value = "C%d" % Netcode.preview_client_number
				else:
					peer_id_value = "C-"
		else:
			# Server.
			peer_id_value = "S"
	else:
		# Omit token.
		peer_id_value = ""
	var peer_id_token = (
		"[%s]" % peer_id_value if G.settings.include_peer_id_in_logs else ""
	)

	return (
		"[%8.3f]%s%s %s" % [
			play_time,
			category_token,
			peer_id_token,
			message,
		]
	)


func _print_internal(
	message = "",
	category := CATEGORY_DEFAULT,
	is_verbose_message := false,
) -> void:
	if TestEnvironmentDetector.is_running_in_test_env(self ):
		return

	if not _is_category_enabled(category):
		return
	if is_verbose_message and not is_verbose:
		return

	if !(message is String):
		message = str(message)

	message = _format_message(message, category)

	if is_queuing_messages:
		_print_queue.append(message)
	else:
		on_message.emit(message)

	# Call built-in print.
	print(message)


func print(
	message = "",
	category := CATEGORY_DEFAULT,
) -> void:
	_print_internal(message, category, false)


func verbose(
	message = "",
	category := CATEGORY_DEFAULT,
) -> void:
	_print_internal(message, category, true)


# -   Using this function instead of `push_error` directly enables us to render
#     the console output in environments like a mobile device.
# -   This requires an explicit error message in order to disambiguate where
#     the error actually happened.
#     -   This is needed because stack traces are not available on non-main
#         threads.
func error(
	message := "",
	category := CATEGORY_DEFAULT,
	should_crash := false,
) -> void:
	if TestEnvironmentDetector.is_running_in_test_env(self ):
		return

	var formatted_message := "ERROR  : %s" % message
	if should_crash:
		formatted_message = "FATAL %s" % formatted_message

	push_error(formatted_message)
	print_stack()
	_print_internal(formatted_message, category)
	breakpoint
	if should_crash:
		if not OS.has_feature("editor"):
			# If we're not running in the editor in preview mode, let the player
			# know why we're quitting.
			OS.alert(formatted_message)
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
	if TestEnvironmentDetector.is_running_in_test_env(self ):
		return

	if _is_category_enabled(category) or _force_include_log_warnings:
		message = "WARNING: %s" % message

		push_warning(message)

		_print_internal(message, category)


func alert_user(message: String, _category := CATEGORY_DEFAULT) -> void:
	if TestEnvironmentDetector.is_running_in_test_env(self ):
		return

	if _is_category_enabled(_category) or _force_include_log_warnings:
		var formatted_message := "ALERT: %s" % message

		push_warning(formatted_message)

		_print_internal(formatted_message, _category)

	OS.alert(message)


func ensure(condition: bool, message := "") -> bool:
	if TestEnvironmentDetector.is_running_in_test_env(self ):
		return condition

	if not condition:
		var formatted_message := "FAILED ENSURE: %s" % message
		error(formatted_message, CATEGORY_CORE_SYSTEMS, false)
		breakpoint

	return condition


func check(condition: bool, message := "") -> bool:
	if TestEnvironmentDetector.is_running_in_test_env(self ):
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
	_print_internal(
		"%s ready" % system_name,
		NetworkLogger.CATEGORY_SYSTEM_INITIALIZATION)


func _print_front_matter() -> void:
	var local_datetime := Time.get_datetime_dict_from_system(false)
	var local_datetime_string := (
		"[Local] %s-%s-%s_%s.%s.%s" % [
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
		"[UTC  ] %s-%s-%s_%s.%s.%s" % [
			utc_datetime.year,
			utc_datetime.month,
			utc_datetime.day,
			utc_datetime.hour,
			utc_datetime.minute,
			utc_datetime.second,
		]
	)

	var device_info_string := (
		("%s " + "%s " + "(%4d,%4d) " + "") % [
			OS.get_name(),
			OS.get_model_name(),
			get_viewport().get_visible_rect().size.x,
			get_viewport().get_visible_rect().size.y,
		]
	)

	# Only print the art when in preview mode, and only once then.
	if Netcode.is_preview and Netcode.is_server:
		#_print_cat()
		var app_name = ProjectSettings.get_setting("application/config/name")
		print_rich(
			"%s %s %s\n" % [_RAINBOW_BAR, app_name, _REVERSE_RAINBOW_BAR])

	var app_version = ProjectSettings.get_setting(
		"application/config/version",
		"unknown"
	)
	_print_internal("Version: %s" % app_version, CATEGORY_CORE_SYSTEMS)

	_print_internal(local_datetime_string, CATEGORY_CORE_SYSTEMS)
	_print_internal(utc_datetime_string, CATEGORY_CORE_SYSTEMS)

	_print_internal(device_info_string, CATEGORY_CORE_SYSTEMS)
	_print_internal("", CATEGORY_CORE_SYSTEMS)


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
