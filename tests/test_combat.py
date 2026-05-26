"""Tests for combat.py turn loop."""

from __future__ import annotations

from pathlib import Path

import pytest

from pokemon_crawlers.combat import (
    CombatOutcome,
    can_play_card,
    check_outcome,
    create_enemy_state,
    end_player_turn,
    enemy_turn,
    play_card,
    player_turn_begin,
    run_combat,
    start_combat,
)
from pokemon_crawlers.deck import build_player_deck, draw_to_hand
from pokemon_crawlers.effects import apply_status, has_status
from pokemon_crawlers.loader import load_balance
from pokemon_crawlers.models import CardType, PlayerState, PokemonType, StatusType

BALANCE_DIR = Path(__file__).resolve().parents[1] / "data" / "balance"


@pytest.fixture
def balance():
    return load_balance(BALANCE_DIR)


@pytest.fixture
def squirtle_player(balance):
    return PlayerState(
        hp=30,
        max_hp=30,
        pokemon_type=PokemonType.WATER,
        base_max_stamina=3,
        max_stamina=3,
        current_stamina=3,
        deck=build_player_deck("squirtle", balance),
    )


def test_player_turn_draws_hand(squirtle_player, balance):
    ctx = start_combat(squirtle_player, "geodude", balance)
    player_turn_begin(ctx)
    assert len(ctx.player.hand) == balance.constants.hand_size


def test_paralyze_blocks_attack_cards(squirtle_player, balance):
    ctx = start_combat(squirtle_player, "geodude", balance)
    ctx.player.hand = ["tackle", "harden", "tail_whip"]
    apply_status(ctx.player, StatusType.PARALYZE, duration=2)

    attack_index = 0
    result = can_play_card(ctx, attack_index)
    assert result.success is False
    assert "Paralyzed" in result.reason


def test_sleep_skips_draw(squirtle_player, balance):
    ctx = start_combat(squirtle_player, "geodude", balance)
    apply_status(ctx.player, StatusType.SLEEP, duration=1)
    player_turn_begin(ctx)
    assert ctx.player.hand == []


def test_play_card_deals_damage(squirtle_player, balance):
    ctx = start_combat(squirtle_player, "geodude", balance)
    player_turn_begin(ctx)

    attack_index = next(
        index
        for index, card_id in enumerate(ctx.player.hand)
        if balance.cards[card_id].card_type == CardType.ATTACK
    )
    result = play_card(ctx, attack_index)
    assert result.success
    assert ctx.enemy.hp < 18


def test_poison_can_kill_enemy_before_enemy_turn(squirtle_player, balance):
    ctx = start_combat(squirtle_player, "geodude", balance)
    ctx.enemy.hp = 3
    apply_status(ctx.enemy, StatusType.POISON, duration=2, magnitude=3)

    end_player_turn(ctx)
    outcome = enemy_turn(ctx).outcome
    assert outcome == CombatOutcome.PLAYER_WIN


def test_confuse_self_damage_on_play(squirtle_player, balance):
    ctx = start_combat(squirtle_player, "geodude", balance)
    player_turn_begin(ctx)
    apply_status(ctx.player, StatusType.CONFUSE, duration=2)

    index = 0
    before = ctx.player.hp
    play_card(ctx, index)
    assert ctx.player.hp == before - 3


def test_brock_boss_combat_has_intent(squirtle_player, balance):
    ctx = start_combat(squirtle_player, "brock", balance)
    assert ctx.next_enemy_action_name == "Rock Throw"


def test_run_combat_squirtle_beats_geodude(squirtle_player, balance):
    result = run_combat(squirtle_player, "geodude", balance, max_turns=50)
    assert result.outcome == CombatOutcome.PLAYER_WIN


def test_block_resets_each_turn(squirtle_player, balance):
    ctx = start_combat(squirtle_player, "geodude", balance)
    ctx.player.block = 5
    player_turn_begin(ctx)
    assert ctx.player.block == 0
