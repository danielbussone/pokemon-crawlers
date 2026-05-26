"""Heuristic autoplay for combat, draft, shop, and items (bulk simulation)."""

from __future__ import annotations

import random
from typing import TYPE_CHECKING

from pokemon_crawlers.combat import can_play_card
from pokemon_crawlers.effects import has_status
from pokemon_crawlers.items import count_inventory_item, inventory_has_room
from pokemon_crawlers.models import CardType, EffectTarget, EffectType, GameBalance, StatusType
from pokemon_crawlers.shop import items_for_shop_window, purchase_center, purchase_item

if TYPE_CHECKING:
    from pokemon_crawlers.combat import CombatContext
    from pokemon_crawlers.logger import RunLog
    from pokemon_crawlers.models import PlayerState

PLAY_STYLES = frozenset({"balanced", "aggressive", "conservative"})
SHOP_POLICIES = frozenset(
    {"greedy", "minimal", "random", "never_center", "potions", "items_only"}
)


def _normalize_play_style(play_style: str) -> str:
    style = play_style.lower()
    if style not in PLAY_STYLES:
        raise ValueError(f"Unknown play_style '{play_style}' (use balanced, aggressive, conservative)")
    return style


def _style_multipliers(play_style: str) -> tuple[float, float, float]:
    """Damage, defense/heal, and status/condition score multipliers."""
    if play_style == "aggressive":
        return (1.4, 0.6, 1.2)
    if play_style == "conservative":
        return (0.7, 1.4, 0.9)
    return (1.0, 1.0, 1.0)


def choose_play_index(ctx: CombatContext, *, play_style: str = "balanced") -> int | None:
    """Pick the best playable hand index, or None to end the turn."""
    style = _normalize_play_style(play_style)
    playable = [
        index
        for index in range(len(ctx.player.hand))
        if can_play_card(ctx, index).success
    ]
    if not playable:
        return None
    return max(playable, key=lambda index: _score_play(ctx, index, style))


def _score_play(ctx: CombatContext, hand_index: int, play_style: str) -> float:
    dmg_mult, defense_mult, status_mult = _style_multipliers(play_style)
    card_id = ctx.player.hand[hand_index]
    card = ctx.balance.cards[card_id]
    player = ctx.player
    enemy = ctx.enemy
    hp_ratio = player.hp / max(player.max_hp, 1)
    enemy_ratio = enemy.hp / max(enemy.max_hp, 1)

    score = 0.0
    for effect in card.effects:
        if effect.type == EffectType.DAMAGE:
            score += effect.magnitude * 2.5 * dmg_mult
        elif effect.type == EffectType.BLOCK:
            weight = 2.2 if hp_ratio < 0.45 else 0.7
            if enemy_ratio < 0.35:
                weight *= 0.5
            score += effect.magnitude * weight * defense_mult
        elif effect.type == EffectType.HEAL:
            missing = player.max_hp - player.hp
            if missing <= 0:
                score -= 5
            else:
                heal_value = min(effect.magnitude, missing)
                weight = 3.0 if hp_ratio < 0.55 else 0.4
                score += heal_value * weight * defense_mult
        elif effect.type == EffectType.APPLY_CONDITION:
            base = 4.0 if effect.target == EffectTarget.ENEMY else 1.0
            score += base * status_mult
        elif effect.type == EffectType.STATUS:
            score += 3.5 * status_mult

    if card.card_type == CardType.ATTACK:
        score += (card.power / max(card.cost, 0.25)) * dmg_mult

    if card.id == "growl" and enemy.hp > 8:
        score *= 0.35

    if card.id == "quick_attack" and player.current_stamina >= 2:
        score += 1.5 * dmg_mult

    return score


def choose_draft_pick(
    player: PlayerState,
    options: list[str],
    balance: GameBalance,
    *,
    play_style: str = "balanced",
) -> str | None:
    if not options:
        return None
    style = _normalize_play_style(play_style)
    hp_ratio = player.hp / max(player.max_hp, 1)
    return max(
        options,
        key=lambda card_id: _score_draft(card_id, balance, hp_ratio, style),
    )


def _score_draft(
    card_id: str,
    balance: GameBalance,
    hp_ratio: float,
    play_style: str,
) -> float:
    dmg_mult, defense_mult, status_mult = _style_multipliers(play_style)
    card = balance.cards[card_id]
    score = 0.0

    for effect in card.effects:
        if effect.type == EffectType.BLOCK:
            score += effect.magnitude * (3.0 if hp_ratio < 0.5 else 1.0) * defense_mult
        elif effect.type == EffectType.HEAL:
            score += effect.magnitude * (3.5 if hp_ratio < 0.55 else 0.5) * defense_mult
        elif effect.type == EffectType.DAMAGE:
            score += effect.magnitude * (2.0 if hp_ratio >= 0.5 else 0.8) * dmg_mult
        elif effect.type in (EffectType.APPLY_CONDITION, EffectType.STATUS):
            score += 2.5 * status_mult

    if card.card_type == CardType.ATTACK:
        score += (card.power / max(card.cost, 1)) * dmg_mult

    if card_id in {"harden", "recover", "defense_curl"}:
        score += (4.0 if hp_ratio < 0.45 else 0.0) * defense_mult

    if card_id == "growl":
        score += 0.5

    return score


def choose_item_use(ctx: CombatContext) -> str | None:
    """Pick an inventory item to use this turn, or None."""
    player = ctx.player
    balance = ctx.balance

    if ctx.items_used_this_turn >= 1:
        return None

    if has_status(player, StatusType.POISON):
        for item_id in player.inventory:
            if item_id == "antidote":
                return "antidote"
        for item_id in player.inventory:
            if item_id == "full_heal":
                return "full_heal"

    if has_status(player, StatusType.SLEEP):
        for item_id in player.inventory:
            if item_id == "awakening":
                return "awakening"
        for item_id in player.inventory:
            if item_id == "full_heal":
                return "full_heal"

    if has_status(player, StatusType.PARALYZE):
        for item_id in player.inventory:
            if item_id == "parlyz_heal":
                return "parlyz_heal"
        for item_id in player.inventory:
            if item_id == "full_heal":
                return "full_heal"

    if has_status(player, StatusType.CONFUSE):
        for item_id in player.inventory:
            if item_id == "full_heal":
                return "full_heal"

    hp_ratio = player.hp / max(player.max_hp, 1)
    if hp_ratio < 0.4:
        for item_id in ("super_potion", "potion"):
            if count_inventory_item(player, item_id) > 0:
                return item_id

    return None


def execute_shop_policy(
    player: PlayerState,
    balance: GameBalance,
    *,
    shop_window: int,
    next_stage_id: str | None,
    policy: str = "greedy",
    rng: random.Random | None = None,
    run_log: RunLog | None = None,
) -> None:
    """Auto-shop after mid-boss."""
    rng = rng or random.Random()
    policy = "potions" if policy == "items_only" else policy

    if policy == "minimal":
        return

    if policy == "random":
        if rng.random() < 0.5 and player.gold >= balance.economy.center_cost:
            _buy_center(player, balance, run_log)
        for _ in range(2):
            mart = items_for_shop_window(balance, shop_window)
            if mart and rng.random() < 0.4:
                item = rng.choice(mart)
                _buy_item(player, balance, item.id, run_log)
        return

    if policy == "potions":
        _execute_potions_shop(player, balance, shop_window=shop_window, run_log=run_log)
        return

    hp_ratio = player.hp / max(player.max_hp, 1)
    if policy == "never_center":
        pass
    elif hp_ratio < 0.65 or player.center_visits == 0:
        if player.gold >= balance.economy.center_cost:
            _buy_center(player, balance, run_log)

    if next_stage_id == "viridian_forest":
        _try_buy(player, balance, "antidote", shop_window, run_log)
    elif next_stage_id == "pewter":
        _try_buy(player, balance, "awakening", shop_window, run_log)
        _try_buy(player, balance, "antidote", shop_window, run_log)
        _try_buy(player, balance, "parlyz_heal", shop_window, run_log)

    while len(player.inventory) < balance.economy.inventory_max_slots and player.gold >= 10:
        if not _try_buy(player, balance, "potion", shop_window, run_log):
            break


def _execute_potions_shop(
    player: PlayerState,
    balance: GameBalance,
    *,
    shop_window: int,
    run_log: RunLog | None,
) -> None:
    """Center when hurt; spend remaining gold on super potions then potions only."""
    hp_ratio = player.hp / max(player.max_hp, 1)
    if hp_ratio < 0.65 or player.center_visits == 0:
        if player.gold >= balance.economy.center_cost:
            _buy_center(player, balance, run_log)

    while len(player.inventory) < balance.economy.inventory_max_slots:
        bought = False
        if _try_buy(player, balance, "super_potion", shop_window, run_log):
            bought = True
        elif _try_buy(player, balance, "potion", shop_window, run_log):
            bought = True
        if not bought:
            break


def _buy_center(
    player: PlayerState,
    balance: GameBalance,
    run_log: RunLog | None,
) -> None:
    result = purchase_center(player, balance)
    if run_log and result.center_visits:
        run_log.record_gold_spent(result.gold_spent)
        run_log.center_visits += result.center_visits


def _buy_item(
    player: PlayerState,
    balance: GameBalance,
    item_id: str,
    run_log: RunLog | None,
) -> bool:
    result = purchase_item(player, item_id, balance)
    if run_log and result.items_purchased:
        run_log.record_gold_spent(result.gold_spent)
        run_log.items_purchased.extend(result.items_purchased)
        return True
    return False


def _try_buy(
    player: PlayerState,
    balance: GameBalance,
    item_id: str,
    shop_window: int,
    run_log: RunLog | None,
) -> bool:
    item = balance.items.get(item_id)
    if item is None or shop_window not in item.shop_windows:
        return False
    if not inventory_has_room(player, item_id, balance):
        return False
    if player.gold < item.cost:
        return False
    return _buy_item(player, balance, item_id, run_log)
