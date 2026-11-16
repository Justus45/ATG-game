extends Node2D
## Juhlasali (Laajennus-päivitys) ja illan tapahtumat baarin sisällä.
##  - Laajennus 1: holvikaaren takana juhlasali: esiintymislava punaisine verhoineen,
##    valotrussi, LED-tanssilattia ja pöydät. Laajennus 2: VIP-lounge samppanjoineen.
##  - Tapahtumat näkyvät oikeasti (BarBusiness.event_id()):
##      band     = bändi lavalla: laulaja, kitaristi, basisti ja rumpali, vahvistimet, valot
##      karaoke  = karaokelaulaja ja sanoitusruutu
##      quiz     = juontaja, kysymysruutu ja vastauslaput pöydillä
##      happy    = HAPPY HOUR -neonkyltti ja tungos
##    Bändi- ja karaokeiltana yleisö tanssii lavan edessä. Ilman Laajennusta esiintyjät
##    ovat pienellä lavalla salin oikeassa reunassa.
## Koordinaatit baarin huoneen paikallisia (Bar._interior:n lapsi).

const TILE := 16
const HALL_X := 352.0
const HALL_W := 144.0
const STAGE := Rect2(364.0, 34.0, 120.0, 32.0)
const MINI_STAGE := Rect2(194.0, 104.0, 68.0, 18.0)
const LED_FLOOR := Rect2(372.0, 80.0, 104.0, 56.0)
const VIP := Rect2(440.0, 146.0, 52.0, 42.0)
const RED := Color(0.55, 0.06, 0.1)
const GOLD := Color(0.85, 0.68, 0.3)

const CHATTER := {
	"band": ["Soittakaa lisää!", "Ihana biisi!", "Encore!", "Tää bändi on kova!", "Tanssimaan!"],
	"karaoke": ["Mun vuoro seuraavaks!", "La la laa!", "Ihan nuotin vierestä!", "Laulakaa Paratiisi!"],
	"quiz": ["Helsinki!", "Se oli 1952!", "Ei hajuakaan...", "Me voitetaan tää!", "Kysymys kolme oli vaikee."],
	"happy": ["Halpaa kaljaa!", "Vielä yhdet!", "Happy hour, jee!", "Tilaa mullekin!"],
}
const QUIZ_QUESTIONS := ["MIKÄ ON SUOMEN PÄÄKAUPUNKI?", "MONTAKO CL ON KOSSUSSA?", "KUKA KEKSI SAUNAN?",
	"MIKÄ VUOSI OLI OLYMPIALAISET?", "MIKÄ ON KOSKENKORVAN VÄRI?", "PALJONKO ON 7 x 8?"]

var bar: Node = null
## "floor" = juhlasalin lattia, lava ja kalusteet (piirretään ennen sisätilaa),
## "top" = tapahtumat, esiintyjät ja yleisö (kaiken päällä)
var layer_kind := "top"
var _t := 0.0
var _chat_t := 6.0
var _quiz_q := 0
var _quiz_t := 0.0


## Lavan tapahtuma (bändi / karaoke / tietovisa) tai "" (happy hour piirretään erikseen)
func _ev() -> String:
	if not Game.owns_bar or bar == null or bar.get("biz") == null:
		return ""
	var e := str(bar.biz.event_id())
	return e if e != "happy" else ""


func _happy() -> bool:
	return Game.owns_bar and bar != null and bar.get("biz") != null and bool(bar.biz.has_event("happy"))


func _lv(id: String) -> int:
	if not Game.owns_bar or bar == null or bar.get("biz") == null:
		return 0
	return int(bar.biz.level(id))


func _music() -> bool:
	var v = bar.get("_view") if bar else null
	return v != null and Game.flag(v, "music_on")


func _process(delta: float) -> void:
	_t += delta
	if bar == null or not bar.get("inside"):
		return
	if layer_kind == "floor":
		queue_redraw()
		return
	var ev := _ev()
	# yleisön huudot tapahtumailtana (lavan esitys tai happy hour)
	if ev == "" and _happy():
		ev = "happy"
	if ev != "":
		_chat_t -= delta
		if _chat_t <= 0.0:
			_chat_t = randf_range(5.0, 10.0)
			var lines: Array = CHATTER.get(ev, [])
			var pats: Array = bar.get("patrons")
			if not lines.is_empty() and not pats.is_empty() and bar.can_shout():
				var pt = pats[randi() % pats.size()]
				if is_instance_valid(pt) and pt.has_method("say"):
					bar.note_shout()
					pt.say(lines[randi() % lines.size()], 2.0)
	if ev == "quiz":
		_quiz_t += delta
		if _quiz_t > 12.0:
			_quiz_t = 0.0
			_quiz_q = (_quiz_q + 1) % 10
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var exp_lvl := _lv("space")
	if layer_kind == "floor":
		if exp_lvl >= 1:
			_draw_hall(font, exp_lvl)
		return
	var big := exp_lvl >= 1
	if _happy():
		_draw_happy(font, big and _ev() == "")
	var ev := _ev()
	if ev == "":
		return
	var stage := STAGE if big else MINI_STAGE
	if not big:
		_draw_mini_stage()
	match ev:
		"band":
			_draw_crowd(big)
			_draw_band(stage, big, font)
		"karaoke":
			_draw_crowd(big)
			_draw_karaoke(stage, big, font)
		"quiz":
			_draw_quiz(stage, big, font)


# ----------------------------------------------------------------------------
#  JUHLASALI
# ----------------------------------------------------------------------------
func _draw_hall(font: Font, lvl: int) -> void:
	var floor_r := Rect2(HALL_X, 2 * TILE, HALL_W, 10 * TILE)
	# tumma parketti
	draw_rect(floor_r, Color(0.22, 0.13, 0.09))
	var y := floor_r.position.y
	var row := 0
	while y < floor_r.end.y:
		draw_line(Vector2(floor_r.position.x, y), Vector2(floor_r.end.x, y), Color(0, 0, 0, 0.25), 1.0)
		var x := floor_r.position.x + float((row * 23) % 36)
		while x < floor_r.end.x:
			draw_line(Vector2(x, y), Vector2(x, y + 8.0), Color(0, 0, 0, 0.18), 1.0)
			x += 36.0
		y += 8.0
		row += 1
	# takaseinä: punaiset samettiverhot ja valotrussi
	var wall := Rect2(HALL_X, 0.0, HALL_W, 2 * TILE)
	draw_rect(wall, RED.darkened(0.3))
	var fx := wall.position.x
	var k := 0
	while fx < wall.end.x:
		draw_rect(Rect2(fx, 0.0, 4.0, 2 * TILE), RED if k % 2 == 0 else RED.lightened(0.12))
		fx += 4.0
		k += 1
	draw_rect(Rect2(wall.position.x, 0.0, wall.size.x, 4.0), GOLD)
	for tx in 6:
		var lp := Vector2(STAGE.position.x + 10.0 + tx * 20.0, 6.0)
		draw_rect(Rect2(lp - Vector2(3, 2), Vector2(6, 5)), Color(0.12, 0.12, 0.14))
		draw_circle(lp + Vector2(0, 3), 1.5, Color(1.0, 0.95, 0.8))
	# lava
	draw_rect(Rect2(STAGE.position + Vector2(0, 3), STAGE.size), Color(0, 0, 0, 0.35))
	draw_rect(STAGE, Color(0.3, 0.18, 0.1))
	var sx := STAGE.position.x
	while sx < STAGE.end.x:
		draw_line(Vector2(sx, STAGE.position.y), Vector2(sx, STAGE.end.y), Color(0, 0, 0, 0.2), 1.0)
		sx += 10.0
	draw_rect(Rect2(STAGE.position.x, STAGE.end.y - 3.0, STAGE.size.x, 3.0), Color(0.5, 0.32, 0.16))
	draw_rect(Rect2(STAGE.position.x, STAGE.end.y - 1.0, STAGE.size.x, 1.0), GOLD)
	# kaiutinpinot lavan reunoilla
	for px: float in [STAGE.position.x + 2.0, STAGE.end.x - 14.0]:
		draw_rect(Rect2(px, STAGE.position.y + 2.0, 12.0, 22.0), Color(0.08, 0.08, 0.09))
		draw_circle(Vector2(px + 6.0, STAGE.position.y + 8.0), 3.5, Color(0.25, 0.25, 0.28))
		draw_circle(Vector2(px + 6.0, STAGE.position.y + 17.0), 4.5, Color(0.25, 0.25, 0.28))
	# nimi verhon yläreunassa
	var nm := Game.bar_name()
	var nb := Game.bar_neon_color()
	var nc := Color(nb.r, nb.g, nb.b, 0.8 + 0.2 * sin(_t * 3.0))
	TextFit.draw_outline(self, font, Vector2(STAGE.position.x, 22.0), nm, STAGE.size.x, 9, 3, Color(nc.r, nc.g, nc.b, 0.3))
	TextFit.draw(self, font, Vector2(STAGE.position.x, 22.0), nm, STAGE.size.x, 9, nc.lerp(Color.WHITE, 0.3))
	# LED-tanssilattia
	var music := _music()
	var cell := 13.0
	var cy := LED_FLOOR.position.y
	var r := 0
	while cy < LED_FLOOR.end.y - 1.0:
		var cx := LED_FLOOR.position.x
		var c := 0
		while cx < LED_FLOOR.end.x - 1.0:
			var wave := sin(_t * (3.0 if music else 0.8) - (c + r) * 0.6)
			var col := Color.from_hsv(fmod((c * 0.07 + r * 0.11) + _t * (0.15 if music else 0.03), 1.0), 0.8, 1.0)
			draw_rect(Rect2(cx, cy, cell - 1.0, cell - 1.0), Color(col.r, col.g, col.b, (0.25 + 0.25 * wave) if music else 0.12))
			cx += cell
			c += 1
		cy += cell
		r += 1
	draw_rect(LED_FLOOR, Color(1, 1, 1, 0.35), false, 1.0)
	# korkeat seisomapöydät
	for tp: Vector2 in [Vector2(366.0, 160.0), Vector2(390.0, 178.0)]:
		draw_circle(tp + Vector2(0, 2), 6.0, Color(0, 0, 0, 0.25))
		draw_circle(tp, 5.5, Color(0.12, 0.12, 0.14))
		draw_circle(tp, 4.5, Color(0.25, 0.25, 0.3))
		draw_rect(Rect2(tp + Vector2(-1, -4), Vector2(2, 4)), Color(0.95, 0.7, 0.2))
	# valokiilat lavalta
	var beam_a := 0.06 + (0.05 if music else 0.0)
	for b in 3:
		var bx := STAGE.position.x + 25.0 + b * 35.0
		var sway := sin(_t * 0.8 + b) * 14.0 if music else 0.0
		var bc := [Color(1.0, 0.3, 0.6), Color(0.3, 0.8, 1.0), Color(1.0, 0.85, 0.4)][b] as Color
		draw_colored_polygon(PackedVector2Array([Vector2(bx - 2, 8), Vector2(bx + 2, 8),
			Vector2(bx + 18 + sway, LED_FLOOR.end.y), Vector2(bx - 18 + sway, LED_FLOOR.end.y)]), Color(bc.r, bc.g, bc.b, beam_a))
	if lvl >= 2:
		_draw_vip(font)


func _draw_vip(font: Font) -> void:
	# korotettu matto, kultaköysi, sohvat, samppanjaämpäri ja VIP-neon
	draw_rect(VIP, Color(0.3, 0.04, 0.08))
	draw_rect(VIP.grow(-2.0), Color(0.4, 0.06, 0.1))
	for k in 4:
		var pp := Vector2(VIP.position.x, VIP.position.y + k * 13.0)
		draw_rect(Rect2(pp + Vector2(-1, -4), Vector2(2.5, 6)), GOLD)
	draw_line(VIP.position + Vector2(0, -2), Vector2(VIP.position.x, VIP.end.y - 3.0), Color(0.6, 0.05, 0.12), 1.5)
	for k in 3:
		var pp2 := Vector2(VIP.position.x + k * 17.0, VIP.position.y)
		draw_rect(Rect2(pp2 + Vector2(-1, -4), Vector2(2.5, 6)), GOLD)
	draw_line(VIP.position + Vector2(0, -2), Vector2(VIP.end.x - 4.0, VIP.position.y - 2.0), Color(0.6, 0.05, 0.12), 1.5)
	# sohvat
	draw_rect(Rect2(VIP.end.x - 12.0, VIP.position.y + 6.0, 10.0, 30.0), Color(0.08, 0.06, 0.07))
	draw_rect(Rect2(VIP.end.x - 11.0, VIP.position.y + 7.0, 8.0, 28.0), Color(0.18, 0.15, 0.17))
	draw_rect(Rect2(VIP.position.x + 8.0, VIP.end.y - 10.0, 28.0, 8.0), Color(0.18, 0.15, 0.17))
	# pöytä ja samppanja
	var tc := VIP.get_center() + Vector2(2, 0)
	draw_circle(tc, 7.0, Color(0.1, 0.1, 0.12))
	draw_circle(tc, 6.0, Color(0.85, 0.85, 0.9, 0.35))
	draw_rect(Rect2(tc + Vector2(-3, -5), Vector2(6, 6)), Color(0.75, 0.77, 0.8))
	draw_rect(Rect2(tc + Vector2(-1, -10), Vector2(2, 6)), Color(0.1, 0.3, 0.15))
	draw_rect(Rect2(tc + Vector2(-1, -11), Vector2(2, 1.5)), GOLD)
	for gx: float in [-5.0, 5.0]:
		draw_line(tc + Vector2(gx, 3), tc + Vector2(gx, 6), Color(1, 1, 1, 0.7), 1.0)
		draw_rect(Rect2(tc + Vector2(gx - 1, 0), Vector2(2, 3)), Color(1.0, 0.9, 0.5, 0.8))
	var vc := Color(1.0, 0.82, 0.3, 0.8 + 0.2 * sin(_t * 2.5))
	TextFit.draw_outline(self, font, Vector2(VIP.position.x, VIP.position.y + 10.0), "VIP", VIP.size.x - 12.0, 8, 3, Color(vc.r, vc.g, vc.b, 0.3))
	TextFit.draw(self, font, Vector2(VIP.position.x, VIP.position.y + 10.0), "VIP", VIP.size.x - 12.0, 8, vc.lerp(Color.WHITE, 0.3))


func _draw_mini_stage() -> void:
	var r := MINI_STAGE
	draw_rect(Rect2(r.position + Vector2(0, 2), r.size), Color(0, 0, 0, 0.35))
	draw_rect(r, Color(0.3, 0.18, 0.1))
	draw_rect(Rect2(r.position.x, r.end.y - 2.0, r.size.x, 2.0), GOLD)
	# kaksi spottia
	for k in 2:
		var bx := r.position.x + 15.0 + k * 38.0
		draw_colored_polygon(PackedVector2Array([Vector2(bx - 2, 34), Vector2(bx + 2, 34), Vector2(bx + 12, r.end.y), Vector2(bx - 12, r.end.y)]),
			Color(1.0, 0.9, 0.6, 0.07))


# ----------------------------------------------------------------------------
#  ESIINTYJÄT
# ----------------------------------------------------------------------------
func _npc(row: int, pos: Vector2, step: int, facing: Vector2i = Vector2i.DOWN) -> void:
	var city = bar.get("city") if bar else null
	if city and city.has_method("npc_tex"):
		var tex: Texture2D = city.npc_tex(row, facing, step)
		if tex:
			draw_texture(tex, pos - tex.get_size() * 0.5 + Vector2(0, -4))
			return
	draw_rect(Rect2(pos + Vector2(-4, -10), Vector2(8, 12)), Color(0.5, 0.4, 0.7))
	draw_circle(pos + Vector2(0, -12), 3.5, Color(0.93, 0.76, 0.6))


func _draw_band(stage: Rect2, big: bool, _font: Font) -> void:
	var music := _music()
	var beat := absf(sin(_t * 7.0)) if music else 0.0
	var base_y := stage.position.y + (20.0 if big else 10.0)
	var cx := stage.get_center().x
	var span := 34.0 if big else 20.0
	# rummut takana
	var dp := Vector2(cx + (0.0 if big else 22.0), base_y - (10.0 if big else 2.0))
	_npc(9, dp + Vector2(0, -4 - beat), 0)
	draw_circle(dp + Vector2(0, 6), 5.0, Color(0.85, 0.85, 0.9))
	draw_circle(dp + Vector2(0, 6), 4.0, Color(0.6, 0.1, 0.15))
	draw_circle(dp + Vector2(-8, 3), 3.0, Color(0.85, 0.85, 0.9))
	draw_circle(dp + Vector2(8, 3), 3.0, Color(0.85, 0.85, 0.9))
	draw_line(dp + Vector2(10, -2), dp + Vector2(14, -8), Color(0.9, 0.8, 0.3), 1.0)
	draw_circle(dp + Vector2(14, -8), 3.5, Color(0.95, 0.8, 0.3, 0.8))   # symbaali
	var stick := sin(_t * 14.0) * 3.0 if music else 0.0
	draw_line(dp + Vector2(-4, -2), dp + Vector2(-7, 2 + stick), Color(0.9, 0.85, 0.7), 1.0)
	draw_line(dp + Vector2(4, -2), dp + Vector2(7, 2 - stick), Color(0.9, 0.85, 0.7), 1.0)
	# kitaristi vasemmalla, laulaja keskellä, basisti oikealla
	var gp := Vector2(cx - span, base_y + 2.0)
	_npc(3, gp + Vector2(0, -beat * 1.5), 1 + int(_t * 4.0) % 2 if music else 0)
	draw_line(gp + Vector2(-6, 0), gp + Vector2(5, -6), Color(0.85, 0.2, 0.15), 2.0)
	draw_circle(gp + Vector2(-5, 0), 2.5, Color(0.85, 0.2, 0.15))
	var sp := Vector2(cx - (0.0 if big else 6.0), base_y + 6.0)
	_npc(12, sp + Vector2(0, -beat), 0)
	draw_line(sp + Vector2(5, 8), sp + Vector2(5, -5), Color(0.6, 0.6, 0.65), 1.0)
	draw_circle(sp + Vector2(5, -6), 1.5, Color(0.15, 0.15, 0.15))
	if big:
		var bp := Vector2(cx + span, base_y + 2.0)
		_npc(6, bp + Vector2(0, -absf(sin(_t * 7.0 + 1.0)) * 1.5 if music else 0.0), 0)
		draw_line(bp + Vector2(-5, 1), bp + Vector2(7, -8), Color(0.2, 0.35, 0.7), 2.0)
		draw_circle(bp + Vector2(-4, 1), 2.5, Color(0.2, 0.35, 0.7))
		# vahvistimet
		for ax: float in [cx - span - 18.0, cx + span + 12.0]:
			draw_rect(Rect2(ax, base_y - 4.0, 9.0, 10.0), Color(0.1, 0.1, 0.1))
			draw_rect(Rect2(ax + 1.0, base_y - 3.0, 7.0, 2.0), Color(0.75, 0.6, 0.3))
	# nuotit leijuvat
	if music:
		for k in 3:
			var ph := fmod(_t * 0.6 + k * 0.33, 1.0)
			var np := Vector2(cx - 30.0 + k * 30.0 + sin(_t * 2.0 + k) * 6.0, stage.position.y - ph * 26.0 + 4.0)
			var na := 1.0 - ph
			draw_circle(np, 1.6, Color(1, 1, 1, na))
			draw_line(np + Vector2(1.4, 0), np + Vector2(1.4, -5), Color(1, 1, 1, na), 1.0)
			draw_line(np + Vector2(1.4, -5), np + Vector2(3.8, -3.5), Color(1, 1, 1, na), 1.0)


func _draw_karaoke(stage: Rect2, big: bool, font: Font) -> void:
	var cx := stage.get_center().x
	var base_y := stage.position.y + (20.0 if big else 10.0)
	# sanoitusruutu
	var scr := Rect2(cx + (16.0 if big else 10.0), stage.position.y + (2.0 if big else -16.0), 34.0, 20.0)
	draw_rect(scr.grow(1.0), Color(0.1, 0.1, 0.12))
	draw_rect(scr, Color(0.05, 0.08, 0.3))
	var hl := fmod(_t * 0.4, 1.0)
	for k in 3:
		var ly := scr.position.y + 5.0 + k * 5.0
		draw_rect(Rect2(scr.position.x + 3.0, ly, scr.size.x - 6.0, 2.0), Color(1, 1, 1, 0.5))
		if k == 1:
			draw_rect(Rect2(scr.position.x + 3.0, ly, (scr.size.x - 6.0) * hl, 2.0), Color(1.0, 0.85, 0.2))
	draw_circle(Vector2(scr.position.x + 3.0 + (scr.size.x - 6.0) * hl, scr.position.y + 7.5 - absf(sin(_t * 8.0)) * 2.0), 1.2, Color(1.0, 0.4, 0.6))
	# laulaja mikrofonin kanssa + spotti
	var sp := Vector2(cx - (8.0 if big else 4.0), base_y + 4.0)
	draw_circle(sp + Vector2(0, 6), 14.0, Color(1.0, 0.95, 0.75, 0.1))
	_npc(15, sp + Vector2(0, -absf(sin(_t * 3.0)) * 1.0), 0)
	draw_line(sp + Vector2(4, -2), sp + Vector2(6, -6), Color(0.3, 0.3, 0.32), 1.5)
	draw_circle(sp + Vector2(6, -7), 1.5, Color(0.15, 0.15, 0.15))
	if fmod(_t, 2.4) < 1.4:
		var t := ["La la laa!", "Oooh beibi!", "Paratiisiii!"][int(_t / 2.4) % 3] as String
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x + 6.0
		var bb := Rect2(sp.x - w * 0.5, sp.y - 28.0, w, 10.0)
		draw_rect(bb, Color(1, 1, 1, 0.92))
		draw_string(font, bb.position + Vector2(3, 7.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.6, 0.1, 0.4))


func _draw_quiz(stage: Rect2, big: bool, font: Font) -> void:
	var cx := stage.get_center().x
	# kysymysruutu
	var scr := Rect2(cx - 34.0, stage.position.y + (1.0 if big else -26.0), 68.0, 24.0)
	draw_rect(scr.grow(1.0), Color(0.1, 0.1, 0.12))
	draw_rect(scr, Color(0.08, 0.1, 0.25))
	TextFit.draw(self, font, Vector2(scr.position.x, scr.position.y + 7.0), "TIETOVISA  %d/10" % (_quiz_q + 1), scr.size.x, 6, Color(1.0, 0.85, 0.3))
	TextFit.draw(self, font, Vector2(scr.position.x + 2.0, scr.position.y + 15.0), QUIZ_QUESTIONS[_quiz_q % QUIZ_QUESTIONS.size()], scr.size.x - 4.0, 4, Color.WHITE)
	var left := 1.0 - _quiz_t / 12.0
	draw_rect(Rect2(scr.position.x + 4.0, scr.end.y - 4.0, (scr.size.x - 8.0) * left, 2.0), Color(0.3, 0.9, 0.4).lerp(Color(0.9, 0.2, 0.2), 1.0 - left))
	# juontaja mikrofonin kanssa
	var hp := Vector2(cx + (scr.size.x * 0.5 + 8.0) * (1.0 if big else 0.0) + (0.0 if big else 26.0), stage.position.y + (24.0 if big else 12.0))
	_npc(0, hp, 0)
	draw_circle(hp + Vector2(-5, -6), 1.5, Color(0.15, 0.15, 0.15))
	# vastauslaput ja kynät pöydillä
	for tp: Vector2 in [Vector2(64.0, 150.0), Vector2(288.0, 150.0)]:
		draw_rect(Rect2(tp + Vector2(-8, -2), Vector2(6, 7)), Color.WHITE)
		draw_line(tp + Vector2(-7, 0), tp + Vector2(-3, 0), Color(0.3, 0.3, 0.5), 1.0)
		draw_line(tp + Vector2(-7, 2), tp + Vector2(-4, 2), Color(0.3, 0.3, 0.5), 1.0)
		draw_line(tp + Vector2(-1, 3), tp + Vector2(3, -1), Color(0.2, 0.3, 0.8), 1.0)


func _draw_happy(font: Font, big: bool) -> void:
	# vapaasti seisova neonkyltti sisäänkäynnin lähellä (ja juhlasalin verhossa)
	var r := Rect2(132.0, 160.0, 76.0, 16.0)
	var on := fmod(_t, 3.0) > 0.15 and not (fmod(_t, 7.0) < 0.3 and fmod(_t * 10.0, 2.0) < 1.0)
	draw_rect(r, Color(0.04, 0.03, 0.08, 0.9))
	draw_rect(r, Color(1.0, 0.85, 0.2, 0.6 if on else 0.2), false, 1.0)
	var c := Color(1.0, 0.85, 0.2) if on else Color(0.35, 0.3, 0.1)
	if on:
		TextFit.draw_outline(self, font, Vector2(r.position.x, r.position.y + 11.0), "HAPPY HOUR", r.size.x, 9, 4, Color(1.0, 0.85, 0.2, 0.25))
	TextFit.draw(self, font, Vector2(r.position.x, r.position.y + 11.0), "HAPPY HOUR", r.size.x, 9, c.lerp(Color.WHITE, 0.3 if on else 0.0))
	if big:
		TextFit.draw_outline(self, font, Vector2(STAGE.position.x, STAGE.position.y + 22.0), "HAPPY HOUR -25%", STAGE.size.x, 10, 4, Color(1.0, 0.85, 0.2, 0.3))
		TextFit.draw(self, font, Vector2(STAGE.position.x, STAGE.position.y + 22.0), "HAPPY HOUR -25%", STAGE.size.x, 10, Color(1.0, 0.95, 0.6))


## Tanssiva yleisö lavan edessä (bändi- ja karaokeilta).
func _draw_crowd(big: bool) -> void:
	var music := _music()
	var pts: Array[Vector2] = []
	if big:
		for k in 7:
			pts.append(Vector2(LED_FLOOR.position.x + 12.0 + (k % 4) * 26.0 + (6.0 if k >= 4 else 0.0), LED_FLOOR.position.y + 14.0 + int(k / 4) * 22.0))
	else:
		for k in 3:
			pts.append(Vector2(MINI_STAGE.position.x + 12.0 + k * 22.0, MINI_STAGE.end.y + 16.0 + (k % 2) * 8.0))
	for k in pts.size():
		var bob := absf(sin(_t * 6.0 + k * 1.3)) * 2.5 if music else 0.0
		var sway := sin(_t * 3.0 + k) * 1.5 if music else 0.0
		_npc(((k * 2 + 1) % 6) * 3, pts[k] + Vector2(sway, -bob), 1 + (int(_t * 3.0 + k) % 2) if music else 0, Vector2i.UP)
