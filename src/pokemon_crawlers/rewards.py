"""Post-combat rewards: draft picks, evolution, badge, signature card."""

from __future__ import annotations

import random

from pokemon_crawlers.deck import add_card_to_deck, apply_evolution
from pokemon_crawlers.models import GameBalance, PlayerState
from pokemon_crawlers.registry import get_balance

# Starter signature attacks offered outside the stage pool (see starter_stab_draft_chance).
STARTER_STAB_CARD_BY_STARTER: dict[str, str] = {
    "bulbasaur": "vine_whip",
    "squirtle": "water_gun",
    "charmander": "ember",
}


def starter_stab_card_id(starter_id: str) -> str | None:
    return STARTER_STAB_CARD_BY_STARTER.get(starter_id)


def generate_draft_options(
    balance: GameBalance | None = None,
    *,
    reward_pool: tuple[str, ...] | None = None,
    rng: random.Random | None = None,
    exclude: set[str] | None = None,
    starter_id: str | None = None,
) -> list[str]:
    """Sample unique cards from the run reward pool for a draft.

    When ``starter_id`` is set, each draft has ``starter_stab_draft_chance`` to
    include that starter's signature attack (vine_whip / water_gun / ember) as
    one option, even if it is not in the stage pool.
    """
    balance = balance or get_balance()
    rng = rng or random.Random()
    pool = list(reward_pool if reward_pool is not None else balance.run_config.reward_pool)
    if exclude:
        pool = [card_id for card_id in pool if card_id not in exclude]
    count = min(balance.constants.draft_options, len(pool))
    if count == 0:
        return []

    stab_card = starter_stab_card_id(starter_id or "")
    inject_stab = (
        stab_card is not None
        and stab_card in balance.cards
        and rng.random() < balance.constants.starter_stab_draft_chance
    )

    if inject_stab:
        filler_pool = [card_id for card_id in pool if card_id != stab_card]
        need = count - 1
        if need <= 0:
            return [stab_card]
        if need <= len(filler_pool):
            options = rng.sample(filler_pool, need) + [stab_card]
            rng.shuffle(options)
            return options

    return rng.sample(pool, count)


def apply_draft_pick(player: PlayerState, card_id: str) -> None:
    add_card_to_deck(player, card_id)


def apply_evolution_catalyst(player: PlayerState, balance: GameBalance | None = None) -> bool:
    """Replace evolution.from with evolution.to across all deck zones."""
    balance = balance or get_balance()
    evolution = balance.run_config.evolution
    return apply_evolution(player, evolution.from_card, evolution.to_card)


def grant_boss_rewards(player: PlayerState, balance: GameBalance | None = None) -> None:
    """Grant Boulder Badge placeholder and Brock signature card after boss win."""
    balance = balance or get_balance()
    config = balance.run_config
    if config.badge_id not in player.badge_ids:
        player.badge_ids.append(config.badge_id)
    add_card_to_deck(player, config.signature_card)
