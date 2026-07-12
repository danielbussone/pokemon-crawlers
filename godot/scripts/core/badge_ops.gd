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
	return _sum(badge_ids, bal, "max_stamina_bonus")


## Sum of `hand_size_bonus` across the given badges.
static func hand_size_bonus(badge_ids: Array, bal) -> int:
	return _sum(badge_ids, bal, "hand_size_bonus")


## Sum of `max_hp_bonus` across the given badges (applied once, on badge grant).
static func max_hp_bonus(badge_ids: Array, bal) -> int:
	return _sum(badge_ids, bal, "max_hp_bonus")


## HP healed at the start of each fight (Rainbow Badge).
static func heal_on_combat_start(badge_ids: Array, bal) -> int:
	return _sum(badge_ids, bal, "heal_on_combat_start")


## True if any badge grants immunity to `status_type` (e.g. Soul → poison).
static func is_status_immune(badge_ids: Array, bal, status_type: String) -> bool:
	for bid in badge_ids:
		if bal.badges.has(bid) and status_type in bal.badges[bid].get("status_immunity", []):
			return true
	return false


static func _sum(badge_ids: Array, bal, field: String) -> int:
	var n := 0
	for bid in badge_ids:
		if bal.badges.has(bid):
			n += int(bal.badges[bid].get(field, 0))
	return n
