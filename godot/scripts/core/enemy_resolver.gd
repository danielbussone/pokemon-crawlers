class_name EnemyResolver
## Per-map Pokemon overrides. enemies.json is the shared library; a run segment's
## `enemy_overrides[pokemon_id]` shallow-overrides it for that area only, so the same
## base Pokemon can be tuned differently per placement (e.g. a gym's boss-tier team).

## Effective def = the library def with the segment's override applied. Scalars replace
## individually; array fields (action_pool / boss_pattern) replace wholesale, since the
## editor authors them whole. Returns {} when there is no override for this Pokemon
## (callers then use the library def directly).
static func effective_def(bal, segment: Dictionary, enemy_id: String) -> Dictionary:
	var overrides: Dictionary = segment.get("enemy_overrides", {})
	var ov: Dictionary = overrides.get(enemy_id, {})
	if ov.is_empty():
		return {}
	var eff: Dictionary = bal.enemies.get(enemy_id, {}).duplicate(true)
	for key in ov:
		eff[key] = ov[key]
	return eff
