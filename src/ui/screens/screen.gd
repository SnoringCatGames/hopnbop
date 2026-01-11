class_name Screen
extends PanelContainer


func _enter_tree() -> void:
    if G.network.is_server:
        visible = false
        process_mode = Node.PROCESS_MODE_DISABLED
        return

    process_mode = Node.PROCESS_MODE_DISABLED if G.network.is_server else Node.PROCESS_MODE_ALWAYS
    _set_default_styling()


func _set_default_styling() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    theme = G.settings.default_theme
    add_theme_stylebox_override("panel", G.settings.screen_style_box)
