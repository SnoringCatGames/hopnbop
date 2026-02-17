class_name GoreTrailParticle
extends Sprite2D
## Visual-only trail particle that shrinks through
## texture sizes over time. Lifecycle managed entirely
## by GoreManager.
##
## Client-side only. Not networked or rollback-aware.


## Trail particle speed as a fraction of the spawning
## chunk's speed at the moment of creation.
const SPEED_MULTIPLIER := 0.5

## Index into the trail texture array (0 = largest).
var size_index := 0

## Whether this trail renders behind players.
var is_behind := false

## Time accumulated since last size step.
var elapsed := 0.0

## Velocity inherited from the spawning chunk.
var vel := Vector2.ZERO
