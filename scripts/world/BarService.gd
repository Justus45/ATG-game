extends Node2D
## Pomo tiskin takana: asiakkaat tulevat tiskille ja tilaavat, pelaaja kaataa ja tarjoilee.
##  - Tiskiluukku tiskin oikeassa päässä aukeaa vain omistajalle (Bar.gd).
##  - Juoma-asemat tiskin takana: E ottaa juoman käteen (olut, kossu, shotti; lisää
##    Juomavalikoima-päivityksillä: lonkero, viski, cocktail).
##  - Asiakkaan kohdalla tiskin takana E tarjoilee. Oikea juoma: hinta + tippi lompakkoon
##    ja mainetta baarille (nopea palvelu = isompi tippi). Väärä juoma tai liian pitkä
##    odotus suututtaa asiakkaan.
##  - Kun pomo ei ole tiskin takana, henkilökunta palvelee asiakkaat itse.
## Koordinaatit ovat baarin huoneen paikallisia (tämä solmu on Bar._interior:n lapsi).

# --- SÄÄDÄ NÄITÄ ---
const STATIONS := [
	{"name": "Olut", "price": 3, "sound": "can", "need": 0},
	{"name": "Kossu", "price": 4, "sound": "clink", "need": 0},
	{"name": "Shotti", "price": 7, "sound": "clink", "need": 0},
	{"name": "Lonkero", "price": 5, "sound": "can", "need": 1},
	{"name": "Viski", "price": 9, "sound": "clink", "need": 2},
	{"name": "Cocktail", "price": 12, "sound": "clink", "need": 3},
]
const STATION_X := [118.0, 146.0, 174.0, 202.0, 230.0, 258.0]
const STATION_Y := 44.0
const SLOT_X := [140.0, 190.0, 240.0]
const CUSTOMER_Y := 98.0          ## asiakas seisoo tiskin edessä
const SERVE_Y := 57.0             ## pelaaja tarjoilee tästä (tiskin takana)
const BEHIND_Y := 64.0            ## tätä ylempänä (pienempi y) pelaaja on tiskin takana
const PATIENCE := 18.0            ## asiakkaan kärsivällisyys (s), sisustus lisää
const STAFF_SERVE_TIME := 4.0     ## henkilökunta palvelee näin nopeasti, kun pomo ei ole tiskillä
const LEAVE_TIME := 0.8

const THANKS := ["Kiitti pomo!", "Nopeeta palvelua!", "Tää on parasta!", "Kippis!", "Pidä loput!"]
const SLOW_THANKS := ["No vihdoin...", "Kesti kauan.", "Kiitti, kai."]
const ANGRY := ["Liian hidasta!", "Mä lähden muualle!", "Surkee palvelu!"]
const WRONG := ["En mä tätä tilannut!", "Väärä juoma, pomo!", "Mitä tää on?"]

const CS := preload("res://scripts/core/CharSprites.gd")
var bar: Node = null                # Bar.gd
var _custs: Array = [null, null, null]
var _carry := -1                    ## käsissä oleva juoma (STATIONS-indeksi), -1 = ei mitään
var _spawn_t := 3.0
var _t := 0.0
var _was_behind := false
var _hint_shown := false


func _ready() -> void:
	z_index = 9
	for i in STATIONS.size():
		InteractSpot.create(self, to_global(Vector2(STATION_X[i], STATION_Y)), Vector2(24.0, 14.0),
			_station_prompt.bind(i), _take_by.bind(i))
	for j in SLOT_X.size():
		InteractSpot.create(self, to_global(Vector2(SLOT_X[j], SERVE_Y)), Vector2(34.0, 10.0),
			_slot_prompt.bind(j), _serve_by.bind(j))


## InteractSpot kutsuu action(player): pelaaja tulee ensin, sidottu indeksi perään.
func _take_by(_p: Node2D, i: int) -> void:
	_take(i)


func _serve_by(_p: Node2D, j: int) -> void:
	_serve(j)


func _biz() -> Node:
	return bar.get("biz") if bar else null


func _drinks_level() -> int:
	var b := _biz()
	return int(b.level("drinks")) if b else 0


func _available(i: int) -> bool:
	return _drinks_level() >= int((STATIONS[i] as Dictionary).need)


## Onko pelaaja (omistaja) tiskin takana?
func owner_behind() -> bool:
	if not Game.owns_bar or bar == null or not bar.get("inside"):
		return false
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p == null or not p.visible:
		return false
	var lp := to_local(p.global_position)
	return lp.y < BEHIND_Y and lp.x > 12.0 and lp.x < 340.0 and lp.y > 20.0


# ----------------------------------------------------------------------------
#  KEHOTTEET JA TOIMINNOT
# ----------------------------------------------------------------------------
func _station_prompt(i: int) -> String:
	var d: Dictionary = STATIONS[i]
	if not _available(i):
		return "Tyhjä hylly (Juomavalikoima %d tuo: %s)" % [int(d.need), d.name]
	if _carry == i:
		return "Kädessä: %s – vie se asiakkaalle" % d.name
	return "Paina E: kaada %s" % str(d.name).to_lower()


func _slot_prompt(j: int) -> String:
	var c = _custs[j]
	if c == null or str(c.state) != "wait":
		return "Tyhjä paikka tiskillä"
	var want: Dictionary = STATIONS[int(c.want)]
	if _carry < 0:
		return "Asiakas haluaa: %s (hae se hyllystä)" % want.name
	return "Paina E: tarjoile %s" % str((STATIONS[_carry] as Dictionary).name).to_lower()


func _take(i: int) -> void:
	if not Game.owns_bar:
		return
	if not _available(i):
		Sfx.play_ui("denied", -8.0)
		bar.hud_message("Hylly on tyhjä. Päivitä juomavalikoimaa toimistosta.", 2.0)
		return
	_carry = i
	Sfx.play(str((STATIONS[i] as Dictionary).sound), to_global(Vector2(STATION_X[i], STATION_Y)), -6.0, 0.1)


func _serve(j: int) -> void:
	var c = _custs[j]
	if c == null or str(c.state) != "wait":
		return
	if _carry < 0:
		bar.hud_message("Asiakas haluaa: %s. Hae se hyllystä ensin." % str((STATIONS[int(c.want)] as Dictionary).name), 2.0)
		return
	var at := to_global(Vector2(SLOT_X[j], CUSTOMER_Y))
	if _carry != int(c.want):
		_carry = -1
		c["pat"] = float(c.pat) - 5.0
		_say(c, WRONG[randi() % WRONG.size()])
		Sfx.play("denied", at, -8.0)
		return
	var d: Dictionary = STATIONS[_carry]
	_carry = -1
	var b := _biz()
	var frac := clampf(float(c.pat) / float(c["max"]), 0.0, 1.0)
	var mult := 1.0
	var lvl := 1
	if b:
		mult = float(b.price_mult())
		lvl = int(b.rep_level())
	var tip := roundi(lerpf(0.0, 4.0, frac) * (1.0 + 0.1 * (lvl - 1)))
	var money := maxi(roundi(float(d.price) * mult), 1) + tip
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("add_money"):
		p.add_money(money)
	Sfx.play("cash", at, -6.0, 0.05)
	_say(c, (THANKS if frac > 0.4 else SLOW_THANKS)[randi() % (THANKS.size() if frac > 0.4 else SLOW_THANKS.size())])
	c["state"] = "leave"
	c["leave_t"] = LEAVE_TIME
	c["served"] = true
	if b:
		b.note_served(money, 2 + (1 if frac > 0.6 else 0))
	Game.add_vitutus(0.8)   # tiskin takana raataminen
	bar.hud_message("+%d $ (tippi %d $)" % [money, tip], 1.4)


# ----------------------------------------------------------------------------
#  ASIAKKAAT
# ----------------------------------------------------------------------------
var _idle_drawn := false


func _process(delta: float) -> void:
	_t += delta
	if not Game.owns_bar or bar == null or not bar.get("inside"):
		_custs = [null, null, null]
		_carry = -1
		if not _idle_drawn:   # optimointi: tyhjä tila piirretään kerran, ei joka ruutu
			_idle_drawn = true
			queue_redraw()
		return
	_idle_drawn = false
	var behind := owner_behind()
	if behind and not _was_behind and not _hint_shown:
		_hint_shown = true
		bar.hud_message("Pomo tiskin takana! Asiakkaat tilaavat: ota juoma hyllystä (E) ja tarjoile asiakkaalle (E).", 4.0)
	if not behind and _was_behind:
		_carry = -1   # juoma jää tiskille
	_was_behind = behind
	# uusia asiakkaita suosion ja maineen mukaan
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = _spawn_interval()
		_spawn()
	for j in _custs.size():
		var c = _custs[j]
		if c == null:
			continue
		c["t"] = float(c.t) + delta
		c["say_t"] = maxf(float(c.say_t) - delta, 0.0)
		if str(c.state) == "wait":
			if behind:
				c["pat"] = float(c.pat) - delta
				if float(c.pat) <= 0.0:
					_say(c, ANGRY[randi() % ANGRY.size()])
					c["state"] = "leave"
					c["leave_t"] = LEAVE_TIME
					var b := _biz()
					if b:
						b.add_rep_xp(-1)
			else:
				# henkilökunta hoitaa, kun pomo ei ole tiskillä
				c["staff_t"] = float(c.get("staff_t", 0.0)) + delta
				if float(c.staff_t) >= STAFF_SERVE_TIME:
					c["state"] = "leave"
					c["leave_t"] = LEAVE_TIME
					c["served"] = true
		elif str(c.state) == "leave":
			c["leave_t"] = float(c.leave_t) - delta
			if float(c.leave_t) <= 0.0:
				_custs[j] = null
	queue_redraw()


func _spawn_interval() -> float:
	var b := _biz()
	var pop := 30.0
	var lvl := 1
	if b:
		pop = float(b.popularity())
		lvl = int(b.rep_level())
	var t := lerpf(11.0, 4.0, pop / 100.0) / (1.0 + 0.06 * (lvl - 1))
	if b:
		t *= pow(0.8, float((b.events_active() as Array).size()))
	return t * randf_range(0.7, 1.3)


func _spawn() -> void:
	var free := []
	for j in _custs.size():
		if _custs[j] == null:
			free.append(j)
	if free.is_empty():
		return
	var j: int = free[randi() % free.size()]
	var choices := []
	for i in STATIONS.size():
		if _available(i):
			choices.append(i)
	var b := _biz()
	var pat := PATIENCE + (2.0 * float(b.level("decor")) if b else 0.0)
	_custs[j] = {"want": choices[randi() % choices.size()], "pat": pat, "max": pat, "row": (randi() % 6) * 3,
		"state": "wait", "t": 0.0, "say": "", "say_t": 0.0, "leave_t": 0.0, "served": false}


func _say(c: Dictionary, text: String) -> void:
	c["say"] = text
	c["say_t"] = 1.8


# ----------------------------------------------------------------------------
#  PIIRTO
# ----------------------------------------------------------------------------
func _draw() -> void:
	if not Game.owns_bar:
		return
	var font := ThemeDB.fallback_font
	_draw_stations(font)
	for j in _custs.size():
		var c = _custs[j]
		if c != null:
			_draw_customer(j, c, font)
	# käsissä oleva juoma pelaajan pään yllä
	if _carry >= 0:
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if p and p.visible:
			var lp := to_local(p.global_position)
			_drink_icon(lp + Vector2(7.0, -16.0 + sin(_t * 6.0) * 0.8), _carry)


## Juoma-asemat tiskin takana (hana, pullot, lonkerojääkaappi, viski, shaker).
func _draw_stations(font: Font) -> void:
	for i in STATIONS.size():
		var p := Vector2(STATION_X[i], STATION_Y)
		var ok := _available(i)
		var a := 1.0 if ok else 0.3
		# pieni työtaso
		draw_rect(Rect2(p + Vector2(-10, 4), Vector2(20, 4)), Color(0.35, 0.22, 0.12, a))
		match i:
			0:   # oluthana
				draw_rect(Rect2(p + Vector2(-6, -8), Vector2(12, 3)), Color(0.75, 0.77, 0.8, a))
				for k in 2:
					var hx := p.x - 3.0 + k * 6.0
					draw_rect(Rect2(hx - 0.5, p.y - 5.0, 1.0, 6.0), Color(0.75, 0.77, 0.8, a))
					draw_rect(Rect2(hx - 1.5, p.y - 12.0, 3.0, 5.0), Color(0.15, 0.15, 0.18, a) if k == 0 else Color(0.85, 0.6, 0.15, a))
			_:
				_drink_icon(p + Vector2(0, -1), i, a)
		if ok and _carry == i:
			draw_arc(p + Vector2(0, -2), 9.0, 0.0, TAU, 16, Color(1.0, 0.9, 0.4, 0.6 + 0.3 * sin(_t * 6.0)), 1.0)
		var nm := str((STATIONS[i] as Dictionary).name).to_upper()
		TextFit.draw_outline(self, font, p + Vector2(-16, 13), nm, 32.0, 5, 3, Color(0, 0, 0, 0.8 * a))
		TextFit.draw(self, font, p + Vector2(-16, 13), nm, 32.0, 5, Color(1, 0.95, 0.8, a))


func _draw_customer(j: int, c: Dictionary, font: Font) -> void:
	var x: float = SLOT_X[j]
	var y := CUSTOMER_Y
	var alpha := 1.0
	if str(c.state) == "leave":
		var k := 1.0 - clampf(float(c.leave_t) / LEAVE_TIME, 0.0, 1.0)
		y += k * 18.0
		alpha = 1.0 - k
	elif float(c.t) < 0.5:
		var k2 := float(c.t) / 0.5
		y += (1.0 - k2) * 18.0
		alpha = k2
	var city = bar.get("city") if bar else null
	var tex: Texture2D = null
	if city and city.has_method("npc_tex"):
		var stp := 0 if str(c.state) == "wait" else 1 + int(float(c.t) * 6.0) % 2
		tex = city.npc_tex(int(c.row), Vector2i.UP if str(c.state) == "wait" else Vector2i.DOWN, stp)
	if tex:
		var tl := Vector2(x, y) - tex.get_size() * 0.5 + Vector2(0, -4)
		# varjo ja ääriviiva: asiakas erottuu kaikilla lattioilla
		draw_set_transform(Vector2(x, y + 3.5), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 5.0, Color(0, 0, 0, 0.25 * alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var dt := tex
		if str(c.state) == "wait" and fmod(float(c.t) + j * 1.7, 3.8) < 0.12:
			var bl := CS.blink(tex)
			if bl:
				dt = bl
		draw_texture(dt, tl, Color(1, 1, 1, alpha))
	else:
		draw_rect(Rect2(x - 4.0, y - 10.0, 8.0, 12.0), Color(0.4, 0.5, 0.8, alpha))
	if str(c.state) == "wait":
		# tilauskupla: juoma ja kärsivällisyyspalkki
		var want := int(c.want)
		var box := Rect2(x - 15.0, 78.0, 30.0, 13.0)
		draw_rect(box, Color(1, 1, 1, 0.92))
		draw_rect(box, Color(0, 0, 0, 0.8), false, 1.0)
		_drink_icon(box.position + Vector2(6, 9), want)
		draw_string(font, box.position + Vector2(11, 7), str((STATIONS[want] as Dictionary).name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 19.0, 4, Color(0, 0, 0))
		var frac := clampf(float(c.pat) / float(c["max"]), 0.0, 1.0)
		var bc := Color(0.9, 0.2, 0.15).lerp(Color(0.3, 0.85, 0.3), frac)
		draw_rect(Rect2(box.position.x + 11.0, box.end.y - 3.5, 17.0, 2.0), Color(0, 0, 0, 0.25))
		draw_rect(Rect2(box.position.x + 11.0, box.end.y - 3.5, 17.0 * frac, 2.0), bc)
	if float(c.say_t) > 0.0 and str(c.say) != "":
		var txt := str(c.say)
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x + 6.0
		var sb := Rect2(x - w * 0.5, y + 4.0, w, 10.0)
		draw_rect(sb, Color(1, 1, 1, 0.9 * alpha))
		draw_string(font, sb.position + Vector2(3, 7.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0, 0, 0, alpha))


## Juoman kuvake. p = lasin pohjan keskikohta.
func _drink_icon(p: Vector2, i: int, a: float = 1.0) -> void:
	var glass := Color(0.85, 0.92, 1.0, 0.5 * a)
	match i:
		0:   # olut
			draw_rect(Rect2(p + Vector2(-2.5, -7), Vector2(5, 7)), Color(0.95, 0.68, 0.15, a))
			draw_rect(Rect2(p + Vector2(-2.5, -8), Vector2(5, 2)), Color(1.0, 0.98, 0.9, a))
			draw_rect(Rect2(p + Vector2(2.5, -6), Vector2(1.5, 4)), glass)
		1:   # kossu
			draw_rect(Rect2(p + Vector2(-2, -5), Vector2(4, 5)), glass)
			draw_rect(Rect2(p + Vector2(-1.5, -3), Vector2(3, 3)), Color(0.95, 0.98, 1.0, 0.9 * a))
		2:   # shotti (salmiakki)
			draw_rect(Rect2(p + Vector2(-1.5, -4), Vector2(3, 4)), glass)
			draw_rect(Rect2(p + Vector2(-1, -3), Vector2(2, 3)), Color(0.15, 0.05, 0.08, a))
		3:   # lonkero-tölkki
			draw_rect(Rect2(p + Vector2(-2, -7), Vector2(4, 7)), Color(0.2, 0.75, 0.6, a))
			draw_rect(Rect2(p + Vector2(-2, -5), Vector2(4, 1.5)), Color(1.0, 0.9, 0.3, a))
		4:   # viski
			draw_rect(Rect2(p + Vector2(-2.5, -4), Vector2(5, 4)), glass)
			draw_rect(Rect2(p + Vector2(-2, -2.5), Vector2(4, 2.5)), Color(0.8, 0.45, 0.1, a))
		5:   # cocktail
			draw_colored_polygon(PackedVector2Array([p + Vector2(-3.5, -7), p + Vector2(3.5, -7), p + Vector2(0, -3)]), Color(1.0, 0.35, 0.6, a))
			draw_line(p + Vector2(0, -3), p, Color(1, 1, 1, 0.7 * a), 1.0)
			draw_circle(p + Vector2(2.5, -8), 1.2, Color(0.4, 0.9, 0.3, a))
