"""Tests for item and shop systems."""

from __future__ import annotations

from pathlib import Path

import pytest

from pokemon_crawlers.loader import load_balance
from pokemon_crawlers.items import add_item_to_inventory, apply_item_effect, use_item_in_combat
from pokemon_crawlers.models import PlayerState, PokemonType, StatusType
from pokemon_crawlers.models import ActiveStatus
from pokemon_crawlers.shop import purchase_center, purchase_item
from pokemon_crawlers.registry import reset_cache, set_balance

BALANCE_DIR = Path(__file__).resolve().parents[1] / "data" / "balance"


@pytest.fixture
def balance():
    reset_cache()
    bal = load_balance(BALANCE_DIR)
    set_balance(bal)
    return bal


def _player(balance) -> PlayerState:
    return PlayerState(
        hp=20,
        max_hp=30,
        pokemon_type=PokemonType.FIRE,
        gold=100,
    )


def test_potion_heal(balance):
    player = _player(balance)
    item = balance.items["potion"]
    result = apply_item_effect(player, item)
    assert result.success
    assert player.hp == 30


def test_antidote_cures_poison(balance):
    player = _player(balance)
    player.statuses.append(
        ActiveStatus(type=StatusType.POISON, turns_remaining=3, magnitude=3)
    )
    add_item_to_inventory(player, "antidote", balance)
    result = use_item_in_combat(player, "antidote", balance, items_used_this_turn=0)
    assert result.success
    assert not any(s.type == StatusType.POISON for s in player.statuses)


def test_center_increases_max_hp(balance):
    player = _player(balance)
    result = purchase_center(player, balance)
    assert result.center_visits == 1
    assert player.max_hp == 33
    assert player.hp == 33


def test_inventory_limit(balance):
    player = _player(balance)
    assert add_item_to_inventory(player, "potion", balance)
    assert add_item_to_inventory(player, "potion", balance)
    assert not add_item_to_inventory(player, "potion", balance)
    assert add_item_to_inventory(player, "antidote", balance)
    assert len(player.inventory) == 3
    assert not add_item_to_inventory(player, "full_heal", balance)


def test_parlyz_heal_shop_window_2_only(balance):
    item = balance.items["parlyz_heal"]
    assert 2 in item.shop_windows
    assert 1 not in item.shop_windows
