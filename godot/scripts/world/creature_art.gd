class_name CreatureArt
## Resolves creature/trainer art: real imported illustration if available for
## that enemy_id, else the procedural pixel-art fallback from CreatureFactory.
## Same pattern as CardArt — drop a `<enemy_id>.png` into art/creatures/ and
## it's picked up automatically next run, no code changes needed.

const ART_DIR := "res://art/creatures"

static var _file_cache: Dictionary = {}  # enemy_id -> Texture2D
static var _scanned := false


static func get_texture(enemy_id: String) -> Texture2D:
	_ensure_scanned()
	if _file_cache.has(enemy_id):
		return _file_cache[enemy_id]
	return CreatureFactory.build_texture(enemy_id)


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
