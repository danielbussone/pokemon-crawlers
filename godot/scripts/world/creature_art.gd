class_name CreatureArt
## Resolves creature/trainer art: real imported illustration if available for
## that enemy_id, else the procedural pixel-art fallback from CreatureFactory.
## Same pattern as CardArt — drop a `<enemy_id>.png` into art/creatures/ (or a
## trainer portrait into art/trainers/, which wins for that id) and it's picked up
## automatically next run. A sibling `<enemy_id>.gif` is preferred when use_gif_art.
##
## The Gen 5 Black/White scrape (see black-white/README.md) is checked first,
## since it's the preferred art source going forward and covers all of Gen 1;
## the flat files above remain a fallback for ids that aren't plain species
## (rival_*, bug_catcher_*, brock) and a safety net for anything unscraped.

const ART_DIR := "res://art/creatures"
const TRAINER_DIR := "res://art/trainers"
const BW_STATIC_DIR := ART_DIR + "/black-white/normal"
const BW_ANIM_DIR := ART_DIR + "/black-white/anim/normal"
const ALPHA_CUTOFF := 16
const BRIGHT_THRESHOLD := 200  # r8/g8/b8 — faint highlights become opaque white
const HOLE_FILL_MIN := 12      # ignore single-pixel noise
const HOLE_FILL_MAX := 350     # skip large interior gaps (mouth shading, etc.)
const MIN_OPAQUE_PER_AXIS := 8
const EYE_WHITE := Color(1, 1, 1, 1)

static var _trainer_cache: Dictionary = {}    # id -> ImageTexture (trainer portrait)
static var _trainer_scanned := false
static var _file_cache: Dictionary = {}       # enemy_id -> ImageTexture
static var _gif_cache: Dictionary = {}        # enemy_id -> AnimatedTexture (or null if none)
static var _bw_static_cache: Dictionary = {}  # enemy_id -> ImageTexture (or null if none)
static var _scanned := false


static func get_texture(enemy_id: String) -> Texture2D:
	# Trainer portraits (people) live in art/trainers/ and win for that id.
	var trainer_tex := _get_trainer_texture(enemy_id)
	if trainer_tex != null:
		return trainer_tex

	if Settings.use_gif_art:
		var gif_tex := _get_gif_texture(enemy_id)
		if gif_tex != null:
			return gif_tex

	var bw_tex := _get_bw_static_texture(enemy_id)
	if bw_tex != null:
		return bw_tex

	_ensure_scanned()
	if _file_cache.has(enemy_id):
		return _file_cache[enemy_id]

	var path := ART_DIR + "/" + enemy_id + ".png"
	if ResourceLoader.exists(path):
		var tex := _load_cropped(path)
		if tex != null:
			_file_cache[enemy_id] = tex
			return tex

	return CreatureFactory.build_texture(enemy_id)


## Trainer portrait by id, from art/trainers/. Scanned once via DirAccess + Image.load
## (the same live-disk read the creature scrape uses — reliable regardless of import
## state, unlike FileAccess/ResourceLoader on imported res:// paths).
static func _get_trainer_texture(enemy_id: String) -> Texture2D:
	if not _trainer_scanned:
		_trainer_scanned = true
		var dir := DirAccess.open(TRAINER_DIR)
		if dir != null:
			dir.list_dir_begin()
			var fname := dir.get_next()
			while fname != "":
				if not dir.current_is_dir() and fname.get_extension().to_lower() == "png":
					var t := _load_cropped(TRAINER_DIR + "/" + fname)
					if t != null:
						_trainer_cache[fname.get_basename()] = t
				fname = dir.get_next()
			dir.list_dir_end()
	return _trainer_cache.get(enemy_id, null)


## pokemondb's scrape uses hyphenated slugs (nidoran-f) where our enemy ids
## use underscores (nidoran_f); try the id as-is, then the hyphenated form.
static func _slug_variants(enemy_id: String) -> Array[String]:
	var variants: Array[String] = [enemy_id]
	if enemy_id.contains("_"):
		variants.append(enemy_id.replace("_", "-"))
	return variants


static func _get_gif_texture(enemy_id: String) -> Texture2D:
	if _gif_cache.has(enemy_id):
		return _gif_cache[enemy_id]

	var tex: Texture2D = null
	for slug in _slug_variants(enemy_id):
		var bw_path := BW_ANIM_DIR + "/" + slug + ".gif"
		if FileAccess.file_exists(bw_path):
			tex = GifDecoder.load_animated_texture(bw_path)
			break

	if tex == null:
		var flat_path := ART_DIR + "/" + enemy_id + ".gif"
		if FileAccess.file_exists(flat_path):
			tex = GifDecoder.load_animated_texture(flat_path)

	_gif_cache[enemy_id] = tex
	return tex


static func _get_bw_static_texture(enemy_id: String) -> Texture2D:
	if _bw_static_cache.has(enemy_id):
		return _bw_static_cache[enemy_id]

	var tex: Texture2D = null
	for slug in _slug_variants(enemy_id):
		var path := BW_STATIC_DIR + "/" + slug + ".png"
		if FileAccess.file_exists(path):
			tex = _load_cropped(path)
			if tex != null:
				break

	_bw_static_cache[enemy_id] = tex
	return tex


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
				var tex := _load_cropped(ART_DIR + "/" + fname)
				if tex != null:
					_file_cache[key] = tex
		fname = dir.get_next()
	dir.list_dir_end()


static func _load_cropped(path: String) -> ImageTexture:
	var img := Image.new()
	if img.load(path) != OK or img.is_empty():
		return null
	return ImageTexture.create_from_image(_tight_opaque_crop(img))


## Drop faint alpha, restore eye whites, ignore stray edge pixels for layout.
static func _tight_opaque_crop(img: Image) -> Image:
	var work := img.duplicate()
	work.convert(Image.FORMAT_RGBA8)
	_decontaminate_alpha(work)
	_fill_small_interior_holes(work)

	# Small pixel-art sheets keep canvas padding; tight crop only helps large sheets.
	if work.get_width() <= 128 and work.get_height() <= 128:
		return work

	var used := _significant_opaque_rect(work)
	if used.size.x <= 0 or used.size.y <= 0:
		return work
	return work.get_region(used)


static func _decontaminate_alpha(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a8 < ALPHA_CUTOFF:
				if p.a8 > 0 \
						and p.r8 >= BRIGHT_THRESHOLD \
						and p.g8 >= BRIGHT_THRESHOLD \
						and p.b8 >= BRIGHT_THRESHOLD:
					img.set_pixel(x, y, EYE_WHITE)
				else:
					img.set_pixel(x, y, Color(0, 0, 0, 0))


## Transparent pockets fully enclosed by opaque art (eye sockets) → white fill.
static func _fill_small_interior_holes(img: Image) -> void:
	var exterior := _exterior_transparent_mask(img)
	var visited: Dictionary = {}
	for y in img.get_height():
		for x in img.get_width():
			var pos := Vector2i(x, y)
			if img.get_pixel(x, y).a8 > 0 or exterior.has(pos) or visited.has(pos):
				continue
			var region: Array[Vector2i] = []
			_flood_transparent_region(img, exterior, visited, pos, region)
			if region.size() >= HOLE_FILL_MIN and region.size() <= HOLE_FILL_MAX:
				for p in region:
					img.set_pixel(p.x, p.y, EYE_WHITE)


static func _exterior_transparent_mask(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var exterior: Dictionary = {}
	var queue: Array[Vector2i] = []

	for x in w:
		_enqueue_exterior(img, exterior, queue, Vector2i(x, 0))
		_enqueue_exterior(img, exterior, queue, Vector2i(x, h - 1))
	for y in h:
		_enqueue_exterior(img, exterior, queue, Vector2i(0, y))
		_enqueue_exterior(img, exterior, queue, Vector2i(w - 1, y))

	while not queue.is_empty():
		var pos: Vector2i = queue.pop_front()
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = pos + offset
			if next.x < 0 or next.y < 0 or next.x >= w or next.y >= h:
				continue
			if exterior.has(next) or img.get_pixel(next.x, next.y).a8 > 0:
				continue
			exterior[next] = true
			queue.append(next)
	return exterior


static func _enqueue_exterior(
		img: Image, exterior: Dictionary, queue: Array[Vector2i], pos: Vector2i
) -> void:
	if img.get_pixel(pos.x, pos.y).a8 > 0 or exterior.has(pos):
		return
	exterior[pos] = true
	queue.append(pos)


static func _flood_transparent_region(
		img: Image,
		exterior: Dictionary,
		visited: Dictionary,
		start: Vector2i,
		region: Array[Vector2i],
) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	while not queue.is_empty():
		var pos: Vector2i = queue.pop_front()
		region.append(pos)
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = pos + offset
			if next.x < 0 or next.y < 0 or next.x >= w or next.y >= h:
				continue
			if exterior.has(next) or visited.has(next) or img.get_pixel(next.x, next.y).a8 > 0:
				continue
			visited[next] = true
			queue.append(next)


static func _significant_opaque_rect(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var left := w
	var right := -1
	var top := h
	var bottom := -1

	for x in w:
		var count := 0
		for y in h:
			if img.get_pixel(x, y).a8 > 0:
				count += 1
		if count >= MIN_OPAQUE_PER_AXIS:
			left = mini(left, x)
			right = maxi(right, x)

	for y in h:
		var count := 0
		for x in w:
			if img.get_pixel(x, y).a8 > 0:
				count += 1
		if count >= MIN_OPAQUE_PER_AXIS:
			top = mini(top, y)
			bottom = maxi(bottom, y)

	if right < left or bottom < top:
		return Rect2i()
	return Rect2i(left, top, right - left + 1, bottom - top + 1)
