class_name TrainerOps
## A trainer is a person (name + portrait) who fields real Pokemon. The team fought
## is a per-placement spec; the trainer is just who's standing there. See docs +
## data/balance/trainers.json.

## Resolve a team spec to the Pokemon fought, in order.
## `mode` "one_of" -> a single random pick; anything else ("sequential") -> the list.
static func resolve_team(team: Array, mode: String, rng: RandomNumberGenerator) -> Array:
	if team.is_empty():
		return []
	if mode == "one_of":
		return [String(team[rng.randi_range(0, team.size() - 1)])]
	var out: Array = []
	for id in team:
		out.append(String(id))
	return out


## Trainer display name; falls back to the id when there's no identity entry.
static func trainer_name(bal, trainer_id: String) -> String:
	var t: Dictionary = bal.trainers.get(trainer_id, {})
	return String(t.get("name", trainer_id))


## Art id for a trainer's portrait; falls back to the trainer id itself.
static func portrait_of(bal, trainer_id: String) -> String:
	var t: Dictionary = bal.trainers.get(trainer_id, {})
	return String(t.get("portrait_id", trainer_id))
