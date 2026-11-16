extends Control
## Keskusteluikkuna Stardew Valleyn tapaan, HUDin väreissä: tumma kultareunainen laatikko alareunassa,
## oikealla iso kehystetty kasvokuva (suu liikkuu, silmät räpsyvät) ja nimikyltti.
##   menu  valikko (Kalle, baarimikko, kauppa...): kysymys kirjoittuu esiin, vastaukset
##         riveinä; hiiri, nuolet + Enter tai numerot 1–9. Esc / E peruu. Peli on lukossa.
##   say   pelin aikana tuleva repliikki: kapeampi laatikko alareunassa (asepaikan oikealla
##         puolella), sulkeutuu itse. HUD siirtää E-kehotuksen laatikon yläpuolelle (say_top).
## Koko ikkuna piirretään (_draw); mitat lasketaan näytön koosta, joten mikään ei mene yli.
## HUD luo tämän (show_menu / show_message).

signal chosen(index: int)

const FS := 20
const LINE_H := 26.0
const ROW_H := 32.0
const CPS := 50.0
const SRC := Rect2(2.5, 1.0, 11.0, 11.0)   ## pää ja hartiat 16x16-kuvasta
const MOUTH := Vector2(7.75, 7.05)
const EYES := [Rect2(5.4, 4.9, 1.6, 1.1), Rect2(9.0, 4.9, 1.6, 1.1)]

# Väripaletti: sama kuin muussa HUDissa (taukovalikko, kello, puhelu)
const BG := Color(0.05, 0.06, 0.1, 0.94)
const GOLD := Color(1.0, 0.82, 0.3)
const TEXT := Color(0.93, 0.93, 0.97)
const DIM := Color(0.6, 0.62, 0.7)

var _mode := ""                 ## "", "menu", "say"
var _speaker := ""
var _tex: Texture2D
var _title_lines: PackedStringArray = []
var _options: Array = []
var _sel := 0
var _hover := -1
var _rows: Array[Rect2] = []
var _t := 0.0
var _life := 0.0
var _dur := 0.0
var _chars := 0
var _skin := Color(0.96, 0.74, 0.57)
var _blink_t := 2.0
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = ThemeDB.fallback_font
	gui_input.connect(_on_gui_input)
	hide()


func is_menu() -> bool:
	return visible and _mode == "menu"


func is_saying() -> bool:
	return visible and _mode == "say"


func open_menu(speaker: String, tex: Texture2D, title: String, options: Array) -> void:
	_start("menu", speaker, tex)
	_options = options.duplicate()
	_sel = 0
	_hover = -1
	_title_lines = _wrap(title, _text_w(), 4)
	mouse_filter = Control.MOUSE_FILTER_STOP


func say(speaker: String, tex: Texture2D, text: String, seconds: float) -> void:
	_start("say", speaker, tex)
	_options = []
	_dur = seconds
	_title_lines = _wrap(text, _text_w(), 3)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func close() -> void:
	_mode = ""
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func move_selection(step: int) -> void:
	if _options.is_empty():
		return
	_sel = (_sel + step + _options.size()) % _options.size()
	Sfx.play_ui("step", -14.0, 1.8)


func selected() -> int:
	return _sel


## Kirjoittaako teksti vielä? Ensimmäinen painallus näyttää koko tekstin.
func typing() -> bool:
	return _t * CPS < _chars


func skip_typing() -> void:
	_t = float(_chars) / CPS + 0.01


func _start(mode: String, speaker: String, tex: Texture2D) -> void:
	_mode = mode
	_speaker = speaker
	_tex = tex
	_t = 0.0
	_life = 0.0
	_skin = _sample_skin(tex)
	show()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_life += delta
	_blink_t -= delta
	if _blink_t < -0.12:
		_blink_t = randf_range(2.2, 4.5)
	if _mode == "say" and _life > _dur + 0.25:
		close()
		return
	queue_redraw()


# ----------------------------------------------------------------------------
#  MITAT
# ----------------------------------------------------------------------------
func _vs() -> Vector2:
	return size if size.x > 1.0 else get_viewport_rect().size


func _box_w() -> float:
	var vs := _vs()
	if _mode == "menu":
		return minf(940.0, vs.x - 60.0)
	# asepaikka vie vasemman alakulman (x 20–240): pysytään sen oikealla puolella
	return maxf(minf(720.0, vs.x - 520.0), minf(480.0, vs.x - 40.0))


## say-laatikon yläreunan etäisyys näytön alareunasta (HUD siirtää kehotteen tämän yläpuolelle).
func say_top() -> float:
	return _vs().y - _box_rect().position.y


func _portrait_w() -> float:
	if _tex == null:
		return 0.0
	return 176.0 if _mode == "menu" else 104.0


func _text_w() -> float:
	var pw := _portrait_w()
	return _box_w() - pw - (16.0 if pw > 0.0 else 0.0) - 64.0


func _box_rect() -> Rect2:
	var w := _box_w()
	var text_h := _title_lines.size() * LINE_H
	var h: float
	if _mode == "menu":
		h = 44.0 + text_h + (14.0 + _options.size() * ROW_H if not _options.is_empty() else 0.0) + 34.0
		if _tex:
			h = maxf(h, _portrait_w() + 34.0 + 40.0)
		h = minf(h, _vs().y - 40.0)
		return Rect2((_vs().x - w) * 0.5, _vs().y - 16.0 - h, w, h)
	h = maxf(38.0 + text_h + 16.0, (_portrait_w() + 38.0) if _tex else 0.0)
	return Rect2((_vs().x - w) * 0.5, _vs().y - 16.0 - h, w, h)


# ----------------------------------------------------------------------------
#  SYÖTE (hiiri; näppäimet hoitaa HUD)
# ----------------------------------------------------------------------------
func _on_gui_input(event: InputEvent) -> void:
	if _mode != "menu":
		return
	if event is InputEventMouseMotion:
		var i := _hit((event as InputEventMouseMotion).position)
		if i >= 0 and i != _sel:
			_sel = i
			Sfx.play_ui("step", -14.0, 1.8)
		_hover = i
	elif event is InputEventMouseButton and event.is_pressed() and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if typing():
			skip_typing()
			return
		var i := _hit((event as InputEventMouseButton).position)
		if i >= 0:
			chosen.emit(i)


func _hit(p: Vector2) -> int:
	for i in _rows.size():
		if _rows[i].has_point(p):
			return i
	return -1


# ----------------------------------------------------------------------------
#  TEKSTI
# ----------------------------------------------------------------------------
func _wrap(text: String, max_w: float, max_lines: int) -> PackedStringArray:
	var out: PackedStringArray = []
	for para in text.split("\n"):
		var line := ""
		for word in para.split(" ", false):
			var test := word if line == "" else line + " " + word
			if _sw(test) <= max_w or line == "":
				line = test
			else:
				out.append(line)
				line = word
		out.append(line)
	while out.size() > 1 and out[out.size() - 1].strip_edges() == "":
		out.resize(out.size() - 1)
	if out.size() > max_lines:
		var last := out[max_lines - 1]
		while last.length() > 1 and _sw(last + "…") > max_w:
			last = last.substr(0, last.length() - 1)
		out.resize(max_lines)
		out[max_lines - 1] = last.strip_edges() + "…"
	_chars = 0
	for l in out:
		_chars += l.length()
	return out


func _sw(s: String, fs: int = FS) -> float:
	return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func talk_time() -> float:
	return float(_chars) / CPS + 0.15


# ----------------------------------------------------------------------------
#  PIIRTO
# ----------------------------------------------------------------------------
func _draw() -> void:
	if _mode == "":
		return
	var r := _box_rect()
	# ilmestyminen: liukuu alhaalta, pieni pomppu
	var k := clampf(_t / 0.22, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	var off := Vector2(0.0, (1.0 - e) * 24.0)
	var a := e
	if _mode == "say":
		a *= clampf((_dur + 0.25 - _life) / 0.25, 0.0, 1.0)
	modulate.a = a
	r.position += off
	if _mode == "menu":
		draw_rect(Rect2(Vector2.ZERO, _vs()), Color(0, 0, 0, 0.25 * e))
	var pw := _portrait_w()
	var text_r := Rect2(r.position, Vector2(r.size.x - (pw + 16.0 if pw > 0.0 else 0.0), r.size.y))
	_frame(text_r)
	_draw_text(text_r)
	if pw > 0.0:
		var pr := Rect2(text_r.end.x + 16.0, r.position.y, pw, r.size.y)
		_draw_portrait_panel(pr)


## HUDin tyyli: tumma läpikuultava paneeli, kultainen reunus, pyöristetyt kulmat.
func _panel(r: Rect2, bg: Color = BG, border: Color = Color(GOLD, 0.8), radius: int = 12) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 14
	draw_style_box(sb, r)


func _frame(r: Rect2) -> void:
	_panel(r)
	# hento kultainen viiva yläreunan sisäpuolella
	draw_rect(Rect2(r.position.x + 16.0, r.position.y + 6.0, r.size.x - 32.0, 1.0), Color(GOLD, 0.18))


func _draw_text(r: Rect2) -> void:
	var p := r.grow(-11.0)
	var x := p.position.x + 20.0
	var y := p.position.y + 14.0 + LINE_H - 6.0
	var n := int(_t * CPS)
	for l in _title_lines:
		var part := l.substr(0, clampi(n, 0, l.length()))
		draw_string_outline(_font, Vector2(x, y), part, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, 4, Color(0, 0, 0, 0.7))
		draw_string(_font, Vector2(x, y), part, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, TEXT)
		n -= l.length()
		y += LINE_H
	_rows.clear()
	if _mode == "menu":
		if not _options.is_empty():
			y += 4.0
			draw_line(Vector2(x, y), Vector2(p.end.x - 20.0, y), Color(GOLD, 0.3), 1.0)
			y += 10.0
			var can_show := not typing()
			for i in _options.size():
				var row := Rect2(p.position.x + 10.0, y, p.size.x - 20.0, ROW_H - 2.0)
				_rows.append(row)
				if can_show:
					_draw_option(row, i)
				y += ROW_H
		var hint := "Klikkaa / ↑↓ + Enter / 1–%d    Esc: peruuta" % mini(_options.size(), 9)
		draw_string(_font, Vector2(p.position.x, p.end.y - 9.0), hint, HORIZONTAL_ALIGNMENT_RIGHT, p.size.x - 14.0, 13,
			Color(DIM, 0.75))
	# kirjoituspisteet tai jäljellä oleva aika oikeassa alakulmassa
	if typing():
		for i in 3:
			draw_circle(Vector2(p.end.x - 36.0 + i * 9.0, p.end.y - 12.0 - absf(sin(_t * 9.0 + i)) * 3.0), 2.2, GOLD)
	elif _mode == "say":
		var left := clampf(1.0 - _life / maxf(_dur, 0.01), 0.0, 1.0)
		draw_rect(Rect2(p.position.x + 14.0, p.end.y - 6.0, (p.size.x - 28.0) * left, 2.0), Color(GOLD, 0.45))


## Vastausrivi taukovalikon painikkeiden tyyliin: valittu rivi kullalla, osoitinnuoli heiluu.
func _draw_option(row: Rect2, i: int) -> void:
	var active := i == _sel
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.17, 0.08, 0.95) if active else Color(0.12, 0.13, 0.19, 0.6)
	sb.border_color = GOLD if active else Color(0.35, 0.37, 0.45, 0.5)
	sb.set_border_width_all(2 if active else 1)
	sb.set_corner_radius_all(7)
	draw_style_box(sb, row.grow_individual(-16.0, 0.0, 0.0, 0.0))
	if active:
		var ax := row.position.x + sin(_t * 8.0) * 3.0
		var ay := row.position.y + row.size.y * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(ax, ay - 6), Vector2(ax + 9, ay), Vector2(ax, ay + 6)]), GOLD)
	# numero
	var badge := Rect2(row.position.x + 24.0, row.position.y + 5.0, 22.0, row.size.y - 10.0)
	var bs := StyleBoxFlat.new()
	bs.bg_color = GOLD if active else Color(0.18, 0.19, 0.26)
	bs.border_color = Color(0.45, 0.47, 0.55)
	bs.set_border_width_all(0 if active else 1)
	bs.set_corner_radius_all(4)
	draw_style_box(bs, badge)
	draw_string(_font, Vector2(badge.position.x, badge.position.y + 15.0), str(i + 1) if i < 9 else "", HORIZONTAL_ALIGNMENT_CENTER,
		badge.size.x, 14, BG if active else GOLD)
	var tx := badge.end.x + 12.0
	var max_w := row.end.x - tx - 8.0
	var text := str(_options[i])
	var fs := FS - 1
	while fs > 13 and _sw(text, fs) > max_w:
		fs -= 1
	draw_string(_font, Vector2(tx, row.position.y + row.size.y * 0.5 + 7.0), text, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs,
		GOLD if active else TEXT)


## Oikea paneeli: sama tumma kultareunainen paneeli, iso kasvokuva ja nimilappu alla.
func _draw_portrait_panel(r: Rect2) -> void:
	_panel(r)
	var name_h := 28.0
	var side := minf(r.size.x - 22.0, r.size.y - name_h - 30.0)
	# kuva + nimilappu pystysuunnassa keskelle paneelia
	var top := r.position.y + maxf((r.size.y - side - 10.0 - name_h) * 0.5, 11.0)
	var pic := Rect2(r.position.x + (r.size.x - side) * 0.5, top, side, side)
	# tausta: iltakaupungin sininen ja ikkunavalot (kuten puhelun kasvokuvassa)
	var ps0 := StyleBoxFlat.new()
	ps0.bg_color = Color(0.22, 0.3, 0.42)
	ps0.set_corner_radius_all(8)
	draw_style_box(ps0, pic)
	var px := pic.size.x / 12.0
	for k in 4:
		var bh := px * (3.0 + float((k * 5) % 4))
		var bx := pic.position.x + px * (0.5 + k * 3.0)
		draw_rect(Rect2(bx, pic.end.y - bh - px * 2.0, px * 2.4, bh), Color(0.14, 0.19, 0.28))
		draw_rect(Rect2(bx + px * 0.6, pic.end.y - bh - px * 1.2, px * 0.5, px * 0.5), Color(GOLD, 0.6))
	if _tex:
		var talking := typing()
		var bob := Vector2(0.0, sin(_t * 9.0) * px * 0.15 if talking else sin(_t * 1.6) * px * 0.08)
		var dest := Rect2(pic.position + bob, pic.size)
		draw_texture_rect_region(_tex, dest, SRC)
		var ps := dest.size.x / SRC.size.x
		if _blink_t < 0.0:
			for eye: Rect2 in EYES:
				draw_rect(Rect2(_to_dest(eye.position, dest), eye.size * ps), _skin)
		if talking:
			var open := absf(sin(_t * 13.0)) * (0.6 + 0.4 * absf(sin(_t * 3.7)))
			if open > 0.2:
				var c := _to_dest(MOUTH, dest)
				var mw := 1.9 * ps
				draw_rect(Rect2(c.x - mw * 0.5, c.y - ps * 0.3, mw, ps * 0.6), _skin.darkened(0.15))
				draw_rect(Rect2(c.x - mw * 0.4, c.y - ps * 0.2, mw * 0.8, maxf(open * 1.3, 0.35) * ps), Color(0.35, 0.08, 0.1))
				if open > 0.6:
					draw_rect(Rect2(c.x - mw * 0.3, c.y - ps * 0.2, mw * 0.6, ps * 0.35), Color(0.95, 0.93, 0.88))
	# kuvan reunus: kultainen puhuessa, vaalea muuten (kuten pienessä kasvokuvassa)
	var fb := StyleBoxFlat.new()
	fb.draw_center = false
	fb.border_color = GOLD if typing() else Color(0.85, 0.82, 0.7)
	fb.set_border_width_all(2)
	fb.set_corner_radius_all(8)
	# keinunta voi viedä kuvaa reunan yli: peitetään ohut kaistale paneelin värillä
	draw_rect(Rect2(pic.position.x, pic.position.y - 4.0, pic.size.x, 4.0), BG)
	draw_rect(Rect2(pic.position.x, pic.end.y, pic.size.x, 4.0), BG)
	draw_style_box(fb, pic.grow(1.0))
	# nimilappu
	var fs := 16
	while fs > 11 and _sw(_speaker, fs) > r.size.x - 34.0:
		fs -= 1
	var nw := minf(_sw(_speaker, fs) + 28.0, r.size.x - 14.0)
	var nr := Rect2(r.position.x + (r.size.x - nw) * 0.5, minf(pic.end.y + 10.0, r.end.y - name_h - 8.0), nw, name_h)
	var ns := StyleBoxFlat.new()
	ns.bg_color = Color(0.04, 0.04, 0.07, 0.9)
	ns.border_color = Color(GOLD, 0.5)
	ns.set_border_width_all(1)
	ns.set_corner_radius_all(6)
	draw_style_box(ns, nr)
	draw_string(_font, Vector2(nr.position.x, nr.position.y + 19.0), _speaker, HORIZONTAL_ALIGNMENT_CENTER, nr.size.x, fs, GOLD)


func _to_dest(src: Vector2, area: Rect2) -> Vector2:
	return area.position + (src - SRC.position) / SRC.size * area.size


func _sample_skin(tex: Texture2D) -> Color:
	if tex == null:
		return _skin
	var img := tex.get_image()
	if img == null or img.is_empty():
		return _skin
	if img.is_compressed():
		img.decompress()
	return img.get_pixelv(Vector2i(int(12.0 * img.get_width() / 32.0), int(13.0 * img.get_height() / 32.0)))
