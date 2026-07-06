class_name Combatant
extends RefCounted
## Shared combat state (mirrors models.Combatant).

var hp: int = 0
var max_hp: int = 0
var ptype: String = "NORMAL"
var block: int = 0
var statuses: Array[Dictionary] = []    # {"type": String, "turns": int, "magnitude": int}
var conditions: Array[Dictionary] = []  # {"id": String, "turns": int}
var blinded_budget: int = -1            # -1 = not blinded
