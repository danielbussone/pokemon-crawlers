"""Tests for player_ai.py."""

from __future__ import annotations

from pathlib import Path

import pytest

from pokemon_crawlers.loader import load_balance
from pokemon_crawlers.models import PlayerState, PokemonType
from pokemon_crawlers.player_ai import (
    choose_draft_pick,
    execute_shop_policy,
)

BALANCE_DIR = Path(__file__).resolve().parents[1] / "data" / "balance"


@pytest.fixture
def balance():
    return load_balance(BALANCE_DIR)


def test_draft_prefers_defense_when_low_hp(balance):
    player = PlayerState(hp=8, max_hp=30, pokemon_type=PokemonType.GRASS)
    pick = choose_draft_pick(player, ["body_slam", "harden", "growl"], balance)
    assert pick == "harden"


def test_draft_prefers_damage_when_healthy(balance):
    player = PlayerState(hp=28, max_hp=30, pokemon_type=PokemonType.GRASS)
    pick = choose_draft_pick(player, ["growl", "body_slam", "harden"], balance)
    assert pick == "body_slam"


def test_draft_aggressive_prefers_body_slam(balance):
    player = PlayerState(hp=28, max_hp=30, pokemon_type=PokemonType.GRASS)
    pick = choose_draft_pick(
        player,
        ["harden", "recover", "body_slam"],
        balance,
        play_style="aggressive",
    )
    assert pick == "body_slam"


def test_draft_conservative_prefers_harden_when_hurt(balance):
    player = PlayerState(hp=12, max_hp=30, pokemon_type=PokemonType.GRASS)
    pick = choose_draft_pick(
        player,
        ["body_slam", "harden", "bite"],
        balance,
        play_style="conservative",
    )
    assert pick == "harden"


def test_potions_shop_skips_status_items(balance):
    player = PlayerState(
        hp=20,
        max_hp=30,
        pokemon_type=PokemonType.WATER,
        gold=50,
        inventory=[],
    )
    execute_shop_policy(
        player,
        balance,
        shop_window=2,
        next_stage_id="pewter",
        policy="potions",
    )
    assert all(item_id in {"potion", "super_potion"} for item_id in player.inventory)
    assert "antidote" not in player.inventory
