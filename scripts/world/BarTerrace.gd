extends Node2D
## Oman baarin terassi (Terassi-päivitys) baarin pihalla rakennuksen vieressä
## (kaupungin generointi varaa pihan: Bar.yard_px). Ei koskaan tielle.
##  - Terassi 1: puukansi, kaiteet, kaksi pöytää tuoleineen ja päivänvarjot, valonauha.
##  - Terassi 2: isompi kansi (kolme pöytää), kangaskatos ja lämmittimet: sade ei haittaa.
##  - Pöydissä istuu asiakkaita (tavallisia NPC-hahmoja): he juovat kaljaa ja lonkeroa,
##    kilistävät ("KIPPIS!"), nauravat ja juttelevat. Väkeä tulee ja lähtee kellonajan,
##    sään ja baarin suosion mukaan (ilta = täysi terassi, aamulla hiljaista).
##  - Palkattu tarjoilija kantaa juomia terassille.
## Bar.gd luo tämän. Piirretään maailmankoordinaateissa maan tasolla (kävelijät päälle).
## Hehkuvat valot (valonauha, lämmittimet) piirtää BarNeon.gd.

const CS := preload("res://scripts/core/CharSprites.gd")
const TILE := 16
const TYPES := [0, 1, 2, 3, 5]   # NPC-tyypit (4 = pelaaja)
const LINES := ["Kippis!", "Hahaha!", "Yks vielä!", "Ihana ilta!", "Tilataanko lisää?", "Mun vuoro tarjota!",
	"Ei voi olla totta!", "Kesä!", "Skool!", "Mitä sä otat?"]

var bar: Node = null
var door_center := Vector2.ZERO
## Piha maailmassa (CityGenerator varaa). Tyhjä = ei tilaa terassille.
var yard := Rect2()

var _t := 0.0
var _seats: Array = []          # [{pos, face, table, occ, want, row, a, sip_t, sip, drink, say, say_t}]
var _tables: Array[Vector2] = []
var _lvl := 0
var _occ_t := 0.0
var _toast_t := 8.0
var _toast_table := -1
var _toast_left := 0.0
var _say_t := 4.0
var _roof: Node2D = null
# --- tarjoilija ---
const WAITER_SPEED := 36.0
var _w_state := "inside"      # inside, out, serve, back
var _w_t := 2.0
var _w_path: Array[Vector2] = []
var _w_i := 0
var _w_pos := Vector2.ZERO
var _w_dir := Vector2.DOWN
var _w_carry := false
var _w_table := -1


## Terassin kansi maailmassa (BarNeon käyttää valoihin). Terassi 1 käyttää osan pihasta
## (oven puoleinen pää), Terassi 2 koko pihan.
func deck() -> Rect2:
	if yard.size.x <= 0.0:
		return Rect2()
	var r := yard.grow(-2.0)
	var y0 := r.end.y - 34.0
	r = Rect2(r.position.x, maxf(r.position.y, y0), r.size.x, minf(r.size.y, 34.0))
	if _lvl < 2 and r.size.x > 72.0:
		# pienempi terassi oven puoleiseen päähän
		var near_right := yard.get_center().x < door_center.x
		r = Rect2(r.end.x - 72.0 if near_right else r.position.x, r.position.y, 72.0, r.size.y)
	return r


## Terassin sisäänkäynti on oven puoleisella sivulla
func _door_side_right() -> bool:
	return yard.get_center().x < door_center.x


func _ready() -> void:
	_roof = RoofView.new()
	_roof.terrace = self
	_roof.z_index = 50
	add_child(_roof)


func _level() -> int:
	if not Game.owns_bar or bar == null or bar.get("biz") == null:
		return 0
	return int(bar.biz.level("terrace"))


func _rebuild(lvl: int) -> void:
	_lvl = lvl
	_seats.clear()
	_tables.clear()
	if lvl < 1 or yard.size.x <= 0.0:
		return
	var dk := deck()
	var n := clampi(int((dk.size.x - 6.0) / 30.0), 1, 3 if lvl >= 2 else 2)
	var step := dk.size.x / float(n)
	for k in n:
		_tables.append(Vector2(dk.position.x + step * (k + 0.5), dk.position.y + 14.0))
	for ti in _tables.size():
		var c: Vector2 = _tables[ti]
		# istumapaikat: takana (kasvot meihin), vasen, oikea, edessä (selkä meihin)
		for s: Array in [[Vector2(0, -2), 1], [Vector2(-10, 4), 3], [Vector2(10, 4), 0], [Vector2(0, 12), 2]]:
			_seats.append({"pos": c + (s[0] as Vector2), "face": int(s[1]), "table": ti, "occ": false, "want": false,
				"row": 0, "a": 0.0, "sip_t": randf_range(1.0, 6.0), "sip": -1.0, "drink": randi() % 3, "say": "", "say_t": 0.0})


## Kuinka täysi terassi on nyt (0..1): kellonaika, sää ja suosio.
func _occupancy() -> float:
	var h := Game.hour()
	var tf := 0.1
	if h >= 12 and h < 17:
		tf = 0.55
	elif h >= 17 or h < 2:
		tf = 1.0
	elif h >= 2 and h < 4:
		tf = 0.35
	var pop: float = bar.biz.popularity()
	var occ := tf * (0.25 + 0.75 * pop / 100.0)
	if Game.weather in ["rain", "storm", "snow"]:
		occ *= lerpf(1.0, 0.75 if _lvl >= 2 else 0.1, Game.weather_k)
	if bar.biz.has_event("happy"):
		occ = minf(occ * 1.3, 1.0)
	return clampf(occ, 0.0, 1.0)


var _empty_drawn := false


func _process(delta: float) -> void:
	var lvl := _level()
	if lvl != _lvl:
		_rebuild(lvl)
		_empty_drawn = false
	if _lvl < 1:
		if not _empty_drawn:   # optimointi: ei terassia -> piirretään vain kerran
			_empty_drawn = true
			if _roof:
				_roof.queue_redraw()
			queue_redraw()
		return
	_empty_drawn = false
	var cam := get_viewport().get_camera_2d()
	if cam and cam.global_position.distance_to(door_center) > 800.0:
		return
	_t += delta
	# asiakkaita tulee ja lähtee pikkuhiljaa
	_occ_t -= delta
	if _occ_t <= 0.0:
		_occ_t = randf_range(2.0, 5.0)
		var want := roundi(_occupancy() * _seats.size())
		var have := 0
		for s: Dictionary in _seats:
			if bool(s.want):
				have += 1
		if have < want:
			var free := _seats.filter(func(x: Dictionary) -> bool: return not bool(x.want))
			if not free.is_empty():
				var s: Dictionary = free[randi() % free.size()]
				s["want"] = true
				s["row"] = int(TYPES[randi() % TYPES.size()]) * 3
				s["drink"] = randi() % 3
		elif have > want:
			var taken := _seats.filter(func(x: Dictionary) -> bool: return bool(x.want))
			if not taken.is_empty():
				var td: Dictionary = taken[randi() % taken.size()]
				td["want"] = false
	for s: Dictionary in _seats:
		s["a"] = move_toward(float(s.a), 1.0 if bool(s.want) else 0.0, delta * 1.5)
		s["occ"] = float(s.a) > 0.01
		s["say_t"] = maxf(float(s.say_t) - delta, 0.0)
		if not bool(s.occ):
			continue
		# juominen: lasi suulle välillä
		if float(s.sip) >= 0.0:
			s["sip"] = float(s.sip) + delta
			if float(s.sip) > 1.3:
				s["sip"] = -1.0
				s["sip_t"] = randf_range(3.0, 8.0)
		else:
			s["sip_t"] = float(s.sip_t) - delta
			if float(s.sip_t) <= 0.0:
				s["sip"] = 0.0
	# kilistys: koko pöytä nostaa lasit
	if _toast_left > 0.0:
		_toast_left -= delta
	else:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast_t = randf_range(14.0, 30.0)
			var ti := randi() % maxi(_tables.size(), 1)
			var n := 0
			for s: Dictionary in _seats:
				if int(s.table) == ti and bool(s.occ):
					n += 1
			if n >= 2:
				_toast_table = ti
				_toast_left = 1.6
				var p := get_tree().get_first_node_in_group("player") as Node2D
				if p and p.global_position.distance_to(_tables[ti]) < 220.0:
					Sfx.play("clink", _tables[ti], -10.0, 0.1, 1.2)
	# juttelu
	_say_t -= delta
	if _say_t <= 0.0:
		_say_t = randf_range(3.0, 8.0)
		var occ_seats := _seats.filter(func(x: Dictionary) -> bool: return bool(x.occ) and float(x.a) > 0.9)
		if not occ_seats.is_empty():
			var s: Dictionary = occ_seats[randi() % occ_seats.size()]
			s["say"] = LINES[randi() % LINES.size()]
			s["say_t"] = 2.2
	_update_waiter(delta)
	queue_redraw()
	if _roof:
		_roof.queue_redraw()


# ----------------------------------------------------------------------------
#  TARJOILIJA
# ----------------------------------------------------------------------------
## Reitti ovelta pöydän luo: jalkakäytävää pitkin terassin sisäänkäynnille ja siitä pöytään.
## Takapihalle kierretään rakennuksen sivun kautta (ei koskaan seinien läpi).
func _waiter_path(table: Vector2) -> Array[Vector2]:
	var dk := deck()
	var start := door_center + Vector2(0.0, TILE + 6.0)
	var pts: Array[Vector2] = [start]
	var roof: Rect2 = bar.get("roof_rect")
	var backyard := yard.position.y < roof.position.y
	if backyard:
		var left := yard.get_center().x <= door_center.x
		var side_x := roof.position.x - 10.0 if left else roof.end.x + 10.0
		pts.append(Vector2(side_x, start.y))
		pts.append(Vector2(side_x, dk.get_center().y + 4.0))
		pts.append(Vector2(table.x, dk.get_center().y + 4.0))
	else:
		var ex := dk.end.x - 7.0 if _door_side_right() else dk.position.x + 7.0
		pts.append(Vector2(ex, start.y))
		pts.append(Vector2(ex, dk.end.y - 5.0))
		pts.append(Vector2(table.x, dk.end.y - 5.0))
	pts.append(table + Vector2(0.0, 17.0))
	return pts


func _update_waiter(delta: float) -> void:
	if int(bar.biz.level("h_waiter")) < 1 or _tables.is_empty():
		_w_state = "inside"
		return
	match _w_state:
		"inside":
			_w_t -= delta
			if _w_t <= 0.0:
				# vie juomia pöytään, jossa istuu joku
				var busy: Array = []
				for ti in _tables.size():
					for st: Dictionary in _seats:
						if int(st.table) == ti and bool(st.occ) and not (ti in busy):
							busy.append(ti)
				if busy.is_empty():
					_w_t = 3.0
					return
				_w_table = int(busy[randi() % busy.size()])
				_w_path = _waiter_path(_tables[_w_table])
				_w_i = 0
				_w_pos = _w_path[0]
				_w_carry = true
				_w_state = "out"
		"out", "back":
			if _w_i >= _w_path.size() - 1:
				if _w_state == "out":
					_w_state = "serve"
					_w_t = 1.6
					var tbl: Vector2 = _tables[_w_table] if _w_table >= 0 and _w_table < _tables.size() else _w_pos + Vector2.UP
					_w_dir = (tbl - _w_pos).normalized() if tbl != _w_pos else Vector2.UP
				else:
					_w_state = "inside"
					_w_t = randf_range(3.0, 7.0)
				return
			var target := _w_path[_w_i + 1]
			var before := _w_pos
			var to := target - _w_pos
			var step := WAITER_SPEED * delta
			if to.length() <= step:
				_w_pos = target
				_w_i += 1
			else:
				_w_pos += to.normalized() * step
			# katse aina kulkusuuntaan (todellinen siirtymä tältä ruudulta)
			var moved := _w_pos - before
			if moved.length() > 0.001:
				_w_dir = moved.normalized()
		"serve":
			_w_t -= delta
			if _w_carry and _w_t < 0.9:
				_w_carry = false   # juomat pöytään
			if _w_t <= 0.0:
				_w_path.reverse()
				_w_i = 0
				_w_state = "back"


func _draw_waiter() -> void:
	var col := 1
	if absf(_w_dir.x) > absf(_w_dir.y):
		col = 0 if _w_dir.x < 0.0 else 3
	else:
		col = 2 if _w_dir.y < 0.0 else 1
	var moving := _w_state == "out" or _w_state == "back"
	var tex := CS.staff(CS.WAITER, 1, col, (1 + int(_t * 6.0) % 2) if moving else 0)
	if tex == null:
		return
	draw_set_transform(_w_pos + Vector2(0, -0.5), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 4.5, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_texture(tex, _w_pos - Vector2(8.0, 15.0))
	# tarjotin: sivulla kulkiessa käden kohdalla, muuten edessä
	var tp := _w_pos + (Vector2(-12.0, -9.0) if col == 0 else (Vector2(4.0, -9.0) if col == 3 else Vector2(-4.0, -10.0)))
	draw_rect(Rect2(tp, Vector2(8.0, 1.5)), Color(0.75, 0.77, 0.8))
	if _w_carry:
		draw_rect(Rect2(tp + Vector2(2.0, -3.0), Vector2(2.0, 3.0)), Color(0.95, 0.7, 0.2))
		draw_rect(Rect2(tp + Vector2(5.0, -3.0), Vector2(2.0, 3.0)), Color(0.2, 0.75, 0.6))


# ----------------------------------------------------------------------------
#  PIIRTO
# ----------------------------------------------------------------------------
func _draw() -> void:
	if _lvl < 1 or yard.size.x <= 0.0:
		return
	var font := ThemeDB.fallback_font
	var deck := deck()
	# puukansi
	draw_rect(Rect2(deck.position + Vector2(1, 2), deck.size), Color(0, 0, 0, 0.25))
	draw_rect(deck, Color(0.55, 0.36, 0.2))
	var y := deck.position.y + 4.0
	while y < deck.end.y:
		draw_line(Vector2(deck.position.x, y), Vector2(deck.end.x, y), Color(0.4, 0.25, 0.13), 1.0)
		y += 4.0
	draw_rect(deck, Color(0.35, 0.2, 0.1), false, 1.0)
	# takakaide ja kauempi sivukaide (sisäänkäynti oven puolella)
	_rail(Vector2(deck.position.x, deck.position.y), Vector2(deck.end.x, deck.position.y))
	if _door_side_right():
		_rail(Vector2(deck.position.x, deck.position.y), Vector2(deck.position.x, deck.end.y))
	else:
		_rail(Vector2(deck.end.x, deck.position.y), Vector2(deck.end.x, deck.end.y))
	# ruukkukasvit kulmissa
	for pp: Vector2 in [deck.position + Vector2(4, 4), Vector2(deck.end.x - 4, deck.position.y + 4)]:
		draw_rect(Rect2(pp + Vector2(-3, -1), Vector2(6, 5)), Color(0.6, 0.32, 0.18))
		draw_circle(pp + Vector2(0, -3), 4.0, Color(0.18, 0.5, 0.25))
		draw_circle(pp + Vector2(-1, -4), 2.2, Color(0.3, 0.65, 0.3))
	# tuolit
	for s: Dictionary in _seats:
		var sp: Vector2 = s.pos
		draw_rect(Rect2(sp + Vector2(-3, -1), Vector2(6, 3)), Color(0.22, 0.22, 0.25))
	# takana istuvat (pöytä peittää alaosan)
	for s: Dictionary in _seats:
		if int(s.face) == 1:
			_person(s)
	# pöydät ja tuopit
	for ti in _tables.size():
		var c: Vector2 = _tables[ti]
		draw_set_transform(c + Vector2(0, 3), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.25))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(c + Vector2(-0.5, 0), Vector2(1, 4)), Color(0.2, 0.2, 0.22))
		draw_circle(c, 6.0, Color(0.88, 0.88, 0.86))
		draw_arc(c, 6.0, 0.0, TAU, 16, Color(0.6, 0.6, 0.62), 1.0)
		# pöydällä olevat juomat (niiden, jotka eivät juuri nyt juo)
		var k := 0
		for s: Dictionary in _seats:
			if int(s.table) != ti or not bool(s.occ) or float(s.sip) >= 0.0 or (_toast_left > 0.0 and _toast_table == ti):
				continue
			var gp := c + Vector2(-4.0 + (k % 3) * 4.0, -2.0 + int(k / 3) * 3.0)
			_glass(gp, int(s.drink), float(s.a))
			k += 1
	# sivuilla istuvat
	for s: Dictionary in _seats:
		if int(s.face) == 3 or int(s.face) == 0:
			_person(s)
	# edessä istuvat (selkä meihin)
	for s: Dictionary in _seats:
		if int(s.face) == 2:
			_person(s)
	# etukaide, aukko oven puolella
	if _door_side_right():
		_rail(Vector2(deck.position.x, deck.end.y), Vector2(deck.end.x - 14.0, deck.end.y))
	else:
		_rail(Vector2(deck.position.x + 14.0, deck.end.y), Vector2(deck.end.x, deck.end.y))
	# tarjoilija (palkattu): kulkee reittiä ovelta terassin sisäänkäynnin kautta pöytään
	if _w_state != "inside" and not _w_path.is_empty():
		_draw_waiter()
	# puhekuplat ja KIPPIS
	for s: Dictionary in _seats:
		if bool(s.occ) and float(s.say_t) > 0.0:
			var sp2: Vector2 = s.pos
			_text(font, sp2 + Vector2(-30, -16), str(s.say), 60.0, 6, Color(1, 1, 1, minf(float(s.say_t) * 2.0, 1.0)))
	if _toast_left > 0.0 and _toast_table >= 0 and _toast_table < _tables.size():
		_text(font, _tables[_toast_table] + Vector2(-30, -22), "KIPPIS!", 60.0, 8, Color(1.0, 0.9, 0.4))


## Istuva asiakas: yläruumis, juo välillä, nostaa lasin kilistyksessä.
func _person(s: Dictionary) -> void:
	if not bool(s.occ):
		return
	var face := int(s.face)
	var row := int(s.row)
	var base := CS.npc(face, row)
	var tex := CS.seated(base)
	if tex == null:
		return
	# räpsytys
	var ph := float(s.pos.x) * 0.37
	if fmod(_t + ph, 4.0 + fmod(ph, 1.5)) < 0.12:
		var bl := CS.blink(tex)
		if bl:
			tex = bl
	var sp: Vector2 = s.pos
	var bob := sin(_t * 1.5 + ph) * 0.3
	var a := float(s.a)
	draw_texture(tex, sp - Vector2(8.0, 12.0 + bob), Color(1, 1, 1, a))
	# lasi kädessä: juominen tai kilistys
	var toasting := _toast_left > 0.0 and int(s.table) == _toast_table
	var head := sp + Vector2(0, -8.0)
	var hand_x := 4.0 if face == 3 else (-4.0 if face == 0 else 3.0)
	if toasting:
		var c: Vector2 = _tables[int(s.table)]
		var k := 1.0 - absf(_toast_left / 1.6 * 2.0 - 1.0)
		_glass(head.lerp(c + Vector2(0, -12), k) + Vector2(hand_x * 0.5, 0), int(s.drink), a)
	elif float(s.sip) >= 0.0 and face != 2:
		var k2 := sin(clampf(float(s.sip) / 1.3, 0.0, 1.0) * PI)
		_glass(sp + Vector2(hand_x, -3.0).lerp(head + Vector2(hand_x * 0.6, 1.0), k2), int(s.drink), a)


## Juoma: 0 olut, 1 lonkero, 2 viinilasi
func _glass(p: Vector2, kind: int, a: float = 1.0) -> void:
	match kind:
		0:
			draw_rect(Rect2(p + Vector2(-1, -3), Vector2(2.5, 3.5)), Color(0.95, 0.68, 0.15, a))
			draw_rect(Rect2(p + Vector2(-1, -3.8), Vector2(2.5, 1.0)), Color(1, 1, 0.95, a))
		1:
			draw_rect(Rect2(p + Vector2(-1, -3.5), Vector2(2, 3.5)), Color(0.2, 0.75, 0.6, a))
		_:
			draw_rect(Rect2(p + Vector2(-1.2, -3.5), Vector2(2.4, 2)), Color(0.7, 0.1, 0.2, a))
			draw_line(p + Vector2(0, -1.5), p, Color(1, 1, 1, 0.7 * a), 1.0)


func _rail(a: Vector2, b: Vector2) -> void:
	draw_line(a + Vector2(0, -4), b + Vector2(0, -4), Color(0.32, 0.18, 0.08), 1.5)
	draw_line(a + Vector2(0, -1), b + Vector2(0, -1), Color(0.32, 0.18, 0.08), 1.0)
	var n := int(a.distance_to(b) / 8.0)
	for k in n + 1:
		var p := a.lerp(b, float(k) / maxf(n, 1))
		draw_rect(Rect2(p + Vector2(-0.5, -5), Vector2(1.5, 5)), Color(0.25, 0.14, 0.06))


func _text(font: Font, pos: Vector2, txt: String, width: float, fs: int, col: Color) -> void:
	TextFit.draw_outline(self, font, pos, txt, width, fs, 3, Color(0, 0, 0, 0.8 * col.a))
	TextFit.draw(self, font, pos, txt, width, fs, col)


## Päivänvarjot (Terassi 1) tai kangaskatos ja lämmittimet (Terassi 2): ihmisten yläpuolella.
class RoofView extends Node2D:
	var terrace: Node2D = null

	func _draw() -> void:
		if terrace == null:
			return
		var lvl: int = terrace.get("_lvl")
		if lvl < 1:
			return
		var tables: Array = terrace.get("_tables")
		var deck: Rect2 = terrace.deck()
		if deck.size.x <= 0.0:
			return
		if lvl >= 2:
			# kangaskatos tolppineen (raidallinen)
			var can := Rect2(deck.position.x - 2.0, deck.position.y - 14.0, deck.size.x + 4.0, 9.0)
			for px: float in [deck.position.x + 1.0, deck.end.x - 2.0]:
				draw_rect(Rect2(px, can.end.y, 1.5, deck.size.y + 8.0), Color(0.3, 0.3, 0.32))
			draw_rect(Rect2(can.position + Vector2(0, 3), can.size), Color(0, 0, 0, 0.25))
			draw_rect(can, Color(0.55, 0.1, 0.16))
			var cs := can.position.x
			var n := 0
			while cs < can.end.x:
				if n % 2 == 0:
					draw_rect(Rect2(cs, can.position.y, 4.0, can.size.y), Color(0.95, 0.93, 0.88))
				draw_circle(Vector2(cs + 2.0, can.end.y), 2.0, Color(0.55, 0.1, 0.16) if n % 2 == 1 else Color(0.95, 0.93, 0.88))
				cs += 4.0
				n += 1
			# lämmittimet
			for hx: float in [deck.position.x + 6.0, deck.end.x - 6.0]:
				var hp := Vector2(hx, deck.end.y - 2.0)
				draw_rect(Rect2(hp + Vector2(-0.75, -16), Vector2(1.5, 16)), Color(0.55, 0.55, 0.6))
				draw_rect(Rect2(hp + Vector2(-3, -18), Vector2(6, 2)), Color(0.4, 0.4, 0.45))
		else:
			# päivänvarjot pöytien yllä
			for ti in tables.size():
				var c: Vector2 = tables[ti]
				var top := c + Vector2(0, -20)
				draw_rect(Rect2(c + Vector2(-0.5, -20), Vector2(1, 14)), Color(0.85, 0.85, 0.85))
				draw_set_transform(top + Vector2(0, 2), 0.0, Vector2(1.0, 0.55))
				draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.15))
				draw_set_transform(top, 0.0, Vector2(1.0, 0.55))
				var col := Color(0.75, 0.12, 0.18) if ti % 2 == 0 else Color(0.15, 0.4, 0.7)
				draw_circle(Vector2.ZERO, 10.0, col)
				for k in 8:
					if k % 2 == 0:
						var a1 := k * TAU / 8.0
						draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2.from_angle(a1) * 10.0, Vector2.from_angle(a1 + TAU / 8.0) * 10.0]), Color(0.97, 0.95, 0.9))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_circle(top, 1.0, Color(0.3, 0.3, 0.3))
