"""Interactive CLI prompts and combat display."""

from __future__ import annotations

from pokemon_crawlers.combat import (
    CombatContext,
    CombatOutcome,
    can_play_card,
    check_outcome,
    end_player_turn,
    enemy_turn,
    format_enemy_turn_message,
    play_card,
    player_turn_begin,
    start_combat,
    use_item,
)
from pokemon_crawlers.combat import CombatResult
from pokemon_crawlers.effects import has_status
from pokemon_crawlers.items import count_inventory_item
from pokemon_crawlers.models import GameBalance, PlayerState, StatusType
from pokemon_crawlers.shop import items_for_shop_window, purchase_center, purchase_item


def prompt_starter(balance: GameBalance) -> str:
    starters = list(balance.starters.keys())
    print("\nChoose your starter:")
    for index, starter_id in enumerate(starters, start=1):
        starter = balance.starters[starter_id]
        print(f"  {index}. {starter.name} ({starter_id})")
    while True:
        raw = input("Starter [1-3]: ").strip()
        if raw.isdigit():
            choice = int(raw)
            if 1 <= choice <= len(starters):
                return starters[choice - 1]
        print("Invalid choice — enter a number from the list.")


def prompt_draft(options: list[str], balance: GameBalance) -> str | None:
    if not options:
        return None
    print("\nDraft reward (or skip):")
    print("  0. Skip")
    for index, card_id in enumerate(options, start=1):
        card = balance.cards[card_id]
        print(f"  {index}. {card.name} — {card.card_type.value}, cost {card.cost}, power {card.power}")
    while True:
        raw = input("Pick [0-{}]: ".format(len(options))).strip()
        if raw == "0":
            return None
        if raw.isdigit():
            choice = int(raw)
            if 1 <= choice <= len(options):
                return options[choice - 1]
        print("Invalid choice.")


def prompt_shop(
    player: PlayerState,
    balance: GameBalance,
    *,
    shop_window: int,
) -> tuple[int, list[str], int]:
    """Returns (gold_spent, items_purchased, center_visits)."""
    gold_spent = 0
    items_purchased: list[str] = []
    center_visits = 0

    print(f"\n=== Shop (Window {shop_window}) ===")
    print(f"Gold: {player.gold} | HP: {player.hp}/{player.max_hp}")
    print(f"Inventory ({len(player.inventory)}/{balance.economy.inventory_max_slots}):")
    if player.inventory:
        for slot, item_id in enumerate(player.inventory, start=1):
            item = balance.items[item_id]
            print(f"  {slot}. {item.name} [{item_id}]")
    else:
        print("  (empty)")

    while True:
        print("\nShop commands:")
        print("  c — Pokémon Center (full heal +3 max HP)")
        print("  m — Buy item from Mart")
        print("  d — Done shopping")
        raw = input("> ").strip().lower()
        if raw in {"d", "done"}:
            break
        if raw in {"c", "center"}:
            result = purchase_center(player, balance)
            if result.center_visits:
                gold_spent += result.gold_spent
                center_visits += 1
                print(f"Center visit! HP {player.hp}/{player.max_hp}")
            else:
                print("Cannot afford Center or already purchased.")
            continue
        if raw in {"m", "mart"}:
            mart_items = items_for_shop_window(balance, shop_window)
            print("\nMart:")
            for index, item in enumerate(mart_items, start=1):
                owned = count_inventory_item(player, item.id)
                print(f"  {index}. {item.name} — {item.cost}g (owned: {owned})")
            pick_raw = input("Buy item # (or enter to cancel): ").strip()
            if not pick_raw.isdigit():
                continue
            pick = int(pick_raw)
            if 1 <= pick <= len(mart_items):
                item = mart_items[pick - 1]
                result = purchase_item(player, item.id, balance)
                if result.items_purchased:
                    gold_spent += result.gold_spent
                    items_purchased.extend(result.items_purchased)
                    print(f"Bought {item.name} ({item.id}).")
                else:
                    print("Purchase failed (gold or inventory full).")
            continue
        print("Enter c, m, or d.")

    return gold_spent, items_purchased, center_visits


def format_card_line(balance: GameBalance, hand_index: int, card_id: str, ctx: CombatContext) -> str:
    card = balance.cards[card_id]
    check = can_play_card(ctx, hand_index)
    playable = "ok" if check.success else check.reason
    return (
        f"  [{hand_index}] {card.name} ({card_id}) — "
        f"{card.card_type.value}, cost {card.cost}, power {card.power} — {playable}"
    )


def display_combat(ctx: CombatContext) -> None:
    player = ctx.player
    enemy = ctx.enemy
    print(f"\n--- Turn {ctx.turn} ---")
    print(
        f"You: {player.hp}/{player.max_hp} HP | "
        f"Stamina {player.current_stamina}/{player.max_stamina} | Block {player.block}"
    )
    if player.inventory:
        print(f"Items: {format_inventory_for_combat(player, ctx.balance)}")
    print(
        f"{ctx.enemy_def.name}: {enemy.hp}/{enemy.max_hp} HP | Block {enemy.block}"
    )
    if ctx.next_enemy_action_name:
        print(f"Enemy intent: {ctx.next_enemy_action_name}")
    if player.hand:
        print("Hand:")
        for index, card_id in enumerate(player.hand):
            print(format_card_line(ctx.balance, index, card_id, ctx))
    else:
        print("Hand: (empty)")


def balance_item_name(balance: GameBalance, item_id: str) -> str:
    item = balance.items.get(item_id)
    return item.name if item else item_id


def format_inventory_for_combat(player: PlayerState, balance: GameBalance) -> str:
    if not player.inventory:
        return "(empty)"
    parts: list[str] = []
    for slot, item_id in enumerate(player.inventory, start=1):
        item = balance.items.get(item_id)
        label = item.name if item else item_id
        parts.append(f"{slot}:{label}[{item_id}]")
    return ", ".join(parts)


def resolve_item_from_input(
    token: str, player: PlayerState, balance: GameBalance
) -> str | None:
    """Resolve slot number (1-based), item id, or item name to inventory item id."""
    token = token.strip().lower()
    if not token:
        return None
    if token.isdigit():
        slot = int(token)
        if 1 <= slot <= len(player.inventory):
            return player.inventory[slot - 1]
        return None
    for item_id in player.inventory:
        if item_id.lower() == token:
            return item_id
        item = balance.items.get(item_id)
        if item and item.name.lower() == token:
            return item_id
    return None


def _print_enemy_turn(ctx: CombatContext, before_player_hp: int) -> CombatOutcome:
    turn_result = enemy_turn(ctx)
    print(format_enemy_turn_message(ctx, before_player_hp, turn_result))
    return turn_result.outcome


def run_interactive_combat(
    player: PlayerState,
    enemy_id: str,
    balance: GameBalance,
) -> CombatResult:
    ctx = start_combat(player, enemy_id, balance)
    print(f"\n=== Fight: {ctx.enemy_def.name} ===")

    while True:
        outcome = player_turn_begin(ctx)
        if outcome != CombatOutcome.ONGOING:
            return CombatResult(outcome=outcome, turns=ctx.turn)

        if has_status(ctx.player, StatusType.SLEEP):
            print("You are asleep and skip your turn.")
            end_player_turn(ctx)
            before_hp = ctx.player.hp
            outcome = _print_enemy_turn(ctx, before_hp)
            if outcome != CombatOutcome.ONGOING:
                return CombatResult(outcome=outcome, turns=ctx.turn)
            continue

        while True:
            display_combat(ctx)
            outcome = check_outcome(ctx)
            if outcome != CombatOutcome.ONGOING:
                return CombatResult(outcome=outcome, turns=ctx.turn)

            print(
                "Commands: <hand index> play | i <slot|id|name> use item | e end turn | q quit"
            )
            raw = input("> ").strip()
            raw_lower = raw.lower()
            if raw_lower in {"e", "end"}:
                break
            if raw_lower in {"q", "quit"}:
                return CombatResult(outcome=CombatOutcome.PLAYER_LOSS, turns=ctx.turn)
            if raw_lower.startswith("i"):
                parts = raw.split(None, 1)
                item_token = parts[1].strip() if len(parts) > 1 else ""
                item_id = resolve_item_from_input(item_token, ctx.player, balance)
                if item_id is None:
                    print("Unknown item — use slot #, item id, or name from your inventory.")
                    continue
                result = use_item(ctx, item_id)
                if not result.success:
                    print(result.reason)
                else:
                    item = balance.items.get(item_id)
                    print(f"Used {item.name if item else item_id}.")
                outcome = check_outcome(ctx)
                if outcome != CombatOutcome.ONGOING:
                    return CombatResult(outcome=outcome, turns=ctx.turn)
                continue
            if not raw_lower.isdigit():
                print("Enter hand index, 'i <slot|id|name>', 'e', or 'q'.")
                continue

            hand_index = int(raw_lower)
            result = play_card(ctx, hand_index)
            if not result.success:
                print(result.reason)
                continue
            print(f"Played {balance.cards[result.card_id].name}.")

            outcome = check_outcome(ctx)
            if outcome != CombatOutcome.ONGOING:
                return CombatResult(outcome=outcome, turns=ctx.turn)

        end_player_turn(ctx)
        before_hp = ctx.player.hp
        outcome = _print_enemy_turn(ctx, before_hp)
        if outcome != CombatOutcome.ONGOING:
            return CombatResult(outcome=outcome, turns=ctx.turn)


def confirm_continue() -> bool:
    raw = input("\nContinue? [Y/n]: ").strip().lower()
    return raw in {"", "y", "yes"}
