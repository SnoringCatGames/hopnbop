# H98: finish T43; verify, then fix, T19

## Problem

Two leftovers from the audit's polish batch:

- **T43** is a by-eye polish list (toasts, game over,
  friends, auth). Its code halves landed as H18 and H31.
  What remains is Levi looking at it, not more code.
- **T19** (verify first): the in-match PlayerDisplay list
  covers the playfield. `src/ui/hud/hud.gd` picks a
  vertical list at the right when the window aspect is at
  least 1.3, else a horizontal list at the bottom. Each
  display's inner box is at least 180x90 with 20 px
  separation and no wrap or scale logic. The rendered
  display is bigger than that minimum. Measured
  2026-11-02 in offline harness runs at four window
  sizes (one display, `eval` of the visible list's and
  one display's `size` and `global_position`): the
  visible display is 204x173 at every size, and the
  list with one display is the same. Four and eight
  below are derived from that size and the 20 px
  separation. The HUD is a CanvasLayer outside the game
  viewport. Nothing scales UI with the window, while
  the playfield zooms to fit the base area. So the
  display stays 204x173 physical pixels at every size,
  and its share of the screen depends on the window
  size, not only its aspect.

  | Window | One display (measured) | Four stacked (derived) | Share of height |
  |---|---|---|---|
  | 1280x720 | 204x173 at (1060, 16) | 752 px | 104% |
  | 1360x765 | 204x173 at (1140, 16) | 752 px | 98% |
  | 1920x1080 | 204x173 at (1700, 16) | 752 px | 70% |
  | 2560x1440 | 204x173 at (2340, 16) | 752 px | 52% |

  Four stacked is 4x173 + 3x20 = 752 px. Eight stacked
  (derived) is 1524 px. Four across (derived) is
  4x204 + 3x20 = 876 px. With the HUD's 16 px margins
  the four stack starts at y 16 and runs past the
  bottom at the two smaller sizes. Observed with one
  player (V28): the vertical panel sits over the
  level's right wall at 1360x765, the horizontal one
  covers floor at 1100x900. Matches cap at four, but
  the layout must handle eight. The list is built for
  eight, every level declares eight, a client can hold
  four local players, and in the lobby remote party
  members add nameplates. Covering means the list's
  rect sits over a spawn point or a platform. Live
  resizing reflows in code. Only the look is unchecked.
  Not yet checked: four and eight displays, party
  members, live resizing by eye, web or mobile.

The adjective reveal is a constraint on any T19
change. As H130 leaves it, the reveal freezes every
list and pops each new adjective over the visible
list's display. H130 holds the bug and the fix. This
doc only says what each option does to that reveal.

## Options (T19)

The cap below is the list's length along its axis
over the window edge it runs along. For the vertical
list that is stacked height over window height. For
the horizontal list it is row width over window width.

1. **Shrink and cap.** Shrink displays as the count
   grows and cap the list at 40% along its axis. At
   1360x765 the cap is 306 px. Four displays then get
   (306 - 60) / 4 = about 62 px of height each, a
   ratio of about 0.36 against 173 px. Eight get
   about 21 px each, a ratio of about 0.12. Shrinking
   means smaller minimum, font and icon sizes inside
   PlayerDisplay. It does not mean a scale factor.
   Both lists are BoxContainers, and containers lay
   children out by size and reset a child's scale
   (inferred for 4.7.2). At those ratios the name and
   score text is likely too small to read (inferred),
   so this option alone may not hold past two or
   three players. It keeps both layouts and still
   overlays the same corners, just smaller. For the
   reveal, it shrinks the label the popup sits on.
   The popup keeps its own size, so it covers more
   of the smaller display.
2. **Move the list off the playfield.** Anchor the
   vertical list over a level's edge strip. No code
   reserves a HUD margin in the levels. The only
   margin is the HUD's own 16 px. What exists is a
   level narrower than 16:9. Dark strips of about
   105 px at each side at 1360x765, and about 100 px
   below at 1100x900 (V28, measured on the images).
   That is about half a display's width, measured
   per level. So this option also needs a smaller
   display. It is option 2 plus option 1 or 3. Needs
   level-by-level checks that the strip exists
   everywhere. For the reveal, the popup moves with
   its display. It still pops over the visible
   display, wherever the list sits.
3. **Collapse to a compact strip.** Replace full
   displays with name-plus-avatar chips during play.
   Most UI work, best playfield, changes what players
   glance at mid-match. The game-over screen does not
   use PlayerDisplay. It builds its own result rows
   with add-friend buttons. A full display there
   would be new UI on a focus-navigated screen. The
   rows' add-friend buttons must stay in the
   navigator's list, and Left must still return to
   the lobby. PlayerDisplay itself is non-interactive,
   so it needs no focus entries. Size: L (inferred).
   For the reveal, chips leave no full display to
   pop over. The reveal would need a new home, or a
   chip that expands for it.

## Recommendation

Verify first, as the item says: capture the list at
1280x720, 1360x765 and 1920x1080 with four and eight
displays, and in the lobby with a full party plus
local players. Capture at the Pixel's landscape
resolution as a legibility check. The Android build
sets no orientation, so it runs landscape (inferred).
Portrait arises only in a phone browser, which
cannot be played without a gamepad. Note that H10's
touch controls will compete with the list for the
same screen edges. The harness already takes a
client count, but match mode caps it at two today.
Cheaper routes (inferred): four local players on one
client, or an `eval` step that adds displays. Try
those before asking for more clients. H76 is more
than two clients and gamepad input. H78 is golden
screenshots. Neither blocks these captures.

If the stack covers platforms as measured, take
option 1 up to two or three players and a compact
display past that count. The numbers do not support
option 1 alone at four or eight. Keep option 3 for
Levi's call, since it changes mid-match information
design. Make the shrink rule depend on the window
size as well as the count, or file UI scaling for
large screens as its own item. T43 closes by Levi's
eye pass over the H18/H31 surfaces. No code is
proposed for it here.

Size for the pair: M. V28 sizes it S to look, M to
move the panel.

Pictures for Levi's two looks are agent work still
to do (H143). Do not wait on them to decide the
shrink rule. The rule is settled by the layout test
below.

## How it would be tested

- First step of any option: a layout test that
  instantiates `hud.tscn` at 1360x765 with four and
  eight displays and asserts that the visible list's
  rect stays inside the cap. It fails today (about
  752 px against 306) and passes after. Do not write
  it as part of this doc. It is the first step of
  whichever option lands. A companion test asserts
  the celebration reads the visible list. H130 wrote
  that one. It fails on the old code.
- Harness (or editor) screenshots at 1280x720,
  1360x765 and 1920x1080 with four and eight
  displays, before and after, judged by eye against
  the playfield corners in V28. Add a capture during
  the adjective reveal.
- A GUT test on the scale-by-count rule (pure
  function of player count and viewport size) if
  option 1 lands.
- Live resize during a match: the list reflows
  without its rect over a spawn point or a platform.

Anything here to fix? (T43 captures of toasts, game
over, friends and auth.)

Which reads best mid-match: smaller full displays or
compact chips? (T19 before-and-after captures at four
and eight displays, side by side.)
