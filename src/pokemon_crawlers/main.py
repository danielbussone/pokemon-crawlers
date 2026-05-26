"""Entry point — Kanto opening arc or legacy Pewter-only run."""

from __future__ import annotations

import argparse
from pathlib import Path

from pokemon_crawlers import __version__
from pokemon_crawlers.loader import BalanceLoadError, load_balance
from pokemon_crawlers.registry import set_balance
from pokemon_crawlers.run_flow import run_kanto_chain, run_pewter_chain


def _default_balance_dir() -> Path:
    return Path(__file__).resolve().parents[2] / "data" / "balance"


def _default_runs_dir() -> Path:
    return Path(__file__).resolve().parents[2] / "runs"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="pokemon-crawlers",
        description="Pokémon Crawlers combat PoC — Kanto opening arc",
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
    parser.add_argument(
        "--runs-dir",
        type=Path,
        default=None,
        help="Directory for run JSON logs (default: runs/)",
    )
    parser.add_argument(
        "--auto",
        action="store_true",
        help="Non-interactive auto-play (for smoke tests / bulk sim)",
    )
    parser.add_argument(
        "--starter",
        choices=["bulbasaur", "squirtle", "charmander"],
        default=None,
        help="Skip starter prompt (requires --auto or used alone)",
    )
    parser.add_argument(
        "--no-log",
        action="store_true",
        help="Do not write run JSON to runs/",
    )
    parser.add_argument(
        "--pewter-only",
        action="store_true",
        help="Legacy Pewter-only 5-encounter chain (regression mode)",
    )
    parser.add_argument(
        "--shop-policy",
        choices=["greedy", "minimal", "random", "never_center", "potions", "items_only"],
        default="greedy",
        help="Shop AI policy for auto runs (default: greedy)",
    )
    parser.add_argument(
        "--play-style",
        choices=["balanced", "aggressive", "conservative"],
        default="balanced",
        help="Combat/draft AI for auto runs (default: balanced)",
    )
    parser.add_argument(
        "--sim",
        type=int,
        metavar="N",
        default=None,
        help="Run N autoplay simulations (heuristic AI) and exit",
    )
    parser.add_argument(
        "--sim-seed",
        type=int,
        default=None,
        help="RNG seed when using --sim",
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

    set_balance(balance)

    if args.sim is not None:
        from pokemon_crawlers.sim import print_summary, run_batch

        if args.sim < 1:
            print("--sim must be at least 1")
            return 1
        summary = run_batch(
            balance_dir,
            count=args.sim,
            runs_dir=args.runs_dir or _default_runs_dir(),
            seed=args.sim_seed,
            starter=args.starter or "all",
            quiet=True,
            pewter_only=args.pewter_only,
            shop_policy=args.shop_policy,
            play_style=args.play_style,
        )
        print_summary(summary)
        return 0

    runs_dir = None if args.no_log else (args.runs_dir or _default_runs_dir())

    print(f"Pokémon Crawlers PoC v{__version__}")
    if args.pewter_only:
        print("Pewter City only — legacy regression mode\n")
    else:
        print("Kanto arc — Route/Viridian → Forest → Pewter\n")

    interactive = not args.auto
    starter_id = args.starter
    if args.auto and starter_id is None:
        starter_id = "squirtle"

    use_heuristic = args.auto
    shop_policy = None if interactive else args.shop_policy

    run_fn = run_pewter_chain if args.pewter_only else run_kanto_chain

    try:
        _run_log, outcome = run_fn(
            balance,
            interactive=interactive,
            starter_id=starter_id,
            runs_dir=runs_dir,
            use_heuristic_ai=use_heuristic,
            shop_policy=shop_policy,
            play_style=args.play_style if use_heuristic else "balanced",
        )
    except KeyboardInterrupt:
        print("\nRun interrupted.")
        return 130

    if outcome == "run_complete":
        print("\n=== Run complete! ===")
        return 0
    print("\n=== Run ended in defeat. ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
