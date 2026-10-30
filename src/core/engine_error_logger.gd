class_name EngineErrorLogger
extends Logger
## Forwards engine and script errors to the CrashReporter
## (H86, CR6): until now only G.log.error fed it, so a script
## error that no game code logged (a broken format string,
## say) was never reported. Warnings are not forwarded, and
## exit-time leak lines are noise (CrashReportText.
## is_exit_noise), not errors.
##
## Godot calls _log_error on whatever thread hit the error;
## CrashReporter.report_crash re-dispatches to the main
## thread itself. Each signature is reported at most once
## per run, so an error loop can't spend the daily cap.


var _reporter: CrashReporter


func _init(reporter: CrashReporter) -> void:
	_reporter = reporter


func _log_error(
	_function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: ErrorType,
	_script_backtraces: Array[ScriptBacktrace],
) -> void:
	if error_type == Logger.ERROR_TYPE_WARNING:
		return
	if _reporter == null or _reporter.is_exiting:
		return
	var message := code
	if not rationale.is_empty() and rationale != code:
		message += ": " + rationale
	if not file.is_empty():
		message += " (%s:%d)" % [file, line]
	if CrashReportText.is_exit_noise(message):
		return
	_reporter.report_crash(message)
