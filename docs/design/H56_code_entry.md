# H56: controller players cannot enter codes

## Problem

Joining a party by its 6-character code (alphabet
`23456789ABCDEFGHJKLMNPQRSTUVWXYZ`, 32 symbols) and adding
a friend by code both end at a `TextInputRow`, which needs
a physical keyboard. A gamepad-only player cannot enter a
code at all. Related polish from the same audit row
(`H37_systems_audit.md` 3.2, finding 13): forward rows in
these panels lack the chevron affordance, rows are not
mirrored for Arabic (RTL), and the Join-with-code icon is
the wrong one.

## Options

1. **On-screen symbol grid of MenuRows.** Rows of four
   symbols each; U/D moves between rows, L/R within a row,
   Trigger types the symbol. It reuses the universal
   MenuRow focus contract, needs no new art (symbols are
   text), and works for every fixed-alphabet code. Cost:
   one new row class plus panel wiring; vertical space
   (8 rows) in a side panel that scrolls.
2. **Cycle-per-character fields.** One row per code slot,
   L/R cycles that slot's symbol. Fewer rows (6) but 32
   presses worst case per slot; slower and fiddlier.
3. **Virtual keyboard scene (QWERTY).** Most general, most
   work, and oversized for a 32-symbol alphabet with no
   lowercase.

## Recommendation

Option 1, built behind `is_code_keyboard_enabled`
(default off) so Levi can accept it by eye before it
ships: eight `CodeKeyboardRow`s (four symbols each) under
the text field in the Join-by-code panel, plus a delete
row reusing the text row's own editing. The same row
class drops into Add-friend later without new design.
Chevrons: set `show_chevron` on the forward rows this
change touches. RTL mirroring and the Join-with-code
icon stay follow-ups: the icon needs Levi's pick, and RTL
needs an Arabic layout pass across all panels, not one.

## How it would be tested

- GUT: a `CodeKeyboardRow` emits the selected symbol on
  trigger, L/R moves the selection and clamps/wraps at
  the row ends; the panel (setting on) appends typed
  symbols to the code field and enables Join at 6.
- Harness: lobby run with the setting on, screenshots of
  the Join-by-code panel driven by gamepad-direction
  steps, sent to Levi for acceptance. It stays off by
  default until he accepts it.
