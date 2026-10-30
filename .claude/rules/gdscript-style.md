---
paths:
  - "**/*.gd"
  - "**/*.tscn"
  - "**/*.tres"
---

# GDScript and scene-file style

The full code-style rules, moved verbatim from CLAUDE.md by H34
(2026-10-13). Follow the
[Godot GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
with the project-specific additions below.

## Formatting

- **Indentation:** Tabs (4-space width), enforced by
  `.editorconfig`.
- **Line length:** 80 characters maximum.
- **Blank lines:** Two blank lines between functions/methods.
- **Line wrapping:** Prefer parentheses over backslashes for
  line continuation. Conversely, unwrap lines onto a single
  line when they fit within the 80-character limit.
- **Operator placement:** When wrapping expressions across
  multiple lines, place operators at the start of the next
  line, not the end of the previous line.
- **Trailing commas:** Include trailing commas in multi-line
  function calls, arrays, and dictionaries.

```gdscript
# Correct: parens for wrapping, operator at start of line.
var is_valid := (
	is_instance_valid(node)
	and node.is_inside_tree()
	and not node.is_queued_for_deletion()
)

# Correct: trailing comma in multi-line call.
some_function(
	first_arg,
	second_arg,
)

# Wrong: backslash continuation.
var is_valid := is_instance_valid(node) \
	and node.is_inside_tree()

# Wrong: operator at end of line.
var is_valid := (
	is_instance_valid(node) and
	node.is_inside_tree()
)
```

## Naming conventions

- **Classes/enums:** `PascalCase`
- **Functions/variables:** `snake_case`
- **Constants:** `UPPER_SNAKE_CASE`
- **Private members:** Prefix with underscore (`_my_var`,
  `_my_method`)
- **Signals:** Past tense (`player_died`, `match_started`)
- **Booleans:** Prefix with `is_`, `can_`, `has_`
- **No prefixes:** Avoid prefixes in variable names (e.g.,
  use `speed` not `player_speed` when already inside a player
  class). The underscore prefix for private members is the
  exception.
- **No abbreviations:** Use full words in identifiers (e.g.,
  `diagnostic` not `diag`, `configuration` not `config`,
  `information` not `info`). Standard domain abbreviations
  (`rtt`, `fps`, `rpc`, `usec`, `id`) are acceptable.

## Type annotations

- Use `:=` for inferred types on variable declarations.
- Always specify return types on functions.
- Use explicit type hints for `@export` vars and function
  parameters.

```gdscript
var speed := 10.0
const _MAX_SPEED := 200.0
@export var jump_height: float = 64.0

func get_speed() -> float:
	return speed
```

## Negation

- Prefer `not` over `!` for boolean negation.
- Do use `!=` for inequality comparisons.

```gdscript
# Correct.
if not is_alive:
	return
if count != 0:
	process()

# Wrong.
if !is_alive:
	return
```

## Comments and prose

- End all comments with a period.
- Use `##` for doc comments (Godot documentation comments),
  `#` for regular comments.
- Never use em dashes, en dashes, or hyphens as grammatical
  em dashes. Use a period and start a new sentence instead.
- Wrap comments at 80 characters, matching the code line
  limit.

```gdscript
## Advances the snail by the given number of
## network frames. Each frame applies a fixed
## movement step.
func _simulate_frames(count: int) -> void:

# Wrong: em dash in comment.
# The snail moves forward — unless blocked.

# Correct: period and new sentence.
# The snail moves forward. It stops when blocked.
```

## File structure

Follow the Godot-recommended ordering within each script:

1. `@tool`
2. `class_name`
3. `extends`
4. Doc comment (`##`)
5. `signal` declarations
6. `enum` declarations
7. `const` declarations
8. `@export` variables
9. Public variables
10. Private variables (`_`-prefixed)
11. `@onready` variables
12. `_init()`, `_enter_tree()`, `_exit_tree()`, `_ready()`
13. `_process()`, `_physics_process()`
14. Other virtual/callback methods
15. Public methods
16. Private methods

## Constants over inline values

Use file-level `const` declarations instead of hard-coding
static values inline in functions. Private constants use
underscore prefix.

```gdscript
# Correct: file-level constant.
const _RESPAWN_DELAY_FRAMES := 30

func _respawn() -> void:
	timer = _RESPAWN_DELAY_FRAMES

# Wrong: magic number inline.
func _respawn() -> void:
	timer = 30
```

## Scene templates over scripts

Prefer configuring state in `.tscn` scene files rather than
in scripts:

- **Animations:** Configure `AnimatedSprite2D.sprite_frames`
  animations in the scene editor, not in code.
- **Resource references:** Use `@export` vars and assign
  resources in the scene inspector. NEVER use `preload()` or
  `load()` for resource references in scripts.
- **Node references:** Use `%NodeName` unique-name syntax in
  scenes when referencing sibling/child nodes.

```gdscript
# Correct: export var assigned in scene inspector.
@export var death_effect: PackedScene

# Wrong: preload in script.
const _DEATH_EFFECT := preload(
	"res://src/effects/death_effect.tscn"
)
```

**Editing `.tscn` files directly (without the Godot editor):**
Scene files can be edited as text. The key fields are:
- `load_steps=N` in the header — **ignore it. Do not maintain
  it.** Godot 4.6 removed `load_steps` from the TSCN format
  (and added unique node IDs). It only ever fed a load-time
  progress bar, was never validated, and upstream dropped it
  precisely because it churned on every rebase. Progress now
  comes from `ResourceLoader.load_threaded_get_status()`.
  Verified on 4.7.1: a scene declaring `load_steps=999` with
  one resource, and a scene with no `load_steps` at all, both
  load with zero errors. `src/core/screens_main.tscn` already
  carries a wrong value (14, should be 15) and has shipped
  that way for months. If the field is absent, don't add it;
  if present, leave it alone — Godot drops it the next time it
  saves the file. Don't do a bulk normalization pass; that's
  98 files of pure churn for no behavior change.
- `[ext_resource type="PackedScene" path="res://..." id="X"]`
  — declares a scene dependency. Use a unique `id` string.
  `uid=` is optional; omit it if the scene has no UID yet.
- `[node name="Foo" parent="." instance=ExtResource("X")]`
  — instantiates the scene as a child node.
- Export vars on an instanced node are set directly on the
  node entry, e.g. `doc_type = 0`. Enum values are integers
  (0, 1, 2…) matching declaration order.

## Direct access over local copies

Do not assign local or class-level variable copies of
autoload properties (`G`, `Netcode`) or unique-name nodes
(`%`). Access them directly where needed.

```gdscript
# Correct: access autoload properties directly.
if G.match_state.is_match_active:
	Netcode.server_frame_index += 1

# Wrong: local copy of autoload property.
var match_state := G.match_state
if match_state.is_match_active:
	pass

# Correct: access unique-name node directly.
%AnimatedSprite2D.play("idle")

# Wrong: local or class-level copy.
@onready var sprite := %AnimatedSprite2D
```

## Performance

- Prefer `distance_squared_to()` over `distance_to()` when
  feasible, to avoid unnecessary `sqrt` calculations.

## GDScript formatter

No GDScript formatter is vendored in this repo (H9 deleted
pr-validate's no-op formatter job). Follow the style rules
above by hand; vendoring a formatter is Levi's call.

## Legacy code migration

Some older files use `!` for negation or backslash line
continuation. When modifying lines in these files, convert
them to the current style (`not`, parenthesized wrapping).
Do not bulk-convert unrelated lines in the same commit.
