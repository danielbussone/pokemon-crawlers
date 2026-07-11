class_name Rewards
## Post-combat rewards: draft picks, badge, signature card (port of rewards.py).
## Starter-line STAB moves now come from the XP learnset (Phase 1), not draft.


static func generate_draft_options(bal, reward_pool: Array, rng: RandomNumberGenerator,
		starter_id: String = "") -> Array[String]:
	var pool: Array = reward_pool.duplicate()
	var count: int = mini(bal.draft_options(), pool.size())
	if count == 0:
		return []
	return _sample(pool, count, rng)


static func apply_draft_pick(player: PlayerState, card_id: String) -> void:
	DeckOps.add_card_to_deck(player, card_id)


static func apply_evolution_catalyst(player: PlayerState, bal) -> bool:
	var evolution: Dictionary = bal.run_config["evolution"]
	return DeckOps.apply_evolution(player, String(evolution["from"]), String(evolution["to"]))


static func grant_boss_rewards(player: PlayerState, bal) -> void:
	var badge_id := String(bal.run_config["badge_id"])
	if not player.badge_ids.has(badge_id):
		player.badge_ids.append(badge_id)
	DeckOps.add_card_to_deck(player, String(bal.run_config["signature_card"]))
	player.rare_candy += bal.rare_candy_gym_boss()


static func _sample(pool: Array, count: int, rng: RandomNumberGenerator) -> Array[String]:
	var copy: Array = pool.duplicate()
	DeckOps.shuffle(copy, rng)
	var out: Array[String] = []
	for i in count:
		out.append(String(copy[i]))
	return out
