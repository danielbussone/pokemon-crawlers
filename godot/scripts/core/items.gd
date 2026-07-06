class_name Items
## Consumable item effects and in-combat use (port of items.py).


static func count_inventory_item(player: PlayerState, item_id: String) -> int:
	var count := 0
	for entry in player.inventory:
		if entry == item_id:
			count += 1
	return count


static func inventory_has_room(player: PlayerState, item_id: String, bal) -> bool:
	if player.inventory.size() >= int(bal.economy["inventory"]["max_slots"]):
		return false
	if count_inventory_item(player, item_id) >= int(bal.economy["inventory"]["max_per_item"]):
		return false
	return true


static func add_item_to_inventory(player: PlayerState, item_id: String, bal) -> bool:
	if not inventory_has_room(player, item_id, bal):
		return false
	player.inventory.append(item_id)
	return true


static func remove_item_from_inventory(player: PlayerState, item_id: String) -> bool:
	var index := player.inventory.find(item_id)
	if index < 0:
		return false
	player.inventory.remove_at(index)
	return true


## Returns {"ok": bool, "reason": String}
static func apply_item_effect(player: PlayerState, item: Dictionary) -> Dictionary:
	var effect: Dictionary = item["effect"]
	var effect_type := String(effect.get("type", ""))

	if effect_type == "heal":
		if player.hp >= player.max_hp:
			return {"ok": false, "reason": "Already at full HP."}
		player.hp = mini(player.max_hp, player.hp + int(effect.get("magnitude", 0)))
		return {"ok": true, "reason": ""}

	if effect_type == "cure_status":
		if not effect.has("status"):
			return {"ok": false, "reason": "Invalid item effect."}
		var status := String(effect["status"])
		if not Effects.has_status(player, status):
			return {"ok": false, "reason": "No %s to cure." % status}
		var remaining: Array[Dictionary] = []
		for entry in player.statuses:
			if entry["type"] != status:
				remaining.append(entry)
		player.statuses = remaining
		return {"ok": true, "reason": ""}

	if effect_type == "cure_all_statuses":
		if player.statuses.is_empty():
			return {"ok": false, "reason": "No statuses to cure."}
		player.statuses.clear()
		return {"ok": true, "reason": ""}

	if effect_type == "revive":
		if player.hp > 0:
			return {"ok": false, "reason": "Can only use Revive at 0 HP."}
		player.hp = maxi(1, int(player.max_hp * int(effect.get("magnitude", 0)) / 100.0))
		return {"ok": true, "reason": ""}

	return {"ok": false, "reason": "Unknown item effect."}


static func use_item_in_combat(player: PlayerState, item_id: String, bal,
		items_used_this_turn: int) -> Dictionary:
	if items_used_this_turn >= 1:
		return {"ok": false, "reason": "Already used an item this turn."}
	if not bal.items.has(item_id):
		return {"ok": false, "reason": "Unknown item."}

	var item: Dictionary = bal.items[item_id]
	if not bool(item.get("in_combat", false)):
		return {"ok": false, "reason": "Item cannot be used in combat."}
	if count_inventory_item(player, item_id) < 1:
		return {"ok": false, "reason": "Item not in inventory."}

	var result := apply_item_effect(player, item)
	if result["ok"]:
		remove_item_from_inventory(player, item_id)
	return result
