"""Data models for balance JSON and combat state."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum


class CardType(StrEnum):
    ATTACK = "attack"
    SUPPORT = "support"
    STATUS = "status"


class PokemonType(StrEnum):
    NORMAL = "NORMAL"
    FIRE = "FIRE"
    WATER = "WATER"
    GRASS = "GRASS"
    ROCK = "ROCK"
    POISON = "POISON"
    ELECTRIC = "ELECTRIC"
    PSYCHIC = "PSYCHIC"
    FIGHTING = "FIGHTING"
    GROUND = "GROUND"
    FLYING = "FLYING"
    BUG = "BUG"


class EffectType(StrEnum):
    DAMAGE = "damage"
    BLOCK = "block"
    HEAL = "heal"
    STATUS = "status"
    DRAW = "draw"
    APPLY_CONDITION = "apply_condition"


class StatusType(StrEnum):
    SLEEP = "sleep"
    PARALYZE = "paralyze"
    CONFUSE = "confuse"
    POISON = "poison"


class ConditionId(StrEnum):
    INTIMIDATED = "intimidated"
    DISTRACTED = "distracted"
    BLINDED = "blinded"
    DEFENSELESS = "defenseless"
    SLOW = "slow"


class Rarity(StrEnum):
    STARTER = "starter"
    COMMON = "common"
    UNCOMMON = "uncommon"
    RARE = "rare"
    SIGNATURE = "signature"


class EffectTarget(StrEnum):
    SELF = "self"
    ENEMY = "enemy"


@dataclass(frozen=True)
class Effect:
    type: EffectType
    magnitude: int = 0
    target: EffectTarget = EffectTarget.ENEMY
    status: StatusType | None = None
    status_duration: int | None = None
    status_magnitude: int | None = None
    condition: ConditionId | None = None
    condition_duration: int | None = None
    ignore_block: bool = False


@dataclass(frozen=True)
class Card:
    id: str
    name: str
    pokemon: str
    card_type: CardType
    pokemon_type: PokemonType
    cost: int
    power: int
    effects: tuple[Effect, ...]
    rarity: Rarity
    evolves_to: str | None = None
    self_evolve: bool = False
    tier: int = 1


@dataclass(frozen=True)
class ConditionDefinition:
    id: ConditionId
    outgoing_damage_mult: float | None = None
    incoming_damage_mult: float | None = None
    blocks_block_gain: bool = False
    default_duration: int | None = None
    initial_budget: int | None = None
    reapply_budget_add: int | None = None
    reapply_budget_cap: int | None = None
    miss_on_even_budget: bool = False
    non_attacks_decrement: bool = False
    on_player_stamina_delta: int | None = None
    on_enemy_grant_player_stamina_next_turn: int | None = None
    allow_stamina_overflow: bool = False


@dataclass(frozen=True)
class EnemyAction:
    id: str
    name: str
    is_attack: bool
    effects: tuple[Effect, ...]
    base_weight: int = 1
    preferred_phase: str | None = None  # healthy | mid | desperate | any


@dataclass(frozen=True)
class EnemyDefinition:
    id: str
    name: str
    pokemon_type: PokemonType
    max_hp: int
    is_wild: bool
    is_boss: bool
    action_pool: tuple[EnemyAction, ...]
    boss_pattern: tuple[str, ...] = ()  # action ids in order; loops from boss_pattern_loop_start
    boss_pattern_loop_start: int = 0  # 0-based index
    xp_reward: int = 0


@dataclass(frozen=True)
class StarterDefinition:
    id: str
    name: str
    deck: tuple[str, ...]


@dataclass(frozen=True)
class BadgeDefinition:
    id: str
    name: str
    outgoing_damage_mult: float = 1.0


@dataclass(frozen=True)
class Constants:
    player_max_hp: int
    player_max_stamina: int
    hand_size: int
    confuse_self_dmg: int
    min_damage: int
    draft_options: int


@dataclass(frozen=True)
class EvolutionConfig:
    from_card: str
    to_card: str
    after_encounter: int


@dataclass(frozen=True)
class RunConfig:
    encounter_sequence: tuple[str, ...]
    reward_pool: tuple[str, ...]
    evolution: EvolutionConfig
    signature_card: str
    badge_id: str


@dataclass(frozen=True)
class GameBalance:
    constants: Constants
    conditions: dict[ConditionId, ConditionDefinition]
    type_chart: dict[tuple[PokemonType, PokemonType], float]
    cards: dict[str, Card]
    enemies: dict[str, EnemyDefinition]
    starters: dict[str, StarterDefinition]
    badges: dict[str, BadgeDefinition]
    run_config: RunConfig


# --- Runtime combat state (mutable) ---


@dataclass
class ActiveStatus:
    type: StatusType
    turns_remaining: int
    magnitude: int = 0


@dataclass
class ActiveCondition:
    condition_id: ConditionId
    turns_remaining: int


@dataclass
class Combatant:
    hp: int
    max_hp: int
    pokemon_type: PokemonType
    block: int = 0
    statuses: list[ActiveStatus] | None = None
    conditions: list[ActiveCondition] | None = None
    blinded_budget: int | None = None

    def __post_init__(self) -> None:
        if self.statuses is None:
            self.statuses = []
        if self.conditions is None:
            self.conditions = []


@dataclass
class PlayerState(Combatant):
    base_max_stamina: int = 3
    max_stamina: int = 3
    current_stamina: int = 3
    stamina_bonus_next_turn: int = 0
    deck: list[str] | None = None
    hand: list[str] | None = None
    discard: list[str] | None = None
    badge_ids: list[str] | None = None

    def __post_init__(self) -> None:
        super().__post_init__()
        if self.deck is None:
            self.deck = []
        if self.hand is None:
            self.hand = []
        if self.discard is None:
            self.discard = []
        if self.badge_ids is None:
            self.badge_ids = []


@dataclass
class EnemyState(Combatant):
    enemy_id: str = ""
    is_boss: bool = False
    is_wild: bool = True
