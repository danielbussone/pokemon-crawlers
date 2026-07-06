class_name PlayerState
extends Combatant
## Player run state (mirrors models.PlayerState).

var base_max_stamina: int = 3
var max_stamina: int = 3
var current_stamina: int = 3
var stamina_bonus_next_turn: int = 0
var deck: Array[String] = []
var hand: Array[String] = []
var discard: Array[String] = []
var badge_ids: Array[String] = []
var gold: int = 0
var inventory: Array[String] = []
var center_visits: int = 0
