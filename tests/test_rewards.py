"""Tests for rewards.py."""

from __future__ import annotations

import random
from pathlib import Path

import pytest

from pokemon_crawlers.deck import add_card_to_deck
from pokemon_crawlers.loader import load_balance
from pokemon_crawlers.models import PlayerState, PokemonType
from pokemon_crawlers.rewards import (
    apply_draft_pick,
    apply_evolution_catalyst,
    generate_draft_options,
    grant_boss_rewards,
    starter_stab_card_id,
)

BALANCE_DIR = Path(__file__).resolve().parents[1] / "data" / "balance"


@pytest.fixture
def balance():
    return load_balance(BALANCE_DIR)


@pytest.fixture
def player():
    return PlayerState(
        hp=30,
        max_hp=30,
        pokemon_type=PokemonType.WATER,
        deck=["quick_attack", "tackle"],
    )


def test_generate_draft_options_unique(balance):
    options = generate_draft_options(balance)
    assert len(options) == balance.constants.draft_options
    assert len(options) == len(set(options))
    for card_id in options:
        assert card_id in balance.run_config.reward_pool


def test_starter_stab_card_id():
    assert starter_stab_card_id("charmander") == "ember"
    assert starter_stab_card_id("squirtle") == "water_gun"
    assert starter_stab_card_id("bulbasaur") == "vine_whip"
    assert starter_stab_card_id("unknown") is None


def test_generate_draft_injects_starter_stab(balance):
    pool = ("quick_attack", "harden", "recover")
    rng = random.Random(0)
    seen_stab = False
    for _ in range(200):
        options = generate_draft_options(
            balance,
            reward_pool=pool,
            rng=rng,
            starter_id="charmander",
        )
        if "ember" in options:
            seen_stab = True
            break
    assert seen_stab


def test_generate_draft_stab_not_in_pool_still_valid(balance):
    pool = ("quick_attack", "harden", "recover")
    rng = random.Random(1)
    for _ in range(500):
        options = generate_draft_options(
            balance,
            reward_pool=pool,
            rng=rng,
            starter_id="squirtle",
        )
        for card_id in options:
            assert card_id in balance.cards


def test_apply_draft_pick(player):
    apply_draft_pick(player, "harden")
    assert "harden" in player.deck


def test_evolution_replaces_card(player, balance):
    apply_evolution_catalyst(player, balance)
    assert "quick_attack" not in player.deck
    assert "hyper_fang" in player.deck


def test_grant_boss_rewards(player, balance):
    grant_boss_rewards(player, balance)
    assert balance.run_config.badge_id in player.badge_ids
    assert balance.run_config.signature_card in player.deck
