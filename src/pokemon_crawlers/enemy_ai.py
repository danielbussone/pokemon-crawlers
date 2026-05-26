"""Enemy action selection — phase-weighted wild AI and boss patterns."""

from __future__ import annotations

import random
from typing import TYPE_CHECKING

from pokemon_crawlers.effects import get_type_modifier
from pokemon_crawlers.models import EffectType, EnemyAction, EnemyDefinition, EnemyState, PlayerState

if TYPE_CHECKING:
    from pokemon_crawlers.models import GameBalance, PokemonType


def _hp_phase(hp: int, max_hp: int) -> str:
    if max_hp <= 0:
        return "desperate"
    pct = hp / max_hp
    if pct > 0.7:
        return "healthy"
    if pct > 0.3:
        return "mid"
    return "desperate"


def _action_pool_by_id(enemy_def: EnemyDefinition) -> dict[str, EnemyAction]:
    return {action.id: action for action in enemy_def.action_pool}


def uses_fixed_pattern(enemy_def: EnemyDefinition) -> bool:
    return bool(enemy_def.boss_pattern)


def _max_attack_damage(action: EnemyAction, enemy_type: PokemonType, player_type: PokemonType, balance: GameBalance) -> int:
    best = 0
    for effect in action.effects:
        if effect.type != EffectType.DAMAGE:
            continue
        amount = int(
            effect.magnitude
            * get_type_modifier(enemy_type, player_type, balance.type_chart)
        )
        best = max(best, amount)
    return best


def _action_weight(
    action: EnemyAction,
    phase: str,
    enemy_type: PokemonType,
    player_type: PokemonType,
    balance: GameBalance,
) -> int:
    weight = max(1, action.base_weight)
    preferred = (action.preferred_phase or "any").lower()

    if phase == "healthy" and preferred == "healthy":
        weight *= 3
    elif phase == "mid" and preferred in {"mid", "any"}:
        weight *= 2
    elif phase == "desperate":
        if action.is_attack:
            weight *= 2
        if preferred == "desperate":
            weight *= 2

    if action.is_attack:
        max_damage = _max_attack_damage(action, enemy_type, player_type, balance)
        if max_damage > 0:
            weight += max_damage

    return weight


def choose_wild_action(
    enemy_def: EnemyDefinition,
    enemy: EnemyState,
    player: PlayerState,
    balance: GameBalance,
) -> EnemyAction:
    phase = _hp_phase(enemy.hp, enemy.max_hp)
    pool = list(enemy_def.action_pool)
    weights = [
        _action_weight(action, phase, enemy.pokemon_type, player.pokemon_type, balance)
        for action in pool
    ]
    return random.choices(pool, weights=weights, k=1)[0]


def get_boss_action(enemy_def: EnemyDefinition, pattern_index: int) -> EnemyAction:
    pool = _action_pool_by_id(enemy_def)
    if not enemy_def.boss_pattern:
        raise ValueError(f"Boss '{enemy_def.id}' has no boss_pattern")
    index = pattern_index % len(enemy_def.boss_pattern)
    action_id = enemy_def.boss_pattern[index]
    if action_id not in pool:
        raise KeyError(f"Boss pattern references unknown action '{action_id}'")
    return pool[action_id]


def advance_boss_pattern_index(enemy_def: EnemyDefinition, current_index: int) -> int:
    next_index = current_index + 1
    if next_index >= len(enemy_def.boss_pattern):
        return enemy_def.boss_pattern_loop_start
    return next_index


def get_next_boss_intent(enemy_def: EnemyDefinition, pattern_index: int) -> EnemyAction:
    """Visible intent for boss — action at current pattern index."""
    return get_boss_action(enemy_def, pattern_index)
