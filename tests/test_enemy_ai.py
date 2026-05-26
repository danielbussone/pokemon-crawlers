"""Tests for enemy_ai.py."""

from __future__ import annotations

from pathlib import Path

import pytest

from pokemon_crawlers.enemy_ai import (
    advance_boss_pattern_index,
    choose_wild_action,
    get_boss_action,
    get_next_boss_intent,
)
from pokemon_crawlers.loader import load_balance
from pokemon_crawlers.models import EnemyState, PlayerState, PokemonType

BALANCE_DIR = Path(__file__).resolve().parents[1] / "data" / "balance"


@pytest.fixture
def balance():
    return load_balance(BALANCE_DIR)


def test_brock_pattern_loops_from_index_2(balance):
    brock = balance.enemies["brock"]
    assert advance_boss_pattern_index(brock, 0) == 1
    assert advance_boss_pattern_index(brock, 4) == 2
    assert get_boss_action(brock, 2).id == "rock_slide"


def test_get_next_boss_intent_matches_current_index(balance):
    brock = balance.enemies["brock"]
    intent = get_next_boss_intent(brock, 0)
    assert intent.name == "Rock Throw"


def test_choose_wild_action_returns_pool_member(balance):
    geodude = balance.enemies["geodude"]
    enemy = EnemyState(hp=18, max_hp=18, pokemon_type=geodude.pokemon_type, enemy_id="geodude")
    player = PlayerState(hp=30, max_hp=30, pokemon_type=PokemonType.WATER)
    pool_ids = {action.id for action in geodude.action_pool}
    for _ in range(20):
        action = choose_wild_action(geodude, enemy, player, balance)
        assert action.id in pool_ids
