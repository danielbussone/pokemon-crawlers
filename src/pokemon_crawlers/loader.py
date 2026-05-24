"""Load and validate balance JSON into typed models."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from pokemon_crawlers.models import (
    BadgeDefinition,
    Card,
    CardType,
    ConditionDefinition,
    ConditionId,
    Constants,
    Effect,
    EffectTarget,
    EffectType,
    EnemyAction,
    EnemyDefinition,
    EvolutionConfig,
    GameBalance,
    PokemonType,
    Rarity,
    RunConfig,
    StarterDefinition,
    StatusType,
)


class BalanceLoadError(Exception):
    """Raised when balance JSON is missing, malformed, or inconsistent."""


def load_balance(balance_dir: Path) -> GameBalance:
    balance_dir = balance_dir.resolve()
    if not balance_dir.is_dir():
        raise BalanceLoadError(f"Balance directory not found: {balance_dir}")

    constants = _load_constants(_read_json(balance_dir / "constants.json"))
    conditions = _load_conditions(_read_json(balance_dir / "conditions.json"))
    type_chart = _load_type_chart(_read_json(balance_dir / "type_chart.json"))
    cards = _load_cards(_read_json(balance_dir / "cards.json"))
    enemies = _load_enemies(_read_json(balance_dir / "enemies.json"))
    starters = _load_starters(_read_json(balance_dir / "starters.json"))
    badges = _load_badges(_read_json(balance_dir / "badges.json"))
    run_config = _load_run_config(_read_json(balance_dir / "run_config.json"), cards, enemies, badges)

    _validate_card_graph(cards)
    _validate_starters(starters, cards)
    _validate_enemies(enemies)
    _validate_run_config(run_config, cards, enemies, badges)

    return GameBalance(
        constants=constants,
        conditions=conditions,
        type_chart=type_chart,
        cards=cards,
        enemies=enemies,
        starters=starters,
        badges=badges,
        run_config=run_config,
    )


def _read_json(path: Path) -> Any:
    if not path.is_file():
        raise BalanceLoadError(f"Missing balance file: {path}")
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except json.JSONDecodeError as exc:
        raise BalanceLoadError(f"Invalid JSON in {path}: {exc}") from exc


def _load_constants(data: dict[str, Any]) -> Constants:
    player = data.get("player", {})
    combat = data.get("combat", {})
    rewards = data.get("rewards", {})
    return Constants(
        player_max_hp=int(player["max_hp"]),
        player_max_stamina=int(player["max_stamina"]),
        hand_size=int(player["hand_size"]),
        confuse_self_dmg=int(combat["confuse_self_dmg"]),
        min_damage=int(combat["min_damage"]),
        draft_options=int(rewards["draft_options"]),
    )


def _load_conditions(data: dict[str, Any]) -> dict[ConditionId, ConditionDefinition]:
    conditions: dict[ConditionId, ConditionDefinition] = {}
    for key, raw in data.items():
        condition_id = ConditionId(key)
        slow_player = raw.get("on_player", {})
        slow_enemy = raw.get("on_enemy", {})
        conditions[condition_id] = ConditionDefinition(
            id=condition_id,
            outgoing_damage_mult=_optional_float(raw.get("outgoing_damage_mult")),
            incoming_damage_mult=_optional_float(raw.get("incoming_damage_mult")),
            blocks_block_gain=bool(raw.get("blocks_block_gain", False)),
            default_duration=_optional_int(raw.get("default_duration")),
            initial_budget=_optional_int(raw.get("initial_budget")),
            reapply_budget_add=_optional_int(raw.get("reapply_budget_add")),
            reapply_budget_cap=_optional_int(raw.get("reapply_budget_cap")),
            miss_on_even_budget=bool(raw.get("miss_on_even_budget", False)),
            non_attacks_decrement=bool(raw.get("non_attacks_decrement", False)),
            on_player_stamina_delta=_optional_int(slow_player.get("stamina_delta")),
            on_enemy_grant_player_stamina_next_turn=_optional_int(
                slow_enemy.get("grant_player_stamina_next_turn")
            ),
            allow_stamina_overflow=bool(slow_enemy.get("allow_stamina_overflow", False)),
        )
    required = {
        ConditionId.INTIMIDATED,
        ConditionId.DISTRACTED,
        ConditionId.BLINDED,
        ConditionId.DEFENSELESS,
        ConditionId.SLOW,
    }
    missing = required - conditions.keys()
    if missing:
        raise BalanceLoadError(f"Missing condition definitions: {sorted(m.value for m in missing)}")
    return conditions


def _load_type_chart(data: dict[str, Any]) -> dict[tuple[PokemonType, PokemonType], float]:
    chart: dict[tuple[PokemonType, PokemonType], float] = {}
    for entry in data.get("matchups", []):
        attacker = PokemonType(entry["attacker"])
        defender = PokemonType(entry["defender"])
        multiplier = float(entry["multiplier"])
        chart[(attacker, defender)] = multiplier
    return chart


def _load_cards(data: dict[str, Any]) -> dict[str, Card]:
    cards: dict[str, Card] = {}
    for raw in data.get("cards", []):
        card_id = raw["id"]
        if card_id in cards:
            raise BalanceLoadError(f"Duplicate card id: {card_id}")
        cards[card_id] = Card(
            id=card_id,
            name=raw["name"],
            pokemon=raw["pokemon"],
            card_type=CardType(raw["card_type"]),
            pokemon_type=PokemonType(raw["pokemon_type"]),
            cost=int(raw["cost"]),
            power=int(raw.get("power", 0)),
            effects=tuple(_parse_effects(raw.get("effects", []))),
            rarity=Rarity(raw["rarity"]),
            evolves_to=raw.get("evolves_to"),
            self_evolve=bool(raw.get("self_evolve", False)),
            tier=int(raw.get("tier", 1)),
        )
    if not cards:
        raise BalanceLoadError("No cards defined")
    return cards


def _load_enemies(data: dict[str, Any]) -> dict[str, EnemyDefinition]:
    enemies: dict[str, EnemyDefinition] = {}
    for raw in data.get("enemies", []):
        enemy_id = raw["id"]
        if enemy_id in enemies:
            raise BalanceLoadError(f"Duplicate enemy id: {enemy_id}")
        action_pool = tuple(_parse_enemy_actions(raw.get("action_pool", []), enemy_id))
        boss_pattern = tuple(raw.get("boss_pattern", []))
        enemies[enemy_id] = EnemyDefinition(
            id=enemy_id,
            name=raw["name"],
            pokemon_type=PokemonType(raw["pokemon_type"]),
            max_hp=int(raw["max_hp"]),
            is_wild=bool(raw["is_wild"]),
            is_boss=bool(raw["is_boss"]),
            action_pool=action_pool,
            boss_pattern=boss_pattern,
            boss_pattern_loop_start=int(raw.get("boss_pattern_loop_start", 0)),
            xp_reward=int(raw.get("xp_reward", 0)),
        )
    if not enemies:
        raise BalanceLoadError("No enemies defined")
    return enemies


def _parse_enemy_actions(raw_actions: list[dict[str, Any]], enemy_id: str) -> list[EnemyAction]:
    actions: list[EnemyAction] = []
    seen: set[str] = set()
    for raw in raw_actions:
        action_id = raw["id"]
        if action_id in seen:
            raise BalanceLoadError(f"Duplicate action id '{action_id}' on enemy '{enemy_id}'")
        seen.add(action_id)
        actions.append(
            EnemyAction(
                id=action_id,
                name=raw["name"],
                is_attack=bool(raw["is_attack"]),
                effects=tuple(_parse_effects(raw.get("effects", []))),
                base_weight=int(raw.get("base_weight", 1)),
                preferred_phase=raw.get("preferred_phase"),
            )
        )
    return actions


def _load_starters(data: dict[str, Any]) -> dict[str, StarterDefinition]:
    starters: dict[str, StarterDefinition] = {}
    for key, raw in data.items():
        starter_id = raw.get("id", key)
        starters[starter_id] = StarterDefinition(
            id=starter_id,
            name=raw["name"],
            deck=tuple(raw["deck"]),
        )
    if not starters:
        raise BalanceLoadError("No starters defined")
    return starters


def _load_badges(data: dict[str, Any]) -> dict[str, BadgeDefinition]:
    badges: dict[str, BadgeDefinition] = {}
    for key, raw in data.items():
        badge_id = raw.get("id", key)
        badges[badge_id] = BadgeDefinition(
            id=badge_id,
            name=raw["name"],
            outgoing_damage_mult=float(raw.get("outgoing_damage_mult", 1.0)),
        )
    return badges


def _load_run_config(
    data: dict[str, Any],
    cards: dict[str, Card],
    enemies: dict[str, EnemyDefinition],
    badges: dict[str, BadgeDefinition],
) -> RunConfig:
    evolution_raw = data.get("evolution", {})
    return RunConfig(
        encounter_sequence=tuple(data["encounter_sequence"]),
        reward_pool=tuple(data["reward_pool"]),
        evolution=EvolutionConfig(
            from_card=evolution_raw["from"],
            to_card=evolution_raw["to"],
            after_encounter=int(data["evolution_catalyst_after_encounter"]),
        ),
        signature_card=data["signature_card"],
        badge_id=data["badge_id"],
    )


def _parse_effects(raw_effects: list[dict[str, Any]]) -> list[Effect]:
    effects: list[Effect] = []
    for raw in raw_effects:
        effect_type = EffectType(raw["type"])
        target = EffectTarget(raw.get("target", "enemy"))
        status = StatusType(raw["status"]) if raw.get("status") else None
        condition = ConditionId(raw["condition"]) if raw.get("condition") else None
        status_magnitude = raw.get("status_magnitude", raw.get("magnitude"))
        if effect_type != EffectType.STATUS:
            status_magnitude = raw.get("status_magnitude")
        magnitude = int(raw.get("magnitude", 0))
        effects.append(
            Effect(
                type=effect_type,
                magnitude=magnitude if effect_type != EffectType.STATUS else 0,
                target=target,
                status=status,
                status_duration=_optional_int(raw.get("duration")),
                status_magnitude=_optional_int(status_magnitude) if effect_type == EffectType.STATUS else None,
                condition=condition,
                condition_duration=_optional_int(raw.get("duration")) if condition else None,
                ignore_block=bool(raw.get("ignore_block", False)),
            )
        )
    return effects


def _validate_card_graph(cards: dict[str, Card]) -> None:
    for card in cards.values():
        if card.evolves_to and card.evolves_to not in cards:
            raise BalanceLoadError(
                f"Card '{card.id}' evolves_to unknown card '{card.evolves_to}'"
            )


def _validate_starters(starters: dict[str, StarterDefinition], cards: dict[str, Card]) -> None:
    for starter in starters.values():
        if not starter.deck:
            raise BalanceLoadError(f"Starter '{starter.id}' has empty deck")
        for card_id in starter.deck:
            if card_id not in cards:
                raise BalanceLoadError(
                    f"Starter '{starter.id}' references unknown card '{card_id}'"
                )


def _validate_enemies(enemies: dict[str, EnemyDefinition]) -> None:
    for enemy in enemies.values():
        pool_ids = {action.id for action in enemy.action_pool}
        if not pool_ids:
            raise BalanceLoadError(f"Enemy '{enemy.id}' has empty action_pool")
        if enemy.is_boss:
            if not enemy.boss_pattern:
                raise BalanceLoadError(f"Boss '{enemy.id}' missing boss_pattern")
            if enemy.boss_pattern_loop_start < 0 or enemy.boss_pattern_loop_start >= len(enemy.boss_pattern):
                raise BalanceLoadError(
                    f"Boss '{enemy.id}' boss_pattern_loop_start out of range"
                )
            for action_id in enemy.boss_pattern:
                if action_id not in pool_ids:
                    raise BalanceLoadError(
                        f"Boss '{enemy.id}' pattern references unknown action '{action_id}'"
                    )


def _validate_run_config(
    run_config: RunConfig,
    cards: dict[str, Card],
    enemies: dict[str, EnemyDefinition],
    badges: dict[str, BadgeDefinition],
) -> None:
    if not run_config.encounter_sequence:
        raise BalanceLoadError("run_config.encounter_sequence is empty")
    for enemy_id in run_config.encounter_sequence:
        if enemy_id not in enemies:
            raise BalanceLoadError(
                f"encounter_sequence references unknown enemy '{enemy_id}'"
            )
    for card_id in run_config.reward_pool:
        if card_id not in cards:
            raise BalanceLoadError(
                f"reward_pool references unknown card '{card_id}'"
            )
    if run_config.signature_card not in cards:
        raise BalanceLoadError(
            f"signature_card '{run_config.signature_card}' not found"
        )
    if run_config.badge_id not in badges:
        raise BalanceLoadError(f"badge_id '{run_config.badge_id}' not found")
    if run_config.evolution.from_card not in cards:
        raise BalanceLoadError(
            f"evolution.from '{run_config.evolution.from_card}' not found"
        )
    if run_config.evolution.to_card not in cards:
        raise BalanceLoadError(
            f"evolution.to '{run_config.evolution.to_card}' not found"
        )


def _optional_int(value: Any) -> int | None:
    if value is None:
        return None
    return int(value)


def _optional_float(value: Any) -> float | None:
    if value is None:
        return None
    return float(value)
