class_name SimCheck
## Headless smoke test: plays full runs with the legacy greedy combat policy
## (first playable card, first draft option, Center when unlocked), now routed
## through a maze pathfinder that walks the real stage grid toward each gate and
## engages optional wilds at a configurable rate.
## Run with:  godot --headless --path . -- --simcheck [--engage=0.6]
## Validates the GDScript engine port end-to-end without a display.

const WG = preload("res://scripts/world/world_grid.gd")
const RareCandyOps = preload("res://scripts/core/rare_candy_ops.gd")
const StageLayout = preload("res://scripts/world/stage_layout.gd")

## Fraction of reachable optional wilds the sim chooses to fight per stage.
const DEFAULT_ENGAGEMENT := 0.6


static func run_batch(runs: int, run_mgr, bal, engagement_rate: float = DEFAULT_ENGAGEMENT,
		spend_candy: bool = false) -> void:
	var starters := ["bulbasaur", "squirtle", "charmander"]
	var wins := 0
	var loss_by_enemy := {}
	var wins_by_starter := {"bulbasaur": 0, "squirtle": 0, "charmander": 0}
	var total_engaged := 0
	var total_steps := 0
	var total_candy_spent := 0
	var total_heals := 0

	for i in runs:
		var starter: String = starters[i % starters.size()]
		run_mgr.start_run(starter)
		var maze := _build_maze(run_mgr)
		var stats := {"engaged": 0, "steps": 0, "candy_spent": 0, "heals": 0}
		var result := _play_run(run_mgr, bal, maze, engagement_rate, run_mgr.rng, stats, spend_candy)
		total_engaged += int(stats["engaged"])
		total_steps += int(stats["steps"])
		total_candy_spent += int(stats["candy_spent"])
		total_heals += int(stats["heals"])
		if result == "win":
			wins += 1
			wins_by_starter[starter] = int(wins_by_starter[starter]) + 1
		else:
			loss_by_enemy[result] = int(loss_by_enemy.get(result, 0)) + 1

	var policy := "SPEND candy" if spend_candy else "HOARD candy"
	print("SimCheck [%s]: %d runs — %d wins (%.1f%%) — engage_rate %.2f" % [
			policy, runs, wins, 100.0 * wins / runs, engagement_rate])
	print("  Wins by starter: ", wins_by_starter)
	print("  Losses by enemy: ", loss_by_enemy)
	print("  Avg optionals engaged: %.1f, avg maze steps: %.1f, avg candy spent: %.2f, avg Center heals: %.2f" % [
			float(total_engaged) / runs, float(total_steps) / runs,
			float(total_candy_spent) / runs, float(total_heals) / runs])


## Builds the stage grid + encounter cell positions for pathfinding, with no
## 3D geometry (WorldMapBuilder.build_grid_only is data-only).
static func _build_maze(run_mgr) -> Dictionary:
	var builder := WorldMapBuilder.new()
	builder.build_grid_only(run_mgr.encounters)
	var grid = builder.grid
	var spawn: Vector2i = builder.spawn_cell
	var cells: Array[Vector2i] = []
	for i in run_mgr.encounters.size():
		cells.append(builder.encounter_cell(i))
	builder.free()
	return {"grid": grid, "cells": cells, "pos": spawn}


## Greedy maze traversal: for each mandatory gate (in order), optionally detour
## through the stage's wild tiles (nearest first, engaged at engagement_rate),
## then walk to and clear the gate. Path lengths use BFS on the real grid.
static func _play_run(run_mgr, bal, maze: Dictionary, engagement_rate: float,
		rng, stats: Dictionary, spend_candy: bool = false) -> String:
	var grid = maze["grid"]
	var cells: Array = maze["cells"]
	var pos: Vector2i = maze["pos"]

	while not run_mgr.run_over:
		var gate_idx := _next_gate(run_mgr)
		if gate_idx < 0:
			break
		var gate_stage := String(run_mgr.encounters[gate_idx]["stage_id"])

		var opt_indices := _stage_optionals(run_mgr, gate_stage)
		var dist_of := {}
		for oi in opt_indices:
			dist_of[oi] = _dist(grid, pos, cells[oi])
		opt_indices.sort_custom(func(a, b): return int(dist_of[a]) < int(dist_of[b]))

		for oi in opt_indices:
			if rng.randf() > engagement_rate:
				continue
			pos = _walk_to(grid, pos, cells[oi], stats)
			var res := _fight(run_mgr, bal, oi, spend_candy, stats)
			if res != "":
				return res
			stats["engaged"] = int(stats["engaged"]) + 1
			if run_mgr.run_over:
				return "win" if run_mgr.run_won else res

		pos = _walk_to(grid, pos, cells[gate_idx], stats)
		var gres := _fight(run_mgr, bal, gate_idx, spend_candy, stats)
		if gres != "":
			return gres
		if run_mgr.run_over:
			return "win" if run_mgr.run_won else gres

	return "win"


static func _next_gate(run_mgr) -> int:
	for i in run_mgr.encounters.size():
		var enc: Dictionary = run_mgr.encounters[i]
		if bool(enc.get("is_mandatory", false)) and run_mgr.can_trigger_encounter(i):
			return i
	return -1


static func _stage_optionals(run_mgr, stage_id: String) -> Array[int]:
	var out: Array[int] = []
	for i in run_mgr.encounters.size():
		var enc: Dictionary = run_mgr.encounters[i]
		if bool(enc.get("is_optional", false)) and not run_mgr.is_optional_cleared(i) \
				and String(enc["stage_id"]) == stage_id:
			out.append(i)
	return out


static func _walk_to(grid, from_cell: Vector2i, to_cell: Vector2i, stats: Dictionary) -> Vector2i:
	var d := _dist(grid, from_cell, to_cell)
	if d > 0:
		stats["steps"] = int(stats["steps"]) + d
	return to_cell


static func _fight(run_mgr, bal, idx: int, spend_candy: bool = false,
		stats: Dictionary = {}) -> String:
	# Model a real player topping up at the city Poké Center before any mandatory
	# boss fight (rival/trainer/gym) when the stage has an unlocked Center.
	var enc: Dictionary = run_mgr.encounters[idx]
	if bool(enc.get("is_mandatory", false)):
		_heal_at_city_center(run_mgr, bal, String(enc["stage_id"]), stats)

	var ctx: CombatCtx = run_mgr.begin_combat_at(idx)
	var outcome := _play_combat(ctx)
	# Trainer battle: fight each Pokemon in the team before the encounter resolves.
	while outcome == CombatCtx.WIN and run_mgr.has_next_bout():
		ctx = run_mgr.begin_next_bout()
		outcome = _play_combat(ctx)
	if outcome != CombatCtx.WIN:
		run_mgr.after_loss()
		return ctx.enemy.enemy_id
	var result: Dictionary = run_mgr.after_win()
	var options: Array = result["draft_options"]
	if not options.is_empty():
		Rewards.apply_draft_pick(run_mgr.player, String(options[0]))
	if spend_candy:
		_spend_candies(run_mgr.player, bal, stats)
	if int(result["shop_window"]) > 0:
		ShopOps.purchase_center(run_mgr.player, bal)
	return ""


## Heal at the current stage's Poké Center if it exists, the player is hurt, and
## they can afford it — the "stock up before the gym" a human does. Centers are
## never leader-gated (main.gd `_on_shop_entered`), so reaching one is enough.
static func _heal_at_city_center(run_mgr, bal, stage_id: String, stats: Dictionary) -> void:
	var player = run_mgr.player
	if player.hp >= player.max_hp:
		return
	var shops := StageLayout.shop_cells_local(bal, stage_id)
	if not shops.has("center"):
		return
	if ShopOps.purchase_center(player, bal) and not stats.is_empty():
		stats["heals"] = int(stats.get("heals", 0)) + 1


## SPEND policy: while a token and an eligible card exist, evolve the card whose
## evolution adds the most enemy-facing damage (greedy). Draft is applied first
## so a freshly-drafted evolvable card is a candidate this same fight.
static func _spend_candies(player, bal, stats: Dictionary) -> void:
	while RareCandyOps.has_spendable(player, bal):
		var best := ""
		var best_gain := -1
		for cid in RareCandyOps.evolvable_deck_cards(player, bal):
			var to_id := String(bal.cards[cid].get("evolves_to", ""))
			var gain := _card_damage(bal, to_id) - _card_damage(bal, cid)
			if gain > best_gain:
				best_gain = gain
				best = cid
		if best == "" or not RareCandyOps.spend(player, best, bal):
			break
		if not stats.is_empty():
			stats["candy_spent"] = int(stats.get("candy_spent", 0)) + 1


## Largest single enemy-facing damage magnitude on a card (self-target recoil
## ignored), used to rank evolution upgrades.
static func _card_damage(bal, card_id: String) -> int:
	var best := 0
	for eff in bal.cards.get(card_id, {}).get("effects", []):
		if String(eff.get("type", "")) == "damage" and String(eff.get("target", "enemy")) != "self":
			best = maxi(best, int(eff.get("magnitude", 0)))
	return best


## BFS shortest walkable-step distance between two cells (walls block; gate
## tiles are treated as passable since the route clears them as it advances).
## Returns -1 if unreachable.
static func _dist(grid, start: Vector2i, goal: Vector2i) -> int:
	if start == goal:
		return 0
	var frontier: Array[Vector2i] = [start]
	var seen := {start: true}
	var steps := 0
	while not frontier.is_empty():
		steps += 1
		var next_frontier: Array[Vector2i] = []
		for c in frontier:
			for f in 4:
				var n: Vector2i = c + WG.FACING_DIR[f]
				if seen.has(n) or not grid.tiles.has(n):
					continue
				if grid.kind_at(n) == WG.TileKind.WALL:
					continue
				if n == goal:
					return steps
				seen[n] = true
				next_frontier.append(n)
		frontier = next_frontier
	return -1


static func _play_combat(ctx: CombatCtx) -> String:
	var safety := 0
	while safety < 200:
		safety += 1
		var outcome := ctx.player_turn_begin()
		if outcome != CombatCtx.ONGOING:
			return outcome

		if not ctx.slept_this_turn:
			while ctx.player.current_stamina > 0 and not ctx.player.hand.is_empty():
				var index := -1
				for i in ctx.player.hand.size():
					if ctx.can_play_card(i)["ok"]:
						index = i
						break
				if index < 0:
					break
				ctx.play_card(index)
				if ctx.check_outcome() != CombatCtx.ONGOING:
					return ctx.check_outcome()

		ctx.end_player_turn()
		var turn_result := ctx.enemy_turn()
		if String(turn_result["outcome"]) != CombatCtx.ONGOING:
			return String(turn_result["outcome"])
	return CombatCtx.ONGOING
