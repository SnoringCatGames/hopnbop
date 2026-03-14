class_name ScreenTriggerRow
extends SettingsRow
## A row that opens a full Screen when activated.
## Used to display in-game legal doc screens from
## the info side-panel.


var _display_name := ""
var _screen_type := ScreensMain.ScreenType.UNKNOWN
var _panel: SidePanel
var _icon_texture: Texture2D

@onready var _icon: TextureRect = %Icon
@onready var _label: Label = %Label
@onready var _arrow: TextureRect = %Arrow


## Set an icon to display before the label. Call
## before add_child().
func set_icon(tex: Texture2D) -> void:
	_icon_texture = tex


func setup(
	display_name: String,
	screen_type: ScreensMain.ScreenType,
	panel: SidePanel,
) -> void:
	_display_name = display_name
	_screen_type = screen_type
	_panel = panel


func _ready() -> void:
	super()
	_label.text = _display_name
	_apply_icon(_icon, _icon_texture)
	_setup_chevron(_arrow)


func on_left() -> void:
	_open_screen()


func on_right() -> void:
	_open_screen()


func _open_screen() -> void:
	if _screen_type == ScreensMain.ScreenType.UNKNOWN:
		return
	var screen: LegalDocScreen = (
		G.screens.get_screen_from_type(
			_screen_type) as LegalDocScreen)
	if not is_instance_valid(screen):
		return
	screen.set_return_screen(G.screens.current_screen)
	_panel.manager.close_all()
	G.screens.client_open_screen(_screen_type)
