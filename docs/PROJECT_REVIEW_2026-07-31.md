# Pokémon Crawlers — Project Review

Full-repo state review, look-and-feel evaluation, and prioritized backlog.

Review date: 2026-07-31 · Branch at time of review: `feature/card-editor` · Last commit: `c0b8be9`

> Snapshot document. Status claims below were verified against source, not against other docs.
> Once `GAMEPLAY_MECHANICS_ROADMAP.md` and `ART_DIRECTION.md` absorb the actions here, this file
> stays as the dated record of why those changes were made.

---

## Context

`pokemon-crawlers` is a Godot 4.7 first-person grid crawler / deckbuilder (12,658 lines of GDScript, 32 stages, 53 cards, 177 enemies, full Brock→Champion arc) on top of a frozen May-2026 Python combat PoC.

Two problems, both from the same cause — the game outran its documentation:

1. **Every status doc under-reports what exists.** `GYM_CONTENT_PLAN.md` and `CARD_EDITOR_PLAN.md` both say "Plan only — not yet implemented" for shipped work. Six roadmap rows sit at "IMPLEMENTED — pending approval" while development continued past them. The root `README.md` still describes the project as a Python CLI PoC. "Phase 7" exists in four commit messages and zero roadmap rows.
2. **There is no written art direction**, so nothing distinguishes the deliberate style choices from the accidental drift — and the accidental parts make the game read as unfinished even where it isn't.

### Decisions locked in this review

- **Mood — bright Gen 1, crawler structure.** The sunny palette stays; "crawler" means the grid movement and dungeon structure, not a dark mood. No lighting overhaul.
- **Art — split by context, three deliberate fidelities.** Cards = painterly illustration. World trainers = detailed portrait art. World Pokémon = Gen-5 pixel sprites. Trainers being more detailed than the creatures they stand beside is **intentional and canonical** — Gen 1 itself paired detailed trainer VS portraits with simple creature sprites. What is *not* intentional is trainers disagreeing with each other.

---

## State summary (verified against source, not docs)

**Built and working** — combat (53 cards, stamina economy, 7 effect types, 4 statuses, 5 conditions, ordered damage pipeline at `effects.gd:36-71`, wild-weighted + deterministic-boss AI with telegraphed intent); progression (XP learnsets, Rare Candy, starter-evo tiers, drafts, 8 typed badges, Bill's PC, items, shops); world (32 author-placed stages stitched into one grid, material-driven terrain, procedural Centers/Marts, fog-of-war minimap, multi-Pokémon bouts); content (full 9-level arc, all 151 Gen-1 sprites + a hand-written GIF decoder); tools (`map_editor.gd` 2,788 lines, `card_editor.gd` 1,228 uncommitted — 32% of the codebase is editors).

**Genuinely not built**

| Gap | Evidence |
|---|---|
| `phase6-telemetry` | no `run_log.gd`; only roadmap row still Pending |
| Balance pass on the arc | roadmap: "front-loaded difficulty; late game trivial once snowballed"; simcheck ~20% |
| Save/resume | only `user://` write in the project is `settings.cfg` |
| Audio | zero `AudioStream*` references repo-wide |
| Custom font | zero `FontFile`/`.ttf`/`.fnt` references repo-wide |
| Options menu | `settings.gd:3-5` says to hand-edit `user://settings.cfg` |
| Deferred 5b mechanics | multi-phase bosses, true evasion, Surge drain, Blaine arena DoT |
| GDScript tests | 73 pytest tests cover the frozen Python PoC only |

**Stale / wrong** — `end_ui.gd:28,37,39` hardcodes Brock/Boulder Badge on *every* run end; `main.gd:158` opens with "Defeat all 13 encounters on the road to Brock!" (actual: ~57); `card_widget.gd`'s new flavor-text branch is dead code (0 of 53 cards have a `description`); `godot/data/balance/.json` is a 56 KB tracked accidental save from `c0b8be9`; `run_manager.gd:12` still says "linear corridor"; duplicate sprite scrapers in `tools/` and `scripts/` were never reconciled.

---

## Look and feel — critical evaluation

### Fidelity map — what's intentional vs. what's a defect

| Layer | Style | Resolution | Verdict |
|---|---|---|---|
| Card art | Painterly illustrated scenes | 384×256 new / 1201×880 legacy | Intentional; legacy files need re-crop |
| World trainers | Detailed vector/anime portrait art | 86×300 (Brock) → 1100×2131 (Erika) | Style intentional; **spread is the defect** |
| World Pokémon | Gen-5 B/W pixel sprites | 96×96 | Intentional |
| Fallbacks | Hand-coded procedural blobs | 32–64px | Placeholder — the real gap |

Detailed trainers standing beside pixel creatures is a deliberate, Gen-1-faithful choice and stays. The actual defect is that **trainers disagree with each other by ~7×** — Brock is 86px wide, Erika 1100px — so their sharpness visibly varies as you move between gyms.

There's a technical reason to fix it beyond consistency: trainers render through `CreatureFactory.build_sprite`, which sets `TEXTURE_FILTER_NEAREST` (`creature_factory.gd:134`). A 2131px-tall texture displayed at roughly 500px on screen is minified ~4× with no mip smoothing, which shimmers and crawls during movement. Pre-downsampling to near render size makes the high-res trainers look *better*, not just smaller.

### Per area

**World exploration** — *Good:* `MOVE_DURATION 0.18` / `TURN_DURATION 0.15` with input queueing is genuinely snappy and correct for the genre; wall-bump nudge; 32 stages stitched into one continuous world; fog-of-war minimap revealing 8 neighbours. *Bad:* `fog_density = 0.01` is effectively invisible — corridors have no depth cue or mystery. *Unfinished:* no footsteps or any audio; no screen transitions anywhere (shop entry hides the world instantly, combat pops in, death hard-reloads the scene); tall grass is only a slightly darker green square, with none of Gen 1's iconic encounter-zone read.

> **Bug worth calling out:** `theme_palette.gd:16` sets `cave_branches` ground to `rock_floor`, which is `category: "exterior"` — unroofed. Caves therefore render under the bright blue procedural sky. `floor_cave` is the `interior` (roofed) material and is what the theme should default to.

**World textures** — *Good:* the material-primary system is the best-designed part of the world code — category drives walkability *and* roofing from one source of truth; procedural 16×16 tileable generation with per-pattern algorithms (brick/planks/tile/windows/water/lava); authored overrides read/written via raw `Image.load`/`save_png` so the in-app painter and the 3D renderer share exact pixels with no reimport. Nearest-neighbour filtering is correctly set, so pixel art stays crisp. *Bad:* only 5 of ~40 materials have authored textures — everything else falls to the `noise` pattern, so most of the outdoor world is mottled speckle over a flat base colour, and large grass fields will visibly repeat. Authored textures are 32×32 while procedural are 16×16. *Unfinished:* the palette is naturalistic and desaturated (`grass` = `0.30, 0.55, 0.28`), which fights the "bright Gen 1" target.

**HUD** — *Good:* `UITheme` is a real design system — one gold accent, consistent rounded panels, green→amber→red HP ramp, three font sizes. Structurally the most professional UI work in the project. *Bad:* **no custom font** — every label in the game is Godot's default sans, which instantly reads as programmer UI rather than Gen 1. *Unfinished:* the HUD carries HP + gold + stamina + XP + next-unlock + rare-candy + evo-tier + zone + party strip + toasts with no stated hierarchy — stat soup risk; `FONT_SMALL 12` / `FONT_BODY 15` at 1920×1080 will be unreadable on a 5.5" Retroid; no pause or options surface exists.

**Cards** — *Good:* the illustrated card art is excellent and cohesive — each depicts the specific move with the specific starter. The TCG-style reduced type palette (Rock/Ground/Fighting→brown, Grass/Poison/Bug→green) is deliberate and documented. *Bad:* **6 of 53 cards have art**; a combat hand is a mix of beautiful illustrations and procedural colour blobs, which is the most visible unfinished thing in the game. Art is keyed per starter (`<card>_<starter>.png`), tripling the work for shared cards. *Unfinished:* 5 legacy arts are 1201×880 / ~1.7 MB against the new 384×256 / ~200 KB standard; `rarity` exists in data (starter→signature) and the widget ignores it, so signature cards feel identical to commons; a 150×210 card now stacks header + art + effect + flavour, and flavour at ~10px will be illegible.

**Animations** — *Good:* `combat_fx.gd` shows real game-feel instincts — damage popups scale *and* redden with magnitude (`22 + clamp(amount,0,26)`), TRANS_BACK pop-in, rise-and-fade; screen shake; hit flash; HP bars tween rather than snap. Markers bob on a per-index phase offset so a row of encounters doesn't pulse in unison, and `hit_flash()` respects per-bout dimming. *Bad:* **no card animation at all** — cards vanish from hand, with no draw, play, or discard motion. For a deckbuilder, card movement *is* the feel; this is the largest single gap. *Unfinished:* `fly_effect` is a flat 0.25s translate that reads as placeholder next to the popup quality; no in-combat death animation; the player has no visual presence in combat beyond a HUD portrait.

**World trainers** — *Good:* the team row is careful work — packed by *opaque* width via `center_sprite_on_opaque`/`sprite_opaque_half_width`, with per-bout dimming (defeated 0.35α, current full, waiting 0.6α) that reads instantly. Ring colour coding (optional blue / gate gold / boss fiery) with emission only on gates and bosses so wilds recede. `Label3D` distance fade stops corridor labels converging into mush. *Bad:* the ~7× resolution spread between trainers, which shimmers under nearest-filter minification. *Unfinished:* trainers are static billboards with no idle animation and no turn-to-face; `_companion_species_id`'s hardcoded `brock`/`rival_`/`bug_catcher_` fallbacks still sit alongside the newer team system.

**World Pokémon** — *Good:* all 151 species, static + animated, with a from-scratch GIF decoder; alpha decontamination, tight opaque cropping, interior hole filling; `sprite_tuning.json` for per-species offsets; crisp nearest filtering with `ALPHA_CUT_DISCARD`. *Bad:* sprites cast no ground shadow, so creatures float over the tile. *Unfinished:* Gen-5 B/W sprites are stylistically Gen 5, not Gen 1 — defensible (they're far better drawn than RB sprites) but worth deciding deliberately rather than by scrape convenience; unscraped entries still fall back to procedural blobs.

---

## Doc reconciliation actions

### 1. `docs/GAMEPLAY_MECHANICS_ROADMAP.md` — single status source of truth
- `Last updated` → 2026-07-31.
- Mark the six `IMPLEMENTED — pending approval` rows **DONE** (`phase4`, `phase5a`, `phase5-map-format`, `phase5-map-editor`, `phase5b`, `phase5c`) — they shipped in `63ed81c`, `4e19f1b`, `8f5ca28`, `b26a558` and have been played since. Carrying "pending approval" on six shipped phases makes the table unreadable.
- Add missing rows: `phase7-terrain` (`ccd6af2`, `93b1f65`), `phase7-hud` (`ad93918`), `phase7-combat-fx` (`e459f16`), `phase5-world-view` (`03f6143`, `448de50`), `phase5-trainers`, `tools-card-editor` (in progress).
- Replace the **Current next TODO** line per the reordering argument below; append the backlog as a `## Backlog — road to playable` section.

### 2. New `docs/ART_DIRECTION.md`
The missing doc that caused the drift. Contents:
- The two locked decisions above, stated as rules.
- **Explicitly record that detailed trainers beside pixel creatures is intended**, with the Gen 1 precedent — otherwise a future pass will "fix" it.
- Asset standards: card art 384×256; trainer art ≤512px tall, aspect preserved, never upscaled; terrain textures 16×16 to match the procedural generator; creature sprites 96×96 as scraped.
- The backup convention: repo-root `art/` holds pre-processing raws; `art/trainers_fullres/` holds processed full-resolution masters (see step 7).
- The per-area evaluation above, as the baseline to measure future work against.

### 3. Fix stale "Plan only" headers
- `docs/GYM_CONTENT_PLAN.md` → implemented (keep the canon-deviation table; it accurately lists *deferred* choices).
- `docs/CARD_EDITOR_PLAN.md` → implemented in `card_editor.gd`; note descriptions are still unauthored; correct "58 battle cards" to 53.
- `docs/ANDROID_EXPORT.md` — leave alone, "planned, not started" is accurate.

### 4. `docs/level_outline.yaml`
Level 2 (Cerulean) `status: partial` → `built`; `run_config.json` now has the `mt_moon` and `nugget_bridge` approach segments.

### 5. Root `README.md`
Reframe so the Godot game is the project and the Python PoC is the frozen balance baseline beneath it. Keep the PoC run/test instructions, moved below. Drop "13-fight Kanto arc".

### 6. `godot/README.md`
Fix the corridor-era claims at ~4, ~36, ~80-82 (layout is 32 author-placed stages stitched by `world_pos`, not derived from `Run.encounters` along a corridor). Rewrite `## Known first-pass gaps` (~252) — the art-coverage claims are long closed; replace with card art 6/53, no audio, no save/resume, no custom font. Document `--cardeditor`. **Keep the background-removal recipe and the `EXPAND_IGNORE_SIZE` note verbatim** — both are hard-won and still correct.

### 7. Back up the trainer masters — `art/trainers_fullres/`
Done **before** any downsampling exists to regret. Purely additive: copy all 17 `godot/art/trainers/*.png` to a new repo-root `art/trainers_fullres/` and commit them (~4 MB).

Repo-root `art/` already holds 20 raw sources (`FRLG_Erika.png`, `Brock_Anime.png`, …), but those are *pre*-background-removal — they do not preserve the alpha-cutout and cropping work baked into the processed files. This backup captures that work.

Repo root, not inside `godot/`, so Godot never imports them as game assets.

### 8. Delete `godot/data/balance/.json`
An accidental blank-filename save from the map editor, tracked in git, stale format, loaded by nothing (`balance_db.gd` loads by explicit name).

---

## Backlog — road to playable and fun

**The one substantive reordering: telemetry before the balance pass**, inverting the roadmap's "balance pass … then `phase6-telemetry`". The only Godot-side oracle is `sim_check.gd`, a first-playable-card bot whose own docstring calls it a smoke test, and it reports one aggregate number. "Front-loaded difficulty, late game trivial" is a *shape* problem across 9 levels; one number can neither show the shape nor confirm a fix. `POC_BALANCE_TUNING.md` already recorded the lesson: *"aggregate win rate is misleading; loss-location metric is a design health check."*

**Tier 1 — cheap, and the game currently misrepresents itself**
1. **Custom pixel font.** No font resource exists; one `FontFile` set on the default theme changes the HUD, cards, combat log, shops and menus simultaneously. Highest impact-per-hour in the project, and the single biggest step toward reading as Gen 1.
2. `end_ui.gd` — derive win/loss text from real run state (badges, gyms cleared, final segment) instead of the hardcoded Brock strings.
3. `main.gd:158` — opening toast from the real encounter count and destination.
4. Land the card WIP: author `description` text so the new `card_widget.gd` branch stops being dead code, commit the 9 Bulbasaur arts and the `shuffle_hand` label fix (that effect has rendered as blank text since `b26a558`).
5. Cave roofing: `cave_branches` theme ground → `floor_cave`, so caves stop rendering under open blue sky.

**Tier 2 — visual coherence (the locked art decisions)**

6. **Normalize trainer fidelity to each other** — cap at 512px tall, aspect preserved, **never upscale** (Brock at 300px stays native; upscaling adds no detail). Erika 1100×2131 → 264×512. Trainers stay deliberately more detailed than the creatures; this only stops them disagreeing among themselves, and removes the nearest-filter shimmer on the oversized ones. Requires the `art/trainers_fullres/` backup from step 7 — one reversible batch script, re-runnable at a different target if 512 reads too soft.
7. **Card art coverage — 6/53.** The card editor now exists to close this. Re-crop the 5 legacy 1201×880 / 1.7 MB files to the 384×256 standard (~30 MB of art today, mostly these).
8. Rarity treatment in `card_widget.gd` — the data exists and is ignored; signature cards should feel earned.
9. Terrain texture coverage (5 of ~40 authored) and a saturation pass toward bright Gen 1; standardize authored textures to 16×16.

**Tier 3 — make the arc fun**

10. `phase6-telemetry` — `run_log.gd` + sim_check extensions emitting **per-level** loss location, HP/gold/deck curves, time-to-clear. Port the aggregation shape from `analyze.py`, which already does this for the Python PoC.
11. Balance pass driven by (10). If the first-playable-card bot can't distinguish "hard" from "unplayable", promote `player_ai.py`'s heuristic into the GDScript sim.

**Tier 4 — game feel**

12. **Card play/draw/discard animation** — the largest remaining feel gap for a deckbuilder. `combat_fx.gd`'s tween patterns are the template.
13. Screen transitions (combat in/out, shop, death) — currently every state change is an instant cut.
14. Audio — zero today; the largest feel gap outside cards.
15. Ground shadows under world sprites so creatures stop floating.
16. Save/resume. Death or quit loses everything; `Settings`' `user://settings.cfg` is the pattern.
17. Options menu + a font-size pass for handheld (12/15px will not survive a 5.5" screen).

**Tier 5 — depth and foundation**

18. Route trainers: built end to end, but only 2 `t` cells exist across 32 stages — the cheapest content-per-effort win available.
19. Deferred 5b mechanics (multi-phase bosses, true evasion, Surge drain, Blaine arena DoT).
20. Python↔Godot data divergence — the README's 3,000-run baseline can no longer validate the shipping game. Retire the Python sim or port the Godot data into it.
21. Delete the duplicate sprite scraper; promote the `godot/README.md` background-removal snippet into `tools/`.
22. Verify the `Loaded resource as image file, this will not work on export` warning on `art/player/*.png` (seen in a Jul 9 capture) — blocks a clean Android export.
23. GDScript tests — `effects.gd` and `combat_ctx.gd` are the highest-value targets.

Android export stays deferred, correctly — it should follow Tier 4, since shipping the current balance and no save system to a device ships the problems.
