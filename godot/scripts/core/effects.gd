class_name Effects
## Damage, block, statuses, conditions, effect resolution (port of effects.py).
## All functions take `bal` (the Balance autoload) explicitly.


static func has_condition(c: Combatant, condition_id: String) -> bool:
	for entry in c.conditions:
		if entry["id"] == condition_id:
			return true
	return false


static func has_status(c: Combatant, status_type: String) -> bool:
	for entry in c.statuses:
		if entry["type"] == status_type:
			return true
	return false


static func can_gain_block(c: Combatant) -> bool:
	return not has_condition(c, "defenseless")


static func apply_blinded_attack_check(attacker: Combatant) -> bool:
	## Returns true if the attack misses due to Blinded. Always decrements budget.
	if attacker.blinded_budget < 0:
		return false
	var missed := attacker.blinded_budget % 2 == 0
	attacker.blinded_budget -= 1
	if attacker.blinded_budget <= 0:
		attacker.blinded_budget = -1
	return missed


## Returns {"hp_damage": int, "blocked": bool, "missed_blinded": bool}
static func apply_damage(base_amount: int, attacker_type: String, defender: Combatant,
		attacker: Combatant, bal, attacker_badge_ids: Array,
		is_attack: bool = true, ignore_block: bool = false,
		outgoing_mult: float = 1.0) -> Dictionary:
	if is_attack and apply_blinded_attack_check(attacker):
		return {"hp_damage": 0, "blocked": false, "missed_blinded": true}

	var amount := int(base_amount * bal.type_mod(attacker_type, defender.ptype))

	if has_condition(attacker, "intimidated"):
		amount = int(amount * float(bal.conditions["intimidated"].get("outgoing_damage_mult", 1.0)))
	for condition_id in ["distracted", "defenseless"]:
		if has_condition(defender, condition_id):
			amount = int(amount * float(bal.conditions[condition_id].get("incoming_damage_mult", 1.0)))

	var badge_mult := 1.0
	for badge_id in attacker_badge_ids:
		if bal.badges.has(badge_id):
			badge_mult *= float(bal.badges[badge_id].get("outgoing_damage_mult", 1.0))
	# `outgoing_mult` carries the starter-evolution buff (Phase 3) for starter-line cards.
	amount = int(amount * badge_mult * outgoing_mult)
	amount = maxi(0, amount)

	if amount == 0:
		return {"hp_damage": 0, "blocked": false, "missed_blinded": false}

	if not ignore_block and defender.block >= amount:
		defender.block -= amount
		return {"hp_damage": 0, "blocked": true, "missed_blinded": false}

	var hp_damage := amount - defender.block
	defender.block = 0
	defender.hp = maxi(0, defender.hp - hp_damage)
	return {"hp_damage": hp_damage, "blocked": false, "missed_blinded": false}


static func apply_heal(target: Combatant, amount: int) -> Dictionary:
	var before := target.hp
	target.hp = mini(target.max_hp, target.hp + amount)
	return {"amount": target.hp - before}


static func apply_block(target: Combatant, amount: int) -> Dictionary:
	if amount <= 0 or not can_gain_block(target):
		return {"amount": 0}
	target.block += amount
	return {"amount": amount}


static func apply_status(target: Combatant, status_type: String, duration: int,
		magnitude: int = 0) -> Dictionary:
	for entry in target.statuses:
		if entry["type"] == status_type:
			entry["turns"] += duration
			if magnitude > 0:
				entry["magnitude"] = magnitude
			return {"status_type": status_type, "turns": duration, "magnitude": magnitude}
	target.statuses.append({"type": status_type, "turns": duration, "magnitude": magnitude})
	return {"status_type": status_type, "turns": duration, "magnitude": magnitude}


## duration: -1 means "not specified" (use the condition's default)
static func apply_condition(target: Combatant, condition_id: String, bal, duration: int = -1,
		player: PlayerState = null, is_target_player: bool = false) -> Dictionary:
	var defn: Dictionary = bal.conditions[condition_id]

	if condition_id == "blinded":
		_apply_blinded(target, defn)
		return {"condition_id": "blinded", "turns": -1}
	if condition_id == "slow":
		var slow_turns := duration if duration > 0 else 1
		_apply_slow(target, defn, duration, player, is_target_player)
		return {"condition_id": "slow", "turns": slow_turns}

	var turns := duration if duration > 0 else int(defn.get("default_duration", 1))
	_stack_condition(target, condition_id, turns)
	return {"condition_id": condition_id, "turns": turns}


static func tick_poison(c: Combatant) -> int:
	var total := 0
	for entry in c.statuses:
		if entry["type"] == "poison" and int(entry["magnitude"]) > 0:
			c.hp = maxi(0, c.hp - int(entry["magnitude"]))
			total += int(entry["magnitude"])
	return total


static func decrement_statuses(c: Combatant) -> void:
	var remaining: Array[Dictionary] = []
	for entry in c.statuses:
		entry["turns"] -= 1
		if entry["turns"] > 0:
			remaining.append(entry)
	c.statuses = remaining


static func decrement_conditions(c: Combatant) -> void:
	var remaining: Array[Dictionary] = []
	for entry in c.conditions:
		entry["turns"] -= 1
		if entry["turns"] > 0:
			remaining.append(entry)
	c.conditions = remaining


## Resolves an effect array (card or enemy action). Returns Array of effect-log dicts.
static func resolve_effects(effects: Array, attacker: Combatant, defender: Combatant,
		attacker_type: String, bal, player: PlayerState, is_player_attacker: bool,
		rng: RandomNumberGenerator, outgoing_mult: float = 1.0) -> Array:
	var results: Array = []
	var badge_ids: Array = []
	if player != null and is_player_attacker:
		badge_ids = player.badge_ids

	for eff in effects:
		var target: Combatant = attacker if String(eff.get("target", "enemy")) == "self" else defender
		var is_target_player := target is PlayerState
		var eff_type := String(eff.get("type", ""))

		if eff_type == "damage":
			var dmg := apply_damage(int(eff.get("magnitude", 0)), attacker_type, target,
					attacker, bal, badge_ids, true, bool(eff.get("ignore_block", false)), outgoing_mult)
			results.append({"type": "damage", "target_is_player": is_target_player}.merged(dmg))
		elif eff_type == "block":
			var block := apply_block(target, int(eff.get("magnitude", 0)))
			results.append({"type": "block", "target_is_player": is_target_player}.merged(block))
		elif eff_type == "heal":
			var heal := apply_heal(target, int(eff.get("magnitude", 0)))
			results.append({"type": "heal", "target_is_player": is_target_player}.merged(heal))
		elif eff_type == "status":
			if eff.has("status") and eff.has("duration"):
				var status := apply_status(target, String(eff["status"]), int(eff["duration"]),
						int(eff.get("magnitude", 0)))
				results.append({"type": "status", "target_is_player": is_target_player}.merged(status))
		elif eff_type == "apply_condition":
			if eff.has("condition"):
				var cond := apply_condition(target, String(eff["condition"]), bal,
						int(eff.get("duration", -1)), player, is_target_player)
				results.append({"type": "apply_condition", "target_is_player": is_target_player}.merged(cond))
		elif eff_type == "draw":
			if player != null and is_player_attacker and int(eff.get("magnitude", 0)) > 0:
				DeckOps.draw_cards(player, int(eff["magnitude"]), bal.hand_size(), rng)

	return results


static func resolve_card_effects(card: Dictionary, player: PlayerState, enemy: Combatant,
		bal, rng: RandomNumberGenerator) -> Array:
	# Starter-line cards (Phase 3) carry the XP-milestone damage buff.
	var outgoing_mult := StarterEvo.card_damage_mult(card, player, bal)
	return resolve_effects(card["effects"], player, enemy, String(card["pokemon_type"]),
			bal, player, true, rng, outgoing_mult)


static func attack_type_for_action(action_id: String, enemy_type: String, bal) -> String:
	if action_id != "" and bal.cards.has(action_id):
		return String(bal.cards[action_id]["pokemon_type"])
	return enemy_type


static func resolve_enemy_action_effects(effects: Array, is_attack: bool, enemy: Combatant,
		player: PlayerState, enemy_type: String, bal, rng: RandomNumberGenerator,
		action_id: String = "") -> Array:
	var attack_type := attack_type_for_action(action_id, enemy_type, bal)
	if not is_attack:
		return resolve_effects(effects, enemy, player, attack_type, bal, player, false, rng)

	var results: Array = []
	for eff in effects:
		if String(eff.get("type", "")) == "damage":
			var dmg := apply_damage(int(eff.get("magnitude", 0)), attack_type, player,
					enemy, bal, [], true, bool(eff.get("ignore_block", false)))
			results.append({"type": "damage", "target_is_player": true}.merged(dmg))
		else:
			results.append_array(resolve_effects([eff], enemy, player, attack_type, bal, player, false, rng))
	return results


static func apply_confuse_self_damage(c: Combatant, amount: int) -> int:
	if not has_status(c, "confuse"):
		return 0
	c.hp = maxi(0, c.hp - amount)
	return amount


static func apply_player_turn_start_modifiers(player: PlayerState, bal) -> void:
	## Reset stamina for the turn including Slow penalty and prior-turn Slow-on-enemy bonus.
	var base := player.base_max_stamina
	var bonus := player.stamina_bonus_next_turn
	player.stamina_bonus_next_turn = 0

	var slow_penalty := 0
	if has_condition(player, "slow"):
		slow_penalty = int(bal.conditions["slow"]["on_player"].get("stamina_delta", 0))

	player.max_stamina = maxi(0, base + bonus + slow_penalty)
	player.current_stamina = player.max_stamina


# --- Internal helpers ---

static func _stack_condition(target: Combatant, condition_id: String, turns: int) -> void:
	for entry in target.conditions:
		if entry["id"] == condition_id:
			entry["turns"] += turns
			return
	target.conditions.append({"id": condition_id, "turns": turns})


static func _apply_blinded(target: Combatant, defn: Dictionary) -> void:
	if target.blinded_budget < 0:
		target.blinded_budget = int(defn.get("initial_budget", 4))
		return
	var add := int(defn.get("reapply_budget_add", 2))
	var cap := int(defn.get("reapply_budget_cap", 6))
	target.blinded_budget = mini(cap, target.blinded_budget + add)


static func _apply_slow(target: Combatant, defn: Dictionary, duration: int,
		player: PlayerState, is_target_player: bool) -> void:
	var turns := duration if duration > 0 else 1
	if is_target_player:
		_stack_condition(target, "slow", turns)
		return
	if player != null:
		var grant := int(defn.get("on_enemy", {}).get("grant_player_stamina_next_turn", 0))
		player.stamina_bonus_next_turn += grant
		_stack_condition(target, "slow", turns)
