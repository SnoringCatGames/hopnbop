# Viewport Centering Session Notes (2026-04-11 to 2026-04-12)

## Original Request

Reduce the `_ASPECT_RATIO_THRESHOLD` in `hud.gd` that toggles the
PlayerDisplay layout between bottom (horizontal) and right side
(vertical). Also fix viewport centering so the level geometry stays
centered when the viewport aspect ratio changes.

## Changes Made (committed)

### hud.gd
- Reduced `_ASPECT_RATIO_THRESHOLD` from `2.0` to `1.3`.
- Removed `_SIDE_PANEL_CAMERA_OFFSET_PX` constant and all
  `set_side_panel_offset` calls. The camera offset approach was
  wrong — it shifted the camera inside the viewport, pushing
  the level off-center.
- Added `_is_vertical_layout` tracking and a log line when the
  layout changes (aspect ratio included).

### pixel_viewport_manager.gd
- Removed the `_side_panel_offset_px` variable and
  `set_side_panel_offset()` method entirely.
- Added `camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER`
  when first encountering a camera. Godot 4.5 defaults to
  `FIXED_TOP_LEFT`, which pins the camera position to the
  top-left of the viewport. `DRAG_CENTER` pins it to the center,
  so extra viewport space (from non-base aspect ratios) is
  automatically distributed equally on all sides.
- Added a forced `_on_window_resized()` call when the active
  camera changes. The `size_changed` signal can miss resizes
  during lobby→match scene teardown/setup, leaving the
  SubViewport at a stale size. The camera-switch check ensures
  the viewport dimensions are always recalculated.
- Added diagnostic logging: `[PVM] Resize:` on every
  `_on_window_resized` call and `[PVM] Camera switched:` on
  camera changes (anchor mode, position, zoom, svp size, parent).

### bunny.tscn
- Removed the `CharacterCamera` (Camera2D) node entirely. It
  was stealing viewport focus from the level's static Camera2D
  when `enabled = true` was set during `_set_up_camera()`.

### bunny.gd
- Removed `%CharacterCamera.enabled = is_local_player` from
  `_set_up_camera()` (the node no longer exists).

### camera_shaker.gd
- Unchanged from original. Uses `camera.offset = Vector2.ZERO`
  on shake end. PVM does not manipulate `camera.offset`.

### match_end_celebration.gd
- **Needs update**: `_get_local_camera()` still references
  `%CharacterCamera` on the player. This will break now that
  the node is removed. Needs to be rewritten to use the level
  camera or another approach for the winner zoom effect.

## Current State / Remaining Issues

### Level camera positions
- **Lobby camera** (`lobby_level.tscn`): position `(-48, -58)`.
  This already works with `DRAG_CENTER` — the position happens
  to be near the center of the lobby level geometry.
- **Match level cameras** (`level_0.tscn` through `level_5.tscn`):
  positions like `(-128, -94)`, `(-128, -82)`, `(-112, -112)`,
  `(0, 0)`, etc. These were authored for `FIXED_TOP_LEFT` where
  the position represented the top-left corner of the designed
  view. With `DRAG_CENTER`, these positions become the viewport
  center, which is wrong — the level geometry appears off-center.
- **Fix needed**: Move each match camera to the center of its
  designed view area: `new_pos = old_pos + (227, 128)` where
  `(227, 128) = (1360/(2*3), 765/(2*3))` (half the base visible
  area at zoom 3 with base resolution 1360x765). This was
  attempted but reverted because it was combined with a
  conflicting `centering_offset` that doubled the shift.
- **Correct new positions** (to be applied WITHOUT any
  centering_offset code in PVM):

  | Level | Old position | New position |
  |-------|-------------|-------------|
  | 0     | (-128, -94) | (99, 34)    |
  | 1     | (-128, -82) | (99, 46)    |
  | 2     | (-128, 18)  | (99, 146)   |
  | 3     | (-128, -82) | (99, 46)    |
  | 4     | (-112, -112)| (115, 16)   |
  | 5     | (0, 0)      | (227, 128)  |
  | Lobby | (-48, -58)  | unchanged   |

### Viewport sizing during level transition
- When transitioning from lobby to match, the SubViewport size
  can shrink (e.g., from 1280x1080 to 640x645) without the
  `size_changed` signal firing. The forced
  `_on_window_resized()` call on camera switch was added to
  fix this. **Status: needs testing to confirm it works.**

### Diagnostic logging
- `[PVM] Resize:` and `[PVM] Camera switched:` logs are still
  in the code. Remove once centering is confirmed working.

## Key Learnings

1. **Godot 4.5 Camera2D default anchor_mode is FIXED_TOP_LEFT.**
   Despite some documentation suggesting DRAG_CENTER is the
   default, testing confirmed FIXED_TOP_LEFT is the actual
   default. Explicitly setting DRAG_CENTER is required.

2. **Camera.offset approach was wrong for DRAG_CENTER.** With
   DRAG_CENTER, extra viewport space is already centered. Any
   camera.offset shifts it OFF center. The centering_offset
   code that was added and removed multiple times was always
   wrong when combined with DRAG_CENTER.

3. **CharacterCamera steals viewport focus.** Setting
   `Camera2D.enabled = true` on the player's CharacterCamera
   makes it the active viewport camera, overriding the level's
   static Camera2D. The CharacterCamera has zoom 1.5 (not 3.0)
   and follows the player instead of framing the full level.

4. **SubViewport size can desync during scene transitions.**
   The `size_changed` signal doesn't always fire during
   lobby→match teardown/setup. Forcing a resize recalculation
   on camera switch fixes this.

5. **_base_resolution comes from project.godot** at
   `display/window/size/viewport_width=1360` and
   `viewport_height=765`, not the hardcoded defaults (1152x648)
   in PVM's `_ready()`.

## Failed Approaches (do not retry)

- **camera.offset centering**: Computed offset to redistribute
  extra viewport space. Was always zero in the width-limited
  regime (user's typical window), and WRONG for DRAG_CENTER
  mode (pushes already-centered view off-center).
- **Container position shift**: Shifted the SubViewportContainer
  position instead of camera offset. Same problem — content was
  already centered by DRAG_CENTER.
- **CharacterCamera.make_current()**: Made the player camera
  active, breaking the level-framing zoom and fixed camera view.
- **Setting anchor_mode every frame**: No benefit over
  setting once; the issue was viewport sizing, not anchor_mode
  being reset.
