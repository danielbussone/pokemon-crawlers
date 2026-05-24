"""Deck draw, discard, shuffle, and evolution."""

from __future__ import annotations

import random

from pokemon_crawlers.models import GameBalance, PlayerState
from pokemon_crawlers.registry import get_balance


def build_player_deck(starter_id: str, balance: GameBalance | None = None) -> list[str]:
    balance = balance or get_balance()
    starter = balance.starters[starter_id]
    deck = list(starter.deck)
    random.shuffle(deck)
    return deck


def draw_cards(player: PlayerState, count: int, hand_size: int) -> int:
    drawn = 0
    for _ in range(count):
        if len(player.hand) >= hand_size:
            break
        if not player.deck and player.discard:
            shuffle_discard_into_deck(player)
        if not player.deck:
            break
        card_id = player.deck.pop(0)
        player.hand.append(card_id)
        drawn += 1
    return drawn


def draw_to_hand(player: PlayerState, balance: GameBalance) -> int:
    needed = balance.constants.hand_size - len(player.hand)
    if needed <= 0:
        return 0
    return draw_cards(player, needed, balance.constants.hand_size)


def discard_hand(player: PlayerState) -> None:
    if player.hand:
        player.discard.extend(player.hand)
        player.hand.clear()


def play_card_from_hand(player: PlayerState, hand_index: int) -> str:
    card_id = player.hand.pop(hand_index)
    player.discard.append(card_id)
    return card_id


def shuffle_discard_into_deck(player: PlayerState) -> None:
    if not player.discard:
        return
    random.shuffle(player.discard)
    player.deck.extend(player.discard)
    player.discard.clear()


def add_card_to_deck(player: PlayerState, card_id: str) -> None:
    player.deck.append(card_id)


def apply_evolution(player: PlayerState, from_card_id: str, to_card_id: str) -> bool:
    """Replace all instances of from_card_id with to_card_id across deck zones."""
    replaced = False
    for pile in (player.deck, player.hand, player.discard):
        for index, card_id in enumerate(pile):
            if card_id == from_card_id:
                pile[index] = to_card_id
                replaced = True
    return replaced
