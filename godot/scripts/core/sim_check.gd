class_name SimCheck
## Headless smoke test: plays full runs with the legacy greedy policy
## (first playable card, first draft option, Center when unlocked).
## Run with:  godot --headless --path . -- --simcheck
## Validates the GDScript engine port end-to-end without a display.


static func run_batch(runs: int, run_mgr, bal) -> void:
	var starters := ["bulbasaur", "squirtle", "charmander"]
	var wins := 0
	var loss_by_enemy := {}
	var wins_by_starter := {"bulbasaur": 0, "squirtle": 0, "charmander": 0}

	for i in runs:
		var starter: String = starters[i % starters.size()]
		run_mgr.start_run(starter)
		var result := _play_run(run_mgr, bal)
		if result == "win":
			wins += 1
			wins_by_starter[starter] = int(wins_by_starter[starter]) + 1
		else:
			loss_by_enemy[result] = int(loss_by_enemy.get(result, 0)) + 1

	print("SimCheck: %d runs — %d wins (%.1f%%)" % [runs, wins, 100.0 * wins / runs])
	print("  Wins by starter: ", wins_by_starter)
	print("  Losses by enemy: ", loss_by_enemy)


static func _play_run(run_mgr, bal) -> String:
	while not run_mgr.run_over:
		var ctx: CombatCtx = run_mgr.begin_combat()
		var outcome := _play_combat(ctx)
		if outcome != CombatCtx.WIN:
			run_mgr.after_loss()
			return ctx.enemy.enemy_id

		var result: Dictionary = run_mgr.after_win()
		var options: Array = result["draft_options"]
		if not options.is_empty():
			Rewards.apply_draft_pick(run_mgr.player, String(options[0]))
		if int(result["shop_window"]) > 0:
			ShopOps.purchase_center(run_mgr.player, bal)
		if bool(result["run_complete"]):
			return "win"
	return "win"


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
