class_name RareCandyOps
## Rare Candy (Phase 3): a boss-drop token spent to evolve one eligible deck card
## (e.g. Quick Attack -> Hyper Fang). Starter-line cards are excluded — those
## evolve through the XP learnset, and letting a token bypass that would desync
## the learnset's current-card tracking.


## Unique card ids across all deck zones that a Rare Candy can evolve: the card
## declares a valid `evolves_to` and is not managed by the starter's learnset.
static func evolvable_deck_cards(player: PlayerState, bal) -> Array[String]:
	var line_cards: Dictionary = bal.starter_line_cards(player.starter_id)
	var seen: Dictionary = {}
	var out: Array[String] = []
	for pile in [player.deck, player.hand, player.discard]:
		for cid_v in pile:
			var cid := String(cid_v)
			if seen.has(cid) or line_cards.has(cid):
				continue
			var evolves_to := String(bal.cards.get(cid, {}).get("evolves_to", ""))
			if evolves_to != "" and bal.cards.has(evolves_to):
				seen[cid] = true
				out.append(cid)
	return out


static func has_spendable(player: PlayerState, bal) -> bool:
	return player.rare_candy > 0 and not evolvable_deck_cards(player, bal).is_empty()


## Spend one token to evolve every copy of `card_id`. Returns true on success.
static func spend(player: PlayerState, card_id: String, bal) -> bool:
	if player.rare_candy <= 0:
		return false
	var to_card := String(bal.cards.get(card_id, {}).get("evolves_to", ""))
	if to_card == "" or not bal.cards.has(to_card):
		return false
	if not DeckOps.apply_evolution(player, card_id, to_card):
		return false
	player.rare_candy -= 1
	return true
