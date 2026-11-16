class_name TextFit
extends RefCounted
## Keskitetty teksti, joka mahtuu annettuun leveyteen kokonaan: jos teksti on liian
## leveä, fonttikokoa pienennetään (teksti ei koskaan katkea kesken sanan).
## Käyttö _draw():ssa: TextFit.draw(self, font, pos, "TEKSTI", leveys, koko, väri)

const MIN_SIZE := 4


static func fit_size(font: Font, text: String, width: float, fs: int) -> int:
	if width <= 0.0 or font == null:
		return fs
	var s := fs
	while s > MIN_SIZE and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > width:
		s -= 1
	return s


static func draw(ci: CanvasItem, font: Font, pos: Vector2, text: String, width: Variant, fs: Variant, col: Color = Color(1, 1, 1)) -> void:
	var w := float(width)
	var s := fit_size(font, text, w, int(fs))
	var x := pos.x
	if w > 0.0:
		x += (w - font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x) * 0.5
	ci.draw_string(font, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, s, col)


static func draw_outline(ci: CanvasItem, font: Font, pos: Vector2, text: String, width: Variant, fs: Variant, size: Variant = 1, col: Color = Color(1, 1, 1)) -> void:
	var w := float(width)
	var s := fit_size(font, text, w, int(fs))
	var x := pos.x
	if w > 0.0:
		x += (w - font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x) * 0.5
	ci.draw_string_outline(font, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, s, int(size), col)
