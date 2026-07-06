class_name PixelArt
## Shared procedural pixel-art drawing toolkit (no imported assets).
## Used by creature sprites, wall/door textures, the HUD portrait, and
## fallback card icons. Draw calls are cheap one-shot builds cached by callers.


static func new_canvas(size: int) -> Image:
	return new_canvas_wh(size, size)


static func new_canvas_wh(w: int, h: int) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func filled_circle(img: Image, center: Vector2, radius: float, color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var y0 := maxi(0, int(center.y - radius))
	var y1 := mini(h - 1, int(center.y + radius))
	var x0 := maxi(0, int(center.x - radius))
	var x1 := mini(w - 1, int(center.x + radius))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				img.set_pixel(x, y, color)


## Outlined circle: darker oversized pass then true-size base color — cheap
## 1px silhouette outline that matters a lot at 32-48px resolution.
static func outlined_circle(img: Image, center: Vector2, radius: float, color: Color,
		outline: Color = Color(0, 0, 0, 0), outline_extra: float = 1.0) -> void:
	var outline_color := outline
	if outline_color.a == 0.0:
		outline_color = color.darkened(0.45)
	filled_circle(img, center, radius + outline_extra, outline_color)
	filled_circle(img, center, radius, color)


static func rect(img: Image, r: Rect2i, color: Color) -> void:
	var clipped := r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if clipped.size.x > 0 and clipped.size.y > 0:
		img.fill_rect(clipped, color)


## Outlined rect, same trick as outlined_circle.
static func outlined_rect(img: Image, r: Rect2i, color: Color,
		outline: Color = Color(0, 0, 0, 0), outline_extra: int = 1) -> void:
	var outline_color := outline
	if outline_color.a == 0.0:
		outline_color = color.darkened(0.45)
	rect(img, r.grow(outline_extra), outline_color)
	rect(img, r, color)


## A thick diagonal streak (claw marks, motion lines, spray) between two points.
static func streak(img: Image, from: Vector2, to: Vector2, thickness: float, color: Color) -> void:
	var dist := from.distance_to(to)
	var steps := maxi(1, int(dist * 2.0))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := from.lerp(to, t)
		filled_circle(img, p, thickness * 0.5, color)


static func pixel(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, color)


static func to_texture(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


static func icon_flame(img: Image, color: Color) -> void:
	outlined_circle(img, Vector2(16, 22), 8, color)
	outlined_circle(img, Vector2(16, 12), 5, color.lightened(0.2))
	outlined_circle(img, Vector2(16, 5), 2.5, Color(1, 0.9, 0.6))


static func icon_water(img: Image, color: Color) -> void:
	for i in 4:
		filled_circle(img, Vector2(10 + i * 4, 22 - i * 3), 3.5 - i * 0.4, color)
	outlined_circle(img, Vector2(24, 9), 3, color.lightened(0.2))


static func icon_leaf(img: Image, color: Color) -> void:
	for i in 5:
		var t := float(i) / 4.0
		var p: Vector2 = Vector2(8, 26).lerp(Vector2(24, 6), t)
		filled_circle(img, p, 3.5 - t * 1.5, color)


static func icon_drip(img: Image, color: Color) -> void:
	outlined_circle(img, Vector2(16, 13), 6, color)
	filled_circle(img, Vector2(16, 23), 3, color)


static func icon_rock(img: Image, color: Color) -> void:
	outlined_rect(img, Rect2i(9, 12, 14, 12), color)
	rect(img, Rect2i(9, 9, 6, 3), color.darkened(0.2))


static func icon_streaks(img: Image, color: Color) -> void:
	streak(img, Vector2(6, 8), Vector2(26, 14), 2.5, color)
	streak(img, Vector2(6, 16), Vector2(26, 22), 2.5, color)
	streak(img, Vector2(6, 24), Vector2(26, 28), 2.0, color)
