# Pokémon Crawlers — Godot 3D Port (first pass)

A first-pass Godot 4 port of the frozen Python PoC ([../POC_FINDINGS.md](../POC_FINDINGS.md),
[../docs/GODOT_HANDOFF.md](../docs/GODOT_HANDOFF.md)). Same balance data, same 13-fight Kanto
opening arc, walked as a first-person tile-grid dungeon crawler (Legend of Grimrock / Etrian
Odyssey style) instead of a CLI prompt loop.

**All world/creature assets are generated in code** — no imported models or audio. Creatures,
walls, floors, and the HUD portrait are pixel-art textures drawn at runtime pixel-by-pixel
(see [scripts/world/pixel_art.gd](scripts/world/pixel_art.gd),
[scripts/world/creature_factory.gd](scripts/world/creature_factory.gd), and
[scripts/world/world_builder.gd](scripts/world/world_builder.gd)) applied to billboarded
sprites and simple tile geometry. **Card art is real illustrated images** where supplied
(see Card art below), with a procedural pixel icon as a placeholder otherwise.

## Running it

Open `godot/` as a Godot 4.3+ project and run (F5), or headless:

```bash
godot --path godot/
```

**Controls** — first-person, tile-by-tile, no analog movement:

| Key | Action |
|-----|--------|
| W / ↑ | Move forward one tile |
| S / ↓ | Move back one tile |
| A / Q | Strafe left one tile |
| D / E | Strafe right one tile |
| ← | Turn left 90° |
| → | Turn right 90° |

Step onto a Pokémon's tile to start a fight — the tile beyond it is gated shut until you win.
Shop alcoves (Pokémon Center + Poké Mart) branch off the corridor at the two checkpoints,
open once that stage's mid-boss is cleared. A minimap (top-right) tracks visited tiles and
facing; your trainer portrait (bottom-left) is the only "visible you" — exploration is
pure first-person, no on-screen body.

## What's here

| Path | Purpose |
|------|---------|
| `data/balance/*.json` | Copied verbatim from the Python PoC — single source of truth |
| `art/cards/` | Real card illustrations, looked up by card id (see Card art below) |
| `scripts/core/` | Engine port: `balance_db`, `combat_ctx`, `effects`, `deck_ops`, `enemy_ai`, `items`, `shop_ops`, `rewards`, `rivals`, `run_manager` |
| `scripts/world/` | Tile-grid data model, world/wall/floor generation, procedural creature sprites, first-person player controller, encounter markers |
| `scripts/ui/` | Starter select, HUD (stats/minimap/portrait), combat overlay, draft, shop, end screens, card art/widget builders |
| `scripts/main.gd` | Flow glue: starter pick → explore → combat/draft/shop → badge or defeat |

### Python module → GDScript mapping

| Python | GDScript |
|--------|----------|
| `loader.py` / `models.py` | `core/balance_db.gd`, `core/combatant.gd`, `core/player_state.gd`, `core/enemy_state.gd` |
| `effects.py` | `core/effects.gd` |
| `deck.py` | `core/deck_ops.gd` |
| `enemy_ai.py` | `core/enemy_ai.gd` |
| `combat.py` | `core/combat_ctx.gd` |
| `items.py` | `core/items.gd` |
| `shop.py` | `core/shop_ops.gd` |
| `rewards.py` | `core/rewards.gd` |
| `rivals.py` | `core/rivals.gd` |
| `run_flow.py` | `core/run_manager.gd` (autoload `Run`) + `scripts/main.gd` |
| `cli.py` | replaced by `scripts/ui/*` |
| `player_ai.py`, `sim.py`, `analyze.py` | not ported (per handoff non-goals); see `core/sim_check.gd` below |

Turn order, damage formula, condition/status stacking, blinded budget parity, boss pattern
looping, and the draft/evolution/shop rules all match the Python reference — see
`docs/GODOT_HANDOFF.md` §"Combat turn order" for the spec this was built against. None of
`scripts/core/` changed for the world/camera rework except `run_manager.gd`'s `_setup_input()`
(discrete movement actions instead of continuous axes).

## World model

The world is a physics-free tile grid ([scripts/world/world_grid.gd](scripts/world/world_grid.gd)):
player position is always a tile center plus a cardinal facing, movement is tweened between
cells, and "can I walk here" / "did I just step on something" are dictionary lookups, not
collision callbacks. `WorldBuilder` lays the 13 encounters out along a single-file corridor
(`Route 1` → `Viridian Forest` → `Pewter`), with two shop alcoves and a small multi-tile gym
room for the Brock finale, all derived directly from `Run.encounters` — no hardcoded per-stage
layout to keep in sync.

## Card art

Cards render as a portrait trading-card layout (illustration on top, cost/type/effect text
below) via [scripts/ui/card_widget.gd](scripts/ui/card_widget.gd). Art resolution
([scripts/ui/card_art.gd](scripts/ui/card_art.gd)) checks, in order:

1. `art/cards/<card_id>_<starter_id>.png` — a starter-flavored variant (e.g. `tackle_squirtle.png`
   vs `tackle_bulbasaur.png` for a card shared by multiple starters' decks)
2. `art/cards/<card_id>.png` — generic art for that card
3. A procedural pixel-art placeholder icon, shaped by the card's type/kind, if neither exists

**To add art**: drop a PNG into `godot/art/cards/` named after the card id (check `data/balance/cards.json`
for ids), or `<card_id>_<starter_id>.png` if you want a different image per starter for a shared
card. It's picked up automatically next run — no code changes needed.

Card backgrounds/borders are tinted by `pokemon_type`, classic-TCG-style, via `CardWidget.TYPE_BG_COLORS`.
Matches the physical game's smaller color set rather than every in-game type getting its own
shade: Rock/Ground/Fighting share brown, Normal/Flying share grey, Grass/Poison/Bug share green
(Bug has no dedicated TCG energy color either — Base Set printed Bug Pokémon as Grass-type cards).

## Creature/trainer art

Same pattern as card art, one level simpler (no starter-variant suffix — a Pokémon or trainer
looks the same regardless of who you're playing). [scripts/world/creature_art.gd](scripts/world/creature_art.gd)
checks `art/creatures/<enemy_id>.png` first, falling back to `CreatureFactory`'s procedural
pixel-art sprite if no file exists. Check `data/balance/enemies.json` for ids — trainers with
multiple variants (`bug_catcher_butterfree`/`bug_catcher_beedrill`, `rival_squirtle`/
`rival_bulbasaur`/`rival_charmander`) each need their own file even if the art is identical,
since there's no generic "family" fallback (simplest option: save the same image under each id).

The three starters (`bulbasaur`/`squirtle`/`charmander`) aren't `enemies.json` entries — they
never appear as a world/creature sprite (exploration is first-person, no companion Pokémon
shown) — but `art/creatures/<starter_id>.png` is still the right place for their art, since the
starter-select screen ([scripts/ui/starter_ui.gd](scripts/ui/starter_ui.gd)) looks them up via
the same `CreatureArt.get_texture()` call.

**Coverage as of this writing**: all 6 trainers (Brock, both Bug Catcher variants, all 3 Rival
variants) and all 3 starters have real art; the 10 wild Pokémon (Geodude, Zubat, Onix, Pidgey,
Rattata, Weedle, Nidoran♂, Caterpie, Metapod, Kakuna) are still the procedural fallback.

**If your source art has a checkerboard "transparency" background baked into opaque pixels**
(no real alpha channel — check with e.g. Pillow's `Image.open(f).mode == 'RGB'` vs `'RGBA'`)
it won't cut out correctly in-engine. Two things bit us doing this for real supplied art, both
handled below:

1. **The checkerboard isn't always neutral gray** (some source art tints it, e.g. pink) — an
   achromatic-only filter silently matches nothing. Fix: sample the actual border pixel tones
   instead of assuming gray, and do it *iteratively* (keep sampling any still-uncovered border
   pixel and re-running) rather than just "top N most common" — a single fixed sample count can
   still miss a rarer tone variant and leave one corner/edge not cut out.
2. **Decorative background elements that don't touch the image border** (a light streak/swoosh
   behind the character, common in these generated sprite sheets) survive a border-flood-fill
   as disconnected islands, since the character's silhouette blocks their only path to the
   border. Fix: after the flood-fill, keep only the single largest remaining connected opaque
   component (the character) and discard everything else — smaller disconnected fragments are
   background decoration, not part of the character, even if their color doesn't match the
   plain checkerboard tone at all.

```python
import numpy as np
from PIL import Image
from scipy import ndimage

def strip_background(path, out_path, tol=12, max_iters=25):
    im = Image.open(path).convert('RGB')
    arr = np.array(im).astype(np.int16)
    h, w = arr.shape[:2]
    structure = np.array([[0,1,0],[1,1,1],[0,1,0]])

    border_mask = np.zeros((h, w), dtype=bool)
    border_mask[0,:] = border_mask[-1,:] = True
    border_mask[:,0] = border_mask[:,-1] = True

    # Pass 1: flood-fill the checkerboard from the border, sampling any
    # still-uncovered border tone iteratively (handles multi-tone/tinted
    # checkerboards without missing a rare variant).
    tones, is_bg = [], np.zeros((h, w), dtype=bool)
    for _ in range(max_iters):
        uncovered = border_mask & ~is_bg
        if not uncovered.any():
            break
        ys, xs = np.nonzero(uncovered)
        tones.append(arr[ys[0], xs[0]].copy())
        candidate = np.zeros((h, w), dtype=bool)
        for tone in tones:
            candidate |= (np.abs(arr - tone).max(axis=2) <= tol)
        labels, _ = ndimage.label(candidate, structure=structure)
        border_labels = set(labels[0,:]) | set(labels[-1,:]) | set(labels[:,0]) | set(labels[:,-1])
        border_labels.discard(0)
        is_bg = np.isin(labels, list(border_labels))

    # Pass 2: keep only the largest remaining connected component (the
    # character) — disconnected decorative elements get removed too.
    remaining = ~is_bg
    labels2, n2 = ndimage.label(remaining, structure=structure)
    if n2 > 0:
        sizes = ndimage.sum(remaining, labels2, range(1, n2 + 1))
        keep = labels2 == (int(np.argmax(sizes)) + 1)
        is_bg = is_bg | (remaining & ~keep)

    alpha = np.where(is_bg, 0, 255).astype(np.uint8)
    Image.fromarray(np.dstack([np.array(im), alpha]), 'RGBA').save(out_path)
```

**Verify it actually worked** — don't trust the image-viewer preview (it renders real alpha
transparency as a checkerboard too, so a "successful" and "still broken" file can look
identical there). Check the underlying data instead:
```python
from scipy import ndimage
import numpy as np
arr = np.array(Image.open(out_path))
labels, n = ndimage.label(arr[...,3] > 0, structure=np.array([[0,1,0],[1,1,1],[0,1,0]]))
assert n == 1, f"{n} disconnected opaque components — background removal incomplete"
```

## Player (trainer) appearance art

The player picks a trainer appearance (Boy/Girl) alongside their starter on the title screen
([scripts/ui/starter_ui.gd](scripts/ui/starter_ui.gd)); the choice is stored on `Run.trainer_appearance`
and drives the HUD portrait via [scripts/ui/portrait_factory.gd](scripts/ui/portrait_factory.gd) —
same real-art-with-procedural-fallback pattern as cards/creatures, checking `art/player/<appearance_id>.png`
(`boy.png` / `girl.png`) first. Unlike creature/card art, the player's own sprite is never
shown in the 3D world itself (exploration is first-person — the portrait is the only "visible
you"), so there's no billboard/world-placement concern here, just the HUD `TextureRect`.

**Remember `expand_mode = TextureRect.EXPAND_IGNORE_SIZE`** on any `TextureRect` showing real
(large) imported art at a small HUD size — the default `EXPAND_KEEP_SIZE` sizes the control to
`max(custom_minimum_size, texture's native pixels)`, which balloons the whole layout to fit a
1000px+ source image instead of respecting the intended small slot. Bit us once already on card
art, then again here on the portrait and the starter-select preview — three separate places so
far that needed this same one-line fix.

## Validating without the editor

`scripts/core/sim_check.gd` runs the full 13-encounter chain headlessly with a naive
"first playable card" bot (not the Python PoC's tuned heuristic AI — that's still Python-only
per the handoff's non-goals). It's a mechanics smoke test, not a balance tool:

```bash
godot --headless --path godot/ -- --simcheck
```

This exercises damage/type-chart math, all status and condition types, boss pattern
advancement, gold/draft/evolution/shop bookkeeping, and win/loss detection across every
enemy in the arc without opening a window. It only touches `scripts/core/`.

### Visual smoke test (`--visualcheck`)

`sim_check` proves the rules are correct but can't catch layout/rendering bugs (e.g. a
`TextureRect` sized wrong, a label overlapping another). `--visualcheck` runs a real
(non-headless) instance, drives it through the opening moments — spawn, look at the first
wild encounter, step into it — and saves what the camera actually saw as PNGs via
`Viewport.get_texture()` from inside the process itself, rather than an OS-level screenshot
tool (which can be unreliable — e.g. blocked entirely under some remote-desktop sessions,
even though the app is rendering correctly):

```bash
godot --path godot/ -- --visualcheck [--starter=bulbasaur|squirtle|charmander] [--appearance=boy|girl]
```

Writes a numbered sequence of PNGs to `godot/.debug_screenshots/` (gitignored) covering the
starter-select screen (appearance toggle + starter cards), spawn, turning, a forced look at
each trainer's sprite (Brock/Bug Catcher/Rival), entering combat, auto-playing a full fight to
completion, the post-fight draft, both the Center and Mart screens, and both end screens
(win/loss) — forced directly rather than requiring a full real playthrough to reach. Needs a
real renderer (don't run this one `--headless`) — Vulkan/GL both work.

## Known first-pass gaps (candidates for the next pass)

- Card art exists only for the 6 starter/basic attacks supplied so far (Ember, Scratch,
  Water Gun, Vine Whip, Tackle ×2 starter variants); everything else uses the procedural
  placeholder icon until more art is supplied.
- Trainer art (Brock, Bug Catcher, Rival) has a very faint color fringe at the alpha cutout
  edge on some pixels (anti-aliased boundary pixels from the source art landing just above
  Godot's alpha-cutoff threshold render at full opacity with a slightly blended color) — minor
  and easy to miss, not worth chasing further without risking overfitting the background-removal
  heuristic to these specific images.
- No audio.
- Sim-check uses a dumb bot; the Python `player_ai.py` heuristics were intentionally not
  ported (see non-goals in the handoff doc) — use the Python sim for balance regression.
- No camera collision avoidance beyond the tile-grid's own wall placement (walls are exactly
  tile-aligned, so this is less of an issue than in the free-roam first pass, but corners
  aren't chamfered/decorated).
- World layout (corridor length, alcove/room placement) is new for this port — not specified
  by the PoC, which only defined encounter order, not geography.
