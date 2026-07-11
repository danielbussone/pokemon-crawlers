class_name StarterEvo
## Starter typed-card evolution (Phase 3): starter-line cards deal more damage
## once the run's XP crosses configured milestones (paced to ~Gym 2 and ~Gym 5).
## Multipliers stack multiplicatively per crossed tier. Applied at damage time in
## effects.gd; the thresholds live in constants.json under `starter_evolution`.


## How many milestone tiers the given XP total has crossed.
static func tier(xp: int, bal) -> int:
	var count := 0
	for t in bal.starter_evolution_tiers():
		if xp >= int(t["at_xp"]):
			count += 1
	return count


## Combined starter-line damage multiplier for the player's current XP.
static func damage_mult(player: PlayerState, bal) -> float:
	var mult := 1.0
	for t in bal.starter_evolution_tiers():
		if player.xp >= int(t["at_xp"]):
			mult *= float(t["damage_mult"])
	return mult


## Multiplier to apply to a specific card: the starter-evolution bonus if the
## card belongs to this run's starter line, otherwise 1.0 (no change).
static func card_damage_mult(card: Dictionary, player: PlayerState, bal) -> float:
	if player == null or player.starter_id == "":
		return 1.0
	if bal.starter_line_cards(player.starter_id).has(String(card.get("id", ""))):
		return damage_mult(player, bal)
	return 1.0
