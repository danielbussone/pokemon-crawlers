# Pokémon Crawlers — PoC Findings

> Sim-backed notes from the 3-stage Kanto arc + economy expansion. Update after manual playtests.
> **Structured tuning log (deltas + KPI tables + meta):** [docs/POC_BALANCE_TUNING.md](docs/POC_BALANCE_TUNING.md)
> PRD sync happens here — not before PoC validation.

## PoC baseline (frozen)

**Committed config in `data/balance/`** (May 2026):

| Setting | Value |
|---------|--------|
| Type chart | **2.0× super / 0.5× resist** |
| Hand size | 4 |
| Starter signatures | Vine Whip / Water Gun / Ember — cost 2, power 10 |
| Body Slam / Hyper Fang | **cost 3** |
| Economy | Wild 3–6g, mid-boss 18g; Center 30g (+3 max HP) |
| Rival | Counter-type starter (typed mid-boss) |
| Draft | 15% chance per pick to offer starter STAB card |

**Reference sim batches** (local, `runs/v2/`, gitignored):

- **Greedy / pessimistic:** `m6-play-balanced-card-cost` (~33% overall WR, seed 42, 3000 runs)
- **Human-like healing:** `m6-shop-potions-card-cost` (~51% overall WR)

**Charmander:** Early Kanto weakness vs Rock is **accepted** for this PoC. This slice ends at Brock; Fire is expected to struggle here and gain relative strength in later regions/gyms in the full game. No further Charmander-specific tuning required for PoC sign-off.

**Godot handoff:** [docs/GODOT_HANDOFF.md](docs/GODOT_HANDOFF.md)

---

## Test conditions

- **Runs completed:** 1000+ per configuration (heuristic AI)
- **Run log directories:**
  - `runs/v2/` — 3-stage arc, **2.0× / 0.5×** type chart (pre-softening)
  - `runs/v2/soft-chart/` — same arc, **1.5× / 0.75×** type chart (adopted)
  - `runs/v2/soft-chart-charm/` — Charmander-only, soft chart, 500 runs
- **Starters tested:** Bulbasaur / Squirtle / Charmander (rotated or isolated)
- **Balance config:** `data/balance/` — `type_chart.json` is the primary lever documented below
- **Sim flags:** `--seed 42`, `--shop-policy greedy|potions`, `--play-style balanced|aggressive|conservative`
- **Date range:** 2026-05-25 – 2026-05-26

---

## Type chart change: 2.0× / 0.5× → 1.5× / 0.75× (experiment) → 2.0× / 0.5× (PoC ship)

**Historical experiment:** **1.5× super effective / 0.75× resisted** was tested to fix Charmander vs Pewter; it raised overall win rate to ~69% (too easy). Neutral matchups remain 1.0×.

**PoC ship decision:** Revert to **2.0× / 0.5×** for overall difficulty in the 25–40% band with M6 knobs (see [docs/POC_BALANCE_TUNING.md](docs/POC_BALANCE_TUNING.md) M5–M6).

**Rationale:** In this combat model (low HP pool, damage-only type scaling, short fights), classic Pokémon multipliers created a **4× spread** between super and resist on the same base power. Pewter Rock at 0.5× effectively doubled enemy effective HP for Fire, overwhelming the 3-stage onboarding arc. Softer multipliers compress starter spread while preserving type identity.

### Comparison (seed 42, 1000 runs, all starters, greedy shop)

| Metric | 2.0 / 0.5 (`runs/v2`) | 1.5 / 0.75 (`runs/v2/soft-chart`) | Plan target |
|--------|------------------------|-------------------------------------|-------------|
| Overall win rate | 49.0% | **69.1%** | 25–40% |
| Bulbasaur | 68.4% | 83.2% | — |
| Squirtle | 75.2% | 79.8% | — |
| **Charmander** | **5.2%** | **45.3%** | ≥ 15% floor |
| Brock reach rate | ~97.7% | 98.9% | ≥ 50% |
| HP entering Pewter (% max) | ~91.4% | ~92.0% | 50–65% |
| Rival win rate | 100% | 100% | ≥ 85% |

### Loss location shift (all starters)

| Loss at enemy | 2.0 / 0.5 | 1.5 / 0.75 |
|---------------|-----------|--------------|
| Onix | 212 | **33** |
| Geodude | 102 | **40** |
| Brock | 179 | **224** |
| Bug Catcher (Butterfree) | 22 | 11 |

Onix was the Charmander wall under hard resist; after softening, **Brock becomes the primary gate** — correct shape for a gym finale.

### Charmander-only (seed 42, soft chart, 500 runs)

| Metric | ~2.0 / 0.5 (300 runs, prior) | 1.5 / 0.75 (500 runs) |
|--------|------------------------------|------------------------|
| Win rate | ~6.7% | **40.6%** |
| Losses | Onix 165, Geodude 73, Brock 41 | Brock 190, Onix 58, Geodude 48 |
| Brock win rate when reached | — | 51.7% |

Fire → Rock: **0.75×** (was 0.5×) — ~50% more damage per attack vs Rock. Fire → Bug: **1.5×** (was 2.0×) — Stage 2 still favorable, less spike.

### Conclusions

- **Keep 1.5 / 0.75** for PoC and Godot handoff unless UX demands classic Pokémon numbers (would need separate tuning for HP/stamina scale).
- Chart fix **does not** bring overall difficulty into plan band alone — 69% aggregate is still **too easy**.
- Do **not** revert chart to fix difficulty; tune Pewter/Brock, Center pricing, or early attrition next.
- Starter spread improved (5% → 45% Charmander) but remains wide (45% vs 83% Bulbasaur) — acceptable for PoC, monitor in manual play.

### Recommended next tuning (with soft chart held constant)

1. **Brock** — small HP or damage increase (pull aggregate win rate toward 25–40%).
2. **Pokémon Center** — 35g and/or +2 max HP instead of +3 (reduce ~92% HP entering Pewter).
3. **Stage 1 wilds** — minor damage bump if Rival should sit below 100% (optional).

---

## Type chart & starters

- Win rate by starter (soft chart, seed 42): Bulbasaur 83%, Squirtle 80%, Charmander 45%.
- Charmander Pewter: playable; Brock is the skill check (51.7% win rate when Brock reached in Charmander-only batch).
- **Recommendations:** Document 1.5/0.75 in PRD as default; show “effective / resisted” in UI, not necessarily “×2 / ×½”.

---

## Stage attrition

- Stage 1 Rival win rate: **100%** (both chart configs) — Stage 1 may be too soft, not a type-chart issue.
- HP entering Pewter: **~92% of max** — far above 50–65% target; economy (Center + greedy shop) dominates.
- Brock reach rate: **≥ 98%** — onboarding arc succeeds.
- Butterfree vs Beedrill: both **≥ 97%** win rate under soft chart; delta well under 15pp.
- **Recommendations:** Attrition tuning is independent of type chart; prioritize Center cost and Pewter enemy pressure.

---

## Economy & shops

- Avg gold per run (soft chart batch): ~105g (in line with design).
- Center visits: ~1.3/run; max HP distribution heavily **33** and **36** (Center compounding works).
- **Recommendations:** Center is very attractive at 30g + 3 HP; consider 35g or +2 HP when lowering overall win rate.

---

## Enemy balance (Pewter)

- Under soft chart, losses concentrate on **Brock**, then Geodude, then Onix (reversed from hard chart).
- Avg HP before Brock (wins): ~20.3 / median 21 (on ~33–36 max HP).
- Brock win rate when reached (all starters): **75.5%** (soft chart, 1000 runs).
- **Recommendations:** Brock is the right lever for global difficulty post-chart-change.

---

## Stamina economy

- Avg cards played per turn: *(not yet extracted from logs)*
- Target guideline: 1.8–2.5
- **Recommendations:** Revisit after Pewter difficulty pass; deck size grew with per-win drafts.

---

## Hand size & deck cycling

- Deck grows ~6 → 12+ cards before Brock with per-win drafts.
- **Recommendations:** Stage-scoped pools help; track `avg_deck_size_entering_brock` in a future analyze pass.

---

## Conditions & statuses

- Status curve (Poison → Sleep/Confuse → full Pewter) implemented; no chart interaction.
- **Recommendations:** Manual playtest for Butterfree telegraph feel.

---

## Item usage

- Greedy AI buys Antidote/Awakening/Potion heavily before Forest/Pewter.
- `antidote_purchase_rate` in analyze counts purchases not runs — ignore until metric fixed.
- **Recommendations:** Fix analyze metric; validate Antidote as prep item in manual runs.

---

## Status curve feel

- *(Manual playtest pending)*
- **Recommendations:** Confirm Confuse debut on Butterfree reads fair with soft chart damage.

---

## Reward draft & progression

- Dominant sim picks: bite, body_slam, quick_attack, harden.
- Evolution post-Rival: ~84% of runs apply catalyst.
- **Recommendations:** Consider `evolution_trigger: post_bug_catcher` A/B if Charmander needs more Stage 2 power (less critical after soft chart).

---

## Recommended MVP adjustments (for Godot)

1. **Type chart:** **2.0× / 0.5×** as in PoC JSON; UI can show qualitative effectiveness, not necessarily classic multipliers.
2. **Early game:** Accept Fire weakness through Brock; plan later-region payoff for Charmander in full roguelite arc.
3. **Economy:** Center 30g/+3 HP and gold curve as tuned; greedy sim undervalues potions — human players heal more (`--shop-policy potions` for comparison).
4. **Cards:** Body Slam / Hyper Fang at **cost 3**; consider rare-pool weighting when draft system grows.

---

## PRD sections to update later

- [ ] Type effectiveness multipliers (2.0 / 0.5 in PoC; UI copy)
- [ ] Card model (`pokemon_type`, conditions)
- [ ] Status / condition semantics
- [ ] Starter deck compositions
- [ ] Badge effects (placeholders only in PoC)
- [ ] Shop / Center / inventory rules

---

## Open questions for Godot phase

- Should resisted matchups show “0.75×” or qualitative “Not very effective…” only?
- Does manual play at M6 baseline feel fair for Squirtle/Bulbasaur and appropriately hard for Charmander pre-Brock?
- When extending past Pewter, how should Fire’s power curve catch up without invalidating early Rock tension?
