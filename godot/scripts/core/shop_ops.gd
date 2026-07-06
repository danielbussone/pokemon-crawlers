class_name ShopOps
## Pokémon Center and Poké Mart purchases (port of shop.py).


static func items_for_shop_window(bal, shop_window: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item_id in bal.items:
		var item: Dictionary = bal.items[item_id]
		for w in item["shop_windows"]:
			if int(w) == shop_window:
				out.append(item)
				break
	return out


static func can_afford(player: PlayerState, cost: int) -> bool:
	return player.gold >= cost


## Full heal + max HP bonus. Returns true if purchased.
static func purchase_center(player: PlayerState, bal) -> bool:
	var cost := int(bal.economy["center"]["cost"])
	if not can_afford(player, cost):
		return false
	player.gold -= cost
	player.max_hp += int(bal.economy["center"]["max_hp_bonus"])
	player.hp = player.max_hp
	player.center_visits += 1
	return true


## Returns {"ok": bool, "reason": String}
static func purchase_item(player: PlayerState, item_id: String, bal) -> Dictionary:
	if not bal.items.has(item_id):
		return {"ok": false, "reason": "Unknown item."}
	var item: Dictionary = bal.items[item_id]
	if not can_afford(player, int(item["cost"])):
		return {"ok": false, "reason": "Not enough gold."}
	if not Items.inventory_has_room(player, item_id, bal):
		return {"ok": false, "reason": "No inventory room."}
	player.gold -= int(item["cost"])
	Items.add_item_to_inventory(player, item_id, bal)
	return {"ok": true, "reason": ""}
