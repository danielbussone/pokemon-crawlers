# PoC Balance Tuning Log

Living artifact for **what we changed**, **how KPIs moved**, and **what we infer**.  
Complements [POC_FINDINGS.md](../POC_FINDINGS.md) (recommendations) and `data/balance/` (source of truth for numbers).

**How to update after a tuning pass**

1. Add a row to [Change log](#change-log) (delta).
2. Run sims into a **new** directory: `runs/v2/<label>/` (do not mix configs in one folder).
3. Copy KPI block from `python -m pokemon_crawlers.analyze runs/v2/<label>/ --json`.
4. Fill [KPI snapshot](#kpi-snapshots) and [KPI deltas](#kpi-deltas).
5. Extend [Meta analysis](#meta-analysis).

**Standard sim command**

```bash
python -m pokemon_crawlers.sim --runs 1000 --seed 42 --starter all \
  --shop-policy greedy --runs-dir runs/v2/<label>
```

---

## KPI definitions

| KPI | Definition | Plan target (Kanto arc) |
|-----|------------|-------------------------|
| `overall_win_rate` | `run_complete` / all runs | 25–40% |
| `win_rate_<starter>` | Wins / runs per starter | Charmander ≥ 15%; spread ≤ ~30pp |
| `brock_reach_rate` | Runs with ≥1 Pewter encounter / all | ≥ 50% |
| `brock_win_when_reached` | Brock wins / runs that reached Brock | ~50–60% |
| `stage1_rival_win_rate` | Wins vs any `rival_*` encounter / rival fights | 70–90% (counter-type) |
| `stage2_bf_vs_be_delta` | \|Butterfree WR − Beedrill WR\| | ≤ 15pp |
| `hp_entering_pewter_pct` | First Pewter fight `hp_before` / `max_hp_final` × 100 | 50–65% |
| `avg_hp_before_brock` | Mean HP before Brock encounter | Contextual (higher = easier) |
| `loss_at_<enemy>` | Count of run-ending loss at enemy | Shape: Pewter > early |
| `avg_gold_per_run` | Mean `gold_earned` on RunLog | ~45–55g before shop 1 (partial run) |
| `avg_center_visits` | Mean Center purchases per run | 40–70% of runs visit ≥1 (policy-dependent) |
| `max_hp_final_dist` | Histogram of `max_hp_final` (30/33/36) | Bimodal if Center attractive |

---

## Configuration milestones

| ID | Label | Run mode | Type chart | Stages | Economy | Log dir |
|----|-------|----------|------------|--------|---------|---------|
| **M0** | Pewter-only (pre-expansion) | 5 fights | 2.0 / 0.5 | — | None | `runs/` (~1632) |
| **M1** | Kanto arc + economy | 13 fights | 2.0 / 0.5 | 1–2 + Pewter | Gold, shops, items | `runs/v2/` (~1020) |
| **M2** | Kanto + soft type chart | 13 fights | **1.5 / 0.75** | Same | Same | `runs/v2/soft-chart/` (1000) |
| **M3** | M2, Charmander only | 13 fights | 1.5 / 0.75 | Same | Same | `runs/v2/soft-chart-charm/` (500) |
| **M4** | M2 + counter Rival + gold trim | 13 fights | 1.5 / 0.75 | Same | wild 3–6, rival 18g | `runs/v2/counter-rival-gold/` (1000) |
| **M5** | M4 + **hard type chart** | 13 fights | **2.0 / 0.5** | Same | Same economy | `runs/v2/hard-chart-m4/` (3000) |
| **M6** | M5 + VW/WG parity + **hand 4** | 13 fights | 2.0 / 0.5 | Same | hand_size 4, VW/WG 2/10 | `runs/v2/hard-chart-buff-hand4/` (3000) |
| **M6a** | M5 + VW/WG only | — | 2.0 / 0.5 | hand 3 | `runs/v2/buff-vw-wg/` (3000) |
| **M6b** | M5 + hand 4 only | — | 2.0 / 0.5 | hand 4 | `runs/v2/4-card-hand/` (1000) |

*M1/M2 use `--seed 42`, `--shop-policy greedy` unless noted.*

---

## Change log

Deltas applied in order. Each row should link to a milestone or new milestone ID.

| # | Date | Milestone | Change | Files / systems | Intent |
|---|------|-----------|--------|-----------------|--------|
| 1 | 2026-05-25 | M0→M1 | **3-stage run** (Route/Viridian → Forest → Pewter) | `run_config.json`, `enemies.json`, `run_flow.py` | Onboarding before Rock; fix starter viability |
| 2 | 2026-05-25 | M1 | **Mid-bosses**: Rival (pattern), Bug Catcher 50/50 BF/Beedrill | `enemies.json`, `enemy_ai.py` | Tutorial intent; telegraphed statuses |
| 3 | 2026-05-25 | M1 | **Status curve**: Poison S1 → Sleep/Confuse S2 → full Pewter | Wild + boss pools | Gradual introduction |
| 4 | 2026-05-25 | M1 | **Gold + shops** after mid-bosses; no in-stage heal | `items.json`, `shop.py`, `player_ai.py` | Prep layer; Center 30g +3 max HP |
| 5 | 2026-05-25 | M1 | **Inventory**: 3 slots, max 2/type; 1 item/player turn | `items.py`, `combat.py` | Safety net without stamina tax |
| 6 | 2026-05-25 | M1 | **Stage-scoped draft pools** | `stage_rewards.json` | Control deck bloat quality |
| 7 | 2026-05-25 | M1 | **Evolution post-Rival** | `run_config.json` | Power spike before Forest |
| 8 | 2026-05-25 | M1 | **BUG/GROUND** type entries | `type_chart.json` | Stage 2 Fire/Grass breakout |
| 9 | 2026-05-25 | M1→M2 | **Type chart soften**: 2.0/0.5 → **1.5/0.75** | `type_chart.json` | Reduce resist brutality in low-HP combat |
| 10 | 2026-05-26 | M4 | **Counter-type Rival** (Squirtle vs Charmander, etc.); typed STAB 8 dmg | `enemies.json`, `rivals.py`, `run_flow.py` | Rival losses > 0; type lesson |
| 11 | 2026-05-26 | M4 | **Gold trim**: wild 3–6g, mid-boss 18g (was 5–10 / 30) | `items.json` | Shop 1: Center OR Super Potion, not both comfortably |
| 12 | 2026-05-26 | M4 | **Combat UX**: item slot/id in UI; enemy turn log line | `cli.py`, `combat.py` | Playtest friction |
| 13 | 2026-05-26 | M5 | **Type chart revert**: 1.5/0.75 → **2.0/0.5** | `type_chart.json` | Re-test M4 economy + counter Rival at scale |
| 14 | 2026-05-26 | M6 | VW/WG **cost 2 / power 10**; **hand_size 4** | `cards.json`, `constants.json` | Starter parity + draw consistency |
| 15 | 2026-05-26 | PoC freeze | **Charmander early weakness accepted**; M6 + cost-3 BS/HF baseline | docs | Fire payoff deferred to post-Brock game |
| 16 | — | *next* | Godot handoff / PRD sync | TBD | — |

---

## KPI snapshots

### M0 — Pewter-only (historical, ~1632 runs)

| KPI | Value |
|-----|-------|
| overall_win_rate | **30.7%** |
| win_rate_bulbasaur | 51.0% |
| win_rate_squirtle | 38.5% |
| win_rate_charmander | **0.0%** |
| brock_reach_rate | ~55.6% (905/1632 reached Brock) |
| brock_win_when_reached | 55.4% |
| avg_hp_before_brock | **13.7** / 30 (~46% max) |
| loss_at (top) | geodude 541, brock 404, onix 172, zubat 14 |

*No Stages 1–2, economy, or items.*

---

### M1 — Kanto arc, 2.0 / 0.5 type chart

**Sim:** `runs/v2/` · 1020 runs · seed 42 · greedy shop

| KPI | Value |
|-----|-------|
| overall_win_rate | **49.0%** |
| win_rate_bulbasaur | 68.4% |
| win_rate_squirtle | 75.2% |
| win_rate_charmander | **5.2%** |
| brock_reach_rate | 97.7% |
| brock_win_when_reached | 73.6% |
| stage1_rival_win_rate | 100% |
| stage2_butterfree_win_rate | 95.9% |
| stage2_beedrill_win_rate | 100% |
| hp_entering_pewter_pct | 91.4% |
| avg_hp_before_brock | 19.3 |
| avg_gold_per_run | 104.5 |
| avg_center_visits | 1.31 |
| max_hp_final_dist | 30: 1, 33: 701, 36: 318 |
| evolution_applied | 81.4% |
| loss_at (top) | onix 212, brock 179, geodude 102, butterfree 22, zubat 4 |

---

### M2 — Kanto arc, 1.5 / 0.75 type chart (historical soft chart)

**Sim:** `runs/v2/soft-chart/` · 1000 runs · seed 42 · greedy shop

| KPI | Value |
|-----|-------|
| overall_win_rate | **69.1%** |
| win_rate_bulbasaur | 83.2% |
| win_rate_squirtle | 79.8% |
| win_rate_charmander | **45.3%** |
| brock_reach_rate | 98.9% |
| brock_win_when_reached | 75.5% |
| stage1_rival_win_rate | 100% |
| stage2_butterfree_win_rate | 97.9% |
| stage2_beedrill_win_rate | 100% |
| hp_entering_pewter_pct | 92.0% |
| avg_hp_before_brock | 20.3 |
| avg_gold_per_run | *(see analyze)* |
| avg_center_visits | *(see analyze)* |
| max_hp_final_dist | *(see analyze)* |
| loss_at (top) | **brock 224**, geodude 40, onix 33, butterfree 11, zubat 1 |

---

### M6 — M5 + starter parity + hand 4 (combined)

**Sim:** `runs/v2/hard-chart-buff-hand4/` · **3000** runs · seed 42 · greedy shop

| KPI | Value |
|-----|-------|
| overall_win_rate | **40.6%** |
| win_rate_bulbasaur | **54.9%** |
| win_rate_squirtle | **54.9%** |
| win_rate_charmander | **13.5%** |
| brock_reach_rate | 94.7% |
| brock_win_when_reached | 66.0% |
| stage1_rival_win_rate | 97.7% |
| avg_hp_before_brock | 17.9 |
| loss_at (top) | **onix 650**, **brock 627**, geodude 337, butterfree 88 |

*Loss gates split evenly Brock/Onix; Grass/Squirt tied; Fire still weak at Pewter (Onix 486 Charmander losses).*

#### M6 AI / shop matrix (3000 runs, seed 42)

| Run dir | Shop | Play | WR% | Ch% | Sq% | Bu% |
|---------|------|------|-----|-----|-----|-----|
| `m6-play-balanced` | greedy | balanced | 39.6 | 10.8 | 55.1 | 54.5 |
| `m6-play-aggressive` | greedy | aggressive | 41.6 | 14.8 | 53.2 | 58.3 |
| `m6-play-conservative` | greedy | conservative | 38.2 | 5.3 | 58.1 | 52.8 |
| `m6-shop-potions` | potions | balanced | **56.8** | 23.1 | 80.5 | 68.4 |
| `m6-potions-aggressive` | potions | aggressive | **57.9** | **26.7** | 76.9 | 71.7 |
| `m6-potions-conservative` | potions | conservative | 52.8 | 14.6 | **79.1** | 66.5 |

*Same rows with `-card-cost` suffix: Body Slam / Hyper Fang **cost 3** (−4.7 to −9.0pp overall vs matching row).*

**Inference:** Potions-only shop ≈ **+17pp** vs greedy (human-like healing undervalued by status-item greedy AI). BS/HF cost 3 is a real nerf (−6pp typical) but potions configs still ~50% WR.

---

### M5 — M4 + hard type chart (2.0 / 0.5)

**Sim:** `runs/v2/hard-chart-m4/` · **3000** runs · seed 42 · greedy shop

| KPI | Value |
|-----|-------|
| overall_win_rate | **23.3%** |
| win_rate_bulbasaur | 31.0% |
| win_rate_squirtle | 34.3% |
| win_rate_charmander | **5.6%** |
| brock_reach_rate | 85.9% |
| brock_win_when_reached | 53.3% |
| stage1_rival_win_rate | **92.8%** |
| stage2_butterfree_win_rate | 86.6% |
| avg_gold_per_run | 58.1 |
| avg_hp_before_brock | 15.6 |
| loss_at (top) | **onix 785**, brock 614, geodude 456, butterfree 191, rival_charmander 114 |

*Rival losses by starter counter: Bulbasaur→Rival Charmander 88% WR; Squirtle→Bulbasaur 91.3%; Charmander→Squirtle 98.6%.*

---

### M4 — Counter Rival + gold trim (M2 baseline)

**Sim:** `runs/v2/counter-rival-gold/` · 1000 runs · seed 42 · greedy shop

| KPI | Value |
|-----|-------|
| overall_win_rate | **57.7%** |
| win_rate_bulbasaur | 71.7% |
| win_rate_squirtle | 70.3% |
| win_rate_charmander | **32.2%** |
| brock_reach_rate | 95.4% |
| brock_win_when_reached | 70.5% |
| stage1_rival_win_rate | **99.7%** (3 losses / 1000) |
| stage2_butterfree_win_rate | 91.8% |
| stage2_beedrill_win_rate | 100% |
| hp_entering_pewter_pct | 91.3% |
| avg_hp_before_brock | 18.9 |
| avg_gold_per_run | **62.0** |
| avg_center_visits | 1.23 |
| max_hp_final_dist | 30: 28, 33: 713, 36: 259 |
| loss_at (top) | **brock 241**, onix 84, geodude 50, butterfree 43, rival_* 3 |

*Stage 1 gold ~31g avg (11–36) — Center (30g) is tight; 28 runs end shop 1 at max HP 30.*

---

### M3 — M2, Charmander-only

**Sim:** `runs/v2/soft-chart-charm/` · 500 runs · seed 42

| KPI | Value |
|-----|-------|
| overall_win_rate | **40.6%** |
| win_rate_charmander | 40.6% |
| brock_reach_rate | 78.6% (393/500) |
| brock_win_when_reached | **51.7%** |
| avg_hp_before_brock | 16.4 |
| loss_at (top) | brock 190, onix 58, geodude 48, butterfree 1 |

---

## KPI deltas

### M0 → M1 (Pewter-only → full Kanto + economy)

| KPI | M0 | M1 | Δ | Notes |
|-----|----|----|---|-------|
| overall_win_rate | 30.7% | 49.0% | **+18.3pp** | More fights but drafts + shops + stages |
| charmander | 0% | 5.2% | +5.2pp | Still unplayable in sim |
| brock_reach_rate | ~56% | 98% | **+42pp** | Almost everyone reaches Pewter |
| avg_hp_before_brock | 13.7 | 19.3 | +5.6 HP | Centers + longer runway |
| loss_at onix | 172 | 212 | +40 | Still Charmander killer under hard chart |
| Primary loss shape | Geodude spike early | Onix > Brock | — | Arc moved problem, didn’t fix Fire |

**Inference:** Expansion achieves onboarding and reach; **type disadvantage at Pewter still dominates Fire** under 2.0/0.5.

---

### M1 → M2 (hard chart → soft chart)

| KPI | M1 | M2 | Δ | vs plan target |
|-----|----|----|---|----------------|
| overall_win_rate | 49.0% | 69.1% | **+20.1pp** | Above 25–40% band |
| charmander | 5.2% | 45.3% | **+40.1pp** | Above 15% floor ✓ |
| bulbasaur | 68.4% | 83.2% | +14.8pp | Very easy |
| squirtle | 75.2% | 79.8% | +4.6pp | Very easy |
| loss_at onix | 212 | 33 | **−179** | Onix no longer Charmander wall |
| loss_at brock | 179 | 224 | +45 | Brock is primary gate ✓ |
| loss_at geodude | 102 | 40 | −62 | Pewter opener easier |
| avg_hp_before_brock | 19.3 | 20.3 | +1.0 | Slightly easier |
| hp_entering_pewter_pct | 91.4% | 92.0% | +0.6pp | Still far above 50–65% |

**Inference:** Soft chart is **necessary but not sufficient** for balance. Fixes Fire viability; **overall difficulty too high** for roguelite target. Next knobs: Brock, Center, not chart revert.

---

### M2 → M4 (counter Rival + gold trim)

| KPI | M2 | M4 | Δ | Notes |
|-----|----|----|---|-------|
| overall_win_rate | 69.1% | 57.7% | **−11.4pp** | Moving toward 25–40% band |
| charmander | 45.3% | 32.2% | −13.1pp | Mostly Pewter (Onix 72, Brock 115), not Rival |
| squirtle | 79.8% | 70.3% | −9.5pp | |
| bulbasaur | 83.2% | 71.7% | −11.5pp | Butterfree losses 11 → 43 |
| stage1_rival_win_rate | 100% | 99.7% | −0.3pp | **3 rival losses** in 1000 runs |
| avg_gold_per_run | 104.9 | 62.0 | **−43g** | Trim worked |
| loss_at butterfree | 11 | 43 | +32 | Less healing budget post-shop 1 |
| loss_at onix | 33 | 84 | +51 | Charmander attrition |
| max_hp 30 (no Center) | ~0 | 28 runs | — | Can't afford 30g after stage 1 |

**Inference:** Gold trim is doing real work; **counter Rival barely moves sim KPIs** (greedy AI still stomps). To make Rival a gate: higher STAB, lower HP budget going in, or Rival before extra wild drafts.

---

### M4 → M5 (soft chart → hard chart, same economy + Rival)

| KPI | M4 (1000) | M5 (3000) | Δ | vs plan target |
|-----|-----------|-----------|---|----------------|
| overall_win_rate | 57.7% | **23.3%** | **−34.4pp** | **In 25–40% band** ✓ |
| charmander | 32.2% | **5.6%** | −26.6pp | Below 15% floor |
| squirtle | 70.3% | 34.3% | −36.0pp | |
| bulbasaur | 71.7% | 31.0% | −40.7pp | Starters compressed |
| stage1_rival_win_rate | 99.7% | **92.8%** | −6.9pp | Rival is a real gate |
| loss_at onix | 84 | 785 | +701 | Charmander Pewter wall returns |
| brock_reach_rate | 95.4% | 85.9% | −9.5pp | |
| brock_win_when_reached | 70.5% | 53.3% | −17.2pp | Fair gym when reached |

**Inference:** Hard chart + M4 economy lands **overall difficulty on target** but **over-corrects Fire** and compresses all starters to ~30% WR. Likely need **split chart** (soft at Pewter only) or Pewter-specific resist tuning—not a full revert to 1.5/0.75 everywhere.

---

### M5 → M6 (hand 4 + VW/WG parity)

| KPI | M5 | M6 | Δ |
|-----|----|----|---|
| overall_win_rate | 23.3% | **40.6%** | **+17.3pp** | Top of 25–40% band |
| charmander | 5.6% | **13.5%** | +7.9pp | Still below 15% floor |
| squirtle | 34.3% | **54.9%** | +20.6pp | |
| bulbasaur | 31.0% | **54.9%** | +23.9pp | Squirt/Bulb now tied |
| loss_at onix | 785 | 650 | −135 | Still #1 for Fire |
| loss_at brock | 614 | 627 | +13 | Co-primary gate |
| avg_hp_before_brock | 15.6 | 17.9 | +2.3 | |

**Inference:** Hand 4 dominates the combined package (~+17pp overall). M6 is a credible **“hard chart + forgiving UX”** config; next knob is **Fire-only** (Pewter chart slice, Onix HP, or Charmander deck), not more global ease.

---

### M1 Charmander (est.) → M3 (soft, 500 runs)

| KPI | ~6.7% (300, hard) | M3 40.6% | Δ |
|-----|-------------------|----------|---|
| charmander win_rate | ~7% | 40.6% | **~+33pp** |
| loss_at brock | ~41 | 190 | Brock becomes main loss |
| brock_win_when_reached | — | 51.7% | Fair gym fight |

---

## Meta analysis

### 1. Separate problems, separate levers

| Problem | Symptom | Lever that worked | Lever that did not |
|---------|---------|-------------------|---------------------|
| No pre-Pewter runway | M0 Charmander 0%; early Geodude losses | 3-stage arc + drafts | Type chart alone (M1) |
| Fire vs Rock in combat math | M1 Charmander 5%; Onix 212 losses | **1.5 / 0.75 chart** | More stages without chart |
| Run too easy overall | M2 69% WR | — yet | Reverting chart |
| No attrition before Pewter | ~92% HP entering Pewter | — yet | Center 30g/+3 HP + greedy shop |

### 2. Type multipliers interact with systems scale

Classic **2× / 0.5×** implies a **4×** damage ratio on the same card power. With **30 HP**, **3 stamina**, and **block**, resist behaves like a boss modifier for a whole stage. **1.5 / 0.75** (2× ratio) matches deckbuilder pacing better and is **documented as PoC default**.

### 3. Loss-location metric is a good design health check

| Milestone | Healthy? | Loss concentration |
|-----------|----------|-------------------|
| M0 | No | Geodude (too early), Onix |
| M1 | Partial | Onix (wrong for arc fantasy) |
| M2 | Yes | Brock > Geodude > Onix; early bosses rare |

Use **loss_at_enemy** in every tuning pass: if Onix or Rival spikes, the wrong layer was tuned.

### 4. Aggregate win rate is misleading

M2 **69%** average hides **45% vs 83%** starter spread. Always report:

- `overall_win_rate`
- Per-starter WR
- Charmander-only batch when evaluating Fire

### 5. Economy is a difficulty knob, not just flavor

Center (full heal + permanent max HP) + greedy shop policy keeps Pewter entry near full HP. **Tuning Center cost or +HP bonus** should move `hp_entering_pewter_pct` and overall WR without touching combat types. Item prep (Antidote/Awakening) adds further safety.

### 6. Sim methodology

| Practice | Why |
|----------|-----|
| **Fixed seed (42)** for A/B on same config | Reproducible comparison |
| **Multiple seeds** before declaring “balanced” | Variance from wild RNG + BF/Beedrill |
| **Separate `runs/v2/<label>/` per config** | Avoid mixed analyze (e.g. 1020 in `runs/v2/`) |
| **`--shop-policy`** sensitivity | Greedy ≠ human; compare minimal / never_center |
| **Charmander-only runs** | Detect Fire-specific fixes without Water/Grass masking |

### 7. Open tuning queue (M4+)

Priority order with soft chart **frozen**:

1. **Brock** — HP or pattern damage ↑ → target overall 25–40%, Brock WR when reached ~50–60%.
2. **Center** — 35g and/or +2 max HP → lower `hp_entering_pewter_pct`.
3. **Stage 1 wild damage** — optional; Rival WR 100% suggests trivial attrition.
4. **Shop AI** — tighten Center threshold (greedy buys at HP &lt; 65% today).

---

## Appendix: file map

| Concern | Primary files |
|---------|----------------|
| Type chart | `data/balance/type_chart.json` |
| Stages / evolution | `data/balance/run_config.json` |
| Draft pools | `data/balance/stage_rewards.json` |
| Items / Center | `data/balance/items.json` |
| Enemies / bosses | `data/balance/enemies.json` |
| Sim | `python -m pokemon_crawlers.sim` |
| Analyze | `python -m pokemon_crawlers.analyze` |

---

*Last updated: 2026-05-25 — M0–M3 recorded; M4 pending Pewter/Center pass.*
