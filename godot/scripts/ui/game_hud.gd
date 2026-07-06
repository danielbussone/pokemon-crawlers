class_name GameHUD
extends CanvasLayer
## Exploration HUD: player stats top-left, zone name top-center, minimap
## top-right, trainer portrait bottom-left, toasts, movement hint.

var minimap: Minimap

var _stats: Label
var _zone: Label
var _toast_box: VBoxContainer
var _minimap_wrap: VBoxContainer


func _ready() -> void:
	layer = 5

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 12
	panel.offset_top = 12
	add_child(panel)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 16)
	panel.add_child(_stats)

	_zone = Label.new()
	_zone.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_zone.offset_top = 14
	_zone.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_zone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone.add_theme_font_size_override("font_size", 22)
	add_child(_zone)

	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_box.offset_top = 60
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_toast_box)

	_minimap_wrap = VBoxContainer.new()
	_minimap_wrap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_minimap_wrap.offset_right = -12
	_minimap_wrap.offset_top = 12
	_minimap_wrap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_minimap_wrap.add_theme_constant_override("separation", 4)
	add_child(_minimap_wrap)

	var minimap_title := Label.new()
	minimap_title.text = "MAP"
	minimap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	minimap_title.add_theme_font_size_override("font_size", 13)
	minimap_title.modulate = Color(1, 1, 1, 0.7)
	_minimap_wrap.add_child(minimap_title)

	minimap = Minimap.new()
	_minimap_wrap.add_child(minimap)

	var portrait_wrap := PanelContainer.new()
	portrait_wrap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	portrait_wrap.offset_left = 12
	portrait_wrap.offset_bottom = -12
	portrait_wrap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(portrait_wrap)
	var portrait := TextureRect.new()
	portrait.texture = PortraitFactory.build(Run.trainer_appearance)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	# Real trainer art is much bigger than the procedural fallback's canvas —
	# without IGNORE_SIZE the control balloons to the texture's native pixels
	# (same bug as the card-art sizing issue).
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.custom_minimum_size = Vector2(96, 120)
	portrait_wrap.add_child(portrait)

	var hint := Label.new()
	hint.text = "WASD/QE — move & strafe.  ← → — turn.  Step onto a Pokémon to battle.  Doors open shops once unlocked."
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_bottom = -10
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.55)
	add_child(hint)

	refresh()


func refresh() -> void:
	if Run.player == null:
		return
	var badge_text := "none yet"
	if not Run.player.badge_ids.is_empty():
		var names: Array[String] = []
		for badge_id in Run.player.badge_ids:
			names.append(String(Balance.badges[badge_id]["name"]))
		badge_text = ", ".join(names)
	var inventory_text := "empty"
	if not Run.player.inventory.is_empty():
		var item_names: Array[String] = []
		for item_id in Run.player.inventory:
			item_names.append(String(Balance.items[item_id]["name"]))
		inventory_text = ", ".join(item_names)
	_stats.text = "HP %d/%d\nGold %dg\nDeck %d cards\nBag: %s\nBadges: %s" % [
		Run.player.hp, Run.player.max_hp, Run.player.gold,
		Run.deck_size(), inventory_text, badge_text,
	]


func set_zone(zone: String) -> void:
	_zone.text = zone


## Combat's enemy panel shares the top-right corner — hide the (much bigger,
## now-legible) minimap while it's up rather than fight over the same space.
## Not useful mid-fight anyway since the player can't move during combat.
func set_minimap_visible(v: bool) -> void:
	_minimap_wrap.visible = v


func toast(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	_toast_box.add_child(label)
	var tween := create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)
