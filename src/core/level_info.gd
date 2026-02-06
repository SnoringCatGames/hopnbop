class_name LevelInfo
extends Resource


## Unique identifier (e.g., "default_level", "forest_arena").
@export var id: StringName = ""

## Human-readable display name (e.g., "Classic Arena").
@export var display_name: String = ""

## The level scene to instantiate.
@export var scene: PackedScene = null

## Minimum players required for this level.
@export var min_players: int = 2

## Maximum players supported by this level.
@export var max_players: int = 4

## Whether this level is available for selection.
@export var is_enabled: bool = true
