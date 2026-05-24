"""Entry point — run orchestration (implemented in later milestones)."""

from __future__ import annotations

import argparse
from pathlib import Path

from pokemon_crawlers import __version__
from pokemon_crawlers.loader import BalanceLoadError, load_balance


def _default_balance_dir() -> Path:
    return Path(__file__).resolve().parents[2] / "data" / "balance"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="pokemon-crawlers",
        description="Pokémon Crawlers Pewter City combat PoC",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {__version__}",
    )
    parser.add_argument(
        "--balance-dir",
        type=Path,
        default=None,
        help="Path to balance JSON directory (default: data/balance/)",
    )
    args = parser.parse_args(argv)

    balance_dir = args.balance_dir or _default_balance_dir()
    if not balance_dir.is_dir():
        print(f"Balance data not found: {balance_dir}")
        return 1

    try:
        balance = load_balance(balance_dir)
    except BalanceLoadError as exc:
        print(f"Failed to load balance data: {exc}")
        return 1

    print(f"Pokémon Crawlers PoC v{__version__}")
    print(f"Balance dir: {balance_dir}")
    print(
        f"Loaded: {len(balance.cards)} cards, "
        f"{len(balance.enemies)} enemies, "
        f"{len(balance.starters)} starters, "
        f"{len(balance.conditions)} conditions"
    )
    print("Combat harness not implemented yet — see upcoming milestones.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
