extends CanvasLayer
## Uuden pelin alkuintro. Kaikki piirretään yhdellä Control-solmulla (_draw): ei labeleita,
## ja jokainen kuvio/teksti mitoitetaan näytön koosta, joten mikään ei mene reunojen yli.
##
##   0 kaupunki   yökaupunki: siluetit, ikkunavalot, kuu, sade, autot ja välkkyvä ATG-neon
##   1 herätys    pelimaailma näkyy taustalla, silmäluomet raottuvat räpsien, puhelin värisee
##   2 puhelin    Hain viestit kuplina (uusin alhaalla); puhelin liukuu sisään ja ulos
##
## Välilyönti / Enter / hiiri: jatka.  Esc: ohita koko intro.
## Peli on pysäytetty ja HUD piilossa intron ajan.

signal finished

const CITY_BACKDROP := preload("res://scripts/ui/CityBackdrop.gd")

var due1 := 7
var due2 := 14
var debt := 4000
var inst1 := 1500

const GOLD := Color(1.0, 0.82, 0.3)
const NEON := Color(1.0, 0.3, 0.55)
const INK := Color(0.02, 0.02, 0.04)
const TEXT := Color(0.93, 0.93, 0.97)
const DIM := Color(0.6, 0.62, 0.7)
const CITY_TIME := 6.5
const WAKE_TIME := 4.4
const BUBBLE_GAP := 1.5
const OUT_TIME := 0.6

var _view: Control
var _font: Font
var _phase := 0
var _t := 0.0
var _total := 0.0
var _shown := 0
var _bubble_t := 0.0
var _out := -1.0
var _was_paused := false
var _hud: CanvasLayer
var _buzzed := 0
# kaupungin data normalisoituna (0..1), luodaan kerran
var _backdrop = CITY_BACKDROP.new()


func _messages() -> Array:
	return [
		"Huomenta, nukkumatti.",
		"Velkasi on %d $. Korkoineen. Mä oon reilu." % debt,
		"Eka erä %d $ päivään %d mennessä. Loput päivään %d." % [inst1, due1, due2],
		"Maksa Kallelle. Se notkuu baarin kulmalla.",
		"Raipe ja Late tietää missä asut. Ne on mukavia poikia. Ainakin aluksi. :)",
	]


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("intro")
	Sfx.bgm_override = "cutscene"
	_font = ThemeDB.fallback_font
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.draw.connect(_draw_view)
	add_child(_view)
	_was_paused = get_tree().paused
	get_tree().paused = true
	_hud = get_tree().current_scene.get_node_or_null("Hud") as CanvasLayer
	if _hud:
		_hud.visible = false


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _out >= 0.0:
		_out += delta
		_view.modulate.a = clampf(1.0 - _out / OUT_TIME, 0.0, 1.0)
		if _out >= OUT_TIME:
			_finish()
			return
	match _phase:
		0:
			if _t > CITY_TIME:
				_next()
		1:
			if _buzzed == 0 and _t > 1.4 or _buzzed == 1 and _t > 2.9:
				_buzzed += 1
				Sfx.play_ui("phone", -10.0, 0.8)
			if _t > WAKE_TIME:
				_next()
		2:
			if _shown < _messages().size():
				_bubble_t += delta
				if _bubble_t >= BUBBLE_GAP:
					_bubble_t = 0.0
					_show_bubble()
	_view.queue_redraw()


func _input(event: InputEvent) -> void:
	var go := false
	var skip := false
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_ESCAPE:
			skip = true
		elif k == KEY_SPACE or k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_E:
			go = true
	elif event is InputEventMouseButton and event.is_pressed():
		go = true
	if not go and not skip:
		return
	get_viewport().set_input_as_handled()
	if skip:
		_begin_out()
	elif _out < 0.0:
		if _phase == 2 and _shown < _messages().size():
			while _shown < _messages().size():
				_show_bubble()
		else:
			_next()


func _next() -> void:
	if _phase >= 2:
		_begin_out()      # puhelin liukuu pois ja intro häivytetään
		return
	_phase += 1
	_t = 0.0
	if _phase == 2:
		_bubble_t = BUBBLE_GAP - 0.5


func _show_bubble() -> void:
	_shown += 1
	Sfx.play_ui("phone", -8.0, 1.0 + 0.05 * _shown)


func _begin_out() -> void:
	if _out < 0.0:
		_out = 0.0


func _finish() -> void:
	Sfx.bgm_override = ""
	get_tree().paused = _was_paused
	if _hud:
		_hud.visible = true
	finished.emit()
	queue_free()


# ----------------------------------------------------------------------------
#  PIIRTO
# ----------------------------------------------------------------------------
func _draw_view() -> void:
	var vs := _view.size
	match _phase:
		0:
			_draw_city(vs)
		1:
			_draw_wake(vs)
		_:
			_draw_phone(vs)
	var hint := "Välilyönti: jatka    Esc: ohita intro"
	var hc := Color(DIM, 0.55) if _phase != 1 else Color(1, 1, 1, 0.45)
	_view.draw_string(_font, Vector2(0, vs.y - 18.0), hint, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 14, hc)


## --- 0: yökaupunki ---
func _draw_city(vs: Vector2) -> void:
	_backdrop.draw(_view, vs, _t)
	# häivytys sisään ja ulos
	var fade := clampf(1.0 - _t / 1.0, 0.0, 1.0) + clampf((_t - (CITY_TIME - 0.7)) / 0.7, 0.0, 1.0)
	if fade > 0.0:
		_view.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, clampf(fade, 0.0, 1.0)))


## --- 1: herääminen silmäluomien läpi ---
func _eye_open(t: float) -> float:
	# avautuminen 0..1 räpsien: [aika, avautuma]
	var keys := [[0.0, 0.0], [0.6, 0.0], [1.1, 0.3], [1.45, 0.02], [2.2, 0.62], [2.5, 0.12], [3.4, 1.05], [WAKE_TIME, 1.2]]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t <= float(b[0]):
			var f := clampf((t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), 0.0, 1.0)
			f = f * f * (3.0 - 2.0 * f)
			return lerpf(float(a[1]), float(b[1]), f)
	return 1.2


func _draw_wake(vs: Vector2) -> void:
	var o := _eye_open(_t)
	var cx := vs.x * 0.5
	var cy := vs.y * 0.5
	# sumea, lämmin aamuhämärä joka hälvenee silmien auetessa
	_view.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.12, 0.07, 0.03, 0.55 * clampf(1.0 - o, 0.0, 1.0)))
	# silmäluomet: pystysuikaleina piirretyt kaaret, joiden väli kasvaa avautuman mukaan
	if o < 0.01:
		_view.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0))
	elif o < 1.0:
		var half := o * vs.y * 0.62
		var col_w := 3.0
		var x := 0.0
		while x < vs.x:
			var n := (x + col_w * 0.5 - cx) / (vs.x * 0.62)
			var k := sqrt(maxf(1.0 - n * n, 0.0))
			var gap := half * k
			var top_h := clampf(cy - gap, 0.0, vs.y)
			if top_h > 0.0:
				_view.draw_rect(Rect2(x, 0.0, col_w, top_h), Color(0, 0, 0))
				_view.draw_rect(Rect2(x, top_h - 2.0, col_w, 2.0), Color(0.25, 0.1, 0.08, 0.6))
				_view.draw_rect(Rect2(x, cy + gap, col_w, vs.y - (cy + gap)), Color(0, 0, 0))
			x += col_w
	# reunojen tummuus (vinjetti)
	for k in 6:
		var w := (6 - k) * vs.y * 0.025
		_view.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.07 * (1.0 - clampf(o - 0.6, 0.0, 1.0))), false, w)
	# puhelin värisee lattialla: tärisevät kaaret ruudun alaosassa
	if _t > 1.3:
		var buzz := fmod(_t, 1.5) < 0.6
		if buzz:
			var p := Vector2(cx + vs.x * 0.2 + randf_range(-2.0, 2.0), vs.y * 0.74 + randf_range(-1.5, 1.5))
			for k in 3:
				var rr := 10.0 + k * 9.0
				_view.draw_arc(p, rr, -0.9, 0.9, 10, Color(1, 1, 1, 0.5 - k * 0.12), 2.0)
				_view.draw_arc(p, rr, PI - 0.9, PI + 0.9, 10, Color(1, 1, 1, 0.5 - k * 0.12), 2.0)
			_view.draw_rect(Rect2(p - Vector2(5, 9), Vector2(10, 18)), Color(0.1, 0.1, 0.13))
			_view.draw_rect(Rect2(p - Vector2(3.5, 7), Vector2(7, 12)), Color(0.5, 0.75, 1.0, 0.9))
	# kevyt valkoinen välähdys kun silmät aukeavat kokonaan
	if o > 1.0:
		_view.draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 0.95, 0.85, clampf((1.2 - o) * 0.6, 0.0, 0.12)))


## --- 2: puhelin ---
func _draw_phone(vs: Vector2) -> void:
	var a := clampf(_t / 0.35, 0.0, 1.0)
	_view.draw_rect(Rect2(Vector2.ZERO, vs), Color(INK, 0.72 * a))
	var pw := minf(340.0, vs.x - 80.0)
	var ph := minf(540.0, vs.y - 90.0)
	# liukuu alhaalta sisään (ja ulos häivytyksessä)
	var slide_in := 1.0 - pow(1.0 - clampf(_t / 0.55, 0.0, 1.0), 3.0)
	var slide := (1.0 - slide_in) * vs.y * 0.7
	if _out >= 0.0:
		slide += pow(clampf(_out / OUT_TIME, 0.0, 1.0), 2.0) * vs.y * 0.6
	var body := Rect2((vs.x - pw) * 0.5, (vs.y - ph) * 0.5 - 10.0 + slide, pw, ph)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.12)
	sb.border_color = Color(0.3, 0.3, 0.36)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(26)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	_view.draw_style_box(sb, body)
	var screen := body.grow(-12.0)
	screen.position.y += 14.0
	screen.size.y -= 30.0
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0.13, 0.15, 0.2)
	ss.set_corner_radius_all(14)
	_view.draw_style_box(ss, screen)
	var head := Rect2(screen.position, Vector2(screen.size.x, 44.0))
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.18, 0.2, 0.27)
	hs.corner_radius_top_left = 14
	hs.corner_radius_top_right = 14
	_view.draw_style_box(hs, head)
	_view.draw_circle(head.position + Vector2(24, 22), 13.0, Color(0.35, 0.45, 0.6))
	_view.draw_string(_font, head.position + Vector2(18, 28), "H", HORIZONTAL_ALIGNMENT_CENTER, 12, 16, TEXT)
	_view.draw_string(_font, head.position + Vector2(46, 20), "Hai", HORIZONTAL_ALIGNMENT_LEFT, head.size.x - 110, 17, TEXT)
	_view.draw_string(_font, head.position + Vector2(46, 36), "kirjoittaa..." if _typing() else "paikalla", HORIZONTAL_ALIGNMENT_LEFT, head.size.x - 110, 12, DIM)
	_view.draw_string(_font, head.position + Vector2(0, 27), "9.04", HORIZONTAL_ALIGNMENT_RIGHT, head.size.x - 14, 13, DIM)
	var area := Rect2(screen.position + Vector2(10, head.size.y + 8), Vector2(screen.size.x - 20, screen.size.y - head.size.y - 16))
	var fs := 15
	var max_w := area.size.x * 0.82
	var pad := Vector2(10, 7)
	var y := area.end.y
	if _typing():
		var tb := Rect2(area.position.x, y - 28.0, 54.0, 28.0)
		_bubble_box(tb)
		for k in 3:
			var ph_k := 0.5 + 0.5 * sin(_total * 7.0 - k * 0.9)
			_view.draw_circle(tb.position + Vector2(15 + k * 12, 14), 3.0, Color(DIM, 0.4 + 0.6 * ph_k))
		y -= 28.0 + 8.0
	var msgs := _messages()
	for i in range(_shown - 1, -1, -1):
		var txt: String = msgs[i]
		var sz := _font.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, max_w - pad.x * 2.0, fs)
		var bw := minf(sz.x + pad.x * 2.0, max_w)
		var bh := sz.y + pad.y * 2.0
		if y - bh < area.position.y:
			break
		var r := Rect2(area.position.x, y - bh, bw, bh)
		_bubble_box(r)
		_view.draw_multiline_string(_font, r.position + Vector2(pad.x, pad.y + fs), txt, HORIZONTAL_ALIGNMENT_LEFT,
			bw - pad.x * 2.0, fs, -1, TEXT)
		y -= bh + 8.0


func _typing() -> bool:
	return _phase == 2 and _shown < _messages().size()


func _bubble_box(r: Rect2) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.26, 0.29, 0.38)
	sb.set_corner_radius_all(10)
	sb.corner_radius_bottom_left = 3
	_view.draw_style_box(sb, r)
