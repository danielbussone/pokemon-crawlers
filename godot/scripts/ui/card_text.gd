class_name CardText
## Shared text formatting for cards, items, statuses across UI screens.


static func summary(card: Dictionary, enemy_type: String, bal) -> String:
	var parts: Array[String] = []
	for eff in card["effects"]:
		match String(eff.get("type", "")):
			"damage":
				var text := "Deal %d" % int(eff.get("magnitude", 0))
				if enemy_type != "":
					var mult: float = bal.type_mod(String(card["pokemon_type"]), enemy_type)
					if mult > 1.0:
						text += " (x2!)"
					elif mult < 1.0:
						text += " (x0.5)"
				parts.append(text)
			"block":
				parts.append("Block %d" % int(eff.get("magnitude", 0)))
			"heal":
				parts.append("Heal %d" % int(eff.get("magnitude", 0)))
			"status":
				var status := String(eff.get("status", ""))
				if status == "poison":
					parts.append("Poison %d/turn (%dt)" % [int(eff.get("magnitude", 0)), int(eff.get("duration", 0))])
				else:
					parts.append("%s (%dt)" % [status.capitalize(), int(eff.get("duration", 0))])
			"apply_condition":
				parts.append(String(eff.get("condition", "")).capitalize())
			"draw":
				parts.append("Draw %d" % int(eff.get("magnitude", 0)))
			"shuffle_hand":
				parts.append("Shuffle hand")
	return ", ".join(parts)


static func item_description(item: Dictionary) -> String:
	var effect: Dictionary = item["effect"]
	match String(effect.get("type", "")):
		"heal":
			return "Heal %d HP" % int(effect.get("magnitude", 0))
		"cure_status":
			return "Cures %s" % String(effect.get("status", "?"))
		"cure_all_statuses":
			return "Cures all statuses"
		"revive":
			return "Revive at 0 HP (not usable in combat)"
	return ""


static func status_line(c: Combatant) -> String:
	var parts: Array[String] = []
	for s in c.statuses:
		if s["type"] == "poison":
			parts.append("Poison %d (%dt)" % [int(s["magnitude"]), int(s["turns"])])
		else:
			parts.append("%s (%dt)" % [String(s["type"]).capitalize(), int(s["turns"])])
	for cond in c.conditions:
		parts.append("%s (%dt)" % [String(cond["id"]).capitalize(), int(cond["turns"])])
	if c.blinded_budget >= 0:
		parts.append("Blinded (%d)" % c.blinded_budget)
	if parts.is_empty():
		return "No effects"
	return " | ".join(parts)
