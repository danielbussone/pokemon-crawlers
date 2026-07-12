# Pokémon Crawlers — Gym Content Plan (Phase 5c)

Design outline for the full 9-level Kanto arc. **Plan only — not yet implemented.**
Gyms 1–2 (Brock, Misty) are already built; the rest are sketched here for review.

Last updated: 2026-07-11

---

## How a "level" maps to the engine

The run is a flat list of **segments** (`run_config.json`). Each segment =
*optional wilds (placed on the map grid) + one mandatory leader gate*. A leader
grants its badge/signature/rare-candy and the run continues; only the `is_final`
leader ends it.

A **level** (the journey to one gym) is **3 consecutive segments by default**
(tunable per level): two *approach* areas (route / cave / building), each with a
wild pool and a mandatory **trainer mid-boss**, then the **gym** segment.

```
Level = approach segment × 2 (default) + gym segment
approach segment = { wild_pool, trainer mid-boss (leader_kind: rival|trainer), map }
gym segment      = { wild_pool, gym leader (leader_kind: gym), badge, signature, is_final? }
```

Level 1 (done) is 3 segments: `route_viridian`(rival) → `viridian_forest`(bug
catcher) → `pewter`(Brock). **Decision (locked): default 3 per level, adjustable
as we balance.** A full run is then ~27 mandatory gates + wilds — long, but it's
the whole game; HP attrition is the main tuning lever.

### Gym-boss modeling: single-phase for now

The engine fights **one enemy** per gate (an `action_pool` + `boss_pattern`), not a
switchable team. **Decision (locked): all leaders are single-phase ace-bosses for
now** — one boss themed on the leader's strongest mon, moveset borrowing a
signature move from the team and carrying the gym mechanic (how Brock/Misty
already work). The canonical team is listed for flavor / move sourcing. The
**multi-phase** mechanic (Giovanni, E4) is **deferred**; those bosses ship
single-phase first and can be upgraded later.

---

## Global conventions

| Aspect | Convention |
|--------|------------|
| Wild pool | 3–5 Gen-1 species per region; **all Gen-1 have BW sprites** already |
| Trainer mid-boss | a themed trainer (or the rival at story beats); `is_wild:false`, modest boss |
| Gym leader | `is_boss:true`, hp/xp scale with gym number; carries the gym mechanic |
| Badge | one per gym; **typed passives** (locked) — schema extended beyond `outgoing_damage_mult` in 5b (see per-gym) |
| Signature card | leader-drop; reuse existing cards where possible, else new (flagged) |
| Draft pool | one `stageN` reward pool per segment, from existing cards |
| Difficulty | leader HP ≈ 45 + 8·(gym#−1); wild HP/dmg drift up slowly; validate via simcheck |
| Trainer art | species use BW scrape; **leaders need a `<name>.png`** flat file (else procedural) |

---

## Combat mechanics needed (Phase 5b) per gym

Effect vocabulary that exists today: `damage` (+`ignore_block`), `block`, `heal`,
`status` (poison/sleep/paralyze/confuse/burn as DoT+heal combos), `apply_condition`
(defenseless/distracted/intimidated/slow/blinded), `draw`.

| Gym | Mechanic | New vocab? | Sketch |
|-----|----------|-----------|--------|
| Brock | Block cycling | ✅ have | alternating `block` self + hits |
| Misty | Heal + ignore-block | ✅ have | `heal` self + `damage ignore_block` |
| Surge | Paralyze + **stamina drain** | **new** | paralyze (have) + `stamina_delta` on player next turn |
| Erika | **Multi-status per action** | mostly have | one action applies 2 statuses (poison+sleep) |
| Koga | **Stacking poison + evasion** | **new** | poison that stacks magnitude + player-miss `evasion` condition |
| Sabrina | **Hand shuffle** | **new** | discard + redraw the player's hand (disrupt) |
| Blaine | **Arena lava tick** | **new** | per-turn arena DoT to both / to player |
| Giovanni | ~~Multi-phase~~ → **single-phase ace for now** | — | Rhydon ace; heavy `ignore_block` ground hits. Multi-phase deferred |
| E4 | **Boss rush, no shops** | **new** | 5 back-to-back bosses in one segment; **no Center/Mart** — heal only from pre-bought inventory |

`5b` builds the **new** mechanic rows + the **typed badge-passive schema** (locked).
Multi-phase is out of 5b scope (deferred).

### Typed badge passives (locked)

Schema extended beyond `outgoing_damage_mult`. Each badge grants a distinct, run-long
buff. (Boulder/Cascade currently ship as `outgoing_damage_mult 1.1`; **Boulder is being
re-typed to defensive** below. 5b adds an `incoming_damage_mult` badge field, applied when
the player is the defender in `apply_damage`.)

| Badge | Gym | Passive (proposed) | Field sketch |
|-------|-----|--------------------|--------------|
| Boulder | Brock | **−10% incoming damage** (defensive) | `incoming_damage_mult: 0.9` |
| Cascade | Misty | +10% outgoing damage | `outgoing_damage_mult: 1.1` |
| Thunder | Surge | +1 max stamina | `max_stamina_bonus: 1` |
| Rainbow | Erika | heal a little each fight | `heal_on_combat_start: 3` |
| Soul | Koga | immune to poison | `status_immunity: ["poison"]` |
| Marsh | Sabrina | +1 hand size (draw) | `hand_size_bonus: 1` |
| Volcano | Blaine | +15% damage vs burning/full-HP | `outgoing_damage_mult: 1.15` |
| Earth | Giovanni | +5 max HP | `max_hp_bonus: 5` |

5b adds these fields to `badges.json` + applies them (stamina/HP/hand at run or
combat start; immunity in `apply_status`; heal in `prepare_between_encounters`).

---

## The 9 levels

Legend: **Ace** = boss we model; team in parentheses is flavor / move source.
Signature/card marked *(new)* needs authoring; otherwise it exists.

### Level 1 — Pewter (Brock) · Rock · **DONE**
- **Segments:** Route 1 (rival) → Viridian Forest (bug catcher) → Pewter (Brock).
- **Wilds:** pidgey, rattata, weedle, nidoran_m; caterpie, metapod, kakuna; geodude, zubat, onix.
- **Trainers:** rival (counter-type), bug_catcher (butterfree/beedrill).
- **Gym:** Brock (Geodude, **Onix**). Mechanic: block cycling. Signature: `rock_slide`. Badge: Boulder.

### Level 2 — Cerulean (Misty) · Water · **DONE**
- **Segments:** Cerulean (Misty). *(approach folded in; could add Mt. Moon later)*
- **Wilds:** psyduck, poliwag, goldeen, shellder.
- **Trainers:** — (none yet; add a Mt. Moon Rocket grunt if we expand).
- **Gym:** Misty (Staryu, **Starmie**). Mechanic: heal + ignore-block. Signature: `water_pulse`. Badge: Cascade.

### Level 3 — Vermilion (Lt. Surge) · Electric
- **Segments:** Route 5–6 / SS Anne (rival OR Rocket grunt) → Vermilion (Surge).
- **Wilds:** spearow, meowth, mankey, diglett, magnemite.
- **Trainers:** sailor / gentleman; rival cameo on SS Anne.
- **Gym:** Surge (Voltorb, Pikachu, **Raichu**). Mechanic: **paralyze + stamina drain**
  (Thunder Wave = paralyze; "Static" = −1 player stamina next turn; Thunderbolt = dmg).
  Signature: `thunderbolt` *(new electric card)*. Badge: Thunder.

### Level 4 — Celadon (Erika) · Grass
- **Segments:** Route 7–8 (gambler / Rocket) → Celadon (Erika).
- **Wilds:** oddish, bellsprout, meowth, growlithe, abra.
- **Trainers:** gambler / cooltrainer; optional Rocket-hideout grunt.
- **Gym:** Erika (Tangela, Weepinbell, **Vileplume**). Mechanic: **multi-status per
  action** (Stun Spore + Poison Powder in one move; Mega Drain = dmg+heal).
  Signature: `giga_drain` *(exists)*. Badge: Rainbow.

### Level 5 — Fuchsia (Koga) · Poison
- **Segments:** Cycling Road / Route 12–15 (biker) → Fuchsia (Koga).
- **Wilds:** grimer, koffing, gloom, venonat, doduo.
- **Trainers:** biker / cue-ball; juggler near Fuchsia.
- **Gym:** Koga (Koffing, Muk, **Weezing**). Mechanic: **stacking poison + evasion**
  (Toxic stacks poison magnitude; Minimize = evasion/player-miss; Sludge = dmg).
  Signature: `sludge_bomb` *(new poison card)*. Badge: Soul.

### Level 6 — Saffron (Sabrina) · Psychic
- **Segments:** Silph Co. (Rocket grunt → Giovanni-lite mini-boss) → Saffron (Sabrina).
- **Wilds:** abra, drowzee, gastly, meowth *(city — mostly trainers)*.
- **Trainers:** Rocket grunts, scientist, rival at Silph.
- **Gym:** Sabrina (Kadabra, Mr. Mime, Venomoth, **Alakazam**). Mechanic: **hand shuffle**
  (discards + redraws player's hand; Psychic = big dmg; Confusion = confuse).
  Signature: `psybeam` *(new psychic card)*. Badge: Marsh.

### Level 7 — Cinnabar (Blaine) · Fire
- **Segments:** Sea Routes 19–21 (swimmer) → Pokémon Mansion (burglar) → Cinnabar (Blaine).
- **Wilds:** tentacool, horsea, staryu, krabby (sea); growlithe, ponyta, koffing (mansion).
- **Trainers:** swimmer; burglar in the mansion.
- **Gym:** Blaine (Growlithe, Ponyta, Rapidash, **Arcanine**). Mechanic: **arena lava tick**
  (per-turn burn to the player; Fire Blast = dmg; Flame Wheel = dmg+burn).
  Signature: `flamethrower` *(exists)*. Badge: Volcano.

### Level 8 — Viridian (Giovanni) · Ground
- **Segments:** back to Viridian (Rocket admin) → Viridian Gym (Giovanni).
- **Wilds:** spearow, rattata, ekans, sandshrew, mankey.
- **Trainers:** Rocket grunts / admin.
- **Gym:** Giovanni — **single-phase ace** for now (**Rhydon**; team Rhyhorn/Dugtrio/
  Nidoqueen/Nidoking for move sourcing). Heavy `ignore_block` ground hits (Earthquake,
  Dig, Bone Club). *Multi-phase upgrade deferred.* Signature: `earthquake` *(new
  ground card)*. Badge: Earth (+5 max HP).

### Level 9 — Victory Road + Elite Four · Boss rush
- **Segments:** Victory Road (wild-heavy, cooltrainer) → Indigo Plateau (E4 rush) → Champion.
- **Wilds:** machop, geodude, graveler, onix, golbat, marowak (Victory Road).
- **Trainers:** cooltrainer / black belt on Victory Road.
- **Bosses (rush, is_final = Champion):** Lorelei (Ice/Water) → Bruno (Fighting/Rock) →
  Agatha (Ghost/Poison) → Lance (Dragon) → **Champion** (rival's team), all single-phase.
  Mechanic: **5-boss rush, no shops** — **no Center/Mart in the E4 level at all**; the only
  healing is the inventory the player stocked up on *before* entering. HP carries across all
  five fights; no draft between. Reward: run win. Badge: — (Champion = victory).
- **Engine note:** model the rush as 5 back-to-back gym-less boss segments with `shop_window: 0`
  and no shop tiles on the maps; the last (Champion) is `is_final`.

---

## Signature cards to author (new)

`thunderbolt` (Electric), `sludge_bomb` (Poison), `psybeam` (Psychic),
`earthquake` (Ground) — all expressible in existing effect vocab (damage +
status/ignore_block). Grass/Fire/Water/Rock signatures already exist.

## New enemies to author (with existing BW sprites)

~6–10 wild species per new region (spearow, meowth, mankey, diglett, magnemite,
oddish, bellsprout, grimer, koffing, gloom, venonat, doduo, drowzee, gastly,
tentacool, horsea, krabby, ponyta, ekans, sandshrew, machop, graveler, golbat,
marowak…) + 7 leaders + trainer mid-bosses + E4 (5 bosses). Leaders/trainers
need flat `<id>.png` art or fall back to procedural.

---

## Decisions (locked)

1. **Run length:** **3 segments per level** default (2 approach + gym), tunable as we
   balance. ~27 mandatory gates for a full run.
2. **Boss modeling:** **single-phase ace-bosses** everywhere for now, incl. Giovanni &
   E4. Multi-phase deferred to a later pass.
3. **Badge passives:** **typed** — each badge a distinct run-long buff (table above);
   5b extends the schema (incl. an `incoming_damage_mult` field; Boulder → −10% incoming).
4. **Rocket / rival cameos:** **yes, as mid-boss trainers where it fits** (Mt. Moon,
   SS Anne, Rocket Hideout, Silph Co., Viridian).
5. **E4 shape:** **5-boss rush, no Center/Mart** in the E4 level — healing limited to
   pre-bought inventory; HP carries across all five.
6. **Build order:** **outline everything first (this doc), then build one gym at a time
   in canon order** (Level 3 Vermilion/Surge next).
```
