"""JSON run logs for playtest analysis."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


@dataclass
class EncounterRecord:
    index: int
    enemy_id: str
    outcome: str
    turns: int
    player_hp_before: int
    player_hp_after: int
    stage_id: str | None = None
    gold_earned: int = 0


@dataclass
class RunLog:
    run_id: str
    starter_id: str
    started_at: str
    outcome: str
    run_mode: str = "kanto"
    encounters: list[EncounterRecord] = field(default_factory=list)
    draft_picks: list[str] = field(default_factory=list)
    evolution_applied: bool = False
    badge_earned: bool = False
    final_deck: list[str] = field(default_factory=list)
    final_hp: int = 0
    gold_earned: int = 0
    gold_spent: int = 0
    center_visits: int = 0
    items_purchased: list[str] = field(default_factory=list)
    items_used_in_combat: list[str] = field(default_factory=list)
    max_hp_final: int = 0
    stage_reached: str = ""
    mid_boss_variant: str | None = None
    shop_strategy: str | None = None
    play_style: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    def add_encounter(self, record: EncounterRecord) -> None:
        self.encounters.append(record)

    def finish(
        self,
        outcome: str,
        *,
        final_deck: list[str],
        final_hp: int,
        evolution_applied: bool,
        badge_earned: bool,
        max_hp_final: int | None = None,
        stage_reached: str = "",
    ) -> None:
        self.outcome = outcome
        self.final_deck = list(final_deck)
        self.final_hp = final_hp
        self.evolution_applied = evolution_applied
        self.badge_earned = badge_earned
        self.max_hp_final = max_hp_final if max_hp_final is not None else final_hp
        self.stage_reached = stage_reached

    def record_gold_spent(self, amount: int) -> None:
        self.gold_spent += amount

    def record_gold_earned(self, amount: int) -> None:
        self.gold_earned += amount


def new_run_log(
    starter_id: str,
    *,
    run_id_suffix: str = "",
    run_mode: str = "kanto",
    shop_strategy: str | None = None,
    play_style: str | None = None,
) -> RunLog:
    now = datetime.now(timezone.utc)
    run_id = now.strftime("%Y%m%d_%H%M%S") + run_id_suffix
    return RunLog(
        run_id=run_id,
        starter_id=starter_id,
        started_at=now.isoformat(),
        outcome="in_progress",
        run_mode=run_mode,
        shop_strategy=shop_strategy,
        play_style=play_style,
    )


def save_run_log(run_log: RunLog, runs_dir: Path) -> Path:
    runs_dir.mkdir(parents=True, exist_ok=True)
    path = runs_dir / f"run_{run_log.run_id}.json"
    with path.open("w", encoding="utf-8") as handle:
        json.dump(run_log.to_dict(), handle, indent=2)
        handle.write("\n")
    return path
