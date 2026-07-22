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
const TerrainTex = preload("res://scripts/world/terrain_tex.gd")

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

const TEMPLATES := ["open_field", "forest_maze", "cave_branches", "town_pocket", "gym_arena",
	"big_city", "ship_interior", "corporate", "mansion", "volcanic", "bridge", "plateau"]
const FACINGS := ["north", "east", "south", "west"]

## Object markers (a cell's `o`) — the secondary brush, painted over walkable terrain.
const OBJECTS := [
	{"ch": "S", "name": "Spawn", "color": Color(0.20, 0.75, 0.85)},
	{"ch": "X", "name": "Exit", "color": Color(0.90, 0.90, 0.95)},
	{"ch": "c", "name": "Center", "color": Color(0.90, 0.35, 0.35)},
	{"ch": "m", "name": "Mart", "color": Color(0.35, 0.55, 0.90)},
	{"ch": "w", "name": "Wild", "color": Color(0.85, 0.80, 0.25)},
	{"ch": "t", "name": "Trainer", "color": Color(0.95, 0.45, 0.75)},
	{"ch": "L", "name": "Leader", "color": Color(0.95, 0.60, 0.15)},
	{"ch": "D", "name": "Gym door", "color": Color(0.65, 0.35, 0.80)},
]
## Object markers the run must be able to reach (sealing one off is a bug).
const CONTENT_OBJECTS := ["S", "X", "c", "m", "w", "t", "L", "D"]

## Editor tooltip per object marker ("" = the eraser).
const OBJECT_DESC := {
	"": "Eraser — clears a cell's object marker (terrain stays).",
	"S": "Spawn — the run's start. Exactly one, on the first area only.",
	"X": "Exit gate — sealed until this area's leader is defeated (needs a leader).",
	"c": "Pokémon Center — heal / shop. Walk into its door.",
	"m": "Poké Mart — buy items. Walk into its door.",
	"w": "Wild encounter (optional). Only spawns if this area's wild pool is non-empty.",
	"t": "Route trainer (optional). Only spawns if this area has a trainer spec.",
	"L": "Leader — the area's boss and mandatory gate.",
	"D": "Gym door — gym entrance dressing.",
}

var _all: Dictionary = {}          # full parsed stage_layouts.json
var _stages: Dictionary = {}       # stage_id -> layout dict
var _run_config: Dictionary = {}   # full parsed run_config.json (for run/segment order)
var _stage_id: String = ""
var _terrain: Array = []           # Array[Array[String]] terrain material name per cell
var _objects: Array = []           # Array[Array[String]] object marker per cell ("" = none)
var _stories: Array = []           # Array[Array[int]] building storeys per cell (0 = default)
var _brush_kind := "terrain"       # "terrain" paints a material, "object" paints a marker
var _active_terrain := "grass"
var _active_object := ""
var _terrain_buttons: Array = []
var _object_buttons: Array = []
var _story_spin: SpinBox           # storeys applied when painting a building material

# In-app terrain-texture painter (edits res://art/terrain/<mat>.png overrides).
var _tex_win: Window
var _tex_canvas: TexCanvas
var _tex_img: Image                 # working copy being painted
var _tex_mat := ""                  # material currently open in the painter
var _tex_color := Color.WHITE       # active paint color
var _tex_eyedrop := false
var _tex_title: Label
var _tex_status: Label
var _tex_swatch_btn: Button         # the "current color" indicator swatch
var _tex_eyedrop_btn: Button
var _tex_pal_flow: HFlowContainer   # per-material starter palette (rebuilt on open)
var _tex_file_dialog: FileDialog    # image import picker (lazy)
var _tex_size_pick: OptionButton    # downsample target size for imports
var _tex_preview: TilePreview       # 3×3 repeat, to spot seams

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
var _leader_pick: OptionButton
var _leader_mode_pick: OptionButton
var _leader_team: Array = []       # pokemon ids fielded by the leader (in order)
var _leader_team_box: VBoxContainer
var _leader_add_pick: OptionButton
var _route_box: VBoxContainer      # one row per `t` cell (trainer dropdown + team)
var _route_rows: Array = []        # [{trainer: OptionButton, team: LineEdit, mode: String}]
var _leader_options: Array = []    # valid leader ids (rival + trainers + enemies)
var _route_t_count := -1           # `t` cells the route rows were last built for

## The per-starter rival sentinel (Rivals.RIVAL_SENTINEL) — a valid leader that
## resolves to the starter's counter-rival at runtime.
const RIVAL_SENTINEL := "rival_blue"

# Pokedex (enemies.json library editor)
var _enemies_all: Dictionary = {}   # full parsed enemies.json
var _enemies: Array = []            # the enemies list (dicts, order preserved)
var _dex_current := ""
var _dex_context := ""              # "" = library (enemies.json); else a segment id (its override)
var _dex_context_pick: OptionButton
var _dex_wanted_context := ""       # one-shot: context to select on the next dex load
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
	for entry in OBJECTS:
		_canvas.object_colors[entry["ch"]] = entry["color"]
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
	for entry in OBJECTS:
		_world_canvas.object_colors[entry["ch"]] = entry["color"]
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
	_fill_leader_options()    # needs trainers/enemies loaded
	_fill_pokemon_options()
	# Start on area 1 (the run's first stage), falling back to the first layout.
	var run_ids := _run_ordered_ids()
	var first_id := ""
	if not run_ids.is_empty():
		first_id = String(run_ids[0])
	elif not _stages.is_empty():
		first_id = String(_stages.keys()[0])
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
	var preview_btn := Button.new()
	preview_btn.text = "▶ Preview 3D"
	preview_btn.tooltip_text = "Save, then open the selected stage in a walkable 3D window to check rendering."
	preview_btn.pressed.connect(_on_preview_3d)
	bar.add_child(preview_btn)
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

	# Terrain palette, grouped by category. A material's category decides walkability
	# (barrier/building block), roof (interior is roofed), and appearance — painting it
	# is the whole authoring model. Buildings are their own group (blocks, storeyed);
	# picking a material selects the terrain brush.
	for group in ["exterior", "interior", "building", "barrier"]:
		var header := Label.new()
		match group:
			"interior": header.text = "Terrain — interior  (roofed)"
			"building": header.text = "Buildings  (block; storeys per cell)"
			_: header.text = "Terrain — %s" % group
		header.add_theme_font_size_override("font_size", 14)
		header.modulate = Color(0.8, 0.85, 0.95)
		box.add_child(header)
		var flow := HFlowContainer.new()
		box.add_child(flow)
		for mat in ThemePalette.PAINTABLE_MATERIALS:
			if ThemePalette.category_of(mat) == group:
				flow.add_child(_terrain_button(mat))
		# Storeys live with the buildings — only they use it. Painting a building writes
		# this value onto the cell; it jumps to a material's default when you pick it.
		if group == "building":
			var story_row := HBoxContainer.new()
			story_row.add_child(_meta_label("Storeys"))
			_story_spin = _spin(1, 12, 2)
			story_row.add_child(_story_spin)
			box.add_child(story_row)

	# Open the pixel painter for the currently-selected terrain material.
	var tex_btn := Button.new()
	tex_btn.text = "✎ Edit texture…"
	tex_btn.tooltip_text = "Paint the 16×16 texture of the selected terrain material.\nSaves an override PNG the 3D preview picks up."
	tex_btn.pressed.connect(_open_texture_editor)
	box.add_child(tex_btn)

	# Object markers — the secondary brush, laid on top of walkable terrain.
	var obj_header := Label.new()
	obj_header.text = "Objects"
	obj_header.add_theme_font_size_override("font_size", 14)
	obj_header.modulate = Color(0.8, 0.85, 0.95)
	box.add_child(obj_header)
	var obj_flow := HFlowContainer.new()
	box.add_child(obj_flow)
	obj_flow.add_child(_object_button("", "None", Color(0.16, 0.17, 0.20)))
	for entry in OBJECTS:
		obj_flow.add_child(_object_button(String(entry["ch"]), String(entry["name"]), entry["color"]))

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
	# fielding those Pokemon; blank team = legacy single-combatant leader/enemy.
	box.add_child(HSeparator.new())
	box.add_child(_meta_label("— Trainers & teams —"))
	box.add_child(_meta_label("Leader (rival / trainer / enemy)"))
	_leader_pick = OptionButton.new()
	_leader_pick.fit_to_longest_item = false
	box.add_child(_leader_pick)  # items filled after _load_file (needs trainers/enemies)
	box.add_child(_meta_label("Leader team mode"))
	_leader_mode_pick = OptionButton.new()
	for m in ["sequential", "one_of"]:
		_leader_mode_pick.add_item(m)
	box.add_child(_leader_mode_pick)
	box.add_child(_meta_label("Leader team — Pokemon (blank = single enemy)"))
	var add_row := HBoxContainer.new()
	_leader_add_pick = OptionButton.new()
	_leader_add_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_leader_add_pick.fit_to_longest_item = false
	add_row.add_child(_leader_add_pick)  # items filled after _load_file
	var add_btn := Button.new()
	add_btn.text = "+ Add"
	add_btn.pressed.connect(_on_leader_add)
	add_row.add_child(add_btn)
	box.add_child(add_row)
	_leader_team_box = VBoxContainer.new()
	box.add_child(_leader_team_box)
	box.add_child(_meta_label("Route trainers — one row per `t` cell"))
	_route_box = VBoxContainer.new()
	box.add_child(_route_box)
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
	var cells := _count_object("w")
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


func _count_object(marker: String) -> int:
	var n := 0
	for row in _objects:
		for cell in row:
			if String(cell) == marker:
				n += 1
	return n


func _swatch_button(label: String, color: Color, tall: bool, on_pick: Callable) -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(70, 30 if tall else 26)
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
	btn.pressed.connect(on_pick)
	return btn


func _terrain_button(mat: String) -> Button:
	var btn := _swatch_button(mat, ThemePalette.color_of(mat), true, _on_terrain_pick.bind(mat))
	btn.button_pressed = mat == _active_terrain and _brush_kind == "terrain"
	btn.tooltip_text = _material_tooltip(mat)
	_terrain_buttons.append({"btn": btn, "mat": mat})
	return btn


## `marker` == "" is the "None" eraser (clears a cell's object).
func _object_button(marker: String, label: String, color: Color) -> Button:
	var btn := _swatch_button(label, color, false, _on_object_pick.bind(marker))
	btn.tooltip_text = String(OBJECT_DESC.get(marker, marker))
	_object_buttons.append({"btn": btn, "marker": marker})
	return btn


## Tooltip for a terrain material: name + category (walk/roof) + use-case example.
func _material_tooltip(mat: String) -> String:
	var tag := String({
		"exterior": "Exterior · walkable, open sky",
		"interior": "Interior · walkable, roofed",
		"building": "Building · blocks, storeyed",
		"barrier": "Barrier · blocks",
	}.get(ThemePalette.category_of(mat), ""))
	var desc := String(ThemePalette.MATERIAL_DESC.get(mat, ""))
	var head := "%s — %s" % [mat, tag]
	return "%s\n%s" % [head, desc] if desc != "" else head


# --- Actions ---

func _on_terrain_pick(mat: String) -> void:
	_active_terrain = mat
	_brush_kind = "terrain"
	# Picking a building jumps the storey spinbox to that material's default floors.
	if _story_spin != null and ThemePalette.is_building_material(mat):
		_story_spin.value = ThemePalette.floors_of(mat)
	for tb in _terrain_buttons:
		tb["btn"].button_pressed = tb["mat"] == mat
	for ob in _object_buttons:
		ob["btn"].button_pressed = false


func _on_object_pick(marker: String) -> void:
	_active_object = marker
	_brush_kind = "object"
	for tb in _terrain_buttons:
		tb["btn"].button_pressed = false
	for ob in _object_buttons:
		ob["btn"].button_pressed = ob["marker"] == marker


# --- Terrain texture painter ---
# A pixel editor for a material's 16×16 texture. Loads the current texture (authored
# override PNG if present, else the procedural one), lets you paint pixels, and saves an
# override PNG (res://art/terrain/<mat>.png) that the 3D preview reads back on next launch.

## Open (or re-focus) the painter on the currently-selected terrain material.
func _open_texture_editor() -> void:
	_tex_mat = _active_terrain
	_tex_img = TerrainTex.image_for(_tex_mat)  # override PNG if any, else procedural
	_tex_img.convert(Image.FORMAT_RGBA8)
	if _tex_win == null:
		_build_texture_window()
	_tex_eyedrop = false
	if _tex_eyedrop_btn != null:
		_tex_eyedrop_btn.button_pressed = false
	_rebuild_tex_palette()
	_tex_set_color(_tex_img.get_pixel(0, 0))
	_tex_canvas.set_image(_tex_img)
	_tex_preview.set_image(_tex_img)
	_tex_status.text = ""
	_tex_win.title = "Texture — %s" % _tex_mat
	_tex_win.popup_centered(Vector2i(600, 480))


func _build_texture_window() -> void:
	_tex_win = Window.new()
	_tex_win.min_size = Vector2i(560, 460)
	_tex_win.close_requested.connect(func(): _tex_win.hide())
	add_child(_tex_win)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	_tex_win.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)

	# Left: title + zoomed pixel canvas + hint.
	var left := VBoxContainer.new()
	row.add_child(left)
	_tex_title = Label.new()
	_tex_title.add_theme_font_size_override("font_size", 14)
	left.add_child(_tex_title)
	_tex_canvas = TexCanvas.new()
	_tex_canvas.on_paint = _tex_paint
	left.add_child(_tex_canvas)
	var hint := Label.new()
	hint.text = "Click / drag to paint. The tile wraps, so edges stay seamless."
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.7, 0.72, 0.78)
	left.add_child(hint)
	left.add_child(_tex_meta_label("Tiled preview (3×3)"))
	_tex_preview = TilePreview.new()
	left.add_child(_tex_preview)

	# Right: current color, palette, tools, save/revert.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(200, 0)
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)

	right.add_child(_tex_meta_label("Color"))
	_tex_swatch_btn = Button.new()
	_tex_swatch_btn.custom_minimum_size = Vector2(0, 26)
	_tex_swatch_btn.disabled = true
	right.add_child(_tex_swatch_btn)

	right.add_child(_tex_meta_label("Palette"))
	_tex_pal_flow = HFlowContainer.new()
	right.add_child(_tex_pal_flow)

	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(0, 26)
	picker.text = "Custom…"
	picker.color_changed.connect(func(c): _tex_set_color(c))
	right.add_child(picker)

	_tex_eyedrop_btn = Button.new()
	_tex_eyedrop_btn.toggle_mode = true
	_tex_eyedrop_btn.text = "Eyedropper"
	_tex_eyedrop_btn.tooltip_text = "Click a pixel to pick up its color."
	_tex_eyedrop_btn.toggled.connect(func(on): _tex_eyedrop = on)
	right.add_child(_tex_eyedrop_btn)

	right.add_child(HSeparator.new())
	right.add_child(_tex_meta_label("Import image"))
	var imp_row := HBoxContainer.new()
	right.add_child(imp_row)
	var imp_btn := Button.new()
	imp_btn.text = "Import…"
	imp_btn.tooltip_text = "Load a PNG/JPG, centre-crop to square, and downsample to the chosen size.\nThen tweak and Save override."
	imp_btn.pressed.connect(_tex_open_import_dialog)
	imp_row.add_child(imp_btn)
	_tex_size_pick = OptionButton.new()
	for n in [16, 32, 64, 128]:
		_tex_size_pick.add_item("%d×%d" % [n, n])
		_tex_size_pick.set_item_metadata(_tex_size_pick.item_count - 1, n)
	_tex_size_pick.select(1)  # default 32×32
	_tex_size_pick.tooltip_text = "Texture resolution to downsample the image to."
	imp_row.add_child(_tex_size_pick)

	right.add_child(HSeparator.new())
	var save_btn := Button.new()
	save_btn.text = "Save override"
	save_btn.pressed.connect(_tex_save)
	right.add_child(save_btn)
	var revert_btn := Button.new()
	revert_btn.text = "Revert to procedural"
	revert_btn.pressed.connect(_tex_revert)
	right.add_child(revert_btn)
	var reload_btn := Button.new()
	reload_btn.text = "Reload (discard edits)"
	reload_btn.pressed.connect(_tex_reload)
	right.add_child(reload_btn)

	_tex_status = Label.new()
	_tex_status.add_theme_font_size_override("font_size", 11)
	_tex_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tex_status.custom_minimum_size = Vector2(190, 0)
	_tex_status.modulate = Color(0.75, 0.9, 0.75)
	right.add_child(_tex_status)


func _tex_meta_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(0.8, 0.85, 0.95)
	return l


## Rebuild the starter palette for the material now open: its base color and shaded
## variants, plus neutral anchors. The Custom picker covers anything else.
func _rebuild_tex_palette() -> void:
	for child in _tex_pal_flow.get_children():
		child.queue_free()
	var base := ThemePalette.color_of(_tex_mat)
	var colors := [
		base, base.lightened(0.2), base.lightened(0.4),
		base.darkened(0.2), base.darkened(0.45),
		Color.WHITE, Color(0.5, 0.5, 0.52), Color(0.08, 0.08, 0.1),
	]
	for c in colors:
		_tex_pal_flow.add_child(_tex_color_swatch(c))


func _tex_color_swatch(c: Color) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(26, 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(3)
	for st in ["normal", "hover", "pressed"]:
		btn.add_theme_stylebox_override(st, sb)
	btn.pressed.connect(func(): _tex_set_color(c))
	return btn


func _tex_set_color(c: Color) -> void:
	_tex_color = Color(c.r, c.g, c.b, 1.0)  # terrain stays opaque
	if _tex_eyedrop_btn != null:
		_tex_eyedrop_btn.button_pressed = false
	_tex_eyedrop = false
	_refresh_tex_ui()


func _refresh_tex_ui() -> void:
	if _tex_title != null:
		var dims := "%d×%d" % [_tex_img.get_width(), _tex_img.get_height()] if _tex_img != null else "—"
		_tex_title.text = "%s  ·  %s  ·  %s" % [_tex_mat, dims,
				"override" if TerrainTex.has_override(_tex_mat) else "procedural"]
	if _tex_swatch_btn != null:
		var sb := StyleBoxFlat.new()
		sb.bg_color = _tex_color
		sb.set_corner_radius_all(3)
		_tex_swatch_btn.add_theme_stylebox_override("disabled", sb)
		_tex_swatch_btn.text = "#" + _tex_color.to_html(false)
		_tex_swatch_btn.add_theme_color_override("font_disabled_color",
				Color.BLACK if _tex_color.get_luminance() > 0.5 else Color.WHITE)


func _tex_paint(cell: Vector2i) -> void:
	if _tex_img == null:
		return
	if _tex_eyedrop:
		_tex_set_color(_tex_img.get_pixel(cell.x, cell.y))
		return
	_tex_img.set_pixel(cell.x, cell.y, _tex_color)
	_tex_canvas.queue_redraw()
	_tex_preview.set_image(_tex_img)


func _tex_save() -> void:
	if _tex_img == null:
		return
	var err := TerrainTex.save_override(_tex_mat, _tex_img)
	if err == OK:
		_tex_status.text = "Saved → art/terrain/%s.png. Open a 3D preview to see it in the world." % _tex_mat
		_refresh_tex_ui()
	else:
		_tex_status.text = "Save failed (error %d)." % err


func _tex_revert() -> void:
	TerrainTex.delete_override(_tex_mat)
	_tex_img = TerrainTex.generate_image(_tex_mat)
	_tex_canvas.set_image(_tex_img)
	_tex_preview.set_image(_tex_img)
	_tex_status.text = "Reverted %s to its procedural texture." % _tex_mat
	_refresh_tex_ui()


func _tex_reload() -> void:
	_tex_img = TerrainTex.image_for(_tex_mat)
	_tex_img.convert(Image.FORMAT_RGBA8)
	_tex_canvas.set_image(_tex_img)
	_tex_preview.set_image(_tex_img)
	_tex_status.text = "Reloaded %s from disk — edits discarded." % _tex_mat
	_refresh_tex_ui()


func _tex_open_import_dialog() -> void:
	if _tex_file_dialog == null:
		_tex_file_dialog = FileDialog.new()
		_tex_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_tex_file_dialog.access = FileDialog.ACCESS_FILESYSTEM  # browse the whole disk, not just res://
		_tex_file_dialog.use_native_dialog = true
		_tex_file_dialog.add_filter("*.png,*.jpg,*.jpeg,*.webp,*.bmp", "Images")
		_tex_file_dialog.file_selected.connect(_tex_import)
		add_child(_tex_file_dialog)
	_tex_file_dialog.popup_centered(Vector2i(780, 540))


## Load an image file, centre-crop it to a square, and downsample to the selected tile
## size — into the working canvas so it previews and can be tweaked before Save.
func _tex_import(path: String) -> void:
	var img := Image.new()
	if img.load(path) != OK:
		_tex_status.text = "Could not load %s." % path.get_file()
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	if w == 0 or h == 0:
		_tex_status.text = "Empty image."
		return
	var side: int = mini(w, h)
	if w != h:  # centre-crop to the largest square so a photo isn't stretched
		img = img.get_region(Rect2i((w - side) / 2, (h - side) / 2, side, side))
	var target := int(_tex_size_pick.get_item_metadata(_tex_size_pick.selected))
	img.resize(target, target, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	_tex_img = img
	_tex_canvas.set_image(_tex_img)
	_tex_preview.set_image(_tex_img)
	_tex_status.text = "Imported %s → %d×%d. Save override to apply." % [path.get_file(), target, target]
	_refresh_tex_ui()


func _paint_cell(cell: Vector2i) -> void:
	if cell.y < 0 or cell.y >= _terrain.size() or cell.x < 0 or cell.x >= _terrain[cell.y].size():
		return
	if _brush_kind == "object":
		_objects[cell.y][cell.x] = _active_object
	else:
		_terrain[cell.y][cell.x] = _active_terrain
		# Storeys apply only to buildings; other terrain clears any stored value.
		_stories[cell.y][cell.x] = int(_story_spin.value) if _is_building_mat(_active_terrain) else 0
	_canvas.queue_redraw()
	_revalidate()


func _is_building_mat(mat: String) -> bool:
	return ThemePalette.is_building_material(mat)


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
	_rows_spin.value = _terrain.size()
	_cols_spin.value = _terrain[0].size() if not _terrain.is_empty() else 0
	_populate_teams_ui(stage_id)
	_populate_wild_ui(stage_id)
	_sync_stage_picker(stage_id)
	_canvas.set_cells(_terrain, _objects, _stories)
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
		"cells": _blank_cells(rows, cols),
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
	var new_terrain: Array = []
	var new_objects: Array = []
	var new_stories: Array = []
	for y in rows:
		var trow: Array = []
		var orow: Array = []
		var srow: Array = []
		for x in cols:
			if y < _terrain.size() and x < _terrain[y].size():
				trow.append(_terrain[y][x])
				orow.append(_objects[y][x] if y < _objects.size() and x < _objects[y].size() else "")
				srow.append(_stories[y][x] if y < _stories.size() and x < _stories[y].size() else 0)
			else:
				# new border cells become walls, new interior grass
				var edge := y == 0 or x == 0 or y == rows - 1 or x == cols - 1
				trow.append("wall" if edge else "grass")
				orow.append("")
				srow.append(0)
		new_terrain.append(trow)
		new_objects.append(orow)
		new_stories.append(srow)
	_terrain = new_terrain
	_objects = new_objects
	_stories = new_stories
	_canvas.set_cells(_terrain, _objects, _stories)
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
		var cells := _stage_cells(sid)
		var terrain: Array = []
		var objects: Array = []
		for row in cells:
			var trow: Array = []
			var orow: Array = []
			for c in row:
				trow.append(String(c["terrain"]))
				orow.append(String(c["object"]))
			terrain.append(trow)
			objects.append(orow)
		defs.append({
			"id": sid, "terrain": terrain, "objects": objects,
			"pos": _layout_pos(sid), "order": _segment_index(sid),
		})
	_world_canvas.set_stages(defs)
	_world_canvas.selected_id = _stage_id
	_world_checks()


func _on_world_move(id: String, new_pos: Vector2i) -> void:
	_stages[id]["world_pos"] = [new_pos.x, new_pos.y]
	_world_checks()


func _on_world_select(id: String) -> void:
	_select_stage(id)  # keeps _stage_id/terrain/picker in sync so map-mode edits the clicked stage
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
## spawn (barrier terrain blocks). A stage counts as reached when any walkable cell
## is, and as broken when a cell that carries a run-content object (`CONTENT_OBJECTS`)
## is not. Decorative pockets sealed behind scenery are intentional and ignored.
func _unreachable_stages(run_ids: Array) -> Array:
	if run_ids.is_empty():
		return []
	var walk := {}
	for sid in run_ids:
		var pos := _layout_pos(sid)
		var cells := _stage_cells(sid)
		for y in cells.size():
			for x in cells[y].size():
				if ThemePalette.is_walkable_material(String(cells[y][x]["terrain"])):
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
		var pos := _layout_pos(sid)
		var cells := _stage_cells(sid)
		var touched := false
		var sealed := false
		for y in cells.size():
			for x in cells[y].size():
				var cell: Dictionary = cells[y][x]
				if not ThemePalette.is_walkable_material(String(cell["terrain"])):
					continue
				if seen.has(pos + Vector2i(x, y)):
					touched = true
				elif String(cell["object"]) in CONTENT_OBJECTS:
					sealed = true
		if not touched or sealed:
			bad.append(sid)
	return bad


# world-view data helpers (read the editor's raw grids; no Balance dependency)

func _stage_rows(sid: String) -> Array:
	return StageLayout.glyph_rows(_stages[sid])


## Rows of {terrain, object} cells for a stage (material-primary or legacy).
func _stage_cells(sid: String) -> Array:
	return StageLayout.cell_rows(_stages[sid])


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

	# Context: edit the shared Library def, or a specific area's override (siloed —
	# e.g. Brock's Onix vs Rock Tunnel's Onix). Overrides store only changed fields.
	var ctx_row := HBoxContainer.new()
	ctx_row.add_child(_label("Editing:"))
	_dex_context_pick = OptionButton.new()
	_dex_context_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dex_context_pick.item_selected.connect(_on_dex_context_picked)
	ctx_row.add_child(_dex_context_pick)
	box.add_child(ctx_row)

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
	_dex_commit()  # save edits to the previously selected Pokémon (under its context)
	if _dex_index(id) < 0:
		return
	_dex_current = id
	_refresh_dex_context_pick(id)
	_dex_load_form(id)


## Load the form from the effective def: the library base, plus this area's override
## if a segment context is active.
func _dex_load_form(id: String) -> void:
	var e := _dex_effective_def(id)
	_dex_id.text = id
	_dex_id.editable = _dex_context == ""  # id is identity — can't rename in an override
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


func _segment_by_id(sid: String) -> Dictionary:
	for s in _segments():
		if String(s.get("id", "")) == sid:
			return s
	return {}


func _dex_base_def(id: String) -> Dictionary:
	var idx := _dex_index(id)
	return _enemies[idx] if idx >= 0 else {}


## Base library def with the active area's override applied (if a context is set).
func _dex_effective_def(id: String) -> Dictionary:
	var base := _dex_base_def(id)
	if _dex_context == "":
		return base
	var ov: Dictionary = _segment_by_id(_dex_context).get("enemy_overrides", {}).get(id, {})
	var eff: Dictionary = base.duplicate(true)
	for k in ov:
		eff[k] = ov[k]
	return eff


## Contexts a Pokémon can be edited in: the shared Library, plus every area where it
## appears (leader / wild / route trainer). Each area maps to that segment's override.
func _dex_contexts_for(id: String) -> Array:
	var out: Array = [{"label": "Library (all areas)", "seg": ""}]
	for s in _segments():
		var roles: Array = []
		if id in _str_array(s.get("leader_team", [])) or String(s.get("leader", "")) == id:
			roles.append("leader")
		if id in _str_array(s.get("wild_pool", [])):
			roles.append("wild")
		for tr in s.get("trainers", []):
			if id in _str_array(tr.get("team", [])):
				roles.append("trainer")
				break
		if not roles.is_empty():
			out.append({"label": "%s — %s" % [String(s.get("id", "")), "/".join(roles)],
					"seg": String(s.get("id", ""))})
	return out


func _refresh_dex_context_pick(id: String) -> void:
	if _dex_context_pick == null:
		return
	var want := _dex_wanted_context if _dex_wanted_context != "" else _dex_context
	_dex_wanted_context = ""
	var ctxs := _dex_contexts_for(id)
	_dex_context_pick.clear()
	var sel := 0
	for i in ctxs.size():
		_dex_context_pick.add_item(String(ctxs[i]["label"]))
		_dex_context_pick.set_item_metadata(i, String(ctxs[i]["seg"]))
		if String(ctxs[i]["seg"]) == want:
			sel = i
	_dex_context_pick.select(sel)
	_dex_context = String(_dex_context_pick.get_item_metadata(sel))


func _on_dex_context_picked(idx: int) -> void:
	_dex_commit()  # save under the previous context first
	_dex_context = String(_dex_context_pick.get_item_metadata(idx))
	_dex_load_form(_dex_current)


## The editable form as a def dict (the fields an override may carry).
func _dex_form_to_def() -> Dictionary:
	var d := {
		"name": _dex_name.text,
		"pokemon_type": POKE_TYPES[_dex_type.selected],
		"max_hp": int(_dex_hp.value),
		"xp_reward": int(_dex_xp.value),
		"is_wild": _dex_wild.button_pressed,
		"is_boss": _dex_boss.button_pressed,
		"action_pool": _parse_moves(_dex_moves.text),
	}
	var pattern := _parse_boss_pattern(_dex_boss_pattern.text, d["action_pool"])
	if not pattern.is_empty():
		d["boss_pattern"] = pattern
		d["boss_pattern_loop_start"] = int(_dex_loop_start.value)
	return d


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
	if _dex_context != "":
		_status.text = "Switch to Library to delete a Pokémon (deletes the base def)."
		_status.modulate = Color(1.0, 0.7, 0.5)
		return
	var idx := _dex_index(_dex_current)
	if idx < 0:
		return
	_enemies.remove_at(idx)
	_dex_current = ""
	_sync_dex_picker(_enemies[0]["id"] if not _enemies.is_empty() else "")


## Write the form back — into the enemies.json library entry (Library context), or
## into the active area's `enemy_overrides` (a segment context), storing only fields
## that differ from the library base so the override stays a minimal shallow diff.
func _dex_commit() -> void:
	if _dex_id == null or _dex_current == "":
		return
	var idx := _dex_index(_dex_current)
	if idx < 0:
		return
	var form := _dex_form_to_def()
	if _dex_context == "":
		var e: Dictionary = _enemies[idx]
		var new_id := _dex_id.text.strip_edges()
		if new_id != "" and (new_id == _dex_current or _dex_index(new_id) < 0):
			_dex_current = new_id
		e["id"] = _dex_current
		for k in form:
			e[k] = form[k]
		if not form.has("boss_pattern"):
			e.erase("boss_pattern")
			e.erase("boss_pattern_loop_start")
		return
	# Area override: keep only the fields that differ from the library base.
	var base: Dictionary = _enemies[idx]
	var seg := _segment_by_id(_dex_context)
	if seg.is_empty():
		return
	var ov := {}
	for k in form:
		if JSON.stringify(base.get(k)) != JSON.stringify(form[k]):
			ov[k] = form[k]
	var all_ov: Dictionary = seg.get("enemy_overrides", {})
	if ov.is_empty():
		all_ov.erase(_dex_current)
	else:
		all_ov[_dex_current] = ov
	if all_ov.is_empty():
		seg.erase("enemy_overrides")
	else:
		seg["enemy_overrides"] = all_ov


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
	# Per-area overrides live in run_config segments, so persist those too.
	if not _run_config.is_empty():
		var rf := FileAccess.open(RUN_CONFIG_PATH, FileAccess.WRITE)
		if rf != null:
			rf.store_string(JSON.stringify(_run_config, "  "))
			rf.close()
	_status.text = "Saved enemies.json (%d) + area overrides." % _enemies.size()
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


## Save the current stage, then open it alone in a walkable 3D window so rendering
## changes can be checked without playing/walking the whole map. Spawns a second
## Godot instance with `--preview=<stage>`; the editor stays open.
func _on_preview_3d() -> void:
	if _stage_id == "":
		return
	_on_save()  # preview reads from disk, so persist current edits first
	var err := OS.create_instance(PackedStringArray(["--", "--preview=" + _stage_id]))
	if err <= 0:
		_status.text = "Preview: could not spawn a window — run `-- --preview=%s` manually." % _stage_id
		_status.modulate = Color(1.0, 0.7, 0.5)
	else:
		_status.text = "3D preview of '%s' opened in a new window." % _stage_id
		_status.modulate = Color(0.6, 1.0, 0.6)


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
	# `cells` (terrain material + object marker per cell) is the engine input; the
	# legacy `grid` is dropped so there's a single source of truth.
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
	if _leader_pick == null:
		return
	var idx := _segment_index(stage_id)
	var seg: Dictionary = _segments()[idx] if idx >= 0 else {}
	_select_option(_leader_pick, String(seg.get("leader", RIVAL_SENTINEL)))
	_leader_mode_pick.select(1 if String(seg.get("leader_team_mode", "sequential")) == "one_of" else 0)
	_leader_team = _str_array(seg.get("leader_team", []))
	_rebuild_leader_team_ui()
	_rebuild_route_rows(seg.get("trainers", []))


func _commit_teams_to_segment() -> void:
	if _leader_pick == null or _stage_id == "":
		return
	var idx := _segment_index(_stage_id)
	if idx < 0:
		return  # orphan stage — not in the run, nothing to write
	var seg: Dictionary = _segments()[idx]
	seg["leader"] = _option_id(_leader_pick)
	if _leader_team.is_empty():
		seg.erase("leader_team")
		seg.erase("leader_team_mode")
	else:
		seg["leader_team"] = _leader_team.duplicate()
		seg["leader_team_mode"] = ["sequential", "one_of"][_leader_mode_pick.selected]
	var specs: Array = []
	for r in _route_rows:
		var tid := _option_id(r["trainer"])
		if tid == "":
			continue
		specs.append({"trainer": tid, "mode": String(r["mode"]), "team": _parse_id_list(r["team"].text)})
	if specs.is_empty():
		seg.erase("trainers")
	else:
		seg["trainers"] = specs


# --- Trainer/leader dropdown helpers ---

func _fill_leader_options() -> void:
	if _leader_pick == null:
		return
	_leader_pick.clear()
	for id in _leader_id_choices():
		_leader_pick.add_item(id)


## Fill the "add to leader team" dropdown with every Pokémon (not trainer blobs).
func _fill_pokemon_options() -> void:
	if _leader_add_pick == null:
		return
	_leader_add_pick.clear()
	for e in _pokemon_ordered():
		var id := String(e.get("id", ""))
		_leader_add_pick.add_item("%s  (%s)" % [String(e.get("name", id)), id])
		_leader_add_pick.set_item_metadata(_leader_add_pick.item_count - 1, id)


func _on_leader_add() -> void:
	var id := _option_id(_leader_add_pick)
	if id != "":
		_leader_team.append(id)
		_rebuild_leader_team_ui()


func _on_leader_remove(idx: int) -> void:
	if idx >= 0 and idx < _leader_team.size():
		_leader_team.remove_at(idx)
		_rebuild_leader_team_ui()


## The leader's team as ordered rows (bout order), each with an edit → Pokédex jump
## and a remove. This is the species list; per-placement stat/move tuning lives in
## the segment's enemy_overrides (edited via the Pokédex in this area's context).
func _rebuild_leader_team_ui() -> void:
	if _leader_team_box == null:
		return
	for child in _leader_team_box.get_children():
		child.queue_free()
	for i in _leader_team.size():
		var id := String(_leader_team[i])
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%d. %s" % [i + 1, id]
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var edit := Button.new()
		edit.text = "✎"
		edit.tooltip_text = "Edit this Pokémon in the Pokédex"
		edit.pressed.connect(_edit_pokemon.bind(id))
		row.add_child(edit)
		var rm := Button.new()
		rm.text = "✕"
		rm.pressed.connect(_on_leader_remove.bind(i))
		row.add_child(rm)
		_leader_team_box.add_child(row)


## Jump to the Pokédex focused on a Pokémon, in THIS area's context — so edits are
## siloed to the current segment's override (e.g. Brock's Onix), not the library.
func _edit_pokemon(id: String) -> void:
	_commit_metadata_from_ui()  # keep the current stage's team edits before switching
	_dex_commit()               # flush any pending dex edit under its own context
	_dex_current = id
	_dex_wanted_context = _stage_id if _segment_index(_stage_id) >= 0 else ""
	_set_editor_mode("pokedex")


## Valid leader ids: the rival sentinel, every trainer (name/portrait), and every
## enemy (a legacy single-combatant leader). A dropdown over this set makes an
## invalid id like 'hiker' impossible to author.
func _leader_id_choices() -> Array:
	if not _leader_options.is_empty():
		return _leader_options
	var seen := {RIVAL_SENTINEL: true}
	var out: Array = [RIVAL_SENTINEL]
	var ids: Array = []
	for tr in _trainers_lib:
		ids.append(String(tr.get("id", "")))
	for e in _enemies:
		ids.append(String(e.get("id", "")))
	ids.sort()
	for id in ids:
		if id != "" and not seen.has(id):
			seen[id] = true
			out.append(id)
	_leader_options = out
	return out


func _trainer_id_choices() -> Array:
	var out: Array = []
	for tr in _trainers_lib:
		out.append(String(tr.get("id", "")))
	out.sort()
	return out


## Select `id` in an OptionButton; if it isn't a known choice (e.g. a stale 'hiker'),
## add it flagged so the author can see and fix it. Real id kept in item metadata.
func _select_option(opt: OptionButton, id: String) -> void:
	for i in opt.item_count:
		var md = opt.get_item_metadata(i)
		if (String(md) if md != null else opt.get_item_text(i)) == id:
			opt.select(i)
			return
	opt.add_item("⚠ %s (unknown)" % id)
	opt.set_item_metadata(opt.item_count - 1, id)
	opt.select(opt.item_count - 1)


func _option_id(opt: OptionButton) -> String:
	if opt.selected < 0:
		return ""
	var md = opt.get_item_metadata(opt.selected)
	return String(md) if md != null else opt.get_item_text(opt.selected)


## One row per `t` cell in the current stage: a trainer dropdown + team field. Extra
## specs beyond the `t` count are dropped; extra `t` cells get blank rows.
func _rebuild_route_rows(specs: Array) -> void:
	if _route_box == null:
		return
	_route_t_count = _count_object("t")
	for child in _route_box.get_children():
		child.queue_free()
	_route_rows.clear()
	var choices := _trainer_id_choices()
	for i in _route_t_count:
		var spec: Dictionary = specs[i] if i < specs.size() else {}
		var row := HBoxContainer.new()
		var pick := OptionButton.new()
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for id in choices:
			pick.add_item(id)
		_select_option(pick, String(spec.get("trainer", choices[0] if not choices.is_empty() else "")))
		row.add_child(pick)
		var team := LineEdit.new()
		team.placeholder_text = "team: mon,mon"
		team.custom_minimum_size = Vector2(96, 0)
		team.text = ",".join(_str_array(spec.get("team", [])))
		row.add_child(team)
		_route_box.add_child(row)
		_route_rows.append({"trainer": pick, "team": team, "mode": String(spec.get("mode", "sequential"))})


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
	# Painting/erasing a `t` changes how many route-trainer rows to show — rebuild
	# them (preserving current edits) so a dropdown appears per trainer square.
	if _leader_pick != null and _count_object("t") != _route_t_count:
		_commit_teams_to_segment()
		var i := _segment_index(_stage_id)
		_rebuild_route_rows(_segments()[i].get("trainers", []) if i >= 0 else [])
	var run_ids := _run_ordered_ids()
	var is_first: bool = not run_ids.is_empty() and String(run_ids[0]) == _stage_id
	var issues := _validate(_terrain, _objects, is_first)
	if issues.is_empty():
		_status.text = "✓ Valid — %d×%d" % [_terrain[0].size() if not _terrain.is_empty() else 0, _terrain.size()]
		_status.modulate = Color(0.6, 1.0, 0.6)
	else:
		_status.text = "✗ " + "   ".join(issues)
		_status.modulate = Color(1.0, 0.7, 0.5)


## Returns a list of human-readable problems with one stage (empty = valid).
## `is_first` = the run's opening stage, the only one carrying the world's spawn.
##
## Object-count + ragged-row rules only, plus a check that every marker sits on
## walkable terrain. Reachability is deliberately absent: stages are stitched by
## `world_pos` and a stage's cells are frequently reachable only through its
## neighbour, so no single-stage flood can answer it — World View's `_world_checks`
## walks the stitched world instead.
static func _validate(terrain: Array, objects: Array, is_first: bool) -> Array:
	var issues: Array = []
	if terrain.is_empty():
		return ["empty grid"]
	var width: int = terrain[0].size()
	var s := 0
	var l := 0
	var x_exit := 0
	for y in terrain.size():
		if terrain[y].size() != width:
			issues.append("row %d wrong length" % y)
		for x in objects[y].size():
			var marker := String(objects[y][x])
			if marker != "" and not ThemePalette.is_walkable_material(String(terrain[y][x])):
				issues.append("object '%s' on non-walkable terrain" % marker)
			match marker:
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


## Load a layout (material-primary `cells` or legacy `grid`) into the two paint
## layers: `_terrain` (material name per cell) and `_objects` (marker, "" = none).
func _explode_layout(layout: Dictionary) -> void:
	_terrain = []
	_objects = []
	_stories = []
	for row in StageLayout.cell_rows(layout):
		var trow: Array = []
		var orow: Array = []
		var srow: Array = []
		for c in row:
			trow.append(String(c["terrain"]))
			orow.append(String(c["object"]))
			srow.append(int(c.get("stories", 0)))
		_terrain.append(trow)
		_objects.append(orow)
		_stories.append(srow)


## Merge the paint layers into the compact `cells` format. A row with no objects
## stays a plain terrain-code string (diff-clean); a row with any object becomes an
## array where each cell is a terrain code string or a {t: material, o: marker}
## object. This is the engine input.
func _build_cells() -> Array:
	var out: Array = []
	for y in _terrain.size():
		var row_special := false  # any object or storeys → row must be an array of cells
		for x in _terrain[y].size():
			if String(_objects[y][x]) != "" or int(_stories[y][x]) > 0:
				row_special = true
				break
		if not row_special:
			var s := ""
			for x in _terrain[y].size():
				s += ThemePalette.code_of_material(String(_terrain[y][x]))
			out.append(s)
			continue
		var row: Array = []
		for x in _terrain[y].size():
			var mat := String(_terrain[y][x])
			var obj := String(_objects[y][x])
			var st := int(_stories[y][x])
			if obj == "" and st == 0:
				row.append(ThemePalette.code_of_material(mat))
			else:
				var cell := {"t": mat}
				if obj != "":
					cell["o"] = obj
				if st > 0:
					cell["stories"] = st
				row.append(cell)
		out.append(row)
	return out


## A blank stage's cells: a wall border, grass interior (terrain-code strings).
static func _blank_cells(rows: int, cols: int) -> Array:
	var out: Array = []
	for y in rows:
		var s := ""
		for x in cols:
			var edge := y == 0 or x == 0 or y == rows - 1 or x == cols - 1
			s += ThemePalette.code_of_material("wall" if edge else "grass")
		out.append(s)
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


## Zoomed pixel canvas for the texture painter: draws an Image one big square per texel,
## with a faint grid, and forwards click/drag to a paint callback (texel coords).
class TexCanvas extends Control:
	const DISPLAY := 384.0  # target on-screen size; per-texel zoom adapts to fit any resolution
	var img: Image
	var px := 24.0
	var on_paint: Callable  # (Vector2i texel) -> void

	func set_image(i: Image) -> void:
		img = i
		if img != null:
			var n: int = maxi(img.get_width(), img.get_height())
			px = maxf(3.0, floorf(DISPLAY / float(n)))  # crisp integer zoom
			custom_minimum_size = Vector2(img.get_width() * px, img.get_height() * px)
		queue_redraw()

	func _draw() -> void:
		if img == null:
			return
		var w := img.get_width()
		var h := img.get_height()
		for y in h:
			for x in w:
				draw_rect(Rect2(x * px, y * px, px, px), img.get_pixel(x, y))
		var line := Color(0, 0, 0, 0.22)
		for i in range(w + 1):
			draw_line(Vector2(i * px, 0), Vector2(i * px, h * px), line)
		for j in range(h + 1):
			draw_line(Vector2(0, j * px), Vector2(w * px, j * px), line)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_paint(event.position)
		elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_paint(event.position)

	func _paint(pos: Vector2) -> void:
		if img == null or not on_paint.is_valid():
			return
		var t := Vector2i(int(pos.x / px), int(pos.y / px))
		if t.x >= 0 and t.y >= 0 and t.x < img.get_width() and t.y < img.get_height():
			on_paint.call(t)


## Draws the working texture repeated in a grid so seams between copies are visible —
## the quickest way to tell whether an imported/edited tile actually wraps cleanly.
class TilePreview extends Control:
	const SIDE := 168.0
	const REPS := 3
	var tex: ImageTexture

	func set_image(img: Image) -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixels, no blur across seams
		if img != null:
			tex = ImageTexture.create_from_image(img)
		custom_minimum_size = Vector2(SIDE, SIDE)
		queue_redraw()

	func _draw() -> void:
		if tex == null:
			return
		var cell := SIDE / float(REPS)
		for j in REPS:
			for i in REPS:
				draw_texture_rect(tex, Rect2(i * cell, j * cell, cell, cell), false)
		draw_rect(Rect2(0, 0, SIDE, SIDE), Color(0, 0, 0, 0.3), false, 1.0)


## Inner canvas: draws each cell by its terrain material — colored by the material,
## with a category cue (barrier = dark border, interior = roofed inset) so painting
## is WYSIWYG — then the object marker on top. Paints cells under the mouse.
class GridCanvas extends Control:
	var terrain: Array = []         # Array[Array[String]] material name per cell
	var objects: Array = []         # Array[Array[String]] marker per cell ("" = none)
	var stories: Array = []         # Array[Array[int]] building storeys per cell (0 = default)
	var object_colors: Dictionary = {}
	var cell_px := 30.0
	var painter: Callable

	func set_cells(t: Array, o: Array, st: Array) -> void:
		terrain = t
		objects = o
		stories = st
		var cols: int = terrain[0].size() if not terrain.is_empty() else 0
		custom_minimum_size = Vector2(cols * cell_px, terrain.size() * cell_px)
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		# Pass 1: terrain fills, category styling, storey labels.
		for y in terrain.size():
			for x in terrain[y].size():
				var mat := String(terrain[y][x])
				var col := ThemePalette.color_of(mat)
				var cat := ThemePalette.category_of(mat)
				var rect := Rect2(x * cell_px, y * cell_px, cell_px - 1, cell_px - 1)
				draw_rect(rect, col)
				if cat == "barrier" or cat == "building":  # solid: a dark border reads as "blocks"
					draw_rect(rect, col.darkened(0.45), false, 3.0)
				elif cat == "interior":  # roofed: an inset frame
					draw_rect(rect.grow(-4.0), Color(1, 1, 1, 0.28), false, 2.0)
				var st := int(stories[y][x]) if y < stories.size() and x < stories[y].size() else 0
				if st > 0:  # building storey count, top-left corner
					draw_string(font, Vector2(x * cell_px + 2, y * cell_px + 12),
							"%dF" % st, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.9))
		# Pass 2: shop footprints — the ~2x2-tile building each Center/Mart door cell
		# actually occupies in 3D (oriented by its approach), drawn translucent so the
		# terrain beneath still reads.
		for y in objects.size():
			for x in objects[y].size():
				var obj := String(objects[y][x])
				if obj == "c" or obj == "m":
					var fr := _shop_footprint_rect(Vector2i(x, y), _shop_facing(Vector2i(x, y)))
					var fc := Color(0.86, 0.18, 0.18) if obj == "c" else Color(0.2, 0.42, 0.86)
					draw_rect(fr, Color(fc.r, fc.g, fc.b, 0.22))
					draw_rect(fr, Color(fc.r, fc.g, fc.b, 0.85), false, 2.0)
		# Pass 3: object markers on top, so their letters stay legible over footprints.
		for y in objects.size():
			for x in objects[y].size():
				var obj := String(objects[y][x])
				if obj != "":
					var ocol: Color = object_colors.get(obj, Color.WHITE)
					draw_rect(Rect2(x * cell_px + 2, y * cell_px + 2, cell_px - 5, cell_px - 5), ocol)
					draw_string(font, Vector2(x * cell_px + 9, y * cell_px + cell_px - 8),
							obj, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
							Color.BLACK if ocol.get_luminance() > 0.5 else Color.WHITE)

	## Which way a shop faces = the best walkable neighbour (mirrors the runtime's
	## `_shop_approach_facing`: any non-barrier, non-shop neighbour, biased South).
	## Returns a WG.Facing index (0=N, 1=E, 2=S, 3=W); defaults South.
	func _shop_facing(cell: Vector2i) -> int:
		var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
		var best := 2
		var best_score := -1
		for i in 4:
			var n: Vector2i = cell + dirs[i]
			if n.y < 0 or n.y >= terrain.size() or n.x < 0 or n.x >= terrain[n.y].size():
				continue
			if not ThemePalette.is_walkable_material(String(terrain[n.y][n.x])):
				continue
			var no := String(objects[n.y][n.x]) if n.y < objects.size() and n.x < objects[n.y].size() else ""
			if no == "c" or no == "m":
				continue
			var score := 2 if i == 2 else 1  # South bias, like the runtime
			if score > best_score:
				best_score = score
				best = i
		return best

	## The 2-tile-wide by 2-tile-deep rectangle the building covers: centred on the
	## door cell across its width, running back from the door cell's front edge
	## (the edge facing the approach) two tiles into the map.
	func _shop_footprint_rect(cell: Vector2i, facing: int) -> Rect2:
		var x := float(cell.x)
		var y := float(cell.y)
		var span := 2.0 * cell_px
		match facing:
			0:  # approach North → body runs South
				return Rect2(Vector2((x - 0.5) * cell_px, y * cell_px), Vector2(span, span))
			1:  # approach East → body runs West
				return Rect2(Vector2((x - 1.0) * cell_px, (y - 0.5) * cell_px), Vector2(span, span))
			3:  # approach West → body runs East
				return Rect2(Vector2(x * cell_px, (y - 0.5) * cell_px), Vector2(span, span))
			_:  # approach South → body runs North
				return Rect2(Vector2((x - 0.5) * cell_px, (y - 1.0) * cell_px), Vector2(span, span))

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
	var stages: Array = []          # [{id, terrain, objects, pos:Vector2i, order:int}]
	var object_colors: Dictionary = {}
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
			var terrain: Array = st["terrain"]
			var objects: Array = st["objects"]
			if terrain.is_empty():
				continue
			var base := pan + Vector2(st["pos"]) * cell_px
			for y in terrain.size():
				for x in terrain[y].size():
					var mat := String(terrain[y][x])
					var col := ThemePalette.color_of(mat)
					var cat := ThemePalette.category_of(mat)
					var cell_rect := Rect2(base + Vector2(x, y) * cell_px, Vector2(cell_px, cell_px))
					draw_rect(cell_rect, col)
					if cat == "barrier" or cat == "building":  # darken so blockers read solid at a glance
						draw_rect(cell_rect, col.darkened(0.35))
					elif cat == "interior" and cell_px >= 5.0:  # roofed dot
						draw_rect(Rect2(cell_rect.position + Vector2(cell_px * 0.35, cell_px * 0.35),
								Vector2(cell_px * 0.3, cell_px * 0.3)), Color(1, 1, 1, 0.4))
					var obj := String(objects[y][x]) if y < objects.size() and x < objects[y].size() else ""
					if obj != "":
						var ocol: Color = object_colors.get(obj, Color.WHITE)
						draw_rect(cell_rect, ocol)
						if cell_px >= 11.0:
							draw_string(font, base + Vector2(x * cell_px + 1, (y + 1) * cell_px - 2),
									obj, HORIZONTAL_ALIGNMENT_LEFT, -1, int(cell_px * 0.9), Color.BLACK)
			var w: int = terrain[0].size()
			var rect := Rect2(base, Vector2(w, terrain.size()) * cell_px)
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
			var terrain: Array = st["terrain"]
			if terrain.is_empty():
				continue
			var p: Vector2i = st["pos"]
			var w: int = terrain[0].size()
			if c.x >= p.x and c.x < p.x + w and c.y >= p.y and c.y < p.y + terrain.size():
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
