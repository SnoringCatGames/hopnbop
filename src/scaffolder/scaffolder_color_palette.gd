@tool
class_name ScaffolderColorPalette
extends Resource
## A palette of colors for theming.


@export var colors: PackedColorArray = []


func get_color(index: int) -> Color:
    if index < 0 or index >= colors.size():
        return Color.WHITE
    return colors[index]


func get_color_count() -> int:
    return colors.size()
