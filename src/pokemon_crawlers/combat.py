"""Turn-based combat state machine."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from enum import StrEnum

from pokemon_crawlers.deck import discard_hand, draw_to_hand, play_card_from_hand
from pokemon_crawlers.effects import (
    apply_confuse_self_damage,
    apply_player_turn_start_modifiers,
    decrement_conditions,
    decrement_statuses,
    has_status,
    resolve_card_effects,
    resolve_enemy_action_effects,
    tick_poison,
)
from pokemon_crawlers.enemy_ai import (
    advance_boss_pattern_index,
    choose_wild_action,
    get_boss_action,
    get_next_boss_intent,
)
from pokemon_crawlers.models import (
    CardType,
    EnemyDefinition,
    EnemyState,
    GameBalance,
    PlayerState,
    StatusType,
)
from pokemon_crawlers.registry import get_balance


class CombatOutcome(StrEnum):
    PLAYER_WIN = "player_win"
    PLAYER_LOSS = "player_loss"
    ONGOING = "ongoing"


@dataclass
class PlayCardResult:
    success: bool
    reason: str = ""
    card_id: str | None = None


@dataclass
class CombatContext:
    player: PlayerState
    enemy: EnemyState
    enemy_def: EnemyDefinition
    balance: GameBalance
    turn: int = 0
    boss_pattern_index: int = 0
    next_enemy_action_name: str | None = None
    items_used_this_turn: int = 0


@dataclass
class CombatResult:
    outcome: CombatOutcome
    turns: int


@dataclass
class EnemyTurnResult:
    outcome: CombatOutcome
    action_name: str | None = None
    slept: bool = False
    paralyzed_skip: bool = False
    acted: bool = False
    poison_win: bool = False


def format_enemy_turn_message(
    ctx: CombatContext,
    before_player_hp: int,
    result: EnemyTurnResult,
) -> str:
    """Human-readable summary of what happened on the enemy turn."""
    name = ctx.enemy_def.name
    if result.poison_win and result.outcome == CombatOutcome.PLAYER_WIN:
        return f"{name} succumbed to poison!"

    parts: list[str] = []
    if result.slept:
        parts.append(f"{name} is asleep and did not act.")
    elif result.paralyzed_skip and result.action_name:
        parts.append(f"{name} is paralyzed — {result.action_name} failed!")
    elif result.action_name:
        parts.append(f"{name} used {result.action_name}.")

    dmg = before_player_hp - ctx.player.hp
    if dmg > 0:
        parts.append(f"You took {dmg} damage.")
    elif result.acted and dmg == 0 and not result.paralyzed_skip and not result.slept:
        parts.append("No damage to you.")

    if not parts:
        return f"{name} took a turn."
    return " ".join(parts)


def create_enemy_state(enemy_id: str, balance: GameBalance | None = None) -> tuple[EnemyState, EnemyDefinition]:
    balance = balance or get_balance()
    enemy_def = balance.enemies[enemy_id]
    enemy = EnemyState(
        hp=enemy_def.max_hp,
        max_hp=enemy_def.max_hp,
        pokemon_type=enemy_def.pokemon_type,
        enemy_id=enemy_id,
        is_boss=enemy_def.is_boss,
        is_wild=enemy_def.is_wild,
    )
    return enemy, enemy_def


def start_combat(
    player: PlayerState,
    enemy_id: str,
    balance: GameBalance | None = None,
) -> CombatContext:
    balance = balance or get_balance()
    enemy, enemy_def = create_enemy_state(enemy_id, balance)
    ctx = CombatContext(player=player, enemy=enemy, enemy_def=enemy_def, balance=balance)
    from pokemon_crawlers.enemy_ai import uses_fixed_pattern

    if uses_fixed_pattern(enemy_def):
        intent = get_next_boss_intent(enemy_def, ctx.boss_pattern_index)
        ctx.next_enemy_action_name = intent.name
    return ctx


def check_outcome(ctx: CombatContext) -> CombatOutcome:
    if ctx.enemy.hp <= 0:
        return CombatOutcome.PLAYER_WIN
    if ctx.player.hp <= 0:
        return CombatOutcome.PLAYER_LOSS
    return CombatOutcome.ONGOING


def player_turn_begin(ctx: CombatContext) -> CombatOutcome:
    ctx.turn += 1
    ctx.items_used_this_turn = 0
    ctx.player.block = 0
    apply_player_turn_start_modifiers(ctx.player, ctx.balance)

    tick_poison(ctx.player)

    outcome = check_outcome(ctx)
    if outcome != CombatOutcome.ONGOING:
        return outcome

    if has_status(ctx.player, StatusType.SLEEP):
        _tick_conditions_and_statuses(ctx.player)
        discard_hand(ctx.player)
        return check_outcome(ctx)

    _tick_conditions_and_statuses(ctx.player)
    outcome = check_outcome(ctx)
    if outcome != CombatOutcome.ONGOING:
        return outcome

    draw_to_hand(ctx.player, ctx.balance)
    return CombatOutcome.ONGOING


def can_play_card(ctx: CombatContext, hand_index: int) -> PlayCardResult:
    if has_status(ctx.player, StatusType.SLEEP):
        return PlayCardResult(success=False, reason="Asleep — cannot play cards.")

    if hand_index < 0 or hand_index >= len(ctx.player.hand):
        return PlayCardResult(success=False, reason="Invalid hand index.")

    card_id = ctx.player.hand[hand_index]
    card = ctx.balance.cards[card_id]

    if has_status(ctx.player, StatusType.PARALYZE) and card.card_type == CardType.ATTACK:
        return PlayCardResult(success=False, reason="Paralyzed — Attack cards locked.")

    if card.cost > ctx.player.current_stamina:
        return PlayCardResult(success=False, reason="Not enough stamina.")

    return PlayCardResult(success=True, card_id=card_id)


def play_card(ctx: CombatContext, hand_index: int) -> PlayCardResult:
    check = can_play_card(ctx, hand_index)
    if not check.success:
        return check

    card_id = ctx.player.hand[hand_index]
    card = ctx.balance.cards[card_id]

    apply_confuse_self_damage(ctx.player, ctx.balance.constants.confuse_self_dmg)

    outcome = check_outcome(ctx)
    if outcome == CombatOutcome.PLAYER_LOSS:
        return PlayCardResult(success=False, reason="Player defeated.")

    card_id = play_card_from_hand(ctx.player, hand_index)
    card = ctx.balance.cards[card_id]
    ctx.player.current_stamina -= card.cost

    resolve_card_effects(
        card.effects,
        card.card_type,
        card.pokemon_type,
        player=ctx.player,
        enemy=ctx.enemy,
        balance=ctx.balance,
        badges=ctx.balance.badges,
    )

    if check_outcome(ctx) == CombatOutcome.PLAYER_WIN:
        return PlayCardResult(success=True, card_id=card_id)

    return PlayCardResult(success=True, card_id=card_id)


def end_player_turn(ctx: CombatContext) -> None:
    discard_hand(ctx.player)


def enemy_turn(ctx: CombatContext) -> EnemyTurnResult:
    ctx.enemy.block = 0

    tick_poison(ctx.enemy)
    outcome = check_outcome(ctx)
    if outcome != CombatOutcome.ONGOING:
        return EnemyTurnResult(
            outcome=outcome,
            poison_win=outcome == CombatOutcome.PLAYER_WIN,
        )

    slept = has_status(ctx.enemy, StatusType.SLEEP)
    paralyzed = has_status(ctx.enemy, StatusType.PARALYZE)

    from pokemon_crawlers.enemy_ai import uses_fixed_pattern

    if uses_fixed_pattern(ctx.enemy_def):
        action = get_boss_action(ctx.enemy_def, ctx.boss_pattern_index)
        ctx.next_enemy_action_name = get_next_boss_intent(
            ctx.enemy_def,
            advance_boss_pattern_index(ctx.enemy_def, ctx.boss_pattern_index),
        ).name
    else:
        action = choose_wild_action(ctx.enemy_def, ctx.enemy, ctx.player, ctx.balance)
        ctx.next_enemy_action_name = None

    action_name = action.name

    if slept:
        _tick_conditions_and_statuses(ctx.enemy)
        if uses_fixed_pattern(ctx.enemy_def):
            ctx.boss_pattern_index = advance_boss_pattern_index(
                ctx.enemy_def, ctx.boss_pattern_index
            )
        return EnemyTurnResult(
            outcome=check_outcome(ctx),
            action_name=action_name,
            slept=True,
        )

    _tick_conditions_and_statuses(ctx.enemy)
    outcome = check_outcome(ctx)
    if outcome != CombatOutcome.ONGOING:
        return EnemyTurnResult(outcome=outcome, action_name=action_name)

    skip_attack = paralyzed and action.is_attack
    acted = False
    if not skip_attack:
        apply_confuse_self_damage(ctx.enemy, ctx.balance.constants.confuse_self_dmg)
        outcome = check_outcome(ctx)
        if outcome != CombatOutcome.ONGOING:
            return EnemyTurnResult(outcome=outcome, action_name=action_name)

        resolve_enemy_action_effects(
            action.effects,
            action.is_attack,
            ctx.enemy,
            ctx.player,
            ctx.enemy.pokemon_type,
            ctx.balance,
            ctx.balance.badges,
        )
        acted = True

    if uses_fixed_pattern(ctx.enemy_def):
        ctx.boss_pattern_index = advance_boss_pattern_index(
            ctx.enemy_def, ctx.boss_pattern_index
        )

    return EnemyTurnResult(
        outcome=check_outcome(ctx),
        action_name=action_name,
        paralyzed_skip=skip_attack,
        acted=acted,
    )


def use_item(ctx: CombatContext, item_id: str) -> PlayCardResult:
    from pokemon_crawlers.items import use_item_in_combat

    result = use_item_in_combat(
        ctx.player,
        item_id,
        ctx.balance,
        items_used_this_turn=ctx.items_used_this_turn,
    )
    if result.success:
        ctx.items_used_this_turn += 1
    return PlayCardResult(success=result.success, reason=result.reason, card_id=item_id)


def run_combat_turn(ctx: CombatContext) -> CombatOutcome:
    """Run one full player turn then enemy turn."""
    outcome = player_turn_begin(ctx)
    if outcome != CombatOutcome.ONGOING:
        return outcome

    if has_status(ctx.player, StatusType.SLEEP):
        return enemy_turn(ctx).outcome

    return CombatOutcome.ONGOING


def run_combat(
    player: PlayerState,
    enemy_id: str,
    balance: GameBalance | None = None,
    *,
    max_turns: int = 200,
    choose_play: Callable[["CombatContext"], int | None] | None = None,
    choose_item: Callable[["CombatContext"], str | None] | None = None,
) -> CombatResult:
    """Run combat until win/loss or max_turns (safety cap).

    If ``choose_play`` is set, it selects a hand index each play step; ``None`` ends the turn.
    Default autoplay uses the first playable card (legacy greedy).
    """
    if choose_play is None:
        def choose_play(ctx: CombatContext) -> int | None:
            for index in range(len(ctx.player.hand)):
                if can_play_card(ctx, index).success:
                    return index
            return None

    ctx = start_combat(player, enemy_id, balance)
    turns = 0

    while turns < max_turns:
        outcome = player_turn_begin(ctx)
        if outcome != CombatOutcome.ONGOING:
            return CombatResult(outcome=outcome, turns=ctx.turn)

        if has_status(ctx.player, StatusType.SLEEP):
            end_player_turn(ctx)
            turn_result = enemy_turn(ctx)
            if turn_result.outcome != CombatOutcome.ONGOING:
                return CombatResult(outcome=turn_result.outcome, turns=ctx.turn)
            continue

        while True:
            if choose_item is not None and ctx.items_used_this_turn < 1:
                item_id = choose_item(ctx)
                if item_id is not None:
                    use_item(ctx, item_id)
                    outcome = check_outcome(ctx)
                    if outcome != CombatOutcome.ONGOING:
                        return CombatResult(outcome=outcome, turns=ctx.turn)

            if ctx.player.current_stamina <= 0 or not ctx.player.hand:
                break

            hand_index = choose_play(ctx)
            if hand_index is None:
                break
            if not can_play_card(ctx, hand_index).success:
                break
            play_card(ctx, hand_index)

            outcome = check_outcome(ctx)
            if outcome != CombatOutcome.ONGOING:
                return CombatResult(outcome=outcome, turns=ctx.turn)

        end_player_turn(ctx)
        turn_result = enemy_turn(ctx)
        if turn_result.outcome != CombatOutcome.ONGOING:
            return CombatResult(outcome=turn_result.outcome, turns=ctx.turn)

    return CombatResult(outcome=CombatOutcome.ONGOING, turns=ctx.turn)


def _tick_conditions_and_statuses(combatant: PlayerState | EnemyState) -> None:
    decrement_statuses(combatant)
    decrement_conditions(combatant)
