"""Tests for deck.py draw/discard/shuffle/evolution."""

from __future__ import annotations

from pathlib import Path

import pytest

from pokemon_crawlers.deck import (
    apply_evolution,
    build_player_deck,
    discard_hand,
    draw_to_hand,
    play_card_from_hand,
    shuffle_discard_into_deck,
)
from pokemon_crawlers.loader import load_balance
from pokemon_crawlers.models import PlayerState, PokemonType

BALANCE_DIR = Path(__file__).resolve().parents[1] / "data" / "balance"


@pytest.fixture
def balance():
    return load_balance(BALANCE_DIR)


@pytest.fixture
def player(balance):
    return PlayerState(
        hp=30,
        max_hp=30,
        pokemon_type=PokemonType.WATER,
        deck=build_player_deck("squirtle", balance),
    )


def test_build_player_deck_has_five_cards(balance):
    deck = build_player_deck("bulbasaur", balance)
    assert len(deck) == 5
    assert deck.count("vine_whip") == 1
    assert deck.count("growl") == 2


def test_draw_to_hand_fills_hand(player, balance):
    drawn = draw_to_hand(player, balance)
    assert drawn == 3
    assert len(player.hand) == 3
    assert len(player.deck) == 2


def test_shuffle_discard_when_deck_empty(player, balance):
    player.deck = []
    player.discard = ["tackle", "tackle", "water_gun", "tail_whip", "tail_whip"]
    draw_to_hand(player, balance)
    assert len(player.hand) == 3
    assert len(player.deck) == 2
    assert player.discard == []


def test_discard_hand_moves_cards(player, balance):
    draw_to_hand(player, balance)
    hand_size = len(player.hand)
    discard_hand(player)
    assert player.hand == []
    assert len(player.discard) == hand_size


def test_play_card_from_hand(player, balance):
    draw_to_hand(player, balance)
    card_id = play_card_from_hand(player, 0)
    assert card_id in balance.cards
    assert len(player.hand) == 2
    assert player.discard[-1] == card_id


def test_apply_evolution_replaces_all_zones(player):
    player.deck = ["quick_attack", "tackle"]
    player.hand = ["quick_attack"]
    player.discard = ["quick_attack"]
    replaced = apply_evolution(player, "quick_attack", "hyper_fang")
    assert replaced is True
    assert player.deck == ["hyper_fang", "tackle"]
    assert player.hand == ["hyper_fang"]
    assert player.discard == ["hyper_fang"]


def test_apply_evolution_returns_false_when_missing(player):
    assert apply_evolution(player, "quick_attack", "hyper_fang") is False


def test_shuffle_discard_into_deck(player):
    player.deck = []
    player.discard = ["a", "b", "c"]
    shuffle_discard_into_deck(player)
    assert sorted(player.deck) == ["a", "b", "c"]
    assert player.discard == []
