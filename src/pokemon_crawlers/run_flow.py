"""Kanto opening arc and Pewter City encounter chain orchestration."""

from __future__ import annotations

import random
from collections.abc import Callable
from pathlib import Path

from pokemon_crawlers.cli import (
    prompt_draft,
    prompt_shop,
    prompt_starter,
    run_interactive_combat,
)
from pokemon_crawlers.combat import CombatOutcome, run_combat
from pokemon_crawlers.deck import build_player_deck, discard_hand
from pokemon_crawlers.logger import EncounterRecord, RunLog, new_run_log, save_run_log
from pokemon_crawlers.models import GameBalance, PlayerState, PokemonType, StageDefinition
from pokemon_crawlers.registry import set_balance
from pokemon_crawlers.rewards import (
    apply_draft_pick,
    apply_evolution_catalyst,
    generate_draft_options,
    grant_boss_rewards,
)
from pokemon_crawlers.shop import apply_economy_shim_heal, purchase_center


def create_player(starter_id: str, balance: GameBalance) -> PlayerState:
    starter = balance.starters[starter_id]
    return PlayerState(
        hp=balance.constants.player_max_hp,
        max_hp=balance.constants.player_max_hp,
        pokemon_type=_starter_pokemon_type(starter_id),
        base_max_stamina=balance.constants.player_max_stamina,
        max_stamina=balance.constants.player_max_stamina,
        current_stamina=balance.constants.player_max_stamina,
        deck=build_player_deck(starter_id, balance),
    )


def _starter_pokemon_type(starter_id: str) -> PokemonType:
    mapping = {
        "bulbasaur": PokemonType.GRASS,
        "squirtle": PokemonType.WATER,
        "charmander": PokemonType.FIRE,
    }
    return mapping.get(starter_id, PokemonType.NORMAL)


def prepare_between_encounters(player: PlayerState) -> None:
    """HP persists; combat state clears between fights."""
    player.block = 0
    player.statuses.clear()
    player.conditions.clear()
    player.blinded_budget = None
    player.stamina_bonus_next_turn = 0
    player.max_stamina = player.base_max_stamina
    player.current_stamina = player.max_stamina
    if player.hand:
        discard_hand(player)


def collect_deck_snapshot(player: PlayerState) -> list[str]:
    return list(player.deck) + list(player.hand) + list(player.discard)


def _grant_wild_gold(player: PlayerState, balance: GameBalance, rng: random.Random) -> int:
    econ = balance.economy
    amount = rng.randint(econ.gold_wild_min, econ.gold_wild_max)
    player.gold += amount
    return amount


def _grant_mid_boss_gold(player: PlayerState, balance: GameBalance) -> int:
    amount = balance.economy.gold_mid_boss
    player.gold += amount
    return amount


def _resolve_mid_boss_id(
    stage: StageDefinition, rng: random.Random, starter_id: str
) -> str:
    from pokemon_crawlers.rivals import RIVAL_SENTINEL, resolve_rival_enemy_id

    if stage.mid_boss == RIVAL_SENTINEL:
        return resolve_rival_enemy_id(starter_id)
    if stage.mid_boss:
        return stage.mid_boss
    if stage.mid_boss_variants:
        return rng.choice(list(stage.mid_boss_variants))
    raise ValueError(f"Stage '{stage.id}' has no mid-boss configured")


def _reward_pool_for_stage(stage: StageDefinition, balance: GameBalance) -> tuple[str, ...]:
    return balance.stage_rewards[stage.reward_pool_key]


def _maybe_apply_evolution(
    player: PlayerState,
    balance: GameBalance,
    *,
    after_rival: bool,
    after_bug_catcher: bool,
    evolution_applied: bool,
) -> bool:
    if evolution_applied:
        return True
    trigger = balance.run_config.evolution_trigger
    should = False
    if trigger == "post_rival" and after_rival:
        should = True
    elif trigger == "post_bug_catcher" and after_bug_catcher:
        should = True
    if should and apply_evolution_catalyst(player, balance):
        return True
    return evolution_applied


def _run_encounter(
    player: PlayerState,
    enemy_id: str,
    balance: GameBalance,
    *,
    interactive: bool,
    use_heuristic_ai: bool,
    play_style: str = "balanced",
    choose_play: Callable | None = None,
    choose_item: Callable | None = None,
) -> tuple[object, str]:
    if interactive:
        return run_interactive_combat(player, enemy_id, balance), enemy_id

    if use_heuristic_ai:
        from pokemon_crawlers.player_ai import choose_item_use, choose_play_index

        play_fn = choose_play or (
            lambda ctx, _style=play_style: choose_play_index(ctx, play_style=_style)
        )

        return (
            run_combat(
                player,
                enemy_id,
                balance,
                choose_play=play_fn,
                choose_item=choose_item or choose_item_use,
            ),
            enemy_id,
        )

    return run_combat(player, enemy_id, balance), enemy_id


def _handle_shop_window(
    player: PlayerState,
    balance: GameBalance,
    run_log: RunLog,
    stage: StageDefinition,
    *,
    interactive: bool,
    shop_policy: str | None,
    rng: random.Random,
) -> None:
    if balance.run_config.economy_shim_heal:
        apply_economy_shim_heal(player)
        return

    if not balance.run_config.economy_enabled:
        return

    if interactive:
        spent, purchases, centers = prompt_shop(
            player, balance, shop_window=stage.shop_window
        )
        run_log.record_gold_spent(spent)
        run_log.center_visits += centers
        run_log.items_purchased.extend(purchases)
        return

    from pokemon_crawlers.player_ai import execute_shop_policy

    execute_shop_policy(
        player,
        balance,
        shop_window=stage.shop_window,
        next_stage_id=_next_stage_id(stage, balance),
        policy=shop_policy or "greedy",
        rng=rng,
        run_log=run_log,
    )


def _next_stage_id(stage: StageDefinition, balance: GameBalance) -> str | None:
    stages = balance.run_config.stages
    for index, entry in enumerate(stages):
        if entry.id == stage.id and index + 1 < len(stages):
            return stages[index + 1].id
    return "pewter"


def _run_stage(
    player: PlayerState,
    balance: GameBalance,
    stage: StageDefinition,
    run_log: RunLog,
    encounter_index: int,
    *,
    interactive: bool,
    use_heuristic_ai: bool,
    rng: random.Random,
    shop_policy: str | None,
    evolution_applied: bool,
    starter_id: str,
    play_style: str = "balanced",
    choose_play: Callable | None = None,
    choose_item: Callable | None = None,
) -> tuple[int, str, bool, str | None]:
    """Returns (next_encounter_index, final_outcome, evolution_applied, mid_boss_variant)."""
    mid_boss_variant: str | None = None
    reward_pool = _reward_pool_for_stage(stage, balance)

    for _ in range(stage.wild_count):
        enemy_id = rng.choice(list(stage.wild_pool))
        hp_before = player.hp
        prepare_between_encounters(player)

        result, _ = _run_encounter(
            player,
            enemy_id,
            balance,
            interactive=interactive,
            use_heuristic_ai=use_heuristic_ai,
            play_style=play_style,
            choose_play=choose_play,
            choose_item=choose_item,
        )

        gold = 0
        if result.outcome == CombatOutcome.PLAYER_WIN and balance.run_config.economy_enabled:
            gold = _grant_wild_gold(player, balance, rng)
            run_log.record_gold_earned(gold)

        prepare_between_encounters(player)
        run_log.add_encounter(
            EncounterRecord(
                index=encounter_index,
                enemy_id=enemy_id,
                outcome=result.outcome.value,
                turns=result.turns,
                player_hp_before=hp_before,
                player_hp_after=player.hp,
                stage_id=stage.id,
                gold_earned=gold,
            )
        )
        encounter_index += 1

        if result.outcome != CombatOutcome.PLAYER_WIN:
            return encounter_index, "run_loss", evolution_applied, mid_boss_variant

        options = generate_draft_options(
            balance,
            reward_pool=reward_pool,
            rng=rng,
            starter_id=starter_id,
        )
        pick = _resolve_draft(
            player,
            options,
            balance,
            interactive=interactive,
            use_heuristic_ai=use_heuristic_ai,
            play_style=play_style,
        )
        if pick:
            apply_draft_pick(player, pick)
            run_log.draft_picks.append(pick)

    mid_boss_id = _resolve_mid_boss_id(stage, rng, starter_id)
    mid_boss_variant = mid_boss_id if stage.mid_boss_variants else None
    hp_before = player.hp
    prepare_between_encounters(player)

    result, _ = _run_encounter(
        player,
        mid_boss_id,
        balance,
        interactive=interactive,
        use_heuristic_ai=use_heuristic_ai,
        play_style=play_style,
        choose_play=choose_play,
        choose_item=choose_item,
    )

    gold = 0
    if result.outcome == CombatOutcome.PLAYER_WIN and balance.run_config.economy_enabled:
        gold = _grant_mid_boss_gold(player, balance)
        run_log.record_gold_earned(gold)

    prepare_between_encounters(player)
    run_log.add_encounter(
        EncounterRecord(
            index=encounter_index,
            enemy_id=mid_boss_id,
            outcome=result.outcome.value,
            turns=result.turns,
            player_hp_before=hp_before,
            player_hp_after=player.hp,
            stage_id=stage.id,
            gold_earned=gold,
        )
    )
    encounter_index += 1

    if result.outcome != CombatOutcome.PLAYER_WIN:
        return encounter_index, "run_loss", evolution_applied, mid_boss_variant

    evolution_applied = _maybe_apply_evolution(
        player,
        balance,
        after_rival=stage.id == "route_viridian",
        after_bug_catcher=stage.id == "viridian_forest",
        evolution_applied=evolution_applied,
    )

    if stage.shop_after:
        _handle_shop_window(
            player,
            balance,
            run_log,
            stage,
            interactive=interactive,
            shop_policy=shop_policy,
            rng=rng,
        )

    return encounter_index, "ongoing", evolution_applied, mid_boss_variant


def _resolve_draft(
    player: PlayerState,
    options: list[str],
    balance: GameBalance,
    *,
    interactive: bool,
    use_heuristic_ai: bool,
    play_style: str = "balanced",
) -> str | None:
    if not options:
        return None
    if interactive:
        return prompt_draft(options, balance)
    if use_heuristic_ai:
        from pokemon_crawlers.player_ai import choose_draft_pick

        return choose_draft_pick(player, options, balance, play_style=play_style)
    return options[0]


def _run_pewter_sequence(
    player: PlayerState,
    balance: GameBalance,
    run_log: RunLog,
    encounter_index: int,
    *,
    interactive: bool,
    use_heuristic_ai: bool,
    rng: random.Random,
    evolution_applied: bool,
    quiet: bool,
    starter_id: str,
    play_style: str = "balanced",
    choose_play: Callable | None = None,
    choose_item: Callable | None = None,
) -> tuple[str, bool]:
    sequence = balance.run_config.pewter_encounter_sequence
    reward_pool = balance.stage_rewards.get("stage3", balance.run_config.reward_pool)
    encounters_won = 0

    for enemy_id in sequence:
        enemy_def = balance.enemies[enemy_id]
        hp_before = player.hp
        prepare_between_encounters(player)

        result, _ = _run_encounter(
            player,
            enemy_id,
            balance,
            interactive=interactive,
            use_heuristic_ai=use_heuristic_ai,
            play_style=play_style,
            choose_play=choose_play,
            choose_item=choose_item,
        )

        prepare_between_encounters(player)
        run_log.add_encounter(
            EncounterRecord(
                index=encounter_index,
                enemy_id=enemy_id,
                outcome=result.outcome.value,
                turns=result.turns,
                player_hp_before=hp_before,
                player_hp_after=player.hp,
                stage_id="pewter",
            )
        )
        encounter_index += 1

        if result.outcome != CombatOutcome.PLAYER_WIN:
            return "run_loss", evolution_applied

        encounters_won += 1
        if not quiet:
            print(f"Victory vs {enemy_def.name}! HP: {player.hp}/{player.max_hp}")

        if enemy_def.is_boss:
            grant_boss_rewards(player, balance)
            run_log.badge_earned = True
            if not quiet:
                print(
                    f"Boulder Badge earned! Added "
                    f"{balance.cards[balance.run_config.signature_card].name}."
                )
            return "run_complete", evolution_applied

        options = generate_draft_options(
            balance,
            reward_pool=reward_pool,
            rng=rng,
            starter_id=starter_id,
        )
        pick = _resolve_draft(
            player,
            options,
            balance,
            interactive=interactive,
            use_heuristic_ai=use_heuristic_ai,
            play_style=play_style,
        )
        if pick:
            apply_draft_pick(player, pick)
            run_log.draft_picks.append(pick)

        if (
            not evolution_applied
            and encounters_won == balance.run_config.evolution.after_encounter
        ):
            if apply_evolution_catalyst(player, balance):
                evolution_applied = True

    return "run_complete", evolution_applied


def run_kanto_chain(
    balance: GameBalance,
    *,
    interactive: bool = True,
    starter_id: str | None = None,
    runs_dir: Path | None = None,
    use_heuristic_ai: bool = False,
    quiet: bool = False,
    run_id_suffix: str = "",
    shop_policy: str | None = None,
    play_style: str = "balanced",
    rng: random.Random | None = None,
) -> tuple[RunLog, str]:
    """Run Route/Viridian → Viridian Forest → Pewter."""
    chosen_starter = starter_id or (prompt_starter(balance) if interactive else "squirtle")
    player = create_player(chosen_starter, balance)
    run_log = new_run_log(
        chosen_starter,
        run_id_suffix=run_id_suffix,
        run_mode="kanto",
        shop_strategy=shop_policy,
        play_style=play_style,
    )
    rng = rng or random.Random()
    evolution_applied = False
    encounter_index = 0
    final_outcome = "run_loss"
    stage_reached = ""
    mid_boss_variant: str | None = None

    for stage in balance.run_config.stages:
        stage_reached = stage.id
        encounter_index, outcome, evolution_applied, variant = _run_stage(
            player,
            balance,
            stage,
            run_log,
            encounter_index,
            interactive=interactive,
            use_heuristic_ai=use_heuristic_ai,
            rng=rng,
            shop_policy=shop_policy,
            evolution_applied=evolution_applied,
            starter_id=chosen_starter,
            play_style=play_style,
        )
        if variant:
            mid_boss_variant = variant
        if outcome != "ongoing":
            final_outcome = outcome
            run_log.mid_boss_variant = mid_boss_variant
            run_log.finish(
                final_outcome,
                final_deck=collect_deck_snapshot(player),
                final_hp=player.hp,
                evolution_applied=evolution_applied,
                badge_earned=run_log.badge_earned,
                max_hp_final=player.max_hp,
                stage_reached=stage_reached,
            )
            if runs_dir is not None:
                path = save_run_log(run_log, runs_dir)
                if not quiet:
                    print(f"\nRun log saved: {path}")
            return run_log, final_outcome

    stage_reached = "pewter"
    final_outcome, evolution_applied = _run_pewter_sequence(
        player,
        balance,
        run_log,
        encounter_index,
        interactive=interactive,
        use_heuristic_ai=use_heuristic_ai,
        rng=rng,
        evolution_applied=evolution_applied,
        quiet=quiet,
        starter_id=chosen_starter,
        play_style=play_style,
    )

    run_log.mid_boss_variant = mid_boss_variant
    run_log.center_visits = player.center_visits
    run_log.finish(
        final_outcome,
        final_deck=collect_deck_snapshot(player),
        final_hp=player.hp,
        evolution_applied=evolution_applied,
        badge_earned=run_log.badge_earned,
        max_hp_final=player.max_hp,
        stage_reached=stage_reached,
    )

    if runs_dir is not None:
        path = save_run_log(run_log, runs_dir)
        if not quiet:
            print(f"\nRun log saved: {path}")

    return run_log, final_outcome


def run_pewter_chain(
    balance: GameBalance,
    *,
    interactive: bool = True,
    starter_id: str | None = None,
    runs_dir: Path | None = None,
    use_heuristic_ai: bool = False,
    quiet: bool = False,
    run_id_suffix: str = "",
    shop_policy: str | None = None,
    play_style: str = "balanced",
    rng: random.Random | None = None,
) -> tuple[RunLog, str]:
    """Legacy Pewter-only chain (5 encounters)."""
    chosen_starter = starter_id or (prompt_starter(balance) if interactive else "squirtle")
    player = create_player(chosen_starter, balance)
    run_log = new_run_log(
        chosen_starter,
        run_id_suffix=run_id_suffix,
        run_mode="pewter",
        shop_strategy=shop_policy,
        play_style=play_style,
    )
    rng = rng or random.Random()
    evolution_applied = False

    final_outcome, evolution_applied = _run_pewter_sequence(
        player,
        balance,
        run_log,
        0,
        interactive=interactive,
        use_heuristic_ai=use_heuristic_ai,
        rng=rng,
        evolution_applied=evolution_applied,
        quiet=quiet,
        starter_id=chosen_starter,
        play_style=play_style,
    )

    run_log.finish(
        final_outcome,
        final_deck=collect_deck_snapshot(player),
        final_hp=player.hp,
        evolution_applied=evolution_applied,
        badge_earned=run_log.badge_earned,
        max_hp_final=player.max_hp,
        stage_reached="pewter",
    )

    if runs_dir is not None:
        path = save_run_log(run_log, runs_dir)
        if not quiet:
            print(f"\nRun log saved: {path}")

    return run_log, final_outcome


def run_kanto_from_balance_dir(
    balance_dir: Path,
    *,
    interactive: bool = True,
    starter_id: str | None = None,
    runs_dir: Path | None = None,
    pewter_only: bool = False,
    **kwargs: object,
) -> tuple[RunLog, str]:
    from pokemon_crawlers.loader import load_balance

    balance = load_balance(balance_dir)
    set_balance(balance)
    if pewter_only:
        return run_pewter_chain(
            balance,
            interactive=interactive,
            starter_id=starter_id,
            runs_dir=runs_dir,
            **kwargs,  # type: ignore[arg-type]
        )
    return run_kanto_chain(
        balance,
        interactive=interactive,
        starter_id=starter_id,
        runs_dir=runs_dir,
        **kwargs,  # type: ignore[arg-type]
    )


def run_pewter_from_balance_dir(
    balance_dir: Path,
    *,
    interactive: bool = True,
    starter_id: str | None = None,
    runs_dir: Path | None = None,
) -> tuple[RunLog, str]:
    return run_kanto_from_balance_dir(
        balance_dir,
        interactive=interactive,
        starter_id=starter_id,
        runs_dir=runs_dir,
        pewter_only=True,
    )
