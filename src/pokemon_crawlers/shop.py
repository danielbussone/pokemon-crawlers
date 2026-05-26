"""Pokémon Center and Poké Mart between-stage shopping."""

from __future__ import annotations

from dataclasses import dataclass, field

from pokemon_crawlers.items import add_item_to_inventory, apply_item_effect, inventory_has_room
from pokemon_crawlers.models import GameBalance, ItemDefinition, PlayerState


@dataclass
class ShopResult:
    gold_spent: int = 0
    center_visits: int = 0
    items_purchased: list[str] = field(default_factory=list)


def items_for_shop_window(balance: GameBalance, shop_window: int) -> list[ItemDefinition]:
    return [
        item
        for item in balance.items.values()
        if shop_window in item.shop_windows
    ]


def can_afford(player: PlayerState, cost: int) -> bool:
    return player.gold >= cost


def purchase_center(player: PlayerState, balance: GameBalance) -> ShopResult:
    result = ShopResult()
    cost = balance.economy.center_cost
    if not can_afford(player, cost):
        return result

    player.gold -= cost
    result.gold_spent = cost
    player.max_hp += balance.economy.center_max_hp_bonus
    player.hp = player.max_hp
    player.center_visits += 1
    result.center_visits = 1
    return result


def purchase_item(
    player: PlayerState,
    item_id: str,
    balance: GameBalance,
) -> ShopResult:
    result = ShopResult()
    item = balance.items.get(item_id)
    if item is None:
        return result
    if not can_afford(player, item.cost):
        return result
    if not inventory_has_room(player, item_id, balance):
        return result

    player.gold -= item.cost
    result.gold_spent = item.cost
    add_item_to_inventory(player, item_id, balance)
    result.items_purchased.append(item_id)
    return result


def apply_economy_shim_heal(player: PlayerState) -> None:
    """Phase-1 balance testing: full heal without gold cost."""
    player.hp = player.max_hp


def use_revive_between_fights(player: PlayerState, item_id: str, balance: GameBalance) -> bool:
    """Use Revive or similar between-combat items."""
    item = balance.items.get(item_id)
    if item is None or item.in_combat:
        return False
    from pokemon_crawlers.items import count_inventory_item, remove_item_from_inventory
    from pokemon_crawlers.items import apply_item_effect as _apply

    if count_inventory_item(player, item_id) < 1:
        return False
    outcome = _apply(player, item)
    if outcome.success:
        remove_item_from_inventory(player, item_id)
        return True
    return False
