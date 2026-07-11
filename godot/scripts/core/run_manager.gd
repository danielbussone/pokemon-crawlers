extends Node
## Autoload "Run" — full Kanto arc orchestration (port of run_flow.py).
## Mandatory gate fights advance encounter_index; optional wilds are tracked separately.

const LearnsetOps = preload("res://scripts/core/learnset_ops.gd")

var rng := RandomNumberGenerator.new()
var starter_id := ""
var trainer_appearance := "boy"
var player: PlayerState = null
## Flat list laid out by the world (linear corridor until maze TODOs land).
var encounters: Array[Dictionary] = []
## Gate fights only — rival, bug catcher, gym leaders.
var mandatory_encounters: Array[Dictionary] = []
## Opt-in wilds — gold + draft, once per tile via cleared_optional.
var optional_encounters: Array[Dictionary] = []
## Mandatory gate progress (0 = before Rival, 1 = before Bug Catcher, …).
var encounter_index := 0
## flat_index -> true for cleared optional wilds.
var cleared_optional: Dictionary = {}
var evolution_applied := false
var unlocked_shop_window := 0  # 0 = none, 1 = after Rival, 2 = after Bug Catcher
var run_over := false
var run_won := false

var _active_encounter_idx := -1

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
	cleared_optional.clear()
	unlocked_shop_window = 0
	run_over = false
	run_won = false
	_active_encounter_idx = -1

	player = PlayerState.new()
	player.hp = Balance.max_hp()
	player.max_hp = player.hp
	player.ptype = String(STARTER_TYPES.get(p_starter_id, "NORMAL"))
	player.starter_id = p_starter_id
	player.base_max_stamina = Balance.max_stamina()
	player.max_stamina = player.base_max_stamina
	player.current_stamina = player.base_max_stamina
	LearnsetOps.init_run(player, p_starter_id, Balance, rng)

	_build_encounters()


func encounter_at(flat_idx: int) -> Dictionary:
	if flat_idx < 0 or flat_idx >= encounters.size():
		return {}
	return encounters[flat_idx]


func is_optional_cleared(flat_idx: int) -> bool:
	return cleared_optional.has(flat_idx)


func is_mandatory_cleared(flat_idx: int) -> bool:
	var enc := encounter_at(flat_idx)
	if enc.is_empty() or not bool(enc.get("is_mandatory", false)):
		return false
	return int(enc.get("mandatory_slot", -1)) < encounter_index


func is_encounter_cleared(flat_idx: int) -> bool:
	var enc := encounter_at(flat_idx)
	if enc.is_empty():
		return true
	if bool(enc.get("is_optional", false)):
		return is_optional_cleared(flat_idx)
	return is_mandatory_cleared(flat_idx)


func can_trigger_encounter(flat_idx: int) -> bool:
	var enc := encounter_at(flat_idx)
	if enc.is_empty() or is_encounter_cleared(flat_idx):
		return false
	if bool(enc.get("is_optional", false)):
		return true
	return int(enc.get("mandatory_slot", -1)) == encounter_index


## Flat index of the next mandatory gate marker to highlight.
func active_marker_index() -> int:
	for i in encounters.size():
		var enc := encounters[i]
		if bool(enc.get("is_mandatory", false)) \
				and int(enc.get("mandatory_slot", -1)) == encounter_index:
			return i
	return mini(encounter_index, maxi(encounters.size() - 1, 0))


func current_encounter() -> Dictionary:
	if _active_encounter_idx >= 0:
		return encounter_at(_active_encounter_idx)
	return encounter_at(active_marker_index())


func begin_combat_at(flat_idx: int) -> CombatCtx:
	_active_encounter_idx = flat_idx
	prepare_between_encounters()
	var enc := encounter_at(flat_idx)
	return CombatCtx.start(player, String(enc["enemy_id"]), Balance, rng)


func begin_combat() -> CombatCtx:
	## Headless sim — fight the next available encounter in flat order.
	for i in encounters.size():
		if can_trigger_encounter(i):
			return begin_combat_at(i)
	return begin_combat_at(active_marker_index())


## Post-victory bookkeeping. Returns what happened so the UI can present it:
## {"gold": int, "draft_options": Array[String], "evolved": bool,
##  "shop_window": int, "run_complete": bool, "was_optional": bool}
func after_win() -> Dictionary:
	var enc := encounter_at(_active_encounter_idx)
	var is_optional := bool(enc.get("is_optional", false))
	var out := {
		"gold": 0,
		"draft_options": [] as Array[String],
		"evolved": false,
		"shop_window": 0,
		"run_complete": false,
		"was_optional": is_optional,
		"xp_gained": 0,
		"learn_events": [] as Array,
		"rare_candy_gained": 0,
	}
	prepare_between_encounters()

	# XP learnset (Phase 1): award XP for the fight and apply any unlocks. This
	# replaces the old fixed evolution_after catalyst.
	var xp_gain := LearnsetOps.xp_for_encounter(enc, Balance)
	out["xp_gained"] = xp_gain
	out["learn_events"] = LearnsetOps.award_xp(player, starter_id, Balance, xp_gain)

	var gold_cfg: Dictionary = Balance.economy["gold"]
	if String(enc.get("gold", "")) == "wild":
		var amount := rng.randi_range(int(gold_cfg["wild_min"]), int(gold_cfg["wild_max"]))
		player.gold += amount
		out["gold"] = amount
	elif String(enc.get("gold", "")) == "midboss":
		var amount := int(gold_cfg["mid_boss"])
		player.gold += amount
		out["gold"] = amount
		# Rare Candy (Phase 3): trainer mid-bosses drop a token so the evolve loop
		# is exercisable before the single gym boss, which ends the PoC run.
		var candy := Balance.rare_candy_mid_boss()
		if candy > 0:
			player.rare_candy += candy
			out["rare_candy_gained"] = candy

	if bool(enc.get("draft_after", false)):
		out["draft_options"] = Rewards.generate_draft_options(
				Balance, Balance.stage_rewards[enc["reward_pool_key"]], rng, starter_id)

	if is_optional:
		cleared_optional[_active_encounter_idx] = true
	else:
		if int(enc.get("shop_window_after", 0)) > 0:
			unlocked_shop_window = int(enc["shop_window_after"])
			out["shop_window"] = unlocked_shop_window

		if bool(enc.get("is_final_boss", false)):
			Rewards.grant_boss_rewards(player, Balance)
			out["rare_candy_gained"] = Balance.rare_candy_gym_boss()
			out["run_complete"] = true
			run_over = true
			run_won = true

		encounter_index += 1

	_active_encounter_idx = -1
	return out


func after_loss() -> void:
	run_over = true
	run_won = false
	_active_encounter_idx = -1


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
	mandatory_encounters.clear()
	optional_encounters.clear()
	var mandatory_slot := 0
	var trigger := String(Balance.run_config.get("evolution_trigger", "post_rival"))

	for stage in Balance.run_config["stages"]:
		var stage_id := String(stage["id"])
		var gate_id := stage_id

		for _i in int(stage["wild_count"]):
			var pool: Array = stage["wild_pool"]
			_append_encounter(_make_optional_wild(
					String(pool[rng.randi_range(0, pool.size() - 1)]),
					stage_id,
					String(stage["reward_pool_key"]),
					gate_id,
			))

		var mid_boss_id := _resolve_mid_boss_id(stage)
		var evolution_after := (trigger == "post_rival" and stage_id == "route_viridian") \
				or (trigger == "post_bug_catcher" and stage_id == "viridian_forest")
		_append_encounter(_make_mandatory_gate(
				mid_boss_id,
				"midboss",
				stage_id,
				String(stage["reward_pool_key"]),
				mandatory_slot,
				gate_id,
				int(stage["shop_window"]) if bool(stage["shop_after"]) else 0,
				evolution_after,
				false,
		))
		mandatory_slot += 1

	for enemy_id in Balance.run_config["pewter_encounter_sequence"]:
		var eid := String(enemy_id)
		var is_boss := bool(Balance.enemies[eid].get("is_boss", false))
		if is_boss:
			_append_encounter(_make_mandatory_gate(
					eid,
					"boss",
					"pewter",
					"stage3",
					mandatory_slot,
					"pewter_gym",
					0,
					false,
					true,
			))
			mandatory_slot += 1
		else:
			_append_encounter(_make_optional_wild(eid, "pewter", "stage3", "pewter_gym", "pewter"))


func _append_encounter(enc: Dictionary) -> void:
	encounters.append(enc)
	if bool(enc.get("is_optional", false)):
		optional_encounters.append(enc)
	else:
		mandatory_encounters.append(enc)


func _make_optional_wild(enemy_id: String, stage_id: String, reward_pool_key: String,
		gate_id: String, kind: String = "wild") -> Dictionary:
	return {
		"kind": kind,
		"enemy_id": enemy_id,
		"stage_id": stage_id,
		"reward_pool_key": reward_pool_key,
		"gate_id": gate_id,
		"is_mandatory": false,
		"is_optional": true,
		"mandatory_slot": -1,
		"draft_after": true,
		"gold": "wild",
		"shop_window_after": 0,
		"evolution_after": false,
		"is_final_boss": false,
	}


func _make_mandatory_gate(enemy_id: String, kind: String, stage_id: String,
		reward_pool_key: String, mandatory_slot: int, gate_id: String,
		shop_window_after: int, evolution_after: bool, is_final_boss: bool) -> Dictionary:
	return {
		"kind": kind,
		"enemy_id": enemy_id,
		"stage_id": stage_id,
		"reward_pool_key": reward_pool_key,
		"gate_id": gate_id,
		"is_mandatory": true,
		"is_optional": false,
		"mandatory_slot": mandatory_slot,
		"draft_after": false,
		"gold": "midboss" if kind == "midboss" else "",
		"shop_window_after": shop_window_after,
		"evolution_after": evolution_after,
		"is_final_boss": is_final_boss,
	}


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
