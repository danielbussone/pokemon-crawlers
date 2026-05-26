"""Tests for bulk simulation."""

from __future__ import annotations

from pathlib import Path

from pokemon_crawlers.sim import run_batch

BALANCE_DIR = Path(__file__).resolve().parents[1] / "data" / "balance"


def test_sim_batch_writes_logs(tmp_path: Path) -> None:
    summary = run_batch(
        BALANCE_DIR,
        count=3,
        runs_dir=tmp_path,
        seed=42,
        starter="squirtle",
        quiet=True,
    )
    assert summary["count"] == 3
    assert len(list(tmp_path.glob("run_*.json"))) == 3
