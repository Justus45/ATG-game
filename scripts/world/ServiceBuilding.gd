extends Node2D
## Kaupungin palvelurakennus (ei sisätilaa): katto + kyltti ja E-kohde oven edessä.
## Ovella aukeaa valikko (HUD.show_menu). Aukioloajat tulevat Game-kellosta.
##
## Lajit (kind):
##   hospital  SAIRAALA         hoito, kipulääke; hävityn tappelun jälkeen herätään täältä
##   bank      PANKKI           talletus / nosto (pankin rahat säilyvät sammuessa ja putkassa)
##   shop      KAUPPA           ruokaa jääkaappiin, energiajuoma, kynä, veitsi
##   realtor   KIINTEISTÖT      baarin tarinan loppu: osta Railin baari (Story.gd)
##
## CityGenerator luo nämä (_make_service) ja kutsuu setup():ia.

const TILE := 16

const KINDS := {
	"hospital": {"name": "Sairaala", "title": "SAIRAALA", "roof": Color(0.88, 0.9, 0.92), "accent": Color(0.85, 0.15, 0.18), "text": Color(0.85, 0.15, 0.18), "open": [0, 0], "letter": "+"},
	"bank": {"name": "Pankki", "title": "PANKKI", "roof": Color(0.16, 0.24, 0.36), "accent": Color(0.95, 0.78, 0.3), "text": Color(0.95, 0.85, 0.45), "open": [9, 17], "letter": "$"},
	"shop": {"name": "Kauppa", "title": "KAUPPA", "roof": Color(0.2, 0.45, 0.25), "accent": Color(0.98, 0.6, 0.15), "text": Color(1.0, 0.95, 0.85), "open": [7, 23], "letter": "K"},
	"realtor": {"name": "Kiinteistövälitys", "title": "KIINTEISTÖT", "roof": Color(0.5, 0.42, 0.55), "accent": Color(0.95, 0.95, 0.95), "text": Color(1.0, 1.0, 1.0), "open": [9, 18], "letter": "M"},
	"manor": {"name": "Kartano", "title": "KARTANO", "roof": Color(0.2, 0.24, 0.3), "accent": Color(0.9, 0.75, 0.35), "text": Color(0.95, 0.82, 0.45), "open": [0, 0], "letter": "H"},
}

const HOSPITAL_BILL := 60
const HEAL_PRICE := 25

var kind := "shop"
var door_px := Vector2.ZERO
var roof := Rect2()
var map_color := Color.WHITE
var letter := "?"
var title := ""
var _info: Dictionary = {}
## Sisätila (kauppa ja pankki), muuten null
var interior: Node2D = null
const InteriorScript := preload("res://scripts/world/ServiceInterior.gd")
const MANOR_EXT := preload("res://scripts/world/ManorExterior.gd")
const MANOR_INT := preload("res://scripts/world/ManorInterior.gd")
const GARAGE := preload("res://scripts/world/LuxuryGarage.gd")
## Kartanon luksusautotalli (vain kind == "manor")
var garage: Node2D = null


## Tallin nosto-oven alareunan keskikohta (kartanon julkisivun vasen reuna)
func garage_door_px() -> Vector2:
	return Vector2(roof.position.x + 24.0, door_px.y + 8.0)


func _garage_prompt() -> String:
	if not Game.owns_manor:
		return "Kartanon autotalli (myynnissä kartanon mukana)"
	return "Paina E: luksusautotalli – aja omalla autolla oven eteen, niin se pysäköidään"


func _garage_use(player: Node2D) -> void:
	if not Game.owns_manor:
		Sfx.play_ui("denied", -6.0)
		Game.msg("Talli kuuluu kartanoon. Osta kartano kiinteistövälittäjältä.", 2.5)
		return
	if garage:
		garage.call("walk_in", player)


## Pysäköintipaikat oven edessä (kartano: omat kulkuneuvot)
func parking_spot(i: int) -> Vector2:
	var xs := [-46.0, 46.0, -74.0, 74.0]
	return door_px + Vector2(float(xs[i % xs.size()]), 34.0)


func setup(p_kind: String, p_roof: Rect2, door_center: Vector2) -> void:
	kind = p_kind
	_info = KINDS.get(kind, KINDS["shop"])
	title = str(_info.title)
	map_color = _info.accent
	letter = str(_info.letter)
	add_to_group("service")
	add_to_group(kind)
	global_position = Vector2.ZERO
	door_px = door_center
	roof = p_roof
	if kind == "manor":
		# kartano: oma katto (hahmojen päällä) ja julkisivu (hahmojen alla), ei kylttiä
		var mroof := MANOR_EXT.new()
		mroof.set("part", "roof")
		mroof.set("roof", p_roof)
		mroof.set("door", door_center)
		mroof.z_index = 50
		add_child(mroof)
		var mfac := MANOR_EXT.new()
		mfac.set("part", "facade")
		mfac.set("roof", p_roof)
		mfac.set("door", door_center)
		add_child(mfac)
		interior = MANOR_INT.new()
		add_child(interior)
		interior.call("setup", self)
		# luksusautotalli: nosto-ovi julkisivun vasemmassa reunassa
		garage = GARAGE.new()
		add_child(garage)
		garage.call("setup", self)
		InteractSpot.create(self, garage_door_px() + Vector2(0.0, 14.0), Vector2(30.0, 18.0), _garage_prompt, _garage_use)
	else:
		var ext := ExteriorView.new()
		ext.roof = p_roof
		ext.info = _info
		ext.kind = kind
		ext.door_front = door_center + Vector2(0.0, TILE)
		ext.z_index = 50
		add_child(ext)
	InteractSpot.create(self, door_center + Vector2(0.0, 17.0), Vector2(24.0, 22.0), _prompt, _use)
	# Kauppaan ja pankkiin pääsee sisälle (ServiceInterior.gd)
	if kind == "shop" or kind == "bank":
		interior = InteriorScript.new()
		add_child(interior)
		interior.setup(self, kind)


func is_open() -> bool:
	var o: Array = _info.open
	return Game.is_open(int(o[0]), int(o[1]))


func hours_text() -> String:
	var o: Array = _info.open
	if int(o[0]) == int(o[1]):
		return "auki aina"
	return "auki %02d–%02d" % [int(o[0]), int(o[1])]


func _prompt() -> String:
	if kind == "manor":
		return "Paina E mennäksesi kotiin (kartano)" if Game.owns_manor else "Kartano – myynnissä %d $ (kiinteistövälitys)" % Game.MANOR_PRICE
	if not is_open():
		return "%s – suljettu (%s)" % [display_name(), hours_text()]
	if interior:
		return "Paina E mennäksesi sisään: %s (%s)" % [display_name(), hours_text()]
	return "Paina E: %s (%s)" % [display_name(), hours_text()]


func _hud() -> Node:
	return get_tree().current_scene.get_node_or_null("Hud")


func _jobs() -> Node:
	return get_tree().get_first_node_in_group("job_manager")


func _menu(t: String, options: Array, cb: Callable) -> void:
	var hud := _hud()
	if hud and hud.has_method("show_menu"):
		hud.show_menu(t, options, cb)


func _use(player: Node2D) -> void:
	if kind == "manor":
		if not Game.owns_manor:
			Sfx.play_ui("denied", -6.0)
			Game.msg("Kartano on myynnissä (%d $). Kysy kiinteistövälittäjältä." % Game.MANOR_PRICE, 3.0)
			return
		if interior:
			interior.call("enter", player)
		return
	if not is_open():
		Sfx.play_ui("denied", -6.0)
		Game.msg("%s on kiinni (%s)." % [display_name(), hours_text()], 2.0)
		return
	if interior:
		interior.enter(player)
		return
	open_menu(player)


## Palvelun valikko (ovella tai sisätilan palvelupisteessä: kassa, virkailija, automaatti).
func open_menu(player: Node2D) -> void:
	match kind:
		"hospital":
			_menu("SAIRAALA\nElämät %d / %d" % [int(player.hp), int(player.get_max_hp())],
				["Hoida haavat (%d $)" % HEAL_PRICE, "Kipulääke krapulaan (10 $)"], _hospital_choice.bind(player))
		"bank":
			_bank_menu(player)
		"shop":
			_menu("KAUPPA – jääkaapissa %d annosta, nälkä %d %%" % [Game.fridge, int(Game.hunger)],
				["Einesateria jääkaappiin (6 $)", "Ruokakassi, 3 annosta (15 $)", "Makkara heti (4 $, nälkä -30)",
				 "Energiajuoma (3 $, väsymys -20)", "Kuulakärkikynä (1 $)", "Keittiöveitsi (20 $)",
				 "Tupakka-aski (%d $, %d savuketta, taskussa nyt %d)" % [Game.CIG_PRICE, Game.CIG_PACK, Game.cigarettes]],
				_shop_choice.bind(player))
		"realtor":
			var opts: Array = []
			var acts: Array = []
			var story := get_tree().get_first_node_in_group("story")
			if not Game.owns_bar and story and story.bar_for_sale():
				opts.append("Osta Railin baari (%d $)" % story.bar_price())
				acts.append(_realtor_choice.bind(0))
			elif not Game.owns_bar and story and str(story.stage()) == "done":
				# alamaailman tien jälkeen baari on myynnissä täyteen hintaan
				opts.append("Osta baari (%d $) – oma baari, tuotto ja päivitykset toimistosta" % Game.BAR_PRICE)
				acts.append(_buy_bar_full.bind(player))
			if not Game.owns_manor:
				opts.append("Osta kartano (%d $) – ei vuokraa, %d $/pv tuotto, hovimestari, paniikkihuone, luksustalli" % [Game.MANOR_PRICE, Game.MANOR_INCOME])
				acts.append(_buy_manor.bind(player))
			if opts.is_empty():
				Game.msg("Välittäjä: \"Teillähän on jo kaikki, kartano ja baari! Mitä vielä?\"", 3.0)
				return
			var cb := func(i: int) -> void:
				if i >= 0 and i < acts.size():
					(acts[i] as Callable).call()
			_menu("KIINTEISTÖT\nRahaa yhteensä %d $ (lompakko + tili)" % (int(player.money) + Game.bank), opts, cb)


func display_name() -> String:
	return str(_info.get("name", title))


## Maksaa hinnan lompakosta. Palauttaa true jos rahat riittivät.
func _pay(player: Node2D, price: int) -> bool:
	if player.money < price:
		Sfx.play_ui("denied", -6.0)
		Game.msg("Ei tarpeeksi rahaa (%d $ / %d $)." % [player.money, price], 2.0)
		return false
	player.add_money(-price)
	return true


func _realtor_choice(i: int) -> void:
	var story := get_tree().get_first_node_in_group("story")
	if i == 0 and story and not story.try_buy_bar():
		Sfx.play_ui("denied", -4.0)
		Game.msg("Välittäjä: \"Tule takaisin, kun sinulla on %d $.\"" % story.bar_price(), 3.0)


## Baarin kauppa täyteen hintaan (alamaailman tarinan jälkeen).
func _buy_bar_full(player: Node2D) -> void:
	if Game.owns_bar:
		return
	if int(player.money) + Game.bank < Game.BAR_PRICE:
		Sfx.play_ui("denied", -4.0)
		Game.msg("Välittäjä: \"Baari maksaa %d $. Teillä on %d $.\"" % [Game.BAR_PRICE, int(player.money) + Game.bank], 3.0)
		return
	Game._pay_total(Game.BAR_PRICE)
	Game.owns_bar = true
	Game.add_rep("regulars", 30)
	Sfx.play_ui("cash", -4.0)
	Game.msg("Baari on nyt sinun! Toimistosta voit päivittää sitä ja palkata väkeä.", 4.0)


## Kartanon kauppa: maksetaan lompakosta ja tililtä, koti muuttaa kartanoon.
func _buy_manor(player: Node2D) -> void:
	if Game.owns_manor:
		return
	if int(player.money) + Game.bank < Game.MANOR_PRICE:
		Sfx.play_ui("denied", -4.0)
		Game.msg("Välittäjä: \"Kartano maksaa %d $. Teillä on %d $.\"" % [Game.MANOR_PRICE, int(player.money) + Game.bank], 3.0)
		return
	Game._pay_total(Game.MANOR_PRICE)
	Game.owns_manor = true
	Game.rent_overdue = false
	Sfx.play_ui("cash", -2.0)
	Game.msg("Kartano on sinun! Muuttofirma vei kaikki tavarat sinne – vuokraa ei enää makseta. Vanhaan kämppään muutti... Sakke.", 5.0)


func _hospital_choice(i: int, player: Node2D) -> void:
	if i == 0 and _pay(player, HEAL_PRICE):
		player.hp = player.get_max_hp()
		player._refresh_health_hud()
		Game.msg("Haavat hoidettu. Elämät täynnä.", 2.0)
	elif i == 1 and _pay(player, 10):
		player.hangover = 0.0
		player._refresh_drunk_hud(true)
		Game.msg("Kipulääke vei krapulan.", 2.0)


func _shop_choice(i: int, player: Node2D) -> void:
	match i:
		0:
			if _pay(player, 6):
				Game.fridge += 1
				Game.msg("Einesateria jääkaappiin.", 2.0)
		1:
			if _pay(player, 15):
				Game.fridge += 3
				Game.msg("Ruokakassi: 3 annosta jääkaappiin.", 2.0)
		2:
			if _pay(player, 4):
				Game.hunger = maxf(Game.hunger - 30.0, 0.0)
				Game.msg("Makkara meni hyvin.", 2.0)
		3:
			if _pay(player, 3):
				Game.fatigue = maxf(Game.fatigue - 20.0, 0.0)
				Game.msg("Energiajuoma piristää.", 2.0)
		4:
			_buy_weapon(player, "pen", 1)
		5:
			_buy_weapon(player, "knife", 20)
		6:
			if _pay(player, Game.CIG_PRICE):
				Game.cigarettes += Game.CIG_PACK
				Sfx.play_ui("coin", -6.0, 1.3)
				Game.msg("Tupakka-aski taskuun (%d savuketta). Polta: C." % Game.cigarettes, 2.5)


## Kaupan hyllytuotteet: id -> [nimi, hinta]
const SHOP_ITEMS := {
	"apple": ["Omena", 1], "energy": ["Energiajuoma", 3], "sausage": ["Makkara", 4],
	"meal": ["Einesateria", 6], "bag": ["Ruokakassi", 15], "pen": ["Kuulakärkikynä", 1],
	"knife": ["Keittiöveitsi", 20], "cigs": ["Tupakka-aski", 7],
}


func item_name(id: String) -> String:
	var it: Array = SHOP_ITEMS.get(id, [id, 0])
	return str(it[0])


func item_price(id: String) -> int:
	if id == "cigs":
		return Game.CIG_PRICE
	var it: Array = SHOP_ITEMS.get(id, [id, 0])
	return int(it[1])


## Tuotteen vaikutus (maksettu tai varastettu)
func apply_item(player: Node2D, id: String) -> void:
	match id:
		"apple":
			Game.hunger = maxf(Game.hunger - 8.0, 0.0)
		"energy":
			Game.fatigue = maxf(Game.fatigue - 20.0, 0.0)
		"sausage":
			Game.hunger = maxf(Game.hunger - 30.0, 0.0)
		"meal":
			Game.fridge += 1
		"bag":
			Game.fridge += 3
		"pen", "knife":
			if not player.has_weapon():
				player.held_weapon.equip(id, "down")
		"cigs":
			Game.cigarettes += Game.CIG_PACK
			var hud := _hud()
			if hud and hud.has_method("set_cigarettes"):
				hud.set_cigarettes(Game.cigarettes)


func _buy_weapon(player: Node2D, id: String, price: int) -> void:
	if player.has_weapon():
		Game.msg("Pudota ensin kädessä oleva ase (G).", 2.0)
		return
	if _pay(player, price):
		player.held_weapon.equip(id, "down")
		Game.msg("%s kädessä. Lyö välilyönnillä / hiirellä." % WeaponDB.display_name(id), 2.5)


# ----------------------------------------------------------------------------
#  PANKKI
# ----------------------------------------------------------------------------
func _bank_menu(player: Node2D) -> void:
	_menu("PANKKI\nLompakko %d $   Tili %d $\nPankin rahat eivät katoa sammuessa tai putkassa." % [player.money, Game.bank],
		["Talleta kaikki", "Talleta 100 $", "Nosta 100 $", "Nosta 500 $", "Nosta kaikki"],
		func(i: int) -> void: _bank_choice(player, i))


func _bank_choice(player: Node2D, i: int) -> void:
	var amount := 0
	match i:
		0:
			amount = player.money
		1:
			amount = mini(100, player.money)
		2:
			amount = -mini(100, Game.bank)
		3:
			amount = -mini(500, Game.bank)
		4:
			amount = -Game.bank
		_:
			return
	if amount == 0:
		Sfx.play_ui("denied", -6.0)
		Game.msg("Ei siirrettävää.", 1.5)
		return
	player.add_money(-amount)
	Game.bank += amount
	Sfx.play_ui("cash", -4.0)
	Game.msg("%s %d $. Tilillä nyt %d $." % ["Talletit" if amount > 0 else "Nostit", absi(amount), Game.bank], 2.5)
	_bank_menu(player)


# ----------------------------------------------------------------------------
#  SAIRAALA: pelaaja herää täältä hävityn tappelun jälkeen
# ----------------------------------------------------------------------------
## Siirtää pelaajan sairaalan ovelle ja perii laskun (lompakko, sitten pankki).
func admit(player: Node2D) -> int:
	for car in get_tree().get_nodes_in_group("player_vehicles"):
		if "is_driving" in car and car.is_driving:
			car.exit_car()
	var col := player.get_node_or_null("CollisionShape2D") as Node2D
	var off := col.position if col else Vector2.ZERO
	player.global_position = door_px + Vector2(0.0, 28.0) - off
	var cam := get_viewport().get_camera_2d()
	if cam:
		cam.global_position = door_px + Vector2(0.0, 28.0)
	Game.butler_fetch_cars(4.0)
	var bill := HOSPITAL_BILL
	var from_wallet := mini(player.money, bill)
	player.add_money(-from_wallet)
	var rest := bill - from_wallet
	var from_bank := mini(Game.bank, rest)
	Game.bank -= from_bank
	Game.skip_minutes(180.0)
	return from_wallet + from_bank


## Katto, kyltti ja tunnus.
class ExteriorView extends Node2D:
	var roof := Rect2()
	var info: Dictionary = {}
	var kind := ""
	var door_front := Vector2.ZERO
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if int(_t * 4.0) != int((_t - delta) * 4.0):
			queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var base: Color = info.get("roof", Color.GRAY)
		var accent: Color = info.get("accent", Color.WHITE)
		var text_c: Color = info.get("text", Color.WHITE)
		draw_rect(Rect2(roof.position.x, roof.end.y, roof.size.x, 3.0), Color(0, 0, 0, 0.28))
		draw_rect(roof, base)
		# saumat
		var x := roof.position.x + 16.0
		while x < roof.end.x:
			draw_line(Vector2(x, roof.position.y), Vector2(x, roof.end.y), Color(0, 0, 0, 0.08), 1.0)
			x += 16.0
		draw_rect(roof, accent, false, 2.0)
		draw_rect(roof.grow(-4.0), Color(accent, 0.35), false, 1.0)

		# tunnus katon keskellä
		var c := roof.get_center() + Vector2(0.0, -8.0)
		match kind:
			"hospital":
				draw_rect(Rect2(c - Vector2(9, 3), Vector2(18, 6)), accent)
				draw_rect(Rect2(c - Vector2(3, 9), Vector2(6, 18)), accent)
			"bank":
				draw_circle(c, 9.0, accent)
				TextFit.draw(self, font, c + Vector2(-5, 5), "$", 10, 14, base)
			"realtor":
				var blink := 0.6 + 0.4 * sin(_t * 3.0)
				draw_rect(Rect2(c - Vector2(16, 6), Vector2(32, 12)), Color(0.85, 0.15, 0.15, blink))
				TextFit.draw(self, font, c + Vector2(-16, 4), "MYYNNISSÄ", 32, 6, Color.WHITE)
			_:
				draw_rect(Rect2(c - Vector2(12, 4), Vector2(24, 8)), accent)

		# kyltti
		var sign_r := Rect2(roof.position.x + 6.0, roof.end.y - 17.0, roof.size.x - 12.0, 13.0)
		draw_rect(sign_r, Color(0.05, 0.05, 0.08, 0.9))
		draw_rect(sign_r, accent, false, 1.0)
		var t: String = info.get("title", "")
		var fs := 9 if t.length() <= 10 else 7
		TextFit.draw(self, font, Vector2(sign_r.position.x, sign_r.position.y + 10.0), t, sign_r.size.x, fs, text_c)

		# ovimatto
		draw_rect(Rect2(door_front.x - 10.0, door_front.y - 6.0, 20.0, 9.0), Color(accent, 0.6))
