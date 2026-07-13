## Reads stage_layouts.json and exposes maze/open-area geometry for world_builder.
## JSON coords: +x east, +y south. World grid: +x east, +y south (north = decreasing y).
##
## Phase 5 map format: geometry is a `grid` of equal-length strings. This file
## parses each grid once (cached) into the same cell structures the builder has
## always consumed, so world_builder is unchanged. Encounter placement lives in
## the grid (`w` optional wilds, `L` leader gate); a leader's trigger cell and
## north facing are derived from the south→north arc.

const VALID_TEMPLATES := [
	"open_field",
	"forest_maze",
	"cave_branches",
	"town_pocket",
	"gym_arena",
	"big_city",
	"ship_interior",
	"corporate",
	"mansion",
	"volcanic",
	"bridge",
	"plateau",
]

const VALID_FACINGS := ["north", "east", "south", "west"]

const BARRIER_CHARS := ["#", "T", "H", "^", "B", "b", "+", "O", "~", "*", "I"]

## Parsed grids, keyed by stage_id. Balance data loads once per session, so this
## stays valid for the whole run.
static var _cache: Dictionary = {}


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


## Parse (and cache) a stage's grid into cell structures.
static func parsed(bal, stage_id: String) -> Dictionary:
	if _cache.has(stage_id):
		return _cache[stage_id]
	var layout := layout_for(bal, stage_id)
	var grid: Array = layout["grid"]
	var h := grid.size()
	var w := String(grid[0]).length()

	var walkable := {}
	var blocked: Array[Vector2i] = []
	var optionals: Array[Vector2i] = []
	var gym_floor: Array[Vector2i] = []
	var shops := {}
	var spawn := Vector2i(-1, -1)
	var exit_cell := Vector2i(-1, -1)
	var leader := Vector2i(-1, -1)
	var gym_door := Vector2i(-1, -1)
	# Cosmetic terrain material per cell (Phase 7): override char, else theme default.
	# `material` = the cell itself (barrier prop for barriers); `floor_material` =
	# the ground rendered under it (theme ground under a tree, theme floor under `_`).
	var theme := String(layout.get("template", "open_field"))
	var material := {}
	var floor_material := {}

	for y in h:
		var row := String(grid[y])
		for x in w:
			var ch := row[x]
			var cell := Vector2i(x, y)
			material[cell] = ThemePalette.material_for(theme, ch)
			if ch == "_":
				floor_material[cell] = ThemePalette.theme_floor(theme)
			elif ch in BARRIER_CHARS:
				floor_material[cell] = ThemePalette.theme_ground(theme)
			else:
				floor_material[cell] = material[cell]
			if ch in BARRIER_CHARS:
				blocked.append(cell)
				continue
			walkable[cell] = true
			match ch:
				"S": spawn = cell
				"X": exit_cell = cell
				"c": shops["center"] = cell
				"m": shops["mart"] = cell
				"w": optionals.append(cell)
				"L": leader = cell
				"D": gym_door = cell
				"_": gym_floor.append(cell)

	# Final stage: the leader sits on the (unused) exit cell.
	if exit_cell == Vector2i(-1, -1):
		exit_cell = leader

	var result := {
		"size": Vector2i(w, h),
		"walkable": walkable,
		"blocked": blocked,
		"spawn": spawn,
		"exit": exit_cell,
		"leader": leader,
		"shops": shops,
		"optionals": optionals,
		"gym_door": gym_door,
		"gym_floor": gym_floor,
		"material": material,
		"floor_material": floor_material,
	}
	_cache[stage_id] = result
	return result


static func spawn_local(bal, stage_id: String) -> Vector2i:
	return parsed(bal, stage_id)["spawn"]


static func spawn_world(bal, stage_id: String, stage_origin: Vector2i) -> Vector2i:
	return local_to_world(spawn_local(bal, stage_id), stage_origin)


static func gate_local(bal, stage_id: String) -> Dictionary:
	var leader: Vector2i = parsed(bal, stage_id)["leader"]
	return {
		# South-of-leader is the approach tile; the arc always faces north.
		"trigger": leader + Vector2i(0, 1),
		"encounter": leader,
		"facing": String(layout_for(bal, stage_id).get("gate_facing", "north")),
	}


static func optional_spawns_local(bal, stage_id: String) -> Array[Dictionary]:
	var p := parsed(bal, stage_id)
	var out: Array[Dictionary] = []
	for cell in p["optionals"]:
		out.append({"trigger": _walkable_neighbor(p, cell), "encounter": cell})
	return out


## A walkable neighbor of `cell` to serve as the encounter's approach tile.
static func _walkable_neighbor(p: Dictionary, cell: Vector2i) -> Vector2i:
	for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if p["walkable"].has(cell + dir):
			return cell + dir
	return cell


static func shop_cells_local(bal, stage_id: String) -> Dictionary:
	return parsed(bal, stage_id)["shops"].duplicate()


static func shop_windows_local(bal, stage_id: String) -> Dictionary:
	var raw: Dictionary = layout_for(bal, stage_id).get("shop_windows", {})
	var out := {}
	if raw.has("center"):
		out["center"] = int(raw["center"])
	if raw.has("mart"):
		out["mart"] = int(raw["mart"])
	return out


static func gym_door_local(bal, stage_id: String) -> Vector2i:
	return parsed(bal, stage_id)["gym_door"]


static func blocked_cells_local(bal, stage_id: String) -> Array[Vector2i]:
	return parsed(bal, stage_id)["blocked"].duplicate()


static func gym_floor_cells_local(bal, stage_id: String) -> Array[Vector2i]:
	return parsed(bal, stage_id)["gym_floor"].duplicate()


## local cell -> cosmetic material name (barrier prop / ground) (Phase 7).
static func material_local(bal, stage_id: String) -> Dictionary:
	return parsed(bal, stage_id)["material"]


## local cell -> floor material rendered under the cell (Phase 7 slice 2).
static func floor_material_local(bal, stage_id: String) -> Dictionary:
	return parsed(bal, stage_id)["floor_material"]


static func exit_local(bal, stage_id: String) -> Vector2i:
	return parsed(bal, stage_id)["exit"]


static func size_local(bal, stage_id: String) -> Vector2i:
	return parsed(bal, stage_id)["size"]


static func template_id(bal, stage_id: String) -> String:
	return String(layout_for(bal, stage_id).get("template", "open_field"))


static func display_name(bal, stage_id: String) -> String:
	return String(layout_for(bal, stage_id).get("display_name", ""))


## Zone title for the gym interior of whichever stage is a gym (the one with a
## `gym_name`). Falls back to a generic label.
static func gym_display_name(bal) -> String:
	for stage_id in bal.stage_layouts:
		var name := String(bal.stage_layouts[stage_id].get("gym_name", ""))
		if name != "":
			return name
	return "Gym"


static func stage_ids_in_order(bal) -> Array[String]:
	var out: Array[String] = []
	for segment in bal.run_config["segments"]:
		out.append(String(segment["id"]))
	return out


## How many optional wilds a stage places (one per `w` cell). The run builder
## draws that many species from the segment's wild pool.
static func optional_count(bal, stage_id: String) -> int:
	return parsed(bal, stage_id)["optionals"].size()


static func validate(bal) -> void:
	var layouts: Dictionary = bal.stage_layouts
	for segment in bal.run_config["segments"]:
		_validate_stage(bal, layouts, String(segment["id"]))


static func _validate_stage(bal, layouts: Dictionary, stage_id: String) -> void:
	assert(layouts.has(stage_id), "Missing stage layout for '%s'" % stage_id)
	var layout: Dictionary = layouts[stage_id]
	assert(String(layout.get("id", "")) == stage_id, "Layout id mismatch for '%s'" % stage_id)
	var template := String(layout.get("template", ""))
	assert(template in VALID_TEMPLATES, "Unknown template '%s' in stage '%s'" % [template, stage_id])
	assert(String(layout.get("gate_facing", "north")) in VALID_FACINGS,
			"Invalid gate_facing in stage '%s'" % stage_id)

	var grid: Array = layout.get("grid", [])
	assert(not grid.is_empty(), "Stage '%s' has no grid" % stage_id)
	var width := String(grid[0]).length()
	assert(width > 0, "Stage '%s' grid row 0 is empty" % stage_id)
	var s_count := 0
	var l_count := 0
	for row_v in grid:
		var row := String(row_v)
		assert(row.length() == width, "Stage '%s' has ragged grid rows" % stage_id)
		s_count += row.count("S")
		l_count += row.count("L")
	assert(s_count == 1, "Stage '%s' must have exactly one spawn (S), found %d" % [stage_id, s_count])
	assert(l_count == 1, "Stage '%s' must have exactly one leader (L), found %d" % [stage_id, l_count])

	# Reachability: spawn must reach the leader, and no optional wild may be sealed.
	var p := parsed(bal, stage_id)
	var reached := _flood(p, p["spawn"])
	assert(reached.has(p["leader"]), "Stage '%s': leader unreachable from spawn" % stage_id)
	for opt in p["optionals"]:
		assert(reached.has(opt), "Stage '%s': optional wild at %s is sealed off" % [stage_id, opt])


static func _flood(p: Dictionary, start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var n: Vector2i = cell + dir
			if p["walkable"].has(n) and not seen.has(n):
				seen[n] = true
				frontier.append(n)
	return seen
