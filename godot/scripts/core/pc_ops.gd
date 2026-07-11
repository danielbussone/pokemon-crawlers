class_name PcOps
## Bill's PC (Phase 4): deposit/withdraw cards between the active deck and a
## storage box at Pokémon Centers, unlocked after the first badge. Each deposit
## or withdraw is one "swap" — it costs a flat fee and counts against a per-visit
## limit; deposits can't take the active deck below a minimum size. Swaps reset
## on each Center visit.


static func unlocked(player: PlayerState) -> bool:
	return not player.badge_ids.is_empty()


## Call when the player enters a Center — refreshes the per-visit swap budget.
static func on_center_visit(player: PlayerState) -> void:
	player.pc_swaps_used = 0


static func swap_limit(bal) -> int:
	return int(bal.bills_pc()["swap_limit"])


static func swap_fee(bal) -> int:
	return int(bal.bills_pc()["swap_fee"])


static func min_deck_size(bal) -> int:
	return int(bal.bills_pc()["min_deck_size"])


static func swaps_remaining(player: PlayerState, bal) -> int:
	return maxi(0, swap_limit(bal) - player.pc_swaps_used)


## Active-deck cards (deck + hand + discard consolidated) as a flat list, so the
## PC can show/deposit whatever the player currently runs regardless of pile.
static func active_deck_cards(player: PlayerState) -> Array[String]:
	var out: Array[String] = []
	out.append_array(player.deck)
	out.append_array(player.hand)
	out.append_array(player.discard)
	return out


static func active_deck_size(player: PlayerState) -> int:
	return player.deck.size() + player.hand.size() + player.discard.size()


## Move a card out of the active deck into the box. Returns {ok, reason}.
static func deposit(player: PlayerState, card_id: String, bal) -> Dictionary:
	if swaps_remaining(player, bal) <= 0:
		return {"ok": false, "reason": "No swaps left this visit."}
	if active_deck_size(player) <= min_deck_size(bal):
		return {"ok": false, "reason": "Deck can't go below %d cards." % min_deck_size(bal)}
	if player.gold < swap_fee(bal):
		return {"ok": false, "reason": "Not enough gold (%dg)." % swap_fee(bal)}
	if not _remove_from_active(player, card_id):
		return {"ok": false, "reason": "Card not in deck."}
	player.pc_box.append(card_id)
	player.gold -= swap_fee(bal)
	player.pc_swaps_used += 1
	return {"ok": true, "reason": ""}


## Move a boxed card back into the active deck. Returns {ok, reason}.
static func withdraw(player: PlayerState, card_id: String, bal) -> Dictionary:
	if swaps_remaining(player, bal) <= 0:
		return {"ok": false, "reason": "No swaps left this visit."}
	if player.gold < swap_fee(bal):
		return {"ok": false, "reason": "Not enough gold (%dg)." % swap_fee(bal)}
	var idx: int = player.pc_box.find(card_id)
	if idx < 0:
		return {"ok": false, "reason": "Card not in box."}
	player.pc_box.remove_at(idx)
	player.deck.append(card_id)
	player.gold -= swap_fee(bal)
	player.pc_swaps_used += 1
	return {"ok": true, "reason": ""}


static func _remove_from_active(player: PlayerState, card_id: String) -> bool:
	for pile in [player.deck, player.hand, player.discard]:
		var idx: int = pile.find(card_id)
		if idx >= 0:
			pile.remove_at(idx)
			return true
	return false
