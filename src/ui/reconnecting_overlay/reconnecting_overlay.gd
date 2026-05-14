class_name ReconnectingOverlay
extends CanvasLayer
## Modal overlay shown to the local player during a
## mid-match reconnect attempt (Stage 7.10). Subscribes to
## the GamePanel's ReconnectHandler and displays a
## "Reconnecting..." message with a per-second countdown.
## Self-frees on reconnect success or failure.
##
## Layout is built programmatically because the structure
## is trivial (one centered VBox with two labels + a
## spinner) and a separate .tscn would add maintenance
## surface without payoff.

const _SPINNER_SCENE := preload(
	"res://src/ui/loading_spinner/loading_spinner.tscn")

var _label: Label
var _countdown_label: Label
var _spinner: LoadingSpinner


func _ready() -> void:
	# Sit above gameplay but below the toast overlay so
	# toasts can still surface (e.g., the success toast
	# from reconnect_succeeded). Toast overlay is at
	# layer 110 in the scene; we sit just below.
	layer = 100

	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.65)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	_spinner = _SPINNER_SCENE.instantiate()
	_spinner.scale = Vector2(4, 4)
	vbox.add_child(_spinner)

	_label = Label.new()
	_label.text = tr("RECONNECT.HEADER")
	_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER)
	_label.add_theme_font_size_override("font_size", 32)
	vbox.add_child(_label)

	_countdown_label = Label.new()
	_countdown_label.text = ""
	_countdown_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER)
	_countdown_label.add_theme_font_size_override(
		"font_size", 20)
	vbox.add_child(_countdown_label)


## Update the countdown label. Called by GamePanel on each
## reconnect_attempt tick.
func update_countdown(sec_remaining: float) -> void:
	_countdown_label.text = tr(
		"RECONNECT.COUNTDOWN") % int(
			ceil(sec_remaining))
