class_name PortraitFactory
## Trainer portrait for the HUD corner — the player's only visible "self" now
## that exploration is first-person. Real art if supplied (art/player/), else
## a procedural pixel-art bust as a fallback. Keyed by appearance ("boy"/
## "girl"), not starter — a trainer's look doesn't depend on their Pokémon.

const ART_DIR := "res://art/player"

static var _file_cache: Dictionary = {}  # appearance_id -> Texture2D
static var _scanned := false
static var _procedural_cache: Dictionary = {}  # appearance_id -> ImageTexture


static func build(appearance_id: String) -> Texture2D:
	_ensure_scanned()
	if _file_cache.has(appearance_id):
		return _file_cache[appearance_id]
	return _procedural(appearance_id)


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


static func _procedural(appearance_id: String) -> ImageTexture:
	if _procedural_cache.has(appearance_id):
		return _procedural_cache[appearance_id]

	var accent := Color(0.3, 0.45, 0.85) if appearance_id == "girl" else Color(0.75, 0.3, 0.3)
	if appearance_id == "girl":
		accent = Color(0.85, 0.35, 0.5)

	var img := PixelArt.new_canvas_wh(32, 40)
	var skin := Color(0.9, 0.72, 0.55)
	PixelArt.outlined_rect(img, Rect2i(8, 22, 16, 18), Color(0.3, 0.3, 0.35))
	PixelArt.outlined_circle(img, Vector2(16, 16), 9, skin)
	PixelArt.outlined_rect(img, Rect2i(6, 3, 20, 9), accent.darkened(0.2))
	PixelArt.rect(img, Rect2i(6, 10, 20, 3), accent.darkened(0.35))
	PixelArt.rect(img, Rect2i(13, 12, 2, 2), Color(0.1, 0.1, 0.1))
	PixelArt.rect(img, Rect2i(18, 12, 2, 2), Color(0.1, 0.1, 0.1))

	var tex := PixelArt.to_texture(img)
	_procedural_cache[appearance_id] = tex
	return tex
