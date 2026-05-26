"""Aggregate metrics from run JSON logs."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from statistics import mean, median


def load_run_logs(runs_dir: Path) -> list[dict]:
    logs: list[dict] = []
    for path in sorted(runs_dir.glob("run_*.json")):
        try:
            with path.open(encoding="utf-8") as handle:
                logs.append(json.load(handle))
        except (json.JSONDecodeError, OSError) as exc:
            print(f"Skipping {path.name}: {exc}", file=sys.stderr)
    return logs


def _loss_enemy(run: dict) -> str | None:
    if run.get("outcome") != "run_loss":
        return None
    encounters = run.get("encounters") or []
    if not encounters:
        return None
    last = encounters[-1]
    if last.get("outcome") == "player_loss":
        return last.get("enemy_id")
    return None


def _hp_before_brock(run: dict) -> int | None:
    for enc in run.get("encounters") or []:
        if enc.get("enemy_id") == "brock":
            return enc.get("player_hp_before")
    return None


def _hp_before_stage(run: dict, stage_id: str) -> int | None:
    for enc in run.get("encounters") or []:
        if enc.get("stage_id") == stage_id:
            return enc.get("player_hp_before")
    return None


def _rival_win(run: dict) -> bool | None:
    from pokemon_crawlers.rivals import is_rival_enemy

    for enc in run.get("encounters") or []:
        enemy_id = enc.get("enemy_id", "")
        if is_rival_enemy(enemy_id):
            return enc.get("outcome") == "player_win"
    return None


def _mid_boss_win(run: dict, enemy_id: str) -> bool | None:
    for enc in run.get("encounters") or []:
        if enc.get("enemy_id") == enemy_id:
            return enc.get("outcome") == "player_win"
    return None


def _encounters_cleared(run: dict) -> int:
    return sum(1 for enc in run.get("encounters") or [] if enc.get("outcome") == "player_win")


def analyze_logs(logs: list[dict]) -> dict[str, object]:
    if not logs:
        return {"total_runs": 0}

    outcomes = Counter(run.get("outcome", "unknown") for run in logs)
    starters = Counter(run.get("starter_id", "unknown") for run in logs)
    wins_by_starter: Counter[str] = Counter()
    runs_by_starter: Counter[str] = Counter()
    loss_at = Counter()
    draft_picks = Counter()
    cleared_counts = Counter()
    hp_after_onix: list[int] = []
    hp_before_brock: list[int] = []
    brock_reached = 0
    brock_wins = 0
    gold_earned: list[int] = []
    center_visits: list[int] = []
    max_hp_final: Counter[int] = Counter()
    rival_wins = 0
    rival_fights = 0
    butterfree_wins = 0
    butterfree_fights = 0
    beedrill_wins = 0
    beedrill_fights = 0
    hp_entering_pewter: list[float] = []
    antidote_buys = 0
    items_purchased = Counter()
    shop_strategies = Counter()

    for run in logs:
        starter = run.get("starter_id", "unknown")
        runs_by_starter[starter] += 1
        if run.get("outcome") == "run_complete":
            wins_by_starter[starter] += 1

        enemy = _loss_enemy(run)
        if enemy:
            loss_at[enemy] += 1

        for pick in run.get("draft_picks") or []:
            draft_picks[pick] += 1

        cleared = _encounters_cleared(run)
        cleared_counts[cleared] += 1

        gold_earned.append(int(run.get("gold_earned", 0)))
        center_visits.append(int(run.get("center_visits", 0)))
        max_hp = int(run.get("max_hp_final") or run.get("final_hp") or 0)
        if max_hp:
            max_hp_final[max_hp] += 1

        if run.get("shop_strategy"):
            shop_strategies[run["shop_strategy"]] += 1

        for item_id in run.get("items_purchased") or []:
            items_purchased[item_id] += 1
            if item_id == "antidote":
                antidote_buys += 1

        rival_result = _rival_win(run)
        if rival_result is not None:
            rival_fights += 1
            if rival_result:
                rival_wins += 1

        variant = run.get("mid_boss_variant")
        if variant == "bug_catcher_butterfree":
            butterfree_fights += 1
            if _mid_boss_win(run, variant):
                butterfree_wins += 1
        elif variant == "bug_catcher_beedrill":
            beedrill_fights += 1
            if _mid_boss_win(run, variant):
                beedrill_wins += 1

        hp_pewter = _hp_before_stage(run, "pewter")
        max_hp_run = int(run.get("max_hp_final") or 30)
        if hp_pewter is not None and max_hp_run:
            hp_entering_pewter.append(hp_pewter / max_hp_run * 100)

        for enc in run.get("encounters") or []:
            if enc.get("enemy_id") == "onix" and enc.get("outcome") == "player_win":
                hp_after_onix.append(enc.get("player_hp_after", 0))
            if enc.get("enemy_id") == "brock":
                brock_reached += 1
                if enc.get("outcome") == "player_win":
                    brock_wins += 1
                hp = _hp_before_brock(run)
                if hp is not None:
                    hp_before_brock.append(hp)

    total = len(logs)
    wins = outcomes.get("run_complete", 0)

    win_rate_by_starter = {
        starter: round(wins_by_starter[starter] / runs_by_starter[starter] * 100, 1)
        for starter in sorted(runs_by_starter)
        if runs_by_starter[starter]
    }

    return {
        "total_runs": total,
        "wins": wins,
        "win_rate_pct": round(wins / total * 100, 1) if total else 0,
        "outcomes": dict(outcomes),
        "starters": dict(starters),
        "win_rate_by_starter_pct": win_rate_by_starter,
        "loss_at_enemy": dict(loss_at.most_common()),
        "draft_picks_top": dict(draft_picks.most_common(12)),
        "encounters_cleared_distribution": dict(sorted(cleared_counts.items())),
        "avg_hp_after_onix_win": round(mean(hp_after_onix), 1) if hp_after_onix else None,
        "median_hp_after_onix_win": median(hp_after_onix) if hp_after_onix else None,
        "avg_hp_before_brock": round(mean(hp_before_brock), 1) if hp_before_brock else None,
        "median_hp_before_brock": median(hp_before_brock) if hp_before_brock else None,
        "brock_reached": brock_reached,
        "brock_win_rate_pct": round(brock_wins / brock_reached * 100, 1) if brock_reached else None,
        "evolution_applied_pct": round(
            sum(1 for r in logs if r.get("evolution_applied")) / total * 100, 1
        ),
        "avg_gold_per_run": round(mean(gold_earned), 1) if gold_earned else None,
        "avg_center_visits": round(mean(center_visits), 2) if center_visits else None,
        "max_hp_final_distribution": dict(sorted(max_hp_final.items())),
        "brock_reach_rate_pct": round(
            sum(1 for r in logs if any(
                e.get("stage_id") == "pewter" for e in (r.get("encounters") or [])
            ))
            / total
            * 100,
            1,
        )
        if total
        else None,
        "stage1_rival_win_rate_pct": round(rival_wins / rival_fights * 100, 1)
        if rival_fights
        else None,
        "stage2_butterfree_win_rate_pct": round(
            butterfree_wins / butterfree_fights * 100, 1
        )
        if butterfree_fights
        else None,
        "stage2_beedrill_win_rate_pct": round(beedrill_wins / beedrill_fights * 100, 1)
        if beedrill_fights
        else None,
        "avg_hp_entering_pewter_pct": round(mean(hp_entering_pewter), 1)
        if hp_entering_pewter
        else None,
        "antidote_purchase_rate_pct": round(antidote_buys / total * 100, 1) if total else None,
        "items_purchased_top": dict(items_purchased.most_common(8)),
        "shop_strategy_counts": dict(shop_strategies),
    }


def format_report(metrics: dict[str, object]) -> str:
    if not metrics.get("total_runs"):
        return "No run logs found."

    lines = [
        f"Runs analyzed: {metrics['total_runs']}",
        f"Overall win rate: {metrics['wins']}/{metrics['total_runs']} ({metrics['win_rate_pct']}%)",
        f"Outcomes: {metrics['outcomes']}",
        "",
        "Win rate by starter:",
    ]
    for starter, rate in (metrics.get("win_rate_by_starter_pct") or {}).items():
        lines.append(f"  {starter}: {rate}%")

    lines.extend(
        [
            "",
            f"Losses by enemy: {metrics.get('loss_at_enemy')}",
            f"Encounters cleared (distribution): {metrics.get('encounters_cleared_distribution')}",
            "",
            "HP checkpoints (winning runs only where noted):",
            f"  After Onix (avg / median): {metrics.get('avg_hp_after_onix_win')} / {metrics.get('median_hp_after_onix_win')}",
            f"  Before Brock (avg / median): {metrics.get('avg_hp_before_brock')} / {metrics.get('median_hp_before_brock')}",
            f"  Brock reached: {metrics.get('brock_reached')} — win rate when reached: {metrics.get('brock_win_rate_pct')}%",
            f"  Evolution applied: {metrics.get('evolution_applied_pct')}% of runs",
            "",
            "Top draft picks:",
        ]
    )
    for card_id, count in (metrics.get("draft_picks_top") or {}).items():
        lines.append(f"  {card_id}: {count}")

    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Analyze Pokémon Crawlers run JSON logs")
    parser.add_argument(
        "runs_dir",
        type=Path,
        nargs="?",
        default=None,
        help="Directory containing run_*.json (default: runs/)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print raw metrics as JSON",
    )
    args = parser.parse_args(argv)

    runs_dir = args.runs_dir or Path(__file__).resolve().parents[2] / "runs"
    if not runs_dir.is_dir():
        print(f"Runs directory not found: {runs_dir}", file=sys.stderr)
        return 1

    logs = load_run_logs(runs_dir)
    metrics = analyze_logs(logs)

    if args.json:
        print(json.dumps(metrics, indent=2))
    else:
        print(format_report(metrics))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
