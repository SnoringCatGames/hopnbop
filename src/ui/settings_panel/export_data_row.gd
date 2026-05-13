class_name ExportDataRow
extends SettingsRow
## A row that exports all player data as JSON.


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


func on_left() -> void:
	_activate()


func on_right() -> void:
	_activate()


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
				tr("TOAST.EXPORT_FAILED") % error,
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
				tr("TOAST.SAVE_FAILED"),
				ToastOverlay.Type.ERROR,
			)
		return

	file.store_string(
		JSON.stringify(data, "\t")
	)
	file.close()

	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("TOAST.EXPORT_SUCCESS"),
			ToastOverlay.Type.SUCCESS,
		)

	# Open the export folder.
	var global_path := (
		ProjectSettings.globalize_path(dir_path)
	)
	OS.shell_open(global_path)
