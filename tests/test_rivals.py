"""Counter-type Rival selection."""

from __future__ import annotations

from pathlib import Path

from pokemon_crawlers.loader import load_balance

BALANCE_DIR = Path(__file__).resolve().parents[1] / "data" / "balance"
from pokemon_crawlers.rivals import (
    COUNTER_RIVAL_BY_STARTER,
    RIVAL_SENTINEL,
    is_rival_enemy,
    resolve_rival_enemy_id,
)
from pokemon_crawlers.run_flow import _resolve_mid_boss_id
import random


def test_counter_rival_mapping():
    assert resolve_rival_enemy_id("charmander") == "rival_squirtle"
    assert resolve_rival_enemy_id("squirtle") == "rival_bulbasaur"
    assert resolve_rival_enemy_id("bulbasaur") == "rival_charmander"


def test_is_rival_enemy():
    assert is_rival_enemy("rival_blue")
    assert is_rival_enemy("rival_squirtle")
    assert not is_rival_enemy("pidgey")


def test_resolve_mid_boss_rival_sentinel():
    balance = load_balance(BALANCE_DIR)
    stage = next(s for s in balance.run_config.stages if s.id == "route_viridian")
    assert stage.mid_boss == RIVAL_SENTINEL
    rng = random.Random(0)
    for starter, rival in COUNTER_RIVAL_BY_STARTER.items():
        enemy_id = _resolve_mid_boss_id(stage, rng, starter)
        assert enemy_id == rival
        assert enemy_id in balance.enemies


def test_rival_enemies_have_typed_attacks():
    balance = load_balance(BALANCE_DIR)
    for rival_id in ("rival_squirtle", "rival_bulbasaur", "rival_charmander"):
        enemy = balance.enemies[rival_id]
        assert enemy.pokemon_type.value in {"WATER", "GRASS", "FIRE"}
        assert enemy.max_hp == 28
