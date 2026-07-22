extends RefCounted
## Procedural 16×16 tileable pixel textures for terrain materials, plus the authored-
## (Consumed via `const TerrainTex = preload(...)`, matching the StageLayout convention.)
## override lookup (art/terrain/<name>.png). Single source of truth shared by the world
## renderer (WorldBuilder) and the map editor's in-app texture painter, so the pixels you
## edit match exactly what renders in 3D.

const SIZE := 16


## The override lives at res://art/terrain/<name>.png, read/written straight from the
## filesystem (Image.load / save_png) rather than via the import pipeline — so the in-app
## painter can write a PNG and the freshly-launched 3D preview reads it back with no Godot
## editor reimport in between. `_fs_path` is the absolute on-disk path of that res:// file.
static func override_path(name: String) -> String:
	return "res://art/terrain/%s.png" % name


static func _fs_path(name: String) -> String:
	return ProjectSettings.globalize_path(override_path(name))


static func has_override(name: String) -> bool:
	return FileAccess.file_exists(_fs_path(name))


## An editable RGBA8 image for a material: the authored PNG if one exists, else a freshly
## generated procedural image. Always RGBA8 so callers can set_pixel.
static func image_for(name: String) -> Image:
	if has_override(name):
		var im := Image.new()
		if im.load(_fs_path(name)) == OK:
			im.convert(Image.FORMAT_RGBA8)
			return im
	return generate_image(name)


## Write a material's override PNG (creating art/terrain/ if needed). Returns an Error.
static func save_override(name: String, img: Image) -> int:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/terrain"))
	return img.save_png(_fs_path(name))


## Remove a material's override so it falls back to the procedural texture.
static func delete_override(name: String) -> void:
	if has_override(name):
		DirAccess.remove_absolute(_fs_path(name))


static func pattern_of(name: String) -> String:
	if ThemePalette.is_building_material(name):
		return "windows"  # any building facade (wood/brick/glass/…) until an override is painted
	match name:
		"wall", "wall_interior": return "brick"
		"water", "water_surf": return "water"
		"lava": return "lava"
		"wood", "planks", "dock", "railing": return "planks"
		"tile", "marble", "pavement", "road", "metal_floor", "wall_metal": return "tile"
		_: return "noise"  # grass, dirt, sand, rock, ash, floor_cave, leaves, boulder…


static func _shade(c: Color, amt: float) -> Color:
	return c.lightened(amt) if amt >= 0.0 else c.darkened(-amt)


## A 16×16 tileable pixel texture for a material, from its base color + pattern.
static func generate_image(name: String) -> Image:
	var s := SIZE
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var base := ThemePalette.color_of(name)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	match pattern_of(name):
		"brick":
			var mortar := _shade(base, -0.4)
			for y in s:
				for x in s:
					var band := y / 4
					var vx := (x + (band % 2) * 4) % 8
					if y % 4 == 0 or vx == 0:
						img.set_pixel(x, y, mortar)
					else:
						img.set_pixel(x, y, _shade(base, rng.randf_range(-0.06, 0.06)))
		"planks":
			var seam := _shade(base, -0.35)
			for y in s:
				var grain := rng.randf_range(-0.05, 0.05)
				for x in s:
					if x % 8 == 0 or y % 4 == 0:
						img.set_pixel(x, y, seam)
					else:
						img.set_pixel(x, y, _shade(base, grain + rng.randf_range(-0.03, 0.03)))
		"tile":
			var line := _shade(base, -0.22)
			for y in s:
				for x in s:
					if x == 0 or y == 0 or x == s / 2 or y == s / 2:
						img.set_pixel(x, y, line)
					else:
						img.set_pixel(x, y, _shade(base, rng.randf_range(-0.03, 0.04)))
		"windows":
			# One storey: a row of windows with a floor-division stripe at its base. The
			# building material tiles this vertically once per storey (world-tiled), so a
			# stack reads as N floors with divider lines between them.
			var frame := _shade(base, -0.32)
			var floor_line := _shade(base, -0.5)
			var glass := Color(0.58, 0.74, 0.9)
			for y in s:
				for x in s:
					var wx := x % 8
					if y >= s - 2:  # floor division at the base of each storey
						img.set_pixel(x, y, floor_line)
					elif y >= 4 and y <= 11 and wx >= 2 and wx <= 6:  # window band, 2 across
						img.set_pixel(x, y, glass.darkened(rng.randf_range(0.0, 0.16)))
					elif wx == 0 and y >= 3 and y <= 12:  # window frame column
						img.set_pixel(x, y, frame)
					else:
						img.set_pixel(x, y, _shade(base, rng.randf_range(-0.04, 0.04)))
		"water":
			for y in s:
				for x in s:
					var wave := 0.12 * sin(TAU * float(y) / 8.0 + float(x) * 0.4)
					img.set_pixel(x, y, _shade(base, wave + rng.randf_range(-0.02, 0.02)))
		"lava":
			for y in s:
				for x in s:
					var r := rng.randf()
					if r < 0.14:
						img.set_pixel(x, y, Color(1.0, 0.85, 0.25))  # hotspot
					elif r < 0.28:
						img.set_pixel(x, y, _shade(base, -0.4))       # crust crack
					else:
						img.set_pixel(x, y, _shade(base, rng.randf_range(-0.08, 0.12)))
		_:  # noise — mottled speckle over the base color
			for y in s:
				for x in s:
					var r := rng.randf()
					if r < 0.10:
						img.set_pixel(x, y, _shade(base, 0.16))
					elif r < 0.22:
						img.set_pixel(x, y, _shade(base, -0.16))
					else:
						img.set_pixel(x, y, _shade(base, rng.randf_range(-0.05, 0.06)))
	return img
