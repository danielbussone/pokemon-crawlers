class_name CombatCtx
extends RefCounted
## Turn-based combat state machine (port of combat.py).
## Turn order must match the PoC exactly — see docs/GODOT_HANDOFF.md.

const ONGOING := "ongoing"
const WIN := "player_win"
const LOSS := "player_loss"

var bal  # Balance autoload
var rng: RandomNumberGenerator
var player: PlayerState
var enemy: EnemyState
var enemy_def: Dictionary
var turn := 0
var boss_pattern_index := 0
var next_enemy_action_name := ""  # empty = unknown (wild AI)
var items_used_this_turn := 0
var slept_this_turn := false      # UI hint: player turn was skipped by Sleep


static func start(p_player: PlayerState, enemy_id: String, p_bal,
		p_rng: RandomNumberGenerator) -> CombatCtx:
	var ctx := CombatCtx.new()
	ctx.bal = p_bal
	ctx.rng = p_rng
	ctx.player = p_player
	ctx.enemy_def = p_bal.enemies[enemy_id]

	var e := EnemyState.new()
	e.hp = int(ctx.enemy_def["max_hp"])
	e.max_hp = e.hp
	e.ptype = String(ctx.enemy_def["pokemon_type"])
	e.enemy_id = enemy_id
	e.is_boss = bool(ctx.enemy_def.get("is_boss", false))
	e.is_wild = bool(ctx.enemy_def.get("is_wild", true))
	ctx.enemy = e

	if EnemyAI.uses_fixed_pattern(ctx.enemy_def):
		ctx.next_enemy_action_name = String(
				EnemyAI.get_boss_action(ctx.enemy_def, ctx.boss_pattern_index)["name"])
	return ctx


func check_outcome() -> String:
	if enemy.hp <= 0:
		return WIN
	if player.hp <= 0:
		return LOSS
	return ONGOING


func player_turn_begin() -> String:
	turn += 1
	items_used_this_turn = 0
	slept_this_turn = false
	player.block = 0
	Effects.apply_player_turn_start_modifiers(player, bal)

	Effects.tick_poison(player)
	var outcome := check_outcome()
	if outcome != ONGOING:
		return outcome

	if Effects.has_status(player, "sleep"):
		slept_this_turn = true
		Effects.decrement_statuses(player)
		Effects.decrement_conditions(player)
		DeckOps.discard_hand(player)
		return check_outcome()

	Effects.decrement_statuses(player)
	Effects.decrement_conditions(player)
	outcome = check_outcome()
	if outcome != ONGOING:
		return outcome

	DeckOps.draw_to_hand(player, bal.hand_size(), rng)
	return ONGOING


## Returns {"ok": bool, "reason": String, "card_id": String}
func can_play_card(hand_index: int) -> Dictionary:
	if Effects.has_status(player, "sleep"):
		return {"ok": false, "reason": "Asleep — cannot play cards.", "card_id": ""}
	if hand_index < 0 or hand_index >= player.hand.size():
		return {"ok": false, "reason": "Invalid hand index.", "card_id": ""}

	var card_id: String = player.hand[hand_index]
	var card: Dictionary = bal.cards[card_id]

	if Effects.has_status(player, "paralyze") and String(card["card_type"]) == "attack":
		return {"ok": false, "reason": "Paralyzed — Attack cards locked.", "card_id": ""}
	if int(card["cost"]) > player.current_stamina:
		return {"ok": false, "reason": "Not enough stamina.", "card_id": ""}
	return {"ok": true, "reason": "", "card_id": card_id}


func play_card(hand_index: int) -> Dictionary:
	var check := can_play_card(hand_index)
	if not check["ok"]:
		return check

	Effects.apply_confuse_self_damage(player, bal.confuse_self_dmg())
	if check_outcome() == LOSS:
		return {"ok": false, "reason": "Player defeated.", "card_id": ""}

	var card_id := DeckOps.play_card_from_hand(player, hand_index)
	var card: Dictionary = bal.cards[card_id]
	player.current_stamina -= int(card["cost"])

	var effect_log := Effects.resolve_card_effects(card, player, enemy, bal, rng)
	return {"ok": true, "reason": "", "card_id": card_id, "effect_log": effect_log}


func end_player_turn() -> void:
	DeckOps.discard_hand(player)


## Returns {"outcome", "action_name", "slept", "paralyzed_skip", "acted", "poison_win"}
func enemy_turn() -> Dictionary:
	enemy.block = 0

	Effects.tick_poison(enemy)
	var outcome := check_outcome()
	if outcome != ONGOING:
		return _turn_result(outcome, "", false, false, false, outcome == WIN)

	var slept := Effects.has_status(enemy, "sleep")
	var paralyzed := Effects.has_status(enemy, "paralyze")

	var action: Dictionary
	if EnemyAI.uses_fixed_pattern(enemy_def):
		action = EnemyAI.get_boss_action(enemy_def, boss_pattern_index)
		next_enemy_action_name = String(EnemyAI.get_boss_action(enemy_def,
				EnemyAI.advance_boss_pattern_index(enemy_def, boss_pattern_index))["name"])
	else:
		action = EnemyAI.choose_wild_action(enemy_def, enemy, player, bal, rng)
		next_enemy_action_name = ""

	var action_name := String(action["name"])

	if slept:
		Effects.decrement_statuses(enemy)
		Effects.decrement_conditions(enemy)
		if EnemyAI.uses_fixed_pattern(enemy_def):
			boss_pattern_index = EnemyAI.advance_boss_pattern_index(enemy_def, boss_pattern_index)
		return _turn_result(check_outcome(), action_name, true, false, false, false)

	Effects.decrement_statuses(enemy)
	Effects.decrement_conditions(enemy)
	outcome = check_outcome()
	if outcome != ONGOING:
		return _turn_result(outcome, action_name, false, false, false, false)

	var skip_attack := paralyzed and bool(action.get("is_attack", false))
	var acted := false
	var effect_log: Array = []
	if not skip_attack:
		Effects.apply_confuse_self_damage(enemy, bal.confuse_self_dmg())
		outcome = check_outcome()
		if outcome != ONGOING:
			return _turn_result(outcome, action_name, false, false, false, false)

		effect_log = Effects.resolve_enemy_action_effects(action["effects"],
				bool(action.get("is_attack", false)), enemy, player, enemy.ptype, bal, rng,
				String(action.get("id", "")))
		acted = true

	if EnemyAI.uses_fixed_pattern(enemy_def):
		boss_pattern_index = EnemyAI.advance_boss_pattern_index(enemy_def, boss_pattern_index)

	return _turn_result(check_outcome(), action_name, false, skip_attack, acted, false, effect_log)


func use_item(item_id: String) -> Dictionary:
	var result := Items.use_item_in_combat(player, item_id, bal, items_used_this_turn)
	if result["ok"]:
		items_used_this_turn += 1
	return result


func format_enemy_turn_message(before_player_hp: int, result: Dictionary) -> String:
	var enemy_name := String(enemy_def["name"])
	if result["poison_win"] and result["outcome"] == WIN:
		return "%s succumbed to poison!" % enemy_name

	var parts: Array[String] = []
	if result["slept"]:
		parts.append("%s is asleep and did not act." % enemy_name)
	elif result["paralyzed_skip"] and result["action_name"] != "":
		parts.append("%s is paralyzed — %s failed!" % [enemy_name, result["action_name"]])
	elif result["action_name"] != "":
		parts.append("%s used %s." % [enemy_name, result["action_name"]])

	var dmg := before_player_hp - player.hp
	if dmg > 0:
		parts.append("You took %d damage." % dmg)
	elif result["acted"] and dmg == 0 and not result["paralyzed_skip"] and not result["slept"]:
		parts.append("No damage to you.")

	if parts.is_empty():
		return "%s took a turn." % enemy_name
	return " ".join(parts)


func _turn_result(outcome: String, action_name: String, slept: bool,
		paralyzed_skip: bool, acted: bool, poison_win: bool, effect_log: Array = []) -> Dictionary:
	return {
		"outcome": outcome,
		"action_name": action_name,
		"slept": slept,
		"paralyzed_skip": paralyzed_skip,
		"acted": acted,
		"poison_win": poison_win,
		"effect_log": effect_log,
	}
