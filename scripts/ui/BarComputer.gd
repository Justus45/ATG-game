extends CanvasLayer
## Toimiston tietokone "BaariOS": baarin hallinta tietokoneen näköisenä käyttöliittymänä.
##  - Näyttö reunuksineen, työpöytä taustakuvineen, sovelluskuvakkeet, ikkuna otsikkopalkkeineen
##    ja tehtäväpalkki (Käynnistä, auki oleva sovellus, rahat, kello, Sammuta).
##  - Sovellukset: Kirjanpito (tunnusluvut, tuloskaavio, tuloslaskelma), Päivitykset,
##    Henkilökunta, Hinnoittelu, Tapahtumat, Huolto ja Asetukset (baarin nimi).
##  - Hiirellä käytetään, Esc sulkee ikkunan / sammuttaa koneen.
## BarBusiness.open_computer() luo tämän. Kaikki toiminnot kutsuvat BarBusinessia.

const APPS := [
	["books", "Kirjanpito", Color(0.2, 0.65, 0.35)],
	["upgrades", "Päivitykset", Color(0.95, 0.58, 0.15)],
	["style", "Sisustus", Color(0.2, 0.62, 0.65)],
	["staff", "Henkilökunta", Color(0.25, 0.5, 0.95)],
	["price", "Hinnoittelu", Color(0.75, 0.3, 0.75)],
	["events", "Tapahtumat", Color(0.92, 0.28, 0.35)],
	["care", "Huolto", Color(0.45, 0.52, 0.6)],
	["settings", "Asetukset", Color(0.32, 0.34, 0.45)],
]
const INK := Color(0.12, 0.13, 0.17)
const MUTED := Color(0.42, 0.44, 0.5)
const GOOD := Color(0.13, 0.6, 0.3)
const BAD := Color(0.85, 0.2, 0.2)
const ACCENT := Color(0.16, 0.36, 0.72)

var biz: Node = null
var start_app := ""

var _root: Control
var _monitor: Panel
var _screen: Control
var _icons: GridContainer
var _window: PanelContainer
var _win_title: Label
var _win_icon: ColorRect
var _content: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _taskbar: Panel
var _task_app: Label
var _clock: Label
var _money: Label
var _app := ""
var _tick := 0.0


func _ready() -> void:
	layer = 50
	var p := get_tree().get_first_node_in_group("player")
	if p:
		p.set("menu_locked", true)
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud and hud.has_method("hide_instruction"):
		hud.hide_instruction()
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	Sfx.play_ui("coin", -16.0, 2.2)
	open_app(start_app)


func close() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p:
		p.set("menu_locked", false)
		var spot: Variant = p.get("nearby_portal")
		var hud := get_tree().current_scene.get_node_or_null("Hud")
		if hud and spot != null and is_instance_valid(spot) and spot.has_method("prompt_text"):
			hud.show_instruction(spot.prompt_text())
	queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if _app != "":
				open_app("")
			else:
				close()


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	if _clock:
		_clock.text = "%s  %s\nPäivä %d" % [Game.weekday(), Game.clock_text(), Game.day]
	if _money and biz:
		_money.text = "%d $" % int(biz.money_total())


# ----------------------------------------------------------------------------
#  RAKENNE: näyttö, työpöytä, ikkuna, tehtäväpalkki
# ----------------------------------------------------------------------------
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = _make_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	# Näyttö: tumma muovireunus, merkki ja virtavalo
	_monitor = Panel.new()
	_monitor.add_theme_stylebox_override("panel", _box(Color(0.11, 0.11, 0.13), 18, Color(0.28, 0.28, 0.32), 3))
	_root.add_child(_monitor)
	var brand := Label.new()
	brand.text = "KOSKI-PC  ·  BaariOS"
	brand.add_theme_color_override("font_color", Color(0.55, 0.56, 0.6))
	brand.add_theme_font_size_override("font_size", 12)
	brand.name = "Brand"
	_monitor.add_child(brand)
	var led := ColorRect.new()
	led.color = Color(0.3, 1.0, 0.45)
	led.name = "Led"
	led.size = Vector2(8, 8)
	_monitor.add_child(led)

	_screen = Control.new()
	_screen.clip_contents = true
	_monitor.add_child(_screen)
	var wall := Wallpaper.new()
	wall.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(wall)

	# Kuvakkeet työpöydällä
	_icons = GridContainer.new()
	_icons.columns = 2
	_icons.add_theme_constant_override("h_separation", 6)
	_icons.add_theme_constant_override("v_separation", 6)
	_screen.add_child(_icons)
	for a: Array in APPS:
		var ic := AppIcon.new()
		ic.kind = str(a[0])
		ic.caption = str(a[1])
		ic.col = a[2]
		ic.pressed.connect(open_app.bind(str(a[0])))
		_icons.add_child(ic)

	# Ikkuna
	_window = PanelContainer.new()
	var wsb := _box(Color(0.97, 0.97, 0.98), 6, Color(0.3, 0.36, 0.5), 2)
	wsb.shadow_color = Color(0, 0, 0, 0.45)
	wsb.shadow_size = 10
	wsb.set_content_margin_all(0)
	_window.add_theme_stylebox_override("panel", wsb)
	_screen.add_child(_window)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 0)
	_window.add_child(wv)
	var title_bar := PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = ACCENT
	tsb.corner_radius_top_left = 5
	tsb.corner_radius_top_right = 5
	tsb.border_width_bottom = 2
	tsb.border_color = ACCENT.darkened(0.3)
	tsb.content_margin_left = 10
	tsb.content_margin_right = 6
	tsb.content_margin_top = 4
	tsb.content_margin_bottom = 4
	title_bar.add_theme_stylebox_override("panel", tsb)
	wv.add_child(title_bar)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 8)
	title_bar.add_child(th)
	_win_icon = ColorRect.new()
	_win_icon.custom_minimum_size = Vector2(14, 14)
	_win_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(_win_icon)
	_win_title = Label.new()
	_win_title.add_theme_color_override("font_color", Color.WHITE)
	_win_title.add_theme_font_size_override("font_size", 15)
	_win_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(_win_title)
	for k in 2:
		var deco := ColorRect.new()   # pienennä / suurenna (koriste)
		deco.custom_minimum_size = Vector2(22, 18)
		deco.color = Color(1, 1, 1, 0.18)
		deco.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		th.add_child(deco)
	var x_btn := Button.new()
	x_btn.text = "X"
	x_btn.custom_minimum_size = Vector2(26, 20)
	x_btn.add_theme_stylebox_override("normal", _box(Color(0.8, 0.22, 0.22), 3))
	x_btn.add_theme_stylebox_override("hover", _box(Color(0.95, 0.3, 0.3), 3))
	x_btn.add_theme_stylebox_override("pressed", _box(Color(0.6, 0.15, 0.15), 3))
	x_btn.add_theme_color_override("font_color", Color.WHITE)
	x_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	x_btn.pressed.connect(open_app.bind(""))
	th.add_child(x_btn)

	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		body.add_theme_constant_override(side, 12)
	wv.add_child(body)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	_scroll.add_child(_content)

	var sbar := PanelContainer.new()
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.88, 0.89, 0.92)
	ssb.border_width_top = 1
	ssb.border_color = Color(0.7, 0.72, 0.78)
	ssb.corner_radius_bottom_left = 5
	ssb.corner_radius_bottom_right = 5
	ssb.content_margin_left = 10
	ssb.content_margin_top = 3
	ssb.content_margin_bottom = 3
	sbar.add_theme_stylebox_override("panel", ssb)
	wv.add_child(sbar)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", MUTED)
	sbar.add_child(_status)

	# Tehtäväpalkki
	_taskbar = Panel.new()
	var tb := StyleBoxFlat.new()
	tb.bg_color = Color(0.08, 0.1, 0.17, 0.96)
	tb.border_width_top = 1
	tb.border_color = Color(0.3, 0.35, 0.5)
	_taskbar.add_theme_stylebox_override("panel", tb)
	_screen.add_child(_taskbar)
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 6
	hb.offset_right = -8
	hb.add_theme_constant_override("separation", 10)
	_taskbar.add_child(hb)
	var start := Button.new()
	start.text = "BaariOS"
	start.custom_minimum_size = Vector2(96, 30)
	start.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	start.add_theme_stylebox_override("normal", _box(Color(0.15, 0.55, 0.3), 4))
	start.add_theme_stylebox_override("hover", _box(Color(0.2, 0.68, 0.38), 4))
	start.add_theme_stylebox_override("pressed", _box(Color(0.1, 0.42, 0.22), 4))
	start.add_theme_color_override("font_color", Color.WHITE)
	start.add_theme_color_override("font_hover_color", Color.WHITE)
	start.pressed.connect(open_app.bind(""))
	hb.add_child(start)
	_task_app = Label.new()
	_task_app.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	_task_app.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_task_app)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)
	_money = Label.new()
	_money.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
	_money.add_theme_font_size_override("font_size", 15)
	_money.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_money)
	_clock = Label.new()
	_clock.add_theme_color_override("font_color", Color.WHITE)
	_clock.add_theme_font_size_override("font_size", 11)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_clock)
	var off := Button.new()
	off.text = "Sammuta"
	off.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	off.add_theme_stylebox_override("normal", _box(Color(0.55, 0.15, 0.18), 4))
	off.add_theme_stylebox_override("hover", _box(Color(0.75, 0.2, 0.24), 4))
	off.add_theme_stylebox_override("pressed", _box(Color(0.4, 0.1, 0.12), 4))
	off.add_theme_color_override("font_color", Color.WHITE)
	off.add_theme_color_override("font_hover_color", Color.WHITE)
	off.pressed.connect(close)
	hb.add_child(off)
	_tick = 0.0


## Sijoittelu ikkunan koon mukaan.
func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var ms := Vector2(minf(vs.x * 0.92, 1080.0), minf(vs.y * 0.92, 700.0))
	_monitor.position = ((vs - ms) * 0.5).floor()
	_monitor.size = ms
	_screen.position = Vector2(18, 18)
	_screen.size = ms - Vector2(36, 54)
	var brand := _monitor.get_node("Brand") as Label
	brand.position = Vector2(ms.x * 0.5 - 70.0, ms.y - 30.0)
	(_monitor.get_node("Led") as ColorRect).position = Vector2(ms.x - 40.0, ms.y - 23.0)
	var tb_h := 40.0
	_taskbar.position = Vector2(0, _screen.size.y - tb_h)
	_taskbar.size = Vector2(_screen.size.x, tb_h)
	_icons.position = Vector2(12, 12)
	var left := 12.0 + 2.0 * 92.0 + 6.0 + 14.0
	_window.position = Vector2(left, 12)
	_window.size = Vector2(_screen.size.x - left - 12.0, _screen.size.y - tb_h - 24.0)


# ----------------------------------------------------------------------------
#  SOVELLUKSET
# ----------------------------------------------------------------------------
func open_app(id: String) -> void:
	_app = id
	_window.visible = id != ""
	var info: Array = []
	for a: Array in APPS:
		if str(a[0]) == id:
			info = a
	_task_app.text = ("  " + str(info[1])) if not info.is_empty() else "  Työpöytä"
	if id == "":
		return
	_win_title.text = "%s – %s" % [str(info[1]), Game.bar_name()]
	_win_icon.color = info[2]
	_status.text = "Valmis."
	_status.add_theme_color_override("font_color", MUTED)
	_rebuild()


func _rebuild() -> void:
	for c in _content.get_children():
		c.queue_free()
	match _app:
		"books":
			_app_books()
		"upgrades":
			_app_upgrades()
		"style":
			_app_style()
		"staff":
			_app_staff()
		"price":
			_app_price()
		"events":
			_app_events()
		"care":
			_app_care()
		"settings":
			_app_settings()


## Toiminnon tulos tilariville; onnistuminen vihreällä, virhe punaisella.
func _result(res: Array) -> void:
	var ok := bool(res[0])
	var msg := str(res[1])
	if msg != "":
		_status.text = msg
		_status.add_theme_color_override("font_color", GOOD if ok else BAD)
	if not ok:
		Sfx.play_ui("denied", -6.0)
	var keep := _status.text
	var keep_col: Color = GOOD if ok else BAD
	_rebuild()
	_status.text = keep
	_status.add_theme_color_override("font_color", keep_col)


# --- Kirjanpito ---
func _app_books() -> void:
	var d: Dictionary = Game.bar_data
	var last: Dictionary = d.get("last", {})
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_content.add_child(row)
	row.add_child(_card("SUOSIO", "%d %%" % roundi(float(biz.popularity())), "%s  %s" % [biz.stars_text(), biz.popularity_label()], Color(0.95, 0.4, 0.6)))
	var nxt := int(biz.rep_next())
	row.add_child(_card("MAINE", "Taso %d" % int(biz.rep_level()), ("%d / %d pistettä" % [int(biz.rep_xp()), nxt]) if nxt > 0 else "Huipputaso", Color(0.95, 0.7, 0.2)))
	row.add_child(_card("KUNTO", "%d %%" % roundi(float(biz.condition())), "Huolto: %d $" % int(biz.repair_price()), Color(0.45, 0.6, 0.75)))
	var prof := int(last.get("profit", 0))
	row.add_child(_card("EILINEN TULOS", ("%+d $" % prof) if not last.is_empty() else "–", "%d asiakasta" % int(last.get("cust", 0)) if not last.is_empty() else "ei vielä tilitystä", GOOD if prof >= 0 else BAD))

	_heading("Tulos 7 päivältä ($)")
	var chart := BarChart.new()
	chart.values = (d.get("history", []) as Array).duplicate()
	chart.custom_minimum_size = Vector2(0, 170)
	_content.add_child(chart)

	_heading("Tuloslaskelma")
	var f: Array = biz.forecast()
	var rows := [
		["", "Eilen", "Ennuste tänään (%s)" % Game.weekday()],
		["Tulijoita", str(int(last.get("cust", 0)) + int(last.get("unserved", 0))) if not last.is_empty() else "–", str(roundi(float(f[3])))],
		["Palveltuja asiakkaita", str(int(last.get("cust", 0))) if not last.is_empty() else "–", str(roundi(float(f[0])))],
		["Palvelematta jääneet", str(int(last.get("unserved", 0))) if not last.is_empty() else "–", str(maxi(roundi(float(f[3]) - float(f[0])), 0))],
		["Myynti", ("%d $" % int(last.get("sales", 0))) if not last.is_empty() else "–", "%d $" % roundi(float(f[1]))],
		["Kulut (tavara, palkat, vuokra)", ("%d $" % int(last.get("costs", 0))) if not last.is_empty() else "–", "%d $" % roundi(float(f[2]))],
		["TULOS", ("%+d $" % prof) if not last.is_empty() else "–", "%+d $" % roundi(float(f[1]) - float(f[2]))],
	]
	_table(rows, [2.2, 1.0, 1.4])

	_heading("Yritystiedot")
	var pr: Array = biz.pricing_list()[int(biz.price_index())]
	var info := [
		["Tieto", "Arvo"],
		["Hinnoittelu", str(pr[0])],
		["Tilaa asiakkaille / pv", str(roundi(float(biz.capacity())))],
		["Henkilökunta ehtii palvella / pv", str(roundi(float(biz.service_capacity())))],
		["Keskiostos", "%.2f $" % float(biz.spend_per_customer())],
		["Palkat / pv", "%d $" % int(biz.wages())],
		["Illan tapahtuma", str(biz.event_name()) if str(biz.event_name()) != "" else "ei"],
		["Itse tarjoiltu tänään", "%d juomaa, %d $" % [int(d.get("served", 0)), int(d.get("tips", 0))]],
		["Tulos omistusaikana yhteensä", "%+d $" % int(d.get("total", 0))],
	]
	_table(info, [2.2, 1.6])


# --- Päivitykset ---
func _app_upgrades() -> void:
	var money := int(biz.money_total())
	_note("Jokainen päivitys nostaa suosiota ja näkyy baarissa. Rahaa käytettävissä: %d $" % money)
	var ups: Array = biz.upgrades_list()
	for i in ups.size():
		var u: Dictionary = ups[i]
		var lv := int(biz.level(str(u.id)))
		var levels_arr: Array = u.levels
		var maxed := lv >= levels_arr.size()
		var nxt: Dictionary = {} if maxed else levels_arr[lv]
		var card := _row_card()
		var h := card.get_child(0) as HBoxContainer
		h.add_child(_swatch(Color.from_hsv(float(i) / float(ups.size()), 0.55, 0.85)))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 2)
		h.add_child(v)
		var top := HBoxContainer.new()
		v.add_child(top)
		top.add_child(_label(str(u.name), 16, INK))
		var pips := Pips.new()
		pips.n = lv
		pips.total = levels_arr.size()
		pips.col = Color(0.95, 0.6, 0.15)
		top.add_child(pips)
		v.add_child(_label("Seuraava: " + str(nxt.desc) if not maxed else "Kaikki tasot ostettu.", 13, MUTED, true))
		if lv > 0:
			v.add_child(_label("Nyt: " + str((levels_arr[lv - 1] as Dictionary).desc), 12, GOOD, true))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(130, 34)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if maxed:
			btn.text = "Täynnä"
			btn.disabled = true
		else:
			btn.text = "Osta %d $" % int(nxt.price)
			btn.disabled = money < int(nxt.price)
			btn.pressed.connect(func() -> void: _result(biz.buy_upgrade(i)))
		h.add_child(btn)


# --- Henkilökunta ---
func _app_staff() -> void:
	var f: Array = biz.forecast()
	var demand := float(f[3])
	var sc := float(biz.service_capacity())
	var box := _row_card()
	var bv := VBoxContainer.new()
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.get_child(0).add_child(bv)
	bv.add_child(_label("Palvelukyky tänään: %d tulijaa, henkilökunta ehtii palvella %d" % [roundi(demand), roundi(sc)], 14, INK))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 18)
	bar.max_value = maxf(sc, demand)
	bar.value = demand
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOOD if demand <= sc else BAD
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	bv.add_child(bar)
	bv.add_child(_label("Henkilökuntaa riittää." if demand <= sc else "Väkeä liian vähän: noin %d asiakasta lähtee palvelematta!" % roundi(demand - sc), 13, GOOD if demand <= sc else BAD))
	bv.add_child(_label("Palkat yhteensä %d $ / päivä. Railin vanha baarimikko ja portsari ovat aina töissä." % int(biz.wages()), 12, MUTED))
	var money := int(biz.money_total())
	for h: Dictionary in biz.hires_list():
		var id := str(h.id)
		var n := int(biz.hired(id))
		var locked := str(h.need) != "" and int(biz.level(str(h.need))) < 1
		var card := _row_card()
		var hb := card.get_child(0) as HBoxContainer
		hb.add_child(_swatch(Color(0.25, 0.5, 0.95) if not locked else Color(0.6, 0.6, 0.65)))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 2)
		hb.add_child(v)
		var top := HBoxContainer.new()
		v.add_child(top)
		top.add_child(_label(str(h.name), 16, INK))
		var pips := Pips.new()
		pips.n = n
		pips.total = int(h.max)
		pips.col = Color(0.25, 0.5, 0.95)
		top.add_child(pips)
		v.add_child(_label("%s  ·  palkka %d $ / pv  ·  palkkaus %d $" % [h.desc, int(h.wage), int(h.hire)], 12, MUTED, true))
		if locked:
			v.add_child(_label("Lukossa: vaatii päivityksen.", 12, BAD))
		var hire_b := Button.new()
		hire_b.text = "Palkkaa"
		hire_b.custom_minimum_size = Vector2(96, 32)
		hire_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hire_b.disabled = locked or n >= int(h.max) or money < int(h.hire)
		hire_b.pressed.connect(func() -> void: _result(biz.hire(id)))
		hb.add_child(hire_b)
		var fire_b := Button.new()
		fire_b.text = "Irtisano"
		fire_b.custom_minimum_size = Vector2(90, 32)
		fire_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		fire_b.disabled = n <= 0
		fire_b.pressed.connect(func() -> void: _result(biz.fire(id)))
		hb.add_child(fire_b)


# --- Hinnoittelu ---
func _app_price() -> void:
	_note("Hinnoittelu vaikuttaa asiakasmäärään, keskiostokseen ja suosioon. Premium sopii hienoon sisustukseen.")
	var cur := int(biz.price_index())
	var plist: Array = biz.pricing_list()
	for i in plist.size():
		var pr: Array = plist[i]
		var card := _row_card(i == cur)
		var hb := card.get_child(0) as HBoxContainer
		hb.add_child(_swatch([GOOD, ACCENT, Color(0.75, 0.3, 0.75)][i] as Color))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(v)
		v.add_child(_label(str(pr[0]), 16, INK))
		v.add_child(_label("Asiakkaat x%.2f   ·   Ostokset x%.2f   ·   Suosio %+d" % [float(pr[1]), float(pr[2]), int(pr[3])], 13, MUTED))
		var b := Button.new()
		b.custom_minimum_size = Vector2(120, 32)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.text = "Käytössä" if i == cur else "Valitse"
		b.disabled = i == cur
		b.pressed.connect(func() -> void: _result(biz.set_price(i)))
		hb.add_child(b)


# --- Tapahtumat ---
func _app_events() -> void:
	var active: Array = biz.events_active()
	_note("Samalle illalle voi tilata kaksi tapahtumaa, esim. livebändin ja happy hourin. Lavalle mahtuu yksi esitys kerrallaan (bändi, karaoke tai tietovisa). Tapahtumat näkyvät baarissa heti, tilitys aamulla.")
	_content.add_child(_label("Illan ohjelma: %s" % (str(biz.event_name()) if not active.is_empty() else "ei tapahtumia"), 15, ACCENT))
	var money := int(biz.money_total())
	for e_arr: Array in biz.events_list():
		var id := str(e_arr[0])
		var e: Dictionary = e_arr[1]
		var on := id in active
		var why := str(biz.event_block_reason(id))
		var card := _row_card(on)
		var hb := card.get_child(0) as HBoxContainer
		hb.add_child(_swatch(Color(0.92, 0.28, 0.35) if (on or why == "") else Color(0.6, 0.6, 0.65)))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(v)
		var title := HBoxContainer.new()
		v.add_child(title)
		title.add_child(_label(str(e.name), 16, INK))
		if id in ["band", "karaoke", "quiz"]:
			title.add_child(_label("   LAVA", 11, Color(0.75, 0.3, 0.75)))
		var fc: Array = biz.forecast(id)
		v.add_child(_label("Hinta %d $  ·  asiakkaat x%.2f  ·  suosio +%d  ·  arvio %d asiakasta" % [int(e.cost), float(e.cust), int(e.pop), roundi(float(fc[0]))], 12, MUTED, true))
		if not on and why != "":
			v.add_child(_label(why, 12, BAD))
		var b := Button.new()
		b.custom_minimum_size = Vector2(120, 32)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if on:
			b.text = "Peru"
			b.pressed.connect(func() -> void: _result(biz.cancel_event(id)))
		else:
			b.text = "Tilaa %d $" % int(e.cost) if int(e.cost) > 0 else "Tilaa"
			b.disabled = why != "" or money < int(e.cost)
			b.pressed.connect(func() -> void: _result(biz.order_event(id)))
		hb.add_child(b)


# --- Sisustus (ulkoasu, ilmainen) ---
func _app_style() -> void:
	_note("Valitse baarin lattia, tapetti, tiskin pinta ja neonin väri vapaasti. Muutokset ovat ilmaisia ja näkyvät heti. Päivitykset tuovat lisäksi kalusteita ja valoja.")
	_heading("Valmiit tyylit")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	_content.add_child(flow)
	var presets: Array = biz.look_presets()
	for i in presets.size():
		var pb := Button.new()
		pb.text = str((presets[i] as Array)[0])
		pb.custom_minimum_size = Vector2(0, 32)
		pb.pressed.connect(func() -> void: _result(biz.apply_preset(i)))
		flow.add_child(pb)
	for sec: Array in [["floor", "Lattia"], ["wall", "Tapetti"], ["counter", "Tiskin pinta"], ["neon", "Neonvalojen väri"]]:
		var key := str(sec[0])
		_heading(str(sec[1]))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		_content.add_child(row)
		var cur := str(biz.look(key))
		for opt: Array in biz.look_options(key):
			var oid := str(opt[0])
			var ob := Button.new()
			ob.text = ("  " + str(opt[1])) if oid != cur else ("> " + str(opt[1]))
			ob.custom_minimum_size = Vector2(0, 34)
			ob.icon = _swatch_icon(opt[2])
			if oid == cur:
				ob.add_theme_stylebox_override("normal", _box(Color(0.85, 0.92, 1.0), 4, ACCENT, 2))
			ob.pressed.connect(func() -> void: _result(biz.set_look(key, oid)))
			row.add_child(ob)


## Pieni värinäyte nappiin (ImageTexture)
func _swatch_icon(col: Color) -> Texture2D:
	var img := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.2, 0.22))
	img.fill_rect(Rect2i(1, 1, 16, 16), col)
	return ImageTexture.create_from_image(img)


# --- Huolto ---
func _app_care() -> void:
	var cond := float(biz.condition())
	var card := _row_card()
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.get_child(0).add_child(v)
	v.add_child(_label("Baarin kunto: %d %%" % roundi(cond), 18, INK))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 22)
	bar.value = cond
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOOD.lerp(BAD, clampf((80.0 - cond) / 50.0, 0.0, 1.0))
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	v.add_child(bar)
	v.add_child(_label("Kunto kuluu asiakkaista ja tappeluista. Alle 70 %:n kunto laskee suosiota.", 13, MUTED, true))
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 36)
	var price := int(biz.repair_price())
	b.text = "Tilaa siivous ja huolto (%d $)" % price if cond < 99.5 else "Kaikki kunnossa"
	b.disabled = cond >= 99.5 or int(biz.money_total()) < price
	b.pressed.connect(func() -> void: _result(biz.do_repair()))
	v.add_child(b)


# --- Asetukset ---
func _app_settings() -> void:
	var card := _row_card()
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	card.get_child(0).add_child(v)
	v.add_child(_label("Baarin nimi (näkyy neonkyltissä, enintään 16 merkkiä)", 14, INK))
	var hb := HBoxContainer.new()
	v.add_child(hb)
	var edit := LineEdit.new()
	edit.max_length = 16
	edit.text = Game.bar_name()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 34)
	hb.add_child(edit)
	var save := Button.new()
	save.text = "Tallenna nimi"
	save.custom_minimum_size = Vector2(130, 34)
	save.pressed.connect(func() -> void: _result(biz.rename(edit.text)))
	edit.text_submitted.connect(func(t: String) -> void: _result(biz.rename(t)))
	hb.add_child(save)
	v.add_child(_label("Ehdotuksia:", 13, MUTED))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	v.add_child(flow)
	for n in biz.name_ideas():
		var ib := Button.new()
		ib.text = str(n)
		var nm := str(n)
		ib.pressed.connect(func() -> void: edit.text = nm)
		flow.add_child(ib)


# ----------------------------------------------------------------------------
#  APUOSAT
# ----------------------------------------------------------------------------
func _box(col: Color, radius: int = 4, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("normal", "Button", _box(Color(0.93, 0.94, 0.96), 4, Color(0.62, 0.65, 0.72), 1))
	t.set_stylebox("hover", "Button", _box(Color(0.85, 0.9, 1.0), 4, ACCENT, 1))
	t.set_stylebox("pressed", "Button", _box(Color(0.72, 0.8, 0.95), 4, ACCENT, 1))
	t.set_stylebox("disabled", "Button", _box(Color(0.9, 0.9, 0.92, 0.7), 4, Color(0.8, 0.8, 0.84), 1))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", ACCENT.darkened(0.3))
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.6, 0.65))
	t.set_stylebox("normal", "LineEdit", _box(Color.WHITE, 3, Color(0.6, 0.63, 0.7), 1))
	t.set_stylebox("focus", "LineEdit", _box(Color.WHITE, 3, ACCENT, 2))
	t.set_color("font_color", "LineEdit", INK)
	t.set_stylebox("background", "ProgressBar", _box(Color(0.85, 0.86, 0.9), 3))
	return t


func _label(text: String, size: int, col: Color, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _heading(text: String) -> void:
	var l := _label(text, 15, ACCENT)
	_content.add_child(l)


func _note(text: String) -> void:
	_content.add_child(_label(text, 13, MUTED, true))


func _swatch(col: Color) -> ColorRect:
	var c := ColorRect.new()
	c.color = col
	c.custom_minimum_size = Vector2(8, 0)
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Valkoinen kortti, jonka sisällä HBoxContainer (child 0). highlight = valittu.
func _row_card(highlight: bool = false) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := _box(Color(0.92, 0.96, 1.0) if highlight else Color.WHITE, 5, ACCENT if highlight else Color(0.8, 0.82, 0.87), 2 if highlight else 1)
	sb.content_margin_left = 0
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	card.add_child(hb)
	_content.add_child(card)
	return card


## Tunnuslukukortti (Kirjanpito)
func _card(title: String, value: String, sub: String, col: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := _box(Color.WHITE, 6, Color(0.8, 0.82, 0.87), 1)
	sb.border_width_top = 4
	sb.border_color = col
	sb.content_margin_left = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	card.add_child(v)
	v.add_child(_label(title, 11, MUTED))
	v.add_child(_label(value, 22, col.darkened(0.15)))
	v.add_child(_label(sub, 11, MUTED))
	return card


## Taulukkolaskentatyylinen taulukko: rivi 0 = otsikkorivi, vuororivit, ruudukko.
func _table(rows: Array, weights: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = weights.size()
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	_content.add_child(grid)
	for r in rows.size():
		var cells: Array = rows[r]
		var is_total := str(cells[0]) == "TULOS"
		for c in cells.size():
			var cell := PanelContainer.new()
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.size_flags_stretch_ratio = float(weights[c])
			var bg := Color(0.86, 0.89, 0.95) if r == 0 else (Color(0.97, 0.98, 1.0) if r % 2 == 1 else Color.WHITE)
			if is_total:
				bg = Color(0.93, 0.97, 0.93)
			var sb := StyleBoxFlat.new()
			sb.bg_color = bg
			sb.border_color = Color(0.78, 0.8, 0.86)
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			if r == 0:
				sb.border_width_top = 1
			if c == 0:
				sb.border_width_left = 1
			sb.content_margin_left = 8
			sb.content_margin_right = 8
			sb.content_margin_top = 4
			sb.content_margin_bottom = 4
			cell.add_theme_stylebox_override("panel", sb)
			var txt := str(cells[c])
			var col := INK
			if r == 0:
				col = ACCENT.darkened(0.2)
			elif c > 0 and (txt.begins_with("+") or txt.begins_with("-")) and txt.ends_with("$"):
				col = GOOD if txt.begins_with("+") else BAD
			var l := _label(txt, 13 if r > 0 else 12, col)
			if c > 0:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			if is_total or r == 0:
				l.add_theme_font_size_override("font_size", 14 if is_total else 12)
			cell.add_child(l)
			grid.add_child(cell)


# ----------------------------------------------------------------------------
#  PIIRRETYT OSAT
# ----------------------------------------------------------------------------
## Työpöydän taustakuva: liukuväri, baarin nimi ja logo.
class Wallpaper extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var top := Color(0.1, 0.18, 0.4)
		var bot := Color(0.45, 0.12, 0.38)
		var y := 0.0
		while y < size.y:
			draw_rect(Rect2(0, y, size.x, 4.0), top.lerp(bot, y / maxf(size.y, 1.0)))
			y += 4.0
		var c := Vector2(size.x * 0.62, size.y * 0.45)
		draw_circle(c, minf(size.x, size.y) * 0.22, Color(1, 1, 1, 0.05))
		draw_arc(c, minf(size.x, size.y) * 0.22, 0.0, TAU, 64, Color(1, 1, 1, 0.12), 2.0)
		var font := get_theme_default_font()
		var nm := Game.bar_name()
		TextFit.draw(self, font, Vector2(c.x - 300.0, c.y + 12.0), nm, 600.0, 34, Color(1, 1, 1, 0.22))
		TextFit.draw(self, font, Vector2(c.x - 300.0, c.y + 40.0), "BaariOS", 600.0, 16, Color(1, 1, 1, 0.18))


## Työpöydän sovelluskuvake: värillinen ruutu, kuva ja nimi.
class AppIcon extends Button:
	var kind := ""
	var caption := ""
	var col := Color.WHITE

	func _ready() -> void:
		flat = true
		text = ""
		custom_minimum_size = Vector2(92, 80)
		focus_mode = Control.FOCUS_NONE
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		if is_hovered():
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.15))
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.35), false, 1.0)
		var r := Rect2(size.x * 0.5 - 22.0, 6.0, 44.0, 44.0)
		draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0, 0, 0, 0.3))
		draw_rect(r, col)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 14.0)), Color(1, 1, 1, 0.15))
		var c := r.get_center()
		var w := Color.WHITE
		match kind:
			"books":
				for k in 4:
					var h := [10.0, 18.0, 13.0, 24.0][k] as float
					draw_rect(Rect2(c.x - 15.0 + k * 8.0, c.y + 12.0 - h, 6.0, h), w)
			"upgrades":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -15), c + Vector2(12, 0), c + Vector2(-12, 0)]), w)
				draw_rect(Rect2(c + Vector2(-5, 0), Vector2(10, 13)), w)
			"staff":
				for k in 2:
					var hp := c + Vector2(-8.0 + k * 16.0, -6.0)
					draw_circle(hp, 5.0, w)
					draw_rect(Rect2(hp + Vector2(-7, 7), Vector2(14, 10)), w)
			"price":
				var font := get_theme_default_font()
				TextFit.draw(self, font, c + Vector2(-20, 12), "$", 40.0, 32, w)
			"events":
				var pts := PackedVector2Array()
				for k in 10:
					var rad := 15.0 if k % 2 == 0 else 6.5
					pts.append(c + Vector2.from_angle(-PI * 0.5 + k * PI / 5.0) * rad)
				draw_colored_polygon(pts, w)
			"style":
				# maalitela
				draw_rect(Rect2(c + Vector2(-13, -12), Vector2(22, 8)), w)
				draw_line(c + Vector2(9, -8), c + Vector2(13, -8), w, 2.0)
				draw_line(c + Vector2(13, -8), c + Vector2(13, -1), w, 2.0)
				draw_line(c + Vector2(13, -1), c + Vector2(1, -1), w, 2.0)
				draw_line(c + Vector2(1, -1), c + Vector2(1, 14), w, 3.0)
			"care":
				draw_line(c + Vector2(-12, 12), c + Vector2(8, -8), w, 5.0)
				draw_circle(c + Vector2(10, -10), 6.0, w)
				draw_circle(c + Vector2(12, -12), 3.0, col)
			"settings":
				for k in 8:
					var a := k * TAU / 8.0
					draw_line(c + Vector2.from_angle(a) * 8.0, c + Vector2.from_angle(a) * 15.0, w, 4.0)
				draw_circle(c, 10.0, w)
				draw_circle(c, 4.5, col)
		var f := get_theme_default_font()
		TextFit.draw(self, f, Vector2(1, 69), caption, size.x, 12, Color(0, 0, 0, 0.6))
		TextFit.draw(self, f, Vector2(0, 68), caption, size.x, 12, Color.WHITE)


## Tasopallurat (päivitykset, henkilökunta)
class Pips extends Control:
	var n := 0
	var total := 3
	var col := Color.ORANGE

	func _ready() -> void:
		custom_minimum_size = Vector2(total * _step() + 10.0, 18)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	## Isommilla määrillä (esim. 8 baarimikkoa) pallurat pienenevät, jotta rivi mahtuu.
	func _step() -> float:
		return 16.0 if total <= 5 else 12.0

	func _draw() -> void:
		for k in total:
			var st := _step()
			var r := Rect2(10.0 + k * st, 3.0 + (12.0 - (st - 4.0)) * 0.5, st - 4.0, st - 4.0)
			draw_rect(r, col if k < n else Color(0.86, 0.87, 0.9))
			draw_rect(r, col.darkened(0.3) if k < n else Color(0.7, 0.72, 0.78), false, 1.0)


## Pylväskaavio päivittäisestä tuloksesta (vihreä voitto, punainen tappio).
class BarChart extends Control:
	var values: Array = []

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var font := get_theme_default_font()
		var area := Rect2(Vector2.ZERO, size)
		draw_rect(area, Color.WHITE)
		draw_rect(area, Color(0.8, 0.82, 0.87), false, 1.0)
		if values.is_empty():
			TextFit.draw(self, font, Vector2(0, size.y * 0.5), "Ei vielä tilityksiä. Ensimmäinen tilitys tulee aamulla.", size.x, 13, Color(0.5, 0.5, 0.55))
			return
		var plot := Rect2(50.0, 14.0, size.x - 64.0, size.y - 40.0)
		var mx := 1.0
		var mn := 0.0
		for v in values:
			mx = maxf(mx, float(v))
			mn = minf(mn, float(v))
		var span := maxf(mx - mn, 1.0)
		var zero_y := plot.position.y + plot.size.y * (mx / span)
		# apuviivat
		for k in 5:
			var gy := plot.position.y + plot.size.y * k / 4.0
			draw_line(Vector2(plot.position.x, gy), Vector2(plot.end.x, gy), Color(0.9, 0.91, 0.94), 1.0)
			var val := mx - span * k / 4.0
			draw_string(font, Vector2(4.0, gy + 4.0), str(roundi(val)), HORIZONTAL_ALIGNMENT_RIGHT, 42.0, 10, Color(0.5, 0.5, 0.55))
		draw_line(Vector2(plot.position.x, zero_y), Vector2(plot.end.x, zero_y), Color(0.4, 0.42, 0.48), 1.0)
		var n := values.size()
		var slot := plot.size.x / 7.0
		for i in n:
			var v := float(values[i])
			var x := plot.position.x + slot * (7 - n + i) + slot * 0.2
			var h := plot.size.y * absf(v) / span
			var rr := Rect2(x, zero_y - h if v >= 0.0 else zero_y, slot * 0.6, h)
			var c := Color(0.2, 0.68, 0.38) if v >= 0.0 else Color(0.88, 0.25, 0.25)
			draw_rect(rr, c)
			draw_rect(Rect2(rr.position, Vector2(rr.size.x, minf(3.0, rr.size.y))), c.lightened(0.25))
			TextFit.draw(self, font, Vector2(x - 10.0, (rr.position.y - 3.0) if v >= 0.0 else (rr.end.y + 12.0)), "%d" % roundi(v), slot * 0.6 + 20.0, 11, c.darkened(0.3))
			var lbl := "eilen" if i == n - 1 else "-%d pv" % (n - i)
			TextFit.draw(self, font, Vector2(x - 10.0, plot.end.y + 16.0), lbl, slot * 0.6 + 20.0, 10, Color(0.45, 0.47, 0.53))
