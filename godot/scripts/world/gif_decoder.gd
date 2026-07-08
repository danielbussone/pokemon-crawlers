class_name GifDecoder
## Minimal GIF87a/89a decoder — Godot has no built-in GIF support at all.
## These sprite GIFs encode each tick as a small delta rect against the
## previous frame (disposal-method compositing), not a full redrawn frame,
## so a naive "read each frame's rect as the whole image" reader would
## produce garbage; this walks the real block structure and composites a
## full canvas per frame before handing frames to an AnimatedTexture.

const DISPOSE_NONE := 0
const DISPOSE_KEEP := 1
const DISPOSE_BACKGROUND := 2
const DISPOSE_PREVIOUS := 3


static func load_animated_texture(path: String) -> AnimatedTexture:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null

	var reader := _ByteReader.new(bytes)
	if reader.read_string(6) not in ["GIF87a", "GIF89a"]:
		return null

	var canvas_w := reader.read_u16()
	var canvas_h := reader.read_u16()
	var screen_packed := reader.read_u8()
	reader.read_u8()  # background color index — unused, we composite on transparent
	reader.read_u8()  # pixel aspect ratio — unused

	var global_table := PackedColorArray()
	if screen_packed & 0x80:
		global_table = _read_color_table(reader, 2 << (screen_packed & 0x07))

	var canvas := Image.create(canvas_w, canvas_h, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))

	var frame_images: Array[Image] = []
	var frame_delays: Array[float] = []

	var pending_delay := 0.1
	var pending_transparent_index := -1
	var pending_disposal := DISPOSE_NONE
	var prev_rect := Rect2i()
	var prev_disposal := DISPOSE_NONE
	var previous_snapshot: Image = null

	while reader.has_more():
		var block_id := reader.read_u8()

		if block_id == 0x21:  # extension
			var label := reader.read_u8()
			var data := reader.read_sub_blocks()
			if label == 0xF9 and data.size() >= 4:  # graphic control extension
				var flags := data[0]
				pending_disposal = (flags >> 2) & 0x07
				var has_transparency := (flags & 0x01) != 0
				var delay_100ths := data[1] | (data[2] << 8)
				pending_transparent_index = data[3] if has_transparency else -1
				pending_delay = (delay_100ths if delay_100ths > 0 else 10) / 100.0

		elif block_id == 0x2C:  # image descriptor
			var left := reader.read_u16()
			var top := reader.read_u16()
			var w := reader.read_u16()
			var h := reader.read_u16()
			var img_packed := reader.read_u8()

			var palette := global_table
			if img_packed & 0x80:
				palette = _read_color_table(reader, 2 << (img_packed & 0x07))
			var interlaced := (img_packed & 0x40) != 0

			var min_code_size := reader.read_u8()
			var lzw_data := reader.read_sub_blocks()
			var indices := _lzw_decode(lzw_data, min_code_size, w * h)
			if indices.size() < w * h:
				break  # truncated/corrupt stream — stop, keep whatever frames decoded so far

			if prev_disposal == DISPOSE_BACKGROUND:
				_clear_rect(canvas, prev_rect)
			elif prev_disposal == DISPOSE_PREVIOUS and previous_snapshot != null:
				canvas.copy_from(previous_snapshot)

			if pending_disposal == DISPOSE_PREVIOUS:
				previous_snapshot = canvas.duplicate()

			_blit(canvas, indices, palette, left, top, w, h, interlaced, pending_transparent_index)

			frame_images.append(canvas.duplicate())
			frame_delays.append(pending_delay)

			prev_rect = Rect2i(left, top, w, h)
			prev_disposal = pending_disposal
			pending_disposal = DISPOSE_NONE
			pending_transparent_index = -1

		elif block_id == 0x3B:  # trailer
			break
		else:
			break  # unrecognized block — bail out with whatever we have

	if frame_images.is_empty():
		return null

	var tex := AnimatedTexture.new()
	tex.frames = mini(frame_images.size(), 256)
	for i in tex.frames:
		tex.set_frame_texture(i, ImageTexture.create_from_image(frame_images[i]))
		tex.set_frame_duration(i, frame_delays[i])
	return tex


static func _read_color_table(reader: _ByteReader, count: int) -> PackedColorArray:
	var table := PackedColorArray()
	table.resize(count)
	for i in count:
		var r := reader.read_u8()
		var g := reader.read_u8()
		var b := reader.read_u8()
		table[i] = Color8(r, g, b, 255)
	return table


static func _clear_rect(canvas: Image, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			canvas.set_pixel(x, y, Color(0, 0, 0, 0))


static func _blit(
		canvas: Image,
		indices: PackedByteArray,
		palette: PackedColorArray,
		left: int,
		top: int,
		w: int,
		h: int,
		interlaced: bool,
		transparent_index: int,
) -> void:
	var row_order := _interlace_row_order(h) if interlaced else PackedInt32Array()
	for k in h:
		var y := row_order[k] if interlaced else k
		for x in w:
			var idx := indices[k * w + x]
			if idx == transparent_index or idx >= palette.size():
				continue
			canvas.set_pixel(left + x, top + y, palette[idx])


static func _interlace_row_order(h: int) -> PackedInt32Array:
	var order := PackedInt32Array()
	for y in range(0, h, 8):
		order.append(y)
	for y in range(4, h, 8):
		order.append(y)
	for y in range(2, h, 4):
		order.append(y)
	for y in range(1, h, 2):
		order.append(y)
	return order


## Classic GIF variable-width LZW decompression ("early change" variant).
static func _lzw_decode(data: PackedByteArray, min_code_size: int, expected_pixel_count: int) -> PackedByteArray:
	var clear_code := 1 << min_code_size
	var end_code := clear_code + 1

	var table: Array[PackedByteArray] = []
	for i in clear_code:
		table.append(PackedByteArray([i]))
	table.append(PackedByteArray())  # clear_code slot, unused
	table.append(PackedByteArray())  # end_code slot, unused

	var code_size := min_code_size + 1
	var next_code := end_code + 1

	var output := PackedByteArray()
	var bit_buffer := 0
	var bit_count := 0
	var byte_pos := 0
	var prev_entry := PackedByteArray()

	while output.size() < expected_pixel_count:
		while bit_count < code_size and byte_pos < data.size():
			bit_buffer |= data[byte_pos] << bit_count
			bit_count += 8
			byte_pos += 1
		if bit_count < code_size:
			break  # ran out of data before the expected pixel count

		var code := bit_buffer & ((1 << code_size) - 1)
		bit_buffer >>= code_size
		bit_count -= code_size

		if code == clear_code:
			table = []
			for i in clear_code:
				table.append(PackedByteArray([i]))
			table.append(PackedByteArray())
			table.append(PackedByteArray())
			code_size = min_code_size + 1
			next_code = end_code + 1
			prev_entry = PackedByteArray()
			continue
		if code == end_code:
			break

		var entry: PackedByteArray
		if code < table.size():
			entry = table[code]
		elif code == next_code and not prev_entry.is_empty():
			entry = prev_entry.duplicate()
			entry.append(prev_entry[0])
		else:
			break  # invalid code — corrupt stream

		output.append_array(entry)

		if not prev_entry.is_empty() and next_code < 4096:
			var new_entry := prev_entry.duplicate()
			new_entry.append(entry[0])
			table.append(new_entry)
			next_code += 1
			if next_code == (1 << code_size) and code_size < 12:
				code_size += 1

		prev_entry = entry

	return output


class _ByteReader:
	var data: PackedByteArray
	var pos: int = 0

	func _init(bytes: PackedByteArray) -> void:
		data = bytes

	func has_more() -> bool:
		return pos < data.size()

	func read_u8() -> int:
		var v := data[pos]
		pos += 1
		return v

	func read_u16() -> int:
		var v := data[pos] | (data[pos + 1] << 8)
		pos += 2
		return v

	func read_string(n: int) -> String:
		var s := ""
		for i in n:
			s += char(data[pos + i])
		pos += n
		return s

	func read_sub_blocks() -> PackedByteArray:
		var out := PackedByteArray()
		while true:
			var size := read_u8()
			if size == 0:
				break
			out.append_array(data.slice(pos, pos + size))
			pos += size
		return out
