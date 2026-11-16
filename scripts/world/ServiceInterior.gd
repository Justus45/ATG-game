extends Node2D
## Kaupan ja pankin sisätilat (ServiceBuilding luo). Ovesta E vie sisään, sisällä ovelta ulos.
##
##  KAUPPA:  kylmäkaapit takaseinällä, kaksi hyllyriviä tuotteineen, hedelmä- ja vihannestiski,
##           kassa liukuhihnoineen, myyjä ja tupakkakaappi kassan takana, ostoskorit, tarjous-
##           julisteet, turvaportit ja loisteputkien valo. Asiakkaita hyllyjen välissä.
##           Kassalla E: kaupan valikko (ruoka, juomat, tupakka, veitsi...).
##  PANKKI:  marmorilattia ja punainen matto, tummat puupaneelit ja kultaiset kirjaimet,
##           kello, tiski lasiseinineen ja kolmella virkailijalla, holvin ovi, odotustila
##           nojatuoleineen, vuoronumeronäyttö ja -automaatti, pankkiautomaatti ja vartija.
##           Tiskillä tai pankkiautomaatilla E: pankin valikko.
## Sisätila sijaitsee kartan ulkopuolella (kuten koti, baari ja asekauppa). Sulkemisaikana
## henkilökunta ohjaa ulos.

const CS := preload("res://scripts/core/CharSprites.gd")
const TILE := 16
const W := 320.0
const H := 192.0
const ORIGINS := {"shop": Vector2(-3400.0, -1000.0), "bank": Vector2(-3400.0, 600.0)}

var building: Node2D = null      # ServiceBuilding
var kind := "shop"
## Onko pelaaja sisällä (minikartta piiloutuu, sää ja pimeys eivät näy)
var inside := false
var origin := Vector2.ZERO

var _busy := false
var _saved_limits := {}
var _fade: ColorRect
var _view: Node2D
## Ostoskori (kauppa): tuote-id:t, maksetaan kassalla. Ovesta ulos maksamatta = juoksuostokset.
var basket: Array[String] = []
var alarm_t := 0.0
var _basket_label: Label
const BASKET_MAX := 12
## Kaupan ryöstö (Kallen keikka): ampuma-ase esillä kassalla, kestää ROB_TIME sekuntia
const ROB_TIME := 22.0
const ROB_SPOT := Vector2(258.0, 146.0)
const ROB_RANGE := 46.0
var robbing := false
## Pankkikeikan tila (BankHeist.gd): "", "in", "alarm", "bomb", "blown", "looted"
var heist := ""
var rob_t := 0.0
var _rob_alarm := false
const WEAPON_ITEMS := ["pen", "knife"]
## Hälytyksen jälkeen poliisit rynnivät kauppaan sisälle (sekuntia hälytyksestä)
const COPS_DELAY := 5.0
const COPS_COUNT := 3
const COPS_WAVE2 := 9.0          ## toinen aalto näin monta sekuntia ensimmäisen jälkeen
const COPS_WAVE2_COUNT := 2
const CUSTOMER_CALL_AT := 0.5    ## sitomaton asiakas soittaa hätänumeroon tässä vaiheessa ryöstöä
## Panttivangit (nippusiteillä sidotut myyjä ja asiakkaat): poliisi ei hyökkää vaan neuvottelee
const RANSOM := 1500
const STANDOFF_MAX := 120.0      ## näin pitkän piirityksen jälkeen erikoisjoukot rynnäköivät (s)
const CAR_SCENE: PackedScene = preload("res://scenes/entities/vehicles/car.tscn")
var tied_customers := {}         ## asiakkaan indeksi (0, 1) -> paikka huoneessa
var standoff := false
var assault := false
var _standoff_t := 0.0
var _neg_fails := 0
var _neg_busy := false
var _wave2_eta := -1.0
var _customer_called := false
var _cops_eta := -1.0
var _cops: Array = []
## Myyjä sidottu nippusiteillä ryöstön aikana: hälytysnappi jää painamatta
var cashier_tied := false
## Asiakkaat ja myyjä pelkäävät (ryöstö käynnissä, poliisit sisällä tai juuri ryöstetty)
var panic_t := 0.0


func panic() -> bool:
	return robbing or panic_t > 0.0 or not _alive_cops().is_empty()


## Panttivankien määrä (sidottu myyjä + sidotut asiakkaat).
func hostages() -> int:
	return (1 if cashier_tied else 0) + tied_customers.size()


## Poliisi pysyy loitolla, kun kaupassa on panttivankeja eikä rynnäkkö ole alkanut.
func holding_off() -> bool:
	return hostages() > 0 and not assault


## Player2D.try_tie: sitoo lähimmän (myyjä kassalla tai pelokas asiakas). Palauttaa viestin,
## tai "" jos ketään ei sidottu.
func try_tie_in_room(player: Node2D) -> String:
	if kind != "shop":
		return ""
	var pp := player.global_position - origin
	var best := -1
	var best_d := 24.0
	if panic() and _view:
		var poss: Array = _view.get("cust_pos")
		for i in poss.size():
			if tied_customers.has(i):
				continue
			var d := pp.distance_to((poss[i] as Vector2) + Vector2(0.0, -7.0))
			if d < best_d:
				best_d = d
				best = i
	if best >= 0:
		tied_customers[best] = (_view.get("cust_pos") as Array)[best]
		if not _alive_cops().is_empty():
			_begin_standoff()
		return "Sidoit asiakkaan nippusiteillä – hän ei soita poliisille. Panttivankeja %d." % hostages()
	if pp.distance_to(ROB_SPOT) <= ROB_RANGE:
		if cashier_tied:
			Game.msg("Myyjä on jo sidottu.", 1.8)
			return ""
		if not robbing and not panic():
			Game.msg("Myyjä: \"Hei, mitä sä meinaat?!\" – sitominen vain ryöstön aikana.", 2.5)
			return ""
		cashier_tied = true
		if not _alive_cops().is_empty():
			_begin_standoff()
		if _rob_alarm:
			return "Sidoit myyjän – mutta hälytys ehti jo lähteä!"
		return "Sidoit myyjän nippusiteillä – hälytysnappi jäi painamatta."
	Game.msg("Ketään ei ole tarpeeksi lähellä sidottavaksi." if panic() else "Kaupassa ei ole ketään sidottavaa – ei ryöstöä käynnissä.", 2.0)
	return ""


## Piiritys alkaa: poliisit pysähtyvät oven luo, neuvottelija ottaa yhteyttä.
func _begin_standoff() -> void:
	if standoff or assault:
		return
	standoff = true
	_standoff_t = 0.0
	_neg_fails = 0
	for c in _alive_cops():
		c.call("say", ["Panttivankeja! Kaikki seis!", "Älä satuta ketään!"][randi() % 2], 2.5)
	Game.msg("Poliisi piirittää kaupan, mutta panttivangit pitävät heidät loitolla. Neuvottele kassalla (E).", 4.0)
	get_tree().create_timer(2.5).timeout.connect(_auto_negotiate)


func _auto_negotiate() -> void:
	var pl := get_tree().get_first_node_in_group("player") as Node2D
	if pl and inside and standoff and not assault:
		_negotiate(pl)


## Neuvottelu poliisin kanssa (kassan E-kohta piirityksen aikana).
func _negotiate(player: Node2D) -> void:
	var hud := _hud()
	if hud == null or not hud.has_method("show_menu") or _neg_busy:
		return
	var h := hostages()
	var opts: Array = [
		"Pakoauto oven eteen ja vapaa tie (%d %%)" % roundi(_chance("escape") * 100.0),
		"Lunnaat %d $ ja pakoauto (%d %%)" % [RANSOM, roundi(_chance("ransom") * 100.0)],
		"Vapauta panttivangit ja antaudu (lievempi tuomio)",
		"Ei vielä mitään",
	]
	hud.show_menu("NEUVOTTELIJA – POLIISI\n\"Sinulla on %d panttivankia. Ei kenenkään tarvitse kuolla. Mitä haluat?\"\nEpäonnistuneita yrityksiä %d/3" % [h, _neg_fails],
		opts, _neg_choice.bind(player))


func _chance(kind_s: String) -> float:
	var h := float(hostages())
	var c := (0.35 + 0.22 * h) if kind_s == "escape" else (0.12 + 0.2 * h)
	return clampf(c - 0.1 * float(_neg_fails), 0.05, 0.95)


func _neg_choice(i: int, player: Node2D) -> void:
	if i == 3 or i < 0:
		return
	if i == 2:
		_surrender()
		return
	_neg_busy = true
	var kind_s := "escape" if i == 0 else "ransom"
	Game.msg("Neuvottelija: \"Odota. Soitan päällikölle...\"", 2.5)
	await get_tree().create_timer(3.0).timeout
	_neg_busy = false
	if not inside or not standoff or assault or hostages() <= 0:
		return
	if randf() <= _chance(kind_s):
		_neg_success(player, kind_s == "ransom")
	else:
		_neg_fails += 1
		Sfx.play_ui("denied", -4.0)
		if _neg_fails >= 3:
			_begin_assault("Neuvottelut kariutuivat – erikoisjoukot rynnäköivät sisään!")
		else:
			Game.msg("Neuvottelija: \"Ei käy. Päällikkö sanoo ei.\" (%d/3) – yritä uudelleen kassalla." % _neg_fails, 3.0)


func _neg_success(player: Node2D, ransom: bool) -> void:
	if robbing:
		_finish_robbery(player)
	cashier_tied = false
	_clear_cops()
	if ransom:
		player.add_money(RANSOM)
		Sfx.play_ui("cash", -2.0)
	# pakoauto oven eteen, poliisi antaa hetken etumatkan
	var car := CAR_SCENE.instantiate() as Node2D
	if building and building.get_parent():
		building.get_parent().add_child(car)
		car.global_position = building.door_px + Vector2(0.0, 44.0)
	var pm := get_tree().get_first_node_in_group("police_manager")
	if pm:
		if pm.has_method("_clear_police"):
			pm.call("_clear_police")
		pm.set("_respawn_timer", 18.0)
	Game.msg("Neuvottelija: \"Sovittu.\" Panttivangit vapautetaan, %spakoauto odottaa oven edessä. Etumatkaa on vain hetki!" % ("lunnaat on maksettu, " if ransom else ""), 4.5)


func _surrender() -> void:
	cashier_tied = false
	robbing = false
	_clear_cops()
	var pm := get_tree().get_first_node_in_group("police_manager")
	if pm and pm.has_method("arrest"):
		var secs := int(float(pm.call("sentence_for_heat", int(pm.get("heat")))) * 0.6)
		pm.call("arrest", "Vapautit panttivangit ja antauduit. Tuomio on lievempi.", maxi(secs, 20))


func _begin_assault(text: String) -> void:
	standoff = false
	assault = true
	Game.msg(text, 3.5)
	_spawn_cops(COPS_WAVE2_COUNT, true)
	cops_hostile()


func _alive_cops() -> Array:
	var out: Array = []
	for c in _cops:
		if is_instance_valid(c) and not Game.flag(c, "dead"):
			out.append(c)
	return out


## Poliisit sisälle oven kautta.
func _spawn_cops(count: int = COPS_COUNT, swat: bool = false) -> void:
	_cops_eta = -1.0
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p == null or not inside:
		return
	Sfx.play("siren", origin + Vector2(W * 0.5, H - 10.0), -4.0, 0.0, 1.0)
	Sfx.play("door_open", origin + Vector2(W * 0.5, H - 20.0), -2.0, 0.1)
	var first := _cops.is_empty()
	if first:
		_wave2_eta = COPS_WAVE2
	for i in count:
		var cop := ShopCop.new()
		cop.room = self
		cop.z_index = 10
		add_child(cop)
		cop.global_position = origin + Vector2(W * 0.5 - 16.0 + i * 16.0, H - 18.0 - (i % 2) * 2.0)
		cop.post = Vector2(W * 0.5 - 40.0 + float(_cops.size() % 6) * 16.0, H - 34.0 - float(_cops.size() % 2) * 8.0)
		if swat:
			cop.hp = 5
			cop.modulate = Color(0.45, 0.45, 0.55)
		_cops.append(cop)
		(cop as ShopCop).say(["POLIISI! Kädet ylös!", "Pudota ase! Heti!", "Maahan!"][i % 3], 2.5)
	if hostages() > 0 and not assault:
		_begin_standoff()
	elif first:
		Game.msg("Poliisit ryntäsivät kauppaan! Pakene, antaudu – tai taistele. Lisää on tulossa!", 3.0)


func _clear_cops() -> void:
	for c in _cops:
		if is_instance_valid(c):
			c.queue_free()
	_cops.clear()
	_cops_eta = -1.0
	_wave2_eta = -1.0
	standoff = false
	assault = false
	tied_customers.clear()
	_customer_called = false


## Poliisi ammuttiin: kaikki sisällä olevat poliisit avaavat tulen (myös piiritys päättyy).
func cops_hostile() -> void:
	if standoff:
		standoff = false
		assault = true
		Game.msg("Ammuit poliisia – neuvottelut ovat ohi!", 2.5)
	for c in _alive_cops():
		c.set("hostile", true)


func setup(b: Node2D, p_kind: String) -> void:
	building = b
	kind = p_kind
	add_to_group("indoor_room")
	origin = ORIGINS.get(kind, Vector2(-3400.0, -1000.0))
	position = origin
	z_index = -10   # hahmot (pelaaja) piirtyvät sisustuksen päälle
	# tausta
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04)
	bg.position = Vector2(-1500.0, -1500.0)
	bg.size = Vector2(3000.0 + W, 3000.0 + H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -20
	add_child(bg)
	_view = (ShopView.new() if kind == "shop" else BankView.new()) as Node2D
	_view.set("room", self)
	add_child(_view)
	# seinät
	for r: Rect2 in [Rect2(0, 0, W, 32), Rect2(0, 0, 16, H), Rect2(W - 16, 0, 16, H), Rect2(0, H - 16, W, 16)]:
		_block(r)
	for r: Rect2 in _view.call("solids"):
		_block(r)
	# ovi ulos
	InteractSpot.create(self, origin + Vector2(W * 0.5, H - 26.0), Vector2(26.0, 18.0), Callable(self, "_door_prompt"), Callable(self, "_exit_door"))
	# palvelupisteet ja hyllyt
	for spot: Array in _view.call("spots"):
		var sp: Vector2 = spot[1]
		InteractSpot.create(self, origin + (spot[0] as Vector2), sp, spot[2], spot[3])
	# häivytys
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	if kind == "shop":
		var ui := CanvasLayer.new()
		ui.layer = 5
		add_child(ui)
		_basket_label = Label.new()
		_basket_label.position = Vector2(20.0, 188.0)
		_basket_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ls := LabelSettings.new()
		ls.font_size = 13
		ls.outline_size = 4
		ls.outline_color = Color(0, 0, 0, 0.9)
		ls.font_color = Color(1.0, 0.95, 0.75)
		_basket_label.label_settings = ls
		_basket_label.visible = false
		ui.add_child(_basket_label)
		_refresh_basket()


func _block(r: Rect2) -> void:
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	body.position = r.get_center()


func _process(delta: float) -> void:
	if alarm_t > 0.0:
		alarm_t -= delta
	if panic_t > 0.0:
		panic_t -= delta
	if _cops_eta > 0.0 and inside and not _busy:
		_cops_eta -= delta
		if _cops_eta <= 0.0:
			_spawn_cops()
	if _wave2_eta > 0.0 and inside and not _busy:
		_wave2_eta -= delta
		if _wave2_eta <= 0.0:
			_wave2_eta = -1.0
			_spawn_cops(COPS_WAVE2_COUNT, true)
	if standoff and inside:
		_standoff_t += delta
		if _standoff_t >= STANDOFF_MAX:
			_begin_assault("Poliisin kärsivällisyys loppui – erikoisjoukot rynnäköivät!")
	if _basket_label:
		_basket_label.visible = inside
	if not inside or _busy:
		return
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if robbing:
		_update_robbery(p, delta)
	# turvaverkko: pelaaja siirretty muualle (esim. pidätys)
	if p and p.global_position.distance_to(origin) > 1200.0:
		inside = false
		robbing = false
		_clear_cops()
		cashier_tied = false
		basket.clear()
		_refresh_basket()
		_set_camera_limits(false)
		return
	if heist == "" and building and building.has_method("is_open") and not building.is_open():
		Game.msg("%s: \"Suljetaan! Tervetuloa huomenna.\"" % ("Myyjä" if kind == "shop" else "Vartija"), 2.5)
		if not basket.is_empty():
			basket.clear()
			_refresh_basket()
		leave(p)


# ----------------------------------------------------------------------------
#  SISÄÄN JA ULOS
# ----------------------------------------------------------------------------
func enter(player: Node2D) -> void:
	await _move(player, true)


func leave(player: Node2D) -> void:
	if player:
		await _move(player, false)


func _move(player: Node2D, to_inside: bool) -> void:
	if _busy or player == null:
		return
	_busy = true
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	if "velocity" in player:
		player.velocity = Vector2.ZERO
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud:
		hud.hide_instruction()
	Sfx.play("door_open", player.global_position, -6.0, 0.1)
	await _fade_to(1.0)
	if to_inside:
		inside = true
		_set_camera_limits(true)
		_move_player(player, origin + Vector2(W * 0.5, H - 40.0))
		if kind == "shop":
			Sfx.play("phone", origin + Vector2(W * 0.5, H - 30.0), -16.0, 0.0, 1.8)   # ovikello
	else:
		inside = false
		_set_camera_limits(false)
		_clear_cops()
		cashier_tied = false
		_move_player(player, building.door_px + Vector2(0.0, 28.0))
	await _fade_to(0.0)
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	_busy = false


func _fade_to(alpha: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, 0.18)
	await tw.finished


func _move_player(player: Node2D, target: Vector2) -> void:
	var col := player.get_node_or_null("CollisionShape2D") as Node2D
	var off := col.position if col else Vector2.ZERO
	player.global_position = target - off
	var cam := get_viewport().get_camera_2d()
	if cam:
		cam.global_position = target


func _set_camera_limits(in_room: bool) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	if in_room:
		if _saved_limits.is_empty():
			_saved_limits = {"l": cam.limit_left, "t": cam.limit_top, "r": cam.limit_right, "b": cam.limit_bottom}
		var r := Rect2(origin, Vector2(W, H)).grow(260.0)
		cam.limit_left = int(r.position.x)
		cam.limit_top = int(r.position.y)
		cam.limit_right = int(r.end.x)
		cam.limit_bottom = int(r.end.y)
	elif not _saved_limits.is_empty():
		cam.limit_left = _saved_limits.l
		cam.limit_top = _saved_limits.t
		cam.limit_right = _saved_limits.r
		cam.limit_bottom = _saved_limits.b
		_saved_limits = {}


## Palvelupisteen toiminto: avaa rakennuksen valikon (kauppa / pankki)
func open_menu(player: Node2D) -> void:
	if building and building.has_method("open_menu"):
		building.open_menu(player)


# ----------------------------------------------------------------------------
#  OSTOSKORI, KASSA JA JUOKSUOSTOKSET
# ----------------------------------------------------------------------------
func _hud() -> Node:
	var sc := get_tree().current_scene
	return sc.get_node_or_null("Hud") if sc else null


func _item_name(id: String) -> String:
	return str(building.call("item_name", id)) if building else id


func _item_price(id: String) -> int:
	return int(building.call("item_price", id)) if building else 0


func basket_total() -> int:
	var t := 0
	for id: String in basket:
		t += _item_price(id)
	return t


func _basket_lines() -> String:
	var counts := {}
	var order: Array[String] = []
	for id: String in basket:
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] = int(counts[id]) + 1
	var parts: Array[String] = []
	for id: String in order:
		var n := int(counts[id])
		parts.append(("%dx %s" % [n, _item_name(id)]) if n > 1 else _item_name(id))
	return ", ".join(parts)


func _refresh_basket() -> void:
	if _basket_label == null:
		return
	if robbing:
		_basket_label.text = "RYÖSTÖ: myyjä tyhjentää kassaa... %d %%\nPysy kassalla ase esillä!" % roundi(rob_t / ROB_TIME * 100.0)
	elif basket.is_empty():
		_basket_label.text = "OSTOSKORI: tyhjä\nOta tuotteita hyllyistä (E), maksa kassalla"
	else:
		_basket_label.text = "OSTOSKORI  %d $\n%s" % [basket_total(), _basket_lines()]


## Hyllyn E-toiminto: tuote koriin
func take_item(player: Node2D, id: String) -> void:
	if basket.size() >= BASKET_MAX:
		Sfx.play_ui("denied", -8.0)
		Game.msg("Kori on täynnä. Käy kassalla.", 1.8)
		return
	if id in WEAPON_ITEMS:
		if player.has_method("has_weapon") and player.has_weapon():
			Sfx.play_ui("denied", -8.0)
			Game.msg("Kädet täynnä – pudota ensin ase (G).", 2.0)
			return
		for w: String in WEAPON_ITEMS:
			if basket.has(w):
				Sfx.play_ui("denied", -8.0)
				Game.msg("Korissa on jo yksi teräase.", 1.8)
				return
	basket.append(id)
	Sfx.play_ui("clink", -10.0, 1.4)
	Game.msg("%s koriin (%d $). Korissa yhteensä %d $." % [_item_name(id), _item_price(id), basket_total()], 1.6)
	_refresh_basket()


func register_prompt() -> String:
	if standoff:
		return "Paina E: neuvottele poliisin kanssa (%d panttivankia)" % hostages()
	if basket.is_empty():
		return "Paina E: kassa (tupakka tiskin takaa)"
	return "Paina E: kassa – maksa %d $ käteisellä tai kortilla" % basket_total()


func _door_prompt() -> String:
	if kind == "shop" and not basket.is_empty():
		return "Paina E: lähde maksamatta (%d $)... juoksuostokset!" % basket_total()
	return "Paina E poistuaksesi"


## Kassan valikko
func checkout(player: Node2D) -> void:
	if standoff:
		_negotiate(player)
		return
	var hud := _hud()
	if hud == null or not hud.has_method("show_menu"):
		return
	var total := basket_total()
	var title := "KASSA\n"
	if basket.is_empty():
		title += "Kori on tyhjä. Ota tuotteita hyllyistä."
	else:
		title += "%s\nYhteensä %d $" % [_basket_lines(), total]
	title += "\nLompakko %d $  |  Tili %d $" % [int(player.money), Game.bank]
	var cig := _item_price("cigs")
	var opts: Array = [
		"Maksa käteisellä (%d $)" % total,
		"Maksa kortilla (%d $)" % total,
		"Tupakka-aski tiskin takaa koriin (%d $, taskussa %d)" % [cig, Game.cigarettes],
		"Palauta tuotteet hyllyyn",
	]
	if _can_rob(player):
		opts.append("RYÖSTÄ KASSA (ase esiin)")
	hud.show_menu(title, opts, _checkout_choice.bind(player))


func _checkout_choice(i: int, player: Node2D) -> void:
	match i:
		0:
			_pay_basket(player, false)
		1:
			_pay_basket(player, true)
		2:
			if basket.size() >= BASKET_MAX:
				Game.msg("Kori on täynnä.", 1.8)
				return
			basket.append("cigs")
			Sfx.play_ui("clink", -10.0, 1.2)
			_refresh_basket()
			checkout(player)
		3:
			if not basket.is_empty():
				basket.clear()
				_refresh_basket()
				Game.msg("Tuotteet palautettu hyllyyn.", 1.6)
		4:
			_start_robbery(player)


# ----------------------------------------------------------------------------
#  KAUPAN RYÖSTÖ
# ----------------------------------------------------------------------------
func _story() -> Node:
	return get_tree().get_first_node_in_group("story")


## Ryöstö on mahdollinen Kallen keikan jälkeen, ampuma-ase kädessä.
func _can_rob(player: Node2D) -> bool:
	if kind != "shop" or robbing:
		return false
	var st := _story()
	if st == null or not st.has_method("rob_unlocked") or not st.rob_unlocked():
		return false
	return player.has_method("has_ranged_weapon") and player.has_ranged_weapon()


func rob_progress() -> float:
	return rob_t / ROB_TIME


func _start_robbery(player: Node2D) -> void:
	if not _can_rob(player):
		return
	if int(Game.story.get("rob_day", -1)) == Game.day:
		Game.msg("Myyjä: \"Kassa on jo tyhjä! Te kävitte jo tänään!\"", 2.5)
		return
	basket.clear()
	robbing = true
	panic_t = 20.0
	rob_t = 0.0
	_rob_alarm = false
	Sfx.play_ui("denied", -2.0, 0.7)
	Game.msg("Sinä: \"Kassa tyhjäks, heti!\"  Myyjä: \"Älä ammu! Mä teen sen, mä teen sen!\"", 3.0)
	_refresh_basket()


func _update_robbery(p: Node2D, delta: float) -> void:
	var ok: bool = p != null and p.has_method("has_ranged_weapon") and p.has_ranged_weapon() \
		and p.global_position.distance_to(origin + ROB_SPOT) < ROB_RANGE
	if not ok:
		robbing = false
		Game.msg("Ryöstö keskeytyi – myyjä sulki kassan.", 2.5)
		_refresh_basket()
		return
	var before := rob_t
	rob_t += delta
	if int(before) != int(rob_t):
		Sfx.play_ui("coin", -14.0, 0.9 + randf() * 0.3)
		_refresh_basket()
	# myyjä painaa salaa hälytysnappia
	# sitomaton asiakas soittaa salaa hätänumeroon
	if not _rob_alarm and not _customer_called and tied_customers.size() < 2 and rob_t >= ROB_TIME * CUSTOMER_CALL_AT:
		_customer_called = true
		_rob_alarm = true
		Game.msg("Asiakas soitti salaa hätänumeroon! Poliisi on tulossa.", 3.0)
		var pm0 := get_tree().get_first_node_in_group("police_manager")
		if pm0 and pm0.has_method("report_crime"):
			pm0.report_crime(5, true)
		_cops_eta = COPS_DELAY
	if not _rob_alarm and not cashier_tied and rob_t >= ROB_TIME * 0.25:
		_rob_alarm = true
		Game.msg("Myyjä painoi hälytysnappia tiskin alla! Poliisi on tulossa.", 3.0)
		Sfx.play("siren", origin + Vector2(W * 0.5, H - 30.0), -10.0, 0.0, 1.8)
		var pm := get_tree().get_first_node_in_group("police_manager")
		if pm and pm.has_method("report_crime"):
			pm.report_crime(5, true)
		_cops_eta = COPS_DELAY
	if rob_t >= ROB_TIME:
		_finish_robbery(p)


func _finish_robbery(p: Node2D) -> void:
	robbing = false
	panic_t = 15.0
	var cash := randi_range(380, 620)   # vaikeampi ryöstö, isompi saalis
	p.add_money(cash)
	Game.story["rob_day"] = Game.day
	Game.add_rep("criminals", 4)
	Game.add_vitutus(Game.VITUTUS_CRIME * 2.0)
	Sfx.play_ui("cash", -2.0)
	var pm := get_tree().get_first_node_in_group("police_manager")
	if pm and pm.has_method("report_crime"):
		pm.report_crime(4, true)
	Game.msg("Kassa tyhjä: +%d $! Häivy ennen kuin kytät tulee!" % cash, 3.0)
	var st := _story()
	if st and st.has_method("on_shop_robbed"):
		st.on_shop_robbed(cash)
	_refresh_basket()


func _strip_weapons(player: Node2D) -> void:
	if not (player.has_method("has_weapon") and player.has_weapon()):
		return
	for w: String in WEAPON_ITEMS:
		if basket.has(w):
			basket.erase(w)
			Game.msg("Kädet täynnä – %s jäi hyllyyn." % _item_name(w), 2.0)


func _pay_basket(player: Node2D, card: bool) -> void:
	if basket.is_empty():
		Game.msg("Myyjä: \"Ei mitään maksettavaa. Hyllyistä saa ottaa!\"", 2.0)
		return
	_strip_weapons(player)
	var total := basket_total()
	if card:
		if Game.bank < total:
			Sfx.play_ui("denied", -4.0)
			Game.msg("Kortti hylätty – tilillä vain %d $ (tarvitaan %d $)." % [Game.bank, total], 2.5)
			return
		Game.bank -= total
	else:
		if int(player.money) < total:
			Sfx.play_ui("denied", -4.0)
			Game.msg("Käteinen ei riitä (%d $ / %d $). Kokeile korttia." % [int(player.money), total], 2.5)
			return
		player.add_money(-total)
	Sfx.play_ui("cash", -4.0)
	var lines := _basket_lines()
	_apply_basket(player)
	Game.msg("%s maksettu (%d $): %s. Myyjä: \"Kiitos, tervetuloa uudelleen!\"" % ["Kortilla" if card else "Käteisellä", total, lines], 3.0)


func _apply_basket(player: Node2D) -> void:
	var items: Array = basket.duplicate()
	basket.clear()
	for id: Variant in items:
		if building and building.has_method("apply_item"):
			building.apply_item(player, str(id))
	_refresh_basket()


## Oven E-toiminto: maksamaton kori = juoksuostokset
func _exit_door(player: Node2D) -> void:
	if heist != "":
		var hz := get_tree().get_first_node_in_group("bank_heist")
		if hz and hz.has_method("on_exit_door"):
			hz.on_exit_door(player)
		return
	if robbing:
		robbing = false
		Game.msg("Lähdit kesken ryöstön – kassa jäi tyhjentämättä.", 2.5)
		_refresh_basket()
	if kind != "shop" or basket.is_empty():
		leave(player)
		return
	if _busy:
		return
	var total := basket_total()
	var lines := _basket_lines()
	alarm_t = 2.5
	Sfx.play("siren", origin + Vector2(W * 0.5, H - 30.0), -6.0, 0.0, 1.8)
	Sfx.play_ui("denied", -2.0, 1.5)
	Game.msg("Myyjä: \"HEI! Toi on maksamatta!\" – hälytysportit piippaa!", 2.0)
	await leave(player)
	# saalis kulkee mukana: kotona ruoat jääkaappiin, esineet lattialle (Home.gd)
	for id: String in basket:
		Game.loot.append(id)
	basket.clear()
	_refresh_basket()
	Sfx.play("siren", building.door_px, -4.0, 0.0, 1.8)
	Game.add_vitutus(Game.VITUTUS_CRIME)
	var pm := get_tree().get_first_node_in_group("police_manager")
	if pm and pm.has_method("report_crime"):
		pm.report_crime(3 if total >= 15 else 2)
	Game.msg("Juoksuostokset (%d $): %s. Poliisi on perässä – vie saalis kotiin!" % [total, lines], 3.5)


# ----------------------------------------------------------------------------
#  KAUPPA
# ----------------------------------------------------------------------------
class ShopView extends "res://scripts/world/ServiceRoomView.gd":
	const FRIDGES := Rect2(20.0, 32.0, 176.0, 20.0)
	const GONDOLA_A := Rect2(56.0, 74.0, 18.0, 64.0)
	const GONDOLA_B := Rect2(116.0, 74.0, 18.0, 64.0)
	const FRUIT := Rect2(184.0, 72.0, 48.0, 26.0)
	const COUNTER := Rect2(228.0, 124.0, 62.0, 14.0)
	const TOBACCO := Rect2(290.0, 60.0, 14.0, 52.0)
	const CANDY := Rect2(214.0, 140.0, 12.0, 22.0)

	func solids() -> Array:
		return [FRIDGES, GONDOLA_A, GONDOLA_B, FRUIT, COUNTER, TOBACCO, CANDY]

	func spots() -> Array:
		var take := Callable(room, "take_item")
		return [
			[Vector2(258.0, 150.0), Vector2(40.0, 18.0), Callable(room, "register_prompt"), Callable(room, "checkout")],
			[Vector2(64.0, 60.0), Vector2(84.0, 14.0), "Paina E: Energiajuoma koriin (3 $, väsymys -20)", take.bind("energy")],
			[Vector2(152.0, 60.0), Vector2(84.0, 14.0), "Paina E: Makkara koriin (4 $, nälkä -30)", take.bind("sausage")],
			[Vector2(47.0, 106.0), Vector2(14.0, 56.0), "Paina E: Einesateria koriin (6 $, jääkaappiin)", take.bind("meal")],
			[Vector2(83.0, 106.0), Vector2(14.0, 56.0), "Paina E: Ruokakassi koriin (15 $, 3 annosta jääkaappiin)", take.bind("bag")],
			[Vector2(107.0, 106.0), Vector2(14.0, 56.0), "Paina E: Kuulakärkikynä koriin (1 $)", take.bind("pen")],
			[Vector2(143.0, 106.0), Vector2(14.0, 56.0), "Paina E: Keittiöveitsi koriin (20 $)", take.bind("knife")],
			[Vector2(208.0, 106.0), Vector2(48.0, 14.0), "Paina E: Omena koriin (1 $, nälkä -8)", take.bind("apple")],
		]

	## Hintalappu hyllyn reunassa
	func _tag(c: Vector2, nm: String, price: int) -> void:
		var r := Rect2(c - Vector2(11.0, 4.0), Vector2(22.0, 9.0))
		draw_rect(r, Color(1.0, 0.92, 0.2))
		draw_rect(r, Color(0.85, 0.15, 0.15), false, 1.0)
		TextFit.draw(self, ThemeDB.fallback_font, r.position + Vector2(0, 7.5), "%d $" % price, r.size.x, 7, Color(0.1, 0.1, 0.1))
		_text(Vector2(c.x - 20.0, r.position.y - 1.0), nm, 40.0, 5, Color.WHITE)

	func _draw() -> void:
		# lattia: vaaleat laatat kiiltoineen
		var fr := Rect2(16, 32, W - 32, H - 48)
		draw_rect(fr, Color(0.86, 0.87, 0.84))
		var x := fr.position.x
		while x < fr.end.x:
			draw_line(Vector2(x, fr.position.y), Vector2(x, fr.end.y), Color(0.74, 0.75, 0.72), 1.0)
			x += 16.0
		var y := fr.position.y
		while y < fr.end.y:
			draw_line(Vector2(fr.position.x, y), Vector2(fr.end.x, y), Color(0.74, 0.75, 0.72), 1.0)
			y += 16.0
		for k in 5:
			draw_line(Vector2(40.0 + k * 60.0, fr.position.y), Vector2(20.0 + k * 60.0, fr.end.y), Color(1, 1, 1, 0.12), 3.0)
		# seinät: kerma + vihreä raita, sivuseinät
		draw_rect(Rect2(0, 0, W, 32), Color(0.93, 0.9, 0.82))
		draw_rect(Rect2(0, 22, W, 5), Color(0.15, 0.55, 0.3))
		draw_rect(Rect2(0, 27, W, 2), Color(0.98, 0.6, 0.15))
		draw_rect(Rect2(0, 32, 16, H - 32), Color(0.88, 0.85, 0.77))
		draw_rect(Rect2(W - 16, 32, 16, H - 32), Color(0.88, 0.85, 0.77))
		draw_rect(Rect2(0, H - 16, W, 16), Color(0.88, 0.85, 0.77))
		# kaupan nimi ja tarjousjulisteet
		_text(Vector2(100.0, 17.0), "K A U P P A", 120.0, 13, Color(0.15, 0.55, 0.3), Color(1, 1, 1, 0.9))
		for px: float in [30.0, 230.0, 270.0]:
			var pr := Rect2(px, 3.0, 26.0, 17.0)
			draw_rect(pr, Color(1.0, 0.92, 0.2))
			draw_rect(pr, Color(0.85, 0.15, 0.15), false, 1.0)
			TextFit.draw(self, ThemeDB.fallback_font, pr.position + Vector2(0, 8), "TARJOUS", pr.size.x, 5, Color(0.85, 0.1, 0.1))
			TextFit.draw(self, ThemeDB.fallback_font, pr.position + Vector2(0, 15), ["0,99", "2 x 1", "-30%"][int(px) % 3], pr.size.x, 7, Color(0.1, 0.1, 0.1))
		_fridges()
		_gondola(GONDOLA_A, 1)
		_gondola(GONDOLA_B, 2)
		_fruit()
		# hintalaput (tuotteet otetaan hyllystä E:llä)
		_tag(Vector2(64.0, 58.0), "ENERGIAJUOMA", 3)
		_tag(Vector2(152.0, 58.0), "MAKKARA", 4)
		_tag(Vector2(50.0, 145.0), "ATERIA", 6)
		_tag(Vector2(80.0, 145.0), "KASSI", 15)
		_tag(Vector2(110.0, 145.0), "KYNÄ", 1)
		_tag(Vector2(140.0, 145.0), "VEITSI", 20)
		_tag(Vector2(208.0, 106.0), "OMENA", 1)
		# ostoskorit oven vieressä
		for k in 3:
			var bp := Vector2(36.0, 158.0 - k * 2.0)
			draw_rect(Rect2(bp, Vector2(16, 8)), Color(0.85, 0.15, 0.15))
			draw_rect(Rect2(bp, Vector2(16, 8)), Color(0.55, 0.05, 0.05), false, 1.0)
		draw_line(Vector2(38, 150), Vector2(50, 150), Color(0.3, 0.3, 0.3), 1.0)
		# asiakkaat hyllyjen välissä; ryöstön ja poliisien aikana pelkäävät ja pakenevat nurkkaan.
		# Nippusiteillä sidotut (panttivangit) pysyvät paikallaan siteet ranteissa.
		var scared: bool = room != null and bool(room.call("panic"))
		var tied: Dictionary = room.get("tied_customers") if room else {}
		_flee_k = move_toward(_flee_k, 1.0 if scared else 0.0, get_process_delta_time() * 0.6)
		var pos_a := Vector2(96.0, 112.0)
		var home := Vector2(158.0, 118.0 + sin(_t * 0.4) * 22.0)
		var hide_pos := Vector2(210.0, 66.0)
		var pos_b := home.lerp(hide_pos, clampf(_flee_k * 1.6, 0.0, 1.0)) if _flee_k > 0.0 else home
		if tied.has(0):
			pos_a = tied[0]
		if tied.has(1):
			pos_b = tied[1]
		cust_pos = [pos_a, pos_b]
		# asiakas 1
		if tied.has(0):
			_tied_char(pos_a, CS.npc(1, 6), 11, 0.0)
		elif _flee_k > 0.0:
			_cower(pos_a + Vector2(sin(_t * 40.0) * 0.5, 0.0), CS.npc(1, 6), 1.0)
			if scared:
				_bubble_at(pos_a + Vector2(0.0, -16.0), ["Apua!", "Älkää ampuko!", "Mä en nähny mitään!", "Äiti..."][int(_t / 2.2) % 4], 0.0)
		else:
			_char(pos_a, CS.npc(0, 6), 11)
		# asiakas 2
		if tied.has(1):
			_tied_char(pos_b, CS.npc(1, 15), 12, 1.1)
		elif _flee_k > 0.0:
			if _flee_k < 0.62:
				_char(pos_b, CS.npc(3 if hide_pos.x > home.x else 0, 15 + (1 + int(_t * 9.0) % 2)), 12)
			else:
				_cower(pos_b + Vector2(sin(_t * 37.0) * 0.4, 0.0), CS.npc(1, 15), 1.0)
			if scared:
				_bubble_at(pos_b + Vector2(0.0, -16.0), ["Soittakaa poliisi!", "Pää alas!", "Ei ei ei!", "Hiljaa, hiljaa..."][int(_t / 2.6 + 1.0) % 4], 0.9)
		else:
			var cust_dir := 1 if cos(_t * 0.4) > 0.0 else 2
			_char(pos_b, CS.npc(cust_dir, 15 + (1 + int(_t * 5.0) % 2)), 12)
		_counter()
		# turvaportit ja ovi
		var alarm := room != null and float(room.get("alarm_t")) > 0.0 and fmod(_t * 6.0, 1.0) < 0.5
		for gx: float in [W * 0.5 - 20.0, W * 0.5 + 18.0]:
			draw_rect(Rect2(gx, H - 34.0, 3.0, 16.0), Color(1.0, 0.15, 0.1) if alarm else Color(0.75, 0.77, 0.8))
			draw_rect(Rect2(gx, H - 34.0, 3.0, 16.0), Color(0.4, 0.42, 0.46), false, 1.0)
		_door("ULOS")
		# loisteputket: kylmä valo
		for lx: float in [70.0, 160.0, 250.0]:
			draw_circle(Vector2(lx, 100.0), 60.0, Color(0.9, 0.95, 1.0, 0.05))

	var _flee_k := 0.0
	## Asiakkaiden jalkojen paikat (huoneen koordinaatit): ServiceInterior.try_tie_in_room
	var cust_pos: Array = [Vector2(96.0, 112.0), Vector2(158.0, 118.0)]

	## Nippusiteillä sidottu panttivanki: tärisee, siteet ranteissa, mumisee.
	func _tied_char(feet: Vector2, tex: Texture2D, id: int, phase: float) -> void:
		var sh := sin(_t * 22.0 + phase) * 0.4
		_char(feet + Vector2(sh, 0.0), tex, id)
		var c := Color(0.97, 0.97, 0.95)
		for sx: float in [-3.8, 3.8]:
			draw_rect(Rect2(feet + Vector2(sx - 0.9 + sh, -5.4), Vector2(1.8, 0.9)), c)
		draw_line(feet + Vector2(-3.0 + sh, -5.0), feet + Vector2(3.0 + sh, -5.0), c, 0.7)
		_bubble_at(feet + Vector2(0.0, -16.0), ["Mmmph!", "Hmmff!", "Mmh-mmh!"][int(_t / 1.8 + phase) % 3], phase)
	static var _hands_cache := {}

	## Myyjän kuva ilman alas roikkuvia käsiä (kädet piirretään ylös erikseen).
	func _hands_up(tex: Texture2D) -> Texture2D:
		if tex == null:
			return null
		var id := tex.get_instance_id()
		if _hands_cache.has(id):
			return _hands_cache[id]
		var img := tex.get_image()
		if img == null:
			return null
		img = img.duplicate() as Image
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var hh := img.get_height()
		var sc := float(w) / 32.0
		var vest := Color8(32, 32, 40)
		for y in range(int(21 * sc), mini(int(26 * sc), hh)):
			for x in w:
				var lx := float(x) / sc
				if not ((lx >= 6.0 and lx < 12.0) or (lx >= 20.0 and lx < 26.0)):
					continue
				var c := img.get_pixel(x, y)
				if c.a < 0.5:
					continue
				var skin := c.r > 0.55 and c.r > c.b + 0.15
				var outl := c.r > 0.32 and c.r < 0.5 and c.g < 0.3 and c.b < 0.26
				if skin or outl:
					img.set_pixel(x, y, vest if (lx >= 8.0 and lx < 24.0) else Color(0, 0, 0, 0))
		var t := ImageTexture.create_from_image(img)
		t.set_size_override(Vector2i(tex.get_size()))
		_hands_cache[id] = t
		return t

	## Pelokas asiakas: normaalikokoinen hahmo tärisee kädet ylhäällä. Alas roikkuvat kädet
	## poistetaan kuvasta (korvataan viereisellä vartalon värillä) ja kädet piirretään ylös
	## hahmon omilla hiha- ja ihonväreillä.
	static var _npc_hands := {}

	func _npc_hands_up(tex: Texture2D) -> Array:
		var id := tex.get_instance_id()
		if _npc_hands.has(id):
			return _npc_hands[id]
		var img := tex.get_image()
		if img == null:
			return [tex, Color(0.6, 0.6, 0.65), Color(0.92, 0.7, 0.55)]
		img = img.duplicate() as Image
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var sc := float(img.get_width()) / 32.0
		var P := func(x: int, y: int) -> Vector2i:
			return Vector2i(mini(int(x * sc), img.get_width() - 1), mini(int(y * sc), img.get_height() - 1))
		var sleeve := img.get_pixelv(P.call(9, 20))
		var skin := img.get_pixelv(P.call(9, 23))
		if sleeve.a < 0.5:
			sleeve = Color(0.6, 0.6, 0.65)
		if skin.a < 0.5 or not (skin.r > 0.55 and skin.r > skin.b + 0.12):
			skin = Color(0.92, 0.7, 0.55)
		# Kädet ovat käsivarsisarakkeissa 7-10 (ja peilattuna 21-24) riveillä 21-25.
		# Käsivarsi jatketaan hihana alas (rivin 20 väreillä) ja käden alareuna poistetaan,
		# jolloin alas roikkuvat kädet katoavat; ylös nostetut kädet piirretään erikseen.
		var n := int(maxf(sc, 1.0))
		for x in [7, 8, 9, 10, 21, 22, 23, 24]:
			var src: Color = img.get_pixelv(P.call(x, 20))
			for y in range(21, 25):
				for dy in n:
					for dx in n:
						img.set_pixelv(P.call(x, y) + Vector2i(dx, dy), src)
		for x in [7, 8, 9, 22, 23, 24]:
			for dy in n:
				for dx in n:
					img.set_pixelv(P.call(x, 25) + Vector2i(dx, dy), Color(0, 0, 0, 0))
		var t := ImageTexture.create_from_image(img)
		t.set_size_override(Vector2i(tex.get_size()))
		var res := [t, sleeve, skin]
		_npc_hands[id] = res
		return res

	func _cower(feet: Vector2, tex: Texture2D, _k: float) -> void:
		# pelokas asiakas: normaali hahmo, joka tärisee (kädet pysyvät alhaalla)
		_char(feet, tex, 14)

	## Pieni puhekupla (teksti vaihtuu ajan mukaan; phase porrastaa eri hahmot).
	func _bubble_at(p: Vector2, text: String, phase: float) -> void:
		if text == "" or fmod(_t + phase, 2.4) > 1.9:
			return
		var font := ThemeDB.fallback_font
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x + 6.0
		var r := Rect2(p.x - tw * 0.5, p.y - 9.0, tw, 9.0)
		draw_rect(r, Color(1, 1, 1, 0.92))
		draw_rect(r, Color(0, 0, 0, 0.6), false, 0.5)
		draw_colored_polygon(PackedVector2Array([Vector2(p.x - 2.0, r.end.y), Vector2(p.x + 2.0, r.end.y), Vector2(p.x, r.end.y + 3.0)]), Color(1, 1, 1, 0.92))
		draw_string(font, Vector2(r.position.x + 3.0, r.end.y - 2.2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.1, 0.1, 0.12))

	func _fridges() -> void:
		var r := FRIDGES
		draw_rect(r.grow(1.0), Color(0.6, 0.62, 0.66))
		var doors := 8
		var dw := r.size.x / doors
		var cols := [Color(0.95, 0.95, 0.95), Color(0.9, 0.2, 0.2), Color(0.2, 0.55, 0.9), Color(0.95, 0.75, 0.2), Color(0.3, 0.75, 0.4)]
		for d in doors:
			var dr := Rect2(r.position.x + d * dw + 1.0, r.position.y + 1.0, dw - 2.0, r.size.y - 2.0)
			draw_rect(dr, Color(0.55, 0.85, 1.0, 0.9))
			for row in 3:
				for k in 4:
					var c: Color = cols[(d + row + k) % cols.size()]
					draw_rect(Rect2(dr.position.x + 1.5 + k * (dr.size.x - 3.0) / 4.0, dr.position.y + 2.0 + row * 6.0, 2.5, 4.0), c)
			draw_rect(dr, Color(1, 1, 1, 0.25 + 0.05 * sin(_t * 2.0 + d)), false, 1.0)
			draw_line(Vector2(dr.end.x - 2.0, dr.position.y + 6.0), Vector2(dr.end.x - 2.0, dr.position.y + 12.0), Color(0.85, 0.85, 0.9), 1.0)
		draw_rect(Rect2(r.position.x, r.position.y - 2.0, r.size.x, 2.0), Color(0.6, 0.85, 1.0, 0.8))   # valolista

	func _gondola(r: Rect2, seed_i: int) -> void:
		draw_rect(Rect2(r.position + Vector2(1, 2), r.size), Color(0, 0, 0, 0.25))
		draw_rect(r, Color(0.78, 0.8, 0.82))
		draw_rect(Rect2(r.get_center().x - 1.0, r.position.y, 2.0, r.size.y), Color(0.55, 0.57, 0.6))
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_i * 97
		var y := r.position.y + 3.0
		while y < r.end.y - 4.0:
			for side in 2:
				var x := r.position.x + 1.0 + side * (r.size.x * 0.5)
				while x < r.position.x + (side + 1) * r.size.x * 0.5 - 2.0:
					var c := Color.from_hsv(rng.randf(), rng.randf_range(0.5, 0.9), rng.randf_range(0.6, 0.95))
					draw_rect(Rect2(x, y, 2.0, 5.0), c)
					x += 2.6
			draw_line(Vector2(r.position.x, y + 6.0), Vector2(r.end.x, y + 6.0), Color(0.5, 0.52, 0.55), 1.0)
			y += 9.0
		draw_rect(Rect2(r.position.x - 1.0, r.position.y - 6.0, r.size.x + 2.0, 6.0), Color(0.15, 0.55, 0.3))
		TextFit.draw(self, ThemeDB.fallback_font, Vector2(r.position.x - 1.0, r.position.y - 1.5), ["", "LEIPÄ", "HERKUT"][seed_i], r.size.x + 2.0, 4, Color.WHITE)

	func _fruit() -> void:
		var r := FRUIT
		draw_rect(Rect2(r.position + Vector2(1, 2), r.size), Color(0, 0, 0, 0.25))
		var crates := [[Color(0.85, 0.15, 0.15), Color(1.0, 0.4, 0.35)], [Color(0.98, 0.85, 0.2), Color(1.0, 0.95, 0.5)], [Color(1.0, 0.55, 0.1), Color(1.0, 0.75, 0.35)], [Color(0.3, 0.7, 0.25), Color(0.55, 0.85, 0.4)]]
		for i in 4:
			var cr := Rect2(r.position.x + (i % 2) * 24.0, r.position.y + int(i / 2) * 13.0, 23.0, 12.0)
			draw_rect(cr, Color(0.6, 0.4, 0.22))
			draw_rect(cr, Color(0.4, 0.25, 0.12), false, 1.0)
			for k in 7:
				var fp := cr.position + Vector2(3.0 + (k % 4) * 5.0, 3.5 + int(k / 4) * 4.0)
				var cc: Array = crates[i]
				draw_circle(fp, 2.0, cc[0])
				draw_circle(fp + Vector2(-0.6, -0.6), 0.7, cc[1])
		_text(Vector2(r.position.x - 6.0, r.position.y - 2.0), "HEDELMÄT", r.size.x + 12.0, 5, Color(0.3, 0.75, 0.3))

	func _counter() -> void:
		# tupakkakaappi myyjän takana
		var tc := TOBACCO
		draw_rect(tc, Color(0.2, 0.2, 0.22))
		for row in 6:
			for k in 2:
				var pk := Rect2(tc.position.x + 1.5 + k * 6.0, tc.position.y + 2.0 + row * 8.5, 5.0, 7.0)
				draw_rect(pk, Color(0.95, 0.95, 0.92))
				draw_rect(Rect2(pk.position, Vector2(5, 2.5)), [Color(0.8, 0.12, 0.12), Color(0.15, 0.3, 0.7), Color(0.15, 0.5, 0.25)][(row + k) % 3] as Color)
		draw_rect(tc, Color(0.1, 0.1, 0.1), false, 1.0)
		# myyjä kassan takana (ryöstössä ja poliisien aikana kädet ylhäällä, rahat tiskille)
		var cashier := CS.staff(CS.WAITER, 1, 1, 0)
		var afraid: bool = room != null and bool(room.call("panic"))
		if room != null and Game.flag(room, "cashier_tied"):
			# sidottu: kädet nippusiteillä edessä, rimpuilee
			var sh2 := sin(_t * 22.0) * 0.4
			_char(Vector2(262.0 + sh2, 124.0), cashier, 13)
			draw_line(Vector2(258.0 + sh2, 120.0), Vector2(266.0 + sh2, 120.0), Color(0.97, 0.97, 0.95), 1.3)
			draw_rect(Rect2(Vector2(261.4 + sh2, 120.5), Vector2(1.2, 1.2)), Color(0.97, 0.97, 0.95))
			_bubble_at(Vector2(262.0, 104.0), ["Mmmph!", "Hmmff!"][int(_t / 1.6) % 2], 0.2)
		elif afraid:
			var sh := sin(_t * 30.0) * 0.35
			_char(Vector2(262.0 + sh, 124.0), cashier, 13)
			_bubble_at(Vector2(262.0, 104.0), ["Älä ammu!", "Ota kaikki!", "Mulla on lapsia!"][int(_t / 2.4) % 3] if Game.flag(room, "robbing") else "", 0.4)
		else:
			_char(Vector2(262.0, 124.0), cashier, 13)
		if room and Game.flag(room, "robbing"):
			var k := clampf(float(room.call("rob_progress")), 0.0, 1.0)
			for i in int(k * 6.0):
				draw_rect(Rect2(232.0 + i * 5.0, 125.0, 4.0, 2.5), Color(0.35, 0.7, 0.35))
				draw_rect(Rect2(232.0 + i * 5.0, 125.0, 4.0, 2.5), Color(0.15, 0.4, 0.15), false, 0.5)
		# kassapöytä, liukuhihna, kassakone ja karkkihylly
		var c := COUNTER
		draw_rect(Rect2(c.position + Vector2(1, 2), c.size), Color(0, 0, 0, 0.3))
		draw_rect(c, Color(0.75, 0.77, 0.8))
		var belt := Rect2(c.position.x + 2.0, c.position.y + 3.0, 32.0, 8.0)
		draw_rect(belt, Color(0.12, 0.12, 0.14))
		var off := fmod(_t * 8.0, 4.0)
		var bx := belt.position.x + off
		while bx < belt.end.x:
			draw_line(Vector2(bx, belt.position.y), Vector2(bx, belt.end.y), Color(0.25, 0.25, 0.28), 1.0)
			bx += 4.0
		draw_rect(Rect2(belt.position.x + 6.0, belt.position.y + 1.0, 5.0, 4.0), Color(0.95, 0.8, 0.2))
		draw_rect(Rect2(belt.position.x + 14.0, belt.position.y + 2.0, 3.0, 5.0), Color(0.2, 0.5, 0.9))
		var reg := Rect2(c.position.x + 40.0, c.position.y - 6.0, 16.0, 12.0)
		draw_rect(reg, Color(0.25, 0.26, 0.3))
		draw_rect(Rect2(reg.position + Vector2(2, 2), Vector2(12, 4)), Color(0.3, 0.95, 0.5))
		var cd := CANDY
		draw_rect(cd, Color(0.6, 0.62, 0.66))
		for k in 6:
			draw_rect(Rect2(cd.position.x + 2.0 + (k % 2) * 4.0, cd.position.y + 2.0 + int(k / 2) * 6.5, 3.5, 5.0), Color.from_hsv(k * 0.17, 0.8, 0.95))
		_text(Vector2(c.position.x - 4.0, c.end.y + 9.0), "KASSA", c.size.x + 8.0, 6, Color(1.0, 0.95, 0.6))


# ----------------------------------------------------------------------------
#  PANKKI
# ----------------------------------------------------------------------------
class BankView extends "res://scripts/world/ServiceRoomView.gd":
	const COUNTER := Rect2(40.0, 62.0, 240.0, 16.0)
	const ATM := Rect2(268.0, 140.0, 20.0, 22.0)
	const CHAIRS := Rect2(24.0, 120.0, 52.0, 14.0)
	const TICKET := Rect2(40.0, 152.0, 10.0, 14.0)
	const PLANT := Rect2(24.0, 140.0, 12.0, 12.0)

	func solids() -> Array:
		return [COUNTER, ATM, CHAIRS, TICKET, PLANT]

	func spots() -> Array:
		var menu := Callable(room, "open_menu")
		return [
			[Vector2(160.0, 88.0), Vector2(150.0, 14.0), "Paina E: asioi pankkivirkailijan kanssa", menu],
			[Vector2(ATM.get_center().x - 14.0, ATM.get_center().y), Vector2(14.0, 22.0), "Paina E: pankkiautomaatti", menu],
			[Vector2(TICKET.get_center().x + 12.0, TICKET.get_center().y), Vector2(14.0, 18.0), "Paina E: ota vuoronumero",
				func(_p: Node2D) -> void: Game.msg("Vuoronumero %d. Mene tiskille, tänään ei ole jonoa." % (40 + randi() % 50), 2.0)],
		]

	func _draw() -> void:
		# marmorilattia ja punainen matto
		var fr := Rect2(16, 32, W - 32, H - 48)
		draw_rect(fr, Color(0.9, 0.86, 0.78))
		var cy := fr.position.y
		var r := 0
		while cy < fr.end.y:
			var cx := fr.position.x
			var c := 0
			while cx < fr.end.x:
				if (r + c) % 2 == 0:
					draw_rect(Rect2(cx, cy, minf(24.0, fr.end.x - cx), minf(24.0, fr.end.y - cy)), Color(0.82, 0.77, 0.68))
				cx += 24.0
				c += 1
			cy += 24.0
			r += 1
		var rng := RandomNumberGenerator.new()
		rng.seed = 33
		for k in 30:
			var a := Vector2(rng.randf_range(fr.position.x, fr.end.x), rng.randf_range(fr.position.y, fr.end.y))
			draw_line(a, a + Vector2(rng.randf_range(-14, 14), rng.randf_range(-6, 6)), Color(0.65, 0.6, 0.55, 0.3), 1.0)
		var carpet := Rect2(W * 0.5 - 16.0, 80.0, 32.0, H - 96.0)
		draw_rect(carpet, Color(0.55, 0.06, 0.1))
		draw_rect(carpet.grow(-2.0), Color(0.85, 0.68, 0.3), false, 1.0)
		# seinät: tummat puupaneelit, kultalista
		draw_rect(Rect2(0, 0, W, 32), Color(0.28, 0.16, 0.09))
		var px := 4.0
		while px < W:
			draw_rect(Rect2(px, 4.0, 22.0, 18.0), Color(0.34, 0.2, 0.11), false, 1.0)
			px += 26.0
		draw_rect(Rect2(0, 27, W, 3), Color(0.85, 0.68, 0.3))
		draw_rect(Rect2(0, 32, 16, H - 32), Color(0.26, 0.15, 0.08))
		draw_rect(Rect2(W - 16, 32, 16, H - 32), Color(0.26, 0.15, 0.08))
		draw_rect(Rect2(0, H - 16, W, 16), Color(0.26, 0.15, 0.08))
		_text(Vector2(110.0, 19.0), "P A N K K I", 100.0, 12, Color(0.95, 0.8, 0.35), Color(0.1, 0.05, 0.02, 0.9))
		# seinäkello (pelin aika)
		var cc := Vector2(40.0, 14.0)
		draw_circle(cc, 9.0, Color(0.85, 0.68, 0.3))
		draw_circle(cc, 7.5, Color(0.97, 0.95, 0.9))
		var hrs := fmod(Game.minutes / 60.0, 12.0)
		var mins := fmod(Game.minutes, 60.0)
		draw_line(cc, cc + Vector2.from_angle(-PI * 0.5 + hrs / 12.0 * TAU) * 4.0, Color(0.1, 0.1, 0.1), 1.5)
		draw_line(cc, cc + Vector2.from_angle(-PI * 0.5 + mins / 60.0 * TAU) * 6.0, Color(0.1, 0.1, 0.1), 1.0)
		# taulu
		var art := Rect2(64.0, 4.0, 30.0, 20.0)
		draw_rect(art.grow(1.5), Color(0.85, 0.68, 0.3))
		draw_rect(art, Color(0.35, 0.55, 0.75))
		draw_rect(Rect2(art.position.x, art.position.y + 12.0, art.size.x, 8.0), Color(0.25, 0.45, 0.25))
		draw_circle(art.position + Vector2(22, 6), 3.0, Color(1.0, 0.9, 0.5))
		# holvin ovi takaseinällä
		var vc := Vector2(262.0, 16.0)
		draw_circle(vc, 14.0, Color(0.45, 0.47, 0.5))
		draw_circle(vc, 12.0, Color(0.62, 0.64, 0.68))
		draw_circle(vc, 4.0, Color(0.4, 0.42, 0.45))
		for k in 6:
			var a := k * TAU / 6.0 + _t * 0.05
			draw_line(vc + Vector2.from_angle(a) * 4.0, vc + Vector2.from_angle(a) * 9.0, Color(0.85, 0.85, 0.88), 1.5)
		draw_rect(Rect2(vc.x + 13.0, vc.y - 6.0, 3.0, 12.0), Color(0.35, 0.36, 0.4))
		var hz := str(room.get("heist")) if room else ""
		if hz == "bomb" and fmod(_t * 4.0, 1.0) < 0.5:
			draw_rect(Rect2(vc.x - 4.0, vc.y + 6.0, 8.0, 5.0), Color(0.85, 0.75, 0.55))   # C4
			draw_circle(Vector2(vc.x, vc.y + 6.0), 1.5, Color(1.0, 0.1, 0.1))
		elif hz == "bomb":
			draw_rect(Rect2(vc.x - 4.0, vc.y + 6.0, 8.0, 5.0), Color(0.85, 0.75, 0.55))
		if hz == "blown" or hz == "looted":
			# räjäytetty holvi: aukko, noki ja (ennen ryöstöä) rahat
			draw_circle(vc, 17.0, Color(0.12, 0.1, 0.1))
			draw_circle(vc, 13.0, Color(0.05, 0.05, 0.06))
			if hz == "blown":
				for k in 6:
					draw_rect(Rect2(vc.x - 9.0 + (k % 3) * 6.0, vc.y - 2.0 + int(k / 3) * 4.0, 5.0, 3.0), Color(0.95, 0.78, 0.25))
				for k in 4:
					draw_rect(Rect2(vc.x - 8.0 + k * 4.0, vc.y - 8.0, 3.0, 4.0), Color(0.35, 0.7, 0.35))
			for k in 8:
				var a := k * TAU / 8.0
				draw_line(vc + Vector2.from_angle(a) * 13.0, vc + Vector2.from_angle(a) * 20.0, Color(0.1, 0.08, 0.08, 0.7), 2.0)
			# irronnut ovi lattialla
			draw_circle(Vector2(vc.x - 26.0, 46.0), 11.0, Color(0.45, 0.47, 0.5))
			draw_circle(Vector2(vc.x - 26.0, 46.0), 9.0, Color(0.58, 0.6, 0.64))
		# virkailijat tiskin takana (tiski peittää jalat); keikassa kädet ylhäällä
		for i in 3:
			var tp := Vector2(90.0 + i * 70.0, 70.0)
			_char(tp, CS.staff(CS.WAITER, i % 3, 1, 0), 21 + i)
			if hz != "":
				var skin := Color(0.96, 0.74, 0.57)
				var sh := sin(_t * 26.0 + i) * 0.4
				draw_line(tp + Vector2(-4.0 + sh, -7.0), tp + Vector2(-6.0 + sh, -15.0), skin, 1.6)
				draw_line(tp + Vector2(4.0 - sh, -7.0), tp + Vector2(6.0 - sh, -15.0), skin, 1.6)
		# tiski ja lasiseinät
		var ct := COUNTER
		draw_rect(Rect2(ct.position + Vector2(1, 2), ct.size), Color(0, 0, 0, 0.3))
		draw_rect(ct, Color(0.4, 0.24, 0.12))
		draw_rect(Rect2(ct.position, Vector2(ct.size.x, 3.0)), Color(0.85, 0.82, 0.78))
		draw_line(Vector2(ct.position.x, ct.end.y - 3.0), Vector2(ct.end.x, ct.end.y - 3.0), Color(0.85, 0.68, 0.3), 1.0)
		draw_rect(Rect2(ct.position.x, 36.0, ct.size.x, 26.0), Color(0.7, 0.85, 0.95, 0.18))
		for i in 4:
			var gx := ct.position.x + i * 80.0
			draw_rect(Rect2(gx - 1.0, 36.0, 2.0, 26.0), Color(0.85, 0.68, 0.3))
		for i in 3:
			var wx := ct.position.x + 40.0 + i * 80.0
			draw_rect(Rect2(wx - 6.0, 38.0, 12.0, 6.0), Color(0.05, 0.05, 0.08))
			TextFit.draw(self, ThemeDB.fallback_font, Vector2(wx - 6.0, 43.0), str(i + 1), 12.0, 6, Color(1.0, 0.3, 0.2))
			draw_line(Vector2(wx - 14.0, 40.0), Vector2(wx + 14.0, 58.0), Color(1, 1, 1, 0.2), 1.0)   # heijastus
		# vuoronumeronäyttö
		# odotustila: nojatuolit, kasvi, esitetelineet
		var ch := CHAIRS
		for k in 3:
			var cr := Rect2(ch.position.x + k * 18.0, ch.position.y, 16.0, ch.size.y)
			draw_rect(cr, Color(0.15, 0.1, 0.08))
			draw_rect(cr.grow(-2.0), Color(0.45, 0.12, 0.12))
		_char(Vector2(ch.position.x + 26.0, ch.position.y + 4.0), CS.npc(1, 0), 25)
		var pl := PLANT
		draw_rect(Rect2(pl.position + Vector2(2, 5), Vector2(8, 7)), Color(0.6, 0.32, 0.18))
		draw_circle(pl.get_center() + Vector2(0, -2), 7.0, Color(0.15, 0.45, 0.22))
		draw_circle(pl.get_center() + Vector2(-2, -4), 4.0, Color(0.25, 0.6, 0.3))
		# vuoronumeroautomaatti ja näyttö
		var tk := TICKET
		draw_rect(tk, Color(0.3, 0.32, 0.36))
		draw_rect(Rect2(tk.position + Vector2(2, 2), Vector2(6, 3)), Color(1.0, 0.3, 0.2))
		draw_rect(Rect2(tk.position + Vector2(3, 9), Vector2(4, 3)), Color(0.95, 0.95, 0.95))
		var nd := Rect2(278.0, 36.0, 22.0, 12.0)
		draw_rect(nd, Color(0.05, 0.05, 0.06))
		TextFit.draw(self, ThemeDB.fallback_font, nd.position + Vector2(0, 9), "%03d" % (40 + int(_t / 20.0) % 60), nd.size.x, 8, Color(1.0, 0.25, 0.15))
		# pankkiautomaatti
		var at := ATM
		draw_rect(Rect2(at.position + Vector2(1, 2), at.size), Color(0, 0, 0, 0.3))
		draw_rect(at, Color(0.55, 0.58, 0.62))
		draw_rect(Rect2(at.position + Vector2(3, 3), Vector2(14, 8)), Color(0.15, 0.4, 0.75))
		draw_rect(Rect2(at.position + Vector2(4, 4), Vector2(12, 1)), Color(0.6, 0.85, 1.0, 0.6 + 0.4 * sin(_t * 2.0)))
		for k in 6:
			draw_rect(Rect2(at.position.x + 4.0 + (k % 3) * 4.0, at.position.y + 13.0 + int(k / 3) * 3.0, 3.0, 2.0), Color(0.85, 0.85, 0.88))
		_text(Vector2(at.position.x - 8.0, at.position.y - 2.0), "OTTO", at.size.x + 16.0, 5, Color(0.6, 0.85, 1.0))
		# jonotusköydet
		for k in 4:
			var qp := Vector2(W * 0.5 - 24.0, 96.0 + k * 18.0)
			draw_rect(Rect2(qp + Vector2(-1, -6), Vector2(2.5, 7)), Color(0.85, 0.68, 0.3))
			if k < 3:
				draw_line(qp + Vector2(0, -5), qp + Vector2(0, 13), Color(0.6, 0.05, 0.12), 1.5)
		# vartija oven vieressä (keikan aikana hän on paennut)
		if hz == "":
			_char(Vector2(W * 0.5 + 30.0, H - 22.0), CS.staff(CS.BOUNCER, 0, 1, 0), 26)
		_door("ULOS")
		# lämmin valo
		for lx: float in [80.0, 160.0, 240.0]:
			draw_circle(Vector2(lx, 110.0), 56.0, Color(1.0, 0.88, 0.6, 0.05))
		# hälytysvalo: punainen sykkivä hehku
		if hz != "" and hz != "in":
			var pulse := 0.5 + 0.5 * sin(_t * 9.0)
			draw_rect(Rect2(0, 0, W, H), Color(1.0, 0.05, 0.05, 0.1 * pulse))
			for lx: float in [40.0, 280.0]:
				draw_circle(Vector2(lx, 30.0), 4.0, Color(1.0, 0.15, 0.1, 0.5 + 0.5 * pulse))
				draw_circle(Vector2(lx, 30.0), 12.0, Color(1.0, 0.1, 0.1, 0.15 * pulse))


# ----------------------------------------------------------------------------
#  POLIISI KAUPAN SISÄLLÄ (hälytyksen jälkeen): kävelee pelaajan luo ja pidättää,
#  ampuu, jos pelaaja ampuu poliisia tai osoittelee aseella liian kauan.
# ----------------------------------------------------------------------------
class ShopCop extends Node2D:
	const CS2 := preload("res://scripts/core/CharSprites.gd")
	const BULLET: PackedScene = preload("res://scenes/entities/weapons/bullet.tscn")
	const BLOOD2 := preload("res://scripts/core/Blood.gd")
	const SPEED := 48.0
	const ARREST_DIST := 14.0
	const ARREST_TIME := 1.1
	const GUN_PATIENCE := 2.5     ## ase kädessä näin kauan -> poliisi ampuu
	var room: Node2D = null
	var hp := 3
	var dead := false
	var hostile := false
	var sprite: Sprite2D
	var _col := 2
	var _anim := 0.0
	var _shoot_t := 1.2
	var _near_t := 0.0
	var _gun_t := 0.0
	var _flash := 0.0
	var _bubble := ""
	var _say_t := 0.0
	## Piirityksen aikainen paikka oven edessä (huoneen koordinaatit)
	var post := Vector2.ZERO
	var _talk_t := 3.0

	func _ready() -> void:
		sprite = Sprite2D.new()
		sprite.offset = Vector2(0, -4)
		add_child(sprite)
		add_to_group("shootable")
		add_to_group("enemy_shooter")
		_refresh(0)

	func _refresh(step: int) -> void:
		sprite.texture = CS2.police(_col, step)

	func hit_point() -> Vector2:
		return global_position + Vector2(0, -4)

	func is_punchable() -> bool:
		return not dead

	func fist_hit(from: Node2D) -> void:
		take_damage(1, from)

	func say(text: String, secs: float = 2.0) -> void:
		_bubble = text
		_say_t = secs

	static func _col_for(v: Vector2) -> int:
		if absf(v.x) > absf(v.y):
			return 3 if v.x > 0.0 else 0
		return 1 if v.y > 0.0 else 2

	func _process(delta: float) -> void:
		queue_redraw()
		_say_t = maxf(_say_t - delta, 0.0)
		_flash = maxf(_flash - delta, 0.0)
		if dead or room == null:
			return
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player == null or not Game.flag(room, "inside"):
			return
		var pc := player.global_position + Vector2(0.0, 6.0)
		if player.has_method("body_center"):
			pc = (player.call("body_center") as Vector2) + Vector2(0.0, 5.0)
		var to := pc - global_position
		var dist := to.length()
		# Panttivankitilanne: pysytään oven edessä aseet ojossa, ei pidätetä eikä ammuta
		if bool(room.call("holding_off")):
			var o2: Vector2 = room.get("origin")
			var mv2 := (o2 + post) - global_position
			if mv2.length() > 1.0:
				global_position += mv2.normalized() * minf(SPEED * delta, mv2.length())
				_anim += delta
				_col = _col_for(mv2)
				_refresh(1 + int(_anim * 7.0) % 2)
			else:
				_col = _col_for(to)
				_refresh(0)
			_near_t = 0.0
			_talk_t -= delta
			if _talk_t <= 0.0:
				_talk_t = randf_range(4.0, 7.0)
				say(["Vapauta panttivangit!", "Puhutaan, ei kenenkään tarvitse kuolla.", "Ase alas, niin tämä päättyy hyvin.", "Kauppa on piiritetty!"][randi() % 4], 2.2)
			return
		# reitti: oven edestä ensin alakäytävää pitkin pelaajan kohdalle, sitten suoraan
		var goal := pc
		var o: Vector2 = room.get("origin")
		if global_position.y > o.y + 150.0 and absf(to.x) > 8.0 and pc.y < o.y + 150.0:
			goal = Vector2(pc.x, global_position.y)
		var mv := goal - global_position
		if dist > ARREST_DIST * 0.8 and mv.length() > 0.5:
			global_position += mv.normalized() * minf(SPEED * delta, mv.length())
			_anim += delta
			_col = _col_for(mv)
			_refresh(1 + int(_anim * 7.0) % 2)
		else:
			_col = _col_for(to)
			_refresh(0)
		# ase pelaajan kädessä: poliisi hermostuu
		var armed: bool = player.has_method("has_ranged_weapon") and player.has_ranged_weapon()
		_gun_t = _gun_t + delta if armed else maxf(_gun_t - delta * 2.0, 0.0)
		if armed and _say_t <= 0.0 and randf() < delta * 0.5:
			say(["Pudota ase!", "Ase maahan!", "Viimeinen varoitus!"][randi() % 3], 1.6)
		# pidätys: poliisi pääsee viereen
		if dist < ARREST_DIST:
			_near_t += delta
			if _near_t >= ARREST_TIME:
				_arrest()
				return
		else:
			_near_t = maxf(_near_t - delta, 0.0)
		# ammunta
		if hostile or _gun_t > GUN_PATIENCE:
			_shoot_t -= delta
			if _shoot_t <= 0.0 and dist < 220.0:
				_shoot_t = randf_range(1.3, 2.3)
				_shoot(pc + Vector2(0.0, -5.0))

	func _shoot(at: Vector2) -> void:
		var dir: Vector2 = (at - hit_point()).normalized().rotated(randf_range(-0.12, 0.12))
		_col = _col_for(dir)
		var b := BULLET.instantiate()
		b.setup(dir, self, 330.0, 1, 260.0)
		get_tree().current_scene.add_child(b)
		b.global_position = hit_point() + dir * 6.0
		_flash = 0.06
		Sfx.play("gun", global_position, -6.0, 0.08, 1.0)

	func _arrest() -> void:
		var pm := get_tree().get_first_node_in_group("police_manager")
		if pm and pm.has_method("arrest"):
			say("Olet pidätetty!", 2.0)
			pm.arrest("Poliisi pidätti sinut kaupassa ryöstön jälkeen!", -1)

	func take_damage(amount: int = 1, source: Node = null) -> void:
		if dead:
			return
		var bdir: Vector2 = (global_position - (source as Node2D).global_position) if source is Node2D else Vector2.ZERO
		BLOOD2.spray(self, hit_point(), bdir, 4 if hp - amount > 0 else 9, hp - amount <= 0)
		hp -= amount
		sprite.modulate = Color(1.0, 0.55, 0.55)
		create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.15)
		if room and room.has_method("cops_hostile"):
			room.call("cops_hostile")
		if hp <= 0:
			dead = true
			remove_from_group("shootable")
			remove_from_group("enemy_shooter")
			sprite.rotation = deg_to_rad(90.0 if _col != 0 else -90.0)
			sprite.modulate = Color(0.6, 0.6, 0.65)
			Sfx.play("punch_hit", global_position, -4.0, 0.05, 0.6)
			var pm := get_tree().get_first_node_in_group("police_manager")
			if pm and pm.has_method("report_crime"):
				pm.report_crime(3, true)
		else:
			say("Laukauksia! Ammutaan!", 1.5)

	func _draw() -> void:
		if not dead:
			# virka-ase kädessä
			var hand := Vector2(4.0, -5.0)
			var v := Vector2.DOWN
			match _col:
				3:
					hand = Vector2(4.0, -6.0)
					v = Vector2.RIGHT
				0:
					hand = Vector2(-4.0, -6.0)
					v = Vector2.LEFT
				2:
					hand = Vector2(4.0, -8.0)
					v = Vector2.UP
			draw_line(hand, hand + v * 3.5, Color(0.08, 0.08, 0.1), 1.4)
			if _flash > 0.0:
				draw_circle(hand + v * 5.0, 1.8, Color(1.0, 0.85, 0.35))
		if _say_t > 0.0 and _bubble != "":
			var font := ThemeDB.fallback_font
			var tw := font.get_string_size(_bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x + 6.0
			var r := Rect2(-tw * 0.5, -27.0, tw, 9.0)
			draw_rect(r, Color(0.92, 0.95, 1.0, 0.95))
			draw_rect(r, Color(0.1, 0.2, 0.6), false, 0.6)
			draw_string(font, Vector2(r.position.x + 3.0, r.end.y - 2.2), _bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.05, 0.1, 0.35))
