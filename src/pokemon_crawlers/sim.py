"""Bulk autoplay runs for balance data collection."""

from __future__ import annotations

import argparse
import random
import sys
from collections import Counter
from pathlib import Path

from pokemon_crawlers.loader import BalanceLoadError, load_balance
from pokemon_crawlers.logger import save_run_log
from pokemon_crawlers.registry import set_balance
from pokemon_crawlers.run_flow import run_kanto_chain, run_pewter_chain

STARTERS = ("bulbasaur", "squirtle", "charmander")
SHOP_POLICIES = ("greedy", "minimal", "random", "never_center", "potions", "items_only")
PLAY_STYLES = ("balanced", "aggressive", "conservative")


def _default_balance_dir() -> Path:
    return Path(__file__).resolve().parents[2] / "data" / "balance"


def _default_runs_dir() -> Path:
    return Path(__file__).resolve().parents[2] / "runs" / "v2"


def run_batch(
    balance_dir: Path,
    *,
    count: int,
    runs_dir: Path,
    seed: int | None = None,
    starter: str = "all",
    quiet: bool = True,
    pewter_only: bool = False,
    shop_policy: str = "greedy",
    play_style: str = "balanced",
) -> dict[str, object]:
    balance = load_balance(balance_dir)
    set_balance(balance, balance_dir=balance_dir)

    rng = random.Random(seed)
    if starter == "all":
        starter_cycle = list(STARTERS)
    else:
        starter_cycle = [starter]

    run_fn = run_pewter_chain if pewter_only else run_kanto_chain

    outcomes: Counter[str] = Counter()
    loss_at: Counter[str] = Counter()
    wins = 0

    for run_index in range(count):
        chosen = (
            starter_cycle[run_index % len(starter_cycle)]
            if starter != "all"
            else rng.choice(STARTERS)
        )
        run_rng = random.Random(rng.randint(0, 2**31 - 1))
        run_log, outcome = run_fn(
            balance,
            interactive=False,
            starter_id=chosen,
            runs_dir=None,
            use_heuristic_ai=True,
            quiet=quiet,
            run_id_suffix=f"_{run_index:04d}",
            shop_policy=shop_policy,
            play_style=play_style,
            rng=run_rng,
        )
        outcomes[outcome] += 1
        if outcome == "run_complete":
            wins += 1
        elif outcome == "run_loss" and run_log.encounters:
            last = run_log.encounters[-1]
            if last.outcome == "player_loss":
                loss_at[last.enemy_id] += 1

        save_run_log(run_log, runs_dir)

    win_rate = wins / count if count else 0.0
    return {
        "count": count,
        "wins": wins,
        "win_rate": win_rate,
        "outcomes": dict(outcomes),
        "loss_at_enemy": dict(loss_at),
        "seed": seed,
        "starter_filter": starter,
        "pewter_only": pewter_only,
        "shop_policy": shop_policy,
        "play_style": play_style,
    }


def print_summary(summary: dict[str, object]) -> None:
    count = int(summary["count"])
    wins = int(summary["wins"])
    win_rate = float(summary["win_rate"])
    print(f"\n=== Simulation ({count} runs) ===")
    print(f"Wins: {wins} ({win_rate * 100:.1f}%)")
    print("Outcomes:", summary["outcomes"])
    loss_at = summary.get("loss_at_enemy") or {}
    if loss_at:
        print("Losses by enemy:", loss_at)
    seed = summary.get("seed")
    if seed is not None:
        print(f"Seed: {seed}")
    if summary.get("pewter_only"):
        print("Mode: pewter-only")
    if summary.get("shop_policy"):
        print(f"Shop policy: {summary['shop_policy']}")
    if summary.get("play_style"):
        print(f"Play style: {summary['play_style']}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="pokemon-crawlers-sim",
        description="Run many Kanto chains with heuristic AI and save JSON logs",
    )
    parser.add_argument(
        "-n",
        "--runs",
        type=int,
        default=20,
        help="Number of runs (default: 20)",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        help="RNG seed for starter rotation / draft variance",
    )
    parser.add_argument(
        "--starter",
        choices=[*STARTERS, "all"],
        default="all",
        help="Starter to use, or 'all' to rotate / randomize (default: all)",
    )
    parser.add_argument(
        "--balance-dir",
        type=Path,
        default=None,
    )
    parser.add_argument(
        "--runs-dir",
        type=Path,
        default=None,
        help="Where to write run_*.json logs (default: runs/v2/)",
    )
    parser.add_argument(
        "--pewter-only",
        action="store_true",
        help="Legacy Pewter-only chain",
    )
    parser.add_argument(
        "--shop-policy",
        choices=list(SHOP_POLICIES),
        default="greedy",
        help="Shop AI: greedy (default), potions (healing only), minimal, random, never_center",
    )
    parser.add_argument(
        "--play-style",
        choices=list(PLAY_STYLES),
        default="balanced",
        help="Combat/draft AI: balanced (default), aggressive, conservative",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Print per-encounter progress",
    )
    args = parser.parse_args(argv)

    if args.runs < 1:
        print("--runs must be at least 1", file=sys.stderr)
        return 1

    balance_dir = args.balance_dir or _default_balance_dir()
    if not balance_dir.is_dir():
        print(f"Balance data not found: {balance_dir}", file=sys.stderr)
        return 1

    try:
        summary = run_batch(
            balance_dir,
            count=args.runs,
            runs_dir=args.runs_dir or _default_runs_dir(),
            seed=args.seed,
            starter=args.starter,
            quiet=not args.verbose,
            pewter_only=args.pewter_only,
            shop_policy=args.shop_policy,
            play_style=args.play_style,
        )
    except BalanceLoadError as exc:
        print(f"Failed to load balance: {exc}", file=sys.stderr)
        return 1

    print_summary(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
