extends CanvasLayer
## Taukovalikko (Esc): peli pysähtyy ja aukeaa valikko.
##   Jatka peliä · Tallenna peli · Asetukset (näppäimet) · Lopeta peli
## Kaikki piirretään yhdellä Control-solmulla (_draw), mitat lasketaan näytön koosta,
## joten mikään ei mene reunojen yli. Hiiri ja näppäimistö (nuolet/WS, Enter, Esc) toimivat.
## Game liittää tämän kenttään.

const GOLD := Color(1.0, 0.82, 0.3)
const TEXT := Color(0.93, 0.93, 0.97)
const DIM := Color(0.6, 0.62, 0.7)

## [toiminto, näppäin]
const KEYS := [
	["Liiku / aja", "WASD tai nuolet"],
	["Juokse", "Shift (pidä pohjassa)"],
	["Toiminto: ovet, osto, autoon / autosta", "E"],
	["Ammu / lyö", "Hiiren vasen tai välilyönti"],
	["Torju", "F tai hiiren oikea"],
	["Heitä kranaatti", "Q tai hiiren keskipainike"],
	["Tupakka: sytytä / vedä henkonen (pidä pohjassa)", "C"],
	["Kevlarliivi: riisu / pue", "V"],
	["Sido nippusiteillä (ohikulkija, kaupassa panttivangit)", "Z"],
	["Pudota ase", "G"],
	["Ryöstä (ase kädessä)", "R"],
	["Auto: kaasu / jarru (pysähdyksissä ympäri)", "Nuoli eteen / taakse"],
	["Auto: peruutus", "Shift + taaksepäin"],
	["Auto: käännös / kaistanvaihto", "Sivunuoli / vino nuoli"],
	["Käsijarru (autossa)", "Shift"],
	["Taksivuoro (vain omassa taksissa)", "T"],
	["Maksa takuut (putkassa)", "B"],
	["Kaupungin kartta", "M"],
	["Valikon valinnat", "1–9"],
	["Tallenna / lataa", "F5 / F9"],
	["Uusi peli", "Shift + F9"],
	["Tauko ja tämä valikko", "Esc"],
]

var _view: Control
var _font: Font
var _open := false
var _page := "main"          # "main", "settings", "quit"
var _sel := 0
var _hover := -1
var _rects: Array[Rect2] = []
var _was_paused := false
var _note := ""
var _note_t := 0.0


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.draw.connect(_draw_view)
	_view.gui_input.connect(_on_gui_input)
	_view.hide()
	add_child(_view)


func _items() -> Array:
	match _page:
		"main":
			return ["Jatka peliä", "Tallenna peli", "Asetukset", "Lopeta peli"]
		"settings":
			return ["Takaisin"]
		"quit":
			return ["Tallenna ja lopeta", "Lopeta tallentamatta", "Peruuta"]
	return []


# ----------------------------------------------------------------------------
#  AUKAISU JA SULKEMINEN
# ----------------------------------------------------------------------------
func _blocked() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return true
	if get_tree().get_first_node_in_group("intro") != null or get_tree().get_first_node_in_group("main_menu") != null \
			or get_tree().get_first_node_in_group("phone_call") != null:
		return true
	var map := scene.get_node_or_null("CityMap")
	if map and Game.flag(map, "_open"):
		return true
	var hud := scene.get_node_or_null("Hud")
	if hud and hud.has_method("menu_open") and hud.menu_open():
		return true
	var games := get_tree().get_first_node_in_group("bar_games")
	if games and games.has_method("busy") and games.busy():
		return true
	return false


func open() -> void:
	if _open or _blocked():
		return
	_open = true
	_page = "main"
	_sel = 0
	_note = ""
	_was_paused = get_tree().paused
	get_tree().paused = true
	_view.show()
	_view.queue_redraw()


func close() -> void:
	if not _open:
		return
	_open = false
	_view.hide()
	get_tree().paused = _was_paused


func _process(delta: float) -> void:
	if _open:
		_note_t = maxf(_note_t - delta, 0.0)
		_view.queue_redraw()


# ----------------------------------------------------------------------------
#  SYÖTE
# ----------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var k := (event as InputEventKey).physical_keycode
	if not _open:
		if k == KEY_ESCAPE and not _blocked():
			get_viewport().set_input_as_handled()
			open()
		return
	get_viewport().set_input_as_handled()
	var n := _items().size()
	match k:
		KEY_ESCAPE:
			if _page == "main":
				close()
			else:
				_go("main")
		KEY_UP, KEY_W:
			_sel = (_sel - 1 + n) % n
		KEY_DOWN, KEY_S:
			_sel = (_sel + 1) % n
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E:
			_activate(_sel)
	_view.queue_redraw()


func _on_gui_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseMotion:
		_hover = _hit((event as InputEventMouseMotion).position)
		if _hover >= 0:
			_sel = _hover
	elif event is InputEventMouseButton and event.is_pressed() and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var i := _hit((event as InputEventMouseButton).position)
		if i >= 0:
			_activate(i)


func _hit(p: Vector2) -> int:
	for i in _rects.size():
		if _rects[i].has_point(p):
			return i
	return -1


func _go(page: String) -> void:
	_page = page
	_sel = 0
	_hover = -1
	_note = ""


func _activate(i: int) -> void:
	match _page:
		"main":
			match i:
				0:
					close()
				1:
					if Game.can_save():
						Game.save_game()
						_flash("Peli tallennettu.")
					else:
						_flash("Ei voi tallentaa nyt (jahti, putka tai keikka kesken).")
				2:
					_go("settings")
				3:
					_go("quit")
		"settings":
			_go("main")
		"quit":
			match i:
				0:
					if Game.can_save():
						Game.save_game()
						get_tree().quit()
					else:
						_flash("Ei voi tallentaa nyt. Lopeta tallentamatta tai jatka peliä.")
				1:
					get_tree().quit()
				2:
					_go("main")


func _flash(text: String) -> void:
	_note = text
	_note_t = 3.0


# ----------------------------------------------------------------------------
#  PIIRTO
# ----------------------------------------------------------------------------
func _panel(r: Rect2) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.1, 0.96)
	sb.border_color = Color(GOLD, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 16
	_view.draw_style_box(sb, r)


func _draw_view() -> void:
	var vs := _view.size
	_view.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
	_rects.clear()
	match _page:
		"main":
			_draw_list(vs, "TAUKO", "Peli on pysäytetty", 420.0)
		"quit":
			_draw_list(vs, "LOPETA PELI", "Tallentamaton edistyminen menetetään.", 460.0)
		"settings":
			_draw_settings(vs)


## Otsikko + allekkain olevat painikkeet.
func _draw_list(vs: Vector2, title: String, sub: String, width: float) -> void:
	var items := _items()
	var w := minf(width, vs.x - 40.0)
	var btn_h := 44.0
	var gap := 10.0
	var head := 92.0
	var note_h := 34.0 if _note != "" and _note_t > 0.0 else 0.0
	var h := head + items.size() * (btn_h + gap) + 14.0 + note_h
	var r := Rect2((vs.x - w) * 0.5, (vs.y - h) * 0.5, w, h)
	_panel(r)
	_view.draw_string(_font, r.position + Vector2(0, 44), title, HORIZONTAL_ALIGNMENT_CENTER, w, 30, GOLD)
	_view.draw_string(_font, r.position + Vector2(0, 70), sub, HORIZONTAL_ALIGNMENT_CENTER, w, 14, DIM)
	var y := r.position.y + head
	for i in items.size():
		var br := Rect2(r.position.x + 28.0, y, w - 56.0, btn_h)
		_button(br, str(items[i]), i == _sel)
		_rects.append(br)
		y += btn_h + gap
	if note_h > 0.0:
		_view.draw_string(_font, Vector2(r.position.x + 16.0, y + 18.0), _note, HORIZONTAL_ALIGNMENT_CENTER, w - 32.0, 14,
			Color(GOLD, clampf(_note_t, 0.0, 1.0)))


func _button(r: Rect2, text: String, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.17, 0.08, 0.95) if active else Color(0.12, 0.13, 0.19, 0.95)
	sb.border_color = GOLD if active else Color(0.35, 0.37, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	_view.draw_style_box(sb, r)
	_view.draw_string(_font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 7.0), text, HORIZONTAL_ALIGNMENT_CENTER,
		r.size.x, 19, GOLD if active else TEXT)


func _draw_settings(vs: Vector2) -> void:
	# Näppäimiä on paljon: jos ne eivät mahdu yhteen sarakkeeseen, käytetään kahta
	var head := 92.0
	var row_h := 25.0
	var btn_h := 44.0
	var avail := vs.y - 40.0 - head - 20.0 - btn_h - 24.0
	var cols := 1 if KEYS.size() * row_h <= avail else 2
	var per_col := ceili(float(KEYS.size()) / float(cols))
	if per_col * row_h > avail:
		row_h = maxf(18.0, floorf(avail / float(per_col)))
	var w := minf(720.0 * cols, vs.x - 40.0)
	var h := minf(head + per_col * row_h + 20.0 + btn_h + 24.0, vs.y - 40.0)
	var r := Rect2((vs.x - w) * 0.5, (vs.y - h) * 0.5, w, h)
	_panel(r)
	_view.draw_string(_font, r.position + Vector2(0, 44), "ASETUKSET", HORIZONTAL_ALIGNMENT_CENTER, w, 30, GOLD)
	_view.draw_string(_font, r.position + Vector2(0, 70), "Näppäimet", HORIZONTAL_ALIGNMENT_CENTER, w, 15, DIM)
	var cw := w / float(cols)
	var fs := 15 if row_h >= 24.0 else 13
	for i in KEYS.size():
		var c := int(i / per_col)
		var ri := i % per_col
		var x0 := r.position.x + c * cw
		var y := r.position.y + head + ri * row_h
		var split_x := cw * 0.56
		if ri % 2 == 0:
			_view.draw_rect(Rect2(x0 + 20.0, y, cw - 40.0, row_h), Color(1, 1, 1, 0.04))
		var row: Array = KEYS[i]
		var label := str(row[0])
		var lfs := TextFit.fit_size(_font, label, split_x - 40.0, fs)
		_view.draw_string(_font, Vector2(x0 + 32.0, y + row_h * 0.5 + 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, TEXT)
		_key_caps(Vector2(x0 + split_x, y + (row_h - 19.0) * 0.5), str(row[1]), cw - split_x - 32.0)
	var br := Rect2(r.position.x + (w - 220.0) * 0.5, r.end.y - btn_h - 16.0, 220.0, btn_h)
	_button(br, "Takaisin", true)
	_rects.append(br)


## Näppäinteksti pienissä "näppäinhatuissa": yksittäiset näppäimet laatikoituina.
func _key_caps(pos: Vector2, text: String, max_w: float) -> void:
	var fs := 13
	var x := pos.x
	var words := text.split(" ")
	for word in words:
		var is_key := word.length() <= 3 or word in ["Shift", "Esc", "WASD", "F5", "F9"]
		var ww := _font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if x + ww + 10.0 > pos.x + max_w:
			break
		if is_key and word not in ["tai", "/", "+", "(pidä", "pohjassa)"]:
			var kr := Rect2(x, pos.y, ww + 10.0, 19.0)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.18, 0.19, 0.26)
			sb.border_color = Color(0.45, 0.47, 0.55)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(4)
			_view.draw_style_box(sb, kr)
			_view.draw_string(_font, Vector2(x + 5.0, pos.y + 14.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, GOLD)
			x += ww + 16.0
		else:
			_view.draw_string(_font, Vector2(x, pos.y + 14.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DIM)
			x += ww + 6.0
