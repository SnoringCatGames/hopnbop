# H123: Muse run 4, follow-ups to run 3

Brief for Muse's fourth run (Muse Code through Paseo), written by Claude
(claude session 0cfd9cf1) on 2026-10-30. Claude sends it, not Levi.
It holds the coordinator's review follow-ups to run 3 (H120): the H119
key trace, which prints nothing on default settings yet; SP102, the
SP90 auth-store guard on the consent path; SP105, Go line endings;
SP103 and SP104, the SP88 review residuals; and a logging check on
H115's delete-panel change.

How to use it: work section 2 top to bottom, one item at a time. A
fresh session resumes from this file, ledger item H123 and
`git log --oneline -15` in hopnbop and the platform. Re-read this file
after a compaction. Path shorthand as in H103: `sdk:`, `rt:`, `net:`.

## 1. Rules

- H120's sections 1, 3 and 4 (`docs/design/H120_muse_run3.md`) apply,
  with H123 in place of H120 and this file's section 5 in place of
  H120's. That carries over the commit and push grant, the public-repo
  rule, the one-writer rule and every gate.
- The released-client gate (H120 section 3) now means 0.57.0, the live
  release (`7fd873fd`): run its compliance suite the way
  `docs/design/H108_compat.md` does for 0.56.0. Keep 0.56.0 in the gate
  while `version_check` still accepts its protocol.
- Add `gofmt -l` over `runtime/` to the pre-push checks (H103 1.4),
  once 2.3 makes it trustworthy on this checkout. aa3dc13 skipped it and
  failed the deploy's gofmt gate.
- **No release.** Everything here reaches players with the next client
  release, and that needs Levi's OK. **No prod actions** (H103 1.3):
  Claude runs any prod check you need; ask in the handoff log.
- Claude's Paseo messages can be lost: three were dropped on
  2026-10-30 while the daemon was wedged. This file is the authority.
  A message changes it only when the message says so.

## 2. Work order

### 2.1 H119: make the key trace capture something

As committed (`2d28d3cc`), the trace most likely prints nothing, so a
playtest can't capture anything yet. Fix it on main.

a. **It is filtered out.** The dump goes through `Netcode.print` with
   `CATEGORY_PLAYER_ACTIONS`, which `settings.gd:293` lists in
   `excluded_log_categories` by default (`settings.tres` doesn't
   override it; `main.gd:9` applies the filter). Log it so it appears
   on default settings. Prove it with a harness run on stock settings
   that forces a dump, then find the `H119TRACE` line in that run's
   log.
b. **Its triggers miss the likely failure.** Both need Godot to still
   think A is held (`Input.is_physical_key_pressed(KEY_A)`). On the
   keyboard-partition path, move_left IS that call
   (`input_device_manager.gd:145`), so "move_left released while A
   held" can only fire through `is_text_input_captured`. The echo replay
   shows the game handles a held A, so the likely failure is that Godot
   stops believing A is held: a key-up reaches Godot while the finger
   is still down, or a focus change clears the pressed keys with no key
   event. Neither case dumps today. Add:
   - a dump when a pressed echo event arrives for a traced key that
     Input reports as up (the OS still repeats a key Godot thinks is
     released);
   - a dump when move_left goes false while the last A event in the
     ring is a press (a release with no key-up event);
   - ring notes for app and window focus out/in, for
     `is_text_input_captured` changes, and for which path the player
     polls (the partition name, or the InputMap);
   - key recording in `_input` instead of `_unhandled_key_input`, so
     events a Control consumes still show.
   Keep one dump per hold and the per-frame cost as it is. Unit-test
   the two new triggers.
c. **Only A fails.** Levi: kanata off, holding D keeps moving right,
   the Left arrow is fine, lobby and match alike. List everything else
   that reads physical A or an action bound to it (InputMap entries,
   shortcuts, UI and dev-key handlers) and say in the handoff log
   whether any of it could release or consume A.
d. **Ledger.** H119's entry says where Levi finds the log: from a local
   run (the exact steps), and from a released build (the native log
   file path; the browser console on web). Add that the trace is
   removed once H119 is diagnosed. Its next step asks Levi for a log
   only after this item lands.

### 2.2 SP102: the SP90 auth-store guard on the consent path

8832a3b (bumped in `73aa04fd`, after the 0.57.0 artifacts, so not yet
with players) moves an unreadable auth file aside in
`login_anonymous()`, and its migration test covers that call alone. On
the normal startup path the move-aside never protects the old file:

- Startup always goes splash, then consent, then sign-in
  (`scg_splash_screen.gd:23`, `consent_screen.gd:69`). The consent
  screen's Continue and its auto-skip both call `save_tokens()`
  (`consent_screen.gd:459` and `:468`). With an unreadable file, that
  save writes over it before `login_anonymous()` runs, so the old guest
  identity is lost (SP44). `login_anonymous()` then still sees
  `load_failed` and moves the fresh consent-only file aside instead.
- A failed move in `login_anonymous()` falls through to `save_tokens()`
  and writes over the file anyway.

Fix:

- Put the guard in `save_tokens()`: when `load_failed` and the file
  exists, move it aside first, and write nothing if the move fails.
  `login_anonymous()` then keeps only its status message.
- Give the aside file a unique name. A rename replaces an existing
  `auth.cfg.unreadable`, so a second unreadable file destroys the
  first.
- Test: an unreadable auth file, then the consent save, then guest
  sign-in. The aside file must hold the original bytes, and the new
  auth file must load.
- Nit in the same area: `_do_anon_auth` clears `_is_refreshing` on its
  two failure paths but never sets it. Drop those two lines.

Bump hopnbop's platform pointer in the same change (it trails at
`92c7ddf`).

### 2.3 SP105: Go files check out with LF

In this Windows checkout `gofmt -l` flags every `.go` file on CRLF line
endings alone, which hid aa3dc13's real problem until the deploy gate
caught it (fixed in 102d418). Add a platform `.gitattributes` with
`*.go text eol=lf`, refresh the checkout's `.go` files so they are LF
on disk, and confirm that `gofmt -l runtime` lists nothing and
`git status` is clean. No runtime code changes, so no deploy.

### 2.4 SP103 and SP104: the SP88 review residuals

SP88 (03884fa, live) is right otherwise: the update hook works, and the
client matches on none of the changed error texts. Fix these when you
touch `rt:account_validation.go`, one runtime item per push:

- **SP103.** `clampDisplayName` returns "" both when the name complies
  and when nothing is left after cleaning, so the after-auth hook keeps
  an imported name made only of invisible characters. The clamp also
  skips the letter-or-digit rule, so an imported name like "!!!" or an
  emoji-only name passes sign-in but is refused if a later update
  resends it. Make the clamp's output pass `validateDisplayName`, and
  decide what an imported name with nothing valid left becomes.
- **SP104.** Refusing every Cf character also refuses ZWNJ and ZWJ,
  which ordinary Persian and Indic names need (and ZWJ emoji
  sequences). Check the supported locales. If none needs them, record
  it as a known limit in SP104 and close it; otherwise allow them where
  a script needs them.

### 2.5 H115 follow-up: delete-RPC failures stay visible

4405cd3b lowered the delete panel's failure log to a warning. Offline
and an expired session are expected, but a server error is not:
account deletion is a compliance path, and the crash report was its
only automatic signal. prod-health-check counts Nakama log lines that
match error, panic or fatal (claude-config
`jobs/scripts/prod-health-check.ps1`, step 5). Check whether the
runtime's delete RPC logs its failures at error level. If it does, say
so in the handoff log. If it doesn't, keep the client's error level for
failures other than offline and an expired session, with a test.

## 3. Already reviewed: nothing to do

- SP96 test restore (aa3dc13, 102d418): it matches b8e20d5 apart from
  the two create tests replaced on purpose; the deploy is green.
- The SP87 follow-up answers (items 3, 5 and 6): accepted, no change.
- SP89 (7d39613): the routing is right, and "superseded" is safe for
  the game. Its `auth_completed` listeners ignore failures or, like
  `game_session_manager.gd:219`, check the token store.
- SP91: Claude verified it on prod. Leave it closed.
- H120's credentials note: Claude corrected it in the handoff log.

## 4. Reporting and stopping

H120's section 4, with H123 for H120 and section 6 here for the log.

## 5. Not in this run

- Everything in H120's section 5.
- H83's Facebook-avatar check: it needs Levi at a browser.
- Any client or game-server release, and any prod action.

## 6. Handoff log

Append one dated entry each time you stop.
