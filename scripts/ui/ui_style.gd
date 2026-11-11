class_name UiStyle
## The look of menu buttons and panels, in one place: dark worn plates with
## a brass edge, teal for the picked one. Big type, strong contrast.

const CREAM := Color(0.95, 0.92, 0.85)
const GOLD := Color(0.92, 0.84, 0.66)
const DIM := Color(0.75, 0.72, 0.65)
const PLATE := Color(0.13, 0.115, 0.10)
const PLATE_HOVER := Color(0.20, 0.175, 0.145)
const EDGE := Color(0.33, 0.29, 0.23)


static func _box(fill: Color, edge: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	return sb


## Styles a button and gives it the click and hover sounds. `primary` is
## the one main action on a screen (brass fill). Toggle buttons show the
## picked state in teal.
static func button(b: Button, font_size := 24, primary := false) -> void:
	b.add_theme_font_size_override("font_size", font_size)
	if primary:
		b.add_theme_stylebox_override("normal", _box(Color(0.42, 0.32, 0.16), Palette.BRASS, 2))
		b.add_theme_stylebox_override("hover", _box(Color(0.55, 0.42, 0.20), GOLD, 2))
		b.add_theme_stylebox_override("pressed", _box(Color(0.34, 0.26, 0.13), GOLD, 2))
		b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), CREAM, 2))
		b.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
	else:
		b.add_theme_stylebox_override("normal", _box(PLATE, EDGE, 1))
		b.add_theme_stylebox_override("hover", _box(PLATE_HOVER, Palette.BRASS, 2))
		b.add_theme_stylebox_override("pressed", _box(Color(0.07, 0.17, 0.17), Palette.TEAL, 2))
		b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), CREAM, 2))
		b.add_theme_color_override("font_color", CREAM)
		b.add_theme_color_override("font_pressed_color", Color(0.75, 1.0, 0.98))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color", Color(0.75, 1.0, 0.98))
	Sounds.wire(b)


static func panel(fill := Color(0.10, 0.09, 0.08, 0.92), margin := 20) -> StyleBoxFlat:
	var sb := _box(fill, Color(Palette.BRASS, 0.7), 1)
	sb.set_content_margin_all(margin)
	return sb


static func label(text: String, size: int, col := CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l
