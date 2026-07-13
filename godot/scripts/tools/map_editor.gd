class_name MapEditor
extends Control
## Phase 5 map editor (dev tool). Launch: godot --path . -- --mapeditor
## Paints the ASCII `grid` in data/balance/stage_layouts.json with a terrain +
## encounter palette, edits per-stage metadata, and live-validates connectivity.
## Reads/writes the same JSON the game consumes; the gate funnel is auto-derived
## at run time, so there is nothing funnel-related to author here.

const LAYOUTS_PATH := "res://data/balance/stage_layouts.json"
const RUN_CONFIG_PATH := "res://data/balance/run_config.json"

const BARRIER_CHARS := ["#", "T", "H", "^", "B"]
const TEMPLATES := ["open_field", "forest_maze", "cave_branches", "town_pocket", "gym_arena",
	"big_city", "ship_interior", "corporate", "mansion", "volcanic", "bridge", "plateau"]
const FACINGS := ["north", "east", "south", "west"]

## char -> {name, color, group}. Order within a group drives palette layout.
const PALETTE := [
	# walkable terrain
	{"ch": ".", "name": "Grass", "group": "Walkable", "color": Color(0.30, 0.55, 0.28)},
	{"ch": "=", "name": "Road", "group": "Walkable", "color": Color(0.55, 0.52, 0.47)},
	{"ch": ",", "name": "Dirt", "group": "Walkable", "color": Color(0.52, 0.42, 0.30)},
	{"ch": "_", "name": "Floor", "group": "Walkable", "color": Color(0.72, 0.68, 0.55)},
	# barriers
	{"ch": "#", "name": "Wall", "group": "Barrier", "color": Color(0.16, 0.17, 0.20)},
	{"ch": "T", "name": "Tree", "group": "Barrier", "color": Color(0.12, 0.34, 0.16)},
	{"ch": "H", "name": "Hedge", "group": "Barrier", "color": Color(0.20, 0.42, 0.22)},
	{"ch": "^", "name": "Mountain", "group": "Barrier", "color": Color(0.40, 0.36, 0.32)},
	{"ch": "B", "name": "Building", "group": "Barrier", "color": Color(0.42, 0.22, 0.20)},
	# objects
	{"ch": "S", "name": "Spawn", "group": "Object", "color": Color(0.20, 0.75, 0.85)},
	{"ch": "X", "name": "Exit", "group": "Object", "color": Color(0.90, 0.90, 0.95)},
	{"ch": "c", "name": "Center", "group": "Object", "color": Color(0.90, 0.35, 0.35)},
	{"ch": "m", "name": "Mart", "group": "Object", "color": Color(0.35, 0.55, 0.90)},
	{"ch": "w", "name": "Wild", "group": "Object", "color": Color(0.85, 0.80, 0.25)},
	{"ch": "L", "name": "Leader", "group": "Object", "color": Color(0.95, 0.60, 0.15)},
	{"ch": "D", "name": "Gym door", "group": "Object", "color": Color(0.65, 0.35, 0.80)},
]

var _all: Dictionary = {}          # full parsed stage_layouts.json
var _stages: Dictionary = {}       # stage_id -> layout dict
var _run_config: Dictionary = {}   # full parsed run_config.json (for run/segment order)
var _stage_id: String = ""
var _grid: Array = []              # Array[Array[String]] (single chars)
var _active_char := "#"

# UI refs
var _canvas: GridCanvas
var _stage_picker: OptionButton
var _status: Label
var _id_edit: LineEdit
var _run_pos: Label
var _name_edit: LineEdit
var _gym_name_edit: LineEdit
var _template_pick: OptionButton
var _facing_pick: OptionButton
var _center_win: SpinBox
var _mart_win: SpinBox
var _rows_spin: SpinBox
var _cols_spin: SpinBox
var _palette_buttons: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	root.add_child(_build_toolbar())

	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 8)
	root.add_child(mid)
	mid.add_child(_build_sidebar())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(scroll)
	_canvas = GridCanvas.new()
	_canvas.painter = _paint_cell
	for entry in PALETTE:
		_canvas.colors[entry["ch"]] = entry["color"]
	scroll.add_child(_canvas)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	root.add_child(_status)

	_load_file()
	if not _stages.is_empty():
		_select_stage(_stages.keys()[0])


# --- UI construction ---

func _build_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)

	bar.add_child(_label("Stage:"))
	_stage_picker = OptionButton.new()
	_stage_picker.item_selected.connect(_on_stage_picked)
	bar.add_child(_stage_picker)

	var new_btn := Button.new()
	new_btn.text = "New…"
	new_btn.pressed.connect(_on_new_stage)
	bar.add_child(new_btn)

	bar.add_child(VSeparator.new())
	bar.add_child(_label("Run order:"))
	var up_btn := Button.new()
	up_btn.text = "◀ Earlier"
	up_btn.pressed.connect(_move_stage.bind(-1))
	bar.add_child(up_btn)
	var down_btn := Button.new()
	down_btn.text = "Later ▶"
	down_btn.pressed.connect(_move_stage.bind(1))
	bar.add_child(down_btn)
	var add_btn := Button.new()
	add_btn.text = "Add to run"
	add_btn.pressed.connect(_on_add_to_run)
	bar.add_child(add_btn)

	bar.add_child(VSeparator.new())
	bar.add_child(_label("Rows:"))
	_rows_spin = _spin(3, 60, 9)
	bar.add_child(_rows_spin)
	bar.add_child(_label("Cols:"))
	_cols_spin = _spin(3, 60, 11)
	bar.add_child(_cols_spin)
	var resize_btn := Button.new()
	resize_btn.text = "Resize"
	resize_btn.pressed.connect(_on_resize)
	bar.add_child(resize_btn)

	bar.add_child(VSeparator.new())
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_on_save)
	bar.add_child(save_btn)
	return bar


func _build_sidebar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(240, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	# Palette, grouped
	var groups := ["Walkable", "Barrier", "Object"]
	for group in groups:
		var header := Label.new()
		header.text = group
		header.add_theme_font_size_override("font_size", 14)
		header.modulate = Color(0.8, 0.85, 0.95)
		box.add_child(header)
		var flow := HFlowContainer.new()
		box.add_child(flow)
		for entry in PALETTE:
			if entry["group"] != group:
				continue
			flow.add_child(_palette_button(entry))

	box.add_child(HSeparator.new())

	# Metadata
	box.add_child(_meta_label("Stage id (rename — key + segment)"))
	_id_edit = LineEdit.new()
	_id_edit.text_submitted.connect(func(_t):
		_commit_metadata_from_ui()
		_sync_stage_picker(_stage_id))
	box.add_child(_id_edit)
	_run_pos = _meta_label("")
	box.add_child(_run_pos)
	box.add_child(_meta_label("Display name"))
	_name_edit = LineEdit.new()
	box.add_child(_name_edit)
	box.add_child(_meta_label("Template"))
	_template_pick = OptionButton.new()
	for t in TEMPLATES:
		_template_pick.add_item(t)
	box.add_child(_template_pick)
	box.add_child(_meta_label("Gym name (blank = not a gym)"))
	_gym_name_edit = LineEdit.new()
	box.add_child(_gym_name_edit)
	box.add_child(_meta_label("Gate facing"))
	_facing_pick = OptionButton.new()
	for f in FACINGS:
		_facing_pick.add_item(f)
	box.add_child(_facing_pick)
	box.add_child(_meta_label("Shop windows (center / mart)"))
	var win_row := HBoxContainer.new()
	_center_win = _spin(0, 9, 1)
	_mart_win = _spin(0, 9, 2)
	win_row.add_child(_center_win)
	win_row.add_child(_mart_win)
	box.add_child(win_row)
	return panel


func _palette_button(entry: Dictionary) -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(70, 30)
	btn.text = "%s %s" % [entry["ch"], entry["name"]]
	btn.add_theme_color_override("font_color", Color.BLACK if entry["color"].get_luminance() > 0.5 else Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = entry["color"]
	sb.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	var pressed_sb := sb.duplicate()
	pressed_sb.border_color = Color.WHITE
	pressed_sb.set_border_width_all(3)
	btn.add_theme_stylebox_override("pressed", pressed_sb)
	btn.button_pressed = entry["ch"] == _active_char
	btn.pressed.connect(_on_palette_pick.bind(entry["ch"]))
	_palette_buttons.append({"btn": btn, "ch": entry["ch"]})
	return btn


# --- Actions ---

func _on_palette_pick(ch: String) -> void:
	_active_char = ch
	for pb in _palette_buttons:
		pb["btn"].button_pressed = pb["ch"] == ch


func _paint_cell(cell: Vector2i) -> void:
	if cell.y < 0 or cell.y >= _grid.size() or cell.x < 0 or cell.x >= _grid[cell.y].size():
		return
	_grid[cell.y][cell.x] = _active_char
	_canvas.queue_redraw()
	_revalidate()


func _on_stage_picked(idx: int) -> void:
	_select_stage(String(_stage_picker.get_item_metadata(idx)))


func _select_stage(stage_id: String) -> void:
	if not _stages.has(stage_id):
		return
	_commit_metadata_from_ui()  # keep edits (incl. rename) to the previously selected stage
	if not _stages.has(stage_id):  # commit may have renamed it
		stage_id = _stage_id if _stages.has(_stage_id) else _stages.keys()[0]
	_stage_id = stage_id
	var layout: Dictionary = _stages[stage_id]
	_id_edit.text = stage_id
	_grid = _grid_from_rows(layout.get("grid", []))
	_name_edit.text = String(layout.get("display_name", ""))
	_gym_name_edit.text = String(layout.get("gym_name", ""))
	_template_pick.select(maxi(0, TEMPLATES.find(String(layout.get("template", "open_field")))))
	_facing_pick.select(maxi(0, FACINGS.find(String(layout.get("gate_facing", "north")))))
	var windows: Dictionary = layout.get("shop_windows", {})
	_center_win.value = int(windows.get("center", 1))
	_mart_win.value = int(windows.get("mart", 2))
	_rows_spin.value = _grid.size()
	_cols_spin.value = _grid[0].size() if not _grid.is_empty() else 0
	_sync_stage_picker(stage_id)
	_canvas.set_grid(_grid)
	_revalidate()


func _on_new_stage() -> void:
	var base := "new_stage"
	var id := base
	var n := 1
	while _stages.has(id):
		n += 1
		id = "%s_%d" % [base, n]
	var cols := int(_cols_spin.value)
	var rows := int(_rows_spin.value)
	_stages[id] = {
		"id": id,
		"template": "open_field",
		"display_name": id,
		"gate_facing": "north",
		"shop_windows": {"center": 1, "mart": 2},
		"grid": _blank_rows(rows, cols),
	}
	_select_stage(id)


func _apply_rename(old_id: String, new_id: String) -> void:
	var layout: Dictionary = _stages[old_id]
	layout["id"] = new_id
	_stages.erase(old_id)
	_stages[new_id] = layout
	var idx := _segment_index(old_id)
	if idx >= 0:
		_segments()[idx]["id"] = new_id


## Move the current stage earlier/later in the run (reorders run_config segments).
func _move_stage(delta: int) -> void:
	_commit_metadata_from_ui()
	var idx := _segment_index(_stage_id)
	if idx < 0:
		_status.text = "'%s' isn't in the run — click 'Add to run' first." % _stage_id
		_status.modulate = Color(1.0, 0.7, 0.5)
		return
	var segs := _segments()
	var j := idx + delta
	if j < 0 or j >= segs.size():
		return
	var tmp: Variant = segs[idx]
	segs[idx] = segs[j]
	segs[j] = tmp
	_sync_stage_picker(_stage_id)
	_status.text = "Moved '%s' to run position %d / %d." % [_stage_id, j + 1, segs.size()]
	_status.modulate = Color(0.6, 1.0, 0.6)


## Add the current (orphan) stage to the run as a stub segment. Leader/pool are
## placeholders the author fills in run_config.json; keeps the run loadable.
func _on_add_to_run() -> void:
	_commit_metadata_from_ui()
	if _segment_index(_stage_id) >= 0:
		_status.text = "'%s' is already in the run." % _stage_id
		return
	if not _run_config.has("segments"):
		_run_config["segments"] = []
	_run_config["segments"].append({
		"id": _stage_id, "wild_pool": [], "leader": "brock", "leader_kind": "trainer",
		"leader_gold": "midboss", "reward_pool_key": "stage1", "shop_window": 0, "is_final": false,
	})
	_sync_stage_picker(_stage_id)
	_status.text = "Added '%s' to run (stub — set leader/wild_pool/badge in run_config.json)." % _stage_id
	_status.modulate = Color(0.85, 0.9, 0.6)


func _on_resize() -> void:
	var rows := int(_rows_spin.value)
	var cols := int(_cols_spin.value)
	var resized: Array = []
	for y in rows:
		var row: Array = []
		for x in cols:
			if y < _grid.size() and x < _grid[y].size():
				row.append(_grid[y][x])
			else:
				# new border cells become walls, new interior floor
				var edge := y == 0 or x == 0 or y == rows - 1 or x == cols - 1
				row.append("#" if edge else ".")
		resized.append(row)
	_grid = resized
	_canvas.set_grid(_grid)
	_revalidate()


func _on_save() -> void:
	_commit_metadata_from_ui()
	_all["stages"] = _stages
	var f := FileAccess.open(LAYOUTS_PATH, FileAccess.WRITE)
	if f == null:
		_status.text = "SAVE FAILED: cannot open %s (err %d)" % [LAYOUTS_PATH, FileAccess.get_open_error()]
		_status.modulate = Color(1, 0.5, 0.5)
		return
	f.store_string(JSON.stringify(_all, "  "))
	f.close()
	# Persist run order + any renames back to run_config.json.
	if not _run_config.is_empty():
		var rf := FileAccess.open(RUN_CONFIG_PATH, FileAccess.WRITE)
		if rf != null:
			rf.store_string(JSON.stringify(_run_config, "  "))
			rf.close()
	_status.text = "Saved %d stages + run order." % _stages.size()
	_status.modulate = Color(0.6, 1.0, 0.6)


func _commit_metadata_from_ui() -> void:
	if _stage_id == "" or not _stages.has(_stage_id):
		return
	# Rename (stage id): update the layout key + id and the matching run segment.
	if _id_edit != null:
		var new_id := _id_edit.text.strip_edges()
		if new_id != "" and new_id != _stage_id and not _stages.has(new_id):
			_apply_rename(_stage_id, new_id)
			_stage_id = new_id
	var layout: Dictionary = _stages[_stage_id]
	layout["id"] = _stage_id
	layout["grid"] = _rows_from_grid(_grid)
	layout["display_name"] = _name_edit.text
	layout["template"] = TEMPLATES[_template_pick.selected]
	layout["gate_facing"] = FACINGS[_facing_pick.selected]
	layout["shop_windows"] = {"center": int(_center_win.value), "mart": int(_mart_win.value)}
	if _gym_name_edit.text.strip_edges() == "":
		layout.erase("gym_name")
	else:
		layout["gym_name"] = _gym_name_edit.text


# --- Validation ---

func _revalidate() -> void:
	var issues := _validate(_grid)
	if issues.is_empty():
		_status.text = "✓ Valid — %d×%d" % [_grid[0].size() if not _grid.is_empty() else 0, _grid.size()]
		_status.modulate = Color(0.6, 1.0, 0.6)
	else:
		_status.text = "✗ " + "   ".join(issues)
		_status.modulate = Color(1.0, 0.7, 0.5)


## Returns a list of human-readable problems (empty = valid).
static func _validate(grid: Array) -> Array:
	var issues: Array = []
	if grid.is_empty():
		return ["empty grid"]
	var width: int = grid[0].size()
	var s := 0
	var l := 0
	var walkable := {}
	var wilds: Array = []
	var spawn := Vector2i(-1, -1)
	var leader := Vector2i(-1, -1)
	for y in grid.size():
		if grid[y].size() != width:
			issues.append("row %d wrong length" % y)
		for x in grid[y].size():
			var ch: String = grid[y][x]
			var cell := Vector2i(x, y)
			if ch not in BARRIER_CHARS:
				walkable[cell] = true
			match ch:
				"S": s += 1; spawn = cell
				"L": l += 1; leader = cell
				"w": wilds.append(cell)
	if s != 1:
		issues.append("need exactly 1 spawn (S), have %d" % s)
	if l > 1:
		issues.append("at most 1 leader (L), have %d" % l)
	# 0 leaders = a connector stage (nav only). Gyms/final need one — checked at load.
	if s == 1:
		var reached := _flood(walkable, spawn)
		if l == 1 and not reached.has(leader):
			issues.append("leader unreachable from spawn")
		for wcell in wilds:
			if not reached.has(wcell):
				issues.append("a wild is sealed off")
				break
	return issues


static func _flood(walkable: Dictionary, start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var n: Vector2i = c + d
			if walkable.has(n) and not seen.has(n):
				seen[n] = true
				stack.append(n)
	return seen


# --- File / grid helpers ---

func _load_file() -> void:
	var f := FileAccess.open(LAYOUTS_PATH, FileAccess.READ)
	if f == null:
		_status.text = "Could not open %s" % LAYOUTS_PATH
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_all = parsed
		_stages = _all.get("stages", {})
	var rf := FileAccess.open(RUN_CONFIG_PATH, FileAccess.READ)
	if rf != null:
		var rc: Variant = JSON.parse_string(rf.get_as_text())
		rf.close()
		if rc is Dictionary:
			_run_config = rc


# --- Run order (run_config.json segments) ---

func _segments() -> Array:
	return _run_config.get("segments", [])


func _segment_index(stage_id: String) -> int:
	var segs := _segments()
	for i in segs.size():
		if String(segs[i].get("id", "")) == stage_id:
			return i
	return -1


## Stage ids in run order first, then any orphan layouts (no segment) at the end.
func _ordered_ids() -> Array:
	var out: Array = []
	for seg in _segments():
		var sid := String(seg.get("id", ""))
		if _stages.has(sid):
			out.append(sid)
	for sid in _stages:
		if not out.has(String(sid)):
			out.append(String(sid))
	return out


## Stage picker, ordered by run position; orphans marked "(not in run)".
func _sync_stage_picker(selected_id: String) -> void:
	_stage_picker.clear()
	var sel := 0
	var i := 0
	for sid in _ordered_ids():
		var seg_i := _segment_index(sid)
		var label := "%d. %s" % [seg_i + 1, sid] if seg_i >= 0 else "•  %s (not in run)" % sid
		_stage_picker.add_item(label)
		_stage_picker.set_item_metadata(i, sid)
		if sid == selected_id:
			sel = i
		i += 1
	_stage_picker.select(sel)
	_update_run_pos()


func _update_run_pos() -> void:
	if _run_pos == null:
		return
	var idx := _segment_index(_stage_id)
	var total := _segments().size()
	_run_pos.text = "In run: %d / %d" % [idx + 1, total] if idx >= 0 else "Not in the run"


static func _grid_from_rows(rows: Array) -> Array:
	var out: Array = []
	for row_v in rows:
		var row: Array = []
		for ch in String(row_v):
			row.append(ch)
		out.append(row)
	return out


static func _rows_from_grid(grid: Array) -> Array:
	var out: Array = []
	for row in grid:
		out.append("".join(row))
	return out


static func _blank_rows(rows: int, cols: int) -> Array:
	var out: Array = []
	for y in rows:
		var chars: Array = []
		for x in cols:
			var edge := y == 0 or x == 0 or y == rows - 1 or x == cols - 1
			chars.append("#" if edge else ".")
		out.append("".join(chars))
	return out


# --- small widget helpers ---

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _meta_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.modulate = Color(0.75, 0.78, 0.85)
	return l


func _spin(min_v: int, max_v: int, val: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.value = val
	s.custom_minimum_size = Vector2(56, 0)
	return s


## Inner canvas: draws the char grid and paints cells under the mouse. Self
## contained — colors are injected so it never reaches back to the outer class.
class GridCanvas extends Control:
	const TERRAIN := [".", "#", "_", "=", ",", "T", "H", "^", "B"]
	var grid: Array = []
	var colors: Dictionary = {}
	var cell_px := 30.0
	var painter: Callable

	func set_grid(g: Array) -> void:
		grid = g
		var cols: int = grid[0].size() if not grid.is_empty() else 0
		custom_minimum_size = Vector2(cols * cell_px, grid.size() * cell_px)
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for y in grid.size():
			for x in grid[y].size():
				var ch: String = grid[y][x]
				var col: Color = colors.get(ch, Color(0.10, 0.11, 0.13))
				draw_rect(Rect2(x * cell_px, y * cell_px, cell_px - 1, cell_px - 1), col)
				if ch not in TERRAIN:
					draw_string(font, Vector2(x * cell_px + 8, y * cell_px + cell_px - 9),
							ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
							Color.BLACK if col.get_luminance() > 0.5 else Color.WHITE)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_paint(event.position)
		elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_paint(event.position)

	func _paint(pos: Vector2) -> void:
		var cell := Vector2i(int(pos.x / cell_px), int(pos.y / cell_px))
		if painter.is_valid():
			painter.call(cell)
