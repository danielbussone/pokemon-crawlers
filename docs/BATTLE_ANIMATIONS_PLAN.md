# Battle animations

## Context

Combat today is instant and silent: cards resolve, HP bars snap to new values, the enemy creature sprite never reacts to being hit or acting, and there's no visual distinction between a full hit, a blocked hit, or a miss. The user wants real battle feedback — damage numbers, hit reactions, HP bars that animate, and per-type attack effects (a fire streak for FIRE cards, a water arc for WATER, etc.) — matching the game's existing procedural-art ethos (no imported effect assets, reuse the pixel-art toolkit already built for cards/creatures).

**A blocking discovery from exploration**: this isn't purely a UI-layer addition. `scripts/core/effects.gd`'s `resolve_effects()` already computes granular per-effect results (damage dealt, blocked, missed-by-blind, status applied) but only *damage* effects get appended to its returned array — heal/block/status/apply_condition effects are applied directly to the combatant and their result thrown away. Worse, `scripts/core/combat_ctx.gd::play_card()` and `enemy_turn()` call `Effects.resolve_card_effects()`/`resolve_enemy_action_effects()` and **discard the returned array entirely** — confirmed via direct read of both files, lines 112 and 164. So today, `CombatUI` has no way to know "12 damage was dealt to the enemy" vs. "it was blocked" vs. "poison was applied for 3 turns" — only a before/after HP diff. Any real animation work needs this plumbing fixed first.

Confirmed scope (via clarifying questions):
- **Coverage**: full scope — core feedback (damage numbers, hit-flash, screen-flash on player hit, tweened HP bar, BLOCKED/MISS indicator) + enemy attack motion (lunge when it acts, distinct from getting hit) + per-type attack effects (a small flying icon per `pokemon_type`, reusing existing `CardArt` icon motifs).
- **Status/condition effects** (poison, sleep, paralyze, confuse, intimidated, distracted, defenseless, blinded, slow): reuse the same generic floating-text popup as damage numbers, just different text/color — no dedicated icon/badge system this pass.

## What stays untouched

- All balance/rules logic and control flow in `effects.gd`/`combat_ctx.gd` — the plumbing fix below only *widens return shapes* (int/void → Dictionary, narrow Array → richer Array), never changes what gets applied to a combatant or in what order. `scripts/core/sim_check.gd` never reads any of the touched return values (only `check_outcome()`/`turn_result["outcome"]`), so the 300-run headless regression should produce identical results before/after — this is the correctness bar for step 1.
- `CombatCtx`'s existing public dict keys (`ok`, `reason`, `card_id`, `outcome`, `action_name`, `slept`, `paralyzed_skip`, `acted`, `poison_win`) — untouched, only gaining one new additive key each (`effect_log`).
- Turn-flow control logic in `combat_ui.gd` (`_begin_player_turn`, `_finish`, win/loss branching) — only `_on_card_pressed`/`_do_enemy_turn` gain an awaited animation step; `combat_ui.busy` remains the sole concurrency gate, already correctly blocks double-input during the (now longer) pacing.
- `draft_ui.gd`, `shop_ui.gd`, `end_ui.gd`, `starter_ui.gd` — no combat animation touches these.

## Step 1 — Expose per-effect results (`effects.gd`, `combat_ctx.gd`)

**`scripts/core/effects.gd`**: widen every effect-application function to return a describing `Dictionary` (currently `apply_heal`/`apply_block` return a plain `int`, `apply_status`/`apply_condition` return nothing):
- `apply_damage(...)` — unchanged, already `{"hp_damage", "blocked", "missed_blinded"}`.
- `apply_heal(...) -> Dictionary` — `{"amount": int}`.
- `apply_block(...) -> Dictionary` — `{"amount": int}`.
- `apply_status(...) -> Dictionary` — `{"status_type": String, "turns": int, "magnitude": int}`.
- `apply_condition(...) -> Dictionary` — `{"condition_id": String, "turns": int}`; for `blinded` (budget-based, no turn timer) return `turns: -1` as a sentinel the UI reads as "no duration to show."

`resolve_effects(...)` (still returns `Array`): for **every** effect in its loop (not just `"damage"`), append one log entry after applying it: `{"type": <effect_type>, "target_is_player": bool, ...the shape above merged in...}`. The `"draw"` branch stays unlogged (nothing in scope needs a draw animation). This is the single place that currently drops heal/block/status/condition results — fixing it here fixes both callers below.

`resolve_enemy_action_effects(...)`: its `is_attack` branch calls `apply_damage` directly for damage sub-effects (append as today) but calls `resolve_effects([eff], ...)` per-effect for everything else and discards the return (line ~188) — change that one discard to `results.append_array(...)` (0-or-1 length now that `resolve_effects` logs everything). No control-flow change.

**`scripts/core/combat_ctx.gd`**: `play_card()` captures `Effects.resolve_card_effects(...)`'s return into a local and adds `result["effect_log"] = log` to its existing return dict. `enemy_turn()` does the same, threading the captured log through as a new parameter on the private `_turn_result(...)` helper (default `[]` so the early-return paths — pre-outcome, slept, paralyzed-skip — that never call `resolve_enemy_action_effects` don't need changes).

**Verify before moving on**: run `godot --headless --path godot/ -- --simcheck` before and after this step, compare win/loss/loss-by-enemy numbers — should be identical (same seed/run count), since nothing here changes applied values, only what's *reported* about them.

## Step 2 — `EncounterMarker` reactions (`scripts/world/encounter_marker.gd`)

Add two public methods, matching the file's existing tween idiom (see `clear()`):
- `hit_flash()` — tween `_creature.modulate` (a `SpriteBase3D` property) to a red-white flash and back: fast in (~0.06s, `TRANS_SINE`/`EASE_OUT`) then a slightly slower recover (~0.18s, `TRANS_SINE`/`EASE_IN`) back to `Color(1,1,1,1)`. Keep a `_flash_tween` reference and `kill()` any in-flight one before starting a new one, so rapid multi-hit doesn't leave `modulate` stuck off-white.
- `attack_lunge()` — reuse the exact two-leg bump-tween shape already in `player_controller.gd`'s wall-bump (`_bump()`): a small forward position offset over ~0.08s (`TRANS_SINE`/`EASE_OUT`) then back over ~0.08s (`EASE_IN`). **Must** guard against fighting `_process()`'s continuous idle-bob sine write to `_creature.position.y` — add a `_lunging` bool `_process()` checks before writing `.y`, set true at lunge start, cleared in the lunge's `tween_callback`.

Both are no-ops when `cleared` is true (mirror the existing guard pattern in this file).

**Wiring**: `CombatUI` needs a handle to the active marker to call these — it doesn't have one today. Change `CombatUI._init(p_ctx: CombatCtx)` to `_init(p_ctx: CombatCtx, p_marker: EncounterMarker)`, store as `_marker`. Update the single call site: `scripts/main.gd:98`, `combat_ui = CombatUI.new(ctx)` → `CombatUI.new(ctx, marker)` (the `marker` param is already in scope in `_on_encounter_triggered`, confirmed by direct read). This is the only call site in the whole codebase (confirmed via grep) — the `--visualcheck` harness in `main.gd` never constructs `CombatUI` directly, only interacts with `main.combat_ui`'s existing public surface (`busy`, `_on_card_pressed`, `_on_end_turn_pressed`, `ctx`), so it needs no changes for this signature change.

## Step 3 — Promote shared icon draw calls (`pixel_art.gd`, `card_art.gd`)

`scripts/ui/card_art.gd` already has exactly the right visual motifs for attack effects, as private-by-convention statics: `_icon_flame`, `_icon_water`, `_icon_leaf`, `_icon_drip` (poison), `_icon_rock`, plus generic fallbacks `_icon_shield`/`_icon_wave`/`_icon_streaks`. Promote the five type-keyed ones (`_icon_flame`→`icon_flame`, `_icon_water`→`icon_water`, `_icon_leaf`→`icon_leaf`, `_icon_drip`→`icon_drip`, `_icon_rock`→`icon_rock`) plus `_icon_streaks`→`icon_streaks` (the generic attack fallback) to public statics on `PixelArt` (`scripts/world/pixel_art.gd` — already the shared cross-class toolkit used by `card_art.gd`, `creature_art.gd`, `world_builder.gd`, `portrait_factory.gd`). Update `CardArt._placeholder`'s `match` block to call `PixelArt.icon_flame(...)` etc. — zero behavior change to existing card placeholder art, just relocated. Leave `_icon_shield`/`_icon_wave` in `CardArt` (keyed by `card_type`, not `pokemon_type` — no role in the attacker→target flying effect).

**Type coverage** (confirmed by checking `data/balance/cards.json` + `enemies.json` action pools — the only `pokemon_type` values that actually appear on any attack in this Kanto slice): **FIRE, WATER, GRASS, POISON, ROCK, NORMAL, BUG**. No ELECTRIC/PSYCHIC/GROUND/FIGHTING/FLYING attacks exist yet (those types only appear as forward-compatible color entries elsewhere). Map: FIRE/WATER/GRASS/POISON/ROCK get their matching bespoke icon; NORMAL and BUG both fall back to `icon_streaks` (already how `CardArt`'s own placeholder treats them today) — distinguishable in flight via `CreatureFactory.type_color()`'s different tint per type (tan-gray vs. olive-green), not a new shape.

## Step 4 — New `CombatFX` node (`scripts/ui/combat_fx.gd`, new file)

`class_name CombatFX extends Control`, added as the last child in `CombatUI._build_ui()` (draws on top; itself and every child it spawns set `mouse_filter = Control.MOUSE_FILTER_IGNORE` so it never intercepts card/button clicks). Public API:

- `popup(text: String, color: Color, screen_pos: Vector2) -> void` — generic floating-text popup, reusing `game_hud.gd`'s existing toast pattern exactly: spawn a `Label`, tween position upward (~40px over ~0.9s, `TRANS_SINE`/`EASE_OUT`) while holding then fading `modulate:a` (reuse the toast's `tween_interval` + fade shape), `tween_callback(label.queue_free)`. **Fire-and-forget** — the caller never awaits this, so multiple simultaneous effects (e.g. Body Slam's damage + paralyze) can pop near-simultaneously without serializing the turn.
- `damage_popup(amount, screen_pos)`, `blocked_popup(screen_pos)`, `missed_popup(screen_pos)`, `status_popup(label, screen_pos)` — thin wrappers over `popup()` with fixed text/colors (status label text matches `CardText.status_line`'s existing vocabulary, e.g. `"Poison"`, `"Paralyze"`, `"Blinded"`, so the popup doesn't introduce new terminology).
- `fly_effect(pokemon_type: String, from_screen: Vector2, to_screen: Vector2) -> Signal` — spawns a small `TextureRect` (icon built via the promoted `PixelArt.icon_*` calls, matched on `pokemon_type`), tweens position `from_screen → to_screen` over ~0.25s (`TRANS_QUAD`/`EASE_IN`, a fast "dart"), `queue_free`s on arrival. Returns the tween's `finished` signal so `CombatUI` can await just the flight.
- `flash_player_hit()` — a single persistent full-rect `ColorRect` (red, alpha 0 at rest, created once in `_ready()` and reused rather than spawned per-hit), tweened alpha up fast (~0.05s) then down (~0.25s).
- `tween_enemy_hp(bar: ProgressBar, new_value: float, duration := 0.35) -> void` — replaces `CombatUI`'s instant `_enemy_hp.value = enemy.hp` snap: `create_tween().tween_property(bar, "value", new_value, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)`.
- `creature_screen_pos(marker: EncounterMarker) -> Vector2` — `get_viewport().get_camera_3d().unproject_position(marker.global_position + small_y_offset)`, recomputed per call (not cached) since the lunge tween moves the creature slightly.

**Screen anchors**: don't chase the pressed card button's position — `_on_card_pressed` → `_refresh()` → `_rebuild_hand()` frees every hand button (including the one just pressed) before any animation could reference it, and deferring `_refresh()` to preserve that position isn't worth the complexity. Use a **fixed** bottom-center screen point as the "player side" anchor for player-card flights, and `_player_stats`'s stable `global_position` (never rebuilt per-turn) as the "player side" target when the enemy attacks.

## Step 5 — `CombatUI` sequencing rework (`scripts/ui/combat_ui.gd`)

Add `var _fx: CombatFX`, constructed last in `_build_ui()`. `_refresh()`'s HP update calls `_fx.tween_enemy_hp(...)` instead of an instant snap — but only when the value actually changed since the last refresh (track `_last_enemy_hp_shown`, since `_refresh()` runs many times per turn for reasons unrelated to HP).

New private helper `_play_effect_log(log: Array, is_player_attacker: bool) -> void` (called from both `_on_card_pressed` and `_do_enemy_turn`, replacing today's flat `await _pause(1.1)`):
1. Attack motion: if player attacking, `await _fx.fly_effect(card_ptype, bottom_center_anchor, _fx.creature_screen_pos(_marker))`. If enemy attacking, fire-and-forget `_marker.attack_lunge()` while awaiting `_fx.fly_effect(enemy_ptype, creature_screen_pos, player_stats_anchor)` in parallel.
2. Iterate `log` entries, firing impact feedback **without** awaiting each one serially (all fire-and-forget, so multi-effect actions don't stack latency): damage-to-enemy → `_marker.hit_flash()` + `damage_popup`/`blocked_popup`/`missed_popup` as appropriate; damage-to-player → `_fx.flash_player_hit()` + popup; heal → green `+N` popup; status/condition → `status_popup` with `CardText`-matching vocabulary.
3. One short trailing `await get_tree().create_timer(0.15).timeout` settle pause, then return.

Target added latency: ~0.25s flight + ~0.15s settle ≈ **0.4s per turn baseline**, not stacking per-effect (multi-effect actions like Body Slam stay in the same ~0.4–0.5s window since impact feedback overlaps rather than serializing) — within the desired "juice without sluggishness" range. `combat_ui.busy` needs no changes — it's already set true at the top of `_on_card_pressed`/`_do_enemy_turn` and cleared after the full await chain, which now just takes a bit longer.

## Verification

1. `godot --headless --path godot/ --import` after every step — catches parse errors in the new/edited files fastest.
2. `godot --headless --path godot/ -- --simcheck` — run before Step 1 (baseline) and after (compare win/loss/loss-by-enemy numbers, same seed/run count) to confirm the plumbing widening didn't change any combat outcome. Re-run after Steps 2–5 too as a cheap "didn't break core" smoke test (this harness never touches animation code, so it should stay identical throughout).
3. `godot --path godot/ -- --visualcheck` (real render, existing harness in `scripts/main.gd`) — its auto-play loop already polls `combat_ui.busy` correctly and will simply wait out the longer animated sequence with no changes needed. Add one deliberate mid-animation screenshot: after the first successful `_on_card_pressed` call in the loop, insert a short fixed `await get_tree().create_timer(0.1).timeout` then save a checkpoint screenshot before continuing — lands inside the ~0.25s flight window for a reliable (if not frame-perfect) capture of the effect in flight. Add a similar checkpoint around an enemy turn to catch the lunge/hit-flash/screen-flash.
4. Manual smoke test: fight the first wild encounter, confirm damage numbers appear and fade, the enemy sprite flashes on hit, the screen flashes when the player is hit, the enemy HP bar animates rather than snapping, a Body Slam (damage+paralyze) doesn't feel sluggish, and the enemy's sprite visibly lunges when it acts (distinct from its hit-flash).
