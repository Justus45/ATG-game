extends "res://scripts/ui/PauseMenu.gd"
## Aloitusvalikko: avautuu ensimmäisenä, kun peli käynnistetään (Game._attach).
## Taustalla animoitu yökaupunki ja ATG-neon (CityBackdrop.gd), peli on pysäytetty.
##   Jatka peliä (vain jos tallennus on olemassa; näyttää päivän ja rahat)
##   Uusi peli (varmistus, jos tallennus korvataan) · Asetukset · Lopeta peli
## Asetussivu ja painikkeiden ulkoasu periytyvät taukovalikosta (PauseMenu.gd).

const CITY_BACKDROP := preload("res://scripts/ui/CityBackdrop.gd")

var _backdrop = CITY_BACKDROP.new()
var _t := 0.0
var _has_save := false
var _save_info := ""


func _ready() -> void:
	super._ready()
	layer = 70
	add_to_group("main_menu")
	Sfx.bgm_override = "menu"
	_backdrop.sign_delay = 0.4
	_backdrop.sign_max_bottom = 0.41   # painikkeet alkavat 0.44 korkeudelta
	var d: Dictionary = Game._read_save()
	_has_save = not d.is_empty()
	if _has_save:
		_save_info = "Päivä %d  ·  %d $" % [int(d.get("day", 1)), int(d.get("money", 0)) + int(d.get("bank", 0))]
	var hud := get_tree().current_scene.get_node_or_null("Hud") as CanvasLayer
	if hud:
		hud.visible = false
	_open = true
	_page = "start"
	_sel = 0
	_was_paused = false
	get_tree().paused = true
	_view.show()


func _process(delta: float) -> void:
	_t += delta
	super._process(delta)


func _items() -> Array:
	match _page:
		"start":
			var out: Array = []
			if _has_save:
				out.append("Jatka peliä")
			out.append_array(["Uusi peli", "Asetukset", "Lopeta peli"])
			return out
		"settings":
			return ["Takaisin"]
		"new_confirm":
			return ["Aloita uusi peli", "Peruuta"]
	return []


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	var k := (event as InputEventKey).physical_keycode
	var n := _items().size()
	match k:
		KEY_ESCAPE:
			if _page != "start":
				_go("start")
		KEY_UP, KEY_W:
			_sel = (_sel - 1 + n) % n
		KEY_DOWN, KEY_S:
			_sel = (_sel + 1) % n
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E:
			_activate(_sel)


func _activate(i: int) -> void:
	var item := str(_items()[i]) if i >= 0 and i < _items().size() else ""
	match item:
		"Jatka peliä":
			_start(true)
		"Uusi peli":
			if _has_save:
				_go("new_confirm")
			else:
				_start(false)
		"Aloita uusi peli":
			_start(false)
		"Peruuta", "Takaisin":
			_go("start")
		"Asetukset":
			_go("settings")
		"Lopeta peli":
			get_tree().quit()


## Kenttä ladataan uudelleen joko tallennuksesta tai puhtaana (Game hoitaa).
func _start(load_save: bool) -> void:
	_open = false
	Sfx.bgm_override = ""
	get_tree().paused = false
	if load_save:
		Game.load_game()
	else:
		Game.new_game()


# ----------------------------------------------------------------------------
#  PIIRTO
# ----------------------------------------------------------------------------
func _draw_view() -> void:
	var vs := _view.size
	_backdrop.draw(_view, vs, _t)
	_rects.clear()
	match _page:
		"start":
			_draw_start(vs)
		"new_confirm":
			_view.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.5))
			_draw_list(vs, "UUSI PELI", "Vanha tallennus (%s) korvataan." % _save_info, 460.0)
		"settings":
			_view.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
			_draw_settings(vs)
	_view.draw_string(_font, Vector2(0, vs.y - 18.0), "Nuolet / hiiri: valitse    Enter: hyväksy    Esc: takaisin",
		HORIZONTAL_ALIGNMENT_CENTER, vs.x, 13, Color(DIM, 0.7))
	# versio oikeaan alakulmaan
	_view.draw_string(_font, Vector2(vs.x - 110.0, vs.y - 18.0), "ATG v%s" % str(ProjectSettings.get_setting("application/config/version", "1.0")),
		HORIZONTAL_ALIGNMENT_RIGHT, 100.0, 12, Color(DIM, 0.6))
	# häivytys sisään
	if _t < 0.8:
		_view.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 1.0 - _t / 0.8))


## Painikkeet neonkyltin alle; "Jatka" näyttää tallennuksen päivän ja rahat.
func _draw_start(vs: Vector2) -> void:
	var items := _items()
	var w := minf(400.0, vs.x - 40.0)
	var btn_h := 46.0
	var gap := 10.0
	var h := items.size() * (btn_h + gap) + 28.0
	var top := clampf(vs.y * 0.44, 20.0, vs.y - h - 40.0)
	var r := Rect2((vs.x - w) * 0.5, top, w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.035, 0.07, 0.85)
	sb.border_color = Color(GOLD, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 14
	_view.draw_style_box(sb, r)
	var y := r.position.y + 14.0
	for i in items.size():
		var br := Rect2(r.position.x + 20.0, y, w - 40.0, btn_h)
		var label := str(items[i])
		if label == "Jatka peliä":
			_button(br, "", i == _sel)
			var active := i == _sel
			_view.draw_string(_font, Vector2(br.position.x + 18.0, br.position.y + 29.0), label, HORIZONTAL_ALIGNMENT_LEFT,
				br.size.x * 0.55, 19, GOLD if active else TEXT)
			_view.draw_string(_font, Vector2(br.position.x, br.position.y + 28.0), _save_info, HORIZONTAL_ALIGNMENT_RIGHT,
				br.size.x - 16.0, 13, DIM)
		else:
			_button(br, label, i == _sel)
		_rects.append(br)
		y += btn_h + gap
