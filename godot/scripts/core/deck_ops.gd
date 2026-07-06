class_name DeckOps
## Deck draw, discard, shuffle, and evolution (port of deck.py).


static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func build_player_deck(starter_id: String, bal, rng: RandomNumberGenerator) -> Array[String]:
	var deck: Array[String] = []
	for card_id in bal.starters[starter_id]["deck"]:
		deck.append(String(card_id))
	shuffle(deck, rng)
	return deck


static func draw_cards(player: PlayerState, count: int, hand_size: int, rng: RandomNumberGenerator) -> int:
	var drawn := 0
	for _i in count:
		if player.hand.size() >= hand_size:
			break
		if player.deck.is_empty() and not player.discard.is_empty():
			shuffle_discard_into_deck(player, rng)
		if player.deck.is_empty():
			break
		player.hand.append(player.deck.pop_front())
		drawn += 1
	return drawn


static func draw_to_hand(player: PlayerState, hand_size: int, rng: RandomNumberGenerator) -> int:
	var needed := hand_size - player.hand.size()
	if needed <= 0:
		return 0
	return draw_cards(player, needed, hand_size, rng)


static func discard_hand(player: PlayerState) -> void:
	if not player.hand.is_empty():
		player.discard.append_array(player.hand)
		player.hand.clear()


static func play_card_from_hand(player: PlayerState, hand_index: int) -> String:
	var card_id: String = player.hand[hand_index]
	player.hand.remove_at(hand_index)
	player.discard.append(card_id)
	return card_id


static func shuffle_discard_into_deck(player: PlayerState, rng: RandomNumberGenerator) -> void:
	if player.discard.is_empty():
		return
	shuffle(player.discard, rng)
	player.deck.append_array(player.discard)
	player.discard.clear()


static func add_card_to_deck(player: PlayerState, card_id: String) -> void:
	player.deck.append(card_id)


static func apply_evolution(player: PlayerState, from_card_id: String, to_card_id: String) -> bool:
	## Replace all instances of from_card_id with to_card_id across deck zones.
	var replaced := false
	for pile in [player.deck, player.hand, player.discard]:
		for index in pile.size():
			if pile[index] == from_card_id:
				pile[index] = to_card_id
				replaced = true
	return replaced
