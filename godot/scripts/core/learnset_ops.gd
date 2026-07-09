class_name LearnsetOps
## XP learnset (Phase 1): builds the starting deck from learnsets.json, awards
## XP after fights, and applies "learn events" that ADD a new card or REPLACE a
## line's current card with its next upgrade (Vine Whip -> Razor Leaf -> ...).
##
## A learnset line is `{name, stages:[{xp, card_id}]}`. Stage 0 with xp 0 is a
## starting move; higher stages replace the line's current card at their XP
## threshold. The 3-card `starter_deck` is Normal filler; a line whose stage-0
## card is one of those filler cards upgrades those copies in place.


static func xp_for_encounter(enc: Dictionary, bal) -> int:
	if bool(enc.get("is_optional", false)):
		return bal.xp_per_wild()
	if bool(enc.get("is_final_boss", false)):
		return bal.xp_per_gym_boss()
	return bal.xp_per_mid_boss()


## Deck the player begins the run with: the filler `starter_deck` plus each
## line's xp-0 move that isn't already one of the filler cards.
static func starting_deck_ids(starter_id: String, bal) -> Array[String]:
	var ls: Dictionary = bal.learnset_for(starter_id)
	var filler: Array = ls.get("starter_deck", [])
	var deck: Array[String] = []
	for c in filler:
		deck.append(String(c))
	for line in ls.get("lines", []):
		var stages: Array = line["stages"]
		if stages.is_empty() or int(stages[0]["xp"]) > 0:
			continue
		var card := String(stages[0]["card_id"])
		if _count(filler, card) == 0:
			deck.append(card)
	return deck


## Reset a player's deck + XP state for a new run (shuffled starting deck,
## xp 0, line tracking primed for the xp-0 moves).
static func init_run(player: PlayerState, starter_id: String, bal, rng: RandomNumberGenerator) -> void:
	player.xp = 0
	player.learn_progress = {}
	player.learn_current = {}
	player.hand = []
	player.discard = []

	var ls: Dictionary = bal.learnset_for(starter_id)
	var lines: Array = ls.get("lines", [])
	for li in lines.size():
		var stages: Array = lines[li]["stages"]
		var target := _stage_for_xp(stages, 0)
		if target >= 0:
			player.learn_progress[li] = target
			player.learn_current[li] = String(stages[target]["card_id"])

	var deck := starting_deck_ids(starter_id, bal)
	DeckOps.shuffle(deck, rng)
	player.deck = deck


## Add XP and apply any newly-crossed unlocks. Returns learn events:
## [{"line": String, "from": String, "to": String, "is_upgrade": bool}].
static func award_xp(player: PlayerState, starter_id: String, bal, amount: int) -> Array:
	if amount <= 0:
		return []
	player.xp += amount
	return _sync_learns(player, starter_id, bal)


## The soonest future unlock across all lines, for HUD display.
## Returns {"at_xp": int, "card_id": String, "remaining": int} or {} if maxed.
static func next_unlock(player: PlayerState, starter_id: String, bal) -> Dictionary:
	var ls: Dictionary = bal.learnset_for(starter_id)
	var lines: Array = ls.get("lines", [])
	var best := {}
	for li in lines.size():
		var stages: Array = lines[li]["stages"]
		var next_idx := int(player.learn_progress.get(li, -1)) + 1
		if next_idx >= stages.size():
			continue
		var at_xp := int(stages[next_idx]["xp"])
		if best.is_empty() or at_xp < int(best["at_xp"]):
			best = {
				"at_xp": at_xp,
				"card_id": String(stages[next_idx]["card_id"]),
				"remaining": maxi(0, at_xp - player.xp),
			}
	return best


# --- Internal ---

static func _sync_learns(player: PlayerState, starter_id: String, bal) -> Array:
	var events: Array = []
	var ls: Dictionary = bal.learnset_for(starter_id)
	var filler: Array = ls.get("starter_deck", [])
	var lines: Array = ls.get("lines", [])
	for li in lines.size():
		var stages: Array = lines[li]["stages"]
		var target := _stage_for_xp(stages, player.xp)
		var prev := int(player.learn_progress.get(li, -1))
		if target <= prev:
			continue
		var to_card := String(stages[target]["card_id"])
		var from_card := ""
		var is_upgrade := false
		if prev < 0:
			var base0 := String(stages[0]["card_id"])
			if _count(filler, base0) > 0:
				# Line's base is one of the filler cards — upgrade those copies.
				DeckOps.apply_evolution(player, base0, to_card)
				from_card = base0
				is_upgrade = true
			else:
				DeckOps.add_card_to_deck(player, to_card)
		else:
			from_card = String(player.learn_current.get(li, stages[prev]["card_id"]))
			DeckOps.apply_evolution(player, from_card, to_card)
			is_upgrade = true
		player.learn_progress[li] = target
		player.learn_current[li] = to_card
		events.append({
			"line": String(lines[li].get("name", "")),
			"from": from_card,
			"to": to_card,
			"is_upgrade": is_upgrade,
		})
	return events


## Highest stage index whose xp threshold is <= xp (or -1 if none).
static func _stage_for_xp(stages: Array, xp: int) -> int:
	var target := -1
	for si in stages.size():
		if int(stages[si]["xp"]) <= xp:
			target = si
	return target


static func _count(arr: Array, value: String) -> int:
	var n := 0
	for v in arr:
		if String(v) == value:
			n += 1
	return n
