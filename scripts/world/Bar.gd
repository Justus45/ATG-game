extends Node2D
## Baari, jossa myydään Koskenkorvaa.
##  - ulkopuoli: tummansininen katto, neonkyltti "BAARI" ja Koskenkorva-pullo katolla
##  - ovi: E oven edessä vie sisätilaan (kartan ulkopuolella), E sisällä ovelta vie ulos
##  - sisätila: tiski, baarimikko, pullohylly, jakkarat, pöydät ja jukeboksi
##  - tiskillä on kolme tilauspaikkaa: olut, kossu ja shotti (DRINKS). Jokaisella on oma
##    hinta, vahvuus ja imeytymisnopeus. Player2D.drink() nostaa promilleja, ja kun
##    juo tarpeeksi pelaaja on kännissä: kamera heiluu, kuva sumenee ja kaksoistuu,
##    kävely kaartelee ja lopulta pelaaja sammuu. Humalan säädöt ovat Player2D.gd:n yläosassa.
##  - jukeboksi: E vaihtaa kappaletta (Sfx.gd syntetisoi musiikin)
##  - pelit rahasta: biljardi, tikanheitto ja ventti (BarGames.gd)
##  - portsari: liika tappelu, aseet tai rauhallisten asiakkaiden lyöminen -> ulos;
##    toisesta kerrasta kieltolista muutamaksi minuutiksi (Game.bar_strike)
##  - tutut kasvot: rähinöitsijät muistavat edellisen tappelun (Game.grudges)
##  - aukioloajat 12–04, valomerkki neljältä. Oman baarin omistajalle juomat ovat ilmaisia.
##  - baarin kulmalla Kalle (pimeät keikat) ja tiskin päässä baarimikko (tehtävät), JobManager.gd
##
## CityGenerator luo tämän ja kutsuu setup():ia (sama rakenne kuin Armory.gd).

const TILE := 16

# Sisätilan tiilet kaupungin tilemapista (samat kuin Armory.gd:ssä)
const FLOOR_TILE := Vector2i(1, 4)
const WALL_TILE := Vector2i(19, 2)
const DOOR_TILE := Vector2i(13, 10)

const ROOM_W := 22
const ROOM_H := 13
## Sisätila sijaitsee kartan ulkopuolella, eri paikassa kuin asekauppa ja koti
const INTERIOR_ORIGIN := Vector2(-1800.0, 1400.0)
const EXIT_CELL := Vector2i(11, 12)
const SPAWN_CELL := Vector2i(11, 10)

## Huoneen paikalliset pikselikoordinaatit
const COUNTER := Rect2(16.0, 64.0, 320.0, 14.0)
const STAFF_ZONE := Rect2(16.0, 32.0, 320.0, 46.0)   # tiski + sen takaosa (ei kulkua)
const SERVE_SPOT := Rect2(120.0, 80.0, 112.0, 26.0)  # tässä kohdassa E tilaa ryypyn
const TABLE_L := Rect2(54.0, 140.0, 20.0, 20.0)
const TABLE_R := Rect2(278.0, 140.0, 20.0, 20.0)
const JUKEBOX := Rect2(304.0, 104.0, 24.0, 22.0)
const POOL_TABLE := Rect2(120.0, 124.0, 64.0, 30.0)
const SOLIDS: Array[Rect2] = [STAFF_ZONE, TABLE_L, TABLE_R, JUKEBOX, POOL_TABLE]
const OPEN_HOUR := 12
const CLOSE_HOUR := 4
const FIGHT_LIMIT := 20.0      ## sekuntia tappelua ennen kuin portsari puuttuu
const TROUBLE_LIMIT := 3       ## kaadetut asiakkaat / rettelöinti ennen ulosheittoa
const WEAPON_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/weapons/weapon_pickup.tscn")
## Lattia, jolla asiakkaat voivat liikkua (huoneen paikalliset koordinaatit)
const FLOOR_RECT := Rect2(22.0, 38.0, 308.0, 148.0)
## Asiakkaiden aloituspaikat
const PATRON_SPOTS: Array[Vector2] = [
	Vector2(40.0, 118.0), Vector2(300.0, 156.0), Vector2(90.0, 168.0), Vector2(252.0, 96.0),
]
## Sama kuin CityGenerator.NPC_TYPES (NPC-hahmotyyppejä tilemapissa)
const NPC_TYPES := 6
const PatronScript := preload("res://scripts/world/BarPatron.gd")
const BusinessScript := preload("res://scripts/world/BarBusiness.gd")
const NeonSignScript := preload("res://scripts/world/BarNeon.gd")
## Toimiston ovi (alaseinä) ja keittiön luukku (tiskin vasen pää), huoneen paikalliset koordinaatit
const OFFICE_SPOT := Vector2(104.0, 178.0)
## Tiski: kiinteä osa ja oikean pään luukku (aukeaa vain omistajalle, pääsy tiskin taakse)
const COUNTER_BLOCK := Rect2(16.0, 62.0, 296.0, 18.0)
const FLAP := Rect2(312.0, 62.0, 24.0, 18.0)
## Toimistohuone (oma huone baarin alapuolella, huoneen paikalliset koordinaatit OFFICE_ORIGIN:sta)
const OFFICE_ORIGIN := Vector2(0.0, 560.0)
const OFFICE_W := 12
const OFFICE_H := 9
const OFFICE_EXIT_CELL := Vector2i(6, 8)
const OFFICE_SPAWN := Vector2(104.0, 106.0)
const OFFICE_DESK := Rect2(72.0, 40.0, 48.0, 18.0)
const OFFICE_SAFE := Rect2(150.0, 36.0, 20.0, 20.0)
const OFFICE_SOFA := Rect2(20.0, 92.0, 16.0, 30.0)
const OFFICE_PLANT := Rect2(156.0, 108.0, 14.0, 14.0)
const ServiceScript := preload("res://scripts/world/BarService.gd")
const KITCHEN_SPOT := Rect2(44.0, 80.0, 44.0, 22.0)
## Suositun baarin lisäasiakkaat (oman baarin suosion mukaan)
const EXTRA_PATRON_SPOTS: Array[Vector2] = [
	Vector2(150.0, 172.0), Vector2(226.0, 124.0), Vector2(244.0, 150.0), Vector2(60.0, 112.0),
	Vector2(206.0, 112.0), Vector2(110.0, 112.0),
]

## -- SÄÄDÄ NÄITÄ --
## Juomalista. alcohol = promillea yhteensä, absorb = sekuntia, joiden aikana promillet
## nousevat (olut nousee hitaasti, shotti melkein heti). sound = Sfx-ääni tarjoillessa.
const DRINKS := [
	{"name": "Olut", "serving": "0,5 l", "price": 3, "alcohol": 0.20, "absorb": 14.0, "sound": "can", "cooldown": 1.2},
	{"name": "Kossu", "serving": "4 cl", "price": 4, "alcohol": 0.30, "absorb": 4.0, "sound": "clink", "cooldown": 0.55},
	{"name": "Shotti", "serving": "2 x 2 cl", "price": 7, "alcohol": 0.45, "absorb": 1.0, "sound": "clink", "cooldown": 0.55},
]
## Vanhat nimet yhteensopivuuden vuoksi (kossu)
## Juomavalikoima-päivitysten tuomat juomat (need = vaadittu taso). vis = lasin kuva kaadettaessa
## (0 tuoppi, 1 lasi, 2 shotti, 3 cocktail, 4 tölkki).
const EXTRA_DRINKS := [
	{"name": "Lonkero", "serving": "0,33 l", "price": 5, "alcohol": 0.24, "absorb": 10.0, "sound": "can", "cooldown": 1.0, "need": 1, "vis": 4},
	{"name": "Siideri", "serving": "0,33 l", "price": 5, "alcohol": 0.2, "absorb": 12.0, "sound": "can", "cooldown": 1.0, "need": 1, "vis": 4},
	{"name": "Viski", "serving": "4 cl", "price": 9, "alcohol": 0.38, "absorb": 3.0, "sound": "clink", "cooldown": 0.7, "need": 2, "vis": 1},
	{"name": "Jaloviina", "serving": "4 cl", "price": 6, "alcohol": 0.34, "absorb": 3.0, "sound": "clink", "cooldown": 0.7, "need": 2, "vis": 1},
	{"name": "Mojito", "serving": "drinkki", "price": 12, "alcohol": 0.3, "absorb": 7.0, "sound": "clink", "cooldown": 1.0, "need": 3, "vis": 3},
	{"name": "Long Island", "serving": "drinkki", "price": 14, "alcohol": 0.6, "absorb": 8.0, "sound": "clink", "cooldown": 1.0, "need": 3, "vis": 3},
]
const SPECIALS_SPOT := Rect2(90.0, 80.0, 30.0, 26.0)
## Laajennus: juhlasali huoneen oikealle puolelle (sarakkeet 22..31). Seinään aukeaa holvikaari.
const ROOM_W_MAX := 32
const ARCH_ROWS := [5, 6, 7, 8, 9, 10]
const HALL_RECT := Rect2(354.0, 70.0, 140.0, 116.0)    # asiakkaiden lattia salissa (lavan edessä)
const STAGE := Rect2(364.0, 34.0, 120.0, 32.0)
## Laajennuksen jälkeen jukeboksi siirtyy juhlasaliin (ei jää holvikaaren eteen kulkuväylälle)
const JUKEBOX_HALL := Rect2(412.0, 166.0, 24.0, 22.0)
const HALL_PATRON_SPOTS: Array[Vector2] = [
	Vector2(392.0, 100.0), Vector2(424.0, 112.0), Vector2(456.0, 98.0), Vector2(404.0, 132.0), Vector2(444.0, 136.0),
	Vector2(372.0, 168.0),
]
const StageScript := preload("res://scripts/world/BarStage.gd")
const TerraceScript := preload("res://scripts/world/BarTerrace.gd")
const SHOT_PRICE := 4
const SHOT_ALCOHOL := 0.30
const SERVE_COOLDOWN := 0.55

## Onko pelaaja sisällä (HUD:n minikartta piiloutuu kun tämä on tosi)
var inside := false
## Oven keskipiste maailmassa (HUD:n minikartta näyttää tämän kohdan)
var door_px := Vector2.ZERO

var _busy := false
var _saved_limits := {}
var _interior: Node2D
var _view: InteriorView
var _fade: ColorRect
var _last_serve_ms := 0
var _serve_gap_ms := 0
## Jukeboksin kappale (-1 = hiljaa)
var _jukebox_tune := 0
## Asetetaan CityGeneratorin _make_bar:ssa ennen setup():ia
var city: Node2D   # CityGenerator
var roof_rect := Rect2()
## Baarin piha terassille (CityGenerator varaa rakennuksen viereen), tyhjä = ei tilaa
var yard_px := Rect2()
var terrace_node: Node2D = null
var _trouble := 0
var _fight_time := 0.0
var _ejecting := false
var _bottle: Node = null
var _cue: Node = null
var _kalle: Sprite2D
var patrons: Array[Node2D] = []
var _brawl_cd := 0.0   # sekuntia seuraavaan haasteeseen
## Oman baarin pyöritys (BarBusiness.gd)
var biz: Node = null
var _ext: ExteriorView = null
var _front: FrontView = null
var _neon: Node2D = null
var _kitchen_spot: Node = null
var _eat_ms := -100000
var _last_boss_warn_ms := -100000
var _flap_shape: CollisionShape2D = null
var _floor_layer: TileMapLayer = null
var _source_id := 0
var _expanded := 0
var _stage_shape: CollisionShape2D = null
var _stage: Node2D = null
var _specials_spot: Node = null
var _stage_floor: Node2D = null
var _jukebox_rect := JUKEBOX
var _jukebox_shape: CollisionShape2D = null
var _jukebox_spot: Node2D = null
var _service: Node2D = null
var _office: Node2D = null
var _office_view: OfficeView = null
## Onko pelaaja toimistohuoneessa (baarin sisällä)
var in_office := false
var _last_shout_ms := -100000
## Rähinöitsijöiden arvonta: jokaisella on tämä todennäköisyys, enintään MAX_ROWDY
const ROWDY_CHANCE := 0.45
const MAX_ROWDY := 2
const SHOUT_GAP := 3.0   # sekuntia kahden huudon välillä (ettei kaikki huuda yhtä aikaa)


## roof = katon suorakulmio pikseleinä, door_center = ovitiilen keskipiste maailmassa.
func setup(tile_set: TileSet, source_id: int, roof: Rect2, door_center: Vector2) -> void:
	add_to_group("bar")
	global_position = Vector2.ZERO  # kaikki piirtokoordinaatit ovat maailmankoordinaatteja
	door_px = door_center
	biz = BusinessScript.new()
	biz.bar = self
	add_child(biz)

	# --- ulkopuoli ---
	var sign_r := Rect2(roof.position.x + 8.0, roof.end.y - 21.0, roof.size.x - 16.0, 17.0)
	var ext := ExteriorView.new()
	ext.roof = roof
	ext.sign_rect = sign_r
	ext.door_center = door_center
	ext.door_front = door_center + Vector2(0.0, TILE)
	ext.bar = self
	ext.z_index = 50
	add_child(ext)
	_ext = ext
	# maan tasolla (hahmojen alla): terassi, liitutaulu, jono, kukkalaatikot
	_front = FrontView.new()
	_front.door_center = door_center
	_front.roof = roof
	_front.bar = self
	add_child(_front)
	# terassi asiakkaineen (Terassi-päivitys)
	var terrace: Node2D = TerraceScript.new()
	terrace.bar = self
	terrace.door_center = door_center
	terrace.yard = yard_px
	add_child(terrace)
	terrace_node = terrace
	# neonkyltti omalla kerroksellaan: yön pimeys (CanvasModulate) ei himmennä sitä
	var neon_layer := CanvasLayer.new()
	neon_layer.layer = 1
	neon_layer.follow_viewport_enabled = true
	add_child(neon_layer)
	_neon = NeonSignScript.new()
	_neon.sign_rect = sign_r
	_neon.roof = roof
	_neon.door_center = door_center
	_neon.bar = self
	neon_layer.add_child(_neon)
	# neonin hehku valaisee ympäristöä pimeällä
	_neon.attach_light(self)

	_add_portal(door_center + Vector2(0.0, 17.0), true, "Paina E mennäksesi sisään (baari, auki 12–04)")

	# --- Kalle baarin kulmalla: pimeät keikat ---
	var kalle_pos := Vector2(roof_rect.end.x + 10.0, door_center.y + 6.0)
	if yard_px.size.x > 0.0 and yard_px.get_center().x > door_center.x and yard_px.position.y > roof_rect.position.y:
		kalle_pos = Vector2(roof_rect.position.x - 10.0, door_center.y + 6.0)   # piha oikealla: Kalle vasemmalle
	if roof_rect.size.x <= 0.0:
		kalle_pos = door_center + Vector2(40.0, 6.0)
	_kalle = Sprite2D.new()
	_kalle.offset = Vector2(0, -4)
	_kalle.z_index = 52
	add_child(_kalle)
	_kalle.global_position = kalle_pos
	InteractSpot.create(self, kalle_pos + Vector2(0, 4), Vector2(26, 26),
		"Paina E jutellaksesi Kallen kanssa (velka, keikat)", _talk_kalle)

	# --- sisätila ---
	_build_interior(tile_set, source_id)

	# --- häivytys ---
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	refresh_business()


func _process(delta: float) -> void:
	_brawl_cd = maxf(_brawl_cd - delta, 0.0)
	if _view and _service:
		var behind: bool = inside and _service.owner_behind()
		if behind != _view.owner_behind:
			_view.owner_behind = behind
	if _kalle and _kalle.texture == null:
		# Kalle: skinhead nahkatakissa, tatuoinnit, röökki aina huulessa
		_kalle.texture = preload("res://scripts/core/CharSprites.gd").kalle(1, 0)
		var smoke := preload("res://scripts/core/SmokeFX.gd").new()
		smoke.sprite = _kalle
		smoke.duration = -1.0
		_kalle.add_child(smoke)
	_kalle_chatter(delta)
	# Turvaverkko: jos pelaaja on siirretty pois sisätilasta (esim. pidätys), palautetaan kamera
	if not inside or _busy:
		return
	# Portsari: liian pitkä tappelu -> ulos. Valomerkki klo 04.
	if active_fighters() > 0:
		_fight_time += delta
		if _fight_time > FIGHT_LIMIT + (6.0 if int(Game.rep.regulars) >= 30 else 0.0):
			eject("Portsari: \"Nyt riittää, painukaa ulos tappelemaan!\"", true)
			return
	else:
		_fight_time = maxf(_fight_time - delta * 0.5, 0.0)
	if not Game.owns_bar and not Game.is_open(OPEN_HOUR, CLOSE_HOUR):
		eject("Valomerkki! Baari sulkeutuu, ulos kaikki.", false)
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and player.global_position.distance_to(INTERIOR_ORIGIN) > 1200.0:
		inside = false
		in_office = false
		_set_camera_limits(false)
		_clear_patrons()
		_music_off()


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

	# Musta tausta huoneen ympärille
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
	_floor_layer = floor_layer
	_source_id = source_id
	for y in ROOM_H:
		for x in ROOM_W:
			var wall := x == 0 or x == ROOM_W - 1 or y <= 1 or y == ROOM_H - 1
			floor_layer.set_cell(Vector2i(x, y), source_id, WALL_TILE if wall else FLOOR_TILE)

	var deco_layer := TileMapLayer.new()
	deco_layer.tile_set = tile_set
	_interior.add_child(deco_layer)
	deco_layer.set_cell(EXIT_CELL, source_id, DOOR_TILE)

	_view = InteriorView.new()
	_view.price = SHOT_PRICE
	_view.menu = DRINKS
	_view.exit_pos = Vector2(EXIT_CELL.x * TILE + TILE * 0.5, EXIT_CELL.y * TILE + TILE * 0.5)
	_view.city = city
	# Juhlasalin lattia, lava ja kalusteet piirretään ennen sisätilan piirtoa, jotta
	# salin puolelle siirtyvät tavarat (jukeboksi, DJ, diskopallo) piirtyvät niiden päälle.
	_stage_floor = StageScript.new()
	_stage_floor.bar = self
	_stage_floor.layer_kind = "floor"
	_interior.add_child(_stage_floor)
	_interior.add_child(_view)
	# Tapahtumat (bändi, karaoke, tietovisa, happy hour) kaiken päällä
	_stage = StageScript.new()
	_stage.bar = self
	_interior.add_child(_stage)
	_stage_shape = _add_block(STAGE)
	_stage_shape.disabled = true

	# Törmäykset: tiski (luukku erikseen), pöydät, jukeboksi. Tiskin takana voi kävellä.
	_add_block(COUNTER_BLOCK)
	_flap_shape = _add_block(FLAP)
	_add_block(TABLE_L)   # pöytä vasemmalla
	_add_block(TABLE_R)   # pöytä oikealla
	_jukebox_shape = _add_block(JUKEBOX)

	# Ovi ulos + tiskin tilauspaikat (yksi kullekin juomalle, vasemmalta oikealle)
	_add_portal(_cell_center(EXIT_CELL) + Vector2(0.0, -17.0), false, "Paina E poistuaksesi")
	var slot_w := SERVE_SPOT.size.x / DRINKS.size()
	for i in DRINKS.size():
		var d: Dictionary = DRINKS[i]
		var center := INTERIOR_ORIGIN + SERVE_SPOT.position + Vector2(slot_w * (i + 0.5), SERVE_SPOT.size.y * 0.5)
		var idx := i
		_add_hotspot(center, Vector2(slot_w, SERVE_SPOT.size.y),
			"Paina E: %s %s (%d $)" % [d.name, d.serving, d.price],
			func(pl: Node2D) -> void: serve(pl, idx))
	# Jukeboksi
	_jukebox_spot = _add_hotspot(INTERIOR_ORIGIN + Vector2(JUKEBOX.position.x - 8.0, JUKEBOX.get_center().y),
		Vector2(18.0, 30.0), "Paina E vaihtaaksesi jukeboksin kappaletta", _use_jukebox)
	_add_block(POOL_TABLE)
	# Pelit ja baarimikko
	_add_hotspot(INTERIOR_ORIGIN + Vector2(POOL_TABLE.position.x - 9.0, POOL_TABLE.get_center().y),
		Vector2(16.0, 30.0), "Paina E pelataksesi biljardia rahasta", func(_pl: Node2D) -> void: _start_game("pool"))
	_add_hotspot(INTERIOR_ORIGIN + Vector2(30.0, 102.0), Vector2(18.0, 22.0),
		"Paina E heittääksesi tikkaa rahasta", func(_pl: Node2D) -> void: _start_game("darts"))
	_add_hotspot(INTERIOR_ORIGIN + Vector2(TABLE_R.get_center().x, TABLE_R.end.y + 10.0), Vector2(26.0, 14.0),
		"Paina E pelataksesi venttiä rahasta", func(_pl: Node2D) -> void: _start_game("cards"))
	_add_hotspot(INTERIOR_ORIGIN + Vector2(266.0, 92.0), Vector2(34.0, 20.0),
		"Paina E jutellaksesi baarimikon kanssa (tehtävät)", _talk_bartender)
	# Toimisto: oman baarin hallinta
	InteractSpot.create(self, INTERIOR_ORIGIN + OFFICE_SPOT, Vector2(22.0, 18.0), _office_prompt, _enter_office)
	# Pomo tiskin takana: asiakkaat ja juoma-asemat
	_service = ServiceScript.new()
	_service.bar = self
	_interior.add_child(_service)
	_build_office(tile_set, source_id)


func _add_block(rect: Rect2, parent: Node2D = null) -> CollisionShape2D:
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	body.add_child(cs)
	(parent if parent else _interior).add_child(body)
	body.position = rect.get_center()
	return cs


# ----------------------------------------------------------------------------
#  TARJOILU
# ----------------------------------------------------------------------------
## Tiskin hotspot kutsuu tätä kun pelaaja painaa E:tä. drink_index = DRINKS-listan rivi.
func serve(player: Node2D, drink_index: int = 1) -> void:
	var di := clampi(drink_index, 0, DRINKS.size() - 1)
	_serve_dict(player, DRINKS[di], di)


## Erikoisjuomat (Juomavalikoima-päivitykset): baarimikko kysyy, mitä saisi olla.
func _specials_menu(_player: Node2D) -> void:
	var opts := []
	var avail := []
	var lvl: int = biz.level("drinks") if biz else 0
	for d: Dictionary in EXTRA_DRINKS:
		if int(d.need) <= lvl:
			opts.append("%s %s (%d $)" % [d.name, d.serving, 0 if Game.owns_bar else int(d.price)])
			avail.append(d)
	if opts.is_empty():
		return
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud and hud.has_method("show_menu"):
		hud.show_menu("BAARIMIKKO – erikoisjuomat", opts, _specials_choice.bind(avail))


func _specials_choice(i: int, avail: Array) -> void:
	if i < 0 or i >= avail.size():
		return
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p:
		var d: Dictionary = avail[i]
		_serve_dict(p, d, int(d.vis))


func _serve_dict(player: Node2D, d: Dictionary, drink_index: int) -> void:
	if _busy or not player.has_method("drink"):
		return
	var now := Time.get_ticks_msec()
	if now - _last_serve_ms < _serve_gap_ms:
		return
	_last_serve_ms = now
	_serve_gap_ms = int(float(d.cooldown) * 1000.0)

	var hud := get_tree().current_scene.get_node_or_null("Hud")
	var price: int = d.price
	if Game.owns_bar:
		price = 0
	elif int(Game.rep.regulars) >= 40:
		price = maxi(price - 1, 1)   # kanta-asiakasalennus
	if player.money < price:
		_view.say("Ilman rahaa ei tipu.", 2.2)
		Sfx.play_ui("denied", -6.0)
		if hud:
			hud.show_message("Ei tarpeeksi rahaa: %d $ / %d $" % [player.money, price], 2.0)
		return

	if price > 0:
		player.add_money(-price)
	Game.add_rep("regulars", 1 if randf() < 0.3 else 0)
	var hung: bool = "hangover" in player and player.hangover > 0.3
	_view.say(_serve_line(player.drunk + player.pending_alcohol(), drink_index, hung), 2.4)
	_view.pour(drink_index)
	Sfx.play(d.sound, INTERIOR_ORIGIN + _view.glass_point())
	# Juoma kumotaan hetken kuluttua, sitten promillet alkavat nousta juoman omaa tahtia
	await get_tree().create_timer(0.55).timeout
	if is_instance_valid(player):
		Sfx.play("gulp", player.global_position, -4.0, 0.1)
		player.drink(float(d.alcohol), float(d.absorb))


## Baarimikon kommentti pelaajan nykyisen humalan ja juoman mukaan.
func _serve_line(level: float, drink_index: int = 1, hungover: bool = false) -> String:
	var lines: Array
	if hungover and level < 0.3:
		lines = ["Tasoittava, vai?", "Näytät kamalalta. Tässä.", "Eilinen kostautuu?"]
	elif level < 0.3:
		match drink_index:
			0:
				lines = ["Kylmä kalja, ole hyvä.", "Tuoppi tulossa.", "Hanasta suoraan."]
			2:
				lines = ["Shotti! Kerralla alas.", "Tää potkii.", "Varovasti näiden kanssa."]
			_:
				lines = ["Ole hyvä, Koskenkorvaa.", "Yksi kossu tulossa.", "Pohjanmaan parasta."]
	elif level < 1.0:
		lines = ["Kippis!", "Eiköhän tästä lähde.", "Tuossa, ota ottaa."]
	elif level < 2.0:
		lines = ["Tuleeko vielä yksi?", "Ei tässä oo kiire minnekään.", "Sä oot hyvässä vauhdissa."]
	elif level < 3.0:
		lines = ["Oot varma että tää on viisasta?", "No, sun rahoilla.", "Pidä kiinni tiskistä."]
	else:
		lines = ["Sulle taitaa riittää jo...", "Mä en kyllä ottais enää.", "Kohta lattia kutsuu."]
	return lines[randi() % lines.size()]


## Pelaaja on sammunut: herätetään hänet baarin oven eteen (kutsuu Player2D).
func wake_up_player(player: Node2D) -> void:
	inside = false
	in_office = false
	_set_camera_limits(false)
	_clear_patrons()
	_music_off()
	_move_player(player, door_px + Vector2(0.0, 28.0))


# ----------------------------------------------------------------------------
#  ASIAKKAAT JA TAPPELU
# ----------------------------------------------------------------------------
## Uudet asiakkaat joka kerta kun pelaaja astuu sisään.
func _spawn_patrons() -> void:
	_clear_patrons()
	if city == null:
		return
	_brawl_cd = 6.0
	var rowdy_count := 0
	# Huono maine kanta-asiakkaiden keskuudessa = enemmän rähinöitsijöitä
	var chance := ROWDY_CHANCE + (0.2 if int(Game.rep.regulars) <= -20 else 0.0) - (0.15 if int(Game.rep.regulars) >= 30 else 0.0)
	var spots: Array[Vector2] = []
	spots.append_array(PATRON_SPOTS)
	if Game.owns_bar and biz:
		# Oma baari: ovimies ja henkilökunta pitävät rähinöitsijät kurissa, suosio tuo väkeä
		chance -= 0.08 * biz.level("staff") + 0.1 * biz.level("security")   # Turvallisuus-päivitys: vähemmän rähinää
		var extra := int(biz.popularity() / 100.0 * EXTRA_PATRON_SPOTS.size() + 0.5)
		if biz.event_id() != "":
			extra += 1
		for i in mini(extra, EXTRA_PATRON_SPOTS.size()):
			spots.append(EXTRA_PATRON_SPOTS[i])
		if _expanded >= 1:
			# juhlasali täyttyy suosion ja tapahtumien mukaan
			var hall_n := int(biz.popularity() / 100.0 * 4.0 + 0.5) + (2 if biz.event_id() != "" else 0)
			for i in mini(hall_n, HALL_PATRON_SPOTS.size()):
				spots.append(HALL_PATRON_SPOTS[i])
	var grudge := Game.random_grudge() if randf() < 0.6 and not Game.owns_bar else {}
	if Game.owns_bar:
		chance = 0.0   # omassa baarissa kukaan ei haasta pomoa
	for spot in spots:
		var p = PatronScript.new()
		if not grudge.is_empty():
			p.grudge = grudge
			grudge = {}
			rowdy_count += 1
		elif rowdy_count < MAX_ROWDY and randf() < chance:
			p.rowdy = true
			rowdy_count += 1
		p.bar = self
		p.city = city
		p.base_row = int(p.grudge.row) if not p.grudge.is_empty() else (randi() % NPC_TYPES) * 3
		p.position = spot
		_interior.add_child(p)
		patrons.append(p)


func _clear_patrons() -> void:
	for p in patrons:
		if is_instance_valid(p):
			p.queue_free()
	patrons.clear()


## Voiko asiakas liikkua tähän pisteeseen (huoneen paikalliset koordinaatit)?
func is_free(p: Vector2) -> bool:
	if not FLOOR_RECT.has_point(p) and not (_expanded >= 1 and HALL_RECT.has_point(p)):
		return false
	for r in SOLIDS:
		var rr: Rect2 = _jukebox_rect if r == JUKEBOX else r
		if rr.grow(5.0).has_point(p):
			return false
	return true


func active_fighters() -> int:
	var n := 0
	for p in patrons:
		if is_instance_valid(p) and p.is_fighting():
			n += 1
	return n


## Haastaja saa aloittaa vain kun kukaan ei jo tappele ja edellisestä on hetki.
func can_challenge() -> bool:
	return inside and _brawl_cd <= 0.0 and active_fighters() == 0


## Tappelu alkoi: osa muista asiakkaista liittyy mukaan hetken päästä.
func brawl_alarm(starter: Node2D) -> void:
	for p in patrons:
		if is_instance_valid(p) and p != starter and p.can_join() and randf() < 0.4:
			p.join_fight()


func can_shout() -> bool:
	return Time.get_ticks_msec() - _last_shout_ms > int(SHOUT_GAP * 1000.0)


func note_shout() -> void:
	_last_shout_ms = Time.get_ticks_msec()


func fight_ended() -> void:
	if active_fighters() == 0:
		_brawl_cd = 14.0


# ----------------------------------------------------------------------------
#  PORTSARI JA TUTUT KASVOT
# ----------------------------------------------------------------------------
## Pelaaja kaatoi asiakkaan. Rähinöitsijä muistaa tämän (tutut kasvot).
func note_knockdown(p: Node2D) -> void:
	_trouble += 1
	if biz:
		biz.note_fight()
	Game.add_rep("regulars", -1)
	if p.get("rowdy"):
		var g := Game.add_grudge(int(p.base_row))
		var gname := str(g.get("name", ""))
		if int(g.get("beaten", 1)) >= 3:
			Game.remove_grudge(g)
			p.say("%s: Okei, sä voitit... en kiusaa enää." % gname, 2.5)
		elif not p.get("grudge").is_empty():
			p.say("%s: Tää ei jää tähän!" % gname, 2.2)
		else:
			p.grudge = g
			p.say("Mä muistan sun naaman, %s ei unohda!" % gname, 2.4)
	if _trouble >= TROUBLE_LIMIT + (1 if int(Game.rep.regulars) >= 30 else 0):
		eject("Portsari: \"Kolmas kaatunut. Sä lähdet nyt!\"", true)


func note_unprovoked() -> void:
	_trouble += 2
	Game.add_rep("regulars", -4)
	hud_message("Portsari näki, että löit rauhallista asiakasta!", 2.0)
	if _trouble >= TROUBLE_LIMIT:
		eject("Portsari: \"Rauhallisia asiakkaita ei hakata. Ulos!\"", true)


func note_weapon_violence() -> void:
	Game.add_rep("regulars", -8)
	if biz:
		biz.note_fight()
		biz.note_fight()
	eject("Portsari: \"Aseet ulos täältä! Ja sinä myös!\"", true)


## Portsari heittää pelaajan ulos. strike = merkintä kieltolistaa varten.
func eject(text: String, strike: bool) -> void:
	if _ejecting or not inside:
		return
	if Game.owns_bar:
		# Omistajaa ei heitetä ulos omasta baarista
		if strike and Time.get_ticks_msec() - _last_boss_warn_ms > 8000:
			_last_boss_warn_ms = Time.get_ticks_msec()
			hud_message("Portsari: \"Pomo, ehkä vähän rauhallisemmin? Asiakkaat säikkyy.\"", 2.5)
		_trouble = 0
		_fight_time = 0.0
		return
	_ejecting = true
	var player := get_tree().get_first_node_in_group("player") as Node2D
	hud_message(text, 2.5)
	await get_tree().create_timer(0.8).timeout
	if player and inside:
		_busy = true
		player.set_physics_process(false)
		await _fade_to(1.0)
		inside = false
		in_office = false
		_set_camera_limits(false)
		_clear_patrons()
		_music_off()
		_move_player(player, door_px + Vector2(0.0, 28.0))
		await _fade_to(0.0)
		player.set_physics_process(true)
		_busy = false
		if strike:
			if Game.bar_strike():
				hud_message("Pääsit portsarin kieltolistalle! Baari on sinulta kiinni %d min." % Game.bar_ban_minutes_left(), 3.5)
			else:
				hud_message("Portsari heitti sinut ulos. Seuraavasta kerrasta tulee kielto.", 3.0)
	_ejecting = false


func _start_game(game: String) -> void:
	if active_fighters() > 0:
		hud_message("Ei nyt, kesken tappelun!", 1.5)
		return
	var bg := get_tree().get_first_node_in_group("bar_games")
	if bg and bg.has_method("start"):
		bg.start(game)


func _talk_bartender(_player: Node2D) -> void:
	var story := get_tree().get_first_node_in_group("story")
	if story and story.has_method("bartender_menu"):
		story.bartender_menu()
		return
	var jm := get_tree().get_first_node_in_group("job_manager")
	if jm and jm.has_method("bartender_menu"):
		jm.bartender_menu()


## Kalle heittää stadin slangia, kun pelaaja kulkee ohi.
const KALLE_LINES := ["Moro jäbä.", "Mitä jengi?", "Onks sul hommii, vai mitä sä tuijotat?",
	"Kytät pyöri täs äsken. Snadisti hiljaa.", "Tuu juttelee, mul ois duunii.", "Massii saa, jos uskaltaa.",
	"Kliffa ilta, eiks je?", "Älä hengaa täs turhaa.", "Faija sano aina: älä luota kyttiin."]
var _kalle_say_t := 4.0
var _kalle_label: Label = null

func _kalle_chatter(delta: float) -> void:
	if _kalle == null or inside:
		return
	_kalle_say_t -= delta
	if _kalle_say_t > 0.0:
		return
	_kalle_say_t = randf_range(9.0, 16.0)
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p == null or not p.visible or p.global_position.distance_to(_kalle.global_position) > 90.0:
		return
	if is_instance_valid(_kalle_label):
		_kalle_label.queue_free()
	var l := Label.new()
	l.text = KALLE_LINES[randi() % KALLE_LINES.size()]
	l.position = Vector2(-80.0, -34.0)
	l.size = Vector2(160.0, 12.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	_kalle.add_child(l)
	_kalle_label = l
	var tw := l.create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


func _talk_kalle(_player: Node2D) -> void:
	var story := get_tree().get_first_node_in_group("story")
	if story and story.has_method("kalle_menu"):
		story.kalle_menu(self)
		return
	var jm := get_tree().get_first_node_in_group("job_manager")
	if jm and jm.has_method("kalle_menu"):
		jm.kalle_menu(self)


## Takapihan kohta (ryöstökeikka): baarin takana, katon yläpuolella.
func back_alley_point() -> Vector2:
	if roof_rect.size.x > 0.0:
		return Vector2(roof_rect.get_center().x, roof_rect.position.y - 10.0)
	return door_px + Vector2(0.0, -80.0)


## Pullo ja biljardikeppi odottavat paikoillaan aina kun tulet sisään.
func _respawn_props() -> void:
	if not is_instance_valid(_bottle) and Game.fixture_should_spawn("bar_bottle"):
		_bottle = WEAPON_PICKUP_SCENE.instantiate()
		_bottle.weapon_id = "bottle"
		_bottle.fixture = "bar_bottle"
		_interior.add_child(_bottle)
		_bottle.global_position = INTERIOR_ORIGIN + Vector2(TABLE_L.get_center().x, TABLE_L.end.y + 8.0)
	if not is_instance_valid(_cue) and Game.fixture_should_spawn("bar_cue"):
		_cue = WEAPON_PICKUP_SCENE.instantiate()
		_cue.weapon_id = "cue"
		_cue.fixture = "bar_cue"
		_interior.add_child(_cue)
		_cue.global_position = INTERIOR_ORIGIN + Vector2(POOL_TABLE.end.x + 10.0, POOL_TABLE.position.y + 4.0)


func hud_message(text: String, seconds: float) -> void:
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(text, seconds)


# ----------------------------------------------------------------------------
#  OMA BAARI: TOIMISTO, KEITTIÖ, ULKOASU
# ----------------------------------------------------------------------------
func _office_prompt() -> String:
	if Game.owns_bar:
		return "Paina E mennäksesi toimistoon"
	return "TOIMISTO – vain henkilökunnalle"


# ----------------------------------------------------------------------------
#  TOIMISTOHUONE
# ----------------------------------------------------------------------------
func _office_cell(c: Vector2i) -> Vector2:
	return INTERIOR_ORIGIN + OFFICE_ORIGIN + Vector2(c.x * TILE + TILE * 0.5, c.y * TILE + TILE * 0.5)


func _build_office(tile_set: TileSet, source_id: int) -> void:
	_office = Node2D.new()
	_office.name = "Office"
	_office.position = OFFICE_ORIGIN
	_interior.add_child(_office)
	var floor_layer := TileMapLayer.new()
	floor_layer.tile_set = tile_set
	_office.add_child(floor_layer)
	for y in OFFICE_H:
		for x in OFFICE_W:
			var wall := x == 0 or x == OFFICE_W - 1 or y <= 1 or y == OFFICE_H - 1
			floor_layer.set_cell(Vector2i(x, y), source_id, WALL_TILE if wall else FLOOR_TILE)
	var deco := TileMapLayer.new()
	deco.tile_set = tile_set
	_office.add_child(deco)
	deco.set_cell(OFFICE_EXIT_CELL, source_id, DOOR_TILE)
	_office_view = OfficeView.new()
	_office_view.bar = self
	_office.add_child(_office_view)
	for r: Rect2 in [OFFICE_DESK, OFFICE_SAFE, OFFICE_SOFA, OFFICE_PLANT]:
		_add_block(r, _office)
	var o := INTERIOR_ORIGIN + OFFICE_ORIGIN
	InteractSpot.create(self, o + Vector2(OFFICE_DESK.get_center().x, OFFICE_DESK.end.y + 9.0), Vector2(30.0, 14.0),
		"Paina E: käynnistä tietokone (BaariOS)", func(_pl: Node2D) -> void: biz.open_computer(""))
	InteractSpot.create(self, o + Vector2(40.0, 44.0), Vector2(30.0, 18.0),
		"Paina E: henkilökuntataulu (palkkaa / irtisano)", func(_pl: Node2D) -> void: biz.open_computer("staff"))
	InteractSpot.create(self, o + Vector2(OFFICE_SAFE.get_center().x, OFFICE_SAFE.end.y + 9.0), Vector2(24.0, 14.0),
		"Paina E: kassakaappi (kirjanpito)", func(_pl: Node2D) -> void: biz.open_computer("books"))
	InteractSpot.create(self, _office_cell(OFFICE_EXIT_CELL) + Vector2(0.0, -17.0), Vector2(24.0, 22.0),
		"Paina E palataksesi baariin", _leave_office)


func _enter_office(player: Node2D) -> void:
	if not Game.owns_bar:
		Sfx.play_ui("denied", -6.0)
		hud_message("Toimiston ovi on lukossa. \"Vain henkilökunnalle.\"", 2.0)
		return
	_office_move(player, true)


func _leave_office(player: Node2D) -> void:
	_office_move(player, false)


func _office_move(player: Node2D, enter: bool) -> void:
	if _busy:
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
	in_office = enter
	_set_camera_limits(false)
	if enter:
		_set_camera_limits(true, Rect2(INTERIOR_ORIGIN + OFFICE_ORIGIN, Vector2(OFFICE_W, OFFICE_H) * TILE))
		_move_player(player, INTERIOR_ORIGIN + OFFICE_ORIGIN + OFFICE_SPAWN)
	else:
		_set_camera_limits(true)
		_move_player(player, INTERIOR_ORIGIN + OFFICE_SPOT + Vector2(0.0, -4.0))
	await _fade_to(0.0)
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	_busy = false
	if enter:
		hud_message("Toimisto. Tietokone: hallinta · Taulu: henkilökunta · Kassakaappi: kirjanpito", 3.0)


## Päivitykset, nimi ja tapahtuma näkyviin sisällä ja ulkona (BarBusiness kutsuu).
func refresh_business() -> void:
	if biz == null:
		return
	var owned := Game.owns_bar
	if _view:
		_view.owned = owned
		_view.up = biz.levels() if owned else {}
		_view.bar_title = Game.bar_name()
		_view.event = biz.event_id() if owned else ""
		_view.events = biz.events_active() if owned else []
		_view.look = biz.looks() if owned else {"floor": "wood", "wall": "brick", "counter": "wood", "neon": "pink"}
	_apply_expansion(biz.level("space") if owned else 0)
	if _stage:
		_stage.queue_redraw()
	# Erikoisjuomat tiskillä (Juomavalikoima 1+)
	var want_specials: bool = biz.level("drinks") >= 1 and owned
	if want_specials and not is_instance_valid(_specials_spot):
		_specials_spot = InteractSpot.create(self, INTERIOR_ORIGIN + SPECIALS_SPOT.get_center(), SPECIALS_SPOT.size,
			"Paina E: erikoisjuomat (lonkero, viski, cocktailit...)", _specials_menu)
	elif not want_specials and is_instance_valid(_specials_spot):
		_specials_spot.queue_free()
		_specials_spot = null
	# Bändi- ja karaokeilta: musiikki soi aina
	if inside and owned and (biz.has_event("band") or biz.has_event("karaoke")) and _jukebox_tune < 0:
		_jukebox_tune = 0
		_music_on()
	# Tiskiluukku aukeaa omistajalle
	if _flap_shape:
		_flap_shape.set_deferred("disabled", owned)
	# Keittiön luukku vain, kun keittiö on päivitetty
	var want_kitchen: bool = owned and biz.level("kitchen") >= 1
	if want_kitchen and not is_instance_valid(_kitchen_spot):
		_kitchen_spot = InteractSpot.create(self, INTERIOR_ORIGIN + KITCHEN_SPOT.get_center(), KITCHEN_SPOT.size,
			_kitchen_prompt, _eat)
	elif not want_kitchen and is_instance_valid(_kitchen_spot):
		_kitchen_spot.queue_free()
		_kitchen_spot = null


## Laajennus: holvikaari seinään ja juhlasali oikealle (tiilet + lavan törmäys).
func _apply_expansion(lvl: int) -> void:
	if _floor_layer == null or lvl == _expanded:
		return
	_expanded = lvl
	if lvl >= 1:
		for y in ROOM_H:
			for x in range(ROOM_W - 1, ROOM_W_MAX):
				var c := Vector2i(x, y)
				var wall := x == ROOM_W_MAX - 1 or y <= 1 or y == ROOM_H - 1
				if x == ROOM_W - 1:
					wall = not (y in ARCH_ROWS) or y <= 1 or y == ROOM_H - 1
				_floor_layer.set_cell(c, _source_id, WALL_TILE if wall else FLOOR_TILE)
	else:
		for y in ROOM_H:
			_floor_layer.set_cell(Vector2i(ROOM_W - 1, y), _source_id, WALL_TILE)
			for x in range(ROOM_W, ROOM_W_MAX):
				_floor_layer.erase_cell(Vector2i(x, y))
	if _stage_shape:
		_stage_shape.set_deferred("disabled", lvl < 1)
	# Jukeboksi juhlasaliin (törmäys + E-kohde mukana)
	_jukebox_rect = JUKEBOX_HALL if lvl >= 1 else JUKEBOX
	if _jukebox_shape and _jukebox_shape.get_parent():
		var jb_body := _jukebox_shape.get_parent() as Node2D
		jb_body.position = _jukebox_rect.get_center()
	if is_instance_valid(_jukebox_spot):
		_jukebox_spot.global_position = INTERIOR_ORIGIN + Vector2(_jukebox_rect.position.x - 8.0, _jukebox_rect.get_center().y)
	if _stage_floor:
		_stage_floor.queue_redraw()
	if _view:
		_view.expanded = lvl
		_view.jukebox_rect = _jukebox_rect
	if inside and not in_office:
		_set_camera_limits(false)
		_set_camera_limits(true)


func _kitchen_prompt() -> String:
	if biz.level("kitchen") >= 2:
		return "Paina E: pizza keittiöstä (talon piikkiin, nälkä -70)"
	return "Paina E: makkaraperunat keittiöstä (talon piikkiin, nälkä -45)"


func _eat(_player: Node2D) -> void:
	var now := Time.get_ticks_msec()
	if now - _eat_ms < 4000:
		return
	_eat_ms = now
	if Game.hunger < 5.0:
		hud_message("Kokki: \"Et sä oo nälkäinen, pomo.\"", 2.0)
		return
	var big: bool = biz.level("kitchen") >= 2
	Game.hunger = maxf(Game.hunger - (70.0 if big else 45.0), 0.0)
	Sfx.play("gulp", INTERIOR_ORIGIN + KITCHEN_SPOT.get_center(), -4.0, 0.1, 0.8)
	hud_message("Kokki: \"%s\"" % ("Pizza uunista, ole hyvä!" if big else "Makkaraperunat, sinappia päälle!"), 2.2)


# ----------------------------------------------------------------------------
#  OVET
# ----------------------------------------------------------------------------
func _add_portal(center: Vector2, to_inside: bool, prompt: String) -> void:
	_add_hotspot(center, Vector2(24.0, 22.0), prompt,
		func(player: Node2D) -> void: use_portal(player, to_inside))


func _add_hotspot(center: Vector2, size_px: Vector2, prompt: String, action: Callable) -> Node2D:
	var h := Hotspot.new()
	h.prompt = prompt
	h.action = action
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size_px
	cs.shape = shape
	h.add_child(cs)
	add_child(h)
	h.global_position = center
	return h


func use_portal(player: Node2D, to_inside: bool) -> void:
	if _busy:
		return
	if to_inside:
		if Game.bar_banned() and not Game.owns_bar:
			Sfx.play_ui("denied", -4.0)
			hud_message("Portsari: \"Sä oot kieltolistalla. Tuu takas %d min päästä.\"" % Game.bar_ban_minutes_left(), 2.5)
			return
		if not Game.owns_bar and not Game.is_open(OPEN_HOUR, CLOSE_HOUR):
			Sfx.play_ui("denied", -6.0)
			hud_message("Baari on kiinni. Auki %02d–%02d." % [OPEN_HOUR, CLOSE_HOUR], 2.0)
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
		refresh_business()
		_set_camera_limits(true)
		_move_player(player, _cell_center(SPAWN_CELL))
		_spawn_patrons()
		_respawn_props()
		_trouble = 0
		_fight_time = 0.0
		_music_on()
		refresh_business()
	else:
		inside = false
		in_office = false
		_set_camera_limits(false)
		_clear_patrons()
		_music_off()
		_move_player(player, door_px + Vector2(0.0, 28.0))
	await _fade_to(0.0)

	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	_busy = false


func _fade_to(alpha: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, 0.18)
	await tw.finished


# ----------------------------------------------------------------------------
#  JUKEBOKSI
# ----------------------------------------------------------------------------
func _music_on() -> void:
	_view.music_on = _jukebox_tune >= 0
	if _jukebox_tune >= 0:
		Sfx.play_music(_jukebox_tune, INTERIOR_ORIGIN + _jukebox_rect.get_center())


func _music_off() -> void:
	_view.music_on = false
	Sfx.stop_music()


## E jukeboksin edessä: seuraava kappale, viimeisen jälkeen hiljaisuus.
func _use_jukebox(_player: Node2D) -> void:
	_jukebox_tune += 1
	if _jukebox_tune >= Sfx.tune_count():
		_jukebox_tune = -1
	Sfx.play("coin", INTERIOR_ORIGIN + _jukebox_rect.get_center(), -8.0, 0.0, 0.8)
	if _jukebox_tune < 0:
		_music_off()
		hud_message("Jukeboksi hiljeni.", 1.8)
	else:
		_music_on()
		hud_message("Jukeboksi: %s" % Sfx.tune_name(_jukebox_tune), 2.2)


## Siirtää pelaajan niin, että hänen törmäysmuotonsa keskipiste on kohdassa target.
func _move_player(player: Node2D, target: Vector2) -> void:
	var col := player.get_node_or_null("CollisionShape2D") as Node2D
	var off := col.position if col else Vector2.ZERO
	player.global_position = target - off
	var cam := _camera()
	if cam:
		cam.global_position = target


func _camera() -> Camera2D:
	return get_viewport().get_camera_2d()


func _set_camera_limits(in_room: bool, room: Rect2 = Rect2()) -> void:
	var cam := _camera()
	if cam == null:
		return
	if in_room:
		if _saved_limits.is_empty():
			_saved_limits = {
				"l": cam.limit_left, "t": cam.limit_top,
				"r": cam.limit_right, "b": cam.limit_bottom,
			}
		var base := room if room.size != Vector2.ZERO else Rect2(INTERIOR_ORIGIN, Vector2(ROOM_W_MAX if _expanded >= 1 else ROOM_W, ROOM_H) * TILE)
		var r := base.grow(260.0)
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
## Alue, jossa E tekee jotain (ovi tai tiskin tilaus). Näyttää kehotteen ja
## ilmoittautuu pelaajan nearby_portal-kohteeksi, jolloin E kutsuu use():a.
class Hotspot extends Area2D:
	var prompt := ""
	var action: Callable

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
			# Vierekkäiset tilauspaikat: siirrytään suoraan naapuriin, jos pelaaja on sen päällä
			for n in get_parent().get_children():
				if n != self and n is Area2D and n.has_method("use") and n.overlaps_body(body):
					body.nearby_portal = n
					if hud:
						hud.show_instruction(str(n.get("prompt")))
					return
			if hud:
				hud.hide_instruction()

	func use(player: Node2D) -> void:
		action.call(player)


## Rakennuksen päälle piirretty ulkoasu: katto, Koskenkorva-pullo, kyltin runko, markiisi,
## seinälamput ja valonauhan johto. Hehkuvat osat (neonnimi, lamput) piirtää BarNeon.gd.
class ExteriorView extends Node2D:
	const TILE := 16
	const BRICK := Color(0.55, 0.25, 0.18)
	const NEON := Color(1.0, 0.25, 0.7)
	const NAVY := Color(0.09, 0.12, 0.27)
	const KK_BLUE := Color(0.13, 0.4, 0.85)
	const BRASS := Color(0.85, 0.68, 0.3)
	var roof := Rect2()
	var sign_rect := Rect2()
	var door_center := Vector2.ZERO
	var door_front := Vector2.ZERO
	var bar: Node = null
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

	func _level(id: String) -> int:
		if not Game.owns_bar or bar == null or bar.get("biz") == null:
			return 0
		return int(bar.biz.level(id))

	## Katolla saunan piippu savuineen ja palju höyryineen; kyltin yläpuolella
	## valvontakamerat ja vilkkuva PELIT-valo, kun päivitykset on ostettu.
	func _draw_roof_upgrades() -> void:
		var top_y := roof.end.y - 21.0   # kyltin yläreuna
		var sauna := _level("sauna")
		if sauna >= 1:
			var ch := Rect2(roof.position.x + 30.0, roof.position.y + 5.0, 7.0, 10.0)
			draw_rect(ch.grow(1.0), Color(0, 0, 0, 0.4))
			draw_rect(ch, BRICK)
			draw_line(Vector2(ch.position.x, ch.position.y + 4.0), Vector2(ch.end.x, ch.position.y + 4.0), Color(0.35, 0.15, 0.1), 1.0)
			draw_rect(Rect2(ch.position.x - 1.0, ch.position.y - 1.0, ch.size.x + 2.0, 2.0), Color(0.3, 0.3, 0.32))
			for k in 4:
				var ph := fmod(_t * 0.6 + k * 0.25, 1.0)
				var sp := Vector2(ch.get_center().x + sin(_t * 1.3 + k) * 2.0 + ph * 6.0, ch.position.y - 2.0 - ph * 16.0)
				draw_circle(sp, 1.5 + ph * 3.0, Color(0.85, 0.85, 0.88, 0.45 * (1.0 - ph)))
		if sauna >= 2:
			var tc := Vector2(roof.end.x - 32.0, roof.position.y + 22.0)
			draw_circle(tc + Vector2(1, 2), 11.0, Color(0, 0, 0, 0.35))
			draw_circle(tc, 11.0, Color(0.45, 0.28, 0.14))
			draw_circle(tc, 9.0, Color(0.2, 0.55, 0.75))
			draw_circle(tc + Vector2(-2, -2), 4.0, Color(0.5, 0.8, 0.95, 0.5))
			for k in 8:
				var a := k * TAU / 8.0
				draw_line(tc + Vector2.from_angle(a) * 9.0, tc + Vector2.from_angle(a) * 11.0, Color(0.3, 0.17, 0.08), 1.0)
			for k in 3:   # kylpijöiden päät
				draw_circle(tc + Vector2.from_angle(k * 2.1 + 0.4) * 5.0, 1.8, Color(0.92, 0.72, 0.56))
			for k in 3:
				var ph2 := fmod(_t * 0.5 + k * 0.33, 1.0)
				draw_circle(tc + Vector2(-5.0 + k * 5.0, -4.0 - ph2 * 12.0), 2.0 + ph2 * 2.5, Color(0.95, 0.95, 1.0, 0.3 * (1.0 - ph2)))
		if _level("security") >= 1:
			for sx: float in [-24.0, 24.0]:
				var cp := Vector2(door_center.x + sx, top_y - 4.0)
				draw_rect(Rect2(cp + Vector2(-3.0, -2.0), Vector2(6.0, 4.0)), Color(0.85, 0.86, 0.9))
				draw_rect(Rect2(cp + Vector2(-1.0, 2.0), Vector2(2.0, 2.0)), Color(0.15, 0.15, 0.18))
				var led := Color(1.0, 0.1, 0.1) if int(_t * 2.0) % 2 == 0 else Color(0.4, 0.05, 0.05)
				draw_circle(cp + Vector2(2.0, -1.0), 0.7, led)
		if _level("slots") >= 1:
			var lp := Vector2(roof.position.x + 16.0, top_y - 6.0)
			var on := int(_t * 3.0) % 2 == 0
			draw_rect(Rect2(lp + Vector2(-10.0, -4.0), Vector2(20.0, 7.0)), Color(0.08, 0.06, 0.1))
			TextFit.draw(self, ThemeDB.fallback_font, lp + Vector2(-10.0, 1.5), "PELIT", 20.0, 5, Color(1.0, 0.85, 0.2) if on else Color(1.0, 0.3, 0.6))

	func _draw() -> void:
		# Tummansininen katto + saumat
		draw_rect(roof, NAVY)
		var x := roof.position.x + TILE
		while x < roof.end.x:
			draw_line(Vector2(x, roof.position.y), Vector2(x, roof.end.y), Color(1, 1, 1, 0.05), 1.0)
			x += TILE
		var y := roof.position.y + TILE
		while y < roof.end.y:
			draw_line(Vector2(roof.position.x, y), Vector2(roof.end.x, y), Color(1, 1, 1, 0.05), 1.0)
			y += TILE
		_stripe_border(roof, 4.0)
		# Ilmastointikone ja antenni katolla
		var ac := Rect2(roof.position.x + 8.0, roof.position.y + 7.0, 14.0, 10.0)
		draw_rect(ac.grow(1.0), Color(0, 0, 0, 0.4))
		draw_rect(ac, Color(0.62, 0.64, 0.68))
		draw_circle(ac.get_center(), 3.5, Color(0.35, 0.36, 0.4))
		draw_line(ac.get_center() - Vector2(3, 0).rotated(_t * 9.0), ac.get_center() + Vector2(3, 0).rotated(_t * 9.0), Color(0.75, 0.77, 0.8), 1.0)
		var ant := Vector2(roof.end.x - 12.0, roof.position.y + 14.0)
		draw_line(ant, ant + Vector2(0, -10), Color(0.5, 0.5, 0.55), 1.0)
		draw_line(ant + Vector2(-4, -7), ant + Vector2(4, -7), Color(0.5, 0.5, 0.55), 1.0)
		draw_circle(ant + Vector2(0, -10), 1.2, Color(1.0, 0.2, 0.2, 0.6 + 0.4 * float(int(_t * 1.5) % 2)))

		# Koskenkorva-pullo katolla
		_bottle(roof.get_center() + Vector2(0.0, -9.0))
		# Oman baarin päivitykset näkyvät ulos: sauna, palju, kamerat, pelikoneet
		_draw_roof_upgrades()

		# Kyltin runko: tumma laatikko, kiinnikkeet ja kaapeli (neonputket BarNeon.gd)
		var lvl := _level("sign")
		var sr := sign_rect.grow(1.0 if lvl >= 3 else 0.0)
		draw_rect(Rect2(sr.position + Vector2(1, 2), sr.size), Color(0, 0, 0, 0.45))
		draw_rect(sr, Color(0.035, 0.03, 0.07))
		draw_rect(sr, Color(0.25, 0.25, 0.3), false, 1.0)
		for bx: float in [sr.position.x + 6.0, sr.end.x - 6.0]:
			draw_rect(Rect2(bx - 1.0, sr.end.y, 2.0, 3.0), Color(0.4, 0.4, 0.45))
		draw_line(Vector2(sr.end.x - 3.0, sr.end.y), Vector2(sr.end.x - 1.0, sr.end.y + 8.0), Color(0.1, 0.1, 0.1), 1.0)

		# Valonauhan johto (lamput hohtavat BarNeon.gd:ssä)
		var y0 := roof.end.y + 2.0
		var fx := roof.position.x + 3.0
		while fx < roof.end.x - 3.0:
			var x1 := minf(fx + 24.0, roof.end.x - 3.0)
			var prev := Vector2(fx, y0)
			for k in 7:
				var tt := float(k + 1) / 7.0
				var pt := Vector2(lerpf(fx, x1, tt), y0 + sin(tt * PI) * 4.0)
				draw_line(prev, pt, Color(0.08, 0.08, 0.08, 0.9), 1.0)
				prev = pt
			draw_circle(Vector2(fx, y0), 0.8, Color(0.2, 0.2, 0.2))
			fx = x1

		# Markiisi oven yläpuolella: sini-valkoiset raidat ja aaltoileva reuna
		var aw := Rect2(door_center.x - 15.0, door_center.y - 14.0, 30.0, 6.0)
		draw_rect(Rect2(aw.position + Vector2(0, 2), aw.size), Color(0, 0, 0, 0.3))
		var stripe := 0
		var sx := aw.position.x
		while sx < aw.end.x:
			var col := KK_BLUE if stripe % 2 == 0 else Color(0.95, 0.95, 0.98)
			draw_rect(Rect2(sx, aw.position.y, minf(3.0, aw.end.x - sx), aw.size.y), col)
			draw_circle(Vector2(sx + 1.5, aw.end.y), 1.5, col)
			sx += 3.0
			stripe += 1
		draw_line(aw.position, Vector2(aw.end.x, aw.position.y), Color(0.05, 0.08, 0.2), 1.0)

		# Messinkiset seinälamput oven molemmin puolin
		for lx: float in [-19.0, 19.0]:
			var lp := door_center + Vector2(lx, -6.0)
			draw_rect(Rect2(lp + Vector2(-1.5, -3.0), Vector2(3, 5)), BRASS)
			draw_rect(Rect2(lp + Vector2(-1.0, -2.0), Vector2(2, 3)), Color(1.0, 0.92, 0.7))

		# Pulssaava merkki oven edessä
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		var rad := 9.0 + 2.0 * pulse
		draw_circle(door_front, rad, Color(NEON.r, NEON.g, NEON.b, 0.12 + 0.15 * pulse))
		draw_arc(door_front, rad, 0.0, TAU, 24, Color(NEON.r, NEON.g, NEON.b, 0.9), 1.0)
		# Pomppiva nuoli oveen päin
		var bob := absf(sin(_t * 3.0)) * 3.0
		var tip := door_front + Vector2(0.0, 24.0 - bob)
		draw_colored_polygon(PackedVector2Array([
			tip + Vector2(0.0, -8.0), tip + Vector2(-5.0, 0.0), tip + Vector2(5.0, 0.0)]), NEON)


	## Koskenkorva-pullo ylhäältä päin: kirkas runko, sininen korkki ja valkoinen etiketti.
	func _bottle(c: Vector2) -> void:
		var glass := Color(0.85, 0.93, 1.0)
		draw_rect(Rect2(c.x - 8.0, c.y - 5.0, 16.0, 22.0), Color(0, 0, 0, 0.55))   # varjo/ääriviiva
		draw_rect(Rect2(c.x - 7.0, c.y - 4.0, 14.0, 20.0), glass)
		draw_colored_polygon(PackedVector2Array([
			Vector2(c.x - 7.0, c.y - 4.0), Vector2(c.x + 7.0, c.y - 4.0),
			Vector2(c.x + 2.5, c.y - 10.0), Vector2(c.x - 2.5, c.y - 10.0)]), glass)
		draw_rect(Rect2(c.x - 2.5, c.y - 18.0, 5.0, 8.0), glass)
		draw_rect(Rect2(c.x - 3.0, c.y - 21.0, 6.0, 4.0), KK_BLUE)
		draw_rect(Rect2(c.x - 7.0, c.y + 1.0, 14.0, 11.0), Color.WHITE)
		draw_rect(Rect2(c.x - 7.0, c.y + 3.0, 14.0, 3.5), KK_BLUE)

	func _stripe_border(r: Rect2, th: float) -> void:
		var step := 4.0
		var n := int(r.size.x / step)
		for i in n:
			var col := Color.WHITE if i % 2 == 0 else KK_BLUE
			draw_rect(Rect2(r.position.x + i * step, r.position.y, step, th), col)
			draw_rect(Rect2(r.position.x + i * step, r.end.y - th, step, th), col)
		var m := int(r.size.y / step)
		for j in m:
			var col2 := Color.WHITE if j % 2 == 0 else KK_BLUE
			draw_rect(Rect2(r.position.x, r.position.y + j * step, th, step), col2)
			draw_rect(Rect2(r.end.x - th, r.position.y + j * step, th, step), col2)


## Baarin edusta maan tasolla (hahmojen alla): kukkalaatikot, liitutaulu, terassi,
## punainen matto, ovimies ja jono suosittuna iltana.
class FrontView extends Node2D:
	const TILE := 16
	const CS := preload("res://scripts/core/CharSprites.gd")
	var roof := Rect2()
	var door_center := Vector2.ZERO
	var bar: Node = null
	var _t := 0.0
	var _queue_cols: Array[Color] = []

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		for i in 6:
			_queue_cols.append(Color.from_hsv(rng.randf(), rng.randf_range(0.4, 0.8), rng.randf_range(0.45, 0.9)))

	func _process(delta: float) -> void:
		_t += delta
		var cam := get_viewport().get_camera_2d()
		if cam == null or cam.global_position.distance_to(door_center) < 700.0:
			queue_redraw()

	func _level(id: String) -> int:
		if not Game.owns_bar or bar == null or bar.get("biz") == null:
			return 0
		return int(bar.biz.level(id))

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var fy := door_center.y + TILE + 2.0   # rakennuksen edessä oleva rivi
		var owned := Game.owns_bar
		# Punainen matto ja messinkitolpat (Sisustus 3)
		if _level("decor") >= 3:
			draw_rect(Rect2(door_center.x - 6.0, door_center.y + 8.0, 12.0, 16.0), Color(0.7, 0.08, 0.12))
			draw_rect(Rect2(door_center.x - 6.0, door_center.y + 8.0, 1.0, 16.0), Color(0.9, 0.75, 0.35))
			draw_rect(Rect2(door_center.x + 5.0, door_center.y + 8.0, 1.0, 16.0), Color(0.9, 0.75, 0.35))
		# Kukkalaatikot julkisivun edessä
		for side: float in [-1.0, 1.0]:
			var bx := door_center.x + side * 30.0 - 7.0
			var box := Rect2(bx, door_center.y + 5.0, 14.0, 4.0)
			draw_rect(box, Color(0.4, 0.25, 0.14))
			for k in 5:
				var fc := [Color(1.0, 0.35, 0.5), Color(1.0, 0.85, 0.3), Color(0.95, 0.95, 1.0)][k % 3] as Color
				draw_circle(Vector2(bx + 2.0 + k * 2.6, box.position.y - 1.0), 1.6, Color(0.2, 0.5, 0.25))
				draw_rect(Rect2(bx + 1.5 + k * 2.6, box.position.y - 2.5, 1.2, 1.2), fc)
		# Liitutaulu oven oikealla puolella: illan tapahtuma tai aukioloajat
		var cb := Vector2(door_center.x - 26.0, fy + 3.0)
		draw_line(cb + Vector2(-5, 9), cb + Vector2(-3, -1), Color(0.35, 0.22, 0.12), 1.0)
		draw_line(cb + Vector2(5, 9), cb + Vector2(3, -1), Color(0.35, 0.22, 0.12), 1.0)
		var board := Rect2(cb + Vector2(-6, -2), Vector2(12, 10))
		draw_rect(board.grow(1.0), Color(0.42, 0.27, 0.14))
		draw_rect(board, Color(0.1, 0.13, 0.12))
		var ev_name := ""
		if owned and bar and bar.get("biz") != null:
			ev_name = str(bar.biz.event_name())
		var line1 := "TÄNÄÄN" if ev_name != "" else "AUKI"
		var line2 := ev_name.to_upper() if ev_name != "" else ("AINA" if owned else "12-04")
		TextFit.draw(self, font, Vector2(board.position.x, board.position.y + 4.0), line1, board.size.x, 4, Color(1, 1, 1, 0.85))
		TextFit.draw(self, font, Vector2(board.position.x - 4.0, board.position.y + 8.5), line2, board.size.x + 8.0, 4, Color(1.0, 0.85, 0.4))
		if not owned:
			return
		# Ovimies (Henkilökunta 2+) ja jono suosittuna iltana
		var staff := 2 if _level("h_bouncer") >= 1 else 0
		if staff >= 2:
			_person_tex(Vector2(door_center.x + 12.0, fy + 4.0), CS.staff(CS.BOUNCER, 0, 1, 0), 0.0)
		if _level("h_bouncer") >= 2:
			_person_tex(Vector2(door_center.x - 12.0, fy + 4.0), CS.staff(CS.BOUNCER, 0, 1, 0), 0.0)
		var pop: float = bar.biz.popularity()
		var evening := Game.darkness() > 0.4
		if evening and pop >= 55.0:
			var n := clampi(int((pop - 45.0) / 12.0), 1, 4)
			if staff >= 2:
				# samettiköysi
				var rp := Vector2(door_center.x + 18.0, fy + 2.0)
				for k in n + 1:
					draw_rect(Rect2(rp + Vector2(k * 9.0 - 0.5, -4.0), Vector2(1.5, 5.0)), Color(0.85, 0.7, 0.3))
				draw_line(rp + Vector2(0, -3), rp + Vector2(n * 9.0, -3), Color(0.6, 0.05, 0.1), 1.0)
			for k in n:
				var qp := Vector2(door_center.x + 22.0 + k * 9.0, fy + 6.0)
				var types := [0, 1, 2, 3, 5]
				_person_tex(qp, CS.npc(0, int(types[k % types.size()]) * 3), k * 1.3)

	## NPC-hahmo (jonottajat, ovimies): sama kuva kuin muilla hahmoilla, räpsyttää ja huojuu.
	func _person_tex(feet: Vector2, tex: Texture2D, phase: float) -> void:
		if tex == null:
			return
		var t := tex
		if fmod(_t + phase * 2.3, 4.0 + phase) < 0.12:
			var b := CS.blink(tex)
			if b:
				t = b
		var bob := sin(_t * 2.0 + phase) * 0.4
		var sz := tex.get_size()
		draw_set_transform(feet, 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 4.5, Color(0, 0, 0, 0.25))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_texture_rect(t, Rect2(feet - Vector2(sz.x * 0.5, sz.y + bob), sz), false)

	## (vanha yksinkertainen hahmo, ei enää käytössä)
	func _person(p: Vector2, shirt: Color, phase: float) -> void:
		var bob := sin(_t * 2.0 + phase) * 0.6
		draw_circle(p + Vector2(0, 3), 3.0, Color(0, 0, 0, 0.2))
		draw_rect(Rect2(p + Vector2(-2.5, -5.0 + bob), Vector2(5, 7)), shirt)
		draw_circle(p + Vector2(0, -7.0 + bob), 2.5, Color(0.93, 0.76, 0.6))
		draw_rect(Rect2(p + Vector2(-2.5, -9.5 + bob), Vector2(5, 2)), Color(0.25, 0.15, 0.08))


## Toimistohuone: puulattia, matto, työpöytä ja tietokone, kassakaappi, henkilökuntataulu,
## sohva, viherkasvi, maine-plaketit ja baarin nimitaulu. Koordinaatit toimiston paikallisia.
class OfficeView extends Node2D:
	const TILE := 16
	const W := 12
	const H := 9
	const DESK := Rect2(72.0, 40.0, 48.0, 18.0)
	const SAFE := Rect2(150.0, 36.0, 20.0, 20.0)
	const SOFA := Rect2(20.0, 92.0, 16.0, 30.0)
	const PLANT := Rect2(156.0, 108.0, 14.0, 14.0)
	var bar: Node = null
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if bar and bar.get("in_office"):
			queue_redraw()

	func _biz() -> Node:
		return bar.get("biz") if bar else null

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var b := _biz()
		# lattia: tummat puulankut
		var fr := Rect2(TILE, 2 * TILE, (W - 2) * TILE, (H - 3) * TILE)
		draw_rect(fr, Color(0.36, 0.22, 0.13))
		var y := fr.position.y
		var row := 0
		while y < fr.end.y:
			draw_line(Vector2(fr.position.x, y), Vector2(fr.end.x, y), Color(0, 0, 0, 0.2), 1.0)
			var x := fr.position.x + float((row * 29) % 40)
			while x < fr.end.x:
				draw_line(Vector2(x, y), Vector2(x, y + 8.0), Color(0, 0, 0, 0.14), 1.0)
				x += 40.0
			y += 8.0
			row += 1
		# takaseinän tapetti
		draw_rect(Rect2(TILE, 0, (W - 2) * TILE, 2 * TILE), Color(0.22, 0.12, 0.16))
		var sx := TILE + 2.0
		while sx < (W - 1) * TILE:
			draw_line(Vector2(sx, 0), Vector2(sx, 2 * TILE), Color(0.35, 0.2, 0.25, 0.6), 1.0)
			sx += 6.0
		# matto
		var rug := Rect2(52.0, 74.0, 88.0, 40.0)
		draw_rect(rug, Color(0.5, 0.1, 0.14))
		draw_rect(rug.grow(-3.0), Color(0.62, 0.16, 0.18))
		draw_rect(rug.grow(-3.0), Color(0.9, 0.75, 0.35), false, 1.0)
		# henkilökuntataulu (korkkitaulu) ja kuvat palkatuista
		var board := Rect2(22.0, 6.0, 38.0, 24.0)
		draw_rect(board.grow(1.0), Color(0.35, 0.22, 0.1))
		draw_rect(board, Color(0.72, 0.55, 0.35))
		var staff_n := 0
		if b:
			for h: Dictionary in b.hires_list():
				staff_n += int(b.hired(str(h.id)))
		for k in mini(staff_n, 10):
			var ph := Vector2(board.position.x + 3.0 + (k % 5) * 7.0, board.position.y + 9.0 + int(k / 5) * 7.0)
			draw_rect(Rect2(ph, Vector2(5, 6)), Color.WHITE)
			draw_circle(ph + Vector2(2.5, 2.5), 1.5, Color(0.9, 0.72, 0.58))
			draw_circle(ph + Vector2(2.5, -0.5), 0.8, Color(0.9, 0.2, 0.2))   # nuppineula
		# maine-plaketit: täytetyt = saavutettu maine-taso
		var lvl: int = int(b.rep_level()) if b else 1
		for k in 10:
			var pp := Vector2(68.0 + (k % 5) * 12.0, 6.0 + int(k / 5) * 12.0)
			var got := k < lvl
			draw_rect(Rect2(pp, Vector2(9, 10)), Color(0.85, 0.68, 0.3) if got else Color(0.3, 0.2, 0.22))
			draw_rect(Rect2(pp + Vector2(2, 2), Vector2(5, 6)), Color(0.15, 0.3, 0.5) if got else Color(0.2, 0.15, 0.17))
			if got:
				draw_circle(pp + Vector2(4.5, 5), 1.3, Color(1.0, 0.85, 0.3))
		# baarin nimitaulu (pieni neon)
		var nt := Rect2(132.0, 6.0, 44.0, 22.0)
		draw_rect(nt, Color(0.04, 0.03, 0.08))
		var name_txt := Game.bar_name()
		var fs := 8
		while fs > 4 and font.get_string_size(name_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > nt.size.x - 4.0:
			fs -= 1
		var nc := Color(1.0, 0.25, 0.7, 0.85 + 0.15 * sin(_t * 4.0))
		TextFit.draw_outline(self, font, Vector2(nt.position.x, nt.get_center().y + fs * 0.35), name_txt, nt.size.x, fs, 3, Color(nc.r, nc.g, nc.b, 0.25))
		TextFit.draw(self, font, Vector2(nt.position.x, nt.get_center().y + fs * 0.35), name_txt, nt.size.x, fs, nc.lerp(Color.WHITE, 0.3))
		# työpöytä, tietokone ja tuoli
		draw_rect(Rect2(DESK.position + Vector2(1, 2), DESK.size), Color(0, 0, 0, 0.3))
		draw_rect(DESK, Color(0.42, 0.25, 0.12))
		draw_rect(DESK.grow(-1.0), Color(0.5, 0.31, 0.16), false, 1.0)
		var mon := Rect2(DESK.position.x + 15.0, DESK.position.y - 4.0, 18.0, 13.0)
		draw_rect(mon, Color(0.1, 0.1, 0.12))
		var scr := mon.grow(-1.5)
		draw_rect(scr, Color(0.05, 0.2, 0.15))
		# näytöllä nouseva tuloskäyrä
		var pts := PackedVector2Array()
		for k in 6:
			var v := 0.3 + 0.12 * k + 0.08 * sin(_t * 1.5 + k)
			pts.append(Vector2(scr.position.x + 1.0 + k * (scr.size.x - 2.0) / 5.0, scr.end.y - 1.0 - v * (scr.size.y - 3.0)))
		draw_polyline(pts, Color(0.3, 1.0, 0.5), 1.0)
		draw_rect(Rect2(DESK.position.x + 13.0, DESK.position.y + 10.0, 22.0, 4.0), Color(0.2, 0.2, 0.22))   # näppäimistö
		draw_rect(Rect2(DESK.position.x + 3.0, DESK.position.y + 3.0, 8.0, 10.0), Color(0.95, 0.95, 0.9))     # paperipino
		draw_rect(Rect2(DESK.end.x - 9.0, DESK.position.y + 4.0, 5.0, 6.0), Color(0.85, 0.92, 1.0, 0.7))      # kossupullo
		draw_rect(Rect2(DESK.end.x - 8.0, DESK.position.y + 2.0, 3.0, 2.0), Color(0.13, 0.4, 0.85))
		draw_circle(Vector2(DESK.get_center().x, DESK.end.y + 9.0), 6.0, Color(0.12, 0.12, 0.14))           # tuoli
		draw_circle(Vector2(DESK.get_center().x, DESK.end.y + 9.0), 4.5, Color(0.3, 0.08, 0.1))
		# kassakaappi
		draw_rect(Rect2(SAFE.position + Vector2(1, 2), SAFE.size), Color(0, 0, 0, 0.3))
		draw_rect(SAFE, Color(0.35, 0.37, 0.4))
		draw_rect(SAFE.grow(-2.0), Color(0.45, 0.47, 0.5), false, 1.0)
		draw_circle(SAFE.get_center(), 4.0, Color(0.2, 0.2, 0.22))
		draw_line(SAFE.get_center(), SAFE.get_center() + Vector2(3, 0).rotated(_t * 0.5), Color(0.85, 0.85, 0.85), 1.0)
		draw_rect(Rect2(SAFE.end.x - 4.0, SAFE.position.y + 6.0, 2.0, 8.0), Color(0.8, 0.7, 0.3))
		# sohva
		draw_rect(SOFA.grow(1.0), Color(0.1, 0.05, 0.03))
		draw_rect(SOFA, Color(0.45, 0.1, 0.12))
		draw_rect(Rect2(SOFA.position.x, SOFA.position.y, 5.0, SOFA.size.y), Color(0.35, 0.07, 0.09))
		draw_line(Vector2(SOFA.position.x + 5.0, SOFA.get_center().y), Vector2(SOFA.end.x, SOFA.get_center().y), Color(0.3, 0.05, 0.07), 1.0)
		# viherkasvi
		draw_rect(Rect2(PLANT.position + Vector2(2, 6), Vector2(10, 8)), Color(0.6, 0.32, 0.18))
		draw_circle(PLANT.get_center() + Vector2(0, -2), 7.0, Color(0.15, 0.45, 0.22))
		draw_circle(PLANT.get_center() + Vector2(-2, -4), 4.0, Color(0.25, 0.6, 0.3))
		# lattialamppu nurkassa + valokeila
		var lamp := Vector2(150.0, 70.0)
		draw_circle(lamp, 24.0, Color(1.0, 0.85, 0.5, 0.05))
		draw_circle(lamp, 4.0, Color(1.0, 0.92, 0.7))
		var exit := Vector2(6 * TILE + TILE * 0.5, 8 * TILE + TILE * 0.5)
		TextFit.draw_outline(self, font, Vector2(exit.x - 30.0, exit.y - 20.0), "BAARIIN", 60.0, 8, 3, Color(0, 0, 0, 0.85))
		TextFit.draw(self, font, Vector2(exit.x - 30.0, exit.y - 20.0), "BAARIIN", 60.0, 8, Color.WHITE)
		# maine ja suosio lattialla tekstinä (pieni kyltti)
		if b:
			var info := "%s  ·  SUOSIO %d %%" % [str(b.rep_text()).to_upper(), roundi(float(b.popularity()))]
			TextFit.draw(self, font, Vector2(fr.position.x, fr.end.y - 4.0), info, fr.size.x, 5, Color(1.0, 0.9, 0.6, 0.7))


## Sisätilan piirto: lattia, pullohylly, tiski, baarimikko, jakkarat, pöydät, jukeboksi.
class InteriorView extends Node2D:
	const TILE := 16
	const ROOM_W := 22
	const ROOM_H := 13
	const NEON := Color(1.0, 0.25, 0.7)
	const KK_BLUE := Color(0.13, 0.4, 0.85)
	const WOOD := Color(0.45, 0.27, 0.14)
	const WOOD_DARK := Color(0.25, 0.14, 0.08)
	const BARTENDER := Vector2(176.0, 62.0)   # baarimikon jalkojen kohta
	const SERVE_SPOT := Rect2(120.0, 80.0, 112.0, 26.0)   # sama kuin ulkoluokassa
	const POOL_TABLE := Rect2(120.0, 124.0, 64.0, 30.0)
	const CS := preload("res://scripts/core/CharSprites.gd")
	const EXTRA_LIST := [
		{"name": "Lonkero", "price": 5, "need": 1}, {"name": "Siideri", "price": 5, "need": 1},
		{"name": "Viski", "price": 9, "need": 2}, {"name": "Jaloviina", "price": 6, "need": 2},
		{"name": "Mojito", "price": 12, "need": 3}, {"name": "Long Island", "price": 14, "need": 3},
	]

	var price := 0
	var menu: Array = []
	var music_on := false
	var exit_pos := Vector2.ZERO
	## Oma baari: päivitysten tasot (BarBusiness.levels()), nimi ja illan tapahtuma
	var owned := false
	var up: Dictionary = {}
	var bar_title := "BAARI"
	var event := ""
	## Pomo itse tiskin takana: vakiobaarimikko pitää tauon
	var owner_behind := false
	var expanded := 0
	var jukebox_rect := Rect2(304.0, 104.0, 24.0, 22.0)
	var city: Node = null
	## Valittu ulkoasu (BarBusiness.looks()): floor, wall, counter, neon
	var look: Dictionary = {"floor": "wood", "wall": "brick", "counter": "wood", "neon": "pink"}
	## Illan tapahtumat (useampi samana iltana)
	var events: Array = []
	var _kind := 1          # 0 = olut, 1 = kossu, 2 = shotti

	var _t := 0.0
	var _pour_t := 0.0     # kaatoanimaatio (sekuntia jäljellä)
	var _glass_t := 0.0    # ryyppylasi tiskillä (sekuntia jäljellä)
	var _say_t := 0.0
	var _say_text := ""

	const POUR_TIME := 0.6
	const GLASS_TIME := 1.3

	## Baarimikon puhekupla
	func say(text: String, seconds: float) -> void:
		_say_text = text
		_say_t = seconds

	## Kaadetaan juoma tiskille. kind = DRINKS-listan rivi.
	func pour(kind: int = 1) -> void:
		_kind = kind
		_pour_t = POUR_TIME
		_glass_t = GLASS_TIME

	## Lasin paikka tiskillä (huoneen paikalliset koordinaatit)
	func glass_point() -> Vector2:
		return Vector2(BARTENDER.x - 12.0, 70.0)

	func _process(delta: float) -> void:
		_t += delta
		_pour_t = maxf(_pour_t - delta, 0.0)
		_glass_t = maxf(_glass_t - delta, 0.0)
		_say_t = maxf(_say_t - delta, 0.0)
		if _on_screen(Rect2(-200.0, -200.0, 900.0, 600.0)):
			queue_redraw()

	## Optimointi: piirretään uudelleen vain kun alue on kameran näkyvissä
	func _on_screen(r: Rect2) -> bool:
		var cam := get_viewport().get_camera_2d()
		if cam == null:
			return true
		var vs := get_viewport().get_visible_rect().size / cam.zoom
		var view := Rect2(cam.get_screen_center_position() - vs * 0.5, vs).grow(160.0)
		return view.intersects(get_global_transform() * r)

	func _lv(id: String) -> int:
		return int(up.get(id, 0))

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		_draw_floor()
		_draw_floor_upgrades()
		_draw_back_wall(font)
		_draw_staff_behind()
		_draw_counter()
		_draw_counter_upgrades(font)
		_draw_bartender(font)
		_draw_counter_flap()
		_draw_furniture()
		_draw_games(font)
		_draw_office_door(font)
		_draw_new_upgrades(font)
		_draw_top_upgrades(font)
		_draw_light_pools()
		_text(font, Vector2(exit_pos.x - 30.0, exit_pos.y - 20.0), "ULOS", 60.0, 8, Color(1, 1, 1, 0.95))

	# --- lattia ---
	func _draw_floor() -> void:
		var fr := Rect2(TILE, 2 * TILE, (ROOM_W - 2) * TILE, (ROOM_H - 3) * TILE)
		var fl := str(look.get("floor", "wood"))
		var dec := 0   # (lattia ei enää riipu sisustuspäivityksestä)
		match fl:
			"checker":
				# shakkiruutulattia (mustavalkoinen laatta) kiiltoineen
				draw_rect(fr, Color(0.9, 0.88, 0.84))
				var cy := fr.position.y
				var r := 0
				while cy < fr.end.y:
					var cx := fr.position.x
					var c := 0
					while cx < fr.end.x:
						if (r + c) % 2 == 0:
							draw_rect(Rect2(cx, cy, minf(16.0, fr.end.x - cx), minf(16.0, fr.end.y - cy)), Color(0.1, 0.1, 0.12))
						cx += 16.0
						c += 1
					cy += 16.0
					r += 1
				for k in 5:
					draw_line(Vector2(fr.position.x + 40.0 + k * 64.0, fr.position.y), Vector2(fr.position.x + 10.0 + k * 64.0, fr.end.y), Color(1, 1, 1, 0.06), 3.0)
			"red_tile":
				draw_rect(fr, Color(0.55, 0.16, 0.12))
				var ty := fr.position.y
				while ty < fr.end.y:
					draw_line(Vector2(fr.position.x, ty), Vector2(fr.end.x, ty), Color(0.35, 0.08, 0.06), 1.0)
					ty += 12.0
				var tx := fr.position.x
				while tx < fr.end.x:
					draw_line(Vector2(tx, fr.position.y), Vector2(tx, fr.end.y), Color(0.35, 0.08, 0.06), 1.0)
					tx += 12.0
			"concrete":
				draw_rect(fr, Color(0.46, 0.47, 0.5))
				var crng := RandomNumberGenerator.new()
				crng.seed = 5
				for k in 60:
					var cp := Vector2(crng.randf_range(fr.position.x, fr.end.x), crng.randf_range(fr.position.y, fr.end.y))
					draw_rect(Rect2(cp, Vector2(2, 1)), Color(0.38, 0.39, 0.42))
				var cx2 := fr.position.x
				while cx2 < fr.end.x:
					draw_line(Vector2(cx2, fr.position.y), Vector2(cx2, fr.end.y), Color(0.36, 0.37, 0.4), 1.0)
					cx2 += 64.0
			"carpet":
				draw_rect(fr, Color(0.15, 0.33, 0.22))
				var py := fr.position.y + 4.0
				var pr := 0
				while py < fr.end.y:
					var px := fr.position.x + 4.0 + (pr % 2) * 8.0
					while px < fr.end.x:
						draw_rect(Rect2(px, py, 2, 2), Color(0.85, 0.7, 0.35, 0.4))
						px += 16.0
					py += 8.0
					pr += 1
			"marble":
				# tumma marmori kultaisilla saumoilla
				draw_rect(fr, Color(0.13, 0.11, 0.14))
				var rng := RandomNumberGenerator.new()
				rng.seed = 77
				for k in 26:
					var a := Vector2(rng.randf_range(fr.position.x, fr.end.x), rng.randf_range(fr.position.y, fr.end.y))
					var b := a + Vector2(rng.randf_range(-40, 40), rng.randf_range(-20, 20))
					draw_line(a, b, Color(0.55, 0.52, 0.6, 0.18), 1.0)
				var gx := fr.position.x
				while gx < fr.end.x:
					draw_line(Vector2(gx, fr.position.y), Vector2(gx, fr.end.y), Color(0.85, 0.68, 0.3, 0.35), 1.0)
					gx += 32.0
				var gy := fr.position.y
				while gy < fr.end.y:
					draw_line(Vector2(fr.position.x, gy), Vector2(fr.end.x, gy), Color(0.85, 0.68, 0.3, 0.35), 1.0)
					gy += 32.0
			_:
				# puulattia: lakattu tumma puu on tummempi ja kiiltävä
				dec = 1 if fl == "dark_wood" else 0
				draw_rect(fr, Color(0.36, 0.19, 0.09) if dec == 1 else Color(0.30, 0.18, 0.11))
				var y := fr.position.y
				var row := 0
				while y < fr.end.y:
					draw_line(Vector2(fr.position.x, y), Vector2(fr.end.x, y), Color(0, 0, 0, 0.22), 1.0)
					var x := fr.position.x + float((row * 37) % 48)
					while x < fr.end.x:
						draw_line(Vector2(x, y), Vector2(x, y + 8.0), Color(0, 0, 0, 0.16), 1.0)
						x += 48.0
					y += 8.0
					row += 1
				if dec == 1:
					for k in 6:
						draw_line(Vector2(fr.position.x + 20.0 + k * 56.0, fr.position.y), Vector2(fr.position.x + k * 56.0, fr.end.y), Color(1, 0.9, 0.7, 0.05), 4.0)
		# Henkilökunnan matto tiskin takana
		draw_rect(Rect2(fr.position.x, fr.position.y, fr.size.x, 2 * TILE), Color(0.10, 0.10, 0.13))
		# Seinäpaneelit sivuseinissä (valittu tapetti)
		var wl := str(look.get("wall", "brick"))
		if wl != "brick":
			var pc := _wall_color(wl).darkened(0.1)
			dec = 3 if wl == "deco" else 1
			for wx: float in [0.0, float((ROOM_W - 1) * TILE)]:
				if wx > 0.0 and expanded >= 1:
					continue   # holvikaari juhlasaliin
				draw_rect(Rect2(wx, 2 * TILE, TILE, (ROOM_H - 3) * TILE), pc)
				for k in 4:
					draw_rect(Rect2(wx + 3.0, 2 * TILE + 6.0 + k * 38.0, TILE - 6.0, 30.0), pc.lightened(0.15), false, 1.0)
				if dec >= 3:
					draw_line(Vector2(wx, 2 * TILE), Vector2(wx, (ROOM_H - 1) * TILE), Color(0.85, 0.68, 0.3), 1.0)
					draw_line(Vector2(wx + TILE, 2 * TILE), Vector2(wx + TILE, (ROOM_H - 1) * TILE), Color(0.85, 0.68, 0.3), 1.0)
		# Holvikaari juhlasaliin (Laajennus 1+)
		if expanded >= 1:
			var ax := float((ROOM_W - 1) * TILE)
			draw_rect(Rect2(ax, 5 * TILE, TILE, 6 * TILE), Color(0.25, 0.16, 0.1))
			draw_rect(Rect2(ax, 5 * TILE - 4.0, TILE, 4.0), Color(0.85, 0.68, 0.3))
			draw_rect(Rect2(ax, 11 * TILE, TILE, 3.0), Color(0.85, 0.68, 0.3))

	# --- takaseinä: pullohylly, listataulu, neon ---
	func _draw_back_wall(font: Font) -> void:
		# Tapetti takaseinässä (Sisustus 1+)
		var wl := str(look.get("wall", "brick"))
		var dec := {"brick": 0, "green": 1, "wood": 1, "blue_stripe": 1, "burgundy": 2, "deco": 3}.get(wl, 0) as int
		if wl != "brick":
			var wall := Rect2(TILE, 0.0, (ROOM_W - 2) * TILE, 2 * TILE)
			var wc := _wall_color(wl)
			draw_rect(wall, wc)
			var px := wall.position.x
			var k := 0
			while px < wall.end.x:
				if wl == "blue_stripe":
					if k % 2 == 0:
						draw_rect(Rect2(px, 0.0, 4.0, 2 * TILE), wc.lightened(0.25))
				elif wl == "wood":
					draw_line(Vector2(px, 0.0), Vector2(px, 2 * TILE), wc.darkened(0.3), 1.0)
				elif dec == 1:
					draw_line(Vector2(px, 0.0), Vector2(px, 2 * TILE), wc.lightened(0.12), 1.0)
				elif dec == 2:
					draw_colored_polygon(PackedVector2Array([Vector2(px + 4, 4 + (k % 2) * 12), Vector2(px + 8, 8 + (k % 2) * 12),
						Vector2(px + 4, 12 + (k % 2) * 12), Vector2(px, 8 + (k % 2) * 12)]), wc.lightened(0.18))
				else:
					draw_arc(Vector2(px + 4, 28.0), 6.0, PI, TAU, 8, Color(0.85, 0.68, 0.3, 0.6), 1.0)
					draw_line(Vector2(px + 4, 22.0), Vector2(px + 4, 28.0), Color(0.85, 0.68, 0.3, 0.4), 1.0)
				px += 8.0
				k += 1
			draw_rect(Rect2(wall.position.x, wall.end.y - 3.0, wall.size.x, 3.0), Color(0.85, 0.68, 0.3) if dec >= 3 else WOOD_DARK)
		# Valaistu viskiseinä (Juomavalikoima 2+): hehku pullojen takana
		if owned and _lv("drinks") >= 2:
			draw_rect(Rect2(92.0, 2.0, 170.0, 27.0), Color(1.0, 0.65, 0.25, 0.22 + 0.04 * sin(_t * 2.0)))
			draw_rect(Rect2(92.0, 2.0, 170.0, 1.0), Color(1.0, 0.8, 0.5, 0.6))
		# Hyllylaudat ja pullot (ylärivi kokonaan Koskenkorvaa, alarivillä muutama muu pullo)
		var mixed := 3 if _lv("drinks") == 0 else (2 if _lv("drinks") == 1 else 1)
		for i in 17:
			var other := (i % mixed == mixed - 1) if mixed > 1 else (i % 3 != 0)
			_shelf_bottle(Vector2(100.0 + i * 9.0, 27.0), (i % 4) + 1 if other else 0)
		for i in 17:
			_shelf_bottle(Vector2(100.0 + i * 9.0, 13.0), 0)
		draw_rect(Rect2(92.0, 13.0, 168.0, 2.0), WOOD_DARK)
		draw_rect(Rect2(92.0, 27.0, 168.0, 2.0), WOOD_DARK)
		draw_rect(Rect2(90.0, 3.0, 2.0, 26.0), WOOD_DARK)
		draw_rect(Rect2(260.0, 3.0, 2.0, 26.0), WOOD_DARK)

		# Listataulu
		var board := Rect2(22.0, 4.0, 62.0, 24.0)
		draw_rect(board, Color(0.07, 0.12, 0.11))
		draw_rect(board, WOOD, false, 2.0)
		if menu.is_empty():
			TextFit.draw(self, font, Vector2(board.position.x, board.position.y + 10.0), "KOSKENKORVA", board.size.x, 7, Color(0.85, 0.93, 1.0))
			TextFit.draw(self, font, Vector2(board.position.x, board.position.y + 20.0), "4 cl  %d $" % price, board.size.x, 8, Color(1.0, 0.85, 0.3))
		else:
			var all_d: Array = menu.duplicate()
			if owned:
				for d2: Dictionary in EXTRA_LIST:
					if int(d2.need) <= _lv("drinks"):
						all_d.append(d2)
			var step := 7.0 if all_d.size() <= 3 else 20.0 / float(all_d.size())
			var fs := 6 if all_d.size() <= 3 else 4
			for i in all_d.size():
				var d: Dictionary = all_d[i]
				var ly := board.position.y + (8.0 if all_d.size() <= 3 else 5.0) + i * step
				draw_string(font, Vector2(board.position.x + 3.0, ly), str(d.name).to_upper(),
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.93, 1.0))
				draw_string(font, Vector2(board.position.x, ly), "%d $" % int(d.price),
					HORIZONTAL_ALIGNMENT_RIGHT, board.size.x - 3.0, fs, Color(1.0, 0.85, 0.3))
			if owned and "happy" in events:
				TextFit.draw(self, font, Vector2(board.position.x, board.end.y + 6.0), "HAPPY HOUR -25%", board.size.x, 5, Color(1.0, 0.9, 0.3, 0.6 + 0.4 * sin(_t * 6.0)))

		# Neon
		var flick := 0.8 + 0.2 * sin(_t * 4.3)
		var nb := Game.bar_neon_color()
		var neon := Color(nb.r, nb.g, nb.b, flick)
		var sign_r := Rect2(268.0, 5.0, 64.0, 22.0)
		draw_rect(sign_r, Color(0.04, 0.03, 0.09))
		draw_rect(sign_r, neon, false, 1.0)
		# baarin nimi kahdelle riville, jos ei mahdu yhdelle
		var words := bar_title.split(" ", false)
		var rows: Array[String] = [bar_title]
		if words.size() >= 2 and font.get_string_size(bar_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x > sign_r.size.x - 4.0:
			var half := int(ceil(words.size() / 2.0))
			rows = [" ".join(words.slice(0, half)), " ".join(words.slice(half))]
		for ri in rows.size():
			var fs := 11 if rows.size() == 1 else 8
			while fs > 5 and font.get_string_size(rows[ri], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > sign_r.size.x - 4.0:
				fs -= 1
			var by := sign_r.position.y + (15.0 if rows.size() == 1 else 10.0 + ri * 9.0)
			var col := Game.bar_neon_color() if ri == 0 or _lv("sign") < 2 else Game.bar_neon_color2()
			var nc := Color(col.r, col.g, col.b, flick)
			var base := Vector2(sign_r.position.x, by)
			TextFit.draw_outline(self, font, base, rows[ri], sign_r.size.x, fs, 3, Color(col.r, col.g, col.b, 0.25 * flick))
			TextFit.draw(self, font, base, rows[ri], sign_r.size.x, fs, nc.lerp(Color.WHITE, 0.3))

	## kind 0 = Koskenkorva, 1-4 = muut pullot. p = pullon pohjan keskikohta.
	func _shelf_bottle(p: Vector2, kind: int) -> void:
		if kind == 0:
			var glass := Color(0.85, 0.93, 1.0)
			draw_rect(Rect2(p.x - 3.0, p.y - 8.0, 6.0, 8.0), glass)
			draw_rect(Rect2(p.x - 1.0, p.y - 11.0, 2.0, 3.0), glass)
			draw_rect(Rect2(p.x - 1.5, p.y - 12.0, 3.0, 1.5), KK_BLUE)
			draw_rect(Rect2(p.x - 3.0, p.y - 6.0, 6.0, 4.5), Color.WHITE)
			draw_rect(Rect2(p.x - 3.0, p.y - 5.0, 6.0, 1.5), KK_BLUE)
		else:
			var cols := [Color(0.55, 0.32, 0.1), Color(0.2, 0.5, 0.3), Color(0.5, 0.12, 0.15), Color(0.3, 0.3, 0.4)]
			var c: Color = cols[(kind - 1) % cols.size()]
			draw_rect(Rect2(p.x - 3.0, p.y - 8.0, 6.0, 8.0), c)
			draw_rect(Rect2(p.x - 1.0, p.y - 11.0, 2.0, 3.0), c)
			draw_rect(Rect2(p.x - 1.5, p.y - 12.0, 3.0, 1.5), Color(0.1, 0.1, 0.1))
			draw_rect(Rect2(p.x - 3.0, p.y - 5.0, 6.0, 2.5), Color(0.9, 0.85, 0.7))

	# --- tiski ---
	func _draw_counter() -> void:
		var top := Rect2(TILE, 62.0, (ROOM_W - 2) * TILE, 16.0)
		draw_rect(top, WOOD)
		draw_line(Vector2(top.position.x, top.position.y + 1.0), Vector2(top.end.x, top.position.y + 1.0),
			Color(0.65, 0.42, 0.24), 2.0)
		# Etupaneeli + messinkinen jalkatuki
		draw_rect(Rect2(top.position.x, top.end.y, top.size.x, 8.0), WOOD_DARK)
		draw_line(Vector2(top.position.x, top.end.y + 5.0), Vector2(top.end.x, top.end.y + 5.0),
			Color(0.85, 0.7, 0.3, 0.8), 1.0)
		# Kassakone oikealla
		draw_rect(Rect2(292.0, 54.0, 16.0, 12.0), Color(0.3, 0.32, 0.36))
		draw_rect(Rect2(294.0, 56.0, 12.0, 4.0), Color(0.3, 0.9, 0.5))
		# Muutama lasi tiskillä
		for gx in [40.0, 52.0, 232.0, 250.0]:
			draw_rect(Rect2(gx, 66.0, 4.0, 5.0), Color(0.85, 0.92, 1.0, 0.55))
		# Hintalaput tiskin etupaneelissa jokaisen tilauspaikan kohdalla
		if not menu.is_empty():
			var font := ThemeDB.fallback_font
			var slot_w := SERVE_SPOT.size.x / menu.size()
			for i in menu.size():
				var d: Dictionary = menu[i]
				var x0 := SERVE_SPOT.position.x + slot_w * i
				draw_rect(Rect2(x0 + 3.0, 79.0, slot_w - 6.0, 6.0), Color(0.07, 0.12, 0.11))
				TextFit.draw(self, font, Vector2(x0, 84.5), "%s %d$" % [str(d.name).to_upper(), int(d.price)], slot_w, 5, Color(1.0, 0.85, 0.3))

	# --- baarimikko ---
	func _draw_bartender(font: Font) -> void:
		var bx := BARTENDER.x
		# (baarimikon hahmo piirretään tiskin taakse: _draw_staff_behind)
		if owner_behind:
			return

		# Kaato: pullo kallistuu lasin päälle
		var glass_pos := Vector2(bx - 12.0, 70.0)
		if _pour_t > 0.0:
			var prog := 1.0 - _pour_t / POUR_TIME
			var ang := sin(PI * prog) * 1.1
			draw_set_transform(Vector2(bx + 13.0, 56.0), -ang, Vector2.ONE)
			_shelf_bottle(Vector2.ZERO, 0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if prog > 0.25 and prog < 0.8:
				draw_line(Vector2(bx + 6.0, 50.0), glass_pos + Vector2(0.0, -2.0), Color(0.85, 0.95, 1.0, 0.8), 1.0)
		# Lasi tiskillä: täyttyy, sitten tyhjenee kun pelaaja kumoaa sen
		if _glass_t > 0.0:
			var full := _glass_t > 0.45
			match _kind:
				0:   # olut: korkea tuoppi, kullankeltainen + vaahto
					var g := Rect2(glass_pos.x - 3.0, glass_pos.y - 8.0, 6.0, 11.0)
					draw_rect(g, Color(0.85, 0.92, 1.0, 0.35))
					if full:
						draw_rect(Rect2(g.position.x + 0.5, g.position.y + 3.0, 5.0, 7.5), Color(0.95, 0.68, 0.15, 0.95))
						draw_rect(Rect2(g.position.x + 0.5, g.position.y + 1.0, 5.0, 2.5), Color(1.0, 0.98, 0.9))
					draw_rect(g, Color(1, 1, 1, 0.7), false, 1.0)
				2:   # shotti: pieni lasi, tumma salmiakki
					var g := Rect2(glass_pos.x - 2.0, glass_pos.y - 1.0, 4.0, 4.0)
					draw_rect(g, Color(0.85, 0.92, 1.0, 0.45))
					if full:
						draw_rect(Rect2(g.position.x + 0.5, g.position.y + 1.0, 3.0, 2.5), Color(0.12, 0.06, 0.08, 0.95))
					draw_rect(g, Color(1, 1, 1, 0.7), false, 1.0)
				3:   # cocktail: jalallinen lasi, vaaleanpunainen + sitruuna
					draw_colored_polygon(PackedVector2Array([glass_pos + Vector2(-4, -7), glass_pos + Vector2(4, -7), glass_pos + Vector2(0, -2)]),
						Color(1.0, 0.4, 0.65, 0.95) if full else Color(0.85, 0.92, 1.0, 0.4))
					draw_line(glass_pos + Vector2(0, -2), glass_pos + Vector2(0, 2), Color(1, 1, 1, 0.7), 1.0)
					draw_line(glass_pos + Vector2(-2, 2), glass_pos + Vector2(2, 2), Color(1, 1, 1, 0.7), 1.0)
					if full:
						draw_circle(glass_pos + Vector2(3.5, -7.5), 1.5, Color(0.95, 0.9, 0.2))
				4:   # tölkki (lonkero / siideri)
					draw_rect(Rect2(glass_pos.x - 2.5, glass_pos.y - 6.0, 5.0, 8.0), Color(0.2, 0.75, 0.6))
					draw_rect(Rect2(glass_pos.x - 2.5, glass_pos.y - 4.0, 5.0, 2.0), Color(1.0, 0.9, 0.3))
					draw_rect(Rect2(glass_pos.x - 2.5, glass_pos.y - 6.0, 5.0, 1.0), Color(0.8, 0.82, 0.85))
				_:   # kossu
					draw_rect(Rect2(glass_pos.x - 2.5, glass_pos.y - 3.0, 5.0, 6.0), Color(0.85, 0.92, 1.0, 0.45))
					if full:
						draw_rect(Rect2(glass_pos.x - 2.0, glass_pos.y - 0.5, 4.0, 3.0), Color(0.95, 0.98, 1.0, 0.9))
					draw_rect(Rect2(glass_pos.x - 2.5, glass_pos.y - 3.0, 5.0, 6.0), Color(1, 1, 1, 0.7), false, 1.0)

		# Puhekupla
		if _say_t > 0.0 and _say_text != "":
			var fs := 8
			var w := font.get_string_size(_say_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0
			var box := Rect2(bx - w * 0.5, 14.0, w, 14.0)
			draw_rect(box, Color(1, 1, 1, 0.95))
			draw_rect(box, Color(0, 0, 0, 0.9), false, 1.0)
			draw_colored_polygon(PackedVector2Array([
				Vector2(bx - 3.0, box.end.y), Vector2(bx + 3.0, box.end.y), Vector2(bx, box.end.y + 5.0)]),
				Color(1, 1, 1, 0.95))
			draw_string(font, Vector2(box.position.x + 5.0, box.position.y + 10.0), _say_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)

	# --- jakkarat, pöydät, jukeboksi ---
	func _draw_furniture() -> void:
		# Tiskin jakkarat
		for sx in [40.0, 72.0, 104.0, 248.0, 280.0, 312.0]:
			_stool(Vector2(sx, 94.0))
		# Pöydät jakkaroineen
		for tx in [64.0, 288.0]:
			var tc := Vector2(tx, 150.0)
			_stool(tc + Vector2(-17.0, 0.0))
			_stool(tc + Vector2(17.0, 0.0))
			draw_circle(tc, 11.0, WOOD_DARK)
			draw_circle(tc, 10.0, WOOD)
			draw_circle(tc + Vector2(2.0, -1.0), 2.0, Color(0.85, 0.92, 1.0, 0.7))
		# Jukeboksi (Laajennuksen jälkeen juhlasalissa)
		var jb := jukebox_rect
		draw_rect(jb, Color(0.14, 0.1, 0.2))
		draw_rect(jb, Color(0.2, 0.9, 1.0, 0.9), false, 1.0)
		for i in 4:
			var h := 3.0 + 6.0 * (0.5 + 0.5 * sin(_t * (5.0 + i * 1.7) + i))
			if not music_on:
				h = 2.0
			draw_rect(Rect2(jb.position.x + 3.0 + i * 5.0, jb.position.y + 16.0 - h, 3.0, h),
				Color(1.0, 0.3, 0.7) if i % 2 == 0 else Color(0.3, 0.9, 1.0))

	## Biljardipöytä, tikkataulu, korttipakka ja portsari.
	func _draw_games(font: Font) -> void:
		var pt := POOL_TABLE
		draw_rect(pt.grow(1.0), Color(0.12, 0.06, 0.03))
		draw_rect(pt, WOOD_DARK)
		draw_rect(pt.grow(-3.0), Color(0.1, 0.45, 0.22))
		for corner in [pt.position + Vector2(3, 3), Vector2(pt.end.x - 3, pt.position.y + 3),
				Vector2(pt.position.x + 3, pt.end.y - 3), pt.end - Vector2(3, 3),
				Vector2(pt.get_center().x, pt.position.y + 3), Vector2(pt.get_center().x, pt.end.y - 3)]:
			draw_circle(corner, 2.0, Color(0.03, 0.03, 0.03))
		var balls := [Color(0.95, 0.85, 0.2), Color(0.8, 0.15, 0.15), Color(0.15, 0.3, 0.8), Color(0.1, 0.1, 0.1), Color(0.95, 0.5, 0.1)]
		for i in balls.size():
			draw_circle(pt.position + Vector2(36.0 + (i % 3) * 3.5, 11.0 + float(i / 3) * 4.0 + (i % 3) * 1.5), 1.6, balls[i])
		draw_circle(pt.position + Vector2(14.0, 15.0), 1.6, Color.WHITE)
		# Tikkataulu vasemmalla seinällä
		var dc := Vector2(9.0, 102.0)
		draw_circle(dc, 7.0, Color(0.1, 0.1, 0.1))
		draw_circle(dc, 6.0, Color(0.9, 0.85, 0.7))
		draw_circle(dc, 4.0, Color(0.15, 0.5, 0.25))
		draw_circle(dc, 2.2, Color(0.8, 0.15, 0.15))
		draw_circle(dc, 0.9, Color(0.1, 0.1, 0.1))
		# Korttipakka oikealla pöydällä
		var tc := Vector2(288.0, 150.0)
		draw_rect(Rect2(tc + Vector2(-6, -3), Vector2(5, 7)), Color.WHITE)
		draw_rect(Rect2(tc + Vector2(1, -3), Vector2(5, 7)), Color(0.85, 0.15, 0.2))
		# Portsari oven vieressä
		var bx := 206.0
		_staff(Vector2(bx, 186.0), CS.BOUNCER, 0, 2, 0, 3)   # kasvot tiskiin päin

	func _wall_color(id: String) -> Color:
		match id:
			"green":
				return Color(0.12, 0.28, 0.2)
			"burgundy":
				return Color(0.38, 0.07, 0.11)
			"deco":
				return Color(0.07, 0.06, 0.09)
			"blue_stripe":
				return Color(0.15, 0.25, 0.5)
			"wood":
				return Color(0.42, 0.26, 0.14)
		return Color(0.55, 0.3, 0.22)

	# --- oman baarin päivitykset ---
	## Lattiatason päivitykset: tanssilattia, loosit, punainen matto, kasvit.
	func _draw_floor_upgrades() -> void:
		if not owned:
			return
		var snd := _lv("sound")
		if snd >= 2 and expanded < 1:   # laajennuksen jälkeen tanssitaan juhlasalin LED-lattialla
			var df := Rect2(192.0, 108.0, 70.0, 52.0)
			var cell := 10.0
			var cols := [Color(1.0, 0.25, 0.7), Color(0.25, 0.9, 1.0), Color(1.0, 0.85, 0.25), Color(0.55, 0.3, 1.0)]
			var yy := df.position.y
			var row := 0
			while yy < df.end.y:
				var xx := df.position.x
				var col_i := 0
				while xx < df.end.x:
					var beat := int(_t * (2.0 if music_on else 0.5)) + row * 3 + col_i
					var c: Color = cols[beat % cols.size()]
					var a := 0.35 if music_on else 0.12
					draw_rect(Rect2(xx, yy, minf(cell, df.end.x - xx) - 1.0, minf(cell, df.end.y - yy) - 1.0), Color(c.r, c.g, c.b, a))
					xx += cell
					col_i += 1
				yy += cell
				row += 1
			draw_rect(df, Color(0.85, 0.85, 0.9, 0.5), false, 1.0)
		var dec := _lv("decor")
		if dec >= 2:
			# nahkaloosit seinien vieressä ja viherkasvit kulmissa
			for bx: float in ([18.0] if expanded >= 1 else [18.0, 322.0]):
				var b := Rect2(bx, 128.0, 12.0, 44.0)
				draw_rect(b.grow(1.0), Color(0.18, 0.05, 0.05))
				draw_rect(b, Color(0.5, 0.1, 0.12))
				for k in 4:
					draw_line(Vector2(b.position.x + 1.0, b.position.y + 11.0 * k), Vector2(b.end.x - 1.0, b.position.y + 11.0 * k), Color(0.3, 0.05, 0.07), 1.0)
			for pp: Vector2 in [Vector2(26.0, 180.0), Vector2(326.0, 180.0)]:
				draw_rect(Rect2(pp + Vector2(-4, -1), Vector2(8, 7)), Color(0.55, 0.3, 0.18))
				draw_circle(pp + Vector2(0, -5), 6.0, Color(0.15, 0.45, 0.22))
				draw_circle(pp + Vector2(-2, -7), 3.5, Color(0.25, 0.6, 0.3))
		if dec >= 3:
			draw_rect(Rect2(exit_pos.x - 8.0, 160.0, 16.0, exit_pos.y - 168.0), Color(0.6, 0.06, 0.1))
			draw_rect(Rect2(exit_pos.x - 8.0, 160.0, 16.0, exit_pos.y - 168.0), Color(0.9, 0.72, 0.3), false, 1.0)

	## Tiskin päivitykset: keittiön luukku, cocktailasema, viskitynnyri.
	func _draw_counter_upgrades(font: Font) -> void:
		if not owned:
			return
		var dec := _lv("decor")
		var top := Rect2(TILE, 62.0, (ROOM_W - 2) * TILE, 16.0)
		var ct := str(look.get("counter", "wood"))
		if ct != "wood":
			# valittu tiskin pinta: marmori tai kupari
			var base := {"white_marble": Color(0.88, 0.87, 0.86), "black_marble": Color(0.12, 0.1, 0.12), "copper": Color(0.72, 0.42, 0.25)}.get(ct, Color(0.45, 0.27, 0.14)) as Color
			draw_rect(top, base)
			var rng := RandomNumberGenerator.new()
			rng.seed = 11
			for k in 18:
				var a := Vector2(rng.randf_range(top.position.x, top.end.x), rng.randf_range(top.position.y, top.end.y))
				var vein := Color(0.5, 0.5, 0.55, 0.35) if ct == "white_marble" else (Color(0.85, 0.68, 0.3, 0.3) if ct == "black_marble" else Color(0.95, 0.65, 0.4, 0.35))
				draw_line(a, a + Vector2(rng.randf_range(6, 16), rng.randf_range(-3, 3)), vein, 1.0)
			draw_line(Vector2(top.position.x, top.position.y + 1.0), Vector2(top.end.x, top.position.y + 1.0), Color(1, 1, 1, 0.5), 1.0)
		if dec >= 2:
			# LED-nauha etupaneelin alla (Sisustus 2)
			var led := Color.from_hsv(fmod(_t * 0.08, 1.0), 0.7, 1.0)
			draw_rect(Rect2(top.position.x, top.end.y + 7.0, top.size.x, 2.0), Color(led.r, led.g, led.b, 0.85))
			draw_rect(Rect2(top.position.x, top.end.y + 9.0, top.size.x, 6.0), Color(led.r, led.g, led.b, 0.12))
		if dec >= 3:
			draw_line(Vector2(top.position.x, top.end.y + 5.0), Vector2(top.end.x, top.end.y + 5.0), Color(1.0, 0.82, 0.35), 2.0)
			# riippuvalaisimet tiskin yllä
			for lx: float in [60.0, 120.0, 236.0, 290.0]:
				draw_line(Vector2(lx, 0.0), Vector2(lx, 52.0), Color(0.2, 0.2, 0.2), 1.0)
				draw_colored_polygon(PackedVector2Array([Vector2(lx - 5, 58), Vector2(lx + 5, 58), Vector2(lx + 2, 52), Vector2(lx - 2, 52)]), Color(0.85, 0.68, 0.3))
				draw_circle(Vector2(lx, 62.0), 9.0, Color(1.0, 0.9, 0.6, 0.12))
		if _lv("drinks") >= 1:
			# kylmäkaappi lasiovella tiskin takana: lonkerot ja siiderit
			var fz := Rect2(270.0, 32.0, 18.0, 28.0)
			draw_rect(fz, Color(0.75, 0.77, 0.8))
			draw_rect(fz.grow(-2.0), Color(0.55, 0.85, 1.0, 0.9))
			for row in 3:
				for k in 3:
					var cc := [Color(0.2, 0.75, 0.6), Color(0.9, 0.75, 0.2), Color(0.85, 0.2, 0.3)][(row + k) % 3] as Color
					draw_rect(Rect2(fz.position.x + 3.0 + k * 4.5, fz.position.y + 4.0 + row * 8.0, 3.0, 6.0), cc)
			draw_rect(Rect2(fz.position.x, fz.position.y, fz.size.x, 3.0), Color(0.3, 0.9, 1.0, 0.8))
		if _lv("drinks") >= 3:
			# COCKTAILS-neon tiskin etupaneelissa
			var cn := Color(0.25, 0.95, 1.0, 0.75 + 0.25 * sin(_t * 3.0))
			draw_string_outline(font, Vector2(244.0, 85.0), "COCKTAILS", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, 3, Color(cn.r, cn.g, cn.b, 0.25))
			draw_string(font, Vector2(244.0, 85.0), "COCKTAILS", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, cn.lerp(Color.WHITE, 0.3))
			# hedelmäkulho ja shaker tiskillä
			draw_circle(Vector2(306.0, 70.0), 3.0, Color(0.95, 0.85, 0.2))
			draw_circle(Vector2(302.0, 71.0), 2.5, Color(0.4, 0.85, 0.3))
			draw_rect(Rect2(296.0, 64.0, 3.0, 7.0), Color(0.8, 0.82, 0.86))
		var kit := _lv("kitchen")
		if kit >= 1:
			# Keittiön luukku tiskin vasemmassa päässä: ranskalaiskorit ja kello
			var hatch := Rect2(26.0, 40.0, 58.0, 22.0)
			draw_rect(hatch, Color(0.75, 0.75, 0.72))
			draw_rect(hatch.grow(-2.0), Color(0.3, 0.3, 0.32))
			if _lv("h_cook") >= 1:
				# kokki luukulla (kokin asu + hattu)
				var cf := Vector2(55.0, 62.0)
				_staff(cf, CS.CHEF, 0, 1, 0, 6)
				draw_rect(Rect2(cf.x - 4.0, cf.y - 19.0, 8.0, 4.0), Color(0.98, 0.98, 0.98))
				draw_circle(Vector2(cf.x - 2.0, cf.y - 19.0), 2.5, Color(0.98, 0.98, 0.98))
				draw_circle(Vector2(cf.x + 2.0, cf.y - 19.5), 2.5, Color(0.98, 0.98, 0.98))
			for k in 2:
				var fp := Vector2(36.0 + k * 14.0, 68.0)
				draw_rect(Rect2(fp + Vector2(-4, -3), Vector2(8, 5)), Color(0.85, 0.15, 0.15))
				for j in 4:
					draw_rect(Rect2(fp + Vector2(-3.0 + j * 2.0, -6.0), Vector2(1, 4)), Color(1.0, 0.8, 0.3))
				# höyry
				var st := fmod(_t * 0.8 + k * 0.5, 1.0)
				draw_circle(fp + Vector2(0, -8.0 - st * 8.0), 1.5 + st * 2.0, Color(1, 1, 1, 0.25 * (1.0 - st)))
			draw_circle(Vector2(72.0, 70.0), 2.0, Color(0.9, 0.75, 0.3))
			if kit >= 2:
				# pizza tiskillä
				var pz := Vector2(80.0, 70.0)
				draw_circle(pz, 4.5, Color(0.9, 0.65, 0.3))
				draw_circle(pz, 3.6, Color(0.85, 0.2, 0.12))
				for k in 4:
					draw_circle(pz + Vector2.from_angle(k * 1.6) * 2.0, 0.7, Color(1.0, 0.95, 0.7))
		var dr := _lv("drinks")
		if dr >= 2:
			# viskitynnyri tiskin takana
			var bc := Vector2(84.0, 52.0)
			draw_circle(bc, 6.0, Color(0.45, 0.26, 0.12))
			draw_arc(bc, 6.0, 0.0, TAU, 14, Color(0.2, 0.2, 0.22), 1.0)
			draw_arc(bc, 3.5, 0.0, TAU, 12, Color(0.3, 0.18, 0.08), 1.0)
		if dr >= 3:
			# cocktaillasit sateenvarjoineen
			for k in 3:
				var gp := Vector2(240.0 + k * 9.0, 70.0)
				draw_colored_polygon(PackedVector2Array([gp + Vector2(-3, -4), gp + Vector2(3, -4), gp + Vector2(0, 0)]),
					[Color(1.0, 0.4, 0.6), Color(0.3, 0.9, 1.0), Color(1.0, 0.75, 0.2)][k] as Color)
				draw_line(gp, gp + Vector2(0, 3), Color(1, 1, 1, 0.7), 1.0)
				draw_line(gp + Vector2(1, -4), gp + Vector2(3, -8), Color(0.9, 0.9, 0.9), 1.0)
				draw_circle(gp + Vector2(3, -8), 1.5, Color(1.0, 0.3, 0.3))

	## Tiskiluukku oikeassa päässä: omistajalle auki (nostettu pystyyn), muuten kiinni.
	func _draw_counter_flap() -> void:
		var fl := Rect2(312.0, 62.0, 24.0, 24.0)
		if owned:
			draw_rect(fl, Color(0.30, 0.18, 0.11))
			draw_rect(Rect2(fl.position.x, fl.position.y, fl.size.x, 2.0), Color(0, 0, 0, 0.25))
			# nostettu luukku seinää vasten
			draw_rect(Rect2(fl.end.x - 4.0, 36.0, 4.0, 26.0), WOOD)
			draw_rect(Rect2(fl.end.x - 4.0, 36.0, 4.0, 26.0), WOOD_DARK, false, 1.0)
			# nuoli: tästä tiskin taakse
			var a := 0.5 + 0.5 * sin(_t * 4.0)
			var tip := Vector2(fl.get_center().x - 2.0, fl.position.y + 6.0)
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-4, 6), tip + Vector2(4, 6)]), Color(1.0, 0.85, 0.3, 0.4 + 0.5 * a))
		else:
			draw_line(Vector2(fl.position.x, fl.position.y), Vector2(fl.position.x, fl.position.y + 16.0), WOOD_DARK, 1.0)

	## Toimiston ovi alaseinässä.
	func _draw_office_door(font: Font) -> void:
		var d := Rect2(97.0, 193.0, 14.0, 14.0)
		draw_rect(d, Color(0.35, 0.2, 0.1))
		draw_rect(d, Color(0.2, 0.1, 0.05), false, 1.0)
		draw_circle(Vector2(d.end.x - 3.0, d.get_center().y), 0.9, Color(0.9, 0.75, 0.3))
		_text(font, Vector2(d.position.x - 14.0, d.position.y - 3.0), "TOIMISTO", d.size.x + 28.0, 6,
			Color(1.0, 0.85, 0.5) if owned else Color(0.85, 0.85, 0.85))

	## Uudemmat päivitykset sisällä: pajatso ja flipperi, valvontakamerat ja metallinpaljastin,
	## WC- ja saunaovet alaseinällä kylttien kera.
	func _draw_new_upgrades(font: Font) -> void:
		if not owned:
			return
		var slots := _lv("slots")
		if slots >= 1:
			# pajatso vasemmalla seinällä tikkataulun alla, kolikko putoilee nastojen läpi
			var pj := Rect2(2.0, 124.0, 12.0, 18.0)
			draw_rect(pj.grow(1.0), Color(0.1, 0.06, 0.03))
			draw_rect(pj, Color(0.6, 0.12, 0.1))
			draw_rect(Rect2(pj.position.x + 2.0, pj.position.y + 2.0, 8.0, 9.0), Color(0.95, 0.9, 0.75))
			for k in 6:
				draw_circle(Vector2(pj.position.x + 3.0 + (k % 3) * 3.0, pj.position.y + 4.0 + floorf(k / 3.0) * 4.0), 0.6, Color(0.6, 0.6, 0.65))
			var coin_y := pj.position.y + 3.0 + fmod(_t * 8.0, 7.0)
			draw_circle(Vector2(pj.position.x + 6.0, coin_y), 0.9, Color(1.0, 0.85, 0.3))
			draw_rect(Rect2(pj.position.x + 2.0, pj.end.y - 5.0, 8.0, 3.0), Color(0.15, 0.1, 0.08))
		if slots >= 2:
			# flipperi oikeassa alakulmassa, valot vilkkuvat ja pallo pomppii
			var fp := Rect2(294.0, 168.0, 20.0, 18.0)
			draw_rect(Rect2(fp.position + Vector2(1, 2), fp.size), Color(0, 0, 0, 0.3))
			draw_rect(fp, Color(0.12, 0.1, 0.2))
			draw_rect(Rect2(fp.position.x + 2.0, fp.position.y + 2.0, fp.size.x - 4.0, fp.size.y - 4.0), Color(0.1, 0.35, 0.55))
			draw_rect(Rect2(fp.position.x, fp.position.y - 6.0, fp.size.x, 7.0), Color(0.08, 0.06, 0.12))
			var lamps := [Color(1, 0.3, 0.6), Color(0.3, 0.9, 1), Color(1, 0.85, 0.2)]
			var blink := int(_t * 4.0) % 3
			for k in 3:
				draw_circle(Vector2(fp.position.x + 4.0 + k * 6.0, fp.position.y - 2.5), 1.4, lamps[(k + blink) % 3] as Color)
			var ball := fp.position + Vector2(4.0 + absf(fmod(_t * 9.0, 24.0) - 12.0), 4.0 + absf(fmod(_t * 7.0, 20.0) - 10.0))
			draw_circle(ball, 0.9, Color(0.9, 0.9, 0.95))
			draw_line(Vector2(fp.position.x + 4.0, fp.end.y - 3.0), Vector2(fp.get_center().x - 1.0, fp.end.y - 2.0), Color(1, 0.9, 0.3), 1.0)
			draw_line(Vector2(fp.end.x - 4.0, fp.end.y - 3.0), Vector2(fp.get_center().x + 1.0, fp.end.y - 2.0), Color(1, 0.9, 0.3), 1.0)
		var sec := _lv("security")
		if sec >= 1:
			# valvontakamerat takaseinän ylänurkissa, punainen ledi vilkkuu
			for cp: Vector2 in [Vector2(20.0, 34.0), Vector2(332.0, 34.0)]:
				var dirx := 1.0 if cp.x < 100.0 else -1.0
				draw_rect(Rect2(cp + Vector2(-3.0, -2.0), Vector2(6.0, 4.0)), Color(0.85, 0.86, 0.9))
				draw_rect(Rect2(cp + Vector2(dirx * 3.0 - 1.0, 0.0), Vector2(2.0, 2.0)), Color(0.15, 0.15, 0.18))
				var led := Color(1.0, 0.1, 0.1) if int(_t * 2.0) % 2 == 0 else Color(0.4, 0.05, 0.05)
				draw_circle(cp + Vector2(-dirx * 2.0, -1.0), 0.7, led)
		if sec >= 2:
			# metallinpaljastinportti ulko-ovella
			var ex := exit_pos
			draw_rect(Rect2(ex.x - 11.0, ex.y - 22.0, 2.0, 14.0), Color(0.6, 0.62, 0.68))
			draw_rect(Rect2(ex.x + 9.0, ex.y - 22.0, 2.0, 14.0), Color(0.6, 0.62, 0.68))
			draw_rect(Rect2(ex.x - 11.0, ex.y - 23.0, 22.0, 2.0), Color(0.6, 0.62, 0.68))
			draw_circle(Vector2(ex.x, ex.y - 22.0), 0.9, Color(0.2, 1.0, 0.3))
		var wc := _lv("toilets")
		if wc >= 1:
			var d := Rect2(40.0, 193.0, 14.0, 14.0)
			var gold := wc >= 2
			draw_rect(d, Color(0.95, 0.92, 0.85) if gold else Color(0.85, 0.85, 0.88))
			draw_rect(d, Color(0.85, 0.7, 0.3) if gold else Color(0.4, 0.4, 0.45), false, 1.0)
			draw_circle(Vector2(d.end.x - 3.0, d.get_center().y), 0.9, Color(0.9, 0.75, 0.3) if gold else Color(0.5, 0.5, 0.55))
			_text(font, Vector2(d.position.x - 6.0, d.position.y - 3.0), "WC", d.size.x + 12.0, 6, Color(1.0, 0.9, 0.5) if gold else Color(0.85, 0.9, 1.0))
		var sauna := _lv("sauna")
		if sauna >= 1:
			var sd := Rect2(250.0, 193.0, 16.0, 14.0)
			draw_rect(sd, Color(0.6, 0.38, 0.18))
			for k in 4:
				draw_line(Vector2(sd.position.x + 1.0, sd.position.y + 3.0 + k * 3.0), Vector2(sd.end.x - 1.0, sd.position.y + 3.0 + k * 3.0), Color(0.45, 0.27, 0.12), 1.0)
			draw_rect(Rect2(sd.get_center().x - 2.0, sd.position.y + 2.0, 4.0, 4.0), Color(1.0, 0.75, 0.4, 0.6))
			for k in 3:
				var ph := fmod(_t * 0.5 + k * 0.33, 1.0)
				draw_circle(Vector2(sd.get_center().x - 4.0 + k * 4.0 + sin(_t + k) * 1.5, sd.position.y - 2.0 - ph * 10.0), 1.5 + ph * 2.0, Color(0.95, 0.95, 1.0, 0.35 * (1.0 - ph)))

	## Yläpuolen päivitykset: valaisimet, kaiuttimet, diskopallo, henkilökunta, esiintyjät.
	func _draw_top_upgrades(_font: Font) -> void:
		if not owned:
			return
		var dec := _lv("decor")
		if dec >= 1:
			# pöytäliinat ja kynttilät
			for tx: float in [64.0, 288.0]:
				var tc := Vector2(tx, 150.0)
				draw_circle(tc, 12.0, Color(0.95, 0.93, 0.88) if dec < 3 else Color(0.6, 0.08, 0.12))
				draw_arc(tc, 12.0, 0.0, TAU, 20, Color(0.85, 0.68, 0.3) if dec >= 3 else Color(0.8, 0.78, 0.72), 1.0)
				var fl := 0.8 + 0.2 * sin(_t * 9.0 + tx)
				draw_rect(Rect2(tc + Vector2(-1, -5), Vector2(2, 5)), Color(0.98, 0.96, 0.9))
				draw_circle(tc + Vector2(0, -6.5), 1.3 * fl, Color(1.0, 0.75, 0.3))
				draw_circle(tc + Vector2(0, -6.5), 9.0, Color(1.0, 0.75, 0.35, 0.08 * fl))
				draw_circle(tc + Vector2(4, 2), 1.8, Color(0.85, 0.92, 1.0, 0.7))
		if dec >= 1:
			for lx: float in [104.0, 146.0, 210.0, 250.0]:
				draw_rect(Rect2(lx - 3.0, 30.0, 6.0, 3.0), Color(0.85, 0.68, 0.3))
				draw_circle(Vector2(lx, 34.0), 7.0, Color(1.0, 0.85, 0.5, 0.12))
				draw_circle(Vector2(lx, 34.0), 1.8, Color(1.0, 0.95, 0.75))
		if dec >= 3:
			# kattokruunu salin keskellä
			var cc := Vector2(176.0, 118.0)
			draw_circle(cc, 22.0, Color(1.0, 0.9, 0.6, 0.06))
			draw_arc(cc, 9.0, 0.0, TAU, 20, Color(0.9, 0.75, 0.3), 1.5)
			for k in 8:
				var bp := cc + Vector2.from_angle(k * TAU / 8.0 + _t * 0.2) * 9.0
				draw_circle(bp, 1.6, Color(1.0, 0.97, 0.85))
				draw_circle(bp, 3.5, Color(1.0, 0.9, 0.6, 0.15))
			draw_circle(cc, 2.5, Color(0.95, 0.8, 0.4))
		var snd := _lv("sound")
		if snd >= 2 and music_on:
			# liikkuvat värispotit lattialla
			for k in 4:
				var ang := _t * (0.7 + k * 0.23) + k * 1.7
				var sp := (Vector2(424.0 + cos(ang) * 52.0, 108.0 + sin(ang * 1.3) * 30.0) if expanded >= 1
					else Vector2(176.0 + cos(ang) * 120.0, 135.0 + sin(ang * 1.3) * 40.0))
				var col := Color.from_hsv(fmod(k * 0.25 + _t * 0.05, 1.0), 0.8, 1.0, 0.12)
				draw_circle(sp, 22.0, col)
				draw_circle(sp, 12.0, Color(col.r, col.g, col.b, 0.12))
		if snd >= 3 and music_on:
			# laserit diskopallosta ja savukoneen usva
			var src := Vector2(424.0, 92.0) if expanded >= 1 else Vector2(227.0, 112.0)
			var reach := Vector2(90.0, 70.0) if expanded >= 1 else Vector2(220.0, 90.0)
			for k in 7:
				var la := _t * 1.2 + k * TAU / 7.0
				var end := src + Vector2(cos(la) * reach.x, sin(la) * reach.y)
				var lc := [Color(1.0, 0.1, 0.3), Color(0.2, 1.0, 0.3), Color(0.3, 0.6, 1.0)][k % 3] as Color
				draw_line(src, end, Color(lc.r, lc.g, lc.b, 0.35), 1.0)
			var haze := Rect2(352.0, 70.0, 144.0, 120.0) if expanded >= 1 else Rect2(TILE, 96.0, (ROOM_W - 2) * TILE, 96.0)
			draw_rect(haze, Color(0.8, 0.8, 0.95, 0.05 + 0.03 * sin(_t * 0.7)))
		if snd >= 1:
			for sx: float in [8.0, 344.0]:
				var sp := Rect2(sx - 5.0, 40.0, 10.0, 14.0)
				draw_rect(sp, Color(0.08, 0.08, 0.09))
				var pulse := (0.4 + 0.6 * absf(sin(_t * 7.0))) if music_on else 0.0
				draw_circle(sp.get_center() + Vector2(0, 2), 3.0 + pulse * 0.6, Color(0.25, 0.25, 0.28))
				draw_circle(sp.get_center() + Vector2(0, -4), 1.4, Color(0.25, 0.25, 0.28))
		if snd >= 3:
			# diskopallo tanssilattian yllä + valopilkut lattialla
			var db := Vector2(424.0, 92.0) if expanded >= 1 else Vector2(227.0, 112.0)
			draw_line(Vector2(db.x, 34.0 if expanded < 1 else 68.0), db + Vector2(0, -5), Color(0.6, 0.6, 0.6, 0.6), 1.0)
			draw_circle(db, 5.0, Color(0.8, 0.82, 0.88))
			for k in 6:
				var a := _t * 1.5 + k
				draw_rect(Rect2(db + Vector2(cos(a) * 3.0 - 0.8, sin(k * 1.3) * 3.0 - 0.8), Vector2(1.6, 1.6)), Color(1, 1, 1, 0.9))
			if music_on:
				for k in 10:
					var ang := _t * 0.9 + k * TAU / 10.0
					var sp2 := db + Vector2(cos(ang) * (26.0 + 8.0 * sin(k)), 18.0 + sin(ang) * 22.0 + 12.0)
					draw_circle(sp2, 1.5, Color.from_hsv(fmod(k * 0.13 + _t * 0.1, 1.0), 0.5, 1.0, 0.7))
		# Palkattu väki: lisäbaarimikot tiskin takana, tarjoilija salissa, kokki luukulla, DJ
		if _lv("h_dj") >= 1 and _lv("sound") >= 1:
			# DJ-pöytä ja DJ kuulokkeineen (tavallinen NPC-hahmo)
			var dj := Vector2(486.0, 104.0) if expanded >= 1 else Vector2(268.0, 112.0)
			var bob := absf(sin(_t * 5.0)) * 1.5 if music_on else 0.0
			_npc_sprite(dj + Vector2(0, 2 - bob), 15, 1, 0, 7)
			draw_arc(dj + Vector2(0, -11 - bob), 4.5, PI, TAU, 8, Color(0.1, 0.1, 0.1), 1.5)   # kuulokkeet
			draw_rect(Rect2(dj + Vector2(-10, 0), Vector2(20, 9)), Color(0.1, 0.1, 0.12))
			draw_circle(dj + Vector2(-5, 4), 2.5, Color(0.3, 0.3, 0.35))
			draw_circle(dj + Vector2(5, 4), 2.5, Color(0.3, 0.3, 0.35))
			draw_rect(Rect2(dj + Vector2(-1, 2), Vector2(2, 4)), Color(0.3, 1.0, 0.6))
		if _lv("h_waiter") >= 1:
			# tarjoilija kiertää salissa tarjotin kädessä
			var ph := _t * 0.5
			var wx := 150.0 + sin(ph) * 60.0
			var going_right := cos(ph) > 0.0
			var feet := Vector2(wx, 114.0)
			_staff(feet, CS.WAITER, 1, 3 if going_right else 0, 1 + int(_t * 6.0) % 2, 4)
			var tx := wx + (5.0 if going_right else -13.0)
			draw_rect(Rect2(tx, feet.y - 10.0, 8.0, 1.5), Color(0.75, 0.77, 0.8))
			draw_rect(Rect2(tx + 2.0, feet.y - 13.0, 2.0, 3.0), Color(0.95, 0.7, 0.2))
			draw_rect(Rect2(tx + 5.0, feet.y - 13.0, 2.0, 3.0), Color(0.95, 0.7, 0.2))
		if _lv("h_waiter") >= 2:
			# toinen tarjoilija kiertää alempana eri tahdissa
			var ph2 := _t * 0.42 + 2.0
			var wx2 := 170.0 + sin(ph2) * 70.0
			var right2 := cos(ph2) > 0.0
			_staff(Vector2(wx2, 168.0), CS.WAITER, 1, 3 if right2 else 0, 1 + int(_t * 6.0 + 1.0) % 2, 6)

	## Henkilökunta tiskin takana (piirretään ennen tiskiä: tiski peittää jalat).
	func _draw_staff_behind() -> void:
		if not owner_behind:
			_staff(Vector2(BARTENDER.x, 68.0), CS.WAITER, 0, 1, 0, 1)
		if owned and _lv("h_bartender") >= 1:
			_staff(Vector2(296.0, 68.0), CS.WAITER, 1, 1, 0, 2)
		if owned and _lv("h_bartender") >= 2 and not owner_behind:
			_staff(Vector2(232.0, 68.0), CS.WAITER, 2, 1, 0, 5)
		if owned and _lv("h_bartender") >= 3:
			_staff(Vector2(120.0, 68.0), CS.WAITER, 1, 1, 0, 8)
		if owned and _lv("h_bartender") >= 4:
			_staff(Vector2(264.0, 68.0), CS.WAITER, 2, 1, 0, 9)

	## Ääriviivan väri: tummalla tai kirjavalla lattialla vaalea, puulattialla tumma.
	func _outline_col() -> Color:
		return Color(1, 1, 1, 0.55) if owned and _lv("decor") >= 2 else Color(0.05, 0.03, 0.02, 0.45)

	## Henkilökunnan hahmo: NPC-kuva tarjoilija-/ovimies-/kokkiasussa. Räpsyttää silmiään,
	## hengittää ja saa ääriviivan, jotta erottuu kaikilla lattioilla. feet = jalkojen kohta.
	func _staff(feet: Vector2, outfit: int, kind: int, col: int = 1, step: int = 0, id: int = 0) -> void:
		_char_tex(feet, CS.staff(outfit, kind, col, step), id)

	func _npc_sprite(feet: Vector2, row: int, col: int, step: int, id: int) -> void:
		_char_tex(feet, CS.npc(col, row + step), id)

	func _char_tex(feet: Vector2, tex: Texture2D, id: int) -> void:
		if tex == null:
			return
		var draw_tex := tex
		if fmod(_t + id * 1.37, 3.6 + id * 0.45) < 0.12:
			var b := CS.blink(tex)
			if b:
				draw_tex = b
		var breath := 1.0 + 0.05 * maxf(sin(_t * 0.7 + id * 2.1), 0.0)
		var sz := tex.get_size()
		var r := Rect2(feet - Vector2(sz.x * 0.5, sz.y * breath), Vector2(sz.x, sz.y * breath))
		draw_set_transform(feet + Vector2(0, -0.5), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 5.0, Color(0, 0, 0, 0.28))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_texture_rect(draw_tex, r, false)

	## Teksti tummalla ääriviivalla: erottuu kaikilla lattioilla ja seinillä.
	func _text(font: Font, pos: Vector2, txt: String, width: float, fs: int, col: Color) -> void:
		TextFit.draw_outline(self, font, pos, txt, width, fs, 3, Color(0, 0, 0, 0.85))
		TextFit.draw(self, font, pos, txt, width, fs, col)

	func _stool(c: Vector2) -> void:
		draw_circle(c, 5.5, Color(0.1, 0.05, 0.05, 0.5))
		draw_circle(c, 5.0, Color(0.62, 0.1, 0.14))
		draw_arc(c, 5.0, 0.0, TAU, 14, Color(0.3, 0.04, 0.06), 1.0)

	# --- lämpimät valokiilat lattialla ---
	func _draw_light_pools() -> void:
		for lx in [96.0, 176.0, 256.0]:
			var c := Vector2(lx, 110.0)
			draw_circle(c, 56.0, Color(1.0, 0.8, 0.4, 0.035))
			draw_circle(c, 40.0, Color(1.0, 0.8, 0.4, 0.04))
			draw_circle(c, 24.0, Color(1.0, 0.85, 0.5, 0.05))
