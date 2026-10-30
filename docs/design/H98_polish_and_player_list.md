# H98: finish T43; verify, then fix, T19

## Problem

Two leftovers from the audit's polish batch:

- **T43** is a by-eye polish list (toasts, game over,
  friends, auth). Its code halves landed as H18 and H31;
  what remains is Levi looking at it, not more code.
- **T19** (verify first): the in-match PlayerDisplay list
  covers the playfield. `src/ui/hud/hud.gd` picks a
  vertical list at the right when the window aspect is at
  least 1.3, else a horizontal list at the bottom. Each
  display is at least 180x90 with 20 px separation and no
  wrap or scale logic. Observed with one player
  (`docs/design/H37/h37-triage.md` V28): the vertical
  panel sits over the level's right wall at 1360x765, the
  horizontal one covers floor at 1100x900. Inferred for
  four players: the stack covers the right-hand platforms
  at 16:9, and four across need about 780 px. Not yet
  checked: four players, party members, live resizing,
  web or mobile.

## Options (T19)

1. **Shrink and cap.** Scale displays down as the count
   grows (4-up gets ~0.75 scale) and cap the list's share
   of the screen. Smallest change, keeps both layouts,
   still overlays the same corners, just smaller.
2. **Move the list off the playfield.** Anchor the
   vertical list over the HUD margin the levels already
   reserve, or fade it to a corner strip. Needs level-by-
   level checks that the margin exists everywhere.
3. **Collapse to a compact strip.** Replace full displays
   with name-plus-avatar chips during play, full display
   on the game-over screen (where PlayerDisplay already
   shines). Most UI work, best playfield, changes what
   players glance at mid-match.

## Recommendation

Verify first, as the item says: capture the list at
1360x765, 1100x900, and a portrait phone size with four
players (needs the harness's >2-client support, H76/H78,
or a local 4-instance editor run). If the stack covers
platforms as inferred, take option 1 (scale by count,
cap at 40% of the short edge) as the fix and keep option
3 for Levi's call, since it changes mid-match
information design. T43 closes by Levi's eye pass over
the H18/H31 surfaces; no code is proposed for it here.

## How it would be tested

- Harness (or editor) screenshots at the three sizes with
  four players, before and after, judged by eye against
  the playfield corners in V28.
- A GUT test on the scale-by-count rule (pure function of
  player count and viewport size) if option 1 lands.
- Live resize during a match: the list reflows without
  covering the respawn area.
