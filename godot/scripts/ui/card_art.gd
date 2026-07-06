class_name CardArt
## Resolves card art: real imported illustration if available (variant-aware
## by starter), else a procedural placeholder icon. Drop a new
## `<card_id>.png` or `<card_id>_<starter_id>.png` into art/cards/ and it's
## picked up automatically next run — no code changes needed.

const ART_DIR := "res://art/cards"

static var _file_cache: Dictionary = {}       # "card_id" or "card_id_starter" -> Texture2D
static var _scanned := false
static var _placeholder_cache: Dictionary = {} # card_id -> ImageTexture


static func get_texture(card_id: String, starter_id: String) -> Texture2D:
	_ensure_scanned()
	var variant_key := "%s_%s" % [card_id, starter_id]
	if _file_cache.has(variant_key):
		return _file_cache[variant_key]
	if _file_cache.has(card_id):
		return _file_cache[card_id]
	return _placeholder(card_id)


static func _ensure_scanned() -> void:
	if _scanned:
		return
	_scanned = true
	var dir := DirAccess.open(ART_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var ext := fname.get_extension().to_lower()
			if ext in ["png", "jpg", "jpeg", "webp"]:
				var key := fname.get_basename()
				var tex: Texture2D = load(ART_DIR + "/" + fname)
				if tex != null:
					_file_cache[key] = tex
		fname = dir.get_next()
	dir.list_dir_end()


static func _placeholder(card_id: String) -> ImageTexture:
	if _placeholder_cache.has(card_id):
		return _placeholder_cache[card_id]

	var card: Dictionary = Balance.cards.get(card_id, {})
	var ptype := String(card.get("pokemon_type", "NORMAL"))
	var card_type := String(card.get("card_type", "attack"))
	var color := CreatureFactory.type_color(ptype)
	var img := PixelArt.new_canvas(32)

	match ptype:
		"FIRE":
			PixelArt.icon_flame(img, color)
		"WATER":
			PixelArt.icon_water(img, color)
		"GRASS":
			PixelArt.icon_leaf(img, color)
		"POISON":
			PixelArt.icon_drip(img, color)
		"ROCK":
			PixelArt.icon_rock(img, color)
		_:
			if card_type == "support":
				_icon_shield(img, color)
			elif card_type == "status":
				_icon_wave(img, color)
			else:
				PixelArt.icon_streaks(img, color)

	var tex := PixelArt.to_texture(img)
	_placeholder_cache[card_id] = tex
	return tex


static func _icon_shield(img: Image, color: Color) -> void:
	PixelArt.outlined_circle(img, Vector2(16, 16), 10, color)
	PixelArt.rect(img, Rect2i(14, 10, 4, 12), color.darkened(0.3))


static func _icon_wave(img: Image, color: Color) -> void:
	PixelArt.filled_circle(img, Vector2(16, 16), 10, color.darkened(0.3))
	PixelArt.filled_circle(img, Vector2(16, 16), 6, color)
	PixelArt.filled_circle(img, Vector2(16, 16), 2, Color(1, 1, 1, 0.85))
