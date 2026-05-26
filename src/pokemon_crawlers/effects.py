"""Damage, conditions, statuses, and effect resolution."""

from __future__ import annotations

from dataclasses import dataclass

from pokemon_crawlers.models import (
    ActiveCondition,
    ActiveStatus,
    BadgeDefinition,
    CardType,
    Combatant,
    ConditionDefinition,
    ConditionId,
    Effect,
    EffectTarget,
    EffectType,
    GameBalance,
    PlayerState,
    PokemonType,
    StatusType,
)


@dataclass(frozen=True)
class DamageResult:
    hp_damage: int
    blocked: bool
    missed_blinded: bool


def get_type_modifier(
    attacker_type: PokemonType,
    defender_type: PokemonType,
    type_chart: dict[tuple[PokemonType, PokemonType], float],
) -> float:
    return type_chart.get((attacker_type, defender_type), 1.0)


def has_condition(combatant: Combatant, condition_id: ConditionId) -> bool:
    return any(c.condition_id == condition_id for c in combatant.conditions)


def has_status(combatant: Combatant, status_type: StatusType) -> bool:
    return any(s.type == status_type for s in combatant.statuses)


def can_gain_block(combatant: Combatant) -> bool:
    return not has_condition(combatant, ConditionId.DEFENSELESS)


def apply_blinded_attack_check(attacker: Combatant) -> bool:
    """Return True if the attack misses due to Blinded. Always decrements budget."""
    if attacker.blinded_budget is None:
        return False

    missed = attacker.blinded_budget % 2 == 0
    attacker.blinded_budget -= 1
    if attacker.blinded_budget <= 0:
        attacker.blinded_budget = None
    return missed


def apply_damage(
    base_amount: int,
    attacker_type: PokemonType,
    defender: Combatant,
    *,
    attacker: Combatant,
    balance: GameBalance,
    badges: dict[str, BadgeDefinition],
    attacker_badge_ids: list[str] | None = None,
    is_attack: bool = True,
    ignore_block: bool = False,
) -> DamageResult:
    if is_attack and apply_blinded_attack_check(attacker):
        return DamageResult(hp_damage=0, blocked=False, missed_blinded=True)

    amount = int(
        base_amount * get_type_modifier(attacker_type, defender.pokemon_type, balance.type_chart)
    )
    amount = _apply_outgoing_modifiers(amount, attacker, balance.conditions)
    amount = _apply_incoming_modifiers(amount, defender, balance.conditions)
    amount = _apply_badge_damage_bonus(amount, attacker_badge_ids or [], badges)
    amount = max(0, amount)

    if amount == 0:
        return DamageResult(hp_damage=0, blocked=False, missed_blinded=False)

    if not ignore_block and defender.block >= amount:
        defender.block -= amount
        return DamageResult(hp_damage=0, blocked=True, missed_blinded=False)

    hp_damage = amount - defender.block
    defender.block = 0
    defender.hp = max(0, defender.hp - hp_damage)
    return DamageResult(hp_damage=hp_damage, blocked=False, missed_blinded=False)


def apply_heal(target: Combatant, amount: int) -> int:
    before = target.hp
    target.hp = min(target.max_hp, target.hp + amount)
    return target.hp - before


def apply_block(target: Combatant, amount: int) -> int:
    if amount <= 0 or not can_gain_block(target):
        return 0
    target.block += amount
    return amount


def apply_status(
    target: Combatant,
    status_type: StatusType,
    duration: int,
    magnitude: int = 0,
) -> None:
    for status in target.statuses:
        if status.type == status_type:
            status.turns_remaining += duration
            if magnitude > 0:
                status.magnitude = magnitude
            return
    target.statuses.append(
        ActiveStatus(type=status_type, turns_remaining=duration, magnitude=magnitude)
    )


def apply_condition(
    target: Combatant,
    condition_id: ConditionId,
    balance: GameBalance,
    duration: int | None = None,
    *,
    player: PlayerState | None = None,
    is_target_player: bool = False,
) -> None:
    definition = balance.conditions[condition_id]

    if condition_id == ConditionId.BLINDED:
        _apply_blinded(target, definition)
        return

    if condition_id == ConditionId.SLOW:
        _apply_slow(target, definition, duration, player=player, is_target_player=is_target_player)
        return

    turns = duration if duration is not None else (definition.default_duration or 1)
    for condition in target.conditions:
        if condition.condition_id == condition_id:
            condition.turns_remaining += turns
            return
    target.conditions.append(ActiveCondition(condition_id=condition_id, turns_remaining=turns))


def tick_poison(combatant: Combatant) -> int:
    total = 0
    for status in list(combatant.statuses):
        if status.type == StatusType.POISON and status.magnitude > 0:
            combatant.hp = max(0, combatant.hp - status.magnitude)
            total += status.magnitude
    return total


def decrement_statuses(combatant: Combatant) -> None:
    remaining: list[ActiveStatus] = []
    for status in combatant.statuses:
        status.turns_remaining -= 1
        if status.turns_remaining > 0:
            remaining.append(status)
    combatant.statuses = remaining


def decrement_conditions(combatant: Combatant) -> None:
    remaining: list[ActiveCondition] = []
    for condition in combatant.conditions:
        condition.turns_remaining -= 1
        if condition.turns_remaining > 0:
            remaining.append(condition)
    combatant.conditions = remaining


def resolve_effects(
    effects: tuple[Effect, ...],
    *,
    attacker: Combatant,
    defender: Combatant,
    attacker_type: PokemonType,
    balance: GameBalance,
    badges: dict[str, BadgeDefinition],
    player: PlayerState | None = None,
    is_player_attacker: bool = False,
) -> list[DamageResult]:
    results: list[DamageResult] = []
    badge_ids = player.badge_ids if player and is_player_attacker else []

    for effect in effects:
        target, _other = _resolve_targets(effect.target, attacker, defender)
        is_target_player = isinstance(target, PlayerState)

        if effect.type == EffectType.DAMAGE:
            results.append(
                apply_damage(
                    effect.magnitude,
                    attacker_type,
                    target,
                    attacker=attacker,
                    balance=balance,
                    badges=badges,
                    attacker_badge_ids=badge_ids,
                    is_attack=True,
                    ignore_block=effect.ignore_block,
                )
            )
        elif effect.type == EffectType.BLOCK:
            apply_block(target, effect.magnitude)
        elif effect.type == EffectType.HEAL:
            apply_heal(target, effect.magnitude)
        elif effect.type == EffectType.STATUS:
            if effect.status is None or effect.status_duration is None:
                continue
            apply_status(
                target,
                effect.status,
                effect.status_duration,
                effect.status_magnitude or 0,
            )
        elif effect.type == EffectType.APPLY_CONDITION:
            if effect.condition is None:
                continue
            apply_condition(
                target,
                effect.condition,
                balance,
                effect.condition_duration,
                player=player,
                is_target_player=is_target_player,
            )
        elif effect.type == EffectType.DRAW:
            if player is not None and is_player_attacker and effect.magnitude > 0:
                from pokemon_crawlers.deck import draw_cards

                draw_cards(player, effect.magnitude, balance.constants.hand_size)

    return results


def resolve_card_effects(
    card_effects: tuple[Effect, ...],
    card_type: CardType,
    card_pokemon_type: PokemonType,
    *,
    player: PlayerState,
    enemy: Combatant,
    balance: GameBalance,
    badges: dict[str, BadgeDefinition],
) -> list[DamageResult]:
    return resolve_effects(
        card_effects,
        attacker=player,
        defender=enemy,
        attacker_type=card_pokemon_type,
        balance=balance,
        badges=badges,
        player=player,
        is_player_attacker=True,
    )


def resolve_enemy_action_effects(
    effects: tuple[Effect, ...],
    is_attack: bool,
    enemy: Combatant,
    player: PlayerState,
    enemy_type: PokemonType,
    balance: GameBalance,
    badges: dict[str, BadgeDefinition],
) -> list[DamageResult]:
    if not is_attack:
        return resolve_effects(
            effects,
            attacker=enemy,
            defender=player,
            attacker_type=enemy_type,
            balance=balance,
            badges=badges,
            player=player,
            is_player_attacker=False,
        )

    results: list[DamageResult] = []
    for effect in effects:
        if effect.type == EffectType.DAMAGE:
            results.append(
                apply_damage(
                    effect.magnitude,
                    enemy_type,
                    player,
                    attacker=enemy,
                    balance=balance,
                    badges=badges,
                    is_attack=True,
                    ignore_block=effect.ignore_block,
                )
            )
        else:
            resolve_effects(
                (effect,),
                attacker=enemy,
                defender=player,
                attacker_type=enemy_type,
                balance=balance,
                badges=badges,
                player=player,
                is_player_attacker=False,
            )
    return results


def apply_confuse_self_damage(combatant: Combatant, amount: int) -> int:
    if not has_status(combatant, StatusType.CONFUSE):
        return 0
    combatant.hp = max(0, combatant.hp - amount)
    return amount


def apply_player_turn_start_modifiers(player: PlayerState, balance: GameBalance) -> None:
    """Reset stamina for the turn including Slow penalty and prior-turn Slow-on-enemy bonus."""
    base = player.base_max_stamina
    bonus = player.stamina_bonus_next_turn
    player.stamina_bonus_next_turn = 0

    slow_penalty = 0
    if has_condition(player, ConditionId.SLOW):
        slow_penalty = balance.conditions[ConditionId.SLOW].on_player_stamina_delta or 0

    player.max_stamina = max(0, base + bonus + slow_penalty)
    player.current_stamina = player.max_stamina


def _apply_blinded(target: Combatant, definition: ConditionDefinition) -> None:
    if target.blinded_budget is None:
        target.blinded_budget = definition.initial_budget or 4
        return
    add = definition.reapply_budget_add or 2
    cap = definition.reapply_budget_cap or 6
    target.blinded_budget = min(cap, target.blinded_budget + add)


def _apply_slow(
    target: Combatant,
    definition: ConditionDefinition,
    duration: int | None,
    *,
    player: PlayerState | None,
    is_target_player: bool,
) -> None:
    if is_target_player:
        turns = duration if duration is not None else 1
        for condition in target.conditions:
            if condition.condition_id == ConditionId.SLOW:
                condition.turns_remaining += turns
                return
        target.conditions.append(ActiveCondition(condition_id=ConditionId.SLOW, turns_remaining=turns))
        return

    if player is not None:
        grant = definition.on_enemy_grant_player_stamina_next_turn or 0
        player.stamina_bonus_next_turn += grant
        turns = duration if duration is not None else 1
        for condition in target.conditions:
            if condition.condition_id == ConditionId.SLOW:
                condition.turns_remaining += turns
                return
        target.conditions.append(ActiveCondition(condition_id=ConditionId.SLOW, turns_remaining=turns))


def _apply_outgoing_modifiers(
    amount: int,
    attacker: Combatant,
    conditions: dict[ConditionId, ConditionDefinition],
) -> int:
    if has_condition(attacker, ConditionId.INTIMIDATED):
        mult = conditions[ConditionId.INTIMIDATED].outgoing_damage_mult or 1.0
        amount = int(amount * mult)
    return amount


def _apply_incoming_modifiers(
    amount: int,
    defender: Combatant,
    conditions: dict[ConditionId, ConditionDefinition],
) -> int:
    for condition_id in (ConditionId.DISTRACTED, ConditionId.DEFENSELESS):
        if has_condition(defender, condition_id):
            mult = conditions[condition_id].incoming_damage_mult or 1.0
            amount = int(amount * mult)
    return amount


def _apply_badge_damage_bonus(
    amount: int,
    badge_ids: list[str],
    badges: dict[str, BadgeDefinition],
) -> int:
    mult = 1.0
    for badge_id in badge_ids:
        badge = badges.get(badge_id)
        if badge:
            mult *= badge.outgoing_damage_mult
    return int(amount * mult)


def _resolve_targets(
    target: EffectTarget,
    attacker: Combatant,
    defender: Combatant,
) -> tuple[Combatant, Combatant]:
    if target == EffectTarget.SELF:
        return attacker, defender
    return defender, attacker
