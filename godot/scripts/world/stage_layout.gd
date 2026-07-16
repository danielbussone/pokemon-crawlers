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


## Normalized cell rows: an Array of rows, each an Array of cell dicts
## {g: glyph, m: material override ("" = inherit), surf: bool}. Reads the
## structured `cells` format (each entry a bare glyph string or an object),
## falling back to the legacy `grid` (row strings of single glyph chars). This is
## the one place the two on-disk shapes converge; everything else works off the
## glyph `g` (unchanged semantics) plus these per-cell dicts.
static func cell_rows(layout: Dictionary) -> Array:
	var out: Array = []
	if layout.has("cells"):
		# A row is either a plain glyph string (compact: no overrides) or an array of
		# cells (each a bare glyph string or a {g, m, ...} object).
		for row_v in layout["cells"]:
			var row: Array = []
			if row_v is String:
				for ch in String(row_v):
					row.append(_norm_cell(ch))
			else:
				for entry in row_v:
					row.append(_norm_cell(entry))
			out.append(row)
	else:
		for row_v in layout.get("grid", []):
			var row: Array = []
			for ch in String(row_v):
				row.append(_norm_cell(ch))
			out.append(row)
	return out


static func _norm_cell(entry) -> Dictionary:
	if entry is Dictionary:
		return {
			"g": String(entry.get("g", ".")),
			"m": String(entry.get("m", "")),
			"surf": bool(entry.get("surf", false)),
		}
	return {"g": String(entry), "m": "", "surf": false}


## Bare-glyph rows (each cell's `g`, joined) — the "simplified" ASCII view, used by
## the char-counting validators and as the editor's readable export.
static func glyph_rows(layout: Dictionary) -> Array:
	var out: Array = []
	for row in cell_rows(layout):
		var s := ""
		for c in row:
			s += String(c["g"])
		out.append(s)
	return out


## Parse (and cache) a stage's grid into cell structures.
static func parsed(bal, stage_id: String) -> Dictionary:
	if _cache.has(stage_id):
		return _cache[stage_id]
	var layout := layout_for(bal, stage_id)
	var rows := cell_rows(layout)
	var h := rows.size()
	var w: int = (rows[0] as Array).size() if h > 0 else 0

	var walkable := {}
	var blocked: Array[Vector2i] = []
	var optionals: Array[Vector2i] = []
	var trainer_cells: Array[Vector2i] = []
	var gym_floor: Array[Vector2i] = []
	var shops := {}
	var spawn := Vector2i(-1, -1)
	var exit_cell := Vector2i(-1, -1)
	var leader := Vector2i(-1, -1)
	var gym_door := Vector2i(-1, -1)
	var surf := {}
	# Cosmetic terrain material per cell (Phase 7): a per-cell `m` override wins,
	# else the override char, else the theme default. `material` = the cell itself
	# (barrier prop for barriers, floor tint for walkable); `floor_material` = the
	# ground rendered under it (theme ground under a tree, theme floor under `_`).
	var theme := String(layout.get("template", "open_field"))
	var material := {}
	var floor_material := {}

	for y in h:
		var row: Array = rows[y]
		for x in row.size():
			var c: Dictionary = row[x]
			var g := String(c["g"])
			var override_mat := String(c["m"])
			var cell := Vector2i(x, y)
			var mat := override_mat if override_mat != "" else ThemePalette.material_for(theme, g)
			material[cell] = mat
			if g == "_":
				floor_material[cell] = ThemePalette.theme_floor(theme)
			elif g in BARRIER_CHARS:
				floor_material[cell] = ThemePalette.theme_ground(theme)
			else:
				floor_material[cell] = mat
			if g in BARRIER_CHARS:
				blocked.append(cell)
				continue
			walkable[cell] = true
			# Surf water is walkable ground gated by a surf ability (glyph `s`, or an
			# explicit surf flag). Recorded so is_walkable can enforce it later.
			if g == "s" or bool(c["surf"]):
				surf[cell] = true
			match g:
				"S": spawn = cell
				"X": exit_cell = cell
				"c": shops["center"] = cell
				"m": shops["mart"] = cell
				"w": optionals.append(cell)
				"t": trainer_cells.append(cell)
				"L": leader = cell
				"D": gym_door = cell
				"_": gym_floor.append(cell)

	# `exit_gate` is the authored `X` and nothing else — it is the cell this stage's
	# leader holds shut. `exit` keeps the legacy meaning (falling back to the leader
	# when a stage has no `X`) for the pre-world_pos telescope walk.
	var exit_gate := exit_cell
	if exit_cell == Vector2i(-1, -1):
		exit_cell = leader

	var result := {
		"size": Vector2i(w, h),
		"walkable": walkable,
		"blocked": blocked,
		"spawn": spawn,
		"exit": exit_cell,
		"exit_gate": exit_gate,
		"leader": leader,
		"shops": shops,
		"optionals": optionals,
		"trainers": trainer_cells,
		"gym_door": gym_door,
		"gym_floor": gym_floor,
		"material": material,
		"floor_material": floor_material,
		"surf": surf,
	}
	_cache[stage_id] = result
	return result


## Local cells that are surfable water (walkable, gated by a surf ability).
static func surf_cells_local(bal, stage_id: String) -> Dictionary:
	return parsed(bal, stage_id)["surf"]


static func spawn_local(bal, stage_id: String) -> Vector2i:
	return parsed(bal, stage_id)["spawn"]


static func spawn_world(bal, stage_id: String, stage_origin: Vector2i) -> Vector2i:
	return local_to_world(spawn_local(bal, stage_id), stage_origin)


## Whether the stage's map places a leader (`L`). Stages without one are pure
## navigation connectors — no mandatory fight, no gate (Phase 7).
static func has_leader(bal, stage_id: String) -> bool:
	return parsed(bal, stage_id)["leader"] != Vector2i(-1, -1)


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


## Trigger/encounter cells for each route-trainer (`t`) placement, in grid order.
static func trainer_spawns_local(bal, stage_id: String) -> Array[Dictionary]:
	var p := parsed(bal, stage_id)
	var out: Array[Dictionary] = []
	for cell in p["trainers"]:
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


## The stage's authored exit gate (`X`), or (-1, -1) if it has none. Its own leader
## holds it shut, so a leader in a dead-end side room still gates the area; a stage
## with no leader has nothing to open it and is never gated. Unlike `exit_local`,
## this never falls back to the leader cell.
static func exit_gate_local(bal, stage_id: String) -> Vector2i:
	return parsed(bal, stage_id)["exit_gate"]


static func size_local(bal, stage_id: String) -> Vector2i:
	return parsed(bal, stage_id)["size"]


## Author-placed top-left origin of the stage in the shared world grid (World View
## in the map editor). Absent → the world builder falls back to legacy telescoping.
static func has_world_pos(bal, stage_id: String) -> bool:
	var wp = layout_for(bal, stage_id).get("world_pos", null)
	return wp is Array and wp.size() == 2


static func world_pos_of(bal, stage_id: String) -> Vector2i:
	var wp: Array = layout_for(bal, stage_id).get("world_pos", [0, 0])
	return Vector2i(int(wp[0]), int(wp[1]))


static func template_id(bal, stage_id: String) -> String:
	return String(layout_for(bal, stage_id).get("template", "open_field"))


static func display_name(bal, stage_id: String) -> String:
	return String(layout_for(bal, stage_id).get("display_name", ""))


static func gym_name_of(bal, stage_id: String) -> String:
	return String(layout_for(bal, stage_id).get("gym_name", ""))


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


static func trainer_count(bal, stage_id: String) -> int:
	return parsed(bal, stage_id)["trainers"].size()


## Load-time data checks (Balance._validate), split by severity: `assert` means
## the run is broken (stranded progression, sealed content); `push_warning` means
## an authoring slip that still builds.
##
## A failed assert aborts only the function it sits in — the caller keeps going —
## so each check below is ordered cheapest-first and the world checks live in
## their own functions to survive a per-stage failure.
static func validate(bal) -> void:
	var layouts: Dictionary = bal.stage_layouts
	var ids := stage_ids_in_order(bal)
	for i in ids.size():
		_validate_stage(bal, layouts, ids[i], i == 0)
	_validate_world(bal, ids)


static func _validate_stage(bal, layouts: Dictionary, stage_id: String, is_first: bool) -> void:
	assert(layouts.has(stage_id), "Missing stage layout for '%s'" % stage_id)
	var layout: Dictionary = layouts[stage_id]
	assert(String(layout.get("id", "")) == stage_id, "Layout id mismatch for '%s'" % stage_id)
	var template := String(layout.get("template", ""))
	assert(template in VALID_TEMPLATES, "Unknown template '%s' in stage '%s'" % [template, stage_id])
	assert(String(layout.get("gate_facing", "north")) in VALID_FACINGS,
			"Invalid gate_facing in stage '%s'" % stage_id)
	assert(has_world_pos(bal, stage_id), "Stage '%s' has no world_pos" % stage_id)

	var rows := glyph_rows(layout)
	assert(not rows.is_empty(), "Stage '%s' has no grid" % stage_id)
	var width := String(rows[0]).length()
	assert(width > 0, "Stage '%s' grid row 0 is empty" % stage_id)
	var s_count := 0
	var l_count := 0
	var x_count := 0
	for row_v in rows:
		var row := String(row_v)
		assert(row.length() == width, "Stage '%s' has ragged grid rows" % stage_id)
		s_count += row.count("S")
		l_count += row.count("L")
		x_count += row.count("X")

	# Stages are stitched into one world by `world_pos`, so only the run's first
	# stage needs an entry point: one spawn for the whole world, none elsewhere.
	if is_first:
		assert(s_count == 1,
				"First stage '%s' must have exactly one spawn (S), found %d" % [stage_id, s_count])
	else:
		assert(s_count == 0, "Stage '%s' has %d spawn(s) (S); only the run's first stage may have one"
				% [stage_id, s_count])
	# A stage places at most one leader; zero = a connector walked straight through.
	assert(l_count <= 1, "Stage '%s' has %d leaders (L); at most one allowed" % [stage_id, l_count])
	assert(x_count <= 1, "Stage '%s' has %d exits (X); at most one allowed" % [stage_id, x_count])
	# An exit gate is opened by its stage's leader falling. With no leader nothing
	# opens it, so it stands open all run and gates nothing.
	if x_count == 1 and l_count == 0:
		push_warning("Stage '%s' has an exit gate (X) but no leader (L) to open it; it is never gated."
				% stage_id)


## World-level checks. Stages share one grid stitched by `world_pos`, so geometry
## only means anything across the seams — a stage's cells are frequently reachable
## only through its neighbour. These validate the stitched world, never a stage
## in isolation.
static func _validate_world(bal, ids: Array[String]) -> void:
	if ids.is_empty():
		return
	var world := {}     # world cell -> glyph
	var owner := {}     # world cell -> stage_id that stamped it
	var clashed := {}
	for stage_id in ids:
		var origin := world_pos_of(bal, stage_id)
		var grid := glyph_rows(layout_for(bal, stage_id))
		for y in grid.size():
			var row := String(grid[y])
			for x in row.length():
				var cell := local_to_world(Vector2i(x, y), origin)
				# The builder stamps in run order, so a later stage silently
				# overwrites the tiles an earlier one authored here.
				if owner.has(cell) and not clashed.has(stage_id):
					clashed[stage_id] = true
					push_warning("Stage '%s' overlaps '%s' at world cell %s; '%s' overwrites those tiles."
							% [stage_id, owner[cell], cell, stage_id])
				world[cell] = row[x]
				owner[cell] = stage_id

	var spawn := local_to_world(spawn_local(bal, ids[0]), world_pos_of(bal, ids[0]))
	assert(world.has(spawn), "Run spawn %s falls outside the stitched world" % spawn)

	# Nothing the run needs may be sealed off once every gate is open.
	var open := _flood_world(world, spawn, {}, 0)
	for stage_id in ids:
		var origin := world_pos_of(bal, stage_id)
		var p := parsed(bal, stage_id)
		for opt in p["optionals"]:
			assert(open.has(local_to_world(opt, origin)),
					"Stage '%s': optional wild at %s is sealed off" % [stage_id, opt])
		for tr in p["trainers"]:
			assert(open.has(local_to_world(tr, origin)),
					"Stage '%s': route trainer at %s is sealed off" % [stage_id, tr])
		for kind in p["shops"]:
			assert(open.has(local_to_world(p["shops"][kind], origin)),
					"Stage '%s': %s is sealed off" % [stage_id, kind])

	_validate_progression(bal, ids, world, spawn)


## Walk the run in mandatory order with leader gates enforced exactly as
## WorldGrid.is_walkable enforces them: a leader tile stays solid until its own
## slot is cleared. Catches a leader authored physically behind a later one,
## which strands the run with no legal move.
static func _validate_progression(bal, ids: Array[String], world: Dictionary,
		spawn: Vector2i) -> void:
	var gates := {}     # world cell -> the mandatory slot that clears it
	var arcs: Array[Dictionary] = []
	for stage_id in ids:
		if not has_leader(bal, stage_id):
			continue
		var origin := world_pos_of(bal, stage_id)
		var gate := gate_local(bal, stage_id)
		gates[local_to_world(gate["encounter"], origin)] = arcs.size()
		# The stage's exit gate is held shut by the same leader — mirrors world_builder.
		var exit_gate := exit_gate_local(bal, stage_id)
		if exit_gate.x >= 0:
			gates[local_to_world(exit_gate, origin)] = arcs.size()
		arcs.append({
			"stage_id": stage_id,
			"trigger": local_to_world(gate["trigger"], origin),
		})

	var pos := spawn
	for slot in arcs.size():
		var arc: Dictionary = arcs[slot]
		var reached := _flood_world(world, pos, gates, slot)
		assert(reached.has(arc["trigger"]),
				"Progression: leader %d ('%s') is unreachable when its turn comes; it sits behind a later leader's gate, so the run strands here."
						% [slot, arc["stage_id"]])
		# A leader you can walk straight past gates nothing: when its turn comes, no
		# later leader may be reachable yet. Typically a dead-end gym whose stage
		# never authored an exit gate (`X`), so nothing holds the area shut.
		if slot + 1 < arcs.size():
			var next_arc: Dictionary = arcs[slot + 1]
			if reached.has(next_arc["trigger"]):
				push_warning("Progression: leader %d ('%s') can be bypassed — '%s' is reachable without fighting it. Give '%s' an exit gate (X)."
						% [slot, arc["stage_id"], next_arc["stage_id"], arc["stage_id"]])
		pos = arc["trigger"]


## Flood the stitched world from `start`. A gate cell is impassable while
## `encounter_index <= its slot`, mirroring WorldGrid.is_walkable; pass an empty
## `gates` to flood with every gate open.
static func _flood_world(world: Dictionary, start: Vector2i, gates: Dictionary,
		encounter_index: int) -> Dictionary:
	var seen := {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var n: Vector2i = cell + dir
			if seen.has(n) or not world.has(n):
				continue
			if String(world[n]) in BARRIER_CHARS:
				continue
			if gates.has(n) and encounter_index <= int(gates[n]):
				continue
			seen[n] = true
			frontier.append(n)
	return seen
