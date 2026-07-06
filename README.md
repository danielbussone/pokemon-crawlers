# Pokémon Crawlers — Combat PoC

Pre-Godot validation harness for **Pokémon Crawlers**. A stdlib-only Python CLI that runs the Kanto opening arc (Route/Viridian → Viridian Forest → Pewter Gym) with mid-boss trainers, gold economy, and in-combat items. Logs runs to JSON for balance tuning via data files.

Long-term target: Godot 4 roguelite deckbuilder. This repo proves combat feel before any engine work.

## PoC status

**Frozen baseline** (May 2026) — validated for Kanto opening through Brock. See [POC_FINDINGS.md](POC_FINDINGS.md#poc-baseline-frozen).

| | |
|--|--|
| Type chart | 2.0× / 0.5× |
| Hand | 4 cards |
| Premium attacks | Body Slam / Hyper Fang at **cost 3** |
| Charmander | Weak pre-Brock by design; accepted for PoC |

**Next step:** [docs/GODOT_HANDOFF.md](docs/GODOT_HANDOFF.md) — implementation phases, data contract, combat turn order.

**Godot 3D port (first pass):** [godot/](godot/) — same balance data and 13-fight Kanto arc,
walked in a 3D explorable world with procedurally generated (code-only) assets. See
[godot/README.md](godot/README.md).

## Prerequisites

- Python 3.11+

## Setup

```bash
cd pokemon-crawlers
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -e ".[dev]"
```

## Run

Interactive Kanto arc run:

```bash
python -m pokemon_crawlers
# or
pokemon-crawlers

# Legacy Pewter-only regression (5 encounters)
python -m pokemon_crawlers --pewter-only --auto --starter squirtle
```

Auto-play smoke test (heuristic AI, logs optional):

```bash
python -m pokemon_crawlers --auto --starter squirtle --no-log
```

Bulk simulation for balance data (writes one JSON log per run under `runs/`):

```bash
python -m pokemon_crawlers.sim --runs 50 --seed 42
# or
python -m pokemon_crawlers --sim 50 --sim-seed 42
```

The sim AI favors block/heal when low on HP and deprioritizes Growl when the enemy still has substantial HP — useful for aggregate win rates, not a perfect human player.

Analyze saved runs:

```bash
python -m pokemon_crawlers.analyze runs/
python -m pokemon_crawlers.analyze runs/ --json
```

Balance tuning log (change deltas, KPI snapshots, meta analysis): [docs/POC_BALANCE_TUNING.md](docs/POC_BALANCE_TUNING.md)

Options:

```bash
python -m pokemon_crawlers --balance-dir path/to/balance
python -m pokemon_crawlers --starter charmander   # skip starter prompt
python -m pokemon_crawlers --runs-dir ./my-runs   # JSON logs (default: runs/)
```

During combat: **hand index** to play a card, **`i`** plus slot number, item id, or name to use an item (once per turn), **`e`** to end turn, **`q`** to quit.

Shop windows open after mid-boss victories (Pokémon Center + Poké Mart).

## Project layout

```
pokemon-crawlers/
├── data/balance/          # Tunable game data (JSON) — source of truth for numbers
├── src/pokemon_crawlers/  # Combat engine + CLI (no hardcoded balance values)
├── runs/                  # Gitignored playtest logs (run_*.json)
├── tests/
└── POC_FINDINGS.md        # Playtest conclusions (filled after 20+ runs)
```

## Regression sim (baseline)

```bash
python -m pokemon_crawlers.sim --runs 3000 --seed 42 --starter all \
  --shop-policy greedy --play-style balanced \
  --runs-dir runs/v2/regression-baseline/
python -m pokemon_crawlers.analyze runs/v2/regression-baseline/ --json
```

Sim logs live under `runs/` (gitignored). Compare future balance changes against ~33% overall win rate on greedy shop.

## Balance tuning

Edit JSON under `data/balance/` (HP, damage, costs, condition magnitudes, encounter order). No Python changes required for numeric tweaks.

## Docs

- [POC_FINDINGS.md](POC_FINDINGS.md) — frozen baseline and playtest conclusions
- [docs/POC_BALANCE_TUNING.md](docs/POC_BALANCE_TUNING.md) — sim milestones and KPI tables
- [docs/GODOT_HANDOFF.md](docs/GODOT_HANDOFF.md) — Godot 4 port checklist and data contract

## License

Personal project — not for distribution.
