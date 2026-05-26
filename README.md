# Pokémon Crawlers — Combat PoC

Pre-Godot validation harness for **Pokémon Crawlers**. A stdlib-only Python CLI that runs the Kanto opening arc (Route/Viridian → Viridian Forest → Pewter Gym) with mid-boss trainers, gold economy, and in-combat items. Logs runs to JSON for balance tuning via data files.

Long-term target: Godot 4 roguelite deckbuilder. This repo proves combat feel before any engine work.

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

During combat: **hand index** to play a card, **`i <item_id>`** to use an item (once per turn), **`e`** to end turn, **`q`** to quit.

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

## Playtest protocol

1. Run full Pewter chains across all three starters (Bulbasaur, Squirtle, Charmander).
2. Log at least 20 runs under `runs/`.
3. Analyze aggregate metrics: `python -m pokemon_crawlers.analyze runs/` (when implemented).
4. Record conclusions in [POC_FINDINGS.md](POC_FINDINGS.md).

## Balance tuning

Edit JSON under `data/balance/` (HP, damage, costs, condition magnitudes, encounter order). No Python changes required for numeric tweaks.

## Docs

- [POC_FINDINGS.md](POC_FINDINGS.md) — findings template / final report
- Plan: `.cursor/plans/pokemon_crawlers_poc_*.plan.md` (local)

## License

Personal project — not for distribution.
