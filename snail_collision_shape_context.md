# Snail Collision Shape Context

## Tile Collision Geometry Change (2026-03-21)

The TileSet used by CollisionTiles was refactored. Terrain indices
are now: normal=0, platform=1, ice=2. The collision geometry also
changed: ceiling surfaces (the bottom edge of tile collision shapes)
are now 4 pixels above the tile boundary.

Tile collision shapes in `default_tile_set.tres`:
- Top/bottom cap tiles: `(-8, -8, 8, -8, 8, 4, -8, 4)` -- bottom
  edge at y=4 (4px above tile boundary at y=8).
- Full interior blocks: `(-8, -8, 8, -8, 8, 8, -8, 8)` -- bottom
  edge at y=8 (tile boundary). These tiles never have an exposed
  ceiling face because they are sandwiched between other tiles.

In practice, every tile with an exposed ceiling face uses the cap
shape, so all ceiling surfaces are 4px above the tile boundary.

## Snail Surface-Following Fix

The snail (`src/objects/snail/snail.gd`) follows tile surfaces using
tile coordinates, face enum, and progress along the face. The visual
position is derived in `_update_visual()` by offsetting from the tile
center along the face normal.

Previously, all faces used `Level.TILE_SIZE / 2.0` (8px) as the
normal offset. With the ceiling inset, `Face.BOTTOM` now uses
`TILE_SIZE / 2.0 - _CEILING_INSET` (4px).

Changes made:
- Added `const _CEILING_INSET := 4.0` to `Snail`.
- `_update_visual()`: BOTTOM face normal offset reduced from 8 to 4.
- `_advance()` trail corner positions: when leaving a BOTTOM face at
  a concave corner, the normal component of the corner vertex uses
  the same 4px inset.

Floor (TOP), wall (LEFT/RIGHT) surfaces are unaffected. Their
collision edges are at the tile boundary.
