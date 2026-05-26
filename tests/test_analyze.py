"""Tests for analyze.py."""

from __future__ import annotations

import json
from pathlib import Path

from pokemon_crawlers.analyze import analyze_logs, load_run_logs


def test_analyze_sample_logs(tmp_path: Path) -> None:
    run_a = {
        "starter_id": "squirtle",
        "outcome": "run_complete",
        "encounters": [
            {"enemy_id": "geodude", "outcome": "player_win", "player_hp_after": 28},
            {"enemy_id": "brock", "outcome": "player_win", "player_hp_before": 10},
        ],
        "draft_picks": ["harden"],
        "evolution_applied": True,
    }
    run_b = {
        "starter_id": "bulbasaur",
        "outcome": "run_loss",
        "encounters": [
            {"enemy_id": "onix", "outcome": "player_loss", "player_hp_before": 12},
        ],
        "draft_picks": [],
        "evolution_applied": False,
    }
    for index, run in enumerate((run_a, run_b)):
        (tmp_path / f"run_test_{index}.json").write_text(json.dumps(run), encoding="utf-8")

    logs = load_run_logs(tmp_path)
    metrics = analyze_logs(logs)
    assert metrics["total_runs"] == 2
    assert metrics["win_rate_pct"] == 50.0
    assert metrics["loss_at_enemy"] == {"onix": 1}
