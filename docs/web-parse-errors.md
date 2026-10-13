# Web build parse errors: diagnosis playbook

Moved verbatim from CLAUDE.md by H34 (2026-10-13). The binding rule
(symptoms vs root cause; never "fix" with `.get()` rewrites) stays in
CLAUDE.md; this file holds the full playbook.

Web exports sometimes fail at boot with cascading parse errors
of this shape:

```
ERROR: Cannot get class ''.
   at: _instantiate_internal (core/object/class_db.cpp:587)
ERROR: Parameter "obj" is null.
   at: ensure_resource_ref_override_for_outer_load
       (core/io/resource_loader.cpp:1013)
SCRIPT ERROR: Parse Error: Could not resolve external class
member "settings".
   at: GDScript::reload (res://src/.../foo.gd:42)
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
ERROR: Failed to load script "res://src/.../bar.gd"
  with error "Compilation failed".
```

**The parse errors at the bottom are symptoms. The root cause
is the `Cannot get class ''` / `Parameter "obj" is null` block
at the very top of the boot log.** Every `Could not resolve
external class member "settings"` parse error downstream is a
consequence of `settings.tres` (or some other class-typed
resource) failing to load, which makes
`var settings: Settings = preload(...)` fail at parse time,
which makes every `G.settings.X` access fail.

**DO NOT "fix" these by rewriting `G.settings.X` to
`G.get("settings").get("X")`**. That destroys autocomplete,
intellisense, and static type checking project-wide and does
*not* address the root cause. We need typed GDScript; treat
the `.get()` pattern as an atrocity, not a fix.

The original "cyclic reference" framing (which used to live in
this section) was a misdiagnosis. The Godot 4.7-beta1 parser
DOES emit a real `Cyclic reference.` suffix when it detects an
actual class-resolution cycle — but that's a *different* error
than the bare `Could not resolve external class member`
messages we usually see. If the message says ``: Cyclic
reference.`` literally at the end, treat it as cyclic; if it
doesn't, look upstream for the `Cannot get class ''` block.

## Real causes seen so far

- **Stale GDExtension declaration.** `addons/X/X.gdextension`
  declares native libraries for desktop platforms but no
  `web.wasm32`, and `extensions_support=false` on the Web
  preset. On web load, Godot tries to instantiate the missing
  extension's classes from cached resource refs and emits the
  `Cannot get class ''` cascade. Fix: either remove the addon
  entirely (if it's no longer used — see the gamelift removal
  in commit `0b9b059`) or add an `exclude_filter` line for
  the addon directory in the Web preset of
  `export_presets.cfg` (see the webrtc exclude added in
  2026-05-04 — webrtc's classes are provided natively by the
  browser at runtime, so the GDExtension binaries shouldn't
  ship to web at all).
- **Stale `.godot/global_script_class_cache.cfg`.** A
  `class_name` was renamed or removed but the cache still
  carries the old entry; resource files referencing the old
  name fail with `Cannot get class ''`. Fix: close the editor,
  delete `.godot/global_script_class_cache.cfg`, reopen, let
  Godot rebuild. (Done in 2026-05-03 for the gamelift_session_
  manager registry leak.)
- **Resource file with broken script ref.** A `.tres` or
  `.tscn` `[ext_resource type="Script" ...]` block points at
  a UID/path whose script no longer registers the same
  `class_name`. Fix the resource file or the script.

## Investigation playbook

1. **Read the web log top-down, not bottom-up.** Find the
   *first* error in boot output. If it's `Cannot get class ''`
   at `_instantiate_internal`, that's your root cause — every
   `Could not resolve external class member` parse error
   below it is downstream noise.
2. Identify what class is being looked up empty. The wasm
   stack frames don't give source line info, so work backward
   from clues: which `[ext_resource]` or `[node type="..."]`
   in recently-changed `.tres`/`.tscn` files might reference a
   class that disappeared, was renamed, or comes from a
   GDExtension that isn't shipped on web.
3. Check for stale GDExtension declarations (`grep -r
   gdextension addons/`) and verify each is either web-
   compatible or excluded from the Web export preset.
4. If nothing in source/resources is suspicious, the cache is
   stale: regenerate `.godot/global_script_class_cache.cfg`.
5. Only after the upstream cascade is gone should you treat
   any remaining parse errors as real. They'll generally
   either disappear with the upstream fix or point at a real
   bug (e.g., a syntax error you can fix without touching the
   typed access pattern).

Desktop builds tolerate a lot more breakage than web does, so
"works in editor" is no signal. Always read the web boot log.

Upstream Godot tracker:
[godot#80877](https://github.com/godotengine/godot/issues/80877)
(meta-issue, 40+ linked).
