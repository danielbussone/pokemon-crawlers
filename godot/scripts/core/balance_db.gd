extends Node
## Autoload "Balance" — loads and validates data/balance/*.json.
## Same data contract as the Python PoC loader.py; fails fast on unknown ids.

const DIR := "res://data/balance"
const StageLayout = preload("res://scripts/world/stage_layout.gd")

var constants: Dictionary = {}
var conditions: Dictionary = {}
var type_chart: Dictionary = {}   # "ATTACKER>DEFENDER" -> float
var cards: Dictionary = {}        # card id -> card dict
var enemies: Dictionary = {}      # enemy id -> enemy dict
var starters: Dictionary = {}     # starter id -> starter dict
var badges: Dictionary = {}       # badge id -> badge dict
var items: Dictionary = {}        # item id -> item dict (insertion order = shop order)
var economy: Dictionary = {}      # {center, inventory, gold}
var run_config: Dictionary = {}
var stage_rewards: Dictionary = {}
var stage_layouts: Dictionary = {}  # stage_id -> layout dict
var sprite_tuning: Dictionary = {}
var learnsets: Dictionary = {}     # starter id -> {starter_deck, lines}


func _ready() -> void:
	constants = _load_json("constants")
	conditions = _load_json("conditions")
	run_config = _load_json("run_config")
	stage_rewards = _load_json("stage_rewards")
	var layouts_raw: Dictionary = _load_json("stage_layouts")
	stage_layouts = layouts_raw.get("stages", {})
	sprite_tuning = _load_json("sprite_tuning")
	starters = _load_json("starters")
	learnsets = _load_json("learnsets")
	badges = _load_json("badges")

	for m in _load_json("type_chart")["matchups"]:
		type_chart["%s>%s" % [m["attacker"], m["defender"]]] = float(m["multiplier"])
	for c in _load_json("cards")["cards"]:
		cards[c["id"]] = c
	for e in _load_json("enemies")["enemies"]:
		enemies[e["id"]] = e

	var items_raw: Dictionary = _load_json("items")
	for it in items_raw["items"]:
		items[it["id"]] = it
	economy = {
		"center": items_raw["center"],
		"inventory": items_raw["inventory"],
		"gold": items_raw["gold"],
	}
	_validate()


# --- Convenience accessors (constants.json) ---

func max_hp() -> int:
	return int(constants["player"]["max_hp"])


func max_stamina() -> int:
	return int(constants["player"]["max_stamina"])


func hand_size() -> int:
	return int(constants["player"]["hand_size"])


func confuse_self_dmg() -> int:
	return int(constants["combat"]["confuse_self_dmg"])


func draft_options() -> int:
	return int(constants["rewards"]["draft_options"])


func stab_chance() -> float:
	return float(constants["rewards"]["starter_stab_draft_chance"])


func xp_per_wild() -> int:
	return int(constants["xp"]["per_wild"])


func xp_per_mid_boss() -> int:
	return int(constants["xp"]["per_mid_boss"])


func xp_per_gym_boss() -> int:
	return int(constants["xp"]["per_gym_boss"])


func learnset_for(starter_id: String) -> Dictionary:
	return learnsets.get(starter_id, {})


func type_mod(attacker_type: String, defender_type: String) -> float:
	return float(type_chart.get(attacker_type + ">" + defender_type, 1.0))


## Per-species billboard tuning for world sprites (wild encounters + trainer partners).
func sprite_tuning_for(species_id: String) -> Dictionary:
	var defaults: Dictionary = sprite_tuning.get("defaults", {})
	var species: Dictionary = sprite_tuning.get("species", {}).get(species_id, {})
	return {
		"wild_scale": float(species.get("wild_scale", defaults.get("wild_scale", 1.0))),
		"companion_scale": float(species.get("companion_scale", defaults.get("companion_scale", 1.0))),
		"flying": bool(species.get("flying", defaults.get("flying", false))),
		"fly_height": float(species.get("fly_height", defaults.get("fly_height", 0.85))),
	}


# --- Loading / validation ---

func _load_json(base_name: String) -> Dictionary:
	var path := "%s/%s.json" % [DIR, base_name]
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "Missing balance file: " + path)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "Invalid JSON in " + path)
	return parsed


func _validate() -> void:
	for sid in starters:
		for cid in starters[sid]["deck"]:
			assert(cards.has(cid), "Unknown card '%s' in starter '%s'" % [cid, sid])
	for cid in cards:
		var evolves_to := String(cards[cid].get("evolves_to", ""))
		assert(evolves_to == "" or cards.has(evolves_to),
				"Card '%s' evolves_to unknown card '%s'" % [cid, evolves_to])
	_validate_learnsets()
	for pool_key in stage_rewards:
		for cid in stage_rewards[pool_key]:
			assert(cards.has(cid), "Unknown card '%s' in stage_rewards '%s'" % [cid, pool_key])
	for eid in run_config["pewter_encounter_sequence"]:
		assert(enemies.has(eid), "Unknown enemy '%s' in pewter sequence" % eid)
	for stage in run_config["stages"]:
		for eid in stage["wild_pool"]:
			assert(enemies.has(eid), "Unknown enemy '%s' in stage '%s'" % [eid, stage["id"]])
	assert(cards.has(run_config["signature_card"]), "Unknown signature card")
	assert(cards.has(run_config["evolution"]["from"]), "Unknown evolution.from card")
	assert(cards.has(run_config["evolution"]["to"]), "Unknown evolution.to card")
	assert(badges.has(run_config["badge_id"]), "Unknown badge id")
	StageLayout.validate(self)


## Every learnset references real cards, and each starter has a learnset.
func _validate_learnsets() -> void:
	for sid in starters:
		assert(learnsets.has(sid), "Missing learnset for starter '%s'" % sid)
	for sid in learnsets:
		if String(sid).begins_with("_"):
			continue  # documentation keys (e.g. _comment)
		var entry: Dictionary = learnsets[sid]
		for cid in entry.get("starter_deck", []):
			assert(cards.has(cid), "Unknown card '%s' in learnset '%s' starter_deck" % [cid, sid])
		var prev_xp := -1
		for line in entry.get("lines", []):
			for stage in line["stages"]:
				var cid := String(stage["card_id"])
				assert(cards.has(cid), "Unknown card '%s' in learnset '%s'" % [cid, sid])
				assert(int(stage["xp"]) >= 0, "Negative xp in learnset '%s'" % sid)
			# Stages within a line must be non-decreasing in XP.
			prev_xp = -1
			for stage in line["stages"]:
				var xp := int(stage["xp"])
				assert(xp >= prev_xp, "Line '%s' in '%s' has out-of-order XP" % [
						String(line.get("name", "?")), sid])
				prev_xp = xp
