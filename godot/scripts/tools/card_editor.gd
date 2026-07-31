class_name CardEditor
extends Control
## Dev card editor. Launch: godot --path . -- --cardeditor
## Authors/tunes data/balance/cards.json with structured fields, New-Card type
## presets, a live CardWidget preview, and art import + crop + pixel touch-up.

const CARDS_PATH := "res://data/balance/cards.json"
const CONDITIONS_PATH := "res://data/balance/conditions.json"
const STARTERS_PATH := "res://data/balance/starters.json"
const LEARNSETS_PATH := "res://data/balance/learnsets.json"
const STAGE_REWARDS_PATH := "res://data/balance/stage_rewards.json"
const RUN_CONFIG_PATH := "res://data/balance/run_config.json"
const ART_DIR := "res://art/cards"
const ART_W := 384
const ART_H := 256

const CARD_TYPES := ["attack", "status", "support"]
const POKE_TYPES := ["NORMAL", "FIRE", "WATER", "GRASS", "POISON", "BUG", "ELECTRIC",
	"PSYCHIC", "GROUND", "ROCK", "FIGHTING", "FLYING"]
const RARITIES := ["starter", "common", "uncommon", "rare", "signature"]
const EFFECT_TYPES := ["damage", "block", "heal", "status", "apply_condition", "draw", "shuffle_hand"]
const STATUSES := ["poison", "sleep", "paralyze", "confuse"]
const TARGETS := ["enemy", "self"]

var _all: Dictionary = {}
var _cards: Array = []
var _current_id: String = ""
var _loading := false
var _condition_ids: Array = []

# Form widgets
var _picker: OptionButton
var _new_type: OptionButton
var _status: Label
var _id_edit: LineEdit
var _name_edit: LineEdit
var _pokemon_edit: LineEdit
var _card_type: OptionButton
var _pokemon_type: OptionButton
var _cost: SpinBox
var _power: SpinBox
var _rarity: OptionButton
var _description: TextEdit
var _evolves_to: OptionButton
var _effects_box: VBoxContainer
var _effect_rows: Array = []  # Array of {type_opt, fields_box, data}

# Preview
var _preview_box: VBoxContainer
var _summary_label: Label

# Art
var _art_img: Image
var _art_source: Image  # full-res import; re-crop is non-destructive
var _art_preview: TextureRect
var _art_canvas: TexCanvas
var _art_off_x: SpinBox
var _art_off_y: SpinBox
var _art_zoom: HSlider
var _art_zoom_label: Label
var _paint_color: ColorPickerButton
var _brush_size: SpinBox
var _eraser: CheckBox
var _art_file_dialog: FileDialog
var _art_status: Label
var _art_variant: OptionButton  # "" = default <id>.png; else starter id → <id>_<starter>.png
var _starter_ids: Array = []    # from starters.json


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.13, 0.16)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_load_conditions()
	_load_starters()
	_load_cards()

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	add_child(root)

	var title := Label.new()
	title.text = "Card Editor"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 12)
	root.add_child(mid)

	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(left_scroll)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	left_scroll.add_child(left)

	_build_toolbar(left)
	_build_form(left)
	_build_effects_section(left)

	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size = Vector2(420, 0)
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(right_scroll)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	right_scroll.add_child(right)

	_build_preview_section(right)
	_build_art_section(right)

	if not _cards.is_empty():
		_sync_picker(String(_cards[0]["id"]))
	else:
		_status.text = "No cards loaded."


func _load_conditions() -> void:
	_condition_ids.clear()
	var f := FileAccess.open(CONDITIONS_PATH, FileAccess.READ)
	if f == null:
		_condition_ids = ["intimidated", "distracted", "defenseless", "blinded", "slow"]
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		for k in parsed.keys():
			_condition_ids.append(String(k))
	_condition_ids.sort()


func _load_cards() -> void:
	var f := FileAccess.open(CARDS_PATH, FileAccess.READ)
	if f == null:
		_all = {"cards": []}
		_cards = []
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	_all = parsed if typeof(parsed) == TYPE_DICTIONARY else {"cards": []}
	_cards = _all.get("cards", [])


func _load_starters() -> void:
	_starter_ids.clear()
	var f := FileAccess.open(STARTERS_PATH, FileAccess.READ)
	if f == null:
		_starter_ids = ["bulbasaur", "squirtle", "charmander"]
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_starter_ids = ["bulbasaur", "squirtle", "charmander"]
		return
	for sid in parsed.keys():
		if String(sid).begins_with("_"):
			continue
		if typeof(parsed[sid]) == TYPE_DICTIONARY:
			_starter_ids.append(String(sid))
	_starter_ids.sort()


# --- toolbar + form ---

func _build_toolbar(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	_picker = OptionButton.new()
	_picker.custom_minimum_size = Vector2(220, 0)
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.item_selected.connect(_on_picker_selected)
	row.add_child(_picker)

	_new_type = OptionButton.new()
	for t in CARD_TYPES:
		_new_type.add_item(t)
		_new_type.set_item_metadata(_new_type.item_count - 1, t)
	row.add_child(_new_type)

	var new_btn := Button.new()
	new_btn.text = "New"
	new_btn.pressed.connect(_on_new)
	row.add_child(new_btn)

	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.pressed.connect(_on_delete)
	row.add_child(del_btn)

	var save_btn := Button.new()
	save_btn.text = "Save Cards"
	save_btn.pressed.connect(_on_save)
	row.add_child(save_btn)

	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(0.75, 0.78, 0.85)
	parent.add_child(_status)


func _build_form(parent: VBoxContainer) -> void:
	parent.add_child(_label("Card fields"))
	parent.add_child(_meta_label("id is unique snake_case; art = art/cards/<id>.png or <id>_<starter>.png"))

	_id_edit = LineEdit.new()
	_id_edit.placeholder_text = "id"
	_wire_edit(_id_edit)
	parent.add_child(_labeled("id", _id_edit))

	_name_edit = LineEdit.new()
	_wire_edit(_name_edit)
	parent.add_child(_labeled("name", _name_edit))

	_pokemon_edit = LineEdit.new()
	_wire_edit(_pokemon_edit)
	parent.add_child(_labeled("pokemon", _pokemon_edit))

	_card_type = OptionButton.new()
	for t in CARD_TYPES:
		_card_type.add_item(t)
		_card_type.set_item_metadata(_card_type.item_count - 1, t)
	_card_type.item_selected.connect(func(_i): _on_form_changed())
	parent.add_child(_labeled("card_type", _card_type))

	_pokemon_type = OptionButton.new()
	for t in POKE_TYPES:
		_pokemon_type.add_item(t)
		_pokemon_type.set_item_metadata(_pokemon_type.item_count - 1, t)
	_pokemon_type.item_selected.connect(func(_i): _on_form_changed())
	parent.add_child(_labeled("pokemon_type", _pokemon_type))

	_cost = _spin(0, 10, 1)
	_cost.value_changed.connect(func(_v): _on_form_changed())
	parent.add_child(_labeled("cost", _cost))

	_power = _spin(0, 99, 0)
	_power.value_changed.connect(func(_v): _on_form_changed())
	parent.add_child(_labeled("power", _power))

	_rarity = OptionButton.new()
	for r in RARITIES:
		_rarity.add_item(r)
		_rarity.set_item_metadata(_rarity.item_count - 1, r)
	_rarity.item_selected.connect(func(_i): _on_form_changed())
	parent.add_child(_labeled("rarity", _rarity))

	parent.add_child(_label("description (flavor)"))
	_description = TextEdit.new()
	_description.custom_minimum_size = Vector2(0, 56)
	_description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_description.text_changed.connect(_on_form_changed)
	parent.add_child(_description)

	_evolves_to = OptionButton.new()
	_evolves_to.item_selected.connect(func(_i): _on_form_changed())
	parent.add_child(_labeled("evolves_to", _evolves_to))


func _build_effects_section(parent: VBoxContainer) -> void:
	parent.add_child(_label("Effects"))
	_effects_box = VBoxContainer.new()
	_effects_box.add_theme_constant_override("separation", 4)
	parent.add_child(_effects_box)

	var add_btn := Button.new()
	add_btn.text = "+ Add effect"
	add_btn.pressed.connect(_on_add_effect)
	parent.add_child(add_btn)


func _build_preview_section(parent: VBoxContainer) -> void:
	parent.add_child(_label("Live preview"))
	_preview_box = VBoxContainer.new()
	_preview_box.add_theme_constant_override("separation", 6)
	parent.add_child(_preview_box)
	_summary_label = _meta_label("")
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_summary_label)


func _build_art_section(parent: VBoxContainer) -> void:
	parent.add_child(_label("Card art"))
	parent.add_child(_meta_label(
			"Default file, or per-starter alternate (CardArt: <id>_<starter>.png first)."))
	_art_status = _meta_label("Import → crop → paint → Save art")
	parent.add_child(_art_status)

	var variant_row := HBoxContainer.new()
	variant_row.add_theme_constant_override("separation", 6)
	parent.add_child(variant_row)
	variant_row.add_child(_label("variant"))
	_art_variant = OptionButton.new()
	_art_variant.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_art_variant.item_selected.connect(_on_art_variant_selected)
	variant_row.add_child(_art_variant)

	_art_preview = TextureRect.new()
	_art_preview.custom_minimum_size = Vector2(ART_W * 0.55, ART_H * 0.55)
	_art_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art_preview.clip_contents = true
	parent.add_child(_art_preview)

	var crop_row := HBoxContainer.new()
	crop_row.add_theme_constant_override("separation", 6)
	parent.add_child(crop_row)
	_art_off_x = _spin(-500, 500, 0)
	_art_off_x.value_changed.connect(func(_v): _reapply_crop())
	crop_row.add_child(_labeled("off X", _art_off_x))
	_art_off_y = _spin(-500, 500, 0)
	_art_off_y.value_changed.connect(func(_v): _reapply_crop())
	crop_row.add_child(_labeled("off Y", _art_off_y))

	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 6)
	parent.add_child(zoom_row)
	zoom_row.add_child(_label("zoom"))
	_art_zoom = HSlider.new()
	_art_zoom.min_value = 0.5
	_art_zoom.max_value = 3.0
	_art_zoom.step = 0.05
	_art_zoom.value = 1.0
	_art_zoom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_art_zoom.value_changed.connect(func(_v): _reapply_crop())
	zoom_row.add_child(_art_zoom)
	_art_zoom_label = _meta_label("1.00×")
	zoom_row.add_child(_art_zoom_label)

	var paint_row := HBoxContainer.new()
	paint_row.add_theme_constant_override("separation", 6)
	parent.add_child(paint_row)
	_paint_color = ColorPickerButton.new()
	_paint_color.color = Color.WHITE
	_paint_color.custom_minimum_size = Vector2(48, 0)
	paint_row.add_child(_paint_color)
	_brush_size = _spin(1, 32, 2)
	paint_row.add_child(_labeled("brush", _brush_size))
	_eraser = CheckBox.new()
	_eraser.text = "Eraser"
	paint_row.add_child(_eraser)

	var art_scroll := ScrollContainer.new()
	art_scroll.custom_minimum_size = Vector2(0, 220)
	parent.add_child(art_scroll)
	_art_canvas = TexCanvas.new()
	_art_canvas.on_paint = _on_art_paint
	art_scroll.add_child(_art_canvas)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	parent.add_child(btn_row)
	var import_btn := Button.new()
	import_btn.text = "Import…"
	import_btn.pressed.connect(_open_import_dialog)
	btn_row.add_child(import_btn)
	var save_art := Button.new()
	save_art.text = "Save art"
	save_art.pressed.connect(_save_art)
	btn_row.add_child(save_art)
	var rem_art := Button.new()
	rem_art.text = "Remove art"
	rem_art.pressed.connect(_remove_art)
	btn_row.add_child(rem_art)


# --- picker / select ---

func _sync_picker(select_id: String) -> void:
	_picker.clear()
	var select_idx := 0
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		var cid := String(c.get("id", ""))
		var label := "%s (%s)" % [String(c.get("name", "?")), cid]
		_picker.add_item(label)
		_picker.set_item_metadata(i, cid)
		if cid == select_id:
			select_idx = i
	if _picker.item_count > 0:
		_picker.select(select_idx)
		_select_card(_option_id(_picker))
	else:
		_current_id = ""


func _on_picker_selected(_idx: int) -> void:
	if _loading:
		return
	_commit()
	_select_card(_option_id(_picker))


func _select_card(cid: String) -> void:
	_loading = true
	_current_id = cid
	var c := _card_by_id(cid)
	if c.is_empty():
		_loading = false
		return
	_id_edit.text = String(c.get("id", ""))
	_name_edit.text = String(c.get("name", ""))
	_pokemon_edit.text = String(c.get("pokemon", ""))
	_select_option(_card_type, String(c.get("card_type", "attack")))
	_select_option(_pokemon_type, String(c.get("pokemon_type", "NORMAL")))
	_cost.value = int(c.get("cost", 0))
	_power.value = int(c.get("power", 0))
	_select_option(_rarity, String(c.get("rarity", "common")))
	_description.text = String(c.get("description", ""))
	_rebuild_evolves_to(String(c.get("evolves_to", "")))
	_rebuild_effect_rows(c.get("effects", []))
	_rebuild_art_variant_picker(cid)
	_load_art_for_current_variant()
	_loading = false
	_refresh_preview()


func _rebuild_evolves_to(selected: String) -> void:
	_evolves_to.clear()
	_evolves_to.add_item("(none)")
	_evolves_to.set_item_metadata(0, "")
	var ids: Array = []
	for c in _cards:
		ids.append(String(c.get("id", "")))
	ids.sort()
	var sel := 0
	for i in ids.size():
		var cid: String = ids[i]
		_evolves_to.add_item(cid)
		_evolves_to.set_item_metadata(_evolves_to.item_count - 1, cid)
		if cid == selected:
			sel = _evolves_to.item_count - 1
	_evolves_to.select(sel)


# --- effects ---

func _rebuild_effect_rows(effects: Array) -> void:
	for child in _effects_box.get_children():
		child.queue_free()
	_effect_rows.clear()
	for eff in effects:
		_add_effect_row(eff if typeof(eff) == TYPE_DICTIONARY else {})


func _on_add_effect() -> void:
	_add_effect_row({"type": "damage", "magnitude": 1})
	_on_form_changed()


func _add_effect_row(eff: Dictionary) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_effects_box.add_child(row)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	row.add_child(top)

	var type_opt := OptionButton.new()
	for t in EFFECT_TYPES:
		type_opt.add_item(t)
		type_opt.set_item_metadata(type_opt.item_count - 1, t)
	_select_option(type_opt, String(eff.get("type", "damage")))
	top.add_child(type_opt)

	var rem := Button.new()
	rem.text = "×"
	top.add_child(rem)

	var fields := HBoxContainer.new()
	fields.add_theme_constant_override("separation", 6)
	row.add_child(fields)

	var entry := {"type_opt": type_opt, "fields": fields, "row": row, "widgets": {}}
	_effect_rows.append(entry)
	type_opt.item_selected.connect(func(_i):
		_rebuild_effect_fields(entry, {})
		_on_form_changed()
	)
	rem.pressed.connect(func():
		_effect_rows.erase(entry)
		row.queue_free()
		_on_form_changed()
	)
	_rebuild_effect_fields(entry, eff)


func _rebuild_effect_fields(entry: Dictionary, eff: Dictionary) -> void:
	var fields: HBoxContainer = entry["fields"]
	for child in fields.get_children():
		child.queue_free()
	var widgets := {}
	entry["widgets"] = widgets
	var etype := _option_id(entry["type_opt"])

	match etype:
		"damage":
			widgets["magnitude"] = _spin(0, 99, int(eff.get("magnitude", 1)))
			fields.add_child(_labeled("mag", widgets["magnitude"]))
			widgets["target"] = _target_opt(String(eff.get("target", "enemy")))
			fields.add_child(_labeled("target", widgets["target"]))
			var ib := CheckBox.new()
			ib.text = "ignore_block"
			ib.button_pressed = bool(eff.get("ignore_block", false))
			ib.toggled.connect(func(_v): _on_form_changed())
			widgets["ignore_block"] = ib
			fields.add_child(ib)
		"block", "heal":
			widgets["magnitude"] = _spin(0, 99, int(eff.get("magnitude", 1)))
			fields.add_child(_labeled("mag", widgets["magnitude"]))
			var default_t := "self" if etype == "block" or etype == "heal" else "enemy"
			widgets["target"] = _target_opt(String(eff.get("target", default_t)))
			fields.add_child(_labeled("target", widgets["target"]))
		"status":
			widgets["status"] = OptionButton.new()
			for s in STATUSES:
				widgets["status"].add_item(s)
				widgets["status"].set_item_metadata(widgets["status"].item_count - 1, s)
			_select_option(widgets["status"], String(eff.get("status", "poison")))
			widgets["status"].item_selected.connect(func(_i): _on_form_changed())
			fields.add_child(_labeled("status", widgets["status"]))
			widgets["duration"] = _spin(0, 20, int(eff.get("duration", 2)))
			fields.add_child(_labeled("dur", widgets["duration"]))
			widgets["magnitude"] = _spin(0, 20, int(eff.get("magnitude", 0)))
			fields.add_child(_labeled("mag", widgets["magnitude"]))
			widgets["target"] = _target_opt(String(eff.get("target", "enemy")))
			fields.add_child(_labeled("target", widgets["target"]))
		"apply_condition":
			widgets["condition"] = OptionButton.new()
			for c in _condition_ids:
				widgets["condition"].add_item(c)
				widgets["condition"].set_item_metadata(widgets["condition"].item_count - 1, c)
			_select_option(widgets["condition"], String(eff.get("condition",
					_condition_ids[0] if not _condition_ids.is_empty() else "intimidated")))
			widgets["condition"].item_selected.connect(func(_i): _on_form_changed())
			fields.add_child(_labeled("cond", widgets["condition"]))
			widgets["duration"] = _spin(0, 20, int(eff.get("duration", 2)))
			fields.add_child(_labeled("dur", widgets["duration"]))
			widgets["target"] = _target_opt(String(eff.get("target", "enemy")))
			fields.add_child(_labeled("target", widgets["target"]))
		"draw":
			widgets["magnitude"] = _spin(1, 10, int(eff.get("magnitude", 1)))
			fields.add_child(_labeled("mag", widgets["magnitude"]))
		"shuffle_hand":
			fields.add_child(_meta_label("(no fields)"))

	for k in widgets:
		var w = widgets[k]
		if w is SpinBox:
			w.value_changed.connect(func(_v): _on_form_changed())
		elif w is OptionButton:
			w.item_selected.connect(func(_i): _on_form_changed())


func _target_opt(selected: String) -> OptionButton:
	var opt := OptionButton.new()
	for t in TARGETS:
		opt.add_item(t)
		opt.set_item_metadata(opt.item_count - 1, t)
	_select_option(opt, selected)
	opt.item_selected.connect(func(_i): _on_form_changed())
	return opt


func _read_effects() -> Array:
	var out: Array = []
	for entry in _effect_rows:
		if not is_instance_valid(entry.get("row")):
			continue
		var etype := _option_id(entry["type_opt"])
		var w: Dictionary = entry["widgets"]
		var d := {"type": etype}
		match etype:
			"damage":
				d["magnitude"] = int(w["magnitude"].value)
				var tgt := _option_id(w["target"])
				if tgt != "enemy":
					d["target"] = tgt
				if w["ignore_block"].button_pressed:
					d["ignore_block"] = true
			"block", "heal":
				d["magnitude"] = int(w["magnitude"].value)
				d["target"] = _option_id(w["target"])
			"status":
				d["status"] = _option_id(w["status"])
				var dur := int(w["duration"].value)
				if dur > 0:
					d["duration"] = dur
				var mag := int(w["magnitude"].value)
				if mag > 0:
					d["magnitude"] = mag
				d["target"] = _option_id(w["target"])
			"apply_condition":
				d["condition"] = _option_id(w["condition"])
				var cd := int(w["duration"].value)
				if cd > 0:
					d["duration"] = cd
				d["target"] = _option_id(w["target"])
			"draw":
				d["magnitude"] = int(w["magnitude"].value)
			"shuffle_hand":
				pass
		out.append(d)
	return out


# --- commit / new / delete / save ---

func _on_form_changed() -> void:
	if _loading:
		return
	_commit()
	_refresh_preview()


func _form_to_dict() -> Dictionary:
	var d := {
		"name": _name_edit.text.strip_edges(),
		"pokemon": _pokemon_edit.text.strip_edges(),
		"card_type": _option_id(_card_type),
		"pokemon_type": _option_id(_pokemon_type),
		"cost": int(_cost.value),
		"power": int(_power.value),
		"rarity": _option_id(_rarity),
		"effects": _read_effects(),
	}
	var desc := _description.text.strip_edges()
	if desc != "":
		d["description"] = desc
	var evo := _option_id(_evolves_to)
	if evo != "":
		d["evolves_to"] = evo
	return d


func _commit() -> void:
	if _current_id == "" or _id_edit == null:
		return
	var idx := _card_index(_current_id)
	if idx < 0:
		return
	var form := _form_to_dict()
	var e: Dictionary = _cards[idx]
	var old_id := _current_id
	var new_id := _id_edit.text.strip_edges()
	if new_id != "" and (new_id == _current_id or _card_index(new_id) < 0):
		if new_id != _current_id:
			var refs := _find_refs(_current_id)
			if not refs.is_empty():
				_status.text = "Warning: renamed '%s' but still referenced in: %s" % [
						_current_id, ", ".join(refs)]
				_status.modulate = Color(1.0, 0.85, 0.4)
		_current_id = new_id
	e["id"] = _current_id
	for k in form:
		e[k] = form[k]
	if not form.has("evolves_to"):
		e.erase("evolves_to")
	if not form.has("description"):
		e.erase("description")
	# Keep Balance.cards in sync for preview (handle id rename).
	if old_id != _current_id and Balance.cards.has(old_id):
		Balance.cards.erase(old_id)
	Balance.cards[_current_id] = e


func _on_new() -> void:
	_commit()
	var base := "new_card"
	var id := base
	var n := 1
	while _card_index(id) >= 0:
		n += 1
		id = "%s_%d" % [base, n]
	var preset := _option_id(_new_type)
	var card := {
		"id": id,
		"name": "New Card",
		"pokemon": "Various",
		"rarity": "common",
	}
	match preset:
		"status":
			card["card_type"] = "status"
			card["pokemon_type"] = "NORMAL"
			card["cost"] = 1
			card["power"] = 0
			card["effects"] = [{
				"type": "apply_condition", "condition": "intimidated",
				"duration": 2, "target": "enemy",
			}]
		"support":
			card["card_type"] = "support"
			card["pokemon_type"] = "NORMAL"
			card["cost"] = 1
			card["power"] = 0
			card["effects"] = [{"type": "block", "magnitude": 5, "target": "self"}]
		_:
			card["card_type"] = "attack"
			card["pokemon_type"] = "NORMAL"
			card["cost"] = 1
			card["power"] = 5
			card["effects"] = [{"type": "damage", "magnitude": 5}]
	_cards.append(card)
	Balance.cards[id] = card
	_sync_picker(id)
	_status.text = "Created %s (%s preset)." % [id, preset]
	_status.modulate = Color(0.6, 1.0, 0.6)


func _on_delete() -> void:
	if _current_id == "":
		return
	var refs := _find_refs(_current_id)
	if not refs.is_empty():
		_status.text = "Warning: '%s' still referenced in: %s — deleting anyway." % [
				_current_id, ", ".join(refs)]
		_status.modulate = Color(1.0, 0.85, 0.4)
	var idx := _card_index(_current_id)
	if idx < 0:
		return
	var gone := _current_id
	_cards.remove_at(idx)
	Balance.cards.erase(gone)
	_current_id = ""
	var next := String(_cards[0]["id"]) if not _cards.is_empty() else ""
	_sync_picker(next)
	if refs.is_empty():
		_status.text = "Deleted %s." % gone
		_status.modulate = Color(0.75, 0.78, 0.85)


func _on_save() -> void:
	_commit()
	_all["cards"] = _cards
	var f := FileAccess.open(CARDS_PATH, FileAccess.WRITE)
	if f == null:
		_status.text = "SAVE FAILED: cannot open %s" % CARDS_PATH
		_status.modulate = Color(1, 0.5, 0.5)
		return
	f.store_string(JSON.stringify(_all, "  "))
	f.close()
	_status.text = "Saved cards.json (%d cards)." % _cards.size()
	_status.modulate = Color(0.6, 1.0, 0.6)
	_sync_picker(_current_id)


func _find_refs(cid: String) -> Array:
	var hits: Array = []
	# evolves_to within cards
	for c in _cards:
		if String(c.get("id", "")) == cid:
			continue
		if String(c.get("evolves_to", "")) == cid:
			hits.append("cards.json evolves_to←%s" % String(c.get("id", "?")))
	_scan_json_for_card(STARTERS_PATH, "starters.json", cid, hits)
	_scan_learnsets(cid, hits)
	_scan_json_for_card(STAGE_REWARDS_PATH, "stage_rewards.json", cid, hits)
	_scan_run_config(cid, hits)
	return hits


func _scan_json_for_card(path: String, label: String, cid: String, hits: Array) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	if path == STARTERS_PATH:
		for sid in parsed.keys():
			if String(sid).begins_with("_"):
				continue
			var s = parsed[sid]
			if typeof(s) != TYPE_DICTIONARY:
				continue
			for deck_cid in s.get("deck", []):
				if String(deck_cid) == cid:
					hits.append("%s deck←%s" % [label, String(s.get("id", sid))])
	elif path == STAGE_REWARDS_PATH:
		for stage_id in parsed.keys():
			if String(stage_id).begins_with("_"):
				continue
			var pool = parsed[stage_id]
			if typeof(pool) != TYPE_ARRAY:
				continue
			for item in pool:
				if String(item) == cid:
					hits.append("%s←%s" % [label, stage_id])
					break
	else:
		if JSON.stringify(parsed).find("\"%s\"" % cid) >= 0:
			hits.append(label)


func _scan_learnsets(cid: String, hits: Array) -> void:
	var f := FileAccess.open(LEARNSETS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	# learnsets.json is flat: starter_id -> {starter_deck, lines} (plus _comment keys).
	for sid in parsed.keys():
		if String(sid).begins_with("_"):
			continue
		var entry = parsed[sid]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		for deck_cid in entry.get("starter_deck", []):
			if String(deck_cid) == cid:
				hits.append("learnsets.json starter_deck←%s" % sid)
		for line in entry.get("lines", []):
			if typeof(line) != TYPE_DICTIONARY:
				continue
			for stage in line.get("stages", []):
				if typeof(stage) == TYPE_DICTIONARY and String(stage.get("card_id", "")) == cid:
					hits.append("learnsets.json card_id←%s/%s" % [sid, String(line.get("name", "?"))])
					break


func _scan_run_config(cid: String, hits: Array) -> void:
	var f := FileAccess.open(RUN_CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for seg in parsed.get("segments", []):
		if typeof(seg) != TYPE_DICTIONARY:
			continue
		if String(seg.get("signature_card", "")) == cid:
			hits.append("run_config.json signature_card←%s" % String(seg.get("id", "?")))


# --- preview ---

func _refresh_preview() -> void:
	if _preview_box == null or _current_id == "":
		return
	for child in _preview_box.get_children():
		child.queue_free()
	var c := _card_by_id(_current_id)
	if c.is_empty():
		return
	Balance.cards[_current_id] = c
	# Pass starter so CardArt would resolve the same alternate; we still overlay
	# the working image so unsaved paint shows immediately.
	var widget := CardWidget.build(_current_id, "", _art_starter_id(), false, "")
	if _art_img != null:
		for child in widget.get_children():
			if child is VBoxContainer:
				for sub in child.get_children():
					if sub is TextureRect:
						sub.texture = ImageTexture.create_from_image(_art_img)
						break
	_preview_box.add_child(widget)
	var starter := _art_starter_id()
	var vlabel := "default" if starter == "" else starter
	_summary_label.text = "Effect: %s\nArt variant: %s → %s.png" % [
			CardText.summary(c, "", Balance), vlabel, _art_basename_for(_current_id, starter)]
	_refresh_art_preview()


# --- art ---

func _art_starter_id() -> String:
	if _art_variant == null or _art_variant.selected < 0:
		return ""
	return _option_id(_art_variant)


func _art_basename_for(cid: String, starter: String) -> String:
	if starter != "":
		return "%s_%s" % [cid, starter]
	return cid


func _art_res_rel(basename: String) -> String:
	return "%s/%s.png" % [ART_DIR, basename]


func _art_fs_path(basename: String) -> String:
	return ProjectSettings.globalize_path(_art_res_rel(basename))


func _art_file_exists(basename: String) -> bool:
	return FileAccess.file_exists(_art_res_rel(basename))


func _blank_art() -> Image:
	var img := Image.create(ART_W, ART_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


func _rebuild_art_variant_picker(cid: String) -> void:
	if _art_variant == null:
		return
	var prev := _art_starter_id()
	_art_variant.clear()
	var def_mark := " ✓" if _art_file_exists(cid) else ""
	_art_variant.add_item("default (%s.png)%s" % [cid, def_mark])
	_art_variant.set_item_metadata(0, "")
	var select_idx := 0
	var first_existing_alt := -1
	for sid in _starter_ids:
		var base := _art_basename_for(cid, String(sid))
		var mark := " ✓" if _art_file_exists(base) else ""
		_art_variant.add_item("%s (%s.png)%s" % [sid, base, mark])
		var idx := _art_variant.item_count - 1
		_art_variant.set_item_metadata(idx, sid)
		if String(sid) == prev:
			select_idx = idx
		if first_existing_alt < 0 and _art_file_exists(base):
			first_existing_alt = idx
	# Prefer an existing alternate when the default file is missing (e.g. tackle).
	if prev == "" and not _art_file_exists(cid) and first_existing_alt >= 0:
		select_idx = first_existing_alt
	_art_variant.select(select_idx)


func _on_art_variant_selected(_idx: int) -> void:
	if _loading or _current_id == "":
		return
	_load_art_for_current_variant()
	_refresh_preview()


func _load_art_for_current_variant() -> void:
	_art_source = null
	_loading = true
	_art_off_x.value = 0
	_art_off_y.value = 0
	_art_zoom.value = 1.0
	_loading = false
	var base := _art_basename_for(_current_id, _art_starter_id())
	var img := Image.new()
	if _art_file_exists(base) and img.load(_art_fs_path(base)) == OK:
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != ART_W or img.get_height() != ART_H:
			img.resize(ART_W, ART_H, Image.INTERPOLATE_LANCZOS)
		_art_img = img
		_art_status.text = "Loaded art/cards/%s.png" % base
	else:
		_art_img = _blank_art()
		_art_status.text = "No file for %s.png — import or paint, then Save art." % base
	_art_canvas.set_image(_art_img)
	_refresh_art_preview()


func _refresh_art_preview() -> void:
	if _art_preview == null or _art_img == null:
		return
	_art_preview.texture = ImageTexture.create_from_image(_art_img)
	if _art_zoom_label != null:
		_art_zoom_label.text = "%.2f×" % _art_zoom.value


func _open_import_dialog() -> void:
	if _art_file_dialog == null:
		_art_file_dialog = FileDialog.new()
		_art_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_art_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_art_file_dialog.use_native_dialog = true
		_art_file_dialog.add_filter("*.png,*.jpg,*.jpeg,*.webp,*.bmp", "Images")
		_art_file_dialog.file_selected.connect(_import_art)
		add_child(_art_file_dialog)
	_art_file_dialog.popup_centered(Vector2i(780, 540))


func _import_art(path: String) -> void:
	var img := Image.new()
	if img.load(path) != OK:
		_art_status.text = "Could not load %s." % path.get_file()
		return
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() == 0 or img.get_height() == 0:
		_art_status.text = "Empty image."
		return
	_art_source = img
	_loading = true
	_art_off_x.value = 0
	_art_off_y.value = 0
	_art_zoom.value = 1.0
	_loading = false
	_reapply_crop()
	_art_status.text = "Imported %s → variant %s.png — Save art to write." % [
			path.get_file(), _art_basename_for(_current_id, _art_starter_id())]


func _reapply_crop() -> void:
	if _loading:
		return
	if _art_source == null:
		_refresh_art_preview()
		return
	var src := _art_source
	var sw := src.get_width()
	var sh := src.get_height()
	var zoom: float = maxf(0.5, float(_art_zoom.value))
	# Cover ART_W×ART_H aspect at given zoom; zoom>1 shows a smaller crop window.
	var aspect := float(ART_W) / float(ART_H)
	var base_w: float
	var base_h: float
	if float(sw) / float(sh) > aspect:
		base_h = float(sh)
		base_w = base_h * aspect
	else:
		base_w = float(sw)
		base_h = base_w / aspect
	var crop_w := maxi(1, int(base_w / zoom))
	var crop_h := maxi(1, int(base_h / zoom))
	var cx := (sw - crop_w) / 2 + int(_art_off_x.value)
	var cy := (sh - crop_h) / 2 + int(_art_off_y.value)
	cx = clampi(cx, 0, maxi(0, sw - crop_w))
	cy = clampi(cy, 0, maxi(0, sh - crop_h))
	var cropped := src.get_region(Rect2i(cx, cy, crop_w, crop_h))
	cropped.resize(ART_W, ART_H, Image.INTERPOLATE_LANCZOS)
	cropped.convert(Image.FORMAT_RGBA8)
	_art_img = cropped
	_art_canvas.set_image(_art_img)
	_refresh_preview()


func _on_art_paint(texel: Vector2i) -> void:
	if _art_img == null:
		return
	var col := Color(0, 0, 0, 0) if _eraser.button_pressed else _paint_color.color
	var r := int(_brush_size.value)
	var half := r / 2
	for dy in range(-half, r - half):
		for dx in range(-half, r - half):
			var x := texel.x + dx
			var y := texel.y + dy
			if x >= 0 and y >= 0 and x < _art_img.get_width() and y < _art_img.get_height():
				_art_img.set_pixel(x, y, col)
	_art_canvas.refresh_texture()
	_refresh_art_preview()
	# Keep live card art in sync without full rebuild spam — light touch.
	if _preview_box != null:
		for child in _preview_box.get_children():
			if child is Button:
				for v in child.get_children():
					if v is VBoxContainer:
						for sub in v.get_children():
							if sub is TextureRect:
								sub.texture = ImageTexture.create_from_image(_art_img)
								return


func _save_art() -> void:
	if _art_img == null or _current_id == "":
		return
	var base := _art_basename_for(_current_id, _art_starter_id())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ART_DIR))
	var err := _art_img.save_png(_art_fs_path(base))
	if err == OK:
		_art_status.text = "Saved → art/cards/%s.png" % base
		_status.text = _art_status.text
		_status.modulate = Color(0.6, 1.0, 0.6)
		_rebuild_art_variant_picker(_current_id)
	else:
		_art_status.text = "Art save failed (error %d)." % err


func _remove_art() -> void:
	if _current_id == "":
		return
	var base := _art_basename_for(_current_id, _art_starter_id())
	if _art_file_exists(base):
		DirAccess.remove_absolute(_art_fs_path(base))
	_art_source = null
	_art_img = _blank_art()
	_art_canvas.set_image(_art_img)
	_rebuild_art_variant_picker(_current_id)
	_refresh_preview()
	_art_status.text = "Removed art/cards/%s.png." % base


# --- helpers ---

func _card_index(cid: String) -> int:
	for i in _cards.size():
		if String(_cards[i].get("id", "")) == cid:
			return i
	return -1


func _card_by_id(cid: String) -> Dictionary:
	var idx := _card_index(cid)
	return _cards[idx] if idx >= 0 else {}


func _wire_edit(le: LineEdit) -> void:
	le.text_changed.connect(func(_t): _on_form_changed())


func _labeled(title: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(96, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


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


## Zoomed pixel canvas for card-art touch-ups. Uses a texture blit (not per-texel
## rects) so ART_W×ART_H canvases stay responsive.
class TexCanvas extends Control:
	const DISPLAY := 384.0
	var img: Image
	var px := 1.0
	var on_paint: Callable
	var _tex: ImageTexture

	func set_image(i: Image) -> void:
		img = i
		if img != null:
			var n: int = maxi(img.get_width(), img.get_height())
			px = maxf(1.0, floorf(DISPLAY / float(n)))
			custom_minimum_size = Vector2(img.get_width() * px, img.get_height() * px)
			if _tex == null:
				_tex = ImageTexture.create_from_image(img)
			else:
				_tex.set_image(img)
		queue_redraw()

	func _draw() -> void:
		if img == null or _tex == null:
			return
		draw_texture_rect(_tex, Rect2(Vector2.ZERO, custom_minimum_size), false)
		# Light grid only when zoomed enough to be useful.
		if px >= 4.0:
			var w := img.get_width()
			var h := img.get_height()
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

	func refresh_texture() -> void:
		if img == null:
			return
		if _tex == null:
			_tex = ImageTexture.create_from_image(img)
		else:
			_tex.set_image(img)
		queue_redraw()

