"""Cached access to loaded balance data."""

from __future__ import annotations

from pathlib import Path

from pokemon_crawlers.loader import load_balance
from pokemon_crawlers.models import Card, EnemyDefinition, GameBalance, StarterDefinition

_DEFAULT_BALANCE_DIR = Path(__file__).resolve().parents[2] / "data" / "balance"
_cached: GameBalance | None = None
_cached_path: Path | None = None


def get_balance(balance_dir: Path | None = None) -> GameBalance:
    global _cached, _cached_path
    path = (balance_dir or _DEFAULT_BALANCE_DIR).resolve()
    if _cached is None or _cached_path != path:
        _cached = load_balance(path)
        _cached_path = path
    return _cached


def set_balance(balance: GameBalance, *, balance_dir: Path | None = None) -> None:
    """Install pre-loaded balance (e.g. after main loads a custom --balance-dir)."""
    global _cached, _cached_path
    _cached = balance
    _cached_path = (balance_dir or _DEFAULT_BALANCE_DIR).resolve()


def reset_cache() -> None:
    global _cached, _cached_path
    _cached = None
    _cached_path = None


def get_card(card_id: str, balance_dir: Path | None = None) -> Card:
    return get_balance(balance_dir).cards[card_id]


def get_enemy(enemy_id: str, balance_dir: Path | None = None) -> EnemyDefinition:
    return get_balance(balance_dir).enemies[enemy_id]


def get_starter(starter_id: str, balance_dir: Path | None = None) -> StarterDefinition:
    return get_balance(balance_dir).starters[starter_id]
