class_name MapEditor
extends Control
## Phase 5 map editor (dev tool). Launch: godot --path . -- --mapeditor
## Paints the ASCII `grid` in data/balance/stage_layouts.json with a terrain +
## encounter palette, edits per-stage metadata, and live-validates connectivity.
## The World View toggle shows every stage in one shared grid so stages can be
## dragged into place (saved as each layout's `world_pos`, which the world builder
## reads). Reads/writes the same JSON the game consumes.

const LAYOUTS_PATH := "res://data/balance/stage_layouts.json"
const RUN_CONFIG_PATH := "res://data/balance/run_config.json"
const ENEMIES_PATH := "res://data/balance/enemies.json"
const TRAINERS_PATH := "res://data/balance/trainers.json"
const StageLayout = preload("res://scripts/world/stage_layout.gd")

const POKE_TYPES := ["NORMAL", "FIRE", "WATER", "GRASS", "ELECTRIC", "ROCK", "GROUND",
	"FIGHTING", "POISON", "FLYING", "BUG", "PSYCHIC"]
const MOVE_PHASES := ["any", "mid", "healthy", "desperate"]

## National Dex order (ids as in enemies.json) — drives Pokédex sorting.
const GEN1_ORDER := ["bulbasaur", "ivysaur", "venusaur", "charmander", "charmeleon", "charizard",
	"squirtle", "wartortle", "blastoise", "caterpie", "metapod", "butterfree", "weedle", "kakuna",
	"beedrill", "pidgey", "pidgeotto", "pidgeot", "rattata", "raticate", "spearow", "fearow",
	"ekans", "arbok", "pikachu", "raichu", "sandshrew", "sandslash", "nidoran_f", "nidorina",
	"nidoqueen", "nidoran_m", "nidorino", "nidoking", "clefairy", "clefable", "vulpix", "ninetales",
	"jigglypuff", "wigglytuff", "zubat", "golbat", "oddish", "gloom", "vileplume", "paras",
	"parasect", "venonat", "venomoth", "diglett", "dugtrio", "meowth", "persian", "psyduck",
	"golduck", "mankey", "primeape", "growlithe", "arcanine", "poliwag", "poliwhirl", "poliwrath",
	"abra", "kadabra", "alakazam", "machop", "machoke", "machamp", "bellsprout", "weepinbell",
	"victreebel", "tentacool", "tentacruel", "geodude", "graveler", "golem", "ponyta", "rapidash",
	"slowpoke", "slowbro", "magnemite", "magneton", "farfetchd", "doduo", "dodrio", "seel",
	"dewgong", "grimer", "muk", "shellder", "cloyster", "gastly", "haunter", "gengar", "onix",
	"drowzee", "hypno", "krabby", "kingler", "voltorb", "electrode", "exeggcute", "exeggutor",
	"cubone", "marowak", "hitmonlee", "hitmonchan", "lickitung", "koffing", "weezing", "rhyhorn",
	"rhydon", "chansey", "tangela", "kangaskhan", "horsea", "seadra", "goldeen", "seaking",
	"staryu", "starmie", "mr_mime", "scyther", "jynx", "electabuzz", "magmar", "pinsir", "tauros",
	"magikarp", "gyarados", "lapras", "ditto", "eevee", "vaporeon", "jolteon", "flareon", "porygon",
	"omanyte", "omastar", "kabuto", "kabutops", "aerodactyl", "snorlax", "articuno", "zapdos",
	"moltres", "dratini", "dragonair", "dragonite", "mewtwo", "mew"]

## Legacy trainer/boss stat-blocks in enemies.json — excluded from the Pokédex
## (they belong in the Trainers section; migrating to trainer+team is Phase 3).
const TRAINER_BLOB_IDS := ["brock", "misty", "surge", "erika", "koga", "sabrina", "blaine",
	"giovanni", "lorelei", "bruno", "agatha", "lance", "champion", "rival_squirtle",
	"rival_bulbasaur", "rival_charmander", "bug_catcher_butterfree", "bug_catcher_beedrill",
	"sailor", "gambler", "rocket_grunt", "rocket_admin", "biker", "swimmer", "burglar",
	"cool_trainer"]

# Blocking chars — kept in sync with StageLayout.BARRIER_CHARS (the game's truth).
const BARRIER_CHARS := ["#", "T", "H", "^", "B", "b", "+", "O", "~", "*", "I"]
## Walkable cells the run has to be able to touch. Any other walkable cell is
## scenery, so sealing it off behind terrain is an authoring choice, not a bug.
const CONTENT_CHARS := ["S", "X", "c", "m", "w", "t", "L", "D"]
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
	{"ch": "s", "name": "Surf", "group": "Walkable", "color": Color(0.30, 0.55, 0.80)},
	# barriers
	{"ch": "#", "name": "Wall", "group": "Barrier", "color": Color(0.16, 0.17, 0.20)},
	{"ch": "T", "name": "Tree", "group": "Barrier", "color": Color(0.12, 0.34, 0.16)},
	{"ch": "H", "name": "Hedge", "group": "Barrier", "color": Color(0.20, 0.42, 0.22)},
	{"ch": "^", "name": "Mountain", "group": "Barrier", "color": Color(0.40, 0.36, 0.32)},
	{"ch": "B", "name": "Building", "group": "Barrier", "color": Color(0.42, 0.22, 0.20)},
	{"ch": "~", "name": "Water", "group": "Barrier", "color": Color(0.20, 0.40, 0.70)},
	{"ch": "*", "name": "Lava", "group": "Barrier", "color": Color(0.85, 0.35, 0.10)},
	# objects
	{"ch": "S", "name": "Spawn", "group": "Object", "color": Color(0.20, 0.75, 0.85)},
	{"ch": "X", "name": "Exit", "group": "Object", "color": Color(0.90, 0.90, 0.95)},
	{"ch": "c", "name": "Center", "group": "Object", "color": Color(0.90, 0.35, 0.35)},
	{"ch": "m", "name": "Mart", "group": "Object", "color": Color(0.35, 0.55, 0.90)},
	{"ch": "w", "name": "Wild", "group": "Object", "color": Color(0.85, 0.80, 0.25)},
	{"ch": "t", "name": "Trainer", "group": "Object", "color": Color(0.95, 0.45, 0.75)},
	{"ch": "L", "name": "Leader", "group": "Object", "color": Color(0.95, 0.60, 0.15)},
	{"ch": "D", "name": "Gym door", "group": "Object", "color": Color(0.65, 0.35, 0.80)},
]

var _all: Dictionary = {}          # full parsed stage_layouts.json
var _stages: Dictionary = {}       # stage_id -> layout dict
var _run_config: Dictionary = {}   # full parsed run_config.json (for run/segment order)
var _stage_id: String = ""
var _grid: Array = []              # Array[Array[String]] (glyph per cell)
var _materials: Array = []         # Array[Array[String]] parallel to _grid; "" = inherit
var _active_char := "#"
var _active_material := ""
var _brush_mode := "terrain"       # "terrain" paints glyphs, "material" paints overrides
var _material_buttons: Array = []

# UI refs
var _canvas: GridCanvas
var _world_canvas: WorldCanvas
var _center_scroll: ScrollContainer
var _sidebar: Control
var _view_toggle: Button
var _world_mode := false
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
var _leader_trainer_edit: LineEdit
var _leader_mode_pick: OptionButton
var _leader_team_edit: LineEdit
var _route_trainers_edit: TextEdit

# Pokedex (enemies.json library editor)
var _enemies_all: Dictionary = {}   # full parsed enemies.json
var _enemies: Array = []            # the enemies list (dicts, order preserved)
var _dex_current := ""
var _pokedex_panel: Control
var _pokedex_mode := false
var _dex_toggle: Button
var _dex_picker: OptionButton
var _dex_id: LineEdit
var _dex_name: LineEdit
var _dex_type: OptionButton
var _dex_hp: SpinBox
var _dex_xp: SpinBox
var _dex_wild: CheckBox
var _dex_boss: CheckBox
var _dex_moves: TextEdit
var _dex_boss_pattern: LineEdit
var _dex_loop_start: SpinBox
var _dex_sprite: TextureRect

# Trainers (trainers.json identity library editor)
var _trainers_all: Dictionary = {}
var _trainers_lib: Array = []       # trainer dicts {id, name, portrait_id}
var _tr_current := ""
var _trainers_panel: Control
var _trainers_toggle: Button
var _tr_picker: OptionButton
var _tr_id: LineEdit
var _tr_name: LineEdit
var _tr_portrait: LineEdit
var _tr_sprite: TextureRect
var _switching_mode := false
var _rows_spin: SpinBox
var _cols_spin: SpinBox
var _palette_buttons: Array = []

# Wild pool drawer — checkboxes over the Pokédex, bound to this stage's segment.
var _wild_panel: Control
var _wild_list: VBoxContainer
var _wild_boxes: Dictionary = {}    # enemy id -> CheckBox
var _wild_filter: LineEdit
var _wild_summary: Label
var _wild_syncing := false          # true while pushing data into the boxes (ignore toggles)


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
	_sidebar = _build_sidebar()
	mid.add_child(_sidebar)

	_center_scroll = ScrollContainer.new()
	_center_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(_center_scroll)
	_canvas = GridCanvas.new()
	_canvas.painter = _paint_cell
	for entry in PALETTE:
		_canvas.colors[entry["ch"]] = entry["color"]
	for mat in ThemePalette.PAINTABLE_MATERIALS:
		_canvas.material_colors[mat] = ThemePalette.color_of(mat)
	_center_scroll.add_child(_canvas)

	# Wild pool drawer, right of the canvas (map mode only).
	_wild_panel = _build_wild_panel()
	mid.add_child(_wild_panel)

	# World View: all stages positioned in one shared grid (hidden until toggled).
	_world_canvas = WorldCanvas.new()
	_world_canvas.visible = false
	# Clip the free-form draw to the canvas rect so panned stages never paint over
	# the toolbar/tabs above it.
	_world_canvas.clip_contents = true
	_world_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for entry in PALETTE:
		_world_canvas.colors[entry["ch"]] = entry["color"]
	_world_canvas.on_move = _on_world_move
	_world_canvas.on_select = _on_world_select
	mid.add_child(_world_canvas)

	# Pokédex: enemies.json library editor (hidden until toggled).
	_pokedex_panel = _build_pokedex_panel()
	_pokedex_panel.visible = false
	mid.add_child(_pokedex_panel)

	# Trainers: trainers.json identity library editor (hidden until toggled).
	_trainers_panel = _build_trainers_panel()
	_trainers_panel.visible = false
	mid.add_child(_trainers_panel)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	root.add_child(_status)

	_load_file()
	_build_wild_checkboxes()  # needs _enemies, so after the load and before any select
	# Start on area 1 (the run's first stage), falling back to the first layout.
	var run_ids := _run_ordered_ids()
	var first_id := String(run_ids[0]) if not run_ids.is_empty() \
			else (_stages.keys()[0] if not _stages.is_empty() else "")
	if first_id != "":
		_select_stage(first_id)
	_sync_dex_picker(_enemies[0]["id"] if not _enemies.is_empty() else "")
	_sync_trainers_picker(_trainers_lib[0]["id"] if not _trainers_lib.is_empty() else "")
	# Open in World View, area 1 selected and centered.
	_set_editor_mode("world")
	_focus_world_on_first_area.call_deferred()


## Center the World View on the run's first area. Deferred a couple of frames so the
## canvas has its laid-out size before we compute the pan from it.
func _focus_world_on_first_area() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var run_ids := _run_ordered_ids()
	if run_ids.is_empty():
		return
	var sid := String(run_ids[0])
	var pos := _layout_pos(sid)
	var size := _stage_size_of(sid)
	var center_tiles := Vector2(pos) + Vector2(size) * 0.5
	_world_canvas.pan = _world_canvas.size * 0.5 - center_tiles * _world_canvas.cell_px
	_world_canvas.queue_redraw()


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
	_view_toggle = Button.new()
	_view_toggle.text = "World View"
	_view_toggle.toggle_mode = true
	_view_toggle.toggled.connect(_on_toggle_world)
	bar.add_child(_view_toggle)
	_dex_toggle = Button.new()
	_dex_toggle.text = "Pokédex"
	_dex_toggle.toggle_mode = true
	_dex_toggle.toggled.connect(_on_toggle_pokedex)
	bar.add_child(_dex_toggle)
	_trainers_toggle = Button.new()
	_trainers_toggle.text = "Trainers"
	_trainers_toggle.toggle_mode = true
	_trainers_toggle.toggled.connect(_on_toggle_trainers)
	bar.add_child(_trainers_toggle)

	bar.add_child(VSeparator.new())
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_on_save)
	bar.add_child(save_btn)
	return bar


func _build_sidebar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(262, 0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(244, 0)
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

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

	# Material override: paints a per-cell appearance on top of the glyph (a wild on
	# water, dirt kept brown in a building area). Picking one switches to the material
	# brush; picking a glyph above switches back. "Inherit" clears the override.
	var mat_header := Label.new()
	mat_header.text = "Material (override)"
	mat_header.add_theme_font_size_override("font_size", 14)
	mat_header.modulate = Color(0.8, 0.85, 0.95)
	box.add_child(mat_header)
	var mat_flow := HFlowContainer.new()
	box.add_child(mat_flow)
	mat_flow.add_child(_material_button("", "Inherit", Color(0.16, 0.17, 0.20)))
	for mat in ThemePalette.PAINTABLE_MATERIALS:
		mat_flow.add_child(_material_button(mat, mat, ThemePalette.color_of(mat)))

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

	# Trainers & teams (this stage's run segment). A leader with a team is a trainer
	# fielding those Pokemon; blank team = legacy single-combatant leader.
	box.add_child(HSeparator.new())
	box.add_child(_meta_label("— Trainers & teams —"))
	box.add_child(_meta_label("Leader trainer id"))
	_leader_trainer_edit = LineEdit.new()
	_leader_trainer_edit.placeholder_text = "e.g. brock (blank = none)"
	box.add_child(_leader_trainer_edit)
	box.add_child(_meta_label("Leader team mode"))
	_leader_mode_pick = OptionButton.new()
	for m in ["sequential", "one_of"]:
		_leader_mode_pick.add_item(m)
	box.add_child(_leader_mode_pick)
	box.add_child(_meta_label("Leader team — Pokemon, comma-sep"))
	_leader_team_edit = LineEdit.new()
	_leader_team_edit.placeholder_text = "geodude,onix (blank = legacy)"
	box.add_child(_leader_team_edit)
	box.add_child(_meta_label("Route trainers (one per `t`):\ntrainer | mode | mon,mon"))
	_route_trainers_edit = TextEdit.new()
	_route_trainers_edit.custom_minimum_size = Vector2(0, 84)
	box.add_child(_route_trainers_edit)
	return panel


# --- Wild pool drawer ---

## Check a Pokémon to put it in this stage's segment `wild_pool`. The pool only says
## *which* species can appear; the map's `w` cells say *how many* actually spawn — so
## either half alone spawns nothing. The summary line reports both, because authoring
## one without the other is silent at runtime.
func _build_wild_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(232, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	box.add_child(_meta_label("— Wild pool —"))
	_wild_summary = Label.new()
	_wild_summary.add_theme_font_size_override("font_size", 12)
	_wild_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_wild_summary)

	var row := HBoxContainer.new()
	_wild_filter = LineEdit.new()
	_wild_filter.placeholder_text = "filter…"
	_wild_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wild_filter.text_changed.connect(func(_t): _refresh_wild_filter())
	row.add_child(_wild_filter)
	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.pressed.connect(_on_wild_clear)
	row.add_child(clear_btn)
	box.add_child(row)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_wild_list = VBoxContainer.new()
	_wild_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_wild_list)
	return panel


## One checkbox per wild-eligible Pokémon, in Dex order. Built once — selecting a
## stage only re-ticks them. Trainer blobs and `is_wild: false` entries are excluded:
## they can't be drawn as a wild, so offering them would author a pool that never fires.
func _build_wild_checkboxes() -> void:
	if _wild_list == null:
		return
	for child in _wild_list.get_children():
		child.queue_free()
	_wild_boxes.clear()
	for e in _pokemon_ordered():
		if not bool(e.get("is_wild", true)):
			continue
		var id := String(e.get("id", ""))
		var num := _dex_num(id)
		var display := String(e.get("name", id))
		var cb := CheckBox.new()
		cb.text = "#%03d  %s" % [num, display] if num < 999 else display
		cb.add_theme_font_size_override("font_size", 13)
		cb.toggled.connect(func(on): _on_wild_toggled(id, on))
		_wild_list.add_child(cb)
		_wild_boxes[id] = cb


func _populate_wild_ui(stage_id: String) -> void:
	if _wild_list == null:
		return
	var idx := _segment_index(stage_id)
	var seg: Dictionary = _segments()[idx] if idx >= 0 else {}
	var pool := {}
	for id in seg.get("wild_pool", []):
		pool[String(id)] = true
	_wild_syncing = true
	for id in _wild_boxes:
		(_wild_boxes[id] as CheckBox).button_pressed = pool.has(id)
	_wild_syncing = false
	_refresh_wild_summary()


func _on_wild_toggled(id: String, on: bool) -> void:
	if _wild_syncing or _stage_id == "":
		return
	var idx := _segment_index(_stage_id)
	if idx < 0:
		return  # orphan stage — not in the run, so it has no pool to write
	var seg: Dictionary = _segments()[idx]
	var pool := _str_array(seg.get("wild_pool", []))
	if on:
		if id not in pool:
			pool.append(id)
	else:
		pool.erase(id)
	# Dex order, so the JSON diff is stable no matter what order they were clicked.
	pool.sort_custom(func(a, b): return _dex_num(String(a)) < _dex_num(String(b)))
	# Always leave the key present, empty or not: run_manager indexes it directly.
	seg["wild_pool"] = pool
	_refresh_wild_summary()


func _on_wild_clear() -> void:
	var idx := _segment_index(_stage_id)
	if idx < 0:
		return
	_segments()[idx]["wild_pool"] = []
	_populate_wild_ui(_stage_id)


func _refresh_wild_filter() -> void:
	var query := _wild_filter.text.strip_edges().to_lower()
	for id in _wild_boxes:
		var cb: CheckBox = _wild_boxes[id]
		cb.visible = query == "" or query in cb.text.to_lower() or query in id.to_lower()


## Species vs `w` cells — the two halves that must both be present to spawn anything.
func _refresh_wild_summary() -> void:
	if _wild_summary == null:
		return
	var idx := _segment_index(_stage_id)
	if idx < 0:
		_wild_summary.text = "Stage is not in the run — no pool to edit."
		_wild_summary.modulate = Color(0.75, 0.75, 0.8)
		return
	var species := _str_array(_segments()[idx].get("wild_pool", [])).size()
	var cells := _count_char("w")
	_wild_summary.text = "%d species · %d `w` cell%s" % [species, cells, "" if cells == 1 else "s"]
	if species > 0 and cells == 0:
		_wild_summary.text += "\n⚠ no `w` on the map — nothing spawns"
		_wild_summary.modulate = Color(1.0, 0.7, 0.5)
	elif cells > 0 and species == 0:
		_wild_summary.text += "\n⚠ empty pool — `w` cells are decorative"
		_wild_summary.modulate = Color(1.0, 0.7, 0.5)
	elif cells == 0:
		_wild_summary.modulate = Color(0.75, 0.75, 0.8)
	else:
		_wild_summary.modulate = Color(0.6, 1.0, 0.6)


func _count_char(ch: String) -> int:
	var n := 0
	for row in _grid:
		for cell in row:
			if String(cell) == ch:
				n += 1
	return n


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


## A material swatch button (override brush). `mat` == "" is the "Inherit" eraser.
func _material_button(mat: String, label: String, color: Color) -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(70, 26)
	btn.text = label
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color.BLACK if color.get_luminance() > 0.5 else Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	var pressed_sb := sb.duplicate()
	pressed_sb.border_color = Color.WHITE
	pressed_sb.set_border_width_all(3)
	btn.add_theme_stylebox_override("pressed", pressed_sb)
	btn.pressed.connect(_on_material_pick.bind(mat))
	_material_buttons.append({"btn": btn, "mat": mat})
	return btn


# --- Actions ---

func _on_palette_pick(ch: String) -> void:
	_active_char = ch
	_brush_mode = "terrain"
	for pb in _palette_buttons:
		pb["btn"].button_pressed = pb["ch"] == ch
	for mb in _material_buttons:
		mb["btn"].button_pressed = false


func _on_material_pick(mat: String) -> void:
	_active_material = mat
	_brush_mode = "material"
	for pb in _palette_buttons:
		pb["btn"].button_pressed = false
	for mb in _material_buttons:
		mb["btn"].button_pressed = mb["mat"] == mat


func _paint_cell(cell: Vector2i) -> void:
	if cell.y < 0 or cell.y >= _grid.size() or cell.x < 0 or cell.x >= _grid[cell.y].size():
		return
	if _brush_mode == "material":
		_materials[cell.y][cell.x] = _active_material
	else:
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
	_explode_layout(layout)
	_name_edit.text = String(layout.get("display_name", ""))
	_gym_name_edit.text = String(layout.get("gym_name", ""))
	_template_pick.select(maxi(0, TEMPLATES.find(String(layout.get("template", "open_field")))))
	_facing_pick.select(maxi(0, FACINGS.find(String(layout.get("gate_facing", "north")))))
	var windows: Dictionary = layout.get("shop_windows", {})
	_center_win.value = int(windows.get("center", 1))
	_mart_win.value = int(windows.get("mart", 2))
	_rows_spin.value = _grid.size()
	_cols_spin.value = _grid[0].size() if not _grid.is_empty() else 0
	_populate_teams_ui(stage_id)
	_populate_wild_ui(stage_id)
	_sync_stage_picker(stage_id)
	_canvas.materials = _materials
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
	var resized_mat: Array = []
	for y in rows:
		var row: Array = []
		var mrow: Array = []
		for x in cols:
			if y < _grid.size() and x < _grid[y].size():
				row.append(_grid[y][x])
				mrow.append(_materials[y][x] if y < _materials.size() and x < _materials[y].size() else "")
			else:
				# new border cells become walls, new interior floor
				var edge := y == 0 or x == 0 or y == rows - 1 or x == cols - 1
				row.append("#" if edge else ".")
				mrow.append("")
		resized.append(row)
		resized_mat.append(mrow)
	_grid = resized
	_materials = resized_mat
	_canvas.materials = _materials
	_canvas.set_grid(_grid)
	_revalidate()


# --- World View (manual stage placement) ---

func _on_toggle_world(pressed: bool) -> void:
	if not _switching_mode:
		_set_editor_mode("world" if pressed else "map")


func _on_toggle_pokedex(pressed: bool) -> void:
	if not _switching_mode:
		_set_editor_mode("pokedex" if pressed else "map")


func _on_toggle_trainers(pressed: bool) -> void:
	if not _switching_mode:
		_set_editor_mode("trainers" if pressed else "map")


## Central switch between the editor's four views (map / world / pokedex / trainers),
## keeping the three toggle buttons mutually exclusive.
func _set_editor_mode(mode: String) -> void:
	_switching_mode = true
	_view_toggle.button_pressed = mode == "world"
	_dex_toggle.button_pressed = mode == "pokedex"
	_trainers_toggle.button_pressed = mode == "trainers"
	_switching_mode = false
	_world_mode = mode == "world"
	_view_toggle.text = "◀ Edit Stage" if _world_mode else "World View"
	_sidebar.visible = mode == "map"
	_center_scroll.visible = mode == "map"
	_wild_panel.visible = mode == "map"
	_world_canvas.visible = mode == "world"
	_pokedex_panel.visible = mode == "pokedex"
	_trainers_panel.visible = mode == "trainers"
	match mode:
		"world":
			_enter_world_view()
		"pokedex":
			_sync_dex_picker(_dex_current)
		"trainers":
			_sync_trainers_picker(_tr_current)
		_:
			_revalidate()


func _enter_world_view() -> void:
	_commit_metadata_from_ui()
	_seed_world_positions()
	_refresh_world_canvas()


## Give every stage a world_pos. Existing ones are kept; missing ones are seeded by
## the same legacy telescope walk the world builder falls back to, so the view
## matches what the game would build before any manual stitching.
func _seed_world_positions() -> void:
	var prev_exit_world := Vector2i.ZERO
	var first := true
	for sid in _ordered_ids():
		var layout: Dictionary = _stages[sid]
		var rows := _stage_rows(sid)
		var pos: Vector2i
		if _has_world_pos(layout):
			pos = _layout_pos(sid)
		elif first:
			pos = Vector2i.ZERO
			layout["world_pos"] = [0, 0]
		else:
			pos = prev_exit_world + Vector2i(0, 1) - _find_char(rows, "S")
			layout["world_pos"] = [pos.x, pos.y]
		prev_exit_world = pos + _exit_local(rows)
		first = false


func _refresh_world_canvas() -> void:
	var defs: Array = []
	for sid in _ordered_ids():
		defs.append({
			"id": sid, "rows": _stage_rows(sid),
			"pos": _layout_pos(sid), "order": _segment_index(sid),
		})
	_world_canvas.set_stages(defs)
	_world_canvas.selected_id = _stage_id
	_world_checks()


func _on_world_move(id: String, new_pos: Vector2i) -> void:
	_stages[id]["world_pos"] = [new_pos.x, new_pos.y]
	_world_checks()


func _on_world_select(id: String) -> void:
	_select_stage(id)  # keeps _stage_id/_grid/picker in sync so grid-mode edits the clicked stage
	_refresh_world_canvas()  # restores selection highlight + world status (over _select_stage's)


## Overlap (rect intersection) + reachability (flood the union of walkable cells
## from the run's first spawn). Warnings go to the status line; offenders outline red.
func _world_checks() -> void:
	var run_ids := _run_ordered_ids()
	var overlap := {}
	var pairs: Array = []
	var shown := _ordered_ids()
	for i in shown.size():
		for j in range(i + 1, shown.size()):
			if _stage_rect(shown[i]).intersects(_stage_rect(shown[j])):
				overlap[shown[i]] = true
				overlap[shown[j]] = true
				if pairs.size() < 3:
					pairs.append("%s×%s" % [shown[i], shown[j]])
	_world_canvas.overlap_ids = overlap

	var unreachable := _unreachable_stages(run_ids)
	var msgs: Array = []
	if not overlap.is_empty():
		msgs.append("⚠ overlap: " + "  ".join(pairs) + ("  +more" if overlap.size() > 6 else ""))
	if not unreachable.is_empty():
		msgs.append("⚠ unreachable: " + "  ".join(unreachable.slice(0, 5)))
	if msgs.is_empty():
		_status.text = "✓ %d stages placed — all connected, no overlaps" % run_ids.size()
		_status.modulate = Color(0.6, 1.0, 0.6)
	else:
		_status.text = "   ".join(msgs)
		_status.modulate = Color(1.0, 0.7, 0.5)
	_world_canvas.queue_redraw()


## Run stages the player can never stand in, or whose content is walled off —
## walking the union of every run stage's walkable cells from the world's single
## spawn (barriers block). Stages carry no spawn of their own, so a stage counts
## as reached when any of its walkable cells is, and as broken when a cell that
## the run must touch (`CONTENT_CHARS`) is not. Decorative pockets sealed behind
## scenery are intentional and ignored.
func _unreachable_stages(run_ids: Array) -> Array:
	if run_ids.is_empty():
		return []
	var walk := {}
	for sid in run_ids:
		var rows := _stage_rows(sid)
		var pos := _layout_pos(sid)
		for y in rows.size():
			var row := String(rows[y])
			for x in row.length():
				if row[x] not in BARRIER_CHARS:
					walk[pos + Vector2i(x, y)] = true
	var spawn_local := _find_char(_stage_rows(run_ids[0]), "S")
	if spawn_local.x < 0:
		return ["(no spawn S in %s)" % run_ids[0]]
	var seen := {_layout_pos(run_ids[0]) + spawn_local: true}
	var frontier: Array = [_layout_pos(run_ids[0]) + spawn_local]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if walk.has(n) and not seen.has(n):
				seen[n] = true
				frontier.append(n)
	var bad: Array = []
	for sid in run_ids:
		var rows := _stage_rows(sid)
		var pos := _layout_pos(sid)
		var touched := false
		var sealed := false
		for y in rows.size():
			var row := String(rows[y])
			for x in row.length():
				if row[x] in BARRIER_CHARS:
					continue
				if seen.has(pos + Vector2i(x, y)):
					touched = true
				elif row[x] in CONTENT_CHARS:
					sealed = true
		if not touched or sealed:
			bad.append(sid)
	return bad


# world-view data helpers (read the editor's raw grids; no Balance dependency)

func _stage_rows(sid: String) -> Array:
	return StageLayout.glyph_rows(_stages[sid])


func _find_char(rows: Array, ch: String) -> Vector2i:
	for y in rows.size():
		var x := String(rows[y]).find(ch)
		if x >= 0:
			return Vector2i(x, y)
	return Vector2i(-1, -1)


## Exit cell = `X`, or the leader `L` when there is no `X` (matches StageLayout).
func _exit_local(rows: Array) -> Vector2i:
	var x := _find_char(rows, "X")
	return x if x.x >= 0 else _find_char(rows, "L")


func _stage_size_of(sid: String) -> Vector2i:
	var rows := _stage_rows(sid)
	return Vector2i(String(rows[0]).length() if not rows.is_empty() else 0, rows.size())


func _stage_rect(sid: String) -> Rect2i:
	return Rect2i(_layout_pos(sid), _stage_size_of(sid))


func _has_world_pos(layout: Dictionary) -> bool:
	var wp = layout.get("world_pos", null)
	return wp is Array and wp.size() == 2


func _layout_pos(sid: String) -> Vector2i:
	var wp: Variant = _stages[sid].get("world_pos", [0, 0])
	if wp is Array and wp.size() == 2:
		return Vector2i(int(wp[0]), int(wp[1]))
	return Vector2i.ZERO


## Stage ids that are actually in the run (segment order) — what the game builds.
func _run_ordered_ids() -> Array:
	var out: Array = []
	for seg in _segments():
		var sid := String(seg.get("id", ""))
		if _stages.has(sid):
			out.append(sid)
	return out


# --- Pokédex: enemies.json library editor ---

func _build_pokedex_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(540, 0)
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	var bar := HBoxContainer.new()
	bar.add_child(_label("Pokémon:"))
	_dex_picker = OptionButton.new()
	_dex_picker.item_selected.connect(_on_dex_picked)
	bar.add_child(_dex_picker)
	var newb := Button.new()
	newb.text = "New"
	newb.pressed.connect(_on_dex_new)
	bar.add_child(newb)
	var delb := Button.new()
	delb.text = "Delete"
	delb.pressed.connect(_on_dex_delete)
	bar.add_child(delb)
	var saveb := Button.new()
	saveb.text = "Save Pokédex"
	saveb.pressed.connect(_on_dex_save)
	bar.add_child(saveb)
	box.add_child(bar)

	_dex_sprite = TextureRect.new()
	_dex_sprite.custom_minimum_size = Vector2(96, 96)
	_dex_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dex_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(_dex_sprite)

	box.add_child(_meta_label("Id (unique, snake_case) — sprite = art/creatures/<id>.png"))
	_dex_id = LineEdit.new()
	box.add_child(_dex_id)
	box.add_child(_meta_label("Name"))
	_dex_name = LineEdit.new()
	box.add_child(_dex_name)
	box.add_child(_meta_label("Type"))
	_dex_type = OptionButton.new()
	for t in POKE_TYPES:
		_dex_type.add_item(t)
	box.add_child(_dex_type)
	var stat_row := HBoxContainer.new()
	stat_row.add_child(_meta_label("Max HP"))
	_dex_hp = _spin(1, 400, 20)
	stat_row.add_child(_dex_hp)
	stat_row.add_child(_meta_label("XP"))
	_dex_xp = _spin(0, 400, 5)
	stat_row.add_child(_dex_xp)
	box.add_child(stat_row)
	var flag_row := HBoxContainer.new()
	_dex_wild = CheckBox.new()
	_dex_wild.text = "is_wild"
	flag_row.add_child(_dex_wild)
	_dex_boss = CheckBox.new()
	_dex_boss.text = "is_boss"
	flag_row.add_child(_dex_boss)
	box.add_child(flag_row)

	box.add_child(_meta_label("Moves — one per line:  Name | atk/util | weight | phase | effects\n"
		+ "effects (;-sep): damage:N[:ignore]  block:N:self  heal:N:self\n"
		+ "  status:poison:MAG:DUR:enemy  cond:defenseless:DUR:enemy  shuffle"))
	_dex_moves = TextEdit.new()
	_dex_moves.custom_minimum_size = Vector2(0, 170)
	box.add_child(_dex_moves)
	box.add_child(_meta_label("Boss pattern (move names, comma-sep) + loop start (bosses only)"))
	var bp_row := HBoxContainer.new()
	_dex_boss_pattern = LineEdit.new()
	_dex_boss_pattern.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bp_row.add_child(_dex_boss_pattern)
	_dex_loop_start = _spin(0, 20, 0)
	bp_row.add_child(_dex_loop_start)
	box.add_child(bp_row)
	return panel


func _dex_index(id: String) -> int:
	for i in _enemies.size():
		if String(_enemies[i].get("id", "")) == id:
			return i
	return -1


## National Dex number for a Pokémon id (999 for custom/non-Gen1, sorted last).
func _dex_num(id: String) -> int:
	var idx := GEN1_ORDER.find(id.replace("-", "_"))
	return idx + 1 if idx >= 0 else 999


## enemies.json entries that are Pokémon (not trainer blobs), in Dex order.
func _pokemon_ordered() -> Array:
	var out: Array = []
	for e in _enemies:
		if String(e.get("id", "")) not in TRAINER_BLOB_IDS:
			out.append(e)
	out.sort_custom(func(a, b): return _dex_num(String(a.get("id", ""))) < _dex_num(String(b.get("id", ""))))
	return out


func _sync_dex_picker(selected_id: String) -> void:
	if _dex_picker == null:
		return
	_dex_picker.clear()
	var sel := 0
	var i := 0
	for e in _pokemon_ordered():
		var id := String(e.get("id", ""))
		var num := _dex_num(id)
		var prefix := "#%03d  " % num if num < 999 else "—  "
		_dex_picker.add_item("%s%s  (%s)" % [prefix, String(e.get("name", "?")), id])
		_dex_picker.set_item_metadata(i, id)
		if id == selected_id:
			sel = i
		i += 1
	if _dex_picker.item_count > 0:
		_dex_picker.select(sel)
		_dex_select(String(_dex_picker.get_item_metadata(sel)))


func _on_dex_picked(idx: int) -> void:
	_dex_select(String(_dex_picker.get_item_metadata(idx)))


func _dex_select(id: String) -> void:
	_dex_commit()  # save edits to the previously selected Pokémon
	var idx := _dex_index(id)
	if idx < 0:
		return
	_dex_current = id
	var e: Dictionary = _enemies[idx]
	_dex_id.text = id
	_dex_name.text = String(e.get("name", ""))
	_dex_type.select(maxi(0, POKE_TYPES.find(String(e.get("pokemon_type", "NORMAL")))))
	_dex_hp.value = int(e.get("max_hp", 20))
	_dex_xp.value = int(e.get("xp_reward", 5))
	_dex_wild.button_pressed = bool(e.get("is_wild", true))
	_dex_boss.button_pressed = bool(e.get("is_boss", false))
	_dex_moves.text = _format_moves(e.get("action_pool", []))
	_dex_boss_pattern.text = _format_boss_pattern(e)
	_dex_loop_start.value = int(e.get("boss_pattern_loop_start", 0))
	_update_dex_sprite(id)


func _update_dex_sprite(id: String) -> void:
	if _dex_sprite != null:
		_dex_sprite.texture = CreatureArt.get_texture(id)


func _on_dex_new() -> void:
	_dex_commit()
	var base := "new_pokemon"
	var id := base
	var n := 1
	while _dex_index(id) >= 0:
		n += 1
		id = "%s_%d" % [base, n]
	_enemies.append({
		"id": id, "name": "New Pokémon", "pokemon_type": "NORMAL", "max_hp": 20,
		"is_wild": true, "is_boss": false, "xp_reward": 5,
		"action_pool": [{"id": "tackle", "name": "Tackle", "is_attack": true,
			"base_weight": 3, "preferred_phase": "any",
			"effects": [{"type": "damage", "magnitude": 5}]}],
	})
	_sync_dex_picker(id)


func _on_dex_delete() -> void:
	var idx := _dex_index(_dex_current)
	if idx < 0:
		return
	_enemies.remove_at(idx)
	_dex_current = ""
	_sync_dex_picker(_enemies[0]["id"] if not _enemies.is_empty() else "")


## Read the form back into the currently-selected Pokémon dict (id rename allowed).
func _dex_commit() -> void:
	if _dex_id == null or _dex_current == "":
		return
	var idx := _dex_index(_dex_current)
	if idx < 0:
		return
	var e: Dictionary = _enemies[idx]
	var new_id := _dex_id.text.strip_edges()
	if new_id != "" and (new_id == _dex_current or _dex_index(new_id) < 0):
		e["id"] = new_id
		_dex_current = new_id
	e["name"] = _dex_name.text
	e["pokemon_type"] = POKE_TYPES[_dex_type.selected]
	e["max_hp"] = int(_dex_hp.value)
	e["xp_reward"] = int(_dex_xp.value)
	e["is_wild"] = _dex_wild.button_pressed
	e["is_boss"] = _dex_boss.button_pressed
	e["action_pool"] = _parse_moves(_dex_moves.text)
	var pattern := _parse_boss_pattern(_dex_boss_pattern.text, e["action_pool"])
	if pattern.is_empty():
		e.erase("boss_pattern")
		e.erase("boss_pattern_loop_start")
	else:
		e["boss_pattern"] = pattern
		e["boss_pattern_loop_start"] = int(_dex_loop_start.value)


func _on_dex_save() -> void:
	_dex_commit()
	_enemies_all["enemies"] = _enemies
	var f := FileAccess.open(ENEMIES_PATH, FileAccess.WRITE)
	if f == null:
		_status.text = "SAVE FAILED: cannot open %s" % ENEMIES_PATH
		_status.modulate = Color(1, 0.5, 0.5)
		return
	f.store_string(JSON.stringify(_enemies_all, "  "))
	f.close()
	_status.text = "Saved %d Pokémon to enemies.json." % _enemies.size()
	_status.modulate = Color(0.6, 1.0, 0.6)
	_sync_dex_picker(_dex_current)


# Moveset DSL: "Name | atk/util | weight | phase | eff;eff"

static func _move_id_from_name(name: String) -> String:
	return name.strip_edges().to_lower().replace(" ", "_").replace("-", "_")


func _format_moves(pool: Array) -> String:
	var lines: Array = []
	for m in pool:
		var effs: Array = []
		for ef in m.get("effects", []):
			effs.append(_format_effect(ef))
		lines.append("%s | %s | %d | %s | %s" % [
			String(m.get("name", "Move")),
			"atk" if bool(m.get("is_attack", true)) else "util",
			int(m.get("base_weight", 1)),
			String(m.get("preferred_phase", "any")),
			" ; ".join(effs),
		])
	return "\n".join(lines)


func _parse_moves(text: String) -> Array:
	var out: Array = []
	for line in text.split("\n"):
		var parts := String(line).split("|")
		if parts.size() < 1 or String(parts[0]).strip_edges() == "":
			continue
		var name := String(parts[0]).strip_edges()
		var effs: Array = []
		if parts.size() >= 5:
			for tok in String(parts[4]).split(";"):
				var ef := _parse_effect(String(tok).strip_edges())
				if not ef.is_empty():
					effs.append(ef)
		out.append({
			"id": _move_id_from_name(name),
			"name": name,
			"is_attack": parts.size() < 2 or String(parts[1]).strip_edges() != "util",
			"base_weight": int(String(parts[2]).strip_edges()) if parts.size() >= 3 else 1,
			"preferred_phase": String(parts[3]).strip_edges() if parts.size() >= 4 else "any",
			"effects": effs,
		})
	return out


func _format_effect(ef: Dictionary) -> String:
	var t := String(ef.get("type", ""))
	match t:
		"damage":
			var s := "damage:%d" % int(ef.get("magnitude", 0))
			return s + ":ignore" if bool(ef.get("ignore_block", false)) else s
		"block":
			return "block:%d:%s" % [int(ef.get("magnitude", 0)), String(ef.get("target", "self"))]
		"heal":
			return "heal:%d:%s" % [int(ef.get("magnitude", 0)), String(ef.get("target", "self"))]
		"status":
			return "status:%s:%d:%d:%s" % [String(ef.get("status", "")),
				int(ef.get("magnitude", 0)), int(ef.get("duration", 0)),
				String(ef.get("target", "enemy"))]
		"apply_condition":
			return "cond:%s:%d:%s" % [String(ef.get("condition", "")),
				int(ef.get("duration", 1)), String(ef.get("target", "enemy"))]
		"shuffle_hand":
			return "shuffle"
	return t


func _parse_effect(tok: String) -> Dictionary:
	if tok == "":
		return {}
	var p := tok.split(":")
	var kind := String(p[0]).strip_edges()
	match kind:
		"damage":
			var d := {"type": "damage", "magnitude": int(p[1]) if p.size() > 1 else 0}
			if p.size() > 2 and String(p[2]).strip_edges() == "ignore":
				d["ignore_block"] = true
			return d
		"block":
			return {"type": "block", "magnitude": int(p[1]) if p.size() > 1 else 0,
				"target": String(p[2]) if p.size() > 2 else "self"}
		"heal":
			return {"type": "heal", "magnitude": int(p[1]) if p.size() > 1 else 0,
				"target": String(p[2]) if p.size() > 2 else "self"}
		"status":
			var s := {"type": "status", "status": String(p[1]).strip_edges() if p.size() > 1 else "poison"}
			if p.size() > 2 and int(p[2]) > 0:
				s["magnitude"] = int(p[2])
			if p.size() > 3 and int(p[3]) > 0:
				s["duration"] = int(p[3])
			s["target"] = String(p[4]).strip_edges() if p.size() > 4 else "enemy"
			return s
		"cond":
			return {"type": "apply_condition", "condition": String(p[1]) if p.size() > 1 else "defenseless",
				"duration": int(p[2]) if p.size() > 2 else 1,
				"target": String(p[3]) if p.size() > 3 else "enemy"}
		"shuffle":
			return {"type": "shuffle_hand"}
	return {}


func _format_boss_pattern(e: Dictionary) -> String:
	var id_to_name := {}
	for m in e.get("action_pool", []):
		id_to_name[String(m.get("id", ""))] = String(m.get("name", ""))
	var names: Array = []
	for mid in e.get("boss_pattern", []):
		names.append(String(id_to_name.get(String(mid), String(mid))))
	return ", ".join(names)


func _parse_boss_pattern(text: String, pool: Array) -> Array:
	var name_to_id := {}
	for m in pool:
		name_to_id[String(m.get("name", "")).to_lower()] = String(m.get("id", ""))
	var out: Array = []
	for part in text.split(","):
		var nm := String(part).strip_edges()
		if nm == "":
			continue
		out.append(String(name_to_id.get(nm.to_lower(), _move_id_from_name(nm))))
	return out


# --- Trainers: trainers.json identity library ---

func _build_trainers_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	var bar := HBoxContainer.new()
	bar.add_child(_label("Trainer:"))
	_tr_picker = OptionButton.new()
	_tr_picker.item_selected.connect(_on_tr_picked)
	bar.add_child(_tr_picker)
	var newb := Button.new()
	newb.text = "New"
	newb.pressed.connect(_on_tr_new)
	bar.add_child(newb)
	var delb := Button.new()
	delb.text = "Delete"
	delb.pressed.connect(_on_tr_delete)
	bar.add_child(delb)
	var saveb := Button.new()
	saveb.text = "Save Trainers"
	saveb.pressed.connect(_on_tr_save)
	bar.add_child(saveb)
	box.add_child(bar)

	_tr_sprite = TextureRect.new()
	_tr_sprite.custom_minimum_size = Vector2(96, 96)
	_tr_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tr_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(_tr_sprite)

	box.add_child(_meta_label("Trainer id (unique, referenced by segment leader / trainers)"))
	_tr_id = LineEdit.new()
	box.add_child(_tr_id)
	box.add_child(_meta_label("Display name"))
	_tr_name = LineEdit.new()
	box.add_child(_tr_name)
	box.add_child(_meta_label("Portrait id — art/trainers/<id>.png (blank = use trainer id)"))
	_tr_portrait = LineEdit.new()
	_tr_portrait.text_changed.connect(func(_t): _update_tr_sprite())
	box.add_child(_tr_portrait)
	box.add_child(_meta_label("A trainer's Pokémon team is set per placement in a stage's\n"
		+ "Trainers & teams panel — not here. This is just the identity."))
	return panel


func _tr_index(id: String) -> int:
	for i in _trainers_lib.size():
		if String(_trainers_lib[i].get("id", "")) == id:
			return i
	return -1


func _sync_trainers_picker(selected_id: String) -> void:
	if _tr_picker == null:
		return
	_tr_picker.clear()
	var sel := 0
	for i in _trainers_lib.size():
		var t: Dictionary = _trainers_lib[i]
		_tr_picker.add_item("%s  (%s)" % [String(t.get("name", "?")), String(t.get("id", "?"))])
		_tr_picker.set_item_metadata(i, String(t.get("id", "")))
		if String(t.get("id", "")) == selected_id:
			sel = i
	if _tr_picker.item_count > 0:
		_tr_picker.select(sel)
		_tr_select(String(_tr_picker.get_item_metadata(sel)))


func _on_tr_picked(idx: int) -> void:
	_tr_select(String(_tr_picker.get_item_metadata(idx)))


func _tr_select(id: String) -> void:
	_tr_commit()
	var idx := _tr_index(id)
	if idx < 0:
		return
	_tr_current = id
	var t: Dictionary = _trainers_lib[idx]
	_tr_id.text = id
	_tr_name.text = String(t.get("name", ""))
	_tr_portrait.text = String(t.get("portrait_id", ""))
	_update_tr_sprite()


func _update_tr_sprite() -> void:
	if _tr_sprite == null:
		return
	var pid := _tr_portrait.text.strip_edges()
	if pid == "":
		pid = _tr_id.text.strip_edges()
	_tr_sprite.texture = CreatureArt.get_texture(pid) if pid != "" else null


func _on_tr_new() -> void:
	_tr_commit()
	var base := "new_trainer"
	var id := base
	var n := 1
	while _tr_index(id) >= 0:
		n += 1
		id = "%s_%d" % [base, n]
	_trainers_lib.append({"id": id, "name": "New Trainer", "portrait_id": ""})
	_sync_trainers_picker(id)


func _on_tr_delete() -> void:
	var idx := _tr_index(_tr_current)
	if idx < 0:
		return
	_trainers_lib.remove_at(idx)
	_tr_current = ""
	_sync_trainers_picker(_trainers_lib[0]["id"] if not _trainers_lib.is_empty() else "")


func _tr_commit() -> void:
	if _tr_id == null or _tr_current == "":
		return
	var idx := _tr_index(_tr_current)
	if idx < 0:
		return
	var t: Dictionary = _trainers_lib[idx]
	var new_id := _tr_id.text.strip_edges()
	if new_id != "" and (new_id == _tr_current or _tr_index(new_id) < 0):
		t["id"] = new_id
		_tr_current = new_id
	t["name"] = _tr_name.text
	t["portrait_id"] = _tr_portrait.text.strip_edges()


func _on_tr_save() -> void:
	_tr_commit()
	_trainers_all["trainers"] = _trainers_lib
	var f := FileAccess.open(TRAINERS_PATH, FileAccess.WRITE)
	if f == null:
		_status.text = "SAVE FAILED: cannot open %s" % TRAINERS_PATH
		_status.modulate = Color(1, 0.5, 0.5)
		return
	f.store_string(JSON.stringify(_trainers_all, "  "))
	f.close()
	_status.text = "Saved %d trainers to trainers.json." % _trainers_lib.size()
	_status.modulate = Color(0.6, 1.0, 0.6)
	_sync_trainers_picker(_tr_current)


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
	# `cells` (glyph + material override per cell) is the engine input; the legacy
	# bare-glyph `grid` is dropped so there's a single source of truth.
	layout["cells"] = _build_cells()
	layout.erase("grid")
	layout["display_name"] = _name_edit.text
	layout["template"] = TEMPLATES[_template_pick.selected]
	layout["gate_facing"] = FACINGS[_facing_pick.selected]
	layout["shop_windows"] = {"center": int(_center_win.value), "mart": int(_mart_win.value)}
	if _gym_name_edit.text.strip_edges() == "":
		layout.erase("gym_name")
	else:
		layout["gym_name"] = _gym_name_edit.text
	_commit_teams_to_segment()


# --- Trainers & teams (run segment) ---

func _populate_teams_ui(stage_id: String) -> void:
	if _leader_trainer_edit == null:
		return
	var idx := _segment_index(stage_id)
	var seg: Dictionary = _segments()[idx] if idx >= 0 else {}
	_leader_trainer_edit.text = String(seg.get("leader", ""))
	_leader_mode_pick.select(1 if String(seg.get("leader_team_mode", "sequential")) == "one_of" else 0)
	_leader_team_edit.text = ",".join(_str_array(seg.get("leader_team", [])))
	var lines: Array = []
	for tr in seg.get("trainers", []):
		lines.append("%s | %s | %s" % [
			String(tr.get("trainer", "")), String(tr.get("mode", "sequential")),
			",".join(_str_array(tr.get("team", []))),
		])
	_route_trainers_edit.text = "\n".join(lines)


func _commit_teams_to_segment() -> void:
	if _leader_trainer_edit == null or _stage_id == "":
		return
	var idx := _segment_index(_stage_id)
	if idx < 0:
		return  # orphan stage — not in the run, nothing to write
	var seg: Dictionary = _segments()[idx]
	var leader_trainer := _leader_trainer_edit.text.strip_edges()
	if leader_trainer != "":
		seg["leader"] = leader_trainer
	var team := _parse_id_list(_leader_team_edit.text)
	if team.is_empty():
		seg.erase("leader_team")
		seg.erase("leader_team_mode")
	else:
		seg["leader_team"] = team
		seg["leader_team_mode"] = ["sequential", "one_of"][_leader_mode_pick.selected]
	var specs: Array = []
	for line in _route_trainers_edit.text.split("\n"):
		var parts := String(line).split("|")
		if parts.size() < 3 or String(parts[0]).strip_edges() == "":
			continue
		specs.append({
			"trainer": String(parts[0]).strip_edges(),
			"mode": String(parts[1]).strip_edges(),
			"team": _parse_id_list(String(parts[2])),
		})
	if specs.is_empty():
		seg.erase("trainers")
	else:
		seg["trainers"] = specs


static func _parse_id_list(text: String) -> Array:
	var out: Array = []
	for part in text.split(","):
		var id := String(part).strip_edges()
		if id != "":
			out.append(id)
	return out


static func _str_array(a) -> Array:
	var out: Array = []
	for v in a:
		out.append(String(v))
	return out


# --- Validation ---

func _revalidate() -> void:
	_refresh_wild_summary()  # painting a `w` changes the pool-vs-cells balance
	var run_ids := _run_ordered_ids()
	var is_first: bool = not run_ids.is_empty() and String(run_ids[0]) == _stage_id
	var issues := _validate(_grid, is_first)
	if issues.is_empty():
		_status.text = "✓ Valid — %d×%d" % [_grid[0].size() if not _grid.is_empty() else 0, _grid.size()]
		_status.modulate = Color(0.6, 1.0, 0.6)
	else:
		_status.text = "✗ " + "   ".join(issues)
		_status.modulate = Color(1.0, 0.7, 0.5)


## Returns a list of human-readable problems with one stage's grid (empty = valid).
## `is_first` = the run's opening stage, the only one carrying the world's spawn.
##
## Glyph rules only. Reachability is deliberately absent: stages are stitched by
## `world_pos` and a stage's cells are frequently reachable only through its
## neighbour, so no single-stage flood can answer it — World View's `_world_checks`
## walks the stitched world instead.
static func _validate(grid: Array, is_first: bool) -> Array:
	var issues: Array = []
	if grid.is_empty():
		return ["empty grid"]
	var width: int = grid[0].size()
	var s := 0
	var l := 0
	var x_exit := 0
	for y in grid.size():
		if grid[y].size() != width:
			issues.append("row %d wrong length" % y)
		for x in grid[y].size():
			match String(grid[y][x]):
				"S": s += 1
				"L": l += 1
				"X": x_exit += 1
	if is_first:
		if s != 1:
			issues.append("run's first stage needs exactly 1 spawn (S), have %d" % s)
	elif s != 0:
		issues.append("only the run's first stage may have a spawn (S), have %d" % s)
	# 0 leaders = a connector stage (nav only). Gyms/final need one — checked at load.
	if l > 1:
		issues.append("at most 1 leader (L), have %d" % l)
	if x_exit > 1:
		issues.append("at most 1 exit (X), have %d" % x_exit)
	# An exit gate is opened by this stage's leader falling; with no leader there
	# is nothing to open it, so it gates nothing.
	if x_exit == 1 and l == 0:
		issues.append("exit (X) but no leader (L) to open it")
	return issues


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
	var ef := FileAccess.open(ENEMIES_PATH, FileAccess.READ)
	if ef != null:
		var ed: Variant = JSON.parse_string(ef.get_as_text())
		ef.close()
		if ed is Dictionary:
			_enemies_all = ed
			_enemies = ed.get("enemies", [])
	var tf := FileAccess.open(TRAINERS_PATH, FileAccess.READ)
	if tf != null:
		var td: Variant = JSON.parse_string(tf.get_as_text())
		tf.close()
		if td is Dictionary:
			_trainers_all = td
			_trainers_lib = td.get("trainers", [])


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


## Load a layout (either the structured `cells` or legacy `grid`) into the two
## parallel paint layers: `_grid` (glyph per cell) and `_materials` ("" = inherit).
func _explode_layout(layout: Dictionary) -> void:
	_grid = []
	_materials = []
	for row in StageLayout.cell_rows(layout):
		var grow: Array = []
		var mrow: Array = []
		for c in row:
			grow.append(String(c["g"]))
			mrow.append(String(c["m"]))
		_grid.append(grow)
		_materials.append(mrow)


## Merge the two paint layers into the compact `cells` format. A row with no
## overrides stays a plain glyph string (identical to the old grid row — diff-clean);
## a row with any override becomes an array where each cell is a bare glyph string
## or a {g, m} object. This is the engine input.
func _build_cells() -> Array:
	var out: Array = []
	for y in _grid.size():
		var row_has_override := false
		for x in _grid[y].size():
			if y < _materials.size() and x < _materials[y].size() and String(_materials[y][x]) != "":
				row_has_override = true
				break
		if not row_has_override:
			out.append("".join(_grid[y]))
			continue
		var row: Array = []
		for x in _grid[y].size():
			var g := String(_grid[y][x])
			var m := String(_materials[y][x]) if y < _materials.size() and x < _materials[y].size() else ""
			row.append({"g": g, "m": m} if m != "" else g)
		out.append(row)
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
	const TERRAIN := [".", "#", "_", "=", ",", "s", "T", "H", "^", "B", "~", "*"]
	var grid: Array = []
	var materials: Array = []       # parallel override layer; "" = inherit
	var colors: Dictionary = {}
	var material_colors: Dictionary = {}
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
				# Base color = the material override if this cell has one, else the glyph's.
				var mat := String(materials[y][x]) if y < materials.size() and x < materials[y].size() else ""
				var col: Color = material_colors.get(mat, colors.get(ch, Color(0.10, 0.11, 0.13))) \
						if mat != "" else colors.get(ch, Color(0.10, 0.11, 0.13))
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


## World View canvas: draws every stage at its world_pos in a shared grid and lets
## the author drag stages to stitch them. Pan on empty space, wheel to zoom.
class WorldCanvas extends Control:
	const BARRIER := {
		"#": true, "T": true, "H": true, "^": true, "B": true,
		"b": true, "+": true, "O": true, "~": true, "*": true, "I": true,
	}
	var stages: Array = []          # [{id, rows:Array[String], pos:Vector2i, order:int}]
	var colors: Dictionary = {}
	var selected_id := ""
	var overlap_ids: Dictionary = {}
	var cell_px := 8.0
	var pan := Vector2(60, 60)
	var on_move: Callable
	var on_select: Callable

	var _drag_id := ""
	var _grab_offset := Vector2i.ZERO
	var _panning := false
	var _pan_last := Vector2.ZERO

	func set_stages(s: Array) -> void:
		stages = s
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for st in stages:
			var rows: Array = st["rows"]
			if rows.is_empty():
				continue
			var base := pan + Vector2(st["pos"]) * cell_px
			for y in rows.size():
				var row := String(rows[y])
				for x in row.length():
					var ch := row[x]
					var col: Color = colors.get(ch, Color(0.10, 0.11, 0.13))
					draw_rect(Rect2(base + Vector2(x, y) * cell_px, Vector2(cell_px, cell_px)), col)
					if cell_px >= 11.0 and ch in ["S", "X", "L"]:
						draw_string(font, base + Vector2(x * cell_px + 1, (y + 1) * cell_px - 2),
								ch, HORIZONTAL_ALIGNMENT_LEFT, -1, int(cell_px * 0.9), Color.BLACK)
			var w := String(rows[0]).length()
			var rect := Rect2(base, Vector2(w, rows.size()) * cell_px)
			var bcol := Color(1, 0.3, 0.3) if overlap_ids.has(st["id"]) \
					else (Color(1, 0.9, 0.35) if st["id"] == selected_id else Color(0.45, 0.47, 0.55))
			draw_rect(rect, bcol, false, 2.0)
			draw_string(font, base + Vector2(2, -4),
					"%d %s" % [int(st["order"]) + 1, st["id"]],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.88, 0.93, 1.0))

	func _cell_at(mouse: Vector2) -> Vector2i:
		return Vector2i(floori((mouse.x - pan.x) / cell_px), floori((mouse.y - pan.y) / cell_px))

	func _pos_of(id: String) -> Vector2i:
		for st in stages:
			if st["id"] == id:
				return st["pos"]
		return Vector2i.ZERO

	func _stage_at(mouse: Vector2) -> String:
		var c := _cell_at(mouse)
		for i in range(stages.size() - 1, -1, -1):  # topmost (last drawn) first
			var st: Dictionary = stages[i]
			var rows: Array = st["rows"]
			if rows.is_empty():
				continue
			var p: Vector2i = st["pos"]
			var w := String(rows[0]).length()
			if c.x >= p.x and c.x < p.x + w and c.y >= p.y and c.y < p.y + rows.size():
				return st["id"]
		return ""

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				_zoom(1.15, event.position)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				_zoom(1.0 / 1.15, event.position)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					var id := _stage_at(event.position)
					if id != "":
						_drag_id = id
						_grab_offset = _cell_at(event.position) - _pos_of(id)
						if on_select.is_valid():
							on_select.call(id)
					else:
						_panning = true
						_pan_last = event.position
				else:
					_drag_id = ""
					_panning = false
		elif event is InputEventMouseMotion:
			if _drag_id != "":
				var new_pos := _cell_at(event.position) - _grab_offset
				for st in stages:
					if st["id"] == _drag_id:
						st["pos"] = new_pos
				queue_redraw()
				if on_move.is_valid():
					on_move.call(_drag_id, new_pos)
			elif _panning:
				pan += event.position - _pan_last
				_pan_last = event.position
				queue_redraw()

	func _zoom(factor: float, center: Vector2) -> void:
		var world_before := (center - pan) / cell_px
		cell_px = clampf(cell_px * factor, 3.0, 40.0)
		pan = center - world_before * cell_px
		queue_redraw()
