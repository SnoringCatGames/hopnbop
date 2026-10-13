---
paths:
  - "src/ui/**"
  - "src/level/**"
  - "src/core/pixel_viewport_manager.gd"
  - "src/core/sign_out_router.gd"
  - "src/core/screens_main.*"
  - "assets/images/gui/**"
---

# UI and presentation lore

UI patterns, the sign-out flows, and the viewport/camera rules, moved
verbatim from CLAUDE.md by H34 (2026-10-13). CLAUDE.md keeps the
navigation requirement and the MenuRow contract summary.

## Navigation

All interactive UI elements must be navigable with U/D and
L/R controls. Players use gamepads or keyboard. UI that only
responds to mouse/touch is not acceptable.

## Input contract (Trigger / Right / Left)

`MenuRow` (`src/ui/menu_row.gd`) is the universal focusable
row widget. It's used by SidePanel rows AND, increasingly, by
Screen buttons (auth, anonymous-upgrade, game-over). The
contract is:

- **Trigger button** (Enter / Space / gamepad trigger): fires
  the row's `on_trigger()`.
- **Right input**: fires `on_trigger()` (same as Trigger).
- **Left input**: routes to the **panel/screen back action**,
  NOT the row. SidePanel calls `manager.pop_panel()`; Screens
  call `on_back()` (default no-op; subclasses override —
  game-over returns to lobby, anonymous-upgrade dismisses,
  leaderboard closes, etc.).
- **Mouse click** on the row body: fires `triggered` signal
  + `on_trigger()`.

Two exceptions opt out of the "Left = back" rule by overriding
`consumes_horizontal_input() -> true`:

- `LevelPrefRow` (tristate cycle): Left cycles state backward
  (PREFERRED → INCLUDED → EXCLUDED), Right cycles forward.
- `BinaryToggle` (standalone PanelContainer used in screens):
  Left picks option 0, Right picks option 1.

Both define `on_trigger()` as an alias for `on_right()` so the
keyboard trigger key still works.

## Side panels

`SidePanel` subclasses scan `_row_container.get_children()`
for `MenuRow` instances; non-MenuRow children (spacers,
labels) are ignored. Call `_connect_row_clicked(row)` for
each row and `rebuild_row_list()` after dynamic content
changes.

For dynamically generated rows that don't need a scene file,
use `ActionRow` (extends `MenuRow`). Call
`setup_action(callback)` with a single callable for the
row's `on_trigger()` action. Example:

```gdscript
var row := ActionRow.new()
var content := HBoxContainer.new()
content.mouse_filter = Control.MOUSE_FILTER_IGNORE
row.add_child(content)
# ... add labels/buttons to content ...
row.setup_action(action_callback)
_row_container.add_child(row)
_connect_row_clicked(row)
```

## Right-side chevron affordance

Set `row.show_chevron = true` on rows that navigate forward
into a sub-view (sub-panel, sub-screen, URL). The base class
toggles a child `TextureRect` with unique name `%Chevron` if
present. `SubPanelTriggerRow`, `ScreenTriggerRow`, `LinkRow`,
and `CreditsRow` set this in their `_ready()` by default.
Programmatic ActionRow callers can also set it per-instance.

## Screens

`Screen` subclasses using `ScreenFocusNavigator` route input
through `_navigator.poll(delta)`. After a true return,
inspect `_navigator.last_activation_direction`:

- `0` (Trigger) → `_activate_focused()` (fire focused button).
- `1` (Right) → same as Trigger for non-horizontal-consumer
  controls; for horizontal-consumer controls (e.g., a
  BinaryToggle), call the control's `on_right()`.
- `-1` (Left) → `on_back()` (or the focused control's
  `on_left()` if it consumes horizontal input).

All interactive buttons must be in the focusable list via
`_navigator.set_focusable_list(items)`. Dynamically created
buttons (e.g., friend action buttons in result rows) must
also be added.

## Mid-session sign-out

The platform SDK signs the player out on its own when Nakama
rejects the stored refresh token (expired or revoked session,
banned or deleted account) and emits `Platform.auth.signed_out`.
`SignOutRouter` (`src/core/sign_out_router.gd`, owned by
ScreensMain on clients) then sends the player to the auth
screen, the one a fresh launch shows:

- From the lobby, or a screen opened over it: at once. The
  lobby is torn down, as on log-out.
- During a match, local or online, or matchmaking: nothing is
  interrupted, and the results screen still shows. The auth
  screen then opens instead of the lobby
  (`ScreensMain.client_open_screen` runs every switch through
  `SignOutRouter.resolve_screen`) and instead of any new online
  match (`GamePanel._client_client_request_session_ids` checks
  `G.screens.is_sign_in_required()`).
- From splash, consent, or auth: the boot flow gets there.

Harness scenarios: `sign-out-lobby`, `sign-out-local-match`,
`sign-out-play-again`.

Every way out ends the session the same way. Log-out
(`SignOutRouter.log_out()`, behind Settings, Log Out), account
deletion (`finish_account_deletion()`), an automatic sign-out
(when the auth screen opens), and the auth screen's launch-time
rejection all run `SignOutRouter.clear_session_state()`. It
closes menus and dialogs, drops profile pictures and the friend
and presence caches, resets the party, stops the friends poller,
and closes the realtime notification socket, which is
authenticated as the old account. The next successful sign-in,
guest or provider, starts the poller again
(`FriendsNotificationPoller._on_auth_completed`); while stopped
it drops whatever still arrives for the old session. The next
provider sign-in opens a socket for the new account. Harness
scenario: `log-out-sign-in-cycles`.

At launch, the auth screen refreshes an expired session before
letting the player in. Only a refresh token that Nakama rejects
signs them out there (SDK 0.5.6). Any other failure (network
error, timeout, 5xx, a response that isn't from Nakama) keeps the
session: the screen emits `continued_offline`, AuthScreen toasts
`TOAST.SESSION_KEPT_OFFLINE`, the player continues to the lobby,
and the auth client keeps retrying in the background. Harness
scenario: `session-kept-offline`.

Starting an online match refreshes an expired session first
(`GameSessionManager.client_request_session`). A failure that
may be transient sends the player back to the lobby, still
signed in, with the same `TOAST.SESSION_KEPT_OFFLINE`. A
rejection signs them out, and the lobby gives way to the auth
screen, which toasts `TOAST.SIGNED_OUT`. Harness scenario:
`session-refresh-before-match`.

Consent (the acceptance time and the legal version accepted)
lives on the device, in the token store's encrypted file. Log-out
and account deletion forget it
(`PlatformAuthTokenStore.clear_tokens()`), so whoever plays next
on the device is asked. An automatic sign-out keeps it
(`clear_session()`, SDK 0.6.2), so the same player is not asked
again. It is asked for again whenever the legal version changes.
Harness scenario: `consent-kept-after-sign-out`.

## Button icons

Use pixel-art icons in most buttons. All icon buttons must use
the same scale from Settings:

```gdscript
button.expand_icon = true
button.add_theme_constant_override(
    "icon_max_width",
    int(G.settings.get_icon_display_width()))
```

Icon assets live in `assets/images/gui/`. When a new feature
needs an icon that doesn't exist yet, ask for one. Do not
ship buttons without icons or use placeholder text where an
icon is expected.

## Viewport and camera (src/core/pixel_viewport_manager.gd)

`PixelViewportManager` sizes the `SubViewportContainer` to
fill the window at the nearest integer pixel scale and adjusts
the active camera's zoom so the base viewport area is always
visible.

**Camera anchor mode:** Godot 4.5 defaults Camera2D to
`FIXED_TOP_LEFT`. PVM sets `ANCHOR_MODE_DRAG_CENTER` on
first contact so extra viewport space is distributed
equally on all sides. Do not use `camera.offset` to "fix"
centering. `DRAG_CENTER` already centers the view.

**Camera activation:** Each level has a static `level_camera`
(Camera2D). Because `queue_free` on the previous level is
deferred, the new level's camera enters the tree while the
old camera is still alive and current. Auto-activation
only triggers when no current camera exists, so the new
camera must call `make_current()` explicitly. This is done
in `_server_spawn_level` and `_client_on_level_spawned`.

**Camera change detection:** PVM forces a
`_on_window_resized()` call when the active camera changes
(the `size_changed` signal can miss resizes during scene
teardown/setup). `_last_camera` must be set before calling
`_on_window_resized` to prevent mutual recursion
(`_on_window_resized` → `_update_camera_zoom` →
`_on_window_resized`).

**No per-player camera:** The bunny has no Camera2D. The
level camera is used for everything, including the
end-of-match celebration (which tweens the level camera's
`offset` to follow the winner).
