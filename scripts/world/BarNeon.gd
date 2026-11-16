extends Node2D
## Baarin neonkyltti: baarin nimi neonputkina.
##  - Piirretään omalla CanvasLayerillaan (Bar.gd), joten yön pimeys ei himmennä sitä:
##    pimeällä kyltti hohtaa ja valaisee ympäristöään (PointLight2D), päivällä putket näkyvät
##    himmeämpinä.
##  - Välkkyy välillä: koko kyltti räpsähtää, yksittäinen kirjain pätkii, tai jokin
##    kirjain sammuu hetkeksi kokonaan.
##  - Oman baarin Neonkyltti-päivitykset: 1 = kirkkaampi + AUKI-valo, 2 = kaksivärinen +
##    reunavalot, 3 = jättikyltti + valonheittimet. Valonauha julkisivussa ja seinälamput
##    hohtavat myös täältä.
## Koordinaatit ovat maailmankoordinaatteja (CanvasLayer.follow_viewport_enabled).

# --- SÄÄDÄ NÄITÄ ---
const PINK := Color(1.0, 0.22, 0.68)
const CYAN := Color(0.25, 0.95, 1.0)
const WARM := Color(1.0, 0.8, 0.45)
const GREEN := Color(0.3, 1.0, 0.45)
const RED := Color(1.0, 0.2, 0.15)
const FLICKER_MIN := 3.0     ## välkähdysten väli (s), satunnainen väliltä
const FLICKER_MAX := 11.0
const DRAW_RANGE := 900.0    ## kauempana kamerasta ei piirretä

var sign_rect := Rect2()
var roof := Rect2()
var door_center := Vector2.ZERO
var bar: Node = null

var _t := 0.0
var _next_event := 4.0
var _blink := []             # koko kyltin räpsäytys: [[kesto, päällä?], ...]
var _blink_t := 0.0
var _bad_letter := -1        # pätkivä kirjain
var _bad_t := 0.0
var _bad_on := true
var _bad_toggle := 0.0
var _dead_letter := -1       # kokonaan sammunut kirjain
var _dead_t := 0.0
var _hum := 1.0
var _light: PointLight2D = null
var _visible_now := false


## Kyltin valo maailmaan (valot vaikuttavat vain pääkerrokseen, siksi eri vanhempi).
func attach_light(world_parent: Node) -> void:
	_light = PointLight2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_light.texture = tex
	_light.texture_scale = 1.4
	_light.color = PINK
	_light.energy = 0.0
	world_parent.add_child(_light)
	_light.global_position = sign_rect.get_center() + Vector2(0.0, 18.0)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	_visible_now = cam == null or cam.global_position.distance_to(sign_rect.get_center()) < DRAW_RANGE
	_t += delta
	_update_flicker(delta)
	var night := Game.darkness()
	if _light:
		_light.enabled = _visible_now and night > 0.05
		_light.energy = night * 0.85 * _sign_level_on()
		_light.color = Game.bar_neon_color()
		_light.texture_scale = 1.4 + 0.25 * _sign_level()
	if _visible_now:
		queue_redraw()


func _owned() -> bool:
	return Game.owns_bar


func _sign_level() -> int:
	if not _owned() or bar == null or bar.get("biz") == null:
		return 0
	return int(bar.biz.level("sign"))


func _name() -> String:
	return Game.bar_name()


## Koko kyltin kirkkaus tällä hetkellä (0 = pimeä, 1 = täysi)
func _sign_level_on() -> float:
	if not _blink.is_empty():
		return 1.0 if bool((_blink[0] as Array)[1]) else 0.05
	return _hum


# ----------------------------------------------------------------------------
#  VÄLKYNTÄ
# ----------------------------------------------------------------------------
func _update_flicker(delta: float) -> void:
	# pieni jatkuva surina
	_hum = clampf(_hum + randf_range(-0.06, 0.06), 0.88, 1.0)
	# koko kyltin räpsäytys
	if not _blink.is_empty():
		_blink_t -= delta
		if _blink_t <= 0.0:
			_blink.pop_front()
			if not _blink.is_empty():
				_blink_t = float((_blink[0] as Array)[0])
	# pätkivä kirjain
	if _bad_letter >= 0:
		_bad_t -= delta
		_bad_toggle -= delta
		if _bad_toggle <= 0.0:
			_bad_on = not _bad_on
			_bad_toggle = randf_range(0.03, 0.14) if not _bad_on else randf_range(0.04, 0.3)
		if _bad_t <= 0.0:
			_bad_letter = -1
			_bad_on = true
	if _dead_letter >= 0:
		_dead_t -= delta
		if _dead_t <= 0.0:
			_dead_letter = -1
	# seuraava välkähdys
	_next_event -= delta
	if _next_event > 0.0:
		return
	_next_event = randf_range(FLICKER_MIN, FLICKER_MAX)
	var n := _name()
	var roll := randf()
	if roll < 0.4:
		# koko kyltti räpsähtää: pois-päälle-pois-päälle
		_blink = [[0.06, false], [0.07, true], [0.12, false], [0.05, true], [randf_range(0.15, 0.4), false], [0.01, true]]
		_blink_t = 0.06
	elif roll < 0.88:
		_bad_letter = _random_letter(n)
		_bad_t = randf_range(0.6, 2.2)
		_bad_toggle = 0.0
	else:
		_dead_letter = _random_letter(n)
		_dead_t = randf_range(4.0, 12.0)


func _random_letter(n: String) -> int:
	var idx := []
	for i in n.length():
		if n[i] != " ":
			idx.append(i)
	return int(idx[randi() % idx.size()]) if not idx.is_empty() else -1


# ----------------------------------------------------------------------------
#  PIIRTO
# ----------------------------------------------------------------------------
func _draw() -> void:
	var night := Game.darkness()
	var lvl := _sign_level()
	var on := _sign_level_on()
	# hehkun voimakkuus: päivällä vain putket, yöllä leveä halo
	var glow := lerpf(0.3, 1.0, night) * on
	_draw_spotlights(lvl, night, on)
	_draw_name(lvl, glow, on, night)
	_draw_frame_bulbs(lvl, glow, on)
	_draw_open_sign(lvl, night)
	_draw_festoon(night)
	_draw_sconces(night)
	_draw_terrace_lights(night)


func _font_size_for(font: Font, text: String, max_w: float, max_size: int) -> int:
	var fs := max_size
	while fs > 6 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 1
	return fs


func _draw_name(lvl: int, glow: float, on: float, night: float) -> void:
	var font := ThemeDB.fallback_font
	var text := _name()
	var r := sign_rect
	var fs := _font_size_for(font, text, r.size.x - 8.0, 12 + (2 if lvl >= 3 else 0))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x0 := r.get_center().x - w * 0.5
	var base_y := r.get_center().y + fs * 0.36
	# Kaksivärinen kyltti: ensimmäinen sana pinkki, loput syaani
	var split := text.find(" ") if lvl >= 2 else -1
	var bright := 0.85 + 0.15 * minf(float(lvl), 1.0)
	# halo kyltin taakse pimeällä
	if night > 0.05 and on > 0.2:
		var hc := Game.bar_neon_color()
		draw_rect(r.grow(6.0), Color(hc.r, hc.g, hc.b, 0.05 * night * on))
		draw_rect(r.grow(3.0), Color(hc.r, hc.g, hc.b, 0.07 * night * on))
	for i in text.length():
		var ch := text[i]
		if ch == " ":
			continue
		var cx := x0 + font.get_string_size(text.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(cx, base_y)
		var col := Game.bar_neon_color() if split < 0 or i < split else Game.bar_neon_color2()
		var lit := on
		if i == _dead_letter:
			lit = 0.0
		elif i == _bad_letter and not _bad_on:
			lit = 0.08
		if lit < 0.2:
			# sammunut putki: himmeä lasi näkyy
			draw_string(font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r * 0.35, col.g * 0.35, col.b * 0.4, 0.75))
			continue
		var g := glow * lit
		# hehku: leveät, läpikuultavat ääriviivat
		draw_string_outline(font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 9, Color(col.r, col.g, col.b, 0.07 * g))
		draw_string_outline(font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(col.r, col.g, col.b, 0.16 * g))
		draw_string_outline(font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2, Color(col.r, col.g, col.b, 0.55 * g * bright))
		# putken kuuma ydin
		draw_string(font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.lerp(Color.WHITE, 0.45 * lit).darkened(0.1 * (1.0 - lit)))


## Reunavalot (Neonkyltti 2+): lamppurivi kyltin reunassa, juoksevat valot tasolla 3.
func _draw_frame_bulbs(lvl: int, glow: float, on: float) -> void:
	if lvl < 2:
		return
	var r := sign_rect.grow(1.0)
	var pts: Array[Vector2] = []
	var step := 5.0
	var x := r.position.x
	while x <= r.end.x:
		pts.append(Vector2(x, r.position.y))
		pts.append(Vector2(x, r.end.y))
		x += step
	var y := r.position.y + step
	while y < r.end.y:
		pts.append(Vector2(r.position.x, y))
		pts.append(Vector2(r.end.x, y))
		y += step
	for i in pts.size():
		var lit := on
		if lvl >= 3:
			lit *= 0.35 + 0.65 * float((int(_t * 8.0) + i) % 3 == 0)
		var c := WARM
		draw_circle(pts[i], 2.4, Color(c.r, c.g, c.b, 0.12 * glow * lit))
		draw_circle(pts[i], 0.9, Color(1.0, 0.95, 0.8, 0.35 + 0.65 * lit))


## AUKI / KIINNI -kyltti oven vieressä (Neonkyltti 1+, tai aina kun baari on auki illalla).
func _draw_open_sign(lvl: int, night: float) -> void:
	if not _owned() and lvl < 1 and night < 0.3:
		return
	var open := Game.owns_bar or Game.is_open(12, 4)
	var font := ThemeDB.fallback_font
	var txt := "AUKI" if open else "KIINNI"
	var col := GREEN if open else RED
	var p := door_center + Vector2(14.0, -13.0)
	var a := 0.75 + 0.25 * sin(_t * 3.0) if open else 0.9
	var g := lerpf(0.4, 1.0, night)
	draw_rect(Rect2(p + Vector2(-1, -6), Vector2(font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x + 2, 8)), Color(0.02, 0.02, 0.05, 0.85))
	draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, 4, Color(col.r, col.g, col.b, 0.18 * g * a))
	draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, col.lerp(Color.WHITE, 0.35) * Color(1, 1, 1, a))


## Valonauha julkisivun yläreunassa: lamput hohtavat pimeällä.
func _draw_festoon(night: float) -> void:
	if night < 0.05:
		return
	var y0 := roof.end.y + 2.0
	var x := roof.position.x + 3.0
	var seg := 24.0
	var i := 0
	while x < roof.end.x - 3.0:
		var x1 := minf(x + seg, roof.end.x - 3.0)
		var bx := x + 3.0
		while bx < x1:
			var t := (bx - x) / (x1 - x)
			var p := Vector2(bx, y0 + sin(t * PI) * 4.0)
			var cols := [WARM, Color(1.0, 0.5, 0.5), Color(0.6, 0.9, 1.0), Color(0.75, 1.0, 0.6)]
			var c: Color = cols[i % cols.size()]
			var tw := 0.8 + 0.2 * sin(_t * 2.0 + i * 1.7)
			draw_circle(p, 3.0, Color(c.r, c.g, c.b, 0.12 * night * tw))
			draw_circle(p, 1.0, Color(c.r, c.g, c.b, 0.6 + 0.4 * night))
			bx += 6.0
			i += 1
		x = x1


## Terassin valonauha ja lämmittimien hehku pimeällä (Terassi-päivitys).
func _draw_terrace_lights(night: float) -> void:
	if night < 0.05 or not Game.owns_bar or bar == null or bar.get("biz") == null:
		return
	var lvl := int(bar.biz.level("terrace"))
	if lvl < 1:
		return
	var tn: Variant = bar.get("terrace_node")
	if tn == null or not is_instance_valid(tn):
		return
	var deck: Rect2 = tn.deck()
	if deck.size.x <= 0.0:
		return
	var y0 := deck.position.y - (16.0 if lvl >= 2 else 12.0)
	var x := deck.position.x
	var i := 0
	while x <= deck.end.x:
		var t := fmod((x - deck.position.x) / 20.0, 1.0)
		var p := Vector2(x, y0 + sin(t * PI) * 3.0)
		var c: Color = [WARM, Color(1.0, 0.55, 0.55), Color(0.6, 0.9, 1.0)][i % 3]
		var tw := 0.85 + 0.15 * sin(_t * 2.3 + i)
		draw_circle(p, 3.0, Color(c.r, c.g, c.b, 0.13 * night * tw))
		draw_circle(p, 0.9, Color(c.r, c.g, c.b, 0.6 + 0.4 * night))
		x += 5.0
		i += 1
	if lvl >= 2:
		for hx: float in [deck.position.x + 6.0, deck.end.x - 6.0]:
			var hp := Vector2(hx, deck.end.y - 19.0)
			var fl := 0.8 + 0.2 * sin(_t * 6.0 + hx)
			draw_circle(hp, 10.0, Color(1.0, 0.45, 0.15, 0.08 * night * fl))
			draw_circle(hp, 3.0, Color(1.0, 0.55, 0.2, 0.6 * fl))


## Lämpimät seinälamput oven molemmin puolin hohtavat pimeällä.
func _draw_sconces(night: float) -> void:
	if night < 0.05:
		return
	for sx: float in [-19.0, 19.0]:
		var p := door_center + Vector2(sx, -6.0)
		draw_circle(p, 9.0, Color(WARM.r, WARM.g, WARM.b, 0.06 * night))
		draw_circle(p, 4.5, Color(WARM.r, WARM.g, WARM.b, 0.14 * night))
		draw_circle(p, 1.2, Color(1.0, 0.95, 0.8, night))


## Valonheittimet (Neonkyltti 3): kaksi keilaa pyyhkii taivasta pimeällä.
func _draw_spotlights(lvl: int, night: float, on: float) -> void:
	if lvl < 3 or night < 0.2:
		return
	for k in 2:
		var base := Vector2(roof.position.x + 6.0 if k == 0 else roof.end.x - 6.0, roof.position.y + 4.0)
		var ang := -PI * 0.5 + sin(_t * 0.6 + k * 2.4) * 0.55
		var dir := Vector2.from_angle(ang)
		var side := Vector2(-dir.y, dir.x)
		var length := 170.0
		var tip := base + dir * length
		var col := Color(0.85, 0.9, 1.0, 0.07 * night * on)
		draw_colored_polygon(PackedVector2Array([base - side * 2.0, base + side * 2.0, tip + side * 18.0, tip - side * 18.0]), col)
		draw_colored_polygon(PackedVector2Array([base - side * 1.0, base + side * 1.0, tip + side * 8.0, tip - side * 8.0]), Color(col.r, col.g, col.b, col.a * 1.4))
		draw_circle(base, 2.5, Color(1.0, 1.0, 0.95, 0.8 * night))
