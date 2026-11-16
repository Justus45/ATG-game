extends Node2D
## Kaupan ja pankin sisätilan piirtonäkymän yhteinen pohja (ServiceInterior.gd:n ShopView ja BankView).
## Omassa tiedostossaan, koska Godotin jäsennin ei aina löydä sisäluokasta perittyä sisäluokkaa
## ("Could not find external parser for class ::RoomView").

const CS := preload("res://scripts/core/CharSprites.gd")
const W := 320.0
const H := 192.0
var room: Node2D = null
var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	if room and room.get("inside"):
		queue_redraw()

func solids() -> Array:
	return []

func spots() -> Array:
	return []

func _text(pos: Vector2, txt: String, width: float, fs: int, col: Color, outline := Color(0, 0, 0, 0.85)) -> void:
	var font := ThemeDB.fallback_font
	TextFit.draw_outline(self, font, pos, txt, width, fs, 3, outline)
	TextFit.draw(self, font, pos, txt, width, fs, col)

## NPC-hahmo jalkojen kohdalle (räpsyttää silmiään)
func _char(feet: Vector2, tex: Texture2D, id: int) -> void:
	if tex == null:
		return
	var t := tex
	if fmod(_t + id * 1.31, 3.7 + id * 0.4) < 0.12:
		var b := CS.blink(tex)
		if b:
			t = b
	var breath := 1.0 + 0.04 * maxf(sin(_t * 0.8 + id * 2.0), 0.0)
	var sz := tex.get_size()
	draw_set_transform(feet + Vector2(0, -0.5), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 5.0, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_texture_rect(t, Rect2(feet - Vector2(sz.x * 0.5, sz.y * breath), Vector2(sz.x, sz.y * breath)), false)

func _door(label: String) -> void:
	var d := Rect2(W * 0.5 - 12.0, H - 16.0, 24.0, 16.0)
	draw_rect(d, Color(0.55, 0.75, 0.85, 0.75))
	draw_rect(d, Color(0.3, 0.32, 0.36), false, 2.0)
	draw_line(Vector2(W * 0.5, d.position.y), Vector2(W * 0.5, d.end.y), Color(0.3, 0.32, 0.36), 1.0)
	draw_rect(Rect2(W * 0.5 - 14.0, H - 28.0, 28.0, 10.0), Color(0.25, 0.25, 0.28))   # ovimatto
	_text(Vector2(W * 0.5 - 30.0, H - 31.0), label, 60.0, 7, Color.WHITE)
