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


## Rewards a beaten mandatory leader hands out (Phase 5a): its badge (if any),
## signature card (if any), and rare candy (gym leaders drop more than trainers).
## The reward data rides on the encounter dict. Returns rare candy granted.
static func grant_leader_rewards(player: PlayerState, enc: Dictionary, bal) -> int:
	var badge_id := String(enc.get("badge_id", ""))
	if badge_id != "" and not player.badge_ids.has(badge_id):
		player.badge_ids.append(badge_id)
	var signature := String(enc.get("signature_card", ""))
	if signature != "":
		DeckOps.add_card_to_deck(player, signature)
	var candy: int = bal.rare_candy_gym_boss() if String(enc.get("leader_kind", "")) == "gym" \
			else bal.rare_candy_mid_boss()
	player.rare_candy += candy
	return candy


static func _sample(pool: Array, count: int, rng: RandomNumberGenerator) -> Array[String]:
	var copy: Array = pool.duplicate()
	DeckOps.shuffle(copy, rng)
	var out: Array[String] = []
	for i in count:
		out.append(String(copy[i]))
	return out
