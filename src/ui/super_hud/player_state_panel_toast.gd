class_name PlayerStatePanelToast
extends PanelContainer


@export var text := "":
    set(value): %Label.text = value
    get: return %Label.text
