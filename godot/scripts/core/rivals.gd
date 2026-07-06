class_name Rivals
## Stage 1 Rival selection — counter-type vs player starter (port of rivals.py).

const RIVAL_SENTINEL := "rival_blue"

const COUNTER_RIVAL_BY_STARTER := {
	"charmander": "rival_squirtle",
	"squirtle": "rival_bulbasaur",
	"bulbasaur": "rival_charmander",
}


static func resolve_rival_enemy_id(starter_id: String) -> String:
	return String(COUNTER_RIVAL_BY_STARTER.get(starter_id, "rival_squirtle"))


static func is_rival_enemy(enemy_id: String) -> bool:
	return enemy_id == RIVAL_SENTINEL or enemy_id.begins_with("rival_")
