# Godot Handoff — Pokémon Crawlers PoC

This document translates the **frozen Python PoC** into an implementation plan for Godot 4. The PoC is validated for the **Kanto opening slice** (Route/Viridian → Viridian Forest → Pewter). Balance numbers live in `data/balance/`; behavior reference lives in `src/pokemon_crawlers/`.

**Authoritative summaries**

- [POC_FINDINGS.md](../POC_FINDINGS.md) — frozen baseline, design decisions, Charmander note
- [POC_BALANCE_TUNING.md](POC_BALANCE_TUNING.md) — milestone history and sim KPIs

---

## Frozen PoC baseline (do not re-tune in Godot v1)

| Setting | Value |
|---------|--------|
| Type chart | 2.0× super effective / 0.5× resisted |
| Hand size | 4 |
| Max stamina | 3 per turn |
| Starter STAB | Vine Whip / Water Gun / Ember — cost 2, power 10 |
| Body Slam / Hyper Fang | cost 3 |
| Gold | Wild 3–6, mid-boss 18 |
| Center | 30g, full heal, +3 max HP |
| Inventory | 3 slots, max 2 of same item type |
| Items in combat | 1 per player turn (free action) |
| Rival | Counter-type vs player starter |
| STAB draft | 15% chance one option is starter signature |

**Regression sim** (optional, local logs gitignored):

```bash
python -m pokemon_crawlers.sim --runs 3000 --seed 42 --starter all \
  --shop-policy greedy --play-style balanced \
  --runs-dir runs/v2/regression-baseline/
python -m pokemon_crawlers.analyze runs/v2/regression-baseline/ --json
```

Expect ~33% overall win rate (greedy shop). Human-like healing (`--shop-policy potions`) lands ~50%.

---

## PoC module map → Godot systems

| Python module | Responsibility | Port priority |
|---------------|----------------|---------------|
| `loader.py` | JSON → typed balance | P0 — copy schema |
| `models.py` | Enums + dataclasses | P0 |
| `effects.py` | Damage, block, status, conditions, type modifiers | P0 |
| `combat.py` | Turn loop, play card, enemy turn, outcomes | P0 |
| `deck.py` | Draw, discard, shuffle, add card | P0 |
| `enemy_ai.py` | Wild + boss pattern selection | P1 |
| `items.py` | Inventory + in-combat item use | P1 |
| `shop.py` | Center + Mart purchases | P1 |
| `rewards.py` | Draft options, evolution, boss rewards | P1 |
| `run_flow.py` | Full Kanto chain orchestration | P1 |
| `rivals.py` | Counter-type Rival enemy id | P1 |
| `cli.py` | UX reference only | P2 (replace with scenes) |
| `player_ai.py` | Sim heuristics | Skip in Godot v1 |
| `sim.py` / `analyze.py` | Balance tooling | Keep Python sidecar |

---

## Recommended implementation phases

### Phase 0 — Data layer (1–2 days)

- [ ] Copy `data/balance/*.json` into Godot project (or load from repo path in dev)
- [ ] Implement loader validating same fields as `loader.py` (fail fast on unknown ids)
- [ ] Resource types or plain dictionaries matching `models.py` enums
- [ ] Unit tests: load balance, type chart lookup, one card effect parse

### Phase 1 — Combat vertical slice (core)

**Goal:** One interactive fight (e.g. Geodude) with deck, stamina, types, block, one status.

- [ ] `CombatContext`: player, enemy, balance, turn counter, boss pattern index
- [ ] Player turn: draw to hand size → play cards until end turn or out of stamina
- [ ] `can_play_card`: stamina, hand index, Defensive Curl + block rules
- [ ] `play_card` → `resolve_card_effects` (damage, block, heal, apply_condition, status)
- [ ] Type modifier from `type_chart.json` on damage
- [ ] Conditions: intimidated, distracted, blinded (budget), defenseless, slow
- [ ] Statuses: sleep (skip turn), paralyze (skip attack), confuse (self-dmg), poison (tick, ignores block)
- [ ] Enemy turn: poison tick → pick action (wild or pattern) → resolve → decrement durations
- [ ] Win/loss when HP ≤ 0
- [ ] UI: hand, HP, stamina, block, enemy intent line, enemy action recap

**Reference:** `combat.py`, `effects.py`, `enemy_ai.py`

### Phase 2 — Economy vertical slice

**Goal:** Shop after one mid-boss; Center + Mart; inventory cap.

- [ ] Player state: gold, inventory, center_visits, max_hp
- [ ] Shop window 1 vs 2 item lists from `items.json`
- [ ] `purchase_center`, `purchase_item` rules
- [ ] Between-fight: full heal to max_hp (no stamina reset mid-run except turn start)

**Reference:** `shop.py`, `items.py`

### Phase 3 — Run orchestration

**Goal:** Full 13-fight Kanto arc in Godot.

- [ ] Load `run_config.json` stages (wild pool, wild count, mid_boss, shop_after, reward_pool_key)
- [ ] Wild fights → draft (3 options, STAB injection) → mid-boss → shop → repeat
- [ ] Evolution catalyst after Rival (`run_config.evolution`)
- [ ] Pewter sequence from `pewter_encounter_sequence`
- [ ] Brock: badge + signature card (`grant_boss_rewards`)
- [ ] Counter Rival: map starter → `rival_squirtle` / `rival_bulbasaur` / `rival_charmander`

**Reference:** `run_flow.py`, `rewards.py`, `rivals.py`

### Phase 4 — Polish & parity

- [ ] Draft UI (skip allowed)
- [ ] In-combat items (1/turn, slot display)
- [ ] Run log JSON compatible with `analyze.py` (optional, for continued tuning)
- [ ] Audio/VFX hooks at effect resolution boundaries

---

## Data contract (`data/balance/`)

| File | Purpose |
|------|---------|
| `constants.json` | player max_hp, max_stamina, hand_size, draft_options, starter_stab_draft_chance |
| `type_chart.json` | attacker/defender/matchup multipliers |
| `conditions.json` | Condition definitions (mults, blinded budget, slow stamina) |
| `cards.json` | All cards + effect arrays |
| `starters.json` | starter id → deck list |
| `enemies.json` | Enemy defs, action pools, boss patterns |
| `items.json` | Shop items + gold table |
| `badges.json` | Badge metadata (PoC: Boulder) |
| `run_config.json` | Stages, Pewter sequence, evolution, economy flags |
| `stage_rewards.json` | Draft pools per stage (`stage1`, `stage2`, `stage3`) |

### Card effect types (must all work in v1 combat)

| `type` | Notes |
|--------|--------|
| `damage` | Apply type chart; respect block unless `ignore_block` |
| `block` | Add to player block; Defenseless blocks gain |
| `heal` | Cap at max_hp |
| `status` | sleep / paralyze / confuse / poison with duration + magnitude |
| `apply_condition` | intimidated, distracted, blinded, defenseless, slow |
| `draw` | Draw N cards (rare in PoC cards) |

### Item effect types

| `type` | Notes |
|--------|--------|
| `heal` | Out of combat or in combat |
| `cure_status` | Single status |
| `cure_all_statuses` | Full Heal |
| `revive` | Not in PoC shop |

---

## Combat turn order (must match PoC)

**Player turn start**

1. Increment turn, clear player block, apply slow stamina modifiers
2. Tick poison on player
3. If asleep: tick statuses/conditions, discard hand, skip to enemy
4. Else: tick statuses/conditions, draw to hand size

**Player actions** (loop)

- Play card (pay stamina) and/or use item (max 1, no stamina)
- End turn → discard hand

**Enemy turn**

1. Clear enemy block
2. Tick poison on enemy (may end fight)
3. Choose action (pattern or wild AI); show intent was set at previous turn end
4. If enemy asleep: advance pattern only
5. Else: tick enemy statuses/conditions; if paralyzed and attack, skip damage
6. Confuse self-damage if applicable
7. Resolve action effects
8. Advance boss pattern index

---

## Run flow (Kanto arc)

```
Starter pick
  → Stage route_viridian: 3 wild → draft each → Rival → draft → evolution? → Shop 1
  → Stage viridian_forest: 3 wild → draft → Bug Catcher (RNG) → Shop 2
  → Pewter: geodude → draft → zubat → draft → onix → draft → geodude → draft → brock
  → Win: badge + Rock Slide
```

Between fights: restore stamina to max; HP persists unless item/Center.

---

## UI/UX notes from PoC CLI

- Show **enemy intent** at start of player turn (`next_enemy_action_name` for pattern enemies)
- After enemy turn, show **what they used** and damage taken
- Items: display `1. Potion [potion]`; accept slot or id
- Shop: Center vs Mart; show gold and inventory slots
- Draft: 3 options + skip

---

## Explicit non-goals for Godot v1

- Porting `player_ai.py` (use human input only)
- Full sim batch in Godot (keep Python `pokemon_crawlers.sim`)
- Regions beyond Pewter / post-Brock progression
- Rare draft weighting by `rarity` (still flat pools; optional later)
- Multiplayer, saves, meta progression

---

## Charmander & balance philosophy

Early Fire weakness vs Rock is **intentional** for this slice. Do not “fix” in Godot by softening Pewter unless playtests feel unfair. Plan later-game type coverage and drafts for Charmander in the full roguelite arc.

---

## PRD sync checklist (after Godot v1 slice)

- [ ] Type effectiveness display (2.0 / 0.5 or qualitative)
- [ ] Card schema and effect pipeline
- [ ] Status vs condition semantics
- [ ] Shop / Center / inventory rules
- [ ] Evolution timing (post-Rival default)
- [ ] Starter decks and STAB draft injection rate

---

## Suggested first Godot milestone

**“Geodude in a box”** — Squirtle starter, one wild fight, hand UI, type-effective Water Gun, win/loss screen. Proves combat + data loading before run map or shops.

When that feels right, add **Rival + Shop 1 + one draft**, then wire the full stage loop.
