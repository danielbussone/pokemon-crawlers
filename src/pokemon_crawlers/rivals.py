"""Stage 1 Rival selection — counter-type starter vs player."""

from __future__ import annotations

# run_config uses mid_boss: "rival_blue" as sentinel for dynamic pick
RIVAL_SENTINEL = "rival_blue"

RIVAL_ENEMY_IDS = frozenset(
    {
        RIVAL_SENTINEL,
        "rival_squirtle",
        "rival_bulbasaur",
        "rival_charmander",
    }
)

# Player starter -> Rival with type advantage (1.5× vs player)
COUNTER_RIVAL_BY_STARTER: dict[str, str] = {
    "charmander": "rival_squirtle",
    "squirtle": "rival_bulbasaur",
    "bulbasaur": "rival_charmander",
}


def resolve_rival_enemy_id(starter_id: str) -> str:
    return COUNTER_RIVAL_BY_STARTER.get(starter_id, "rival_squirtle")


def is_rival_enemy(enemy_id: str) -> bool:
    return enemy_id in RIVAL_ENEMY_IDS or enemy_id.startswith("rival_")
