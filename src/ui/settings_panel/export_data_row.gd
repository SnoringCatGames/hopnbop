class_name ExportDataRow
extends SettingsRow
## A row that exports all player data as JSON.


var _panel: SettingsPanel
var _is_busy := false

@onready var _label: Label = %Label


func setup(panel: SettingsPanel) -> void:
	_panel = panel


func _ready() -> void:
	super()
	_label.text = "Export My Data"


func on_left() -> void:
	_activate()


func on_right() -> void:
	_activate()


func _activate() -> void:
	if _is_busy:
		return
	_is_busy = true

	G.auth_client.export_completed.connect(
		_on_export_completed, CONNECT_ONE_SHOT,
	)
	G.auth_client.export_player_data()


func _on_export_completed(
	success: bool,
	error: String,
	data: Dictionary,
) -> void:
	_is_busy = false

	if is_instance_valid(_panel):
		_panel.close()

	if not success:
		G.log.error(
			"Data export failed: %s" % error,
		)
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				"Export failed: %s" % error,
				ToastOverlay.Type.ERROR,
			)
		return

	# Save JSON to user://export/.
	var dir_path := "user://export"
	DirAccess.make_dir_recursive_absolute(dir_path)
	var timestamp := int(
		Time.get_unix_time_from_system()
	)
	var file_name := (
		"hopnbop_export_%d.json" % timestamp
	)
	var file_path := "%s/%s" % [dir_path, file_name]
	var file := FileAccess.open(
		file_path, FileAccess.WRITE,
	)
	if file == null:
		G.log.error("Export: failed to save file")
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				"Failed to save export file",
				ToastOverlay.Type.ERROR,
			)
		return

	file.store_string(
		JSON.stringify(data, "\t")
	)
	file.close()

	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			"Data exported successfully",
			ToastOverlay.Type.SUCCESS,
		)

	# Open the export folder.
	var global_path := (
		ProjectSettings.globalize_path(dir_path)
	)
	OS.shell_open(global_path)
