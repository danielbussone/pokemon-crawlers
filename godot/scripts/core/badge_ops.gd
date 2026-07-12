class_name BadgeOps
## Typed badge passives (Phase 5b). Each earned badge grants a distinct run-long
## buff, read from badges.json. This aggregates the buffs across a player's badges
## at the point they're applied (damage, stamina, …). New passive fields plug in
## here + at their one apply site; badges without a field contribute the identity.


## Product of `outgoing_damage_mult` across the given badges (attacker's).
static func outgoing_mult(badge_ids: Array, bal) -> float:
	var m := 1.0
	for bid in badge_ids:
		if bal.badges.has(bid):
			m *= float(bal.badges[bid].get("outgoing_damage_mult", 1.0))
	return m


## Product of `incoming_damage_mult` across the given badges (defender's).
static func incoming_mult(badge_ids: Array, bal) -> float:
	var m := 1.0
	for bid in badge_ids:
		if bal.badges.has(bid):
			m *= float(bal.badges[bid].get("incoming_damage_mult", 1.0))
	return m


## Sum of `max_stamina_bonus` across the given badges.
static func max_stamina_bonus(badge_ids: Array, bal) -> int:
	var n := 0
	for bid in badge_ids:
		if bal.badges.has(bid):
			n += int(bal.badges[bid].get("max_stamina_bonus", 0))
	return n
