class_name GameHUD
extends CanvasLayer
## Exploration HUD: player stats top-left, zone name top-center, minimap
## top-right, trainer + starter party strip bottom-left, toasts, movement hint.

const LearnsetOps = preload("res://scripts/core/learnset_ops.gd")
const StarterEvo = preload("res://scripts/core/starter_evo.gd")

const PARTY_TRAINER_HEIGHT := 150
const PARTY_POKEMON_HEIGHT := 93  # ~62% of trainer
const LAYER_NORMAL := 5
const LAYER_ABOVE_COMBAT := 11  # CombatUI sits at layer 10

var minimap: Minimap

var _stats: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _zone: Label
var _toast_box: VBoxContainer
var _minimap_wrap: VBoxContainer
var _party_layer: CanvasLayer
var _party_box: HBoxContainer   # [trainer sprite, current-species Pokémon sprite]
var _party_species := ""        # species the Pokémon avatar currently shows


func _ready() -> void:
	layer = 5

	var panel := UITheme.make_panel(10)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 12
	panel.offset_top = 12
	panel.custom_minimum_size = Vector2(198, 0)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	_hp_label = UITheme.label("HP", UITheme.FONT_SMALL, UITheme.TEXT_DIM)
	col.add_child(_hp_label)
	_hp_bar = UITheme.make_bar(UITheme.GOOD)
	col.add_child(_hp_bar)
	_stats = UITheme.label("", UITheme.FONT_BODY)
	col.add_child(_stats)

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

	_party_layer = CanvasLayer.new()
	_party_layer.layer = LAYER_NORMAL
	add_child(_party_layer)

	var portrait_wrap := PanelContainer.new()
	portrait_wrap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	portrait_wrap.offset_left = 12
	portrait_wrap.offset_bottom = -12
	portrait_wrap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_party_layer.add_child(portrait_wrap)

	var party := HBoxContainer.new()
	party.add_theme_constant_override("separation", 2)
	party.alignment = BoxContainer.ALIGNMENT_END
	portrait_wrap.add_child(party)
	party.add_child(_make_party_sprite(
			PortraitFactory.build(Run.trainer_appearance), PARTY_TRAINER_HEIGHT))
	_party_box = party  # the Pokémon sprite is (re)built by refresh(), so it evolves with XP

	var hint := Label.new()
	hint.text = "WASD/QE — move & strafe.  ← → — turn.  Face a Pokémon to battle.  Walk into a door to shop."
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
	# Evolve the party avatar when XP crosses a tier (rebuild — sprite size is
	# aspect-dependent, so a texture swap wouldn't resize correctly).
	var species := StarterEvo.species(Run.player, Balance)
	if _party_box != null and species != _party_species:
		_party_species = species
		while _party_box.get_child_count() > 1:
			var old := _party_box.get_child(_party_box.get_child_count() - 1)
			_party_box.remove_child(old)
			old.queue_free()
		if species != "":
			_party_box.add_child(_make_party_sprite(
					CreatureArt.get_texture(species), PARTY_POKEMON_HEIGHT))
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
	var candy_text := ""
	if Run.player.rare_candy > 0:
		candy_text = "\nRare Candy ×%d" % Run.player.rare_candy
	var evo_tier := StarterEvo.tier(Run.player.xp, Balance)
	if evo_tier > 0:
		candy_text += "\nStarter evo: tier %d" % evo_tier
	UITheme.set_bar(_hp_bar, Run.player.hp, Run.player.max_hp)
	_hp_label.text = "HP  %d / %d" % [Run.player.hp, Run.player.max_hp]
	_stats.text = "Gold  %dg\nDeck  %d cards\n%s%s\nBag:  %s\nBadges:  %s" % [
		Run.player.gold, Run.deck_size(), _xp_line(), candy_text, inventory_text, badge_text,
	]


func _xp_line() -> String:
	var next: Dictionary = LearnsetOps.next_unlock(Run.player, Run.starter_id, Balance)
	if next.is_empty():
		return "XP %d (all moves learned)" % Run.player.xp
	var move_name := String(Balance.cards[next["card_id"]]["name"])
	return "XP %d — next: %s in %d" % [Run.player.xp, move_name, int(next["remaining"])]


func set_zone(zone: String) -> void:
	_zone.text = zone


## Combat's enemy panel shares the top-right corner — hide the (much bigger,
## now-legible) minimap while it's up rather than fight over the same space.
## Not useful mid-fight anyway since the player can't move during combat.
func set_minimap_visible(v: bool) -> void:
	_minimap_wrap.visible = v


## Raise the party strip above CombatUI (layer 10) so it isn't covered by the
## bottom battle rail.
func set_party_above_combat(above: bool) -> void:
	_party_layer.layer = LAYER_ABOVE_COMBAT if above else LAYER_NORMAL


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


static func _make_party_sprite(texture: Texture2D, height: float) -> Control:
	texture = _crop_to_opaque(texture)
	var tex_h := maxf(float(texture.get_height()), 1.0)
	var aspect := float(texture.get_width()) / tex_h
	var width := height * aspect

	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(width, height)

	var rect := TextureRect.new()
	rect.texture = texture
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	rect.offset_right = width
	rect.offset_top = -height
	wrap.add_child(rect)
	return wrap


static func _crop_to_opaque(texture: Texture2D) -> Texture2D:
	var img := texture.get_image()
	if img == null or img.is_empty():
		return texture
	var used: Rect2i = img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return texture
	return ImageTexture.create_from_image(img.get_region(used))
