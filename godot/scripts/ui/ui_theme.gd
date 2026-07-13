class_name UITheme
## Shared HUD styling (Phase 7) so the exploration + combat UIs read as one system:
## dark rounded panels, one accent, consistent type + status colours.

const BG        := Color(0.07, 0.08, 0.11, 0.90)   # panel background
const BG_SOLID  := Color(0.07, 0.08, 0.11, 1.0)
const BORDER    := Color(0.30, 0.34, 0.44, 0.85)
const ACCENT    := Color(1.00, 0.82, 0.35)          # gold — highlights, XP
const TEXT      := Color(0.90, 0.92, 0.96)
const TEXT_DIM  := Color(0.62, 0.66, 0.74)
const GOOD      := Color(0.45, 0.85, 0.45)          # HP high, positive
const WARN      := Color(0.95, 0.75, 0.35)
const BAD       := Color(0.90, 0.35, 0.35)          # HP low, damage

const FONT_TITLE := 22
const FONT_BODY  := 15
const FONT_SMALL := 12


## Rounded, semi-opaque dark panel with a subtle border and inner padding.
static func panel_style(bg: Color = BG, pad: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.set_border_width_all(1)
	s.border_color = BORDER
	s.set_content_margin_all(pad)
	return s


static func make_panel(pad: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(BG, pad))
	return p


static func title(text: String, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_TITLE)
	l.add_theme_color_override("font_color", color)
	return l


static func label(text: String, size: int = FONT_BODY, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## HP colour ramp: green → amber → red as the bar drains.
static func hp_color(fraction: float) -> Color:
	if fraction > 0.5:
		return GOOD
	if fraction > 0.25:
		return WARN
	return BAD


## A styled HP/resource bar. Returns the ProgressBar (caller sets max/value).
static func make_bar(fill: Color, height: int = 14) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.14, 0.15, 0.18)
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	var f := StyleBoxFlat.new()
	f.bg_color = fill
	f.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", f)
	return bar


static func set_bar(bar: ProgressBar, value: int, max_value: int, recolor := true) -> void:
	bar.max_value = maxi(1, max_value)
	bar.value = clampi(value, 0, max_value)
	if recolor:
		var f: StyleBoxFlat = bar.get_theme_stylebox("fill")
		if f != null:
			f.bg_color = hp_color(float(value) / float(maxi(1, max_value)))
