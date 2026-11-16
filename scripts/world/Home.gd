extends Node2D
## Pelaajan koti.
##  - ulkopuoli: terrakotta-katto, "KOTI"-kyltti ja ovimatto oven edessä
##  - ovi: E oven edessä vie sisätilaan (kartan ulkopuolella), E sisällä ovelta vie ulos
##  - sisätila: yksiö (sänky, keittiö, ruokapöytä, sohva + tv, matto)
##  - peli alkaa kodin sisältä: CityGenerator kutsuu start_inside()
##  - sänky (E): nuku aamuun, väsymys nollautuu, humala haihtuu, peli tallentuu
##  - jääkaappi (E): syö annos (osta ruokaa kaupasta), keittiöveitsi työtasolla
##  - vuokra (Game.RENT) erääntyy viikoittain; maksamatta ovi on lukossa
##
## CityGenerator luo tämän ja kutsuu setup():ia (sama rakenne kuin Armory.gd).

const TILE := 16

const FLOOR_TILE := Vector2i(1, 4)
const WALL_TILE := Vector2i(19, 2)
const DOOR_TILE := Vector2i(13, 10)

const ROOM_W := 16
const ROOM_H := 11
## Eri paikassa kuin asekaupan sisätila, jotta huoneet eivät osu toistensa näkymään
const INTERIOR_ORIGIN := Vector2(-1800.0, -1000.0)
const EXIT_CELL := Vector2i(8, 10)
const SPAWN_CELL := Vector2i(8, 6)

## Onko pelaaja sisällä (minikartta piiloutuu)
var inside := false
## Oven keskipiste maailmassa (minikartta näyttää tämän kohdan)
var door_px := Vector2.ZERO

var _busy := false
var _saved_limits := {}
var _interior: Node2D
var _fade: ColorRect
var _knife: Node = null
## Kartano (Game.owns_manor): koti siirtyy kartanoon, vanhaan vuokrakämppään muuttaa Sakke
var old_door_px := Vector2.ZERO
var _old_portal: Node = null
var _manor_applied := false
var _kit: Node = null
var _sakke: Node = null
var _sakke_cd := 0.0
var _taunt_t := 0.0
const SAKKE_LINES := ["Mitä sä täällä nuohoot? Tää on mun kämppä nyt!", "Kartanoherra tuli kylään, häh?",
	"Kivinen vuokras tän mulle halvalla. Sun vanhat tapetit on ihan paskat.", "Häivy mun pihalta tai mä häivytän sut."]
const WEAPON_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/weapons/weapon_pickup.tscn")
const REPAIR_KIT_SCRIPT := preload("res://scripts/world/RepairKit.gd")
const GUN_CABINET := preload("res://scripts/world/GunCabinet.gd")


func setup(tile_set: TileSet, source_id: int, roof: Rect2, door_center: Vector2) -> void:
	add_to_group("home")
	global_position = Vector2.ZERO  # piirtokoordinaatit ovat maailmankoordinaatteja
	door_px = door_center
	old_door_px = door_center

	var ext := ExteriorView.new()
	ext.roof = roof
	ext.door_front = door_center + Vector2(0.0, TILE)
	ext.z_index = 50
	add_child(ext)

	_old_portal = _add_portal(door_center + Vector2(0.0, 17.0), true, "Paina E mennäksesi sisään (koti)")
	_build_interior(tile_set, source_id)

	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)


## Etupiha, autotalli ja julkisivun yksityiskohdat (CityGenerator kutsuu setup():n jälkeen).
## Piirretään maan tasolle (hahmojen alle). Pikselialueet maailmankoordinaateissa.
func add_details(lot_px: Rect2, garage_px: Rect2, drive_px: Rect2) -> void:
	var g := GardenView.new()
	g.lot = lot_px
	g.garage = garage_px
	g.drive = drive_px
	g.door_x = door_px.x
	add_child(g)
	# Korjaussetti tallin oikeaan etukulmaan (polkupyörän alapuolelle)
	if garage_px.size.x > 0.0:
		var kit := REPAIR_KIT_SCRIPT.new()
		add_child(kit)
		kit.setup(Vector2(garage_px.end.x + 9.0, garage_px.end.y + 7.0))
		_kit = kit


## Pelin alussa pelaaja syntyy kodin sisälle. Odotetaan yksi ruutu, jotta kamera ja pelaaja ovat valmiina.
## Kartanon omistaja herää kartanosta (ei vanhasta vuokrakämpästä, jossa asuu nyt Sakke).
func start_inside() -> void:
	_fade.color.a = 1.0
	await get_tree().process_frame
	# Odotetaan, että Game on liittänyt kentän ja ladannut tallennuksen (owns_manor ym. ajan tasalla)
	var tries := 0
	while Game.get("_attached_scene") != get_tree().current_scene and tries < 30:
		await get_tree().process_frame
		tries += 1
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		_fade.color.a = 0.0
		return
	if Game.owns_manor:
		if not _manor_applied:
			_apply_manor()
		var mi := get_tree().get_first_node_in_group("manor_interior")
		if mi and mi.has_method("start_inside"):
			_fade.color.a = 0.0
			mi.call("start_inside", player)
			return
	inside = true
	_set_camera_limits(true)
	_move_player(player, _cell_center(SPAWN_CELL))
	_fade.color.a = 1.0
	await _fade_to(0.0)


var _ring_t := 0.0

## Kartano ostettu: koti (ovi, minikartta, paluupaikka) siirtyy kartanoon.
func _apply_manor() -> void:
	var manor := get_tree().get_first_node_in_group("manor") as Node2D
	if manor == null:
		return
	_manor_applied = true
	door_px = manor.get("door_px")
	if _old_portal:
		_old_portal.set("prompt", "Sakke asuu nyt täällä (vanha vuokrakämppä)")
	# omat kulkuneuvot kartanon pihaan (auto, klassikko, superauto) ja korjaussetti mukaan
	var spot := 0
	var own: Array = []
	var car := get_tree().current_scene.get_node_or_null("Car")
	if car:
		own.append(car)
	for g: String in ["classic", "supercar"]:
		for v in get_tree().get_nodes_in_group(g):
			if not own.has(v):
				own.append(v)
	var garage: Node2D = manor.get("garage")
	for v in own:
		if is_instance_valid(v) and not Game.flag(v, "is_driving") and not Game.flag(v, "exploded"):
			if garage and garage.call("store", v):
				continue
			(v as Node2D).global_position = manor.call("parking_spot", spot)
			spot += 1
	if is_instance_valid(_kit):
		_kit.queue_free()
	var kit := REPAIR_KIT_SCRIPT.new()
	add_child(kit)
	kit.setup(manor.call("parking_spot", 3) + Vector2(18.0, -6.0))
	_kit = kit


## Sakke vanhan kodin pihalla: ilmestyy kun pelaaja tulee lähelle, haukkuu ja käy päälle.
func _update_sakke(delta: float) -> void:
	_sakke_cd = maxf(_sakke_cd - delta, 0.0)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var d := player.global_position.distance_to(old_door_px)
	if _sakke != null and not is_instance_valid(_sakke):
		_sakke = null
	if _sakke == null or int(_sakke.get("state")) >= 2:
		if _sakke == null and _sakke_cd <= 0.0 and d < 260.0 and d > 120.0:
			var story := get_tree().get_first_node_in_group("story")
			if story and story.has_method("_spawn_thug"):
				_sakke = story.call("_spawn_thug", old_door_px + Vector2(-14.0, 30.0), "target", "Sakke", 15, 14, 80)
				_sakke_cd = 90.0
		return
	if int(_sakke.get("state")) == 0:   # IDLE: haukkuu, ja liian lähellä käy päälle
		_taunt_t -= delta
		if d < 150.0 and _taunt_t <= 0.0:
			_taunt_t = randf_range(5.0, 8.0)
			_sakke.call("say", SAKKE_LINES[randi() % SAKKE_LINES.size()], 2.6)
		if d < 56.0:
			_sakke.set("state", 1)
			_sakke.call("say", "No niin, nyt se alkaa!", 1.8)


func _process(delta: float) -> void:
	if Game.owns_manor:
		if not _manor_applied:
			_apply_manor()
		_update_sakke(delta)
	# Puhelin soi pelaajan ollessa sisällä
	if inside and not get_tree().paused and phone_ringing():
		_ring_t -= delta
		if _ring_t <= 0.0:
			_ring_t = 2.2
			Sfx.play("phone", INTERIOR_ORIGIN + PHONE_POS, -4.0, 0.0, 1.15)
			get_tree().create_timer(0.35).timeout.connect(_ring_again)
	# Turvaverkko: jos pelaaja on siirretty pois sisätilasta (esim. pidätys), palautetaan kamera
	if not inside or _busy:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and player.global_position.distance_to(INTERIOR_ORIGIN) > 1200.0:
		inside = false
		_set_camera_limits(false)


# ----------------------------------------------------------------------------
#  SISÄTILA
# ----------------------------------------------------------------------------
func _cell_center(c: Vector2i) -> Vector2:
	return INTERIOR_ORIGIN + Vector2(c.x * TILE + TILE * 0.5, c.y * TILE + TILE * 0.5)


func _build_interior(tile_set: TileSet, source_id: int) -> void:
	_interior = Node2D.new()
	_interior.name = "Interior"
	_interior.position = INTERIOR_ORIGIN
	add_child(_interior)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04)
	bg.position = Vector2(-1500.0, -1500.0)
	bg.size = Vector2(3000.0 + ROOM_W * TILE, 3000.0 + ROOM_H * TILE)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -20
	_interior.add_child(bg)

	var floor_layer := TileMapLayer.new()
	floor_layer.tile_set = tile_set
	_interior.add_child(floor_layer)
	for y in ROOM_H:
		for x in ROOM_W:
			var wall := x == 0 or x == ROOM_W - 1 or y <= 1 or y == ROOM_H - 1
			floor_layer.set_cell(Vector2i(x, y), source_id, WALL_TILE if wall else FLOOR_TILE)

	var deco_layer := TileMapLayer.new()
	deco_layer.tile_set = tile_set
	_interior.add_child(deco_layer)
	deco_layer.set_cell(EXIT_CELL, source_id, DOOR_TILE)

	var view := InteriorView.new()
	view.exit_pos = Vector2(EXIT_CELL.x * TILE + TILE * 0.5, EXIT_CELL.y * TILE + TILE * 0.5)
	_interior.add_child(view)

	# Kalusteiden törmäysmuodot (huoneen paikallisissa koordinaateissa)
	var body := StaticBody2D.new()
	_interior.add_child(body)
	for r: Rect2 in InteriorView.SOLIDS:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = r.size
		cs.shape = shape
		cs.position = r.get_center()
		body.add_child(cs)

	_add_portal(_cell_center(EXIT_CELL) + Vector2(0.0, -17.0), false, "Paina E poistuaksesi")
	# Asekaappi takaseinällä kirjahyllyn vieressä, ikkunan alla
	var gc := GUN_CABINET.new()
	_interior.add_child(gc)
	gc.setup(INTERIOR_ORIGIN + Vector2(104.0, 32.0), Vector2(18.0, 12.0), INTERIOR_ORIGIN + Vector2(110.0, 53.0), 8.0, 20.0)
	# Sänky ja jääkaappi
	InteractSpot.create(self, INTERIOR_ORIGIN + Vector2(44.0, 100.0), Vector2(40.0, 14.0),
		"Paina E nukkuaksesi (aamuun, tallentaa pelin)", _sleep)
	InteractSpot.create(self, INTERIOR_ORIGIN + Vector2(230.0, 58.0), Vector2(22.0, 14.0), _fridge_prompt, _eat)
	# Lankapuhelin takaseinällä ikkunoiden välissä
	view.home = self
	InteractSpot.create(self, INTERIOR_ORIGIN + Vector2(PHONE_POS.x, 55.0), Vector2(26.0, 16.0), _phone_prompt, _answer_phone)


# ----------------------------------------------------------------------------
#  LANKAPUHELIN: soi, kun on kuuntelematon viesti. Kertoo vuokrasta, nälästä ja
#  väsymyksestä sekä poliisista. Vuokranantaja soittaa myös ennen eräpäivää.
# ----------------------------------------------------------------------------
const PHONE_POS := Vector2(137.0, 12.0)     ## huoneen paikallisissa koordinaateissa
const LINE_CHARS := 42                     ## valikkoikkunan rivin pituus (merkkiä)

## Viestit: [soittaja, [sivut]]
func _calls() -> Dictionary:
	return {
		"rent": ["Vuokranantaja Kivinen", [
			"Päivää, Kivinen täällä, vuokranantajasi. Pari asiaa kämpästä.",
			"Vuokra on %d $ viikossa. Se veloitetaan eräpäivänä automaattisesti: ensin pankkitililtä, loput lompakosta." % Game.RENT,
			"Jos rahat eivät riitä, vaihdan lukot. Pääset sisään vasta, kun maksat vuokran oven luona.",
			"Seuraava eräpäivä on päivä %d. Pidä tilillä rahaa, niin ei tule riitaa." % Game.rent_due_day,
		]],
		"needs": ["Äiti", [
			"Kulta, äiti tässä. Syöthän sä kunnolla?",
			"Jääkaapista saa ruokaa (E keittiössä). Kaupasta voi ostaa lisää annoksia jääkaappiin tai makkaran heti.",
			"Jos nälkä kasvaa yli 70 %, et jaksa liikkua kunnolla. Pitkään syömättä alat heiketä ja lopulta pyörryt.",
			"Ja nuku välillä! Yli 75 % väsyneenä olet hidas, etkä jaksa juosta. Sängyssä nukut aamuun, ja peli tallentuu.",
			"Juokseminen (Shift) väsyttää. Ja älä juo liikaa, se näkyy aamulla krapulana.",
		]],
		"police": ["Serkku Jartsa", [
			"Jartsa tässä. Kuulin et sä oot taas kaupungissa. Pari vinkkiä poliiseista.",
			"Jos joku näkee rikoksen, se soittaa poliisille. Lyö tai uhkaa todistajaa, tai häivy ennen kuin puhelu menee läpi.",
			"Tähdet kertoo etsinnän tason. Neljällä tähdellä tulee SWAT, viidellä armeija. Älä mene sinne asti.",
			"Kun poliisit ei nää sua, tähdet vilkkuu ja haihtuu pikkuhiljaa. Kotona piilossa ne unohtaa sut nelinkertaisella vauhdilla.",
			"Lievästä jutusta selviää sakolla, jos lompakossa on rahaa. Muuten putkaan, ja kranaatit viedään aina.",
			"Ja joka pidätys pidentää seuraavaa tuomiota. Pidä nenäs puhtaana. Tai ainakin kuivana.",
		]],
		"rent_soon": ["Vuokranantaja Kivinen", [
			"Kivinen taas. Muistutan vain: vuokra %d $ erääntyy päivänä %d." % [Game.RENT, Game.rent_due_day],
			"Varmista, että tilillä tai lompakossa on rahaa. Lukkoseppä on nopea mies.",
		]],
		"rent_late": ["Vuokranantaja Kivinen", [
			"Vuokra on maksamatta, joten lukot on vaihdettu.",
			"Maksa %d $ oven luona, niin avaimet toimivat taas." % Game.RENT,
		]],
	}


## Kuuntelemattomat viestit tärkeysjärjestyksessä.
func pending_calls() -> Array:
	var out: Array = []
	for id: String in ["rent", "needs", "police"]:
		if id == "rent" and Game.owns_manor:
			continue
		if not Game.phone_heard.has(id):
			out.append(id)
	if not Game.owns_manor and not Game.rent_overdue and Game.rent_due_day - Game.day <= 1:
		var key := "rent_soon_%d" % Game.rent_due_day
		if not Game.phone_heard.has(key) and Game.phone_heard.has("rent"):
			out.append(key)
	return out


func _ring_again() -> void:
	if inside and phone_ringing():
		Sfx.play("phone", INTERIOR_ORIGIN + PHONE_POS, -4.0, 0.0, 1.15)


func phone_ringing() -> bool:
	return not pending_calls().is_empty()


func _phone_prompt() -> String:
	if phone_ringing():
		return "Puhelin soi! Paina E vastataksesi"
	return "Paina E: kuuntele puhelinvastaajaa"


func _answer_phone(_player: Node2D) -> void:
	var pend := pending_calls()
	if pend.is_empty():
		var hud := get_tree().current_scene.get_node_or_null("Hud")
		if hud and hud.has_method("show_menu"):
			hud.show_menu("PUHELINVASTAAJA", ["Vuokranantaja: vuokra ja lukot", "Äiti: nälkä ja väsymys", "Serkku Jartsa: poliisit"],
				_replay_choice)
		return
	var id: String = pend[0]
	Game.phone_heard.append(id)
	Sfx.play_ui("clink", -8.0)
	_play_call(id, 0)


func _replay_choice(i: int) -> void:
	if i >= 0 and i < 3:
		_play_call(["rent", "needs", "police"][i], 0)


func _call_next(i: int, id: String, page: int, last: bool) -> void:
	if i == 0 and not last:
		_play_call(id, page + 1)


## Puhelu omassa piirretyssä puhelunäkymässä (PhoneCall.gd): soittajan kasvot ja puhekupla.
const PHONE_CALL := preload("res://scripts/ui/PhoneCall.gd")
const CHAR_SPRITES := preload("res://scripts/core/CharSprites.gd")
## Soittajien kasvot: hahmotyypin ensimmäinen rivi characters_hd.png:ssä
const CALLER_ROWS := {"rent": 6, "rent_soon": 6, "rent_late": 6, "needs": 3, "police": 0}

func _play_call(id: String, _page: int = 0) -> void:
	var key := id
	if id.begins_with("rent_soon"):
		key = "rent_soon"
	var calls := _calls()
	if not calls.has(key) or get_tree().get_first_node_in_group("phone_call") != null:
		return
	var c: Array = calls[key]
	var pc := PHONE_CALL.new()
	pc.caller = str(c[0])
	pc.pages = c[1]
	pc.portrait = CHAR_SPRITES.npc(1, int(CALLER_ROWS.get(key, 0)))
	get_tree().current_scene.add_child(pc)


## Rivitys valikkoikkunan leveyteen (show_menu laskee korkeuden rivinvaihdoista).
func _wrap(text: String) -> String:
	var lines: PackedStringArray = []
	var line := ""
	for w in text.split(" "):
		if line.length() + w.length() + 1 > LINE_CHARS and line != "":
			lines.append(line)
			line = w
		else:
			line = w if line == "" else line + " " + w
	if line != "":
		lines.append(line)
	return "\n".join(lines)


# ----------------------------------------------------------------------------
#  OVET
# ----------------------------------------------------------------------------
func _add_portal(center: Vector2, to_inside: bool, prompt: String) -> Node:
	var p := Portal.new()
	p.home = self
	p.to_inside = to_inside
	p.prompt = prompt
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24.0, 22.0)
	cs.shape = shape
	p.add_child(cs)
	add_child(p)
	p.global_position = center
	return p


## Kartanon ovi (ServiceBuilding "manor") vie samaan kotiin: kaikki tavarat ovat muuttaneet sinne.
func enter_from_manor(player: Node2D) -> void:
	await use_portal(player, true, true)


func use_portal(player: Node2D, to_inside: bool, via_manor: bool = false) -> void:
	if _busy:
		return
	if to_inside and Game.owns_manor and not via_manor:
		Sfx.play_ui("denied", -6.0)
		Game.msg("Ovi on lukossa. Sisältä kuuluu Saken ääni: \"Painu kartanoos, rikas poika!\"", 3.0)
		return
	if to_inside and Game.rent_overdue and not Game.owns_manor:
		var hud0 := get_tree().current_scene.get_node_or_null("Hud")
		if hud0 and hud0.has_method("show_menu"):
			hud0.show_menu("Lukko on vaihdettu!\nVuokra %d $ maksamatta. Rahaa %d $ (lompakko + pankki)." % [Game.RENT, player.money + Game.bank],
				["Maksa vuokra (%d $)" % Game.RENT], _rent_choice.bind(player))
		return
	_busy = true
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	if "velocity" in player:
		player.velocity = Vector2.ZERO
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud:
		hud.hide_instruction()

	await _fade_to(1.0)
	if to_inside:
		inside = true
		_set_camera_limits(true)
		_move_player(player, _cell_center(SPAWN_CELL))
		_respawn_knife()
		_deliver_loot()
	else:
		inside = false
		_set_camera_limits(false)
		_move_player(player, door_px + Vector2(0.0, 28.0))
	await _fade_to(0.0)

	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	_busy = false


func _rent_choice(i: int, player: Node2D) -> void:
	if i != 0:
		return
	if Game.pay_overdue_rent():
		Sfx.play_ui("cash", -4.0)
		Game.msg("Vuokra maksettu. Avaimet toimivat taas.", 2.5)
		use_portal(player, true)
	else:
		Sfx.play_ui("denied", -4.0)
		Game.msg("Rahat eivät riitä vuokraan.", 2.0)


## Juoksuostosten saalis kotiin: ruoat jääkaappiin, esineet lattialle, tupakat taskuun.
func _deliver_loot(parent: Node = null, base: Vector2 = Vector2.INF) -> void:
	if parent == null:
		parent = _interior
	if base == Vector2.INF:
		base = INTERIOR_ORIGIN + Vector2(112.0, 96.0)
	if Game.loot.is_empty():
		return
	var food := 0
	var cigs := 0
	var items := 0
	for v: Variant in Game.loot:
		var id := str(v)
		match id:
			"bag":
				food += 3
			"meal", "sausage", "apple", "energy":
				food += 1
			"cigs":
				cigs += Game.CIG_PACK
			"pen", "knife":
				var w := WEAPON_PICKUP_SCENE.instantiate()
				w.weapon_id = id
				parent.add_child(w)
				w.global_position = base + Vector2(items * 14.0, 0.0)
				items += 1
	Game.loot.clear()
	Game.fridge += food
	Game.cigarettes += cigs
	var parts: Array[String] = []
	if food > 0:
		parts.append("%d annosta jääkaappiin" % food)
	if items > 0:
		parts.append("%d esinettä lattialle" % items)
	if cigs > 0:
		parts.append("%d savuketta taskuun" % cigs)
	Sfx.play_ui("clink", -8.0, 1.1)
	Game.msg("Saalis purettu kotona: %s." % ", ".join(parts), 3.0)


## Kodin keittiöveitsen tunniste (pysyy samana esineenä kädessä ja lattialla).
func _knife_tag() -> String:
	return "home_knife"


## Keittiöveitsi työtasolla, ellei se ole kädessä, lattialla, asekaapissa tai takavarikossa.
func _respawn_knife() -> void:
	if is_instance_valid(_knife):
		return
	if not Game.fixture_should_spawn(_knife_tag()):
		return
	_knife = WEAPON_PICKUP_SCENE.instantiate()
	_knife.weapon_id = "knife"
	_knife.fixture = _knife_tag()
	_interior.add_child(_knife)
	_knife.global_position = INTERIOR_ORIGIN + Vector2(190.0, 60.0)


func _fridge_prompt() -> String:
	if Game.fridge <= 0:
		return "Jääkaappi on tyhjä. Osta ruokaa kaupasta."
	return "Paina E syödäksesi (jääkaapissa %d annosta, nälkä %d %%)" % [Game.fridge, int(Game.hunger)]


func _eat(_player: Node2D) -> void:
	if Game.fridge <= 0:
		Sfx.play_ui("denied", -6.0)
		Game.msg("Jääkaappi on tyhjä. Kauppa (K) myy ruokaa.", 2.0)
		return
	Game.fridge -= 1
	Game.hunger = maxf(Game.hunger - 55.0, 0.0)
	Sfx.play_ui("gulp", -4.0, 0.8)
	Game.msg("Söit. Nälkä %d %%, jääkaappiin jäi %d annosta." % [int(Game.hunger), Game.fridge], 2.5)


## Nukkuminen: kello siirtyy aamuun (tai 8 h eteenpäin), väsymys ja humala katoavat.
func _sleep(player: Node2D) -> void:
	if _busy:
		return
	if Game.fatigue < 25.0 and Game.period() == "päivä":
		Game.msg("Et ole vielä väsynyt.", 1.8)
		return
	var pm := get_tree().get_first_node_in_group("police_manager")
	if pm and pm.wanted > 0:
		Game.msg("Et saa unta, kun poliisi etsii sinua.", 2.0)
		return
	_busy = true
	player.set("menu_locked", true)
	await _fade_to(1.0)
	var h := Game.minutes / 60.0
	var sleep_min := 480.0
	if h >= 18.0:
		sleep_min = (24.0 - h + 8.0) * 60.0
	elif h < 6.0:
		sleep_min = (8.0 - h) * 60.0
	Game.skip_minutes(sleep_min)
	Game.fatigue = 0.0
	Game.add_vitutus(-Game.VITUTUS_SLEEP)
	if player.has_method("sober_up"):
		player.sober_up()
	player.hangover = maxf(player.hangover * 0.5, 0.0)
	player.hp = player.get_max_hp()
	player._refresh_health_hud()
	await get_tree().create_timer(0.6).timeout
	await _fade_to(0.0)
	player.set("menu_locked", false)
	_busy = false
	if Game.can_save():
		Game.save_game()
		Game.msg("Nukuit hyvin. Kello on %s. Peli tallennettu." % Game.clock_text(), 3.0)
	else:
		Game.msg("Nukuit. Kello on %s." % Game.clock_text(), 2.5)


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
			_saved_limits = {
				"l": cam.limit_left, "t": cam.limit_top,
				"r": cam.limit_right, "b": cam.limit_bottom,
			}
		var r := Rect2(INTERIOR_ORIGIN, Vector2(ROOM_W, ROOM_H) * TILE).grow(260.0)
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


# ----------------------------------------------------------------------------
#  SISÄ-LUOKAT
# ----------------------------------------------------------------------------
class Portal extends Area2D:
	var home: Node2D
	var to_inside := true
	var prompt := ""

	func _ready() -> void:
		collision_layer = 0
		collision_mask = 1
		body_entered.connect(_on_enter)
		body_exited.connect(_on_exit)

	func _on_enter(body: Node2D) -> void:
		if not body.has_method("pickup_weapon"):
			return
		body.nearby_portal = self
		var hud := get_tree().current_scene.get_node_or_null("Hud")
		if hud:
			hud.show_instruction(prompt)

	func _on_exit(body: Node2D) -> void:
		if not body.has_method("pickup_weapon"):
			return
		if body.nearby_portal == self:
			body.nearby_portal = null
			var hud := get_tree().current_scene.get_node_or_null("Hud")
			if hud:
				hud.hide_instruction()

	func use(player: Node2D) -> void:
		home.use_portal(player, to_inside)


## Talon päälle piirretty ulkoasu: harjakatto, savupiippu savuineen, kattoikkuna ja ovimatto.
class ExteriorView extends Node2D:
	var roof := Rect2()
	var door_front := Vector2.ZERO
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _on_screen(roof.grow(200.0)):
			queue_redraw()

	## Optimointi: piirretään uudelleen vain kun alue on kameran näkyvissä
	func _on_screen(r: Rect2) -> bool:
		var cam := get_viewport().get_camera_2d()
		if cam == null:
			return true
		var vs := get_viewport().get_visible_rect().size / cam.zoom
		var view := Rect2(cam.get_screen_center_position() - vs * 0.5, vs).grow(160.0)
		return view.intersects(get_global_transform() * r)

	## Sakke asuu nyt täällä: graffiti seinässä oven vieressä
	func _sakke_tag() -> void:
		if not Game.owns_manor:
			return
		var font := ThemeDB.fallback_font
		var p := door_front + Vector2(-46.0, -22.0)
		draw_string_outline(font, p, "SAKKE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 2, Color(0, 0, 0, 0.6))
		draw_string(font, p, "SAKKE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.9, 0.15, 0.2))
		draw_line(p + Vector2(0, 2), p + Vector2(30, 1), Color(0.9, 0.15, 0.2, 0.8), 1.0)

	func _draw() -> void:
		var mid := roof.get_center().y
		var dark := Color(0.47, 0.19, 0.14)    # ylärinne (varjossa)
		var light := Color(0.67, 0.30, 0.21)   # alarinne (valoisa)

		# Räystään varjo seinälle
		draw_rect(Rect2(roof.position.x, roof.end.y, roof.size.x, 3.0), Color(0, 0, 0, 0.28))

		# Kaksi kattolappea
		draw_rect(Rect2(roof.position.x, roof.position.y, roof.size.x, mid - roof.position.y), dark)
		draw_rect(Rect2(roof.position.x, mid, roof.size.x, roof.end.y - mid), light)

		# Kattotiilet: vaakarivit + porrastetut pystysaumat
		var row := 0
		var y := roof.position.y + 5.0
		while y < roof.end.y - 1.0:
			if absf(y - mid) > 3.0:
				draw_line(Vector2(roof.position.x, y), Vector2(roof.end.x, y), Color(0, 0, 0, 0.22), 1.0)
				var x := roof.position.x + (4.0 if row % 2 == 0 else 8.0)
				while x < roof.end.x:
					draw_line(Vector2(x, y), Vector2(x, y + 5.0), Color(0, 0, 0, 0.12), 1.0)
					x += 8.0
			row += 1
			y += 5.0

		# Harja (kattoa pitkin keskellä)
		draw_rect(Rect2(roof.position.x, mid - 2.5, roof.size.x, 5.0), Color(0.33, 0.12, 0.10))
		draw_line(Vector2(roof.position.x, mid - 2.0), Vector2(roof.end.x, mid - 2.0), Color(1, 1, 1, 0.25), 1.0)

		# Päätylistat ja räystäslista
		draw_rect(Rect2(roof.position.x, roof.position.y, 2.0, roof.size.y), Color(0.95, 0.9, 0.8))
		draw_rect(Rect2(roof.end.x - 2.0, roof.position.y, 2.0, roof.size.y), Color(0.95, 0.9, 0.8))
		draw_rect(Rect2(roof.position.x, roof.end.y - 2.0, roof.size.x, 2.0), Color(0.95, 0.9, 0.8))
		draw_rect(Rect2(roof.position.x, roof.position.y, roof.size.x, 1.0), Color(0.3, 0.12, 0.1))

		# Kattoikkuna (alarinteellä)
		if roof.size.y >= 48.0 and roof.size.x >= 64.0:
			var cx := roof.position.x + roof.size.x * 0.3
			var d := Rect2(cx - 10.0, mid + 7.0, 20.0, 14.0)
			draw_rect(d.grow(1.0), Color(0, 0, 0, 0.3))
			draw_rect(d, Color(0.95, 0.9, 0.8))
			draw_rect(d.grow(-3.0), Color(0.55, 0.78, 0.95))
			draw_line(Vector2(d.get_center().x, d.position.y + 3.0), Vector2(d.get_center().x, d.end.y - 3.0), Color(0.95, 0.9, 0.8), 1.0)
			draw_colored_polygon(PackedVector2Array([
				Vector2(d.position.x - 2.0, d.position.y), Vector2(d.get_center().x, d.position.y - 7.0),
				Vector2(d.end.x + 2.0, d.position.y)]), Color(0.33, 0.12, 0.10))

		# Savupiippu (tiili) ja savu
		var ch := Rect2(roof.end.x - 30.0, mid - 22.0, 14.0, 18.0)
		draw_rect(Rect2(ch.position + Vector2(3.0, 3.0), ch.size), Color(0, 0, 0, 0.3))
		draw_rect(ch, Color(0.55, 0.22, 0.17))
		for i in 3:
			draw_line(Vector2(ch.position.x, ch.position.y + 5.0 + i * 5.0), Vector2(ch.end.x, ch.position.y + 5.0 + i * 5.0), Color(0.3, 0.1, 0.08, 0.6), 1.0)
		draw_rect(Rect2(ch.position.x - 1.5, ch.position.y - 3.0, ch.size.x + 3.0, 4.0), Color(0.62, 0.6, 0.6))
		draw_rect(Rect2(ch.position.x + 3.0, ch.position.y - 2.0, ch.size.x - 6.0, 2.0), Color(0.12, 0.1, 0.1))
		for i in 4:
			var ph := fmod(_t * 0.5 + float(i) * 0.25, 1.0)
			var sp := Vector2(ch.get_center().x + ph * 12.0 + sin(_t * 2.0 + i) * 2.0, ch.position.y - 5.0 - ph * 26.0)
			draw_circle(sp, 2.5 + ph * 4.0, Color(0.85, 0.85, 0.88, 0.5 * (1.0 - ph)))

		# Ovimatto
		var mat := Rect2(door_front.x - 10.0, door_front.y - 6.0, 20.0, 9.0)
		draw_rect(mat, Color(0.25, 0.45, 0.3))
		draw_rect(mat, Color(0.85, 0.9, 0.8), false, 1.0)
		_sakke_tag()


## Etupiha, autotalli ja julkisivun yksityiskohdat maan tasolla (hahmot piirtyvät päälle).
class GardenView extends Node2D:
	var lot := Rect2()
	var garage := Rect2()
	var drive := Rect2()
	var door_x := 0.0
	var _t := 0.0
	var _night := -1.0

	func _process(delta: float) -> void:
		_t += delta
		var n := snappedf(Game.darkness(), 0.1)
		if n != _night:
			_night = n
			queue_redraw()

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(lot.position.x * 13.0 + lot.position.y * 7.0)
		var face_top := lot.end.y - 32.0
		var front_y := lot.end.y          # talon edessä oleva nurmirivi
		# --- Syöksytorvet julkisivun kulmissa
		for x: float in [lot.position.x + 1.0, lot.end.x - 4.0]:
			draw_rect(Rect2(x, face_top, 3.0, 32.0), Color(0.62, 0.64, 0.68))
			draw_rect(Rect2(x, face_top, 1.0, 32.0), Color(0.85, 0.87, 0.9))
			draw_rect(Rect2(x - 1.0, lot.end.y - 2.0, 5.0, 2.0), Color(0.5, 0.52, 0.56))
		# --- Seinälamppu oven vieressä (hehkuu pimeällä)
		var lamp := Vector2(door_x + 10.0, face_top + 18.0)
		if _night > 0.05:
			for i in 3:
				draw_circle(lamp, 10.0 - i * 3.0, Color(1.0, 0.85, 0.5, 0.12 * _night))
		draw_rect(Rect2(lamp - Vector2(1.5, 2.0), Vector2(3, 4)), Color(0.15, 0.15, 0.17))
		draw_rect(Rect2(lamp - Vector2(0.5, 1.0), Vector2(1, 2)), Color(1.0, 0.9, 0.6) if _night > 0.05 else Color(0.8, 0.8, 0.75))
		# --- Kukkapenkit talon edessä (ei oven kohdalla)
		var flower_cols := [Color(1.0, 0.35, 0.45), Color(1.0, 0.85, 0.3), Color(0.95, 0.95, 1.0), Color(0.75, 0.5, 1.0), Color(1.0, 0.55, 0.2)]
		for side in 2:
			var x0 := lot.position.x + 3.0 if side == 0 else door_x + 14.0
			var x1 := door_x - 14.0 if side == 0 else lot.end.x - 3.0
			if x1 - x0 < 8.0:
				continue
			var bed := Rect2(x0, front_y + 1.0, x1 - x0, 7.0)
			draw_rect(Rect2(bed.position + Vector2(0, 1), bed.size), Color(0, 0, 0, 0.2))
			draw_rect(bed, Color(0.36, 0.24, 0.15))
			draw_rect(bed, Color(0.62, 0.6, 0.56), false, 1.0)
			var fx := bed.position.x + 2.0
			while fx < bed.end.x - 2.0:
				var fc: Color = flower_cols[rng.randi() % flower_cols.size()]
				var fy := bed.position.y + rng.randf_range(1.5, 4.5)
				draw_rect(Rect2(fx, fy + 1.0, 1, 2), Color(0.2, 0.5, 0.25))
				draw_rect(Rect2(fx - 1.0, fy, 3, 1), fc)
				draw_rect(Rect2(fx, fy - 1.0, 1, 3), fc)
				draw_rect(Rect2(fx, fy, 1, 1), Color(1.0, 0.95, 0.5))
				fx += rng.randf_range(3.0, 5.0)
		# --- Ruukkukasvit oven molemmin puolin
		for sx: float in [-11.0, 11.0]:
			var p := Vector2(door_x + sx, front_y + 3.0)
			draw_rect(Rect2(p + Vector2(-3, 0), Vector2(6, 5)), Color(0.7, 0.36, 0.22))
			draw_rect(Rect2(p + Vector2(-3, 0), Vector2(6, 1)), Color(0.85, 0.5, 0.32))
			draw_circle(p + Vector2(0, -2), 4.0, Color(0.18, 0.5, 0.25))
			draw_circle(p + Vector2(-1, -3), 2.0, Color(0.3, 0.65, 0.3))
		# --- Postilaatikko jalkakäytävän reunalla
		var mb := Vector2(door_x + 22.0, front_y + 20.0)
		draw_rect(Rect2(mb + Vector2(0, -2), Vector2(2, 10)), Color(0.35, 0.3, 0.25))
		draw_rect(Rect2(mb + Vector2(-4, -8), Vector2(10, 7)), Color(0.15, 0.3, 0.6))
		draw_rect(Rect2(mb + Vector2(-4, -8), Vector2(10, 2)), Color(0.3, 0.45, 0.8))
		draw_rect(Rect2(mb + Vector2(5, -10), Vector2(1, 4)), Color(0.9, 0.2, 0.2))
		draw_string(ThemeDB.fallback_font, mb + Vector2(-4, -2), "12", HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Color.WHITE)
		if garage.size.x <= 0.0:
			return
		# --- Roska-astiat talon ja tallin välissä
		var gap_x := (lot.end.x + garage.position.x) * 0.5
		for i in 2:
			var bp := Vector2(gap_x - 5.0 + i * 6.0, lot.end.y - 8.0)
			var bc := Color(0.2, 0.45, 0.25) if i == 0 else Color(0.2, 0.3, 0.6)
			draw_rect(Rect2(bp + Vector2(1, 1), Vector2(5, 7)), Color(0, 0, 0, 0.25))
			draw_rect(Rect2(bp, Vector2(5, 7)), bc)
			draw_rect(Rect2(bp + Vector2(-0.5, 0), Vector2(6, 2)), bc.lightened(0.25))
		# --- Autotalli: katto
		var roof := Rect2(garage.position, Vector2(garage.size.x, garage.size.y - 16.0))
		draw_rect(roof, Color(0.33, 0.34, 0.4))
		var ry := roof.position.y + 4.0
		while ry < roof.end.y - 1.0:
			draw_line(Vector2(roof.position.x, ry), Vector2(roof.end.x, ry), Color(0, 0, 0, 0.18), 1.0)
			ry += 4.0
		draw_rect(Rect2(roof.position, Vector2(roof.size.x, 2)), Color(0.5, 0.52, 0.58))
		draw_rect(Rect2(Vector2(roof.position.x, roof.end.y - 2.0), Vector2(roof.size.x, 2)), Color(0.85, 0.85, 0.82))
		# kattoikkuna
		draw_rect(Rect2(roof.get_center() - Vector2(5, 4), Vector2(10, 7)), Color(0.85, 0.85, 0.82))
		draw_rect(Rect2(roof.get_center() - Vector2(4, 3), Vector2(8, 5)), Color(0.5, 0.72, 0.9))
		# --- Autotalli: etuseinä ja nosto-ovi
		var face := Rect2(Vector2(garage.position.x, roof.end.y), Vector2(garage.size.x, 16.0))
		draw_rect(face, Color(0.88, 0.84, 0.74))
		draw_rect(Rect2(face.position, Vector2(face.size.x, 2)), Color(0.05, 0.05, 0.15, 0.3))
		var door := Rect2(face.position + Vector2(4, 3), Vector2(face.size.x - 8.0, 13.0))
		draw_rect(door, Color(0.92, 0.93, 0.95))
		var dy := door.position.y + 3.0
		while dy < door.end.y:
			draw_line(Vector2(door.position.x, dy), Vector2(door.end.x, dy), Color(0.55, 0.58, 0.64), 1.0)
			dy += 3.0
		draw_rect(door, Color(0.4, 0.42, 0.48), false, 1.0)
		draw_rect(Rect2(door.get_center() + Vector2(-3, 3), Vector2(6, 1)), Color(0.3, 0.3, 0.32))
		# tallin valo oven yläpuolella
		var gl := Vector2(face.get_center().x, face.position.y + 2.0)
		if _night > 0.05:
			draw_colored_polygon(PackedVector2Array([gl, gl + Vector2(-14, 26), gl + Vector2(14, 26)]), Color(1.0, 0.9, 0.6, 0.12 * _night))
		draw_rect(Rect2(gl - Vector2(2, 0), Vector2(4, 2)), Color(1.0, 0.9, 0.6) if _night > 0.05 else Color(0.7, 0.7, 0.68))
		# --- Ajoluiska: renkaanjäljet ja öljytahra
		if drive.size.x > 0.0:
			for tx: float in [drive.position.x + 9.0, drive.end.x - 11.0]:
				draw_rect(Rect2(tx, drive.position.y, 3.0, drive.size.y), Color(0, 0, 0, 0.1))
			draw_set_transform(drive.get_center() + Vector2(0, -6), 0.0, Vector2(1.0, 0.55))
			draw_circle(Vector2.ZERO, 4.0, Color(0.02, 0.02, 0.05, 0.25))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# --- Polkupyörä tallin seinää vasten
		var bk := Vector2(garage.end.x + 3.0, garage.end.y - 4.0)
		draw_arc(bk + Vector2(0, 0), 3.0, 0.0, TAU, 10, Color(0.1, 0.1, 0.1), 1.0)
		draw_arc(bk + Vector2(9, 0), 3.0, 0.0, TAU, 10, Color(0.1, 0.1, 0.1), 1.0)
		draw_polyline(PackedVector2Array([bk, bk + Vector2(4, -4), bk + Vector2(9, 0), bk + Vector2(5, 0), bk]), Color(0.85, 0.2, 0.2), 1.0)
		draw_line(bk + Vector2(4, -4), bk + Vector2(3, -6), Color(0.1, 0.1, 0.1), 1.0)
		draw_line(bk + Vector2(8, -3), bk + Vector2(9, -6), Color(0.6, 0.6, 0.6), 1.0)


## Sisätilan kalusteet. Koordinaatit huoneen paikallisia (pikseleitä).
class InteriorView extends Node2D:
	## Törmäävät kalusteet
	const BED := Rect2(24, 36, 40, 56)
	const STAND := Rect2(68, 36, 14, 14)
	const COUNTER := Rect2(150, 32, 90, 18)
	const TABLE := Rect2(170, 86, 40, 28)
	const SOFA := Rect2(24, 112, 52, 20)
	const TV := Rect2(24, 146, 52, 10)
	const SHELF := Rect2(88, 32, 14, 12)
	const PLANT_A := Rect2(18, 94, 12, 12)
	const PLANT_B := Rect2(128, 34, 12, 12)
	const SHOWER := Rect2(212, 120, 28, 22)
	const TOILET := Rect2(218, 144, 14, 14)
	const COFFEE := Rect2(34, 134, 32, 8)
	const SOLIDS := [BED, STAND, COUNTER, TABLE, SOFA, TV, SHELF, PLANT_A, PLANT_B, SHOWER, TOILET, COFFEE]

	var exit_pos := Vector2.ZERO
	var home: Node = null
	var _t := 0.0
	var _acc := 0.0

	func _process(delta: float) -> void:
		_t += delta
		_acc += delta
		if _acc > 0.1:
			_acc = 0.0
			if _on_screen(Rect2(-100.0, -100.0, 520.0, 400.0)):
				queue_redraw()

	## Optimointi: piirretään uudelleen vain kun alue on kameran näkyvissä
	func _on_screen(r: Rect2) -> bool:
		var cam := get_viewport().get_camera_2d()
		if cam == null:
			return true
		var vs := get_viewport().get_visible_rect().size / cam.zoom
		var view := Rect2(cam.get_screen_center_position() - vs * 0.5, vs).grow(160.0)
		return view.intersects(get_global_transform() * r)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var outline := Color(0, 0, 0, 0.55)

		# Lankkulattia
		var fl := Rect2(16, 32, 224, 128)
		draw_rect(fl, Color(0.56, 0.39, 0.25))
		var row := 0
		var py := fl.position.y
		while py < fl.end.y:
			var shade := 0.04 if row % 2 == 0 else -0.03
			draw_rect(Rect2(fl.position.x, py, fl.size.x, 6), Color(1, 1, 1, shade) if shade > 0.0 else Color(0, 0, 0, -shade))
			draw_line(Vector2(fl.position.x, py), Vector2(fl.end.x, py), Color(0.3, 0.2, 0.12, 0.5), 1.0)
			var px := fl.position.x + (row * 23) % 40
			while px < fl.end.x:
				draw_line(Vector2(px, py), Vector2(px, py + 6), Color(0.3, 0.2, 0.12, 0.45), 1.0)
				px += 40.0
			py += 6.0
			row += 1
		# Takaseinän tapetti ja jalkalista
		draw_rect(Rect2(16, 0, 224, 32), Color(0.86, 0.8, 0.66))
		var sx := 20.0
		while sx < 240.0:
			draw_rect(Rect2(sx, 0, 3, 30), Color(0.78, 0.7, 0.55))
			sx += 9.0
		draw_rect(Rect2(16, 29, 224, 3), Color(0.45, 0.3, 0.2))
		# Sivu- ja alaseinät (ovi jätetään näkyviin)
		draw_rect(Rect2(0, 0, 16, 176), Color(0.62, 0.55, 0.45))
		draw_rect(Rect2(240, 0, 16, 176), Color(0.62, 0.55, 0.45))
		draw_rect(Rect2(14, 32, 2, 128), Color(0, 0, 0, 0.25))
		draw_rect(Rect2(240, 32, 2, 128), Color(0, 0, 0, 0.15))
		draw_rect(Rect2(16, 160, 112, 16), Color(0.62, 0.55, 0.45))
		draw_rect(Rect2(144, 160, 96, 16), Color(0.62, 0.55, 0.45))
		draw_rect(Rect2(16, 160, 224, 1), Color(0, 0, 0, 0.3))
		# Kattovalon valokeila
		for i in 4:
			draw_circle(Vector2(128, 96), 70.0 - i * 15.0, Color(1.0, 0.9, 0.65, 0.035))

		# Matto keskellä
		var rug := Rect2(90, 64, 70, 62)
		draw_rect(rug, Color(0.25, 0.42, 0.55))
		draw_rect(rug, Color(0.9, 0.85, 0.7), false, 1.0)
		draw_rect(rug.grow(-4.0), Color(0.18, 0.32, 0.44), false, 1.0)

		# Ikkunat takaseinällä
		for wx in [100.0, 150.0]:
			var w := Rect2(wx, 6.0, 26.0, 18.0)
			draw_rect(w, Color(0.55, 0.78, 0.95))
			draw_rect(w, Color(0.95, 0.92, 0.85), false, 2.0)
			draw_line(Vector2(w.get_center().x, w.position.y), Vector2(w.get_center().x, w.end.y), Color(0.95, 0.92, 0.85), 1.0)
			draw_rect(Rect2(w.position.x - 4, 3, 5, 24), Color(0.7, 0.2, 0.22))
			draw_rect(Rect2(w.end.x - 1, 3, 5, 24), Color(0.7, 0.2, 0.22))
			draw_rect(Rect2(w.position.x - 5, 2, w.size.x + 10, 2), Color(0.35, 0.25, 0.18))

		# Taulu sängyn yläpuolella
		draw_rect(Rect2(32, 6, 22, 16), Color(0.4, 0.27, 0.16))
		draw_rect(Rect2(34, 8, 18, 12), Color(0.55, 0.75, 0.9))
		draw_colored_polygon(PackedVector2Array([Vector2(34, 20), Vector2(42, 12), Vector2(52, 20)]), Color(0.3, 0.55, 0.3))
		draw_circle(Vector2(47, 11), 2.0, Color(1.0, 0.9, 0.4))
		# Seinäkello: näyttää pelin ajan
		var clk := Vector2(76, 14)
		draw_circle(clk, 7.0, Color(0.25, 0.2, 0.15))
		draw_circle(clk, 6.0, Color(0.97, 0.96, 0.92))
		var hr := fmod(Game.minutes / 60.0, 12.0)
		var mn := fmod(Game.minutes, 60.0)
		draw_line(clk, clk + Vector2.from_angle(hr / 12.0 * TAU - PI * 0.5) * 3.5, Color(0.1, 0.1, 0.1), 1.0)
		draw_line(clk, clk + Vector2.from_angle(mn / 60.0 * TAU - PI * 0.5) * 5.0, Color(0.1, 0.1, 0.1), 1.0)
		# Keittiön yläkaapit
		draw_rect(Rect2(180, 6, 56, 16), Color(0.62, 0.45, 0.3))
		for i in 3:
			draw_rect(Rect2(181 + i * 18.5, 7, 17, 14), Color(0, 0, 0, 0.35), false, 1.0)
			draw_rect(Rect2(188 + i * 18.5, 17, 3, 1), Color(0.85, 0.8, 0.7))
		draw_rect(Rect2(180, 22, 56, 2), Color(0, 0, 0, 0.2))

		# Sänky: runko, peitto, tyyny
		draw_rect(BED, Color(0.42, 0.27, 0.16))
		draw_rect(Rect2(BED.position.x + 3, BED.position.y + 14, BED.size.x - 6, BED.size.y - 17), Color(0.3, 0.5, 0.8))
		draw_rect(Rect2(BED.position.x + 5, BED.position.y + 3, BED.size.x - 10, 10), Color(0.95, 0.95, 0.95))
		draw_rect(BED, outline, false, 1.0)
		draw_rect(STAND, Color(0.5, 0.33, 0.2))
		draw_rect(STAND, outline, false, 1.0)
		draw_circle(STAND.get_center(), 3.0, Color(1.0, 0.9, 0.5))

		# Keittiö: työtaso, hella, tiskiallas, jääkaappi
		draw_rect(COUNTER, Color(0.78, 0.8, 0.84))
		draw_rect(Rect2(COUNTER.position.x + 6, COUNTER.position.y + 3, 22, 12), Color(0.45, 0.5, 0.58))   # allas
		for i in 4:
			var c := Vector2(COUNTER.position.x + 44 + (i % 2) * 12, COUNTER.position.y + 6 + floori(i / 2.0) * 7)
			draw_circle(c, 3.0, Color(0.15, 0.15, 0.17))
		draw_rect(Rect2(COUNTER.end.x - 20, COUNTER.position.y, 20, COUNTER.size.y), Color(0.92, 0.93, 0.95))  # jääkaappi
		draw_rect(Rect2(COUNTER.end.x - 4, COUNTER.position.y + 5, 1, 8), Color(0.6, 0.6, 0.62))
		draw_rect(COUNTER, outline, false, 1.0)
		# kattila hellalla (höyryää), vedenkeitin, mikro, magneetit jääkaapissa
		var pot := Vector2(COUNTER.position.x + 50, COUNTER.position.y + 9)
		draw_circle(pot, 4.5, Color(0.6, 0.62, 0.66))
		draw_circle(pot, 3.0, Color(0.85, 0.55, 0.3))
		for i in 2:
			var ph := fmod(_t * 0.6 + i * 0.5, 1.0)
			draw_circle(pot + Vector2(sin(_t * 2.0 + i) * 2.0, -4.0 - ph * 10.0), 1.5 + ph * 2.0, Color(1, 1, 1, 0.35 * (1.0 - ph)))
		draw_rect(Rect2(COUNTER.position.x + 66, COUNTER.position.y + 3, 6, 8), Color(0.2, 0.2, 0.22))
		draw_rect(Rect2(COUNTER.position.x + 74, COUNTER.position.y + 2, 18, 11), Color(0.85, 0.85, 0.87))
		draw_rect(Rect2(COUNTER.position.x + 76, COUNTER.position.y + 4, 11, 7), Color(0.15, 0.15, 0.18))
		draw_rect(Rect2(COUNTER.end.x - 16, COUNTER.position.y + 4, 3, 3), Color(1.0, 0.3, 0.3))
		draw_rect(Rect2(COUNTER.end.x - 11, COUNTER.position.y + 9, 3, 3), Color(0.3, 0.6, 1.0))

		# Ruokapöytä ja tuolit
		for cx in [TABLE.position.x - 9.0, TABLE.end.x + 3.0]:
			draw_rect(Rect2(cx, TABLE.position.y + 8, 6, 12), Color(0.38, 0.24, 0.14))
		draw_rect(TABLE, Color(0.55, 0.36, 0.2))
		draw_rect(TABLE, outline, false, 1.0)
		draw_circle(TABLE.get_center(), 4.0, Color(0.95, 0.95, 0.9))

		# Sohva ja televisio
		draw_rect(SOFA, Color(0.65, 0.2, 0.22))
		draw_rect(Rect2(SOFA.position.x, SOFA.position.y + SOFA.size.y - 5, SOFA.size.x, 5), Color(0.5, 0.14, 0.16))
		draw_rect(SOFA, outline, false, 1.0)
		draw_rect(TV, Color(0.08, 0.08, 0.1))
		draw_rect(Rect2(TV.position.x + 2, TV.position.y + 1, TV.size.x - 4, TV.size.y - 3), Color(0.3, 0.55, 0.7))

		# Sohvapöytä: pizzalaatikko ja tölkit
		draw_rect(COFFEE, Color(0.45, 0.3, 0.18))
		draw_rect(COFFEE, outline, false, 1.0)
		draw_rect(Rect2(COFFEE.position + Vector2(3, 1), Vector2(12, 6)), Color(0.85, 0.75, 0.55))
		draw_rect(Rect2(COFFEE.position + Vector2(5, 2), Vector2(8, 1)), Color(0.8, 0.2, 0.15))
		for i in 2:
			draw_rect(Rect2(COFFEE.position + Vector2(19 + i * 5, 2), Vector2(3, 4)), Color(0.2, 0.45, 0.85))
		# Pelikonsoli ja ohjain TV:n edessä
		draw_rect(Rect2(TV.position.x + 30, TV.position.y - 4, 10, 3), Color(0.12, 0.12, 0.14))
		draw_rect(Rect2(TV.position.x + 31, TV.position.y - 3, 2, 1), Color(0.3, 1.0, 0.4))
		# Lattiavalaisin sohvan vieressä
		var lmp := Vector2(84, 116)
		for i in 3:
			draw_circle(lmp, 14.0 - i * 4.0, Color(1.0, 0.85, 0.55, 0.08))
		draw_circle(lmp, 5.0, Color(0.95, 0.88, 0.7))
		draw_circle(lmp, 2.0, Color(1.0, 0.95, 0.75))
		_draw_phone(font)
		# Kirjahylly
		draw_rect(SHELF, Color(0.42, 0.28, 0.17))
		var bx := SHELF.position.x + 2.0
		var bcols := [Color(0.75, 0.2, 0.2), Color(0.2, 0.45, 0.75), Color(0.9, 0.75, 0.3), Color(0.3, 0.6, 0.35), Color(0.85, 0.85, 0.8), Color(0.5, 0.3, 0.6)]
		var bi := 0
		while bx < SHELF.end.x - 3.0:
			var bw := 2.0 + float(bi % 3)
			draw_rect(Rect2(bx, SHELF.position.y + 2.0 + float(bi % 2), bw, 8.0 - float(bi % 2)), bcols[bi % bcols.size()])
			bx += bw + 0.5
			bi += 1
		draw_rect(SHELF, outline, false, 1.0)
		# Viherkasvit
		for pr: Rect2 in [PLANT_A, PLANT_B]:
			var c := pr.get_center()
			draw_rect(Rect2(c + Vector2(-4, 0), Vector2(8, 6)), Color(0.75, 0.4, 0.25))
			draw_circle(c + Vector2(0, -2), 5.5, Color(0.15, 0.45, 0.22))
			draw_circle(c + Vector2(-2, -4), 3.0, Color(0.25, 0.6, 0.3))
			draw_circle(c + Vector2(3, -1), 2.5, Color(0.2, 0.55, 0.28))
		# Kylpyhuone: väliseinä, suihku (verho) ja wc
		draw_rect(Rect2(208, 116, 3, 44), Color(0.75, 0.7, 0.6))
		draw_rect(SHOWER, Color(0.8, 0.9, 0.95))
		var gy := SHOWER.position.y + 4.0
		while gy < SHOWER.end.y:
			draw_line(Vector2(SHOWER.position.x, gy), Vector2(SHOWER.end.x, gy), Color(0.6, 0.72, 0.8), 1.0)
			gy += 4.0
		var gx := SHOWER.position.x + 4.0
		while gx < SHOWER.end.x:
			draw_line(Vector2(gx, SHOWER.position.y), Vector2(gx, SHOWER.end.y), Color(0.6, 0.72, 0.8), 1.0)
			gx += 4.0
		draw_circle(SHOWER.get_center(), 1.5, Color(0.4, 0.45, 0.5))
		draw_rect(Rect2(SHOWER.position.x, SHOWER.end.y - 3, SHOWER.size.x * 0.6, 3), Color(0.95, 0.85, 0.3))
		draw_rect(SHOWER, outline, false, 1.0)
		draw_rect(Rect2(TOILET.position + Vector2(1, 0), Vector2(TOILET.size.x - 2, 5)), Color(0.95, 0.95, 0.97))
		draw_circle(TOILET.position + Vector2(TOILET.size.x * 0.5, 9), 5.5, Color(0.95, 0.95, 0.97))
		draw_circle(TOILET.position + Vector2(TOILET.size.x * 0.5, 9), 3.0, Color(0.7, 0.8, 0.85))
		draw_rect(TOILET, Color(0, 0, 0, 0.2), false, 1.0)
		# Eteinen: kenkämatto, kengät ja naulakko
		draw_rect(Rect2(112, 148, 14, 9), Color(0.35, 0.4, 0.3))
		draw_rect(Rect2(114, 150, 4, 2), Color(0.15, 0.1, 0.08))
		draw_rect(Rect2(119, 152, 4, 2), Color(0.15, 0.1, 0.08))
		draw_circle(Vector2(153, 152), 3.0, Color(0.35, 0.25, 0.15))
		draw_rect(Rect2(148, 146, 5, 8), Color(0.25, 0.35, 0.6))
		draw_rect(Rect2(154, 147, 4, 7), Color(0.6, 0.25, 0.2))
		# Pyykkikori
		draw_rect(Rect2(92, 140, 12, 10), Color(0.85, 0.8, 0.65))
		draw_rect(Rect2(93, 139, 5, 3), Color(0.9, 0.4, 0.4))
		draw_rect(Rect2(98, 138, 5, 4), Color(0.4, 0.6, 0.9))
		# Kissa nukkuu matolla (häntä heiluu)
		var cat := Vector2(108, 112)
		draw_set_transform(cat, 0.0, Vector2(1.0, 0.75))
		draw_circle(Vector2.ZERO, 6.0, Color(0.92, 0.55, 0.22))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(cat + Vector2(-5, -2), 3.5, Color(0.92, 0.55, 0.22))
		draw_colored_polygon(PackedVector2Array([cat + Vector2(-8, -4), cat + Vector2(-7, -8), cat + Vector2(-5, -5)]), Color(0.92, 0.55, 0.22))
		draw_colored_polygon(PackedVector2Array([cat + Vector2(-4, -5), cat + Vector2(-2, -8), cat + Vector2(-2, -4)]), Color(0.92, 0.55, 0.22))
		draw_line(cat + Vector2(-6, -2), cat + Vector2(-5, -2), Color(0.2, 0.1, 0.05), 1.0)
		for i in 3:
			draw_line(cat + Vector2(-2 + i * 3, -4), cat + Vector2(-1 + i * 3, 0), Color(0.75, 0.4, 0.15), 1.0)
		var tail := cat + Vector2(5, 2)
		draw_line(tail, tail + Vector2(5, 2).rotated(sin(_t * 1.5) * 0.5), Color(0.92, 0.55, 0.22), 2.0)
		# Zzz
		var zz := fmod(_t * 0.4, 1.0)
		draw_string(font, cat + Vector2(-6, -10 - zz * 8), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(1, 1, 1, 0.7 * (1.0 - zz)))

		TextFit.draw(self, font, Vector2(exit_pos.x - 30.0, exit_pos.y - 20.0), "ULOS", 60.0, 8, Color(1, 1, 1, 0.8))
		draw_string(font, Vector2(8.0, 12.0), "KARTANO" if Game.owns_manor else "KOTI", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.35))
		if Game.owns_manor:
			_manor_decor(font)

	## Kartanon sisustus: persialainen matto, kultakehysten taulut, kattokruunu ja kultalista.
	func _manor_decor(font: Font) -> void:
		draw_rect(Rect2(16, 29, 224, 3), Color(0.85, 0.68, 0.3))
		var rug := Rect2(92.0, 64.0, 66.0, 40.0)
		draw_rect(rug, Color(0.5, 0.08, 0.12))
		draw_rect(rug.grow(-3.0), Color(0.85, 0.65, 0.3), false, 1.0)
		draw_rect(rug.grow(-7.0), Color(0.2, 0.25, 0.45))
		draw_rect(rug.grow(-10.0), Color(0.85, 0.65, 0.3), false, 1.0)
		var rc := rug.get_center()
		draw_colored_polygon(PackedVector2Array([rc + Vector2(0, -8), rc + Vector2(12, 0), rc + Vector2(0, 8), rc + Vector2(-12, 0)]), Color(0.6, 0.12, 0.15))
		draw_circle(rc, 2.5, Color(0.9, 0.75, 0.35))
		for k in 7:
			draw_line(Vector2(rug.position.x + 4.0 + k * 9.5, rug.position.y), Vector2(rug.position.x + 4.0 + k * 9.5, rug.position.y - 2.0), Color(0.9, 0.85, 0.7), 1.0)
			draw_line(Vector2(rug.position.x + 4.0 + k * 9.5, rug.end.y), Vector2(rug.position.x + 4.0 + k * 9.5, rug.end.y + 2.0), Color(0.9, 0.85, 0.7), 1.0)
		# taulut seinällä
		for pr: Rect2 in [Rect2(28.0, 6.0, 26.0, 18.0), Rect2(198.0, 6.0, 26.0, 18.0)]:
			draw_rect(pr.grow(2.0), Color(0.85, 0.68, 0.3))
			draw_rect(pr, Color(0.25, 0.32, 0.22))
			draw_rect(Rect2(pr.position.x, pr.position.y + 11.0, pr.size.x, 7.0), Color(0.35, 0.45, 0.25))
			draw_circle(pr.position + Vector2(18.0, 6.0), 3.0, Color(0.95, 0.85, 0.5))
		# kattokruunu
		var ch := Vector2(76.0, 13.0)
		draw_circle(ch + Vector2(0, 40), 46.0, Color(1.0, 0.9, 0.6, 0.06 + 0.02 * sin(_t * 2.0)))
		draw_line(ch + Vector2(0, -14), ch, Color(0.85, 0.68, 0.3), 1.0)
		draw_arc(ch, 9.0, 0.0, PI, 10, Color(0.85, 0.68, 0.3), 1.5)
		for k in 5:
			var cp := ch + Vector2(-9.0 + k * 4.5, 4.0 + absf(k - 2) * -1.0)
			draw_rect(Rect2(cp - Vector2(0.6, 3.0), Vector2(1.2, 3.0)), Color(0.97, 0.95, 0.88))
			draw_circle(cp - Vector2(0, 3.8), 1.0 + 0.3 * sin(_t * 9.0 + k), Color(1.0, 0.8, 0.3))
		for k in 4:
			draw_circle(ch + Vector2(-6.0 + k * 4.0, 9.0), 0.9, Color(0.85, 0.95, 1.0))

	## Seinäpuhelin (punainen, kiekkovalitsin, kiharajohto). Soidessa luuri hytkyy
	## ja ympärillä näkyy ääniaaltoja ja vilkkuva merkkivalo.
	func _draw_phone(font: Font) -> void:
		var ringing: bool = home != null and home.phone_ringing()
		var p := Vector2(137.0, 12.0)
		var shake := Vector2.ZERO
		if ringing and fmod(_t, 2.2) < 0.9:
			shake = Vector2(sin(_t * 60.0) * 0.8, 0.0)
		# taustalevy seinässä
		draw_rect(Rect2(p.x - 7.0, p.y - 7.0, 14.0, 16.0), Color(0.35, 0.25, 0.18))
		draw_rect(Rect2(p.x - 7.0, p.y - 7.0, 14.0, 16.0), Color(0, 0, 0, 0.5), false, 1.0)
		# runko + kiekkovalitsin
		var body := Rect2(p.x - 5.5, p.y - 3.0, 11.0, 10.0)
		draw_rect(body, Color(0.75, 0.13, 0.12))
		draw_rect(Rect2(body.position.x, body.position.y, body.size.x, 2.0), Color(0.9, 0.3, 0.25))
		draw_rect(body, Color(0.25, 0.04, 0.04), false, 1.0)
		draw_circle(p + Vector2(0.0, 2.0), 3.2, Color(0.95, 0.92, 0.85))
		draw_circle(p + Vector2(0.0, 2.0), 1.2, Color(0.75, 0.13, 0.12))
		for k in 6:
			draw_circle(p + Vector2(0.0, 2.0) + Vector2.from_angle(k * TAU / 6.0 - 0.6) * 2.3, 0.45, Color(0.2, 0.2, 0.2))
		# luuri hookissa (hytkyy soidessa)
		var h := p + Vector2(0.0, -5.0) + shake + Vector2(0.0, -0.8 if ringing and fmod(_t * 8.0, 1.0) < 0.5 else 0.0)
		draw_rect(Rect2(h.x - 7.0, h.y - 1.5, 14.0, 3.0), Color(0.7, 0.11, 0.1))
		draw_rect(Rect2(h.x - 7.5, h.y - 2.0, 3.0, 4.0), Color(0.6, 0.09, 0.08))
		draw_rect(Rect2(h.x + 4.5, h.y - 2.0, 3.0, 4.0), Color(0.6, 0.09, 0.08))
		draw_rect(Rect2(h.x - 7.0, h.y - 1.5, 14.0, 1.0), Color(0.92, 0.35, 0.3))
		# kiharajohto alas
		var y := p.y + 7.0
		var k2 := 0
		while y < p.y + 18.0:
			draw_line(Vector2(p.x - 4.0 + (1.2 if k2 % 2 == 0 else -1.2), y), Vector2(p.x - 4.0 + (-1.2 if k2 % 2 == 0 else 1.2), y + 1.5),
				Color(0.55, 0.1, 0.1), 1.0)
			y += 1.5
			k2 += 1
		if ringing:
			# ääniaallot ja merkkivalo
			var ph := fmod(_t * 1.4, 1.0)
			for side in [-1.0, 1.0]:
				for k in 2:
					var r := 9.0 + k * 4.0 + ph * 3.0
					draw_arc(p, r, -0.6 + (0.0 if side > 0.0 else PI), 0.6 + (0.0 if side > 0.0 else PI), 8,
						Color(1.0, 0.95, 0.6, (0.8 - k * 0.3) * (1.0 - ph)), 1.0)
			if fmod(_t * 3.0, 1.0) < 0.5:
				draw_circle(p + Vector2(4.0, -1.0), 1.0, Color(0.3, 1.0, 0.4))
			TextFit.draw(self, font, p + Vector2(-16.0, 30.0), "RING!", 32.0, 6, Color(1.0, 0.95, 0.6, 0.6 + 0.4 * sin(_t * 10.0)))
