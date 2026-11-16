extends Node2D
## TORI: avoin kiveys kahdella kojulla.
##  - Auto-Make myy klassikkoauton (Car2D.make_classic, musta "Bemari 635 CSi") ja tuo tilauksesta
##    superauton (Furia V12). Ostettu auto odottaa näyttelypaikallaan.
##  - Kampaamo (Kampaaja-Kiki) tekee kampauksia (Game.HAIRS), mm. banaanikampauksen.
##  - Vaate-Vuokko myy paitoja ja housuja (Game.SHIRTS / Game.PANTS), jotka näkyvät
##    pelaajan ulkoasussa (CharSprites.outfit_frames). Ostetut vaatteet voi vaihtaa ilmaiseksi.
## CityGenerator luo tämän palvelukortteliin (SERVICE_ORDER "market") ja kutsuu setup():ia.

const CS := preload("res://scripts/core/CharSprites.gd")
const CAR_SCENE: PackedScene = preload("res://scenes/entities/vehicles/car.tscn")
const CAR_SCRIPT := preload("res://scripts/entities/Car2D.gd")
const TILE := 16.0
const OPEN := 8
const CLOSE := 20

var kind := "market"
var door_px := Vector2.ZERO          ## minikartan merkki (aukion keskellä)
var map_color := Color(0.98, 0.55, 0.15)
var letter := "T"
var area := Rect2()
var stall_cells: Array[Rect2i] = []  ## CityGenerator merkitsee nämä ruudut esteiksi
var classic_spot := Vector2.ZERO       ## klassikkoauton näyttelypaikka Auto-Maken kojun vieressä
var car_spot := Vector2.ZERO          ## superauton (Furia V12) näyttelypaikka
var _car_stall: Node2D
var _clothes_stall: Node2D
var _hair_stall: Node2D
var _display: Node2D
var _check_t := 1.0


func display_name() -> String:
	return "Tori"


func is_open() -> bool:
	return Game.is_open(OPEN, CLOSE)


func hours_text() -> String:
	return "auki %02d–%02d" % [OPEN, CLOSE]


## inner = korttelin sisäosa ruutuina, px = sama pikseleinä (maailma)
func setup(inner: Rect2i, px: Rect2) -> void:
	add_to_group("service")
	add_to_group("market")
	y_sort_enabled = true
	global_position = Vector2.ZERO
	area = px
	door_px = px.get_center()
	# kojut 3x2 ruutua: vierekkäin, kapeassa korttelissa allekkain
	var a := Rect2i(inner.position + Vector2i(1, 1), Vector2i(3, 2))
	var b := Rect2i(Vector2i(inner.end.x - 4, inner.position.y + 1), Vector2i(3, 2))
	if inner.size.x < 9:
		b = Rect2i(Vector2i(inner.end.x - 4, inner.position.y + 4), Vector2i(3, 2))
	stall_cells = [a, b]
	var ra := _cell_rect(inner, px, a)
	var rb := _cell_rect(inner, px, b)
	_car_stall = _make_stall(ra, "cars")
	_clothes_stall = _make_stall(rb, "clothes")
	# myytävä klassikko kojun vieressä (tai alla)
	if inner.size.x >= 11:
		classic_spot = Vector2(ra.end.x + 22.0, ra.end.y - 4.0)
	else:
		classic_spot = Vector2(ra.get_center().x, ra.end.y + 32.0)
	_display = ClassicDisplay.new()
	_display.position = classic_spot + Vector2(0.0, 8.0)
	_display.set("market", self)
	add_child(_display)
	# superauto korokkeella: aukion alareunan keskellä (kapeassa korttelissa oikeassa yläkulmassa)
	if inner.size.x >= 9:
		car_spot = Vector2(px.get_center().x, px.end.y - 26.0)
	else:
		car_spot = Vector2(px.end.x - 40.0, px.position.y + 30.0)
	var cd := CarDisplay.new()
	cd.position = car_spot + Vector2(0.0, 8.0)
	cd.set("market", self)
	add_child(cd)
	InteractSpot.create(self, car_spot + Vector2(0.0, 20.0), Vector2(40.0, 14.0), _car_prompt, _car_menu)
	# E-kohdat kojujen edessä
	InteractSpot.create(self, Vector2(ra.get_center().x, ra.end.y + 9.0), Vector2(44.0, 16.0), _classic_prompt, _classic_menu)
	InteractSpot.create(self, Vector2(rb.get_center().x, rb.end.y + 9.0), Vector2(44.0, 16.0), _clothes_prompt, _clothes_menu)
	InteractSpot.create(self, classic_spot + Vector2(0.0, 18.0), Vector2(36.0, 12.0), _classic_prompt, _classic_menu)
	# kampaamo: vapaa 3x2-paikka, joka ei osu muihin kojuihin eikä autojen näyttelypaikkoihin
	var keep_free: Array[Rect2] = [
		Rect2(classic_spot - Vector2(22.0, 16.0), Vector2(44.0, 44.0)),
		Rect2(car_spot - Vector2(24.0, 18.0), Vector2(48.0, 48.0)),
	]
	var cands: Array[Rect2i] = [
		Rect2i(Vector2i(inner.position.x + 1, inner.end.y - 3), Vector2i(3, 2)),
		Rect2i(Vector2i(inner.end.x - 4, inner.end.y - 3), Vector2i(3, 2)),
		Rect2i(Vector2i(inner.position.x + 1, inner.position.y + 4), Vector2i(3, 2)),
		Rect2i(Vector2i(inner.end.x - 4, inner.position.y + 4), Vector2i(3, 2)),
		Rect2i(Vector2i(inner.position.x + (inner.size.x - 3) / 2, inner.position.y + 1), Vector2i(3, 2)),
	]
	for hc: Rect2i in cands:
		if hc.position.y + hc.size.y + 1 > inner.end.y or hc.position.x < inner.position.x or hc.end.x > inner.end.x:
			continue
		var ok := true
		for other: Rect2i in stall_cells:
			if other.grow(1).intersects(hc):
				ok = false
		var hp := _cell_rect(inner, px, hc)
		var front := Rect2(hp.position.x, hp.end.y, hp.size.x, 18.0)
		for fr: Rect2 in keep_free:
			if fr.intersects(hp.grow(2.0)) or fr.intersects(front):
				ok = false
		if ok:
			stall_cells.append(hc)
			_hair_stall = _make_stall(hp, "hair")
			InteractSpot.create(self, Vector2(hp.get_center().x, hp.end.y + 9.0), Vector2(44.0, 16.0), _hair_prompt, _hair_menu)
			break
	if _hair_stall == null:
		# ei tilaa omalle kojulle: Vaate-Vuokko leikkaa hiuksetkin
		InteractSpot.create(self, Vector2(rb.get_center().x, rb.end.y + 24.0), Vector2(44.0, 12.0), _hair_prompt, _hair_menu)


func _cell_rect(inner: Rect2i, px: Rect2, c: Rect2i) -> Rect2:
	return Rect2(px.position + Vector2(c.position - inner.position) * TILE, Vector2(c.size) * TILE)


func _make_stall(r: Rect2, stall_kind: String) -> Node2D:
	var st := Stall.new()
	st.position = Vector2(r.position.x, r.end.y)
	st.set("w", r.size.x)
	st.set("h", r.size.y)
	st.set("kind", stall_kind)
	st.set("market", self)
	add_child(st)
	# kiinteä koju
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(r.size.x, r.size.y - 4.0)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	body.global_position = r.get_center() + Vector2(0.0, 2.0)
	return st


func _process(delta: float) -> void:
	# Tallennetut autot palautetaan torille / kartanolle (autoja ei tallenneta paikkoineen)
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 3.0
	if Game.owns_classic and _my_classic() == null and not _classic_restored:
		_spawn_classic(true)
		_classic_restored = true
	if Game.owns_supercar and _my_car() == null and not _car_restored:
		_spawn_car(true)
		_car_restored = true


var _classic_restored := false
var _car_restored := false


func _my_car() -> Node2D:
	for m in get_tree().get_nodes_in_group("supercar"):
		if is_instance_valid(m) and not Game.flag(m, "exploded"):
			return m as Node2D
	return null


func _spawn_car(restore: bool = false) -> Node2D:
	var car := CAR_SCENE.instantiate() as Node2D
	get_parent().add_child(car)
	car.global_position = _home_spot(2, car_spot) if restore else car_spot
	car.call("make_supercar")
	if restore:
		_to_garage(car)
	return car


# ----------------------------------------------------------------------------
#  SUPERAUTO (Auto-Make tuo tilauksesta)
# ----------------------------------------------------------------------------
func _car_prompt() -> String:
	if _my_car() != null:
		return "Furia V12 – sinun superautosi"
	if not is_open():
		return "Superauto (suljettu, %s)" % hours_text()
	return "Paina E: Furia V12 -superauto – %d $" % Game.SUPERCAR_PRICE


func _car_menu(player: Node2D) -> void:
	if _my_car() != null:
		Game.msg("Make: \"Pidä se ehjänä. Ei niitä ihan joka päivä tuoda Italiasta.\"", 3.0)
		return
	if not is_open():
		Game.msg("Make on lähtenyt kotiin. Auto odottaa aamuun.", 2.5)
		return
	_menu("AUTO-MAKE – FURIA V12\n\"Italialainen superauto, V12, kolmesataa heppaa ja vähän päälle. Kiihtyy ku raketti.\"\nHinta %d $  |  Lompakko %d $  |  Tili %d $" % [
		Game.SUPERCAR_PRICE, int(player.money), Game.bank],
		["Maksa käteisellä (%d $)" % Game.SUPERCAR_PRICE, "Maksa kortilla (%d $)" % Game.SUPERCAR_PRICE, "Ehkä joskus"],
		_car_choice.bind(player))


func _car_choice(i: int, player: Node2D) -> void:
	if i == 0:
		if int(player.money) < Game.SUPERCAR_PRICE:
			Sfx.play_ui("denied", -4.0)
			Game.msg("Make: \"Käteistä pitää olla %d $, kundi.\"" % Game.SUPERCAR_PRICE, 2.5)
			return
		player.add_money(-Game.SUPERCAR_PRICE)
	elif i == 1:
		if Game.bank < Game.SUPERCAR_PRICE:
			Sfx.play_ui("denied", -4.0)
			Game.msg("Kortti ei mennyt läpi – tilillä %d $." % Game.bank, 2.5)
			return
		Game.bank -= Game.SUPERCAR_PRICE
	else:
		return
	Game.owns_supercar = true
	_car_restored = true
	Sfx.play_ui("cash", -2.0)
	_spawn_car()
	Sfx.play("engine_start", car_spot, -2.0, 0.05, 0.7)
	Game.msg("Furia V12 on sun! Make: \"Avaimet virtalukossa. Älä aja sitä puuhun.\"", 4.0)


func _hud() -> Node:
	var sc := get_tree().current_scene
	return sc.get_node_or_null("Hud") if sc else null


func _menu(title: String, opts: Array, cb: Callable) -> void:
	var hud := _hud()
	if hud and hud.has_method("show_menu"):
		hud.show_menu(title, opts, cb)


## Ehjä oma klassikko kaupungissa, tai null
func _my_classic() -> Node2D:
	for m in get_tree().get_nodes_in_group("classic"):
		if is_instance_valid(m) and not Game.flag(m, "exploded"):
			return m as Node2D
	return null


func _spawn_classic(restore: bool = false) -> Node2D:
	var car := CAR_SCENE.instantiate() as Node2D
	get_parent().add_child(car)
	car.global_position = _home_spot(1, classic_spot) if restore else classic_spot
	car.call("make_classic")
	if restore:
		_to_garage(car)
	return car


## Kartanon omistajan kulkuneuvot palautuvat luksustalliin
func _to_garage(car: Node2D) -> void:
	if not Game.owns_manor:
		return
	var g := get_tree().get_first_node_in_group("luxury_garage")
	if g and g.has_method("store"):
		g.call("store", car)


## Kartanon omistajan kulkuneuvot palautuvat kartanon pihaan
func _home_spot(i: int, fallback: Vector2) -> Vector2:
	if Game.owns_manor:
		var manor := get_tree().get_first_node_in_group("manor")
		if manor and manor.has_method("parking_spot"):
			return manor.call("parking_spot", i)
	return fallback


# ----------------------------------------------------------------------------
#  AUTO-MAKE: KLASSIKKO
# ----------------------------------------------------------------------------
func _classic_prompt() -> String:
	if not is_open():
		return "Auto-Make on lähtenyt kotiin (%s)" % hours_text()
	if _my_classic() != null:
		return "Paina E: juttele Auto-Maken kanssa"
	return "Paina E: Auto-Make – Bemari 635 CSi %d $" % Game.CLASSIC_PRICE


func _classic_menu(player: Node2D) -> void:
	if not is_open():
		Game.msg("Koju on kiinni. Make tulee taas aamulla kahdeksalta.", 2.5)
		return
	if _my_classic() != null:
		Game.msg(["Make: \"No, miten se Bemari kulkee? Kuus sylinteriä rivissä, ei mitään hätää.\"",
			"Make: \"Muista: matala auto, ei reunakiviä. Ne kultavanteet on harvinaiset.\"",
			"Make: \"Hai-nokka halkoo ilmaa. Klassikko, kundi, klassikko.\""][randi() % 3], 3.0)
		return
	var lost := Game.owns_classic
	_menu("AUTO-MAKE – BEMARI 635 CSi\n\"%s\"\nHinta %d $  |  Lompakko %d $  |  Tili %d $" % [
		"Edellinen meni romuks? No, mul sattu olemaan toinen samanlainen." if lost else "Kasikytluvun hai-nokka. Musta, madallettu, kultaiset ristipinnat. Kulkee ku juna.",
		Game.CLASSIC_PRICE, int(player.money), Game.bank],
		["Maksa käteisellä (%d $)" % Game.CLASSIC_PRICE, "Maksa kortilla (%d $)" % Game.CLASSIC_PRICE, "Ei kiitos"],
		_classic_choice.bind(player))


func _classic_choice(i: int, player: Node2D) -> void:
	if i == 0:
		if int(player.money) < Game.CLASSIC_PRICE:
			Sfx.play_ui("denied", -4.0)
			Game.msg("Make: \"Käteistä pitää olla %d $, kundi.\"" % Game.CLASSIC_PRICE, 2.5)
			return
		player.add_money(-Game.CLASSIC_PRICE)
	elif i == 1:
		if Game.bank < Game.CLASSIC_PRICE:
			Sfx.play_ui("denied", -4.0)
			Game.msg("Kortti ei mennyt läpi – tilillä %d $." % Game.bank, 2.5)
			return
		Game.bank -= Game.CLASSIC_PRICE
	else:
		return
	Game.owns_classic = true
	_classic_restored = true
	Sfx.play_ui("cash", -4.0)
	_spawn_classic()
	Sfx.play("engine_start", classic_spot, -3.0, 0.05, 0.85)
	Game.msg("Bemari on sun! Se odottaa kojun vieressä – E kyytiin. Make: \"Pidä se mustana ja kiiltävänä.\"", 4.0)


# ----------------------------------------------------------------------------
#  VAATE-VUOKKO
# ----------------------------------------------------------------------------
func _clothes_prompt() -> String:
	if not is_open():
		return "Vaate-Vuokko on lähtenyt kotiin (%s)" % hours_text()
	return "Paina E: Vaate-Vuokko – vaatteet"


func _clothes_menu(player: Node2D) -> void:
	if not is_open():
		Game.msg("Koju on kiinni. Vuokko tulee taas aamulla kahdeksalta.", 2.5)
		return
	_menu("VAATE-VUOKKO\n\"Kulta, sä tarviit uuden lookin!\"\nLompakko %d $" % int(player.money),
		["Paidat ja takit", "Housut", "Hatut", "Lasit", "Hieno puku – koko setti (%d $)" % Game.SUIT_SET_PRICE], _clothes_cat.bind(player))


func _clothes_cat(i: int, player: Node2D) -> void:
	match i:
		0:
			_list(player, "shirt")
		1:
			_list(player, "pants")
		2:
			_list(player, "hat")
		3:
			_list(player, "glasses")
		4:
			_suit_set(player)


## Koko puku kerralla: takki, kauluspaita, kravatti ja puvun housut, puetaan heti päälle.
func _suit_set(player: Node2D) -> void:
	var have := Game.clothes_owned.has("suit") and Game.clothes_owned.has("suit_pants")
	if not have:
		if int(player.money) < Game.SUIT_SET_PRICE:
			Sfx.play_ui("denied", -4.0)
			Game.msg("Vuokko: \"Voi kulta, puku maksaa %d $.\"" % Game.SUIT_SET_PRICE, 2.5)
			return
		player.add_money(-Game.SUIT_SET_PRICE)
		for id: String in ["suit", "dress_tie", "suit_pants"]:
			if not Game.clothes_owned.has(id):
				Game.clothes_owned.append(id)
		Sfx.play_ui("cash", -4.0)
	Game.outfit["shirt"] = "suit"
	Game.outfit["pants"] = "suit_pants"
	Sfx.play_ui("clink", -8.0, 0.8)
	Game.msg("Vuokko: \"Takki, kauluspaita, kravatti ja suorat housut. Näytät pankinjohtajalta, kulta!\"", 3.5)


func _catalog(slot: String) -> Dictionary:
	match slot:
		"shirt":
			return Game.SHIRTS
		"hat":
			return Game.HATS
		"glasses":
			return Game.GLASSES
	return Game.PANTS


## Valikkoon mahtuu 9 riviä: pitkä luettelo jaetaan sivuihin ("Lisää…").
const PAGE := 8

func _list(player: Node2D, slot: String, page: int = 0) -> void:
	var cat := _catalog(slot)
	var all_ids: Array = cat.keys()
	var pages := maxi(1, ceili(float(all_ids.size()) / float(PAGE)))
	page = clampi(page, 0, pages - 1)
	var ids: Array = all_ids.slice(page * PAGE, page * PAGE + PAGE) if pages > 1 else all_ids
	var opts: Array = []
	for id: Variant in ids:
		var it: Array = cat[id]
		var sid := str(id)
		if str(Game.outfit.get(slot, "")) == sid:
			opts.append("%s (päällä)" % str(it[0]))
		elif Game.clothes_owned.has(sid):
			opts.append("%s (omistat – pue päälle)" % str(it[0]))
		else:
			opts.append("%s – %d $" % [str(it[0]), int(it[1])])
	if pages > 1:
		opts.append("Lisää… (sivu %d/%d)" % [(page + 1) % pages + 1, pages])
	var titles := {"shirt": "PAIDAT JA TAKIT", "pants": "HOUSUT", "hat": "HATUT", "glasses": "LASIT"}
	_menu("VAATE-VUOKKO – %s\nLompakko %d $" % [str(titles.get(slot, "")), int(player.money)],
		opts, _pick_page.bind(player, slot, ids, page, pages))


func _pick_page(i: int, player: Node2D, slot: String, ids: Array, page: int, pages: int) -> void:
	if pages > 1 and i == ids.size():
		_list(player, slot, (page + 1) % pages)
		return
	_pick(i, player, slot, ids, page)


func _pick(i: int, player: Node2D, slot: String, ids: Array, page: int = 0) -> void:
	if i < 0 or i >= ids.size():
		return
	var id := str(ids[i])
	var it: Array = _catalog(slot)[id]
	if str(Game.outfit.get(slot, "")) == id:
		Game.msg("Vuokko: \"Sehän on jo sun päällä, hassu!\"", 2.0)
		return
	if not Game.clothes_owned.has(id):
		var price := int(it[1])
		if int(player.money) < price:
			Sfx.play_ui("denied", -4.0)
			Game.msg("Vuokko: \"Voi kulta, rahat ei riitä. %d $.\"" % price, 2.5)
			return
		player.add_money(-price)
		Game.clothes_owned.append(id)
		Sfx.play_ui("cash", -4.0)
	Game.outfit[slot] = id
	Sfx.play_ui("clink", -8.0, 0.8)
	Game.msg("Vuokko: \"%s! Näytät ihan filmitähdeltä.\"" % str(it[0]), 2.5)
	_list(player, slot, page)


# ----------------------------------------------------------------------------
#  KAMPAAMO (Kampaaja-Kiki): kampaukset näkyvät pelaajan päässä (Player2D.HairView)
# ----------------------------------------------------------------------------
func _hair_prompt() -> String:
	if not is_open():
		return "Kampaamo on kiinni (%s)" % hours_text()
	return "Paina E: Kampaamo – kampaukset"


func _hair_menu(player: Node2D) -> void:
	if not is_open():
		Game.msg("Kampaamo on kiinni. Kiki tulee taas aamulla kahdeksalta.", 2.5)
		return
	var ids: Array = Game.HAIRS.keys()
	var opts: Array = []
	for id: Variant in ids:
		var it: Array = Game.HAIRS[id]
		var sid := str(id)
		if Game.hair == sid:
			opts.append("%s (nyt)" % str(it[0]))
		elif Game.hair_owned.has(sid):
			opts.append("%s (ilmainen muotoilu)" % str(it[0]))
		else:
			opts.append("%s – %d $" % [str(it[0]), int(it[1])])
	_menu("KAMPAAMO\n\"Istu alas, kulta! Mitä tänään tehdään?\"\nLompakko %d $" % int(player.money), opts, _hair_pick.bind(player, ids))


func _hair_pick(i: int, player: Node2D, ids: Array) -> void:
	if i < 0 or i >= ids.size():
		return
	var id := str(ids[i])
	var it: Array = Game.HAIRS[id]
	if Game.hair == id:
		Game.msg("Kiki: \"Sehän on jo päässä, ja näyttää hyvältä!\"", 2.0)
		return
	if not Game.hair_owned.has(id):
		var price := int(it[1])
		if int(player.money) < price:
			Sfx.play_ui("denied", -4.0)
			Game.msg("Kiki: \"Voi ei, rahat ei riitä. %d $, kulta.\"" % price, 2.5)
			return
		player.add_money(-price)
		Game.hair_owned.append(id)
		Sfx.play_ui("cash", -4.0)
	Game.hair = id
	Sfx.play_ui("clink", -8.0, 1.3)
	var lines := {
		"banana": "Kiki: \"Banaani! Rasvaa ja kampaa – Elviskin olis kateellinen.\"",
		"mohawk": "Kiki: \"Irokeesi! Nyt säikähtää mummotkin.\"",
		"afro": "Kiki: \"Afro! Ei mahu enää ovista sisään.\"",
		"bald": "Kiki: \"Kalju kiiltää. Klassikko.\"",
	}
	Game.msg(str(lines.get(id, "Kiki: \"%s! Näytät upealta.\"" % str(it[0]))), 3.0)


# ----------------------------------------------------------------------------
#  PIIRTO: KOJU (y-järjestys: solmu kojun etureunassa)
# ----------------------------------------------------------------------------
class Stall extends Node2D:
	const CS2 := preload("res://scripts/core/CharSprites.gd")
	var w := 48.0
	var h := 32.0
	var kind := "cars"
	var market: Node2D = null
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		var cam := get_viewport().get_camera_2d()
		if cam == null or cam.get_screen_center_position().distance_to(global_position) < 520.0:
			queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var open: bool = market != null and market.call("is_open")
		var stripe := Color(0.85, 0.15, 0.15) if kind == "cars" else (Color(0.85, 0.3, 0.65) if kind == "hair" else Color(0.15, 0.4, 0.8))
		var wood := Color(0.5, 0.32, 0.17)
		var wood_d := Color(0.32, 0.2, 0.1)
		# varjo ja tolpat
		draw_rect(Rect2(2.0, -4.0, w, 6.0), Color(0, 0, 0, 0.22))
		for px: float in [2.0, w - 4.0]:
			draw_rect(Rect2(px, -h - 14.0, 2.0, h + 12.0), wood_d)
		# takaseinä (kangas)
		draw_rect(Rect2(3.0, -h - 4.0, w - 6.0, 18.0), Color(0.93, 0.9, 0.82))
		# myyjä tiskin takana (vain aukioloaikana)
		if open:
			var row := 3 if kind == "cars" else (0 if kind == "hair" else 15)
			var look := 1 if fmod(_t, 7.0) < 5.0 else (0 if kind != "clothes" else 3)
			var tex := CS2.npc(look, row)
			if tex:
				var t := tex
				if fmod(_t + w, 4.1) < 0.12:
					var bl := CS2.blink(tex)
					if bl:
						t = bl
				var breath := 1.0 + 0.04 * maxf(sin(_t * 0.8), 0.0)
				var feet := Vector2(w * 0.5, -14.0)
				draw_texture_rect(t, Rect2(feet - Vector2(8.0, 16.0 * breath), Vector2(16.0, 16.0 * breath)), false)
		# vaatekojun henkarit sivuilla
		if kind == "clothes":
			var cols: Array = []
			for id: Variant in Game.SHIRTS:
				var c: Color = (Game.SHIRTS[id] as Array)[2]
				cols.append(c if c.a > 0.0 else Color(0.55, 0.56, 0.6))
			draw_line(Vector2(4.0, -h - 1.0), Vector2(16.0, -h - 1.0), Color(0.6, 0.6, 0.65), 1.0)
			draw_line(Vector2(w - 16.0, -h - 1.0), Vector2(w - 4.0, -h - 1.0), Color(0.6, 0.6, 0.65), 1.0)
			for k in 4:
				_shirt_icon(Vector2(6.0 + k * 3.2, -h + 4.0), cols[k % cols.size()], 0.7)
				_shirt_icon(Vector2(w - 14.0 + k * 3.2, -h + 4.0), cols[(k + 4) % cols.size()], 0.7)
		# tiski
		var counter := Rect2(0.0, -14.0, w, 14.0)
		draw_rect(counter, wood)
		draw_rect(Rect2(counter.position, Vector2(w, 3.0)), wood.lightened(0.25))
		for k in range(1, 4):
			draw_line(Vector2(0.0, -14.0 + k * 3.5 + 2.0), Vector2(w, -14.0 + k * 3.5 + 2.0), wood_d, 1.0)
		draw_rect(counter, wood_d, false, 1.0)
		# tavarat tiskillä
		if kind == "cars":
			draw_rect(Rect2(6.0, -17.0, 7.0, 3.0), Color(0.12, 0.13, 0.16))   # avaimenperä-laatikko
			draw_rect(Rect2(7.0, -16.5, 5.0, 1.0), Color(0.85, 0.7, 0.3))
			draw_rect(Rect2(17.0, -18.0, 4.0, 5.0), Color(0.2, 0.5, 0.25))    # öljykanisteri
			draw_line(Vector2(w - 18.0, -15.0), Vector2(w - 9.0, -16.5), Color(0.7, 0.72, 0.78), 1.5)   # jakoavain
			draw_circle(Vector2(w - 7.0, -16.0), 6.0, Color(0.12, 0.12, 0.14))   # vararengas
			draw_circle(Vector2(w - 7.0, -16.0), 3.0, Color(0.55, 0.57, 0.62))
		elif kind == "hair":
			# peili, sakset, föönit ja peruukkipäät
			draw_rect(Rect2(4.0, -20.0, 8.0, 7.0), Color(0.75, 0.85, 0.95))
			draw_rect(Rect2(4.0, -20.0, 8.0, 7.0), Color(0.85, 0.7, 0.35), false, 1.0)
			draw_line(Vector2(15.0, -16.0), Vector2(20.0, -18.0), Color(0.75, 0.77, 0.82), 1.0)
			draw_line(Vector2(15.0, -18.0), Vector2(20.0, -16.0), Color(0.75, 0.77, 0.82), 1.0)
			draw_circle(Vector2(15.0, -16.0), 0.9, Color(0.85, 0.2, 0.5))
			draw_circle(Vector2(15.0, -18.0), 0.9, Color(0.85, 0.2, 0.5))
			var hc_i := 0
			for id: Variant in ["banana", "mohawk", "afro"]:
				var hcol: Color = (Game.HAIRS[id] as Array)[2]
				var hx := w - 22.0 + hc_i * 8.0
				draw_circle(Vector2(hx, -17.0), 2.6, Color(0.93, 0.85, 0.75))
				draw_circle(Vector2(hx, -19.5), 2.4 if id != "afro" else 3.4, hcol)
				hc_i += 1
		else:
			var i := 0
			for id: Variant in Game.SHIRTS:
				var c: Color = (Game.SHIRTS[id] as Array)[2]
				if c.a <= 0.0:
					c = Color(0.55, 0.56, 0.6)
				var x := 4.0 + (i % 4) * 11.0
				var y := -16.0 - int(i / 4) * 2.0
				draw_rect(Rect2(x, y, 9.0, 3.0), c)
				draw_rect(Rect2(x, y, 9.0, 3.0), c.darkened(0.35), false, 0.5)
				i += 1
		# markiisi
		var aw := Rect2(-3.0, -h - 20.0, w + 6.0, 10.0)
		var sx := aw.position.x
		var n := 0
		while sx < aw.end.x:
			var sw := minf(6.0, aw.end.x - sx)
			draw_rect(Rect2(sx, aw.position.y, sw, aw.size.y), stripe if n % 2 == 0 else Color(0.97, 0.96, 0.92))
			sx += 6.0
			n += 1
		var x2 := aw.position.x
		var m := 0
		while x2 < aw.end.x - 1.0:
			draw_colored_polygon(PackedVector2Array([Vector2(x2, aw.end.y), Vector2(x2 + 6.0, aw.end.y), Vector2(x2 + 3.0, aw.end.y + 3.0)]),
				stripe if m % 2 == 0 else Color(0.97, 0.96, 0.92))
			x2 += 6.0
			m += 1
		draw_rect(aw, Color(0, 0, 0, 0.35), false, 1.0)
		# kyltti
		var sign_r := Rect2(w * 0.5 - 22.0, -h - 30.0, 44.0, 10.0)
		draw_rect(sign_r, Color(0.98, 0.95, 0.85))
		draw_rect(sign_r, wood_d, false, 1.0)
		TextFit.draw(self, font, sign_r.position + Vector2(0.0, 8.0), "AUTO-MAKE" if kind == "cars" else ("KAMPAAMO" if kind == "hair" else "VAATE-VUOKKO"), sign_r.size.x, 7, stripe.darkened(0.2))
		if not open:
			TextFit.draw_outline(self, font, Vector2(0.0, -4.0), "SULJETTU", w, 7, 3, Color(0, 0, 0, 0.8))
			TextFit.draw(self, font, Vector2(0.0, -4.0), "SULJETTU", w, 7, Color(1.0, 0.85, 0.5))

	func _shirt_icon(p: Vector2, c: Color, s: float) -> void:
		var pts := PackedVector2Array([p + Vector2(-2, 0) * s, p + Vector2(2, 0) * s, p + Vector2(4, 2) * s, p + Vector2(3, 3) * s,
			p + Vector2(2, 2.5) * s, p + Vector2(2, 8) * s, p + Vector2(-2, 8) * s, p + Vector2(-2, 2.5) * s, p + Vector2(-3, 3) * s, p + Vector2(-4, 2) * s])
		draw_colored_polygon(pts, c)


## Myytävä klassikko hintalapun kanssa (piilossa, kun oma klassikko on jo olemassa).
class ClassicDisplay extends Node2D:
	const CAR := preload("res://scripts/entities/Car2D.gd")
	var market: Node2D = null
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		var want: bool = market != null and market.call("_my_classic") == null
		if want != visible:
			visible = want
		if want:
			var cam := get_viewport().get_camera_2d()
			if cam == null or cam.get_screen_center_position().distance_to(global_position) < 520.0:
				queue_redraw()

	func _draw() -> void:
		var sf: SpriteFrames = CAR.classic_frames()
		if sf == null or not sf.has_animation(&"car_right"):
			return
		var tex := sf.get_frame_texture(&"car_right", 0)
		var sz := tex.get_size()
		draw_set_transform(Vector2(0.0, -1.0), 0.0, Vector2(1.0, 0.35))
		draw_circle(Vector2.ZERO, sz.x * 0.55, Color(0, 0, 0, 0.25))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_texture_rect(tex, Rect2(Vector2(-sz.x * 0.5, -sz.y), sz), false)
		# kiilto liukuu mustan maalin yli
		var gx := fmod(_t * 14.0, sz.x + 40.0) - 20.0 - sz.x * 0.5
		if gx > -sz.x * 0.5 and gx < sz.x * 0.5 - 3.0:
			draw_line(Vector2(gx, -sz.y + 2.0), Vector2(gx + 3.0, -3.0), Color(0.75, 0.85, 1.0, 0.22), 1.5)
		var bob := sin(_t * 3.0) * 1.0
		var tag := Rect2(-22.0, -sz.y - 13.0 + bob, 44.0, 11.0)
		draw_rect(tag, Color(1.0, 0.92, 0.2))
		draw_rect(tag, Color(0.85, 0.15, 0.15), false, 1.0)
		TextFit.draw(self, ThemeDB.fallback_font, tag.position + Vector2(0.0, 8.5), "%d $" % Game.CLASSIC_PRICE, tag.size.x, 8, Color(0.1, 0.1, 0.1))


## Superauto korokkeella (piilossa, kun oma superauto on jo kaupungissa).
class CarDisplay extends Node2D:
	const CAR := preload("res://scripts/entities/Car2D.gd")
	var market: Node2D = null
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		var want: bool = market != null and market.call("_my_car") == null
		if want != visible:
			visible = want
		if want:
			var cam := get_viewport().get_camera_2d()
			if cam == null or cam.get_screen_center_position().distance_to(global_position) < 520.0:
				queue_redraw()

	func _draw() -> void:
		var sf: SpriteFrames = CAR.supercar_frames()
		if sf == null or not sf.has_animation(&"car_right"):
			return
		var tex := sf.get_frame_texture(&"car_right", 0)
		var sz := tex.get_size()
		# pyöreä näyttelykoroke ja valot
		draw_set_transform(Vector2(0.0, -2.0), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 22.0, Color(0.15, 0.15, 0.18))
		draw_circle(Vector2.ZERO, 20.0, Color(0.3, 0.3, 0.34))
		draw_circle(Vector2.ZERO, 18.0, Color(1.0, 0.9, 0.5, 0.12 + 0.06 * sin(_t * 2.0)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_texture_rect(tex, Rect2(Vector2(-sz.x * 0.5, -sz.y - 2.0), sz), false)
		# kiilto liukuu yli
		var gx := fmod(_t * 18.0, sz.x + 30.0) - 15.0 - sz.x * 0.5
		draw_line(Vector2(gx, -sz.y), Vector2(gx + 4.0, -2.0), Color(1, 1, 1, 0.25), 2.0)
		var tag := Rect2(-24.0, -sz.y - 16.0, 48.0, 11.0)
		draw_rect(tag, Color(0.08, 0.08, 0.1))
		draw_rect(tag, Color(1.0, 0.8, 0.1), false, 1.0)
		TextFit.draw(self, ThemeDB.fallback_font, tag.position + Vector2(0.0, 8.5), "%d $" % Game.SUPERCAR_PRICE, tag.size.x, 8, Color(1.0, 0.85, 0.2))
