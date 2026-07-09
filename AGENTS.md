# AGENTS.md

## Cursor Cloud specific instructions

This is a stdlib-only Python CLI (Pokémon Crawlers combat PoC). Requires Python 3.11+ (VM has 3.12). The only third-party dependency is `pytest` (dev extra). Standard setup/run/test commands live in `README.md`.

- Dependencies install into a local `.venv` created by the startup update script. Activate it before working: `source .venv/bin/activate` (or invoke binaries directly as `.venv/bin/python` / `.venv/bin/pytest`).
- Run tests: `python -m pytest` (config in `pyproject.toml`; 73 tests, ~0.3s).
- Run the app (interactive): `python -m pokemon_crawlers`. For non-interactive verification use auto-play: `python -m pokemon_crawlers --auto --starter squirtle --no-log`.
- Bulk sim / analysis: `python -m pokemon_crawlers.sim --runs N --seed S` and `python -m pokemon_crawlers.analyze runs/`.
- No linter is configured for this repo.
- Sim/run JSON logs are written under `runs/` which is gitignored (only `runs/.gitkeep` is tracked); safe to generate freely.
