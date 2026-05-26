"""Smoke tests for Pewter run orchestration."""

from __future__ import annotations

from pathlib import Path

import pytest

from pokemon_crawlers.loader import load_balance
from pokemon_crawlers.logger import save_run_log
from pokemon_crawlers.registry import reset_cache, set_balance
from pokemon_crawlers.run_flow import run_kanto_chain, run_pewter_chain

BALANCE_DIR = Path(__file__).resolve().parents[1] / "data" / "balance"


@pytest.fixture
def balance():
    reset_cache()
    bal = load_balance(BALANCE_DIR)
    set_balance(bal, balance_dir=BALANCE_DIR)
    return bal


def test_auto_run_smoke(balance, tmp_path):
    run_log, outcome = run_kanto_chain(
        balance,
        interactive=False,
        starter_id="squirtle",
        runs_dir=tmp_path,
        use_heuristic_ai=True,
        quiet=True,
        shop_policy="minimal",
    )
    assert outcome in {"run_complete", "run_loss"}
    assert len(run_log.encounters) >= 1
    path = save_run_log(run_log, tmp_path)
    assert path.is_file()


def test_pewter_only_smoke(balance, tmp_path):
    run_log, outcome = run_pewter_chain(
        balance,
        interactive=False,
        starter_id="squirtle",
        runs_dir=tmp_path,
        use_heuristic_ai=True,
        quiet=True,
    )
    assert outcome in {"run_complete", "run_loss"}
    assert run_log.run_mode == "pewter"
