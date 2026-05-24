"""Tests for balance JSON loading and validation."""

from __future__ import annotations

from pathlib import Path

import pytest

from pokemon_crawlers.loader import BalanceLoadError, load_balance
from pokemon_crawlers.models import ConditionId, PokemonType
from pokemon_crawlers.registry import get_balance, get_card, reset_cache

BALANCE_DIR = Path(__file__).resolve().parents[1] / "data" / "balance"


@pytest.fixture(autouse=True)
def _clear_registry_cache() -> None:
    reset_cache()
    yield
    reset_cache()


def test_load_default_balance() -> None:
    balance = load_balance(BALANCE_DIR)
    assert balance.constants.player_max_hp == 30
    assert len(balance.cards) >= 20
    assert len(balance.enemies) == 4
    assert len(balance.starters) == 3
    assert ConditionId.BLINDED in balance.conditions


def test_type_chart_water_vs_rock() -> None:
    balance = load_balance(BALANCE_DIR)
    key = (PokemonType.WATER, PokemonType.ROCK)
    assert balance.type_chart[key] == 2.0


def test_starter_decks_reference_valid_cards() -> None:
    balance = load_balance(BALANCE_DIR)
    squirtle = balance.starters["squirtle"]
    assert squirtle.deck.count("tail_whip") == 2
    for card_id in squirtle.deck:
        assert card_id in balance.cards


def test_quick_attack_zero_cost() -> None:
    card = get_card("quick_attack", BALANCE_DIR)
    assert card.cost == 0
    assert card.evolves_to == "hyper_fang"


def test_brock_has_screech_in_pattern() -> None:
    balance = load_balance(BALANCE_DIR)
    brock = balance.enemies["brock"]
    assert "screech" in brock.boss_pattern
    assert brock.boss_pattern_loop_start == 2


def test_run_config_encounter_sequence() -> None:
    balance = load_balance(BALANCE_DIR)
    assert balance.run_config.encounter_sequence[-1] == "brock"
    assert "sand_attack" in balance.run_config.reward_pool
    assert "string_shot" in balance.run_config.reward_pool


def test_registry_caches_balance() -> None:
    first = get_balance(BALANCE_DIR)
    second = get_balance(BALANCE_DIR)
    assert first is second


def test_missing_balance_file_raises(tmp_path: Path) -> None:
    with pytest.raises(BalanceLoadError, match="Missing balance file"):
        load_balance(tmp_path)


def test_invalid_starter_reference_raises(tmp_path: Path) -> None:
    import json
    import shutil

    shutil.copytree(BALANCE_DIR, tmp_path / "balance")
    starters_path = tmp_path / "balance" / "starters.json"
    starters = json.loads(starters_path.read_text())
    starters["bulbasaur"]["deck"].append("not_a_real_card")
    starters_path.write_text(json.dumps(starters))

    with pytest.raises(BalanceLoadError, match="unknown card"):
        load_balance(tmp_path / "balance")
