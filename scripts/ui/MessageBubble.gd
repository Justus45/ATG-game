extends Control
## Viestit alakeskellä, piirrettynä (_draw), ei Labelia.
##   Repliikki (puhuja tunnistettu): sarjakuvamainen vaalea puhekupla, jonka nokka osoittaa
##   vasemmalla olevaan kasvokuvaan. Teksti kirjoittuu esiin, kupla "ponnahtaa" näkyviin
##   ja keinahtaa hieman puheen aikana.
##   Ilmoitus (ei puhujaa): pieni tumma kapseli ja ohut värillinen viiva, häipyy pehmeästi.
## Kupla mitoitetaan tekstin mukaan (max 3 riviä) ja kasvaa ylöspäin; alareuna pysyy paikallaan.
## HUD luo tämän ja kutsuu show_text().

const FS := 19
const LINE_H := 25.0
const PAD_X := 18.0
const PAD_Y := 11.0
const MAX_LINES := 3
const CPS := 48.0              ## kirjoitusnopeus (merkkiä/s)
const TAIL := 16.0             ## nokan pituus
const INK := Color(0.08, 0.08, 0.12)
const PAPER := Color(0.98, 0.96, 0.9)
const GOLD := Color(1.0, 0.82, 0.3)

var _font: Font
var _lines: PackedStringArray = []
var _chars := 0
var _speech := false
var _speaker := ""
var _kind := "info"            ## info / money / alert
var _t := 0.0
var _life := 0.0
var _dur := 3.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	hide()


## Puhujan repliikki, jos speaker != "", muuten ilmoitus.
func show_text(text: String, speaker: String, seconds: float) -> void:
	_speech = speaker != ""
	_speaker = speaker
	var max_w := size.x - PAD_X * 2.0 - (TAIL + 6.0 if _speech else 40.0)
	_lines = _wrap(text, max_w)
	_chars = 0
	for l in _lines:
		_chars += l.length()
	_kind = _classify(text)
	_t = 0.0
	_life = 0.0
	_dur = seconds
	show()
	queue_redraw()


## Kuinka kauan tekstin kirjoittuminen kestää (suun liike kasvokuvassa).
func talk_time() -> float:
	return float(_chars) / CPS + 0.15


func hide_now() -> void:
	hide()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_life += delta
	if _life > _dur + 0.25:
		hide()
		return
	var fade_out := clampf((_dur + 0.25 - _life) / 0.25, 0.0, 1.0)
	if _speech:
		modulate.a = minf(_t / 0.11, 1.0) * fade_out
	else:
		modulate.a = (1.0 - pow(1.0 - clampf(_t / 0.2, 0.0, 1.0), 3.0)) * fade_out
	queue_redraw()


func _classify(text: String) -> String:
	if text.contains("$"):
		return "money"
	if text.contains("!") or text.to_lower().contains("poliisi") or text.to_lower().contains("varo"):
		return "alert"
	return "info"


## Rivitys sanoittain annettuun leveyteen; yli MAX_LINES -> viimeinen rivi päättyy "…".
func _wrap(text: String, max_w: float) -> PackedStringArray:
	var out: PackedStringArray = []
	for para in text.split("\n"):
		var line := ""
		for word in para.split(" ", false):
			var test := word if line == "" else line + " " + word
			if _w(test) <= max_w or line == "":
				line = test
			else:
				out.append(line)
				line = word
		out.append(line)
	if out.size() > MAX_LINES:
		var last := out[MAX_LINES - 1]
		while last.length() > 1 and _w(last + "…") > max_w:
			last = last.substr(0, last.length() - 1)
		out.resize(MAX_LINES)
		out[MAX_LINES - 1] = last.strip_edges() + "…"
	return out


func _w(s: String) -> float:
	return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x


func _text_w() -> float:
	var m := 0.0
	for l in _lines:
		m = maxf(m, _w(l))
	return m


# ----------------------------------------------------------------------------
#  PIIRTO
# ----------------------------------------------------------------------------
func _draw() -> void:
	if _lines.is_empty():
		return
	if _speech:
		_draw_speech()
	else:
		_draw_notice()


## Vaalea puhekupla, nokka vasemmalle kasvokuvaan.
func _draw_speech() -> void:
	var tw := _text_w()
	var h := _lines.size() * LINE_H + PAD_Y * 2.0
	var w := maxf(tw + PAD_X * 2.0, 120.0)
	var r := Rect2(TAIL + 2.0, size.y - h, w, h)
	# ponnahdus: skaalaus nokan kärjestä, pieni keinunta puheen aikana
	var tip := Vector2(-6.0, size.y - minf(h * 0.5, 40.0) + 6.0)
	var k := clampf(_t / 0.22, 0.0, 1.0)
	var s := 1.0 + 0.12 * sin(k * PI) * (1.0 - k) - 0.25 * (1.0 - k)
	var talking := _t * CPS < _chars
	var sway := sin(_t * 6.0) * 0.006 if talking else 0.0
	draw_set_transform(tip, sway, Vector2(s, s))
	var o := -tip  # piirretään pivot-koordinaateissa
	var rr := Rect2(r.position + o, r.size)
	# varjo
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0, 0, 0, 0.35)
	sh.set_corner_radius_all(16)
	draw_style_box(sh, Rect2(rr.position + Vector2(4, 5), rr.size))
	# nokka (ääriviiva + täyttö)
	var ty := rr.position.y + rr.size.y * 0.5 + 6.0
	var base_top := Vector2(rr.position.x + 4.0, ty - 9.0)
	var base_bot := Vector2(rr.position.x + 4.0, ty + 7.0)
	var tp := Vector2.ZERO
	draw_colored_polygon(PackedVector2Array([base_top + Vector2(0, -3), tp + Vector2(-3, 0), base_bot + Vector2(0, 3)]), INK)
	# kupla
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = INK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(16)
	draw_style_box(sb, rr)
	draw_colored_polygon(PackedVector2Array([base_top + Vector2(1, 0), tp + Vector2(2, 0), base_bot + Vector2(1, 0)]), PAPER)
	# kiilto yläreunassa
	draw_rect(Rect2(rr.position + Vector2(14, 5), Vector2(rr.size.x - 28.0, 3)), Color(1, 1, 1, 0.7))
	# teksti kirjoituskoneena
	var n := int(_t * CPS)
	var y := rr.position.y + PAD_Y + LINE_H - 7.0
	for l in _lines:
		var part := l.substr(0, clampi(n, 0, l.length()))
		draw_string(_font, Vector2(rr.position.x + PAD_X, y), part, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, INK)
		n -= l.length()
		y += LINE_H
	# puhe kesken: kolme hyppivää pistettä oikeassa alakulmassa
	if talking:
		for i in 3:
			var c := Vector2(rr.end.x - 30.0 + i * 8.0, rr.end.y - 8.0 - absf(sin(_t * 9.0 + i * 0.9)) * 3.0)
			draw_circle(c, 2.2, Color(INK, 0.55))
	else:
		# jäljellä oleva aika ohuena palkkina alareunassa
		var left := clampf(1.0 - _life / maxf(_dur, 0.01), 0.0, 1.0)
		draw_rect(Rect2(rr.position.x + 14.0, rr.end.y - 6.0, (rr.size.x - 28.0) * left, 2.0), Color(INK, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Pieni, hillitty ilmoitus: tumma kapseli ja ohut värillinen viiva vasemmalla.
## Ei kuvaketta, ei välähdystä; ilmestyy pehmeästi ja häipyy.
func _draw_notice() -> void:
	var accent: Color = {"money": Color(0.55, 0.9, 0.55), "alert": Color(1.0, 0.55, 0.4), "info": Color(0.7, 0.8, 0.95)}[_kind]
	var fs := 17
	var lh := 22.0
	var tw := 0.0
	for l in _lines:
		tw = maxf(tw, _font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var h := _lines.size() * lh + 14.0
	var w := tw + 34.0
	var e := 1.0 - pow(1.0 - clampf(_t / 0.18, 0.0, 1.0), 3.0)
	var r := Rect2((size.x - w) * 0.5, size.y - h + (1.0 - e) * 6.0, w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.78)
	sb.set_corner_radius_all(int(minf(h * 0.5, 16.0)))
	draw_style_box(sb, r)
	draw_rect(Rect2(r.position.x + 9.0, r.position.y + 7.0, 3.0, r.size.y - 14.0), Color(accent, 0.85))
	var y := r.position.y + 7.0 + lh - 6.0
	for l in _lines:
		draw_string(_font, Vector2(r.position.x + 20.0, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.94, 0.95, 0.97))
		y += lh
