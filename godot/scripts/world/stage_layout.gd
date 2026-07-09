## Reads stage_layouts.json and exposes maze/open-area geometry for world_builder.
## JSON coords: +x east, +y south. World grid: +x east, +y south (north = decreasing y).

const VALID_TEMPLATES := [
	"open_field",
	"forest_maze",
	"cave_branches",
	"town_pocket",
	"gym_arena",
]

const VALID_FACINGS := ["north", "east", "south", "west"]


static func local_to_world(local_cell: Vector2i, stage_origin: Vector2i) -> Vector2i:
	return stage_origin + local_cell


static func world_to_local(world: Vector2i, stage_origin: Vector2i) -> Vector2i:
	return world - stage_origin


static func vec2_from_json(pair: Array) -> Vector2i:
	assert(pair.size() >= 2, "Expected [x, y] coordinate pair")
	return Vector2i(int(pair[0]), int(pair[1]))


static func layout_for(bal, stage_id: String) -> Dictionary:
	var layouts: Dictionary = bal.stage_layouts
	assert(layouts.has(stage_id), "Missing stage layout for '%s'" % stage_id)
	return layouts[stage_id]


static func spawn_local(bal, stage_id: String) -> Vector2i:
	return vec2_from_json(layout_for(bal, stage_id)["spawn"])


static func spawn_world(bal, stage_id: String, stage_origin: Vector2i) -> Vector2i:
	return local_to_world(spawn_local(bal, stage_id), stage_origin)


static func gate_local(bal, stage_id: String) -> Dictionary:
	var gate: Dictionary = layout_for(bal, stage_id)["gate"]
	return {
		"trigger": vec2_from_json(gate["trigger"]),
		"encounter": vec2_from_json(gate["encounter"]),
		"facing": String(gate.get("facing", "north")),
	}


static func optional_spawns_local(bal, stage_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in layout_for(bal, stage_id)["optional_spawns"]:
		out.append({
			"trigger": vec2_from_json(entry["trigger"]),
			"encounter": vec2_from_json(entry["encounter"]),
		})
	return out


static func funnel_cells_local(bal, stage_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for pair in layout_for(bal, stage_id)["funnel_cells"]:
		out.append(vec2_from_json(pair))
	return out


static func shop_cells_local(bal, stage_id: String) -> Dictionary:
	var shops: Dictionary = layout_for(bal, stage_id).get("shops", {})
	var out := {}
	if shops.has("center"):
		out["center"] = vec2_from_json(shops["center"])
	if shops.has("mart"):
		out["mart"] = vec2_from_json(shops["mart"])
	return out


static func shop_windows_local(bal, stage_id: String) -> Dictionary:
	var raw: Dictionary = layout_for(bal, stage_id).get("shop_windows", {})
	var out := {}
	if raw.has("center"):
		out["center"] = int(raw["center"])
	if raw.has("mart"):
		out["mart"] = int(raw["mart"])
	return out


static func gym_door_local(bal, stage_id: String) -> Vector2i:
	var door = layout_for(bal, stage_id).get("gym_door", null)
	if door == null:
		return Vector2i(-1, -1)
	return vec2_from_json(door)


static func blocked_cells_local(bal, stage_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for pair in layout_for(bal, stage_id).get("blocked_cells", []):
		out.append(vec2_from_json(pair))
	return out


static func gym_floor_cells_local(bal, stage_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for pair in layout_for(bal, stage_id).get("gym_floor_cells", []):
		out.append(vec2_from_json(pair))
	return out


static func exit_local(bal, stage_id: String) -> Vector2i:
	return vec2_from_json(layout_for(bal, stage_id)["exit"])


static func size_local(bal, stage_id: String) -> Vector2i:
	return vec2_from_json(layout_for(bal, stage_id)["size"])


static func template_id(bal, stage_id: String) -> String:
	return String(layout_for(bal, stage_id).get("template", "open_field"))


static func stage_ids_in_order(bal) -> Array[String]:
	var out: Array[String] = []
	for stage in bal.run_config["stages"]:
		out.append(String(stage["id"]))
	out.append("pewter")
	return out


static func validate(bal) -> void:
	var layouts: Dictionary = bal.stage_layouts
	for stage in bal.run_config["stages"]:
		var stage_id := String(stage["id"])
		_validate_stage(layouts, stage_id, int(stage["wild_count"]))
	_validate_stage(layouts, "pewter", _pewter_optional_count(bal))


static func _pewter_optional_count(bal) -> int:
	var count := 0
	for enemy_id in bal.run_config["pewter_encounter_sequence"]:
		if not bool(bal.enemies[String(enemy_id)].get("is_boss", false)):
			count += 1
	return count


static func _validate_stage(layouts: Dictionary, stage_id: String, expected_optionals: int) -> void:
	assert(layouts.has(stage_id), "Missing stage layout for '%s'" % stage_id)
	var layout: Dictionary = layouts[stage_id]
	assert(String(layout.get("id", "")) == stage_id, "Layout id mismatch for '%s'" % stage_id)
	var template := String(layout.get("template", ""))
	assert(template in VALID_TEMPLATES, "Unknown template '%s' in stage '%s'" % [template, stage_id])

	var size := vec2_from_json(layout["size"])
	assert(size.x > 0 and size.y > 0, "Invalid size for stage '%s'" % stage_id)

	var gate: Dictionary = layout["gate"]
	vec2_from_json(gate["trigger"])
	vec2_from_json(gate["encounter"])
	var facing := String(gate.get("facing", "north"))
	assert(facing in VALID_FACINGS, "Invalid gate facing '%s' in stage '%s'" % [facing, stage_id])

	var optionals: Array = layout["optional_spawns"]
	assert(optionals.size() == expected_optionals,
			"Stage '%s' expects %d optional spawns, layout has %d" % [
				stage_id, expected_optionals, optionals.size()])
	for entry in optionals:
		vec2_from_json(entry["trigger"])
		vec2_from_json(entry["encounter"])

	for pair in layout["funnel_cells"]:
		vec2_from_json(pair)

	vec2_from_json(layout["spawn"])
	vec2_from_json(layout["exit"])

	for pair in layout.get("blocked_cells", []):
		vec2_from_json(pair)

	for pair in layout.get("gym_floor_cells", []):
		vec2_from_json(pair)

	var gym_door = layout.get("gym_door", null)
	if gym_door != null:
		vec2_from_json(gym_door)

	var shops: Dictionary = layout.get("shops", {})
	if shops.has("center"):
		vec2_from_json(shops["center"])
	if shops.has("mart"):
		vec2_from_json(shops["mart"])
