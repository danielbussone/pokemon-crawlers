extends Node
## Autoload "Run" — full Kanto arc orchestration (port of run_flow.py).
## Builds the 13-encounter chain at run start; the 3D world lays markers out from it.

var rng := RandomNumberGenerator.new()
var starter_id := ""
var trainer_appearance := "boy"
var player: PlayerState = null
var encounters: Array[Dictionary] = []
var encounter_index := 0
var evolution_applied := false
var unlocked_shop_window := 0  # 0 = none, 1 = after Rival, 2 = after Bug Catcher
var run_over := false
var run_won := false

const STARTER_TYPES := {
	"bulbasaur": "GRASS",
	"squirtle": "WATER",
	"charmander": "FIRE",
}


func _ready() -> void:
	rng.randomize()
	_setup_input()


func start_run(p_starter_id: String, p_appearance: String = "boy") -> void:
	starter_id = p_starter_id
	trainer_appearance = p_appearance
	evolution_applied = false
	encounter_index = 0
	unlocked_shop_window = 0
	run_over = false
	run_won = false

	player = PlayerState.new()
	player.hp = Balance.max_hp()
	player.max_hp = player.hp
	player.ptype = String(STARTER_TYPES.get(p_starter_id, "NORMAL"))
	player.base_max_stamina = Balance.max_stamina()
	player.max_stamina = player.base_max_stamina
	player.current_stamina = player.base_max_stamina
	player.deck = DeckOps.build_player_deck(p_starter_id, Balance, rng)

	_build_encounters()


func current_encounter() -> Dictionary:
	if encounter_index >= encounters.size():
		return {}
	return encounters[encounter_index]


func begin_combat() -> CombatCtx:
	prepare_between_encounters()
	return CombatCtx.start(player, String(current_encounter()["enemy_id"]), Balance, rng)


## Post-victory bookkeeping. Returns what happened so the UI can present it:
## {"gold": int, "draft_options": Array[String], "evolved": bool,
##  "shop_window": int, "run_complete": bool}
func after_win() -> Dictionary:
	var enc := current_encounter()
	var out := {
		"gold": 0,
		"draft_options": [] as Array[String],
		"evolved": false,
		"shop_window": 0,
		"run_complete": false,
	}
	prepare_between_encounters()

	var gold_cfg: Dictionary = Balance.economy["gold"]
	if String(enc["gold"]) == "wild":
		var amount := rng.randi_range(int(gold_cfg["wild_min"]), int(gold_cfg["wild_max"]))
		player.gold += amount
		out["gold"] = amount
	elif String(enc["gold"]) == "midboss":
		var amount := int(gold_cfg["mid_boss"])
		player.gold += amount
		out["gold"] = amount

	if bool(enc["draft_after"]):
		out["draft_options"] = Rewards.generate_draft_options(
				Balance, Balance.stage_rewards[enc["reward_pool_key"]], rng, starter_id)

	if bool(enc["evolution_after"]) and not evolution_applied:
		if Rewards.apply_evolution_catalyst(player, Balance):
			evolution_applied = true
			out["evolved"] = true

	if int(enc["shop_window_after"]) > 0:
		unlocked_shop_window = int(enc["shop_window_after"])
		out["shop_window"] = unlocked_shop_window

	if bool(enc["is_final_boss"]):
		Rewards.grant_boss_rewards(player, Balance)
		out["run_complete"] = true
		run_over = true
		run_won = true

	encounter_index += 1
	return out


func after_loss() -> void:
	run_over = true
	run_won = false


## HP persists; combat state clears between fights (port of prepare_between_encounters).
func prepare_between_encounters() -> void:
	player.block = 0
	player.statuses.clear()
	player.conditions.clear()
	player.blinded_budget = -1
	player.stamina_bonus_next_turn = 0
	player.max_stamina = player.base_max_stamina
	player.current_stamina = player.max_stamina
	DeckOps.discard_hand(player)


func deck_size() -> int:
	return player.deck.size() + player.hand.size() + player.discard.size()


func _build_encounters() -> void:
	encounters.clear()
	var trigger := String(Balance.run_config.get("evolution_trigger", "post_rival"))

	for stage in Balance.run_config["stages"]:
		var stage_id := String(stage["id"])
		for _i in int(stage["wild_count"]):
			var pool: Array = stage["wild_pool"]
			encounters.append({
				"kind": "wild",
				"enemy_id": String(pool[rng.randi_range(0, pool.size() - 1)]),
				"stage_id": stage_id,
				"reward_pool_key": String(stage["reward_pool_key"]),
				"draft_after": true,
				"gold": "wild",
				"shop_window_after": 0,
				"evolution_after": false,
				"is_final_boss": false,
			})

		var mid_boss_id := _resolve_mid_boss_id(stage)
		var evolution_after := (trigger == "post_rival" and stage_id == "route_viridian") \
				or (trigger == "post_bug_catcher" and stage_id == "viridian_forest")
		encounters.append({
			"kind": "midboss",
			"enemy_id": mid_boss_id,
			"stage_id": stage_id,
			"reward_pool_key": String(stage["reward_pool_key"]),
			"draft_after": false,
			"gold": "midboss",
			"shop_window_after": int(stage["shop_window"]) if bool(stage["shop_after"]) else 0,
			"evolution_after": evolution_after,
			"is_final_boss": false,
		})

	for enemy_id in Balance.run_config["pewter_encounter_sequence"]:
		var is_boss := bool(Balance.enemies[enemy_id].get("is_boss", false))
		encounters.append({
			"kind": "boss" if is_boss else "pewter",
			"enemy_id": String(enemy_id),
			"stage_id": "pewter",
			"reward_pool_key": "stage3",
			"draft_after": not is_boss,
			"gold": "",
			"shop_window_after": 0,
			"evolution_after": false,
			"is_final_boss": is_boss,
		})


func _resolve_mid_boss_id(stage: Dictionary) -> String:
	if stage.get("mid_boss") != null:
		if String(stage["mid_boss"]) == Rivals.RIVAL_SENTINEL:
			return Rivals.resolve_rival_enemy_id(starter_id)
		return String(stage["mid_boss"])
	var variants: Array = stage["mid_boss_variants"]
	return String(variants[rng.randi_range(0, variants.size() - 1)])


# --- Input map (defined in code so project.godot stays minimal) ---

func _setup_input() -> void:
	_add_action("move_forward", [KEY_W, KEY_UP])
	_add_action("move_back", [KEY_S, KEY_DOWN])
	_add_action("strafe_left", [KEY_A, KEY_Q])
	_add_action("strafe_right", [KEY_D, KEY_E])
	_add_action("turn_left", [KEY_LEFT])
	_add_action("turn_right", [KEY_RIGHT])


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
