"""Tests for effects.py damage pipeline and conditions."""

from __future__ import annotations

from pathlib import Path

import pytest

from pokemon_crawlers.effects import (
    apply_blinded_attack_check,
    apply_condition,
    apply_damage,
    apply_status,
    decrement_statuses,
    get_type_modifier,
    has_condition,
    resolve_card_effects,
    tick_poison,
)
from pokemon_crawlers.loader import load_balance
from pokemon_crawlers.models import (
    ConditionId,
    EnemyState,
    PlayerState,
    PokemonType,
    StatusType,
)

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
        base_max_stamina=3,
        max_stamina=3,
        current_stamina=3,
    )


@pytest.fixture
def geodude(balance):
    enemy_def = balance.enemies["geodude"]
    return EnemyState(
        hp=enemy_def.max_hp,
        max_hp=enemy_def.max_hp,
        pokemon_type=enemy_def.pokemon_type,
        enemy_id="geodude",
    )


def test_type_modifier_water_vs_rock(balance):
    mod = get_type_modifier(PokemonType.WATER, PokemonType.ROCK, balance.type_chart)
    assert mod == 2.0


def test_type_modifier_fire_vs_rock(balance):
    mod = get_type_modifier(PokemonType.FIRE, PokemonType.ROCK, balance.type_chart)
    assert mod == 0.5


def test_damage_super_effective(player, geodude, balance):
    result = apply_damage(
        8,
        PokemonType.WATER,
        geodude,
        attacker=player,
        balance=balance,
        badges=balance.badges,
    )
    assert result.hp_damage == 16
    assert geodude.hp == 2


def test_damage_not_very_effective(player, geodude, balance):
    result = apply_damage(
        1,
        PokemonType.FIRE,
        geodude,
        attacker=player,
        balance=balance,
        badges=balance.badges,
    )
    assert result.hp_damage == 0
    assert geodude.hp == 18


def test_block_absorbs_damage(player, geodude, balance):
    geodude.block = 10
    result = apply_damage(
        8,
        PokemonType.NORMAL,
        geodude,
        attacker=player,
        balance=balance,
        badges=balance.badges,
    )
    assert result.blocked is True
    assert result.hp_damage == 0
    assert geodude.hp == 18


def test_blinded_budget_miss_hit_sequence(geodude):
    geodude.blinded_budget = 4
    assert apply_blinded_attack_check(geodude) is True
    assert geodude.blinded_budget == 3
    assert apply_blinded_attack_check(geodude) is False
    assert geodude.blinded_budget == 2
    assert apply_blinded_attack_check(geodude) is True
    assert geodude.blinded_budget == 1
    assert apply_blinded_attack_check(geodude) is False
    assert geodude.blinded_budget is None


def test_blinded_damage_miss_on_even_budget(player, geodude, balance):
    player.blinded_budget = 4
    result = apply_damage(
        10,
        PokemonType.WATER,
        geodude,
        attacker=player,
        balance=balance,
        badges=balance.badges,
        is_attack=True,
    )
    assert result.missed_blinded is True
    assert result.hp_damage == 0


def test_intimidated_reduces_outgoing_damage(player, geodude, balance):
    apply_condition(player, ConditionId.INTIMIDATED, balance)
    result = apply_damage(
        10,
        PokemonType.NORMAL,
        geodude,
        attacker=player,
        balance=balance,
        badges=balance.badges,
    )
    assert result.hp_damage == 3


def test_distracted_increases_damage_taken(player, geodude, balance):
    apply_condition(geodude, ConditionId.DISTRACTED, balance)
    result = apply_damage(
        8,
        PokemonType.NORMAL,
        geodude,
        attacker=player,
        balance=balance,
        badges=balance.badges,
    )
    assert result.hp_damage == 5


def test_poison_tick_ignores_block(player):
    player.block = 10
    apply_status(player, StatusType.POISON, duration=3, magnitude=3)
    dealt = tick_poison(player)
    assert dealt == 3
    assert player.hp == 27


def test_status_stacking_extends_duration(player):
    apply_status(player, StatusType.POISON, duration=2, magnitude=2)
    apply_status(player, StatusType.POISON, duration=3, magnitude=3)
    assert len(player.statuses) == 1
    assert player.statuses[0].turns_remaining == 5
    assert player.statuses[0].magnitude == 3


def test_vine_whip_card_against_geodude(player, geodude, balance):
    card = balance.cards["vine_whip"]
    results = resolve_card_effects(
        card.effects,
        card.card_type,
        card.pokemon_type,
        player=player,
        enemy=geodude,
        balance=balance,
        badges=balance.badges,
    )
    assert results[0].hp_damage == 20
    assert geodude.hp == 0
    assert has_condition(geodude, ConditionId.DISTRACTED) is False


def test_growl_applies_intimidated(player, geodude, balance):
    card = balance.cards["growl"]
    resolve_card_effects(
        card.effects,
        card.card_type,
        card.pokemon_type,
        player=player,
        enemy=geodude,
        balance=balance,
        badges=balance.badges,
    )
    assert has_condition(geodude, ConditionId.INTIMIDATED)


def test_decrement_statuses_removes_expired(player):
    apply_status(player, StatusType.SLEEP, duration=1, magnitude=0)
    decrement_statuses(player)
    assert player.statuses == []
