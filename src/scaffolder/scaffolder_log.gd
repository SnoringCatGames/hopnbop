class_name ScaffolderLog
extends Node


signal on_message(message: String)

const CATEGORY_DEFAULT := StringName("Default")
const CATEGORY_SYSTEM_INITIALIZATION := StringName("SysInit")
const CATEGORY_CORE_SYSTEMS := StringName("CoreSystems")
const CATEGORY_PLAYER_MOVEMENT := StringName("PlayerMovement")
const CATEGORY_NETWORK_SYNC := StringName("NetworkSync")

# Dictionary<StringName, StringName>
var _parsed_category_prefixes := {}

var is_queuing_messages := true

var _print_queue: Array[String] = []

# Dictionary<StringName, bool>
var _excluded_log_categories := {}
var _force_include_log_warnings := true


func _ready() -> void:
    _print_front_matter()

    G.log.print("ScaffolderLog._ready", ScaffolderLog.CATEGORY_SYSTEM_INITIALIZATION)


static func _format_message(message: String, category: StringName) -> String:
    var play_time: float = \
            G.time.get_play_time() if \
            is_instance_valid(G) and is_instance_valid(G.time) else \
            -1.0
    return "%8.3f [%s] %s" % [play_time, category, message]


func print(message = "", category := CATEGORY_DEFAULT) -> void:
    if not _is_category_enabled(category):
        return

    if !(message is String):
        message = str(message)

    message = _format_message(message, category)

    if is_queuing_messages:
        _print_queue.push_back(message)
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
        should_assert := true) -> void:
    message = "ERROR  : %s" % message
    push_error(message)
    self.print(message, _category)
    if should_assert:
         assert(false)


# -   Using this function instead of `push_error` directly enables us to render
#     the console output in environments like a mobile device.
# -   This requires an explicit error message in order to disambiguate where
#     the error actually happened.
#     -   This is needed because stack traces are not available on non-main
#         threads.
static func static_error(
        message: String,
        _category := CATEGORY_DEFAULT,
        should_assert := true) -> void:
    message = "ERROR  : %s" % message
    push_error(message)
    if should_assert:
         assert(false)


# -   Using this function instead of `push_error` directly enables us to render
#     the console output in environments like a mobile device.
# -   This requires an explicit error message in order to disambiguate where
#     the error actually happened.
#     -   This is needed because stack traces are not available on non-main
#         threads.
func warning(message: String, category := CATEGORY_DEFAULT) -> void:
    if _is_category_enabled(category) or _force_include_log_warnings:
        message = "WARNING: %s" % message
        push_warning(message)
        self.print(message, category)


func alert_user(message: String, _category := CATEGORY_DEFAULT) -> void:
    if _is_category_enabled(_category) or _force_include_log_warnings:
        var formatted_message := "ALERT: %s" % message
        push_warning(formatted_message)
        self.print(formatted_message, _category)
    OS.alert(message)


func set_log_filtering(
        p_excluded_log_categories: Array[StringName],
        p_force_include_log_warnings: bool) -> void:
    for category in p_excluded_log_categories:
        _excluded_log_categories[category] = true
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
        if c >= 'A' and c <= 'Z':
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


func _print_front_matter() -> void:
    var local_datetime := Time.get_datetime_dict_from_system(false)
    var local_datetime_string := "[Local] %s-%s-%s_%s.%s.%s" % [
        local_datetime.year,
        local_datetime.month,
        local_datetime.day,
        local_datetime.hour,
        local_datetime.minute,
        local_datetime.second,
    ]

    var utc_datetime := Time.get_datetime_dict_from_system(true)
    var utc_datetime_string := "[UTC  ] %s-%s-%s_%s.%s.%s" % [
        utc_datetime.year,
        utc_datetime.month,
        utc_datetime.day,
        utc_datetime.hour,
        utc_datetime.minute,
        utc_datetime.second,
    ]

    var device_info_string := (
        "%s " +
        "%s " +
        "(%4d,%4d) " +
        ""
    ) % [
        OS.get_name(),
        OS.get_model_name(),
        get_viewport().get_visible_rect().size.x,
        get_viewport().get_visible_rect().size.y,
    ]

    self.print(local_datetime_string, CATEGORY_CORE_SYSTEMS)
    self.print(utc_datetime_string, CATEGORY_CORE_SYSTEMS)

    self.print(device_info_string, CATEGORY_CORE_SYSTEMS)
    self.print("", CATEGORY_CORE_SYSTEMS)
