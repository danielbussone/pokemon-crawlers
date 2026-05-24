# Pokémon Crawlers — Combat PoC

Pre-Godot validation harness for **Pokémon Crawlers**. A stdlib-only Python CLI that runs the Pewter City encounter loop (starter → wild fights → Brock), logs runs to JSON, and supports balance tuning via data files.

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

```bash
python -m pokemon_crawlers
# or
pokemon-crawlers
```

Optional balance override (when implemented):

```bash
python -m pokemon_crawlers --balance-dir path/to/balance
```

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
