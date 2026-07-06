class_name Rewards
## Post-combat rewards: draft picks, evolution, badge, signature card (port of rewards.py).

const STARTER_STAB_CARD := {
	"bulbasaur": "vine_whip",
	"squirtle": "water_gun",
	"charmander": "ember",
}


static func generate_draft_options(bal, reward_pool: Array, rng: RandomNumberGenerator,
		starter_id: String = "") -> Array[String]:
	var pool: Array = reward_pool.duplicate()
	var count: int = mini(bal.draft_options(), pool.size())
	if count == 0:
		return []

	var stab_card := String(STARTER_STAB_CARD.get(starter_id, ""))
	var inject_stab: bool = stab_card != "" and bal.cards.has(stab_card) \
			and rng.randf() < bal.stab_chance()

	if inject_stab:
		var filler: Array = pool.filter(func(card_id): return card_id != stab_card)
		var need := count - 1
		if need <= 0:
			var only: Array[String] = [stab_card]
			return only
		if need <= filler.size():
			var options := _sample(filler, need, rng)
			options.append(stab_card)
			DeckOps.shuffle(options, rng)
			return options

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


static func _sample(pool: Array, count: int, rng: RandomNumberGenerator) -> Array[String]:
	var copy: Array = pool.duplicate()
	DeckOps.shuffle(copy, rng)
	var out: Array[String] = []
	for i in count:
		out.append(String(copy[i]))
	return out
