class_name ExportDataRow
extends MenuRow
## A row that exports all player data as JSON. On desktop the file
## is saved to user://export and the folder opened; on web, where
## user:// is browser storage the player can't reach, the browser
## downloads it.

## Where desktop exports are saved.
const EXPORT_DIR := "user://export"
const _EXPORT_FILE_FORMAT := "hopnbop_export_%d.json"
const _EXPORT_MIME_TYPE := "application/json"
## Indent for the fallback re-encoding below.
const _JSON_INDENT := "\t"

var _panel: SidePanel
var _is_busy := false
var _icon_texture: Texture2D

@onready var _icon: TextureRect = %Icon
@onready var _label: Label = %Label


## Set an icon to display before the label. Call
## before add_child().
func set_icon(tex: Texture2D) -> void:
	_icon_texture = tex


func setup(panel: SidePanel) -> void:
	_panel = panel


func _ready() -> void:
	super()
	_label.text = tr("SETTINGS.EXPORT_DATA")
	_apply_icon(_icon, _icon_texture)


func on_trigger() -> void:
	_activate()


## The export file's name for a unix time.
static func export_file_name(unix_time: int) -> String:
	return _EXPORT_FILE_FORMAT % unix_time


## The export's text: the server's JSON exactly as sent. Re-encoding
## `data` is the fallback for an SDK that doesn't keep the text; it
## loses no fields, but Godot's JSON turns every number into a float.
static func export_text(server_json: String, data: Dictionary) -> String:
	if not server_json.is_empty():
		return server_json
	return JSON.stringify(data, _JSON_INDENT)


## Writes the export into EXPORT_DIR. Returns the saved path, or ""
## when the file couldn't be written.
static func save_export(text: String, file_name: String) -> String:
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	var path := "%s/%s" % [EXPORT_DIR, file_name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(text)
	file.close()
	return path


func _activate() -> void:
	if _is_busy:
		return
	_is_busy = true

	Platform.auth.export_completed.connect(
		_on_export_completed, CONNECT_ONE_SHOT,
	)
	Platform.auth.export_player_data()


func _on_export_completed(
	success: bool,
	error: String,
	data: Dictionary,
) -> void:
	_is_busy = false

	if (is_instance_valid(_panel)
			and is_instance_valid(_panel.manager)):
		_panel.manager.close_all()

	if not success:
		G.log.error(
			"Data export failed: %s" % error,
		)
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				tr("TOAST.EXPORT_FAILED"),
				ToastOverlay.Type.ERROR,
			)
		return

	var text := export_text(Platform.auth.last_export_json, data)
	var file_name := export_file_name(
		int(Time.get_unix_time_from_system()))

	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(
			text.to_utf8_buffer(), file_name, _EXPORT_MIME_TYPE)
		_show_success_toast()
		return

	if save_export(text, file_name).is_empty():
		G.log.error("Export: failed to save file")
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				tr("TOAST.SAVE_FAILED"),
				ToastOverlay.Type.ERROR,
			)
		return

	_show_success_toast()
	OS.shell_open(ProjectSettings.globalize_path(EXPORT_DIR))


func _show_success_toast() -> void:
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("TOAST.EXPORT_SUCCESS"),
			ToastOverlay.Type.SUCCESS,
		)
