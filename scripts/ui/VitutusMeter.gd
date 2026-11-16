extends Control
## Tarvepalkit ruudun vasemmassa yläkulmassa rahojen alla: NÄLKÄ, VÄSYMYS ja VITUTUS.
## Jokaisella oma kuvake, palkki (vihreä -> keltainen -> punainen) ja prosentti.
## Kriittinen tarve (yli 85 %) vilkkuu, täysi vitutus tärisee. Lukee arvot suoraan Gamesta.

const W := 210.0
const ROW_H := 22.0
const ROWS := [["hunger", "NÄLKÄ"], ["fatigue", "VÄSYMYS"], ["vitutus", "VITUTUS"]]
var _t := 0.0
var _shown := {"hunger": 0.0, "fatigue": 0.0, "vitutus": 0.0}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _value(id: String) -> float:
	match id:
		"hunger":
			return Game.hunger
		"fatigue":
			return Game.fatigue
	return Game.vitutus


func _process(delta: float) -> void:
	_t += delta
	for r: Array in ROWS:
		var id := str(r[0])
		_shown[id] = move_toward(float(_shown[id]), _value(id), delta * 60.0)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	bg.set_corner_radius_all(8)
	draw_style_box(bg, Rect2(Vector2.ZERO, Vector2(W, ROW_H * ROWS.size() + 6.0)))
	for i in ROWS.size():
		var id := str((ROWS[i] as Array)[0])
		var title := str((ROWS[i] as Array)[1])
		var v := float(_shown[id])
		var k := clampf(v / 100.0, 0.0, 1.0)
		var y := 3.0 + i * ROW_H
		var shake := Vector2.ZERO
		if id == "vitutus" and v >= 90.0:
			shake = Vector2(sin(_t * 47.0), cos(_t * 39.0)) * 1.0
		draw_set_transform(shake, 0.0, Vector2.ONE)
		var c := Vector2(14.0, y + ROW_H * 0.5)
		_icon(id, c, k)
		var col := Color(0.3, 0.85, 0.35).lerp(Color(1.0, 0.8, 0.2), clampf(k * 2.0, 0.0, 1.0)).lerp(Color(0.95, 0.15, 0.15), clampf(k * 2.0 - 1.0, 0.0, 1.0))
		var blink := v >= 85.0 and fmod(_t, 0.8) < 0.4
		var bar := Rect2(30.0, y + 12.0, W - 40.0, 6.0)
		draw_rect(bar, Color(0.15, 0.15, 0.18))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), col.lightened(0.25) if blink else col)
		draw_rect(bar, Color(1, 1, 1, 0.45), false, 1.0)
		var label := title
		if id == "vitutus":
			if k >= 1.0:
				label = "PINNA PALAA!"
			elif k >= 0.8:
				label = "VITUTTAA SIKANA"
			elif k >= 0.5:
				label = "VITUTTAA"
		elif k >= 0.85:
			label = title + "!"
		var tc := Color.WHITE if k < 0.8 else Color(1.0, 0.65, 0.6)
		draw_string_outline(font, Vector2(30.0, y + 10.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0, 0, 0, 0.9))
		draw_string(font, Vector2(30.0, y + 10.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tc)
		var pct := "%d %%" % roundi(v)
		draw_string_outline(font, Vector2(0.0, y + 10.0), pct, HORIZONTAL_ALIGNMENT_RIGHT, W - 10.0, 10, 3, Color(0, 0, 0, 0.9))
		draw_string(font, Vector2(0.0, y + 10.0), pct, HORIZONTAL_ALIGNMENT_RIGHT, W - 10.0, 10, Color.WHITE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _icon(id: String, c: Vector2, k: float) -> void:
	match id:
		"hunger":
			# lautanen, haarukka ja veitsi
			draw_circle(c, 7.0, Color(0.92, 0.92, 0.9))
			draw_circle(c, 4.5, Color(0.8, 0.8, 0.78))
			draw_line(c + Vector2(-9, -6), c + Vector2(-9, 7), Color(0.75, 0.77, 0.8), 1.5)
			draw_line(c + Vector2(-10.5, -6), c + Vector2(-10.5, -2), Color(0.75, 0.77, 0.8), 1.0)
			draw_line(c + Vector2(-7.5, -6), c + Vector2(-7.5, -2), Color(0.75, 0.77, 0.8), 1.0)
			draw_line(c + Vector2(9, -6), c + Vector2(9, 7), Color(0.75, 0.77, 0.8), 1.5)
		"fatigue":
			# kuu ja zzz
			draw_circle(c + Vector2(-1, 1), 6.5, Color(0.98, 0.88, 0.45))
			draw_circle(c + Vector2(2, -1), 5.5, Color(0, 0, 0, 0.0))
			draw_circle(c + Vector2(2.5, -1.5), 5.0, Color(0.12, 0.12, 0.18))
			var font := ThemeDB.fallback_font
			draw_string(font, c + Vector2(3, -2), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.85, 0.9, 1.0))
		_:
			# vihaiset kasvot
			var face := Color(0.98, 0.85, 0.35).lerp(Color(0.95, 0.25, 0.2), k)
			draw_circle(c, 8.0, face)
			draw_arc(c, 8.0, 0.0, TAU, 18, Color(0, 0, 0, 0.6), 1.2)
			var brow := lerpf(0.0, 3.0, k)
			draw_line(c + Vector2(-5, -3 - brow * 0.3), c + Vector2(-1.5, -2.5 + brow * 0.5), Color(0.1, 0.05, 0.05), 1.3)
			draw_line(c + Vector2(5, -3 - brow * 0.3), c + Vector2(1.5, -2.5 + brow * 0.5), Color(0.1, 0.05, 0.05), 1.3)
			draw_circle(c + Vector2(-2.8, 0), 1.0, Color(0.1, 0.05, 0.05))
			draw_circle(c + Vector2(2.8, 0), 1.0, Color(0.1, 0.05, 0.05))
			var my := c.y + 4.0
			var curve := lerpf(-1.6, 2.0, k)
			draw_polyline(PackedVector2Array([Vector2(c.x - 3, my + curve * 0.2), Vector2(c.x, my - curve), Vector2(c.x + 3, my + curve * 0.2)]), Color(0.1, 0.05, 0.05), 1.3)
