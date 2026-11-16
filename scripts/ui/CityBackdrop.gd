extends RefCounted
## Animoitu yökaupunki: siluetit, ikkunavalot, kuu, tähdet, sade, autot ja ATG-neonkyltti.
## Yhteinen tausta alkuintrolle (Intro.gd) ja aloitusvalikolle (MainMenu.gd).
## Käyttö: var bd := CityBackdrop.new(); ... _draw():ssa bd.draw(self, size, aika)

const GOLD := Color(1.0, 0.82, 0.3)
const NEON := Color(1.0, 0.3, 0.55)

var font: Font = ThemeDB.fallback_font
## Neonin syttymisen viive (s): 0 = syttyy heti
var sign_delay := 1.0
## Neonkyltin (ja alaotsikkokyltin) alareuna korkeintaan tässä kohdassa näytön korkeudesta
var sign_max_bottom := 1.0
var _far: Array = []
var _near: Array = []
var _stars: Array = []
var _drops: Array = []
var _sign_idx := -1


func _init() -> void:
	_build_city()


func _build_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var x := -0.05
	while x < 1.25:
		var w := rng.randf_range(0.035, 0.08)
		_far.append([x, w, rng.randf_range(0.16, 0.4)])
		x += w + rng.randf_range(0.0, 0.01)
	x = -0.05
	while x < 1.3:
		var w := rng.randf_range(0.06, 0.12)
		var h := rng.randf_range(0.22, 0.52)
		var wins: Array = []
		var cols := int(w * 120.0)
		var rows := int(h * 36.0)
		for r in rows:
			for c in cols:
				var roll := rng.randf()
				if roll < 0.32:
					# [sarake, rivi, lämmin?, välkkyvä?]
					wins.append([c, r, rng.randf() < 0.8, rng.randf() < 0.08])
		_near.append([x, w, h, cols, rows, wins, rng.randf() < 0.3])
		x += w + rng.randf_range(0.004, 0.02)
	for i in 90:
		_stars.append([rng.randf(), rng.randf_range(0.0, 0.45), rng.randf_range(0.5, 1.6), rng.randf() * TAU])
	for i in 140:
		_drops.append([rng.randf(), rng.randf(), rng.randf_range(0.7, 1.3)])


func draw(c: CanvasItem, vs: Vector2, t: float) -> void:
	var horizon := vs.y * 0.82
	# taivas: liukuväri ylhäältä horisonttiin
	var top := Color(0.03, 0.03, 0.09)
	var low := Color(0.2, 0.08, 0.22)
	c.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), Vector2(vs.x, horizon), Vector2(0, horizon)]),
		PackedColorArray([top, top, low, low]))
	# tähdet
	for s: Array in _stars:
		var tw := 0.5 + 0.5 * sin(t * float(s[2]) * 2.0 + float(s[3]))
		c.draw_rect(Rect2(float(s[0]) * vs.x, float(s[1]) * vs.y, 1.5, 1.5), Color(1, 1, 1, 0.25 + 0.5 * tw))
	# kuu ja hehku
	var mc := Vector2(vs.x * 0.8, vs.y * 0.17)
	var mr := vs.y * 0.055
	for k in 3:
		c.draw_circle(mc, mr * (1.25 + k * 0.3), Color(1.0, 0.9, 0.7, 0.05))
	c.draw_circle(mc, mr, Color(1.0, 0.95, 0.82))
	c.draw_circle(mc + Vector2(mr * 0.35, -mr * 0.15), mr * 0.85, Color(0.96, 0.9, 0.76))
	# kaukaiset talot (hidas liuku)
	var pan_far := -t * 0.006
	for b: Array in _far:
		var bx := (float(b[0]) + pan_far) * vs.x
		var bh := float(b[2]) * vs.y
		c.draw_rect(Rect2(bx, horizon - bh, float(b[1]) * vs.x, bh), Color(0.11, 0.09, 0.2))
	# lähitalot ikkunoineen
	var pan := -t * 0.014
	var sign_rect := Rect2()
	for i in _near.size():
		var b: Array = _near[i]
		var bx := (float(b[0]) + pan) * vs.x
		var bw := float(b[1]) * vs.x
		var bh := float(b[2]) * vs.y
		var r := Rect2(bx, horizon - bh, bw, bh)
		if r.end.x < 0.0 or r.position.x > vs.x:
			continue
		c.draw_rect(r, Color(0.05, 0.045, 0.09))
		if bool(b[6]):
			# kattolaite + vilkkuva punainen valo
			c.draw_rect(Rect2(r.position.x + bw * 0.3, r.position.y - 8.0, 4.0, 8.0), Color(0.05, 0.045, 0.09))
			var blink := 1.0 if fmod(t + i * 0.37, 1.6) < 0.25 else 0.15
			c.draw_circle(Vector2(r.position.x + bw * 0.3 + 2.0, r.position.y - 9.0), 2.0, Color(1, 0.2, 0.2, blink))
		var cw := bw / float(maxi(int(b[3]), 1))
		var rh := bh / float(maxi(int(b[4]), 1))
		for wdat: Array in b[5]:
			var on := true
			if bool(wdat[3]):
				on = fmod(t * 1.3 + float(wdat[0]) * 0.7 + float(wdat[1]), 3.0) > 0.6
			if not on:
				continue
			var wc := Color(1.0, 0.82, 0.45, 0.85) if bool(wdat[2]) else Color(0.6, 0.8, 1.0, 0.7)
			c.draw_rect(Rect2(r.position.x + float(wdat[0]) * cw + cw * 0.25, r.position.y + float(wdat[1]) * rh + rh * 0.3,
				cw * 0.5, rh * 0.45), wc)
		# neonkyltti: valitaan kerran talo, joka on alussa näytön keskellä
		if _sign_idx < 0 and r.get_center().x > vs.x * 0.42:
			_sign_idx = i
		if i == _sign_idx:
			sign_rect = Rect2(r.get_center().x - vs.x * 0.11, r.position.y - vs.y * 0.17, vs.x * 0.22, vs.y * 0.13)
	# katu
	c.draw_rect(Rect2(0, horizon, vs.x, vs.y - horizon), Color(0.06, 0.06, 0.08))
	c.draw_rect(Rect2(0, horizon, vs.x, 3.0), Color(0.35, 0.3, 0.4))
	var lane_y := horizon + (vs.y - horizon) * 0.5
	var dash := 40.0
	var off := fmod(t * 30.0, dash * 2.0)
	var dx := -off
	while dx < vs.x:
		c.draw_rect(Rect2(dx, lane_y - 1.5, dash, 3.0), Color(0.75, 0.72, 0.5, 0.5))
		dx += dash * 2.0
	_draw_car(c, vs, fmod(t * 0.16 + 0.1, 1.4) - 0.2, horizon + (vs.y - horizon) * 0.3, 1.0, Color(0.75, 0.2, 0.2))
	_draw_car(c, vs, 1.2 - fmod(t * 0.22 + 0.5, 1.4), horizon + (vs.y - horizon) * 0.72, -1.0, Color(0.25, 0.45, 0.8))
	# sade
	var rain_c := Color(0.7, 0.75, 0.95, 0.22)
	for d: Array in _drops:
		var sp := float(d[2])
		var px := fmod(float(d[0]) * vs.x + t * 60.0 * sp, vs.x + 40.0) - 20.0
		var py := fmod(float(d[1]) * vs.y + t * 520.0 * sp, vs.y)
		c.draw_line(Vector2(px, py), Vector2(px - 3.0, py + 12.0 * sp), rain_c, 1.0)
	# ATG-neon: syttyy räpsien, välillä välähtää
	if sign_rect.size.x > 0.0:
		# alaotsikkokyltti vie n. 0.07 näytön korkeutta neonin alapuolelta
		var max_top := vs.y * sign_max_bottom - sign_rect.size.y - vs.y * 0.07
		if sign_rect.position.y > max_top:
			sign_rect.position.y = maxf(max_top, 8.0)
		_draw_neon(c, sign_rect, t)


func _draw_car(c: CanvasItem, vs: Vector2, u: float, y: float, dir: float, body: Color) -> void:
	var w := vs.x * 0.06
	var h := w * 0.32
	var x := u * vs.x
	var front := x + (w if dir > 0.0 else 0.0)
	# valokeila
	var beam := PackedVector2Array([Vector2(front, y - h * 0.35), Vector2(front + dir * w * 2.2, y - h * 1.0), Vector2(front + dir * w * 2.2, y + h * 0.6)])
	c.draw_colored_polygon(beam, Color(1.0, 0.95, 0.7, 0.12))
	c.draw_rect(Rect2(x, y - h, w, h), body.darkened(0.35))
	c.draw_rect(Rect2(x + w * 0.2, y - h * 1.55, w * 0.55, h * 0.6), body.darkened(0.5))
	c.draw_circle(Vector2(front, y - h * 0.4), 2.5, Color(1.0, 0.95, 0.75))
	var back := x + (0.0 if dir > 0.0 else w)
	c.draw_circle(Vector2(back, y - h * 0.4), 2.0, Color(1.0, 0.15, 0.15))


func _draw_neon(c: CanvasItem, r: Rect2, t: float) -> void:
	# syttymisjärjestys: välähdyksiä, sitten päällä; satunnainen nykäys myöhemmin
	t = t - sign_delay + 1.0
	var on := 0.0
	if t > 1.0:
		on = 1.0
		if t < 1.9:
			on = 1.0 if fmod(t * 7.0, 1.0) > 0.45 else 0.1
		elif fmod(t, 3.1) < 0.08:
			on = 0.25
	# kyltin tausta ja kannattimet
	c.draw_rect(Rect2(r.position.x + r.size.x * 0.2, r.end.y, 3.0, r.size.y * 0.35), Color(0.12, 0.1, 0.16))
	c.draw_rect(Rect2(r.end.x - r.size.x * 0.2, r.end.y, 3.0, r.size.y * 0.35), Color(0.12, 0.1, 0.16))
	c.draw_rect(r, Color(0.07, 0.05, 0.1, 0.95))
	c.draw_rect(r, Color(NEON, 0.25 + 0.65 * on), false, 2.0)
	var fs := clampi(int(r.size.y * 0.78), 24, 110)
	var base := Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.36)
	# hehku: sama teksti useaan kertaan läpikuultavana ympärille
	if on > 0.5:
		for k in 8:
			var o := Vector2.from_angle(k * TAU / 8.0) * 3.0
			c.draw_string(font, base + o, "ATG", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color(NEON, 0.12))
		c.draw_circle(r.get_center(), r.size.x * 0.55, Color(NEON, 0.05))
	c.draw_string(font, base, "ATG", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs,
		Color(1.0, 0.75, 0.85).lerp(Color(0.3, 0.12, 0.2), 1.0 - on))
