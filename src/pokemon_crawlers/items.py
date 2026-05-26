"""Consumable item effects and in-combat use."""

from __future__ import annotations

from dataclasses import dataclass

from pokemon_crawlers.effects import has_status
from pokemon_crawlers.models import (
    GameBalance,
    ItemDefinition,
    ItemEffectType,
    PlayerState,
    StatusType,
)


@dataclass
class ItemUseResult:
    success: bool
    reason: str = ""


def count_inventory_item(player: PlayerState, item_id: str) -> int:
    return sum(1 for entry in player.inventory if entry == item_id)


def inventory_has_room(
    player: PlayerState,
    item_id: str,
    balance: GameBalance,
) -> bool:
    if len(player.inventory) >= balance.economy.inventory_max_slots:
        return False
    if count_inventory_item(player, item_id) >= balance.economy.inventory_max_per_item:
        return False
    return True


def add_item_to_inventory(player: PlayerState, item_id: str, balance: GameBalance) -> bool:
    if not inventory_has_room(player, item_id, balance):
        return False
    player.inventory.append(item_id)
    return True


def remove_item_from_inventory(player: PlayerState, item_id: str) -> bool:
    try:
        player.inventory.remove(item_id)
        return True
    except ValueError:
        return False


def apply_item_effect(player: PlayerState, item: ItemDefinition) -> ItemUseResult:
    effect = item.effect
    if effect.type == ItemEffectType.HEAL:
        if player.hp >= player.max_hp:
            return ItemUseResult(success=False, reason="Already at full HP.")
        player.hp = min(player.max_hp, player.hp + effect.magnitude)
        return ItemUseResult(success=True)

    if effect.type == ItemEffectType.CURE_STATUS:
        if effect.status is None:
            return ItemUseResult(success=False, reason="Invalid item effect.")
        if not has_status(player, effect.status):
            return ItemUseResult(success=False, reason=f"No {effect.status.value} to cure.")
        player.statuses = [s for s in player.statuses if s.type != effect.status]
        return ItemUseResult(success=True)

    if effect.type == ItemEffectType.CURE_ALL_STATUSES:
        if not player.statuses:
            return ItemUseResult(success=False, reason="No statuses to cure.")
        player.statuses.clear()
        return ItemUseResult(success=True)

    if effect.type == ItemEffectType.REVIVE:
        if player.hp > 0:
            return ItemUseResult(success=False, reason="Can only use Revive at 0 HP.")
        player.hp = max(1, player.max_hp * effect.magnitude // 100)
        return ItemUseResult(success=True)

    return ItemUseResult(success=False, reason="Unknown item effect.")


def use_item_in_combat(
    player: PlayerState,
    item_id: str,
    balance: GameBalance,
    *,
    items_used_this_turn: int,
) -> ItemUseResult:
    if items_used_this_turn >= 1:
        return ItemUseResult(success=False, reason="Already used an item this turn.")

    if item_id not in balance.items:
        return ItemUseResult(success=False, reason="Unknown item.")

    item = balance.items[item_id]
    if not item.in_combat:
        return ItemUseResult(success=False, reason="Item cannot be used in combat.")

    if count_inventory_item(player, item_id) < 1:
        return ItemUseResult(success=False, reason="Item not in inventory.")

    result = apply_item_effect(player, item)
    if result.success:
        remove_item_from_inventory(player, item_id)
    return result
