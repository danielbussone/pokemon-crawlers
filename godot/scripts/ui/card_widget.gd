class_name CardWidget
## Shared portrait trading-card control builder for combat_ui.gd/draft_ui.gd —
## header strip, illustration panel (real art if available, else a
## procedural placeholder from CardArt), effect text below.

const CARD_SIZE := Vector2(150, 210)
const ART_HEIGHT_FRACTION := 0.45

## Classic Pokémon TCG energy-color coding — several game-types intentionally
## share one card color here, same as the physical TCG's smaller color set
## (Rock/Ground/Fighting -> brown, Normal/Flying -> grey, Grass/Poison -> green).
## Bug has no dedicated TCG energy color either; Base Set printed Bug Pokémon
## (Caterpie, Weedle) as Grass-type cards, so it shares that green too.
const TYPE_BG_COLORS := {
	"FIRE": Color(0.55, 0.22, 0.1),
	"WATER": Color(0.13, 0.32, 0.58),
	"GRASS": Color(0.16, 0.4, 0.18),
	"POISON": Color(0.16, 0.4, 0.18),
	"BUG": Color(0.16, 0.4, 0.18),
	"ELECTRIC": Color(0.55, 0.46, 0.08),
	"PSYCHIC": Color(0.4, 0.18, 0.48),
	"GROUND": Color(0.42, 0.3, 0.16),
	"ROCK": Color(0.42, 0.3, 0.16),
	"FIGHTING": Color(0.42, 0.3, 0.16),
	"NORMAL": Color(0.36, 0.36, 0.34),
	"FLYING": Color(0.36, 0.36, 0.34),
}


static func _type_stylebox(ptype: String, pressed: bool = false) -> StyleBoxFlat:
	var base: Color = TYPE_BG_COLORS.get(ptype, Color(0.2, 0.2, 0.22))
	var sb := StyleBoxFlat.new()
	sb.bg_color = base.darkened(0.25) if pressed else base
	sb.border_color = base.lightened(0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(4)
	return sb


static func build(card_id: String, enemy_type: String, starter_id: String,
		disabled: bool, tooltip: String, card_size: Vector2 = CARD_SIZE) -> Button:
	var card: Dictionary = Balance.cards[card_id]
	var ptype := String(card["pokemon_type"])
	var scale := card_size.y / CARD_SIZE.y
	var button := Button.new()
	button.custom_minimum_size = card_size
	# Without these, the parent HBoxContainer stretches each card to fill any
	# leftover space in the bottom panel instead of respecting CARD_SIZE.
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.clip_contents = true
	button.text = ""
	button.disabled = disabled
	button.tooltip_text = tooltip
	button.clip_text = false

	# Type-colored background/border, classic-TCG style.
	var normal_sb := _type_stylebox(ptype)
	var pressed_sb := _type_stylebox(ptype, true)
	var disabled_sb := _type_stylebox(ptype)
	disabled_sb.bg_color = disabled_sb.bg_color.darkened(0.55)
	disabled_sb.border_color = disabled_sb.border_color.darkened(0.4)
	button.add_theme_stylebox_override("normal", normal_sb)
	button.add_theme_stylebox_override("hover", _type_stylebox(ptype))
	button.add_theme_stylebox_override("pressed", pressed_sb)
	button.add_theme_stylebox_override("disabled", disabled_sb)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	button.add_child(vbox)

	var header := Label.new()
	header.text = "%s — %d" % [String(card["name"]), int(card["cost"])]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", maxi(9, int(13.0 * scale)))
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header)

	var art := TextureRect.new()
	art.texture = CardArt.get_texture(card_id, starter_id)
	art.custom_minimum_size = Vector2(card_size.x - 12, card_size.y * ART_HEIGHT_FRACTION)
	# Default expand_mode (EXPAND_KEEP_SIZE) sizes to max(custom_minimum_size,
	# texture's native pixels) — real art (e.g. 1201x880) would blow the card
	# up to fit it. IGNORE_SIZE defers entirely to custom_minimum_size/layout.
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.clip_contents = true
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(art)

	var effect := Label.new()
	effect.text = "%s\n%s" % [String(card["pokemon_type"]), CardText.summary(card, enemy_type, Balance)]
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.add_theme_font_size_override("font_size", maxi(9, int(12.0 * scale)))
	effect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(effect)

	var desc := String(card.get("description", ""))
	if desc != "":
		var flavor := Label.new()
		flavor.text = desc
		flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		flavor.add_theme_font_size_override("font_size", maxi(8, int(10.0 * scale)))
		flavor.modulate = Color(0.82, 0.82, 0.86, 0.78)
		flavor.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		flavor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(flavor)

	return button
