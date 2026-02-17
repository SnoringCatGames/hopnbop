class_name CostumeConfig
extends Resource
## Configuration for a single costume overlay. All
## costumes share the same sprite sheet template (same
## frame layout, size, and count) and work with all body
## types.


## Human-readable name for editor display.
@export var display_name: String = ""

## Overlay texture. Must use the same frame layout as
## the template AnimatedSprite2D in the animator scene.
## Null means no overlay (base body type only).
@export var sprite_sheet: Texture2D = null
