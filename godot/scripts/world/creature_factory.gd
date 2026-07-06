class_name CreatureFactory
## Procedural pixel-art billboard creatures — no imported assets.
## Every enemy in enemies.json gets a recognizable 2D silhouette drawn with
## PixelArt primitives, applied to a billboarded Sprite3D. Since the camera
## is always first-person and roughly frontal, sprites are drawn face-on —
## no more need to sculpt a silhouette that reads from every angle.

const TYPE_COLORS := {
	"NORMAL": Color(0.78, 0.7, 0.55),
	"FIRE": Color(0.95, 0.45, 0.2),
	"WATER": Color(0.3, 0.55, 0.92),
	"GRASS": Color(0.38, 0.72, 0.35),
	"ROCK": Color(0.58, 0.54, 0.46),
	"POISON": Color(0.62, 0.36, 0.68),
	"BUG": Color(0.68, 0.74, 0.25),
	"FLYING": Color(0.65, 0.72, 0.88),
}

static var _cache: Dictionary = {}  # enemy_id -> ImageTexture


static func type_color(ptype: String) -> Color:
	return TYPE_COLORS.get(ptype, Color(0.7, 0.7, 0.7))


static func build_texture(enemy_id: String) -> ImageTexture:
	if _cache.has(enemy_id):
		return _cache[enemy_id]

	var img: Image
	match enemy_id:
		"pidgey":
			img = _pidgey()
		"rattata":
			img = _rattata()
		"weedle":
			img = _grub(Color(0.85, 0.62, 0.3), true)
		"caterpie":
			img = _grub(Color(0.45, 0.78, 0.35), false)
		"nidoran_m":
			img = _nidoran()
		"metapod":
			img = _cocoon(Color(0.42, 0.7, 0.4))
		"kakuna":
			img = _cocoon(Color(0.85, 0.75, 0.25))
		"geodude":
			img = _geodude()
		"zubat":
			img = _zubat()
		"onix":
			img = _onix()
		"brock":
			img = _trainer(Color(0.45, 0.3, 0.2), Color(0.25, 0.2, 0.18))
		_:
			if enemy_id.begins_with("rival_"):
				img = _trainer(Color(0.25, 0.35, 0.75), Color(0.5, 0.3, 0.15))
			elif enemy_id.begins_with("bug_catcher"):
				img = _trainer(Color(0.35, 0.6, 0.3), Color(0.9, 0.8, 0.3))
			else:
				img = _blob(Color(0.7, 0.7, 0.7))

	var tex := PixelArt.to_texture(img)
	_cache[enemy_id] = tex
	return tex


static func build_sprite(enemy_id: String) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = CreatureArt.get_texture(enemy_id)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	var tex_height := sprite.texture.get_height()
	sprite.pixel_size = 1.9 / float(tex_height)
	sprite.offset = Vector2(0, tex_height / 2.0)
	return sprite


# --- Species builders (32px-wide canvases, taller where needed) ---

static func _pidgey() -> Image:
	var img := PixelArt.new_canvas(32)
	var brown := Color(0.65, 0.48, 0.3)
	var cream := Color(0.9, 0.82, 0.65)
	PixelArt.outlined_circle(img, Vector2(16, 20), 9, brown)
	PixelArt.outlined_circle(img, Vector2(16, 11), 7, cream)
	PixelArt.rect(img, Rect2i(14, 9, 4, 3), Color(0.9, 0.6, 0.2))
	PixelArt.outlined_circle(img, Vector2(6, 19), 5, brown)
	PixelArt.outlined_circle(img, Vector2(26, 19), 5, brown)
	_eyes(img, 16, 8, 3)
	return img


static func _rattata() -> Image:
	var img := PixelArt.new_canvas(32)
	var purple := Color(0.6, 0.4, 0.62)
	PixelArt.outlined_circle(img, Vector2(16, 21), 9, purple)
	PixelArt.outlined_circle(img, Vector2(16, 11), 7, purple)
	PixelArt.outlined_circle(img, Vector2(10, 5), 3, purple)
	PixelArt.outlined_circle(img, Vector2(22, 5), 3, purple)
	PixelArt.rect(img, Rect2i(14, 14, 2, 2), Color(0.95, 0.95, 0.9))
	PixelArt.rect(img, Rect2i(16, 14, 2, 2), Color(0.95, 0.95, 0.9))
	_eyes(img, 16, 9, 3)
	return img


static func _grub(body_color: Color, horn: bool) -> Image:
	var img := PixelArt.new_canvas(32)
	PixelArt.outlined_circle(img, Vector2(16, 23), 8, body_color.darkened(0.2))
	PixelArt.outlined_circle(img, Vector2(16, 15), 8.5, body_color.darkened(0.08))
	PixelArt.outlined_circle(img, Vector2(16, 7), 7, body_color)
	if horn:
		PixelArt.rect(img, Rect2i(15, 0, 2, 4), Color(0.95, 0.9, 0.8))
	else:
		PixelArt.outlined_circle(img, Vector2(16, 1), 2, Color(0.9, 0.3, 0.25))
	_eyes(img, 16, 6, 3)
	return img


static func _nidoran() -> Image:
	var img := PixelArt.new_canvas(32)
	var pink := Color(0.78, 0.45, 0.65)
	PixelArt.outlined_circle(img, Vector2(16, 20), 9, pink)
	PixelArt.rect(img, Rect2i(8, 3, 5, 11), pink.darkened(0.1))
	PixelArt.rect(img, Rect2i(19, 3, 5, 11), pink.darkened(0.1))
	PixelArt.rect(img, Rect2i(14, 9, 4, 5), Color(0.95, 0.9, 0.85))
	PixelArt.outlined_circle(img, Vector2(23, 20), 2, pink.darkened(0.25))
	_eyes(img, 16, 16, 4)
	return img


static func _cocoon(color: Color) -> Image:
	var img := PixelArt.new_canvas_wh(32, 40)
	PixelArt.outlined_rect(img, Rect2i(9, 4, 14, 32), color)
	_eyes(img, 16, 14, 3)
	return img


static func _geodude() -> Image:
	var img := PixelArt.new_canvas(32)
	var gray := Color(0.55, 0.52, 0.47)
	PixelArt.outlined_circle(img, Vector2(16, 18), 12, gray)
	PixelArt.outlined_circle(img, Vector2(3, 20), 5, gray.darkened(0.1))
	PixelArt.outlined_circle(img, Vector2(29, 20), 5, gray.darkened(0.1))
	PixelArt.rect(img, Rect2i(9, 9, 14, 2), gray.darkened(0.3))
	_eyes(img, 16, 15, 4)
	return img


static func _zubat() -> Image:
	var img := PixelArt.new_canvas(32)
	var blue := Color(0.35, 0.45, 0.8)
	var wing := Color(0.55, 0.35, 0.6)
	_streak_wing(img, Vector2(13, 16), -1, wing)
	_streak_wing(img, Vector2(19, 16), 1, wing)
	PixelArt.outlined_circle(img, Vector2(16, 16), 8, blue)
	PixelArt.rect(img, Rect2i(9, 12, 3, 3), blue.darkened(0.15))
	PixelArt.rect(img, Rect2i(20, 12, 3, 3), blue.darkened(0.15))
	PixelArt.rect(img, Rect2i(14, 19, 1, 3), Color(0.95, 0.95, 0.9))
	PixelArt.rect(img, Rect2i(17, 19, 1, 3), Color(0.95, 0.95, 0.9))
	return img


static func _streak_wing(img: Image, base: Vector2, dir: int, color: Color) -> void:
	for i in range(4):
		var far := base + Vector2(dir * (7 + i * 2.0), -4.0 + i * 2.5)
		PixelArt.streak(img, base, far, 2.0, color)


static func _onix() -> Image:
	var img := PixelArt.new_canvas_wh(32, 48)
	var gray := Color(0.5, 0.48, 0.45)
	PixelArt.outlined_circle(img, Vector2(16, 43), 8, gray.darkened(0.05))
	PixelArt.outlined_circle(img, Vector2(15, 31), 7, gray.darkened(0.05))
	PixelArt.outlined_circle(img, Vector2(17, 20), 6, gray.darkened(0.05))
	PixelArt.outlined_circle(img, Vector2(16, 9), 8, gray)
	PixelArt.rect(img, Rect2i(14, 0, 4, 4), gray.darkened(0.2))
	_eyes(img, 16, 8, 4)
	return img


static func _trainer(shirt: Color, hair: Color) -> Image:
	var img := PixelArt.new_canvas_wh(32, 40)
	var skin := Color(0.9, 0.72, 0.55)
	PixelArt.rect(img, Rect2i(11, 22, 10, 16), Color(0.25, 0.25, 0.3))
	PixelArt.outlined_rect(img, Rect2i(8, 12, 16, 16), shirt)
	PixelArt.outlined_circle(img, Vector2(16, 7), 7, skin)
	PixelArt.outlined_rect(img, Rect2i(9, 0, 14, 6), hair)
	_eyes(img, 16, 7, 3)
	return img


static func _blob(color: Color) -> Image:
	var img := PixelArt.new_canvas(32)
	PixelArt.outlined_circle(img, Vector2(16, 16), 10, color)
	_eyes(img, 16, 14, 4)
	return img


static func _eyes(img: Image, cx: int, cy: int, spacing: int) -> void:
	PixelArt.rect(img, Rect2i(cx - spacing - 1, cy - 1, 2, 2), Color(0.1, 0.1, 0.1))
	PixelArt.rect(img, Rect2i(cx + spacing - 1, cy - 1, 2, 2), Color(0.1, 0.1, 0.1))
