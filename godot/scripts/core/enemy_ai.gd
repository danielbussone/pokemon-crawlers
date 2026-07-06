class_name EnemyAI
## Enemy action selection — phase-weighted wild AI and boss patterns (port of enemy_ai.py).


static func hp_phase(hp: int, max_hp: int) -> String:
	if max_hp <= 0:
		return "desperate"
	var pct := float(hp) / float(max_hp)
	if pct > 0.7:
		return "healthy"
	if pct > 0.3:
		return "mid"
	return "desperate"


static func uses_fixed_pattern(enemy_def: Dictionary) -> bool:
	return not (enemy_def.get("boss_pattern", []) as Array).is_empty()


static func choose_wild_action(enemy_def: Dictionary, enemy: EnemyState, player: PlayerState,
		bal, rng: RandomNumberGenerator) -> Dictionary:
	var phase := hp_phase(enemy.hp, enemy.max_hp)
	var pool: Array = enemy_def["action_pool"]
	var weights: Array[float] = []
	var total := 0.0
	for action in pool:
		var w := float(_action_weight(action, phase, enemy.ptype, player.ptype, bal))
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]


static func get_boss_action(enemy_def: Dictionary, pattern_index: int) -> Dictionary:
	var pattern: Array = enemy_def["boss_pattern"]
	assert(not pattern.is_empty(), "Boss '%s' has no boss_pattern" % enemy_def.get("id", "?"))
	var action_id: String = pattern[pattern_index % pattern.size()]
	for action in enemy_def["action_pool"]:
		if action["id"] == action_id:
			return action
	assert(false, "Boss pattern references unknown action '%s'" % action_id)
	return {}


static func advance_boss_pattern_index(enemy_def: Dictionary, current_index: int) -> int:
	var next_index := current_index + 1
	if next_index >= (enemy_def["boss_pattern"] as Array).size():
		return int(enemy_def.get("boss_pattern_loop_start", 0))
	return next_index


static func _max_attack_damage(action: Dictionary, enemy_type: String, player_type: String, bal) -> int:
	var best := 0
	for eff in action["effects"]:
		if String(eff.get("type", "")) != "damage":
			continue
		best = maxi(best, int(float(eff.get("magnitude", 0)) * bal.type_mod(enemy_type, player_type)))
	return best


static func _action_weight(action: Dictionary, phase: String, enemy_type: String,
		player_type: String, bal) -> int:
	var weight: int = maxi(1, int(action.get("base_weight", 1)))
	var preferred := String(action.get("preferred_phase", "any")).to_lower()
	var is_attack := bool(action.get("is_attack", false))

	if phase == "healthy" and preferred == "healthy":
		weight *= 3
	elif phase == "mid" and (preferred == "mid" or preferred == "any"):
		weight *= 2
	elif phase == "desperate":
		if is_attack:
			weight *= 2
		if preferred == "desperate":
			weight *= 2

	if is_attack:
		var max_damage := _max_attack_damage(action, enemy_type, player_type, bal)
		if max_damage > 0:
			weight += max_damage

	return weight
