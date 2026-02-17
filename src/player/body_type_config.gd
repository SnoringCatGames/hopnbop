class_name BodyTypeConfig
extends Resource
## Configuration for a single body type. All body types
## share the same sprite sheet template (same frame
## layout, size, and count).


## Human-readable name for editor display.
@export var display_name: String = ""

## Sprite sheet texture. Must use the same frame layout
## as the template AnimatedSprite2D in the animator scene.
@export var sprite_sheet: Texture2D = null
