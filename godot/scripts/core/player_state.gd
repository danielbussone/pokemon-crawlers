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
## XP learnset (Phase 1). `xp` accrues from fights; `learn_progress`/`learn_current`
## track, per learnset line index, the highest unlocked stage and the card that
## line currently contributes to the deck (so upgrades can replace it).
var xp: int = 0
var learn_progress: Dictionary = {}   # line_index -> highest stage index applied
var learn_current: Dictionary = {}    # line_index -> current card_id in deck
