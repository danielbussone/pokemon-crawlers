class_name CombatUI
extends CanvasLayer
## Interactive card-combat overlay driving one CombatCtx to win/loss.
## Turn pacing: player plays cards / uses one item, ends turn; enemy acts with recap.

signal finished(win: bool)

const COMBAT_CARD_SIZE := Vector2(125, 175)

var ctx: CombatCtx
var busy := true

var _marker: EncounterMarker
var _fx: CombatFX
var _last_enemy_hp_shown := -1

var _enemy_name: Label
var _enemy_hp: ProgressBar
var _enemy_hp_text: Label
var _enemy_status: Label
var _intent: Label
var _log: Label
var _player_stats: Label
var _player_status: Label
var _hand_box: HBoxContainer
var _items_box: HBoxContainer
var _end_turn: Button


func _init(p_ctx: CombatCtx, p_marker: EncounterMarker) -> void:
	ctx = p_ctx
	_marker = p_marker
	layer = 10


func _ready() -> void:
	_build_ui()
	_refresh()
	_begin_player_turn()


# --- Turn flow ---

func _begin_player_turn() -> void:
	busy = true
	var outcome := ctx.player_turn_begin()
	_refresh()
	if outcome == CombatCtx.LOSS:
		_finish(false)
		return
	if outcome == CombatCtx.WIN:
		_finish(true)
		return
	if ctx.slept_this_turn:
		_log_msg("You are fast asleep!")
		await _pause(1.1)
		if not is_inside_tree():
			return
		_do_enemy_turn()
		return
	busy = false
	_refresh()
	_log_msg("Turn %d — your move." % ctx.turn)


func _do_enemy_turn() -> void:
	busy = true
	_refresh()
	ctx.end_player_turn()
	var hp_before := ctx.player.hp
	var result := ctx.enemy_turn()
	_refresh()
	_log_msg(ctx.format_enemy_turn_message(hp_before, result))
	if result["acted"]:
		var ptype := ctx.enemy.ptype
		await _play_effect_log(result["effect_log"], false, ptype)
	else:
		await _pause(0.4)
	if not is_inside_tree():
		return
	var outcome := String(result["outcome"])
	if outcome == CombatCtx.WIN:
		_finish(true)
	elif outcome == CombatCtx.LOSS:
		_finish(false)
	else:
		_begin_player_turn()


func _finish(win: bool) -> void:
	busy = true
	_refresh()
	_log_msg("Victory!" if win else "You blacked out...")
	await _pause(1.0)
	if not is_inside_tree():
		return
	finished.emit(win)


# --- Input handlers ---

func _on_card_pressed(hand_index: int) -> void:
	if busy:
		return
	busy = true
	_refresh()
	var result := ctx.play_card(hand_index)
	_refresh()
	if not result["ok"]:
		busy = false
		_refresh()
		if ctx.check_outcome() == CombatCtx.LOSS:
			_finish(false)
		else:
			_log_msg(String(result["reason"]))
		return
	var played := String(Balance.cards[result["card_id"]]["name"])
	_log_msg("You played %s." % played)
	var ptype := String(Balance.cards[result["card_id"]]["pokemon_type"])
	await _play_effect_log(result["effect_log"], true, ptype)
	if not is_inside_tree():
		return
	var outcome := ctx.check_outcome()
	if outcome == CombatCtx.WIN:
		_finish(true)
	elif outcome == CombatCtx.LOSS:
		_finish(false)
	else:
		busy = false
		_refresh()


func _on_item_pressed(item_id: String) -> void:
	if busy:
		return
	var result := ctx.use_item(item_id)
	_refresh()
	if result["ok"]:
		_log_msg("Used %s." % String(Balance.items[item_id]["name"]))
	else:
		_log_msg(String(result["reason"]))


func _on_end_turn_pressed() -> void:
	if busy:
		return
	_do_enemy_turn()


# --- Effect animations ---

func _play_effect_log(log: Array, is_player_attacker: bool, attacker_ptype: String) -> void:
	var enemy_pos := _fx.creature_screen_pos(_marker)
	var player_pos := _player_stats.global_position + Vector2(80, 0)

	if is_player_attacker:
		await _fx.fly_effect(attacker_ptype, _fx.player_card_anchor(), enemy_pos)
	else:
		_marker.attack_lunge()
		await _fx.fly_effect(attacker_ptype, enemy_pos, player_pos)

	for entry in log:
		var eff_type := String(entry.get("type", ""))
		var on_player := bool(entry.get("target_is_player", false))
		var popup_pos := player_pos if on_player else enemy_pos

		match eff_type:
			"damage":
				var dmg := int(entry.get("hp_damage", 0))
				if on_player:
					_fx.flash_player_hit(clampf(0.28 + dmg * 0.02, 0.28, 0.6))
					if entry.get("missed_blinded", false):
						_fx.missed_popup(popup_pos)
					elif entry.get("blocked", false):
						_fx.blocked_popup(popup_pos)
					elif dmg > 0:
						_fx.screen_shake(clampf(dmg * 0.014, 0.05, 0.28))
						_fx.damage_popup(dmg, popup_pos)
				else:
					_marker.hit_flash()
					if entry.get("missed_blinded", false):
						_fx.missed_popup(popup_pos)
					elif entry.get("blocked", false):
						_fx.blocked_popup(popup_pos)
					elif dmg > 0:
						_fx.screen_shake(clampf(dmg * 0.014, 0.05, 0.28))
						_fx.damage_popup(dmg, popup_pos)
			"heal":
				if int(entry.get("amount", 0)) > 0:
					_fx.popup("+%d" % int(entry["amount"]), Color(0.45, 1.0, 0.55), popup_pos)
			"status":
				var status_type := String(entry.get("status_type", ""))
				_fx.status_popup(_status_label(status_type), popup_pos)
			"apply_condition":
				var cond_id := String(entry.get("condition_id", ""))
				_fx.status_popup(cond_id.capitalize(), popup_pos)

	await get_tree().create_timer(0.15).timeout


static func _status_label(status_type: String) -> String:
	match status_type:
		"poison":
			return "Poison"
		"sleep":
			return "Sleep"
		"paralyze":
			return "Paralyze"
		"confuse":
			return "Confuse"
		_:
			return status_type.capitalize()


# --- UI construction / refresh ---

func _build_ui() -> void:
	# Enemy panel (top right).
	var enemy_panel := UITheme.make_panel(10)
	enemy_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	enemy_panel.offset_right = -14
	enemy_panel.offset_top = 14
	enemy_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(enemy_panel)

	var enemy_box := VBoxContainer.new()
	enemy_box.custom_minimum_size = Vector2(320, 0)
	enemy_panel.add_child(enemy_box)

	_enemy_name = Label.new()
	_enemy_name.add_theme_font_size_override("font_size", 22)
	enemy_box.add_child(_enemy_name)

	var hp_row := HBoxContainer.new()
	enemy_box.add_child(hp_row)
	_enemy_hp = _make_hp_bar(Color(0.85, 0.3, 0.3))
	hp_row.add_child(_enemy_hp)
	_enemy_hp_text = Label.new()
	hp_row.add_child(_enemy_hp_text)

	_enemy_status = Label.new()
	_enemy_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	enemy_box.add_child(_enemy_status)

	_intent = Label.new()
	_intent.add_theme_font_size_override("font_size", 16)
	_intent.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	enemy_box.add_child(_intent)

	# Bottom rail: compact, semi-transparent — cards hug the screen edge so the
	# center band stays clear for the 3D opponent.
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 8
	bottom.offset_right = -8
	bottom.offset_bottom = 0
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.07, 0.08, 0.11, 0.82), 6))
	add_child(bottom)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	bottom.add_child(vbox)

	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 10)
	vbox.add_child(meta_row)

	_player_stats = Label.new()
	_player_stats.add_theme_font_size_override("font_size", 13)
	meta_row.add_child(_player_stats)

	_player_status = Label.new()
	_player_status.add_theme_font_size_override("font_size", 11)
	_player_status.modulate = Color(1, 1, 1, 0.75)
	meta_row.add_child(_player_status)

	_log = Label.new()
	_log.add_theme_font_size_override("font_size", 14)
	_log.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))
	_log.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.clip_text = true
	meta_row.add_child(_log)

	var items_label := Label.new()
	items_label.text = "Bag:"
	items_label.add_theme_font_size_override("font_size", 13)
	meta_row.add_child(items_label)
	_items_box = HBoxContainer.new()
	_items_box.add_theme_constant_override("separation", 4)
	meta_row.add_child(_items_box)

	_end_turn = Button.new()
	_end_turn.text = "End Turn"
	_end_turn.custom_minimum_size = Vector2(108, 30)
	_end_turn.add_theme_font_size_override("font_size", 14)
	_end_turn.pressed.connect(_on_end_turn_pressed)
	meta_row.add_child(_end_turn)

	_hand_box = HBoxContainer.new()
	_hand_box.add_theme_constant_override("separation", 6)
	_hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_box.size_flags_vertical = Control.SIZE_SHRINK_END
	vbox.add_child(_hand_box)

	_fx = CombatFX.new()
	add_child(_fx)


func _make_hp_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(190, 20)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.14, 0.15, 0.18)
	background.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", background)
	return bar


func _refresh() -> void:
	var enemy := ctx.enemy
	var enemy_def := ctx.enemy_def
	_enemy_name.text = "%s  [%s]" % [String(enemy_def["name"]), enemy.ptype]
	_enemy_hp.max_value = enemy.max_hp
	if _last_enemy_hp_shown < 0:
		_enemy_hp.value = enemy.hp
		_last_enemy_hp_shown = enemy.hp
	elif enemy.hp != _last_enemy_hp_shown:
		_fx.tween_enemy_hp(_enemy_hp, float(enemy.hp))
		_last_enemy_hp_shown = enemy.hp
	_enemy_hp_text.text = " %d/%d" % [enemy.hp, enemy.max_hp]
	var enemy_bits: Array[String] = []
	if enemy.block > 0:
		enemy_bits.append("Block %d" % enemy.block)
	enemy_bits.append(CardText.status_line(enemy))
	_enemy_status.text = " | ".join(enemy_bits)
	if ctx.next_enemy_action_name != "":
		_intent.text = "Intent: %s" % ctx.next_enemy_action_name
	else:
		_intent.text = "Intent: ???"

	var player := ctx.player
	_player_stats.text = "HP %d/%d   Block %d   Stamina %d/%d   Gold %dg" % [
		player.hp, player.max_hp, player.block,
		player.current_stamina, player.max_stamina, player.gold,
	]
	_player_status.text = CardText.status_line(player)

	_rebuild_hand()
	_rebuild_items()
	_end_turn.disabled = busy


func _rebuild_hand() -> void:
	for child in _hand_box.get_children():
		child.queue_free()
	for i in ctx.player.hand.size():
		var card_id: String = ctx.player.hand[i]
		var check := ctx.can_play_card(i)
		var button := CardWidget.build(
			card_id, ctx.enemy.ptype, Run.starter_id,
			busy or not check["ok"], String(check["reason"]), COMBAT_CARD_SIZE,
		)
		button.pressed.connect(_on_card_pressed.bind(i))
		_hand_box.add_child(button)
	if ctx.player.hand.is_empty():
		var empty := Label.new()
		empty.text = "(no cards in hand)"
		empty.modulate = Color(1, 1, 1, 0.5)
		_hand_box.add_child(empty)


func _rebuild_items() -> void:
	for child in _items_box.get_children():
		child.queue_free()
	if ctx.player.inventory.is_empty():
		var empty := Label.new()
		empty.text = "(empty)"
		empty.modulate = Color(1, 1, 1, 0.5)
		_items_box.add_child(empty)
		return
	for item_id in ctx.player.inventory:
		var item: Dictionary = Balance.items[item_id]
		var button := Button.new()
		button.text = String(item["name"])
		button.tooltip_text = CardText.item_description(item)
		button.disabled = busy or ctx.items_used_this_turn >= 1 or not bool(item.get("in_combat", false))
		button.pressed.connect(_on_item_pressed.bind(String(item_id)))
		_items_box.add_child(button)


func _log_msg(message: String) -> void:
	_log.text = message


func _pause(seconds: float) -> Signal:
	return get_tree().create_timer(seconds).timeout
