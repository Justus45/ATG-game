extends CanvasLayer
## Lankapuhelimen puhelu: piirretty puhelunäkymä (ei labeleita).
##   vasen   soittajan kasvokuva (hahmon HD-kuva suurennettuna), nimi, puhelun kesto
##           ja puheen tahdissa liikkuva äänipalkki
##   oikea   puhekupla, teksti kirjoituskoneena, sivupallot
## E / välilyönti / Enter / hiiri: jatka (ensimmäinen painallus näyttää koko sivun).
## Esc: lopeta puhelu. Peli on pysäytetty puhelun ajan.
## Home.gd luo tämän: caller, pages, portrait (Texture2D).

signal finished

const GOLD := Color(1.0, 0.82, 0.3)
const TEXT := Color(0.93, 0.93, 0.97)
const DIM := Color(0.6, 0.62, 0.7)
const RED := Color(0.8, 0.15, 0.14)
const CPS := 42.0

var caller := ""
var pages: Array = []
var portrait: Texture2D

var _view: Control
var _font: Font
var _page := 0
var _t := 0.0          ## aika nykyisellä sivulla
var _total := 0.0
var _was_paused := false
var _out := -1.0


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("phone_call")
	_font = ThemeDB.fallback_font
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.draw.connect(_draw_view)
	add_child(_view)
	_was_paused = get_tree().paused
	get_tree().paused = true
	Sfx.play_ui("clink", -6.0, 0.7)


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _out >= 0.0:
		_out += delta
		_view.modulate.a = clampf(1.0 - _out / 0.3, 0.0, 1.0)
		if _out >= 0.3:
			get_tree().paused = _was_paused
			finished.emit()
			queue_free()
			return
	_view.queue_redraw()


func _typing() -> bool:
	return _page < pages.size() and _t * CPS < str(pages[_page]).length()


func _input(event: InputEvent) -> void:
	var go := false
	var stop := false
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_ESCAPE:
			stop = true
		elif k in [KEY_E, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			go = true
	elif event is InputEventMouseButton and event.is_pressed():
		go = true
	if not go and not stop:
		return
	get_viewport().set_input_as_handled()
	if _out >= 0.0:
		return
	if stop:
		_hang_up()
	elif _typing():
		_t = 999.0
	elif _page < pages.size() - 1:
		_page += 1
		_t = 0.0
	else:
		_hang_up()


func _hang_up() -> void:
	Sfx.play_ui("clink", -6.0, 0.6)
	_out = 0.0


# ----------------------------------------------------------------------------
#  PIIRTO
# ----------------------------------------------------------------------------
func _draw_view() -> void:
	var vs := _view.size
	_view.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	var w := minf(700.0, vs.x - 40.0)
	var left_w := 170.0
	var text_w := w - left_w - 64.0
	var txt := str(pages[_page]) if _page < pages.size() else ""
	var fs := 18
	var full_h := _font.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, text_w - 32.0, fs).y
	var h := clampf(maxf(250.0, full_h + 150.0), 250.0, vs.y - 40.0)
	var r := Rect2((vs.x - w) * 0.5, (vs.y - h) * 0.5, w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.1, 0.97)
	sb.border_color = Color(GOLD, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	_view.draw_style_box(sb, r)

	# yläpalkki: luuri-ikoni ja "PUHELU"
	var head := Rect2(r.position + Vector2(2, 2), Vector2(w - 4, 34))
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.14, 0.12, 0.08)
	hs.corner_radius_top_left = 12
	hs.corner_radius_top_right = 12
	_view.draw_style_box(hs, head)
	_handset(head.position + Vector2(22, 17), 1.0, GOLD)
	_view.draw_string(_font, head.position + Vector2(40, 23), "PUHELU  ·  LANKAPUHELIN", HORIZONTAL_ALIGNMENT_LEFT, w * 0.6, 14, GOLD)
	var secs := int(_total)
	_view.draw_string(_font, head.position + Vector2(0, 23), "%02d:%02d" % [secs / 60, secs % 60], HORIZONTAL_ALIGNMENT_RIGHT,
		head.size.x - 16.0, 14, DIM)

	# vasen: kasvokuva
	var pc := Vector2(r.position.x + 24.0 + left_w * 0.5, r.position.y + 50.0 + 60.0)
	var frame := Rect2(pc - Vector2(60, 60), Vector2(120, 120))
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.22, 0.3, 0.42)
	fsb.border_color = Color(0.9, 0.85, 0.7)
	fsb.set_border_width_all(3)
	fsb.set_corner_radius_all(60)
	_view.draw_style_box(fsb, frame)
	if portrait:
		# pää ja hartiat 16x16-kuvasta (HD 32x32), suurennettuna
		var bob := sin(_total * 9.0) * 1.5 if _typing() else 0.0
		_view.draw_texture_rect_region(portrait, Rect2(pc + Vector2(-54, -50 + bob), Vector2(108, 108)), Rect2(2.5, 1.0, 11.0, 11.0))
	_view.draw_string(_font, Vector2(r.position.x + 24.0, frame.end.y + 26.0), caller, HORIZONTAL_ALIGNMENT_CENTER, left_w, 16, TEXT)
	# äänipalkki: liikkuu puheen tahdissa
	var bars := 9
	var bw := 8.0
	var bx := r.position.x + 24.0 + (left_w - bars * (bw + 3.0)) * 0.5
	var by := frame.end.y + 50.0
	for i in bars:
		var a := 0.15
		if _typing():
			a = 0.25 + 0.75 * absf(sin(_total * (7.0 + i * 1.3) + i))
		var bh := 4.0 + 18.0 * a
		_view.draw_rect(Rect2(bx + i * (bw + 3.0), by - bh * 0.5, bw, bh), Color(GOLD, 0.35 + 0.6 * a))

	# oikea: puhekupla
	var bubble := Rect2(r.position.x + left_w + 40.0, r.position.y + 54.0, text_w, h - 54.0 - 54.0)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.16, 0.18, 0.25)
	bsb.set_corner_radius_all(12)
	_view.draw_style_box(bsb, bubble)
	# kuplan nokka kohti kasvoja
	_view.draw_colored_polygon(PackedVector2Array([bubble.position + Vector2(0, 40), bubble.position + Vector2(-14, 52),
		bubble.position + Vector2(0, 62)]), Color(0.16, 0.18, 0.25))
	var n := clampi(int(_t * CPS), 0, txt.length())
	_view.draw_multiline_string(_font, bubble.position + Vector2(16, 16 + fs), txt.substr(0, n), HORIZONTAL_ALIGNMENT_LEFT,
		bubble.size.x - 32.0, fs, -1, TEXT)

	# sivupallot ja ohje
	var dots_y := r.end.y - 30.0
	var dx := bubble.position.x
	for i in pages.size():
		_view.draw_circle(Vector2(dx + 6.0 + i * 16.0, dots_y), 4.5 if i == _page else 3.5, GOLD if i <= _page else Color(DIM, 0.5))
	var hint := "E / välilyönti: jatka" if (_page < pages.size() - 1 or _typing()) else "E / välilyönti: lopeta puhelu"
	_view.draw_string(_font, Vector2(bubble.position.x, dots_y + 5.0), hint + "    Esc: lopeta", HORIZONTAL_ALIGNMENT_RIGHT,
		bubble.size.x, 13, Color(DIM, 0.6 + 0.3 * sin(_total * 3.0)))


## Puhelimen luuri -kuvake (kaksi kuulokekuppia ja kaari).
func _handset(c: Vector2, s: float, col: Color) -> void:
	_view.draw_arc(c + Vector2(0, 5) * s, 9.0 * s, PI * 1.15, PI * 1.85, 12, col, 3.5 * s)
	_view.draw_circle(c + Vector2(-7.5, 1.5) * s, 3.2 * s, col)
	_view.draw_circle(c + Vector2(7.5, 1.5) * s, 3.2 * s, col)
