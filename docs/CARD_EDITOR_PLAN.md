# Pokémon Crawlers — Card Editor Plan

In-game dev tool to author/tune the battle cards in `data/balance/cards.json`.
**Plan only — not yet implemented.**

Last updated: 2026-07-22

---

## Context

The game's 58 battle cards live in a single JSON file (`godot/data/balance/cards.json`) and are
hand-edited. There's already a code-generated in-game **map editor** (`scripts/tools/map_editor.gd`,
launched with `-- --mapeditor`) that authors the sibling balance JSONs (enemies, trainers, stages)
with New/Delete/Save flows, structured forms, texture import and a pixel painter.

There is no equivalent tool for cards, so adding/tuning a card means editing raw JSON and matching
art filenames by hand. This plan adds a **Card Editor** that mirrors the map editor's proven
patterns: a standalone `Control` launched by a CLI flag, editing `cards.json` directly, with
structured field editing, New-Card type presets, a live trading-card preview, and art import +
touch-up painting. Outcome: cards can be created and balanced entirely in-app.

Confirmed design decisions:

- **Description** → add a new editable `description` flavor-text field to the card schema, shown
  alongside the auto-generated effect summary (and rendered on the card widget).
- **Effects** → structured controls (dropdowns + spinboxes per effect), not a text DSL.
- **Art** → import + crop/position, **plus** a pixel painter for touch-ups on top of the import.
- **Templates** → New-Card presets keyed by card type (attack / status / support).

## Reference material (reuse these patterns)

- Editor skeleton & UI factory helpers: `scripts/tools/map_editor.gd`
  - Launch dispatch to mirror: `main.gd:56-62` (`--mapeditor` branch).
  - Picker + New/Delete/Save toolbar: `_build_pokedex_panel()` (map_editor.gd:1355).
  - New/Delete/commit round-trip that **preserves fields by merging** into the existing dict:
    `_on_dex_new` (1610), `_on_dex_delete` (1628), `_dex_commit` (1644).
  - Save via `FileAccess.WRITE` + `JSON.stringify(dict, "  ")` (2-space indent) with a green/red
    status label: `_on_dex_save` (1683).
  - Widget helpers to copy (~5 lines each): `_label` (2470), `_meta_label` (2476), `_spin` (2484),
    the `OptionButton` id-in-metadata pattern `_select_option`/`_option_id` (2188).
  - Image import: `_tex_open_import_dialog` (929) + `_tex_import` (943) — `FileDialog`
    (`ACCESS_FILESYSTEM`, `use_native_dialog`), `Image.load` → `convert(RGBA8)` → centre-crop
    `get_region` → `resize(..., INTERPOLATE_LANCZOS)`.
  - Pixel paint canvas: inner class `TexCanvas` (2495) — `_draw`/`_gui_input`/`_paint` with an
    `on_paint: Callable`.
- Card data & rendering:
  - Effect vocabulary/fields: `scripts/core/effects.gd:145-196`.
  - Card text preview: `CardText.summary(card, enemy_type, bal)` — `scripts/ui/card_text.gd:5`.
  - Live card widget: `CardWidget.build(card_id, enemy_type, starter_id, disabled, tooltip)` —
    `scripts/ui/card_widget.gd:41` (reads `Balance.cards[card_id]`; type colors at :14-27).
  - Art resolver: `CardArt.get_texture(card_id, starter_id)`, `ART_DIR = "res://art/cards"` —
    `scripts/ui/card_art.gd:7,14`. Art is filename-convention only (`<card_id>.png`), nothing in
    the JSON.
  - PNG save-outside-import pattern: `scripts/world/terrain_tex.gd:39-47`
    (`save_override`/`delete_override` using `ProjectSettings.globalize_path` + `img.save_png` +
    `DirAccess.remove_absolute`).

## Card schema (target)

Existing per-card fields: `id, name, pokemon, card_type, pokemon_type, cost, power, rarity,
effects[]`, optional `evolves_to`, plus data-only `self_evolve`/`tier` on the poison line. This
plan **adds** `description` (string, flavor text). Effect object shapes (from effects.gd):
`damage{magnitude, target?, ignore_block?}`, `block{magnitude, target}`, `heal{magnitude, target}`,
`status{status, duration, magnitude?, target?}`, `apply_condition{condition, duration?, target?}`,
`draw{magnitude}`, `shuffle_hand{}`.

## Implementation

### 1. New file: `scripts/tools/card_editor.gd`

`class_name CardEditor extends Control`. Code-generated UI, no `.tscn` — same as MapEditor.

- Header comment with launch command: `godot --path . -- --cardeditor`.
- `const CARDS_PATH := "res://data/balance/cards.json"`.
- Load in `_ready()`: `FileAccess` → `JSON.parse_string` → keep `_all: Dictionary` and
  `_cards: Array = _all["cards"]`. Full-rect background + root `VBoxContainer`.
- Copy the small factory helpers (`_label`, `_meta_label`, `_spin`) locally (private to MapEditor).

### 2. Launch hook: `scripts/main.gd`

Add a `--cardeditor` branch immediately after the `--mapeditor` block (main.gd:62), identical
shape (instantiate the editor, add under a `CanvasLayer`, `return`).

### 3. Toolbar + form (mirror the Pokédex panel)

- Toolbar row: `OptionButton` card picker (label `"<name> (<id>)"`, real id in item metadata) +
  **New** (with a small type dropdown for the preset) + **Delete** + **Save Cards** buttons + a
  status `Label`.
- Form (in a `ScrollContainer` → `VBoxContainer`):
  - `id` `LineEdit` (meta-label: unique snake_case, art = `art/cards/<id>.png`).
  - `name` `LineEdit`; `pokemon` `LineEdit`.
  - `card_type` `OptionButton` (attack/status/support); `pokemon_type` `OptionButton` (element
    list: NORMAL, FIRE, WATER, GRASS, POISON, BUG, ELECTRIC, PSYCHIC, GROUND, ROCK, plus
    FIGHTING/FLYING which have colors).
  - `cost` `_spin(0, 10)`; `power` `_spin(0, 99)`; `rarity` `OptionButton`
    (starter/common/uncommon/rare/signature).
  - **`description`** `TextEdit` (short, ~2 lines) — the new flavor field.
  - `evolves_to` `OptionButton`: "(none)" + every card id.

### 4. Structured effects editor

A `VBoxContainer` rebuilt from the working `effects` array (clear children with `queue_free()`,
then one row per effect — same rebuild idiom as `_rebuild_route_rows`). Each row:

- `OptionButton` for effect `type` (damage/block/heal/status/apply_condition/draw/shuffle_hand);
  changing it rebuilds that row's field controls.
- Type-specific controls:
  - damage: magnitude `SpinBox`, target `OptionButton` (enemy/self), `ignore_block` `CheckBox`.
  - block/heal: magnitude `SpinBox`, target `OptionButton`.
  - status: status `OptionButton` (poison/sleep/paralyze/confuse), duration `SpinBox`, magnitude
    `SpinBox` (poison only, 0 = omit), target `OptionButton`.
  - apply_condition: condition `OptionButton` (intimidated/distracted/defenseless/blinded/slow —
    read keys from `conditions.json`), duration `SpinBox`, target `OptionButton`.
  - draw: magnitude `SpinBox`. shuffle_hand: no fields.
  - Remove (`x`) button per row.
- "+ Add effect" button appends a default `{type:"damage", magnitude:1}` row.

Read controls back into effect dicts on commit; **omit** default/empty optional keys (no `target`
when "enemy", no poison `magnitude` when 0) to keep JSON diffs clean, matching `_parse_effect`
conventions (map_editor.gd:1772).

### 5. New-Card type presets

The **New** button reads its adjacent type dropdown and appends a starter card:

- attack → `{card_type:"attack", pokemon_type:"NORMAL", cost:1, power:5, effects:[{type:"damage", magnitude:5}]}`
- status → `{card_type:"status", cost:1, power:0, effects:[{type:"apply_condition", condition:"intimidated", duration:2, target:"enemy"}]}`
- support → `{card_type:"support", cost:1, power:0, effects:[{type:"block", magnitude:5, target:"self"}]}`

Plus a unique id (`new_card`, `new_card_2`, … like `_on_dex_new`), `name:"New Card"`,
`pokemon:"Various"`, `rarity:"common"`, `description:""`. Then select it in the picker.

### 6. Live preview (reuse CardWidget)

A preview container rebuilt on any edit. Because `CardWidget.build` reads `Balance.cards[id]`,
commit the working dict into `Balance.cards[working_id]` first, then
`CardWidget.build(working_id, "", "", false, description)` and add it. Also show
`CardText.summary(...)` text so the auto effect line is visible while editing. (Editor runs with
the `Balance` autoload loaded, so this is safe and accurate.)

### 7. Art tooling (import → crop/position → pixel touch-up → save/remove)

A card-art sub-section with its own working `Image` (`_art_img`) and a live `TextureRect` preview
fed from `ImageTexture.create_from_image(_art_img)`:

- **Import**: lazy `FileDialog` (copy `_tex_open_import_dialog`), on select run an importer like
  `_tex_import` but crop to the **card art aspect** (~3:2, matching the `card_widget` art panel) and
  resize to a fixed authored size (e.g. `ART_W×ART_H`, ~384×256) with `INTERPOLATE_LANCZOS`.
- **Crop/position**: after loading the source at full res, offset-x / offset-y `SpinBox`es (or a
  drag) + a zoom `HSlider` choose the crop rectangle before down-resize; re-crop re-runs from the
  cached source image so it's non-destructive until Save.
- **Pixel touch-up**: a `TexCanvas`-style paint canvas (copy the inner class) bound to `_art_img`
  with a color `ColorPickerButton`, brush-size `SpinBox`, and an eraser toggle (paints
  transparent). `on_paint` writes pixels (respecting brush size) and refreshes the preview.
- **Save art**: `_art_img.save_png(ProjectSettings.globalize_path("res://art/cards/<id>.png"))`
  after `DirAccess.make_dir_recursive_absolute(...)` — same as `terrain_tex.save_override`.
- **Remove art**: `DirAccess.remove_absolute` the PNG (falls back to the procedural placeholder).
- On card select, seed `_art_img` from the existing PNG if present (`Image.load` the globalized
  `art/cards/<id>.png`), else a blank transparent canvas. Since `CardArt` caches its scan
  statically, the editor previews from `_art_img` directly (not through `CardArt`) so freshly
  imported/painted art shows immediately without a relaunch.

### 8. Save + reference safety

- `_commit()` writes the form + effects back by **merging into the existing card dict** (so unused
  fields like `self_evolve`/`tier` survive round-trips), mirroring `_dex_commit`. Handle id rename
  like `_dex_commit` (only adopt a new id if unique).
- **Save Cards**: `_all["cards"] = _cards`; `FileAccess.WRITE` + `JSON.stringify(_all, "  ")`;
  green/red status label.
- Reference safety: before **Delete** or an **id rename**, scan the other balance JSONs for the id
  (`starters.json` decks, `learnsets.json` `card_id`/`starter_deck`, `stage_rewards.json` pools,
  `run_config.json` `signature_card`, and `evolves_to` within cards) and show a warning in the
  status label listing where it's still referenced. Non-blocking (dev tool), but prevents silently
  breaking `balance_db.gd::_validate()` (balance_db.gd:157) on next game launch.

### 9. Card schema + widget change for `description`

- `cards.json`: `description` is optional and additive — existing cards without it read as `""`.
- `scripts/ui/card_widget.gd`: in `build()`, if `card.get("description","")` is non-empty, surface
  it — append it to the button `tooltip_text` (guaranteed room) and optionally add a small dimmed
  italic `Label` line under the effect text. Keep it graceful (`.get` with `""` default) so the 58
  existing cards are unaffected.

## Files

- **Create** `scripts/tools/card_editor.gd` (+ its `.uid`, generated by Godot).
- **Edit** `scripts/main.gd` — add `--cardeditor` launch branch after line 62.
- **Edit** `scripts/ui/card_widget.gd` — render optional `description`.
- **Data** `data/balance/cards.json` — gains `description` fields as cards are edited (field is
  optional; no manual pre-edit needed).
- No change to `card_art.gd`, `card_text.gd`, or `effects.gd` (read/reused as-is).

## Verification

1. **Launch**: `cd godot && godot --path . -- --cardeditor` — editor UI appears; card picker lists
   all 58 cards; selecting one populates every field, the effects rows, the live preview, and the
   art preview.
2. **Edit round-trip**: change a card's name/cost, add a `status` effect via the structured rows,
   type a `description`, **Save Cards**. Confirm `git diff data/balance/cards.json` shows a clean
   2-space-indented change with the new `description` and effect, no reordering of other cards.
3. **New Card presets**: New → each of attack/status/support produces a valid, unique-id card that
   previews correctly and saves.
4. **Art**: Import an image → crop/position → paint a few touch-up strokes → Save; verify
   `art/cards/<id>.png` is written and the preview matches. Remove → PNG deleted, preview falls
   back to the procedural placeholder.
5. **Integrity**: try to Delete a card referenced by a starter deck → warning names the reference.
   Then launch the real game (`godot --path .`) and confirm `balance_db.gd::_validate()` passes and
   the edited card renders in combat with its new description (tooltip/text) and art.
6. **Regression**: existing cards with no `description` still render (no errors from the widget
   change).
