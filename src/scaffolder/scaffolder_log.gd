class_name ScaffolderLog
extends Node


# FIXME: Log categories:
# - Introduce a new StringName parameter for enabling filtering logs by category.
#   - Add support for listing expected StringName categories in Settings, mapped
#     to a boolean for whether they're enabled.
# - Add some logging for obvious bits that need it.
#   - Re-introduce some character, surface state, and action logs.
# - Add support for toggling the visibility of this debug panel from Settings.
#


signal on_message(message: String)


var is_queuing_messages := true

var _print_queue: Array[String] = []


func _ready() -> void:
    _print_front_matter()


static func _format_message(message: String) -> String:
    var play_time: float = \
            G.time.get_play_time() if \
            is_instance_valid(G) and is_instance_valid(G.time) else \
            -1.0
    return "[%8.3f] %s" % [play_time, message]


func print(message = "") -> void:
    if !(message is String):
        message = str(message)
    
    message = _format_message(message)
    
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
        should_assert := true) -> void:
    message = _format_message("ERROR  : %s" % message)
    push_error(message)
    self.print(message)
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
        should_assert := true) -> void:
    message = _format_message("ERROR  : %s" % message)
    push_error(message)
    if should_assert:
         assert(false)


# -   Using this function instead of `push_error` directly enables us to render
#     the console output in environments like a mobile device.
# -   This requires an explicit error message in order to disambiguate where
#     the error actually happened.
#     -   This is needed because stack traces are not available on non-main
#         threads.
func warning(message: String) -> void:
    message = _format_message("WARNING: %s" % message)
    push_warning(message)
    self.print(message)


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
    
    self.print(local_datetime_string)
    self.print(utc_datetime_string)
    
    self.print(device_info_string)
    self.print()
