extends Control
## Päivä, kello ja sää minikartan yläpuolella. Kaikki piirretään (_draw), ei labeleita.
##   vasen   vuorokausikiekko: taivaan väri kellonajan mukaan, aurinko/kuu kiertää
##   keski   viikonpäivä + päivä, kellonaika ja vuorokaudenaika
##   oikea   animoitu sääikoni ja sään nimi
## Koko on kiinteä (W x H); HUD asettaa paikan oikeaan yläkulmaan.

const W := 240.0
const H := 52.0
const GOLD := Color(1.0, 0.82, 0.3)
const TEXT := Color(0.95, 0.95, 1.0)
const DIM := Color(0.65, 0.68, 0.78)

const WEEKDAY_FULL := {"Ma": "Maanantai", "Ti": "Tiistai", "Ke": "Keskiviikko", "To": "Torstai",
	"Pe": "Perjantai", "La": "Lauantai", "Su": "Sunnuntai"}

var _t := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.7)
	bg.border_color = Color(1, 1, 1, 0.6)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(12)
	draw_style_box(bg, r)
	_draw_dial(Vector2(27.0, size.y * 0.5), 19.0)
	_draw_texts(Rect2(54.0, 0.0, size.x - 54.0 - 64.0, size.y))
	_draw_weather(Rect2(size.x - 62.0, 0.0, 56.0, size.y))


# ----------------------------------------------------------------------------
#  VUOROKAUSIKIEKKO
# ----------------------------------------------------------------------------
func _sky_color() -> Color:
	var h := Game.minutes / 60.0
	var night := Color(0.06, 0.07, 0.2)
	var day := Color(0.38, 0.62, 0.95)
	var dusk := Color(0.95, 0.5, 0.3)
	var d := Game.darkness()
	var c := day.lerp(night, d)
	# aamu- ja iltarusko
	var glow := maxf(1.0 - absf(h - 6.0) / 1.2, 0.0) + maxf(1.0 - absf(h - 19.5) / 1.5, 0.0)
	return c.lerp(dusk, clampf(glow, 0.0, 1.0) * 0.7)


func _draw_dial(c: Vector2, rad: float) -> void:
	var sky := _sky_color()
	draw_circle(c, rad + 2.0, Color(0, 0, 0, 0.6))
	draw_circle(c, rad, sky)
	var d := Game.darkness()
	# tähdet yöllä
	if d > 0.3:
		for k in 6:
			var p := c + Vector2(-10 + k * 4.0, -12 + (k * 7) % 9).limit_length(rad - 4.0)
			draw_rect(Rect2(p, Vector2(1.5, 1.5)), Color(1, 1, 1, (d - 0.3) * (0.5 + 0.5 * sin(_t * 2.0 + k))))
	# aurinko ja kuu kiertävät: keskipäivällä aurinko ylhäällä, keskiyöllä kuu ylhäällä
	var a := Game.minutes / 1440.0 * TAU
	var sun := c + Vector2(-sin(a), cos(a)) * rad * 0.58
	var moon := c - Vector2(-sin(a), cos(a)) * rad * 0.58
	if sun.y < c.y + 6.0:
		for k in 8:
			var dir := Vector2.from_angle(k * TAU / 8.0 + _t * 0.4)
			draw_line(sun + dir * 6.5, sun + dir * 8.5, Color(1.0, 0.9, 0.4, 0.9), 1.5)
		draw_circle(sun, 5.0, Color(1.0, 0.86, 0.3))
	if moon.y < c.y + 6.0:
		draw_circle(moon, 5.0, Color(0.95, 0.95, 0.85))
		draw_circle(moon + Vector2(2.2, -1.5), 4.2, sky)
	# horisontti: alaosa maata (piirretään kiekon päälle, peittää laskeneet taivaankappaleet)
	var ground := PackedVector2Array()
	var steps := 16
	var hy := c.y + rad * 0.3
	var a0 := asin((hy - c.y) / rad)
	for i in steps + 1:
		var ang := a0 + (PI - 2.0 * a0) * float(i) / float(steps)
		ground.append(c + Vector2(cos(ang), sin(ang)) * rad)
	draw_colored_polygon(ground, Color(0.1, 0.16, 0.12).lerp(Color(0.03, 0.04, 0.05), d))
	# talojen siluetit horisontissa
	for k in 5:
		var bw := 4.0
		var bh := 3.0 + float((k * 5) % 7)
		draw_rect(Rect2(c.x - 11.0 + k * 4.5, hy - bh, bw, bh), Color(0.05, 0.05, 0.08).lerp(Color(0.02, 0.02, 0.03), d))
		if d > 0.4:
			draw_rect(Rect2(c.x - 10.0 + k * 4.5, hy - bh + 1.5, 1.2, 1.2), Color(1.0, 0.85, 0.4, d))
	draw_arc(c, rad, 0.0, TAU, 32, Color(1, 1, 1, 0.5), 1.5)


# ----------------------------------------------------------------------------
#  TEKSTIT
# ----------------------------------------------------------------------------
func _draw_texts(r: Rect2) -> void:
	# pitkä viikonpäivä, jos mahtuu; muuten lyhenne
	var top := "%s · päivä %d" % [str(WEEKDAY_FULL.get(Game.weekday(), Game.weekday())), Game.day]
	if _font.get_string_size(top, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x > r.size.x:
		top = "%s · päivä %d" % [Game.weekday(), Game.day]
	draw_string(_font, Vector2(r.position.x, 19.0), top, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 11, GOLD)
	var clock := Game.clock_text()
	draw_string(_font, Vector2(r.position.x, 42.0), clock, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 22, TEXT)
	var cw := _font.get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var per := Game.period()
	if cw + 6.0 + _font.get_string_size(per, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= r.size.x:
		draw_string(_font, Vector2(r.position.x + cw + 6.0, 42.0), per, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)


# ----------------------------------------------------------------------------
#  SÄÄ
# ----------------------------------------------------------------------------
func _draw_weather(r: Rect2) -> void:
	var c := Vector2(r.get_center().x, 19.0)
	var w := Game.weather
	var night := Game.darkness() > 0.5
	match w:
		"clear":
			if night:
				# kuunsirppi paksuna kaarena
				draw_arc(c + Vector2(1.5, 0.0), 7.0, PI * 0.5, PI * 1.5, 16, Color(0.95, 0.95, 0.85), 5.0)
			else:
				for k in 8:
					var dir := Vector2.from_angle(k * TAU / 8.0 + _t * 0.5)
					draw_line(c + dir * 10.0, c + dir * 13.5, Color(1.0, 0.85, 0.35), 2.0)
				draw_circle(c, 7.5, Color(1.0, 0.85, 0.3))
		"cloudy":
			_cloud(c + Vector2(sin(_t * 0.6) * 1.5, 0.0), Color(0.82, 0.84, 0.9))
		"fog":
			for k in 3:
				var y := c.y - 7.0 + k * 7.0
				var off := sin(_t * 1.2 + k) * 3.0
				draw_line(Vector2(c.x - 15.0 + off, y), Vector2(c.x + 15.0 + off, y), Color(0.8, 0.82, 0.88, 0.85), 3.0)
		"rain":
			_cloud(c + Vector2(0, -4), Color(0.6, 0.64, 0.74))
			for k in 4:
				var ph := fmod(_t * 1.6 + k * 0.27, 1.0)
				var x := c.x - 9.0 + k * 6.0
				var y := c.y + 4.0 + ph * 10.0
				draw_line(Vector2(x, y), Vector2(x - 1.5, y + 4.0), Color(0.5, 0.7, 1.0, 1.0 - ph), 1.5)
		"storm":
			_cloud(c + Vector2(0, -4), Color(0.38, 0.4, 0.5))
			var flash := fmod(_t, 2.3) < 0.18
			var bolt := PackedVector2Array([c + Vector2(1, 1), c + Vector2(-4, 9), c + Vector2(0, 9), c + Vector2(-3, 16),
				c + Vector2(5, 6), c + Vector2(1, 6), c + Vector2(4, 1)])
			draw_colored_polygon(bolt, Color(1.0, 0.95, 0.4) if flash else Color(0.95, 0.8, 0.25, 0.75))
		"snow":
			_cloud(c + Vector2(0, -4), Color(0.85, 0.88, 0.95))
			for k in 4:
				var ph := fmod(_t * 0.6 + k * 0.29, 1.0)
				var p := Vector2(c.x - 9.0 + k * 6.0 + sin(_t * 2.0 + k) * 1.5, c.y + 4.0 + ph * 10.0)
				draw_circle(p, 1.6, Color(1, 1, 1, 1.0 - ph * 0.7))
	var wn := Game.weather_name()
	var wfs := 10
	while wfs > 7 and _font.get_string_size(wn, HORIZONTAL_ALIGNMENT_LEFT, -1, wfs).x > r.size.x:
		wfs -= 1
	TextFit.draw(self, _font, Vector2(r.position.x, 46.0), wn, r.size.x, wfs, DIM)


func _cloud(c: Vector2, col: Color) -> void:
	draw_circle(c + Vector2(-6, 2), 6.0, col)
	draw_circle(c + Vector2(1, -2), 8.0, col)
	draw_circle(c + Vector2(8, 2), 5.5, col)
	draw_rect(Rect2(c.x - 12.0, c.y + 1.0, 25.0, 6.5), col)
