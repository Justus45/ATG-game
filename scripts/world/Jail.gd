extends Node2D
## Putka. Pidätetty pelaaja viedään selliin kartan ulkopuolelle istumaan tuomionsa.
## Tuomion pituus lasketaan rikoksen vakavuudesta (PoliceManager / PolicePatrol).
##
##  - serve(): häivytys, siirto selliin, ajastin vasemmassa yläreunassa, vapautus kodin oven eteen
##  - sellissä pelaaja voi kävellä, mutta seinät pitävät hänet sisällä
##  - sellikaveri (E): vihjeitä pelin järjestelmistä
##  - punnerrukset (E lattialla, sitten vuorotellen vasen/oikea): jokainen punnerrus lyhentää
##    tuomiota sekunnilla, enintään 40 %
##  - takuut: B maksaa itsensä ulos (bail_per_second $ jokaisesta jäljellä olevasta sekunnista),
##    jos lompakossa on tarpeeksi rahaa
##
## PoliceManager luo tämän ja kutsuu setup():ia (sama rakenne kuin Home.gd).

const TILE := 16
const FLOOR_TILE := Vector2i(1, 4)
const WALL_TILE := Vector2i(19, 2)

const ROOM_W := 10
const ROOM_H := 8
## Eri paikassa kuin koti (-1000), asekauppa (-1800) ja baari (1400)
const INTERIOR_ORIGIN := Vector2(-1800.0, 400.0)
const SPAWN_CELL := Vector2i(5, 4)

## Onko pelaaja sellissä (minikartta piiloutuu)
var inside := false
## Onko tuomio käynnissä (siirtymät mukaan lukien)
var serving := false

var _saved_limits := {}
var _interior: Node2D
var _label: Label
var _bail_label: Label
## Takuiden hinta sekuntia kohden (PoliceManager asettaa)
var bail_per_second := 2.0
## Kuinka kauan sellissä pitää olla ennen kuin takuut voi maksaa (ettei näppäin lipsahda)
const BAIL_GRACE := 1.5
const PUSHUP_MAX_CUT := 0.4      ## punnerruksilla voi lyhentää enintään tämän osan tuomiosta
const PUSHUP_SECONDS := 1.0      ## yksi punnerrus lyhentää tuomiota näin monta sekuntia
## PoliceManager asettaa: sellikaverin hahmokuva tulee kaupungin NPC-tekstuureista
var city: Node = null
var _mate: Sprite2D
var _mate_row := 0
var _mate_bubble: Label
var _pushing := false
var _push_side := 0
var _push_idle := 0.0
var _push_cut := 0.0
var _push_reps := 0
var _player_ref: Node2D
var _spr_base := Vector2.ZERO

const TIPS := [
	"Talleta rahat pankkiin. Sammuessa tai putkassa lompakko kevenee, tili ei.",
	"Jos joku näkee rikoksen, hän soittaa. Lyö tai uhkaa todistajaa, tai häivy ennen kuin puhelu menee läpi.",
	"Lievästä jutusta selviää sakolla, jos lompakossa on rahaa.",
	"Kun poliisi jahtaa eikä näe sinua, vaihda autoa. Ne etsii väärää autoa.",
	"Kotona piilossa poliisi unohtaa sut nelinkertaisella vauhdilla.",
	"Krapulaan auttaa tasoittava. Tai sairaalan kipulääke.",
	"Portsari heittää ulos, jos tappelet liikaa. Toisesta kerrasta tulee porttikielto.",
	"Ne rähinöitsijät muistaa sut. Yöllä kadulla voi tulla kosto.",
	"Taksilla saa rehellistä rahaa. Hyppää autoon ja paina T.",
	"Baarin kulmalla notkuu Kalle. Sillä on pimeitä keikkoja, mutta partiot on vaarallisia.",
	"Vuokra erääntyy viikoittain. Jos et maksa, vuokranantaja vaihtaa lukot.",
	"Syö välillä. Nälkäisenä et jaksa juosta, ja lopulta pyörryt.",
	"Torju F:llä tai hiiren oikealla. Shift pohjassa juoksee. Kolmas lyönti putkeen on koukku.",
	"Haulikon saa asekaupasta. Lähietäisyydellä se on paha.",
	"Neljällä tähdellä tulee SWAT, viidellä armeija. Älä mene sinne asti.",
	"Joka pidätys pidentää seuraavaa tuomiota. Poliisi alkaa tunnistaa sut.",
	"Ostin kerran oman baarin... unessa. 5000 taalaa kiinteistövälittäjältä.",
	"Punnerra, niin pääset aikaisemmin. Vartijat tykkää siitä.",
]


func setup(tile_set: TileSet, source_id: int) -> void:
	add_to_group("jail")
	global_position = Vector2.ZERO
	if not InputMap.has_action("bail"):
		InputMap.add_action("bail")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_B
		InputMap.action_add_event("bail", ev)
	_build_interior(tile_set, source_id)
	_build_cellmate()

	var layer := CanvasLayer.new()
	layer.layer = 55
	add_child(layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 7)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_label)
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.offset_left = -200.0
	_label.offset_right = 200.0
	_label.offset_top = 24.0
	_label.offset_bottom = 70.0
	_label.hide()

	_bail_label = Label.new()
	_bail_label.add_theme_font_size_override("font_size", 18)
	_bail_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_bail_label.add_theme_constant_override("outline_size", 6)
	_bail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_bail_label)
	_bail_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bail_label.offset_left = -240.0
	_bail_label.offset_right = 240.0
	_bail_label.clip_text = true
	_bail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_bail_label.offset_top = 74.0
	_bail_label.offset_bottom = 102.0
	_bail_label.hide()


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
	floor_layer.modulate = Color(0.72, 0.76, 0.85)   # kylmä, harmaa sävy
	_interior.add_child(floor_layer)
	for y in ROOM_H:
		for x in ROOM_W:
			var wall := x == 0 or x == ROOM_W - 1 or y <= 1 or y == ROOM_H - 1
			floor_layer.set_cell(Vector2i(x, y), source_id, WALL_TILE if wall else FLOOR_TILE)

	var view := CellView.new()
	view.z_index = 5
	_interior.add_child(view)

	# Törmäykset: ulkoseinät + kalusteet (huoneen paikallisissa koordinaateissa)
	var body := StaticBody2D.new()
	_interior.add_child(body)
	var solids: Array[Rect2] = [
		Rect2(0, 0, ROOM_W * TILE, 2 * TILE),                    # takaseinä
		Rect2(0, 0, TILE, ROOM_H * TILE),                        # vasen seinä
		Rect2((ROOM_W - 1) * TILE, 0, TILE, ROOM_H * TILE),      # oikea seinä
		Rect2(0, (ROOM_H - 1) * TILE, ROOM_W * TILE, TILE),      # ritilät edessä
	]
	solids.append_array(CellView.SOLIDS)
	solids.append(Rect2(118, 80, 12, 10))   # sellikaveri
	for r in solids:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = r.size
		cs.shape = shape
		cs.position = r.get_center()
		body.add_child(cs)


# ----------------------------------------------------------------------------
#  TUOMION ISTUMINEN
# ----------------------------------------------------------------------------
## Vie pelaajan selliin `seconds` sekunniksi ja vapauttaa hänet kodin oven eteen.
## sober = pelaaja selviää putkassa (esim. rattijuopumus).
func serve(player: Node2D, seconds: int, intro: String, release_at: Vector2, sober: bool = false) -> void:
	if serving:
		return
	serving = true
	player.set("police_locked", true)   # lukossa siirtymän ajan
	var fx := player.get_node_or_null("DrunkFX")
	if fx:
		await fx.fade_to(1.0, 0.6)

	inside = true
	_set_camera_limits(true)
	_move_player(player, _cell_center(SPAWN_CELL))
	Sfx.play_ui("clang", -2.0)
	_say(intro + "  Tuomio: %d s." % seconds, 4.5)
	_label.show()
	_bail_label.show()
	if fx:
		fx.fade_to(0.0, 0.6)   # ei await: ajastin alkaa heti
	player.set("police_locked", false)

	var left := float(seconds)
	var elapsed := 0.0
	var paid := 0
	while left > 0.0:
		_label.text = "PUTKA  %d:%02d" % [int(ceil(left)) / 60, int(ceil(left)) % 60]
		var bail := bail_for(left)
		var money: int = player.get("money")
		if money >= bail:
			_bail_label.text = "Paina B maksaaksesi takuut: %d $" % bail
			_bail_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55))
		else:
			_bail_label.text = "Takuut %d $  (lompakossa %d $)" % [bail, money]
			_bail_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		await get_tree().process_frame
		var dt := get_process_delta_time()
		left -= dt
		elapsed += dt
		if _pushing:
			left -= _update_pushups(player, dt, float(seconds))
		elif elapsed > BAIL_GRACE and Input.is_action_just_pressed("bail"):
			bail = bail_for(left)
			money = player.get("money")
			if money >= bail and player.has_method("add_money"):
				player.add_money(-bail)
				paid = bail
				break
			Sfx.play_ui("denied", -4.0)
			_say("Rahat eivät riitä takuisiin (%d $ / %d $)." % [money, bail], 2.0)
	_label.hide()
	_bail_label.hide()
	if _pushing:
		_stop_pushups(player)

	player.set("police_locked", true)
	if fx:
		await fx.fade_to(1.0, 0.6)
	inside = false
	_set_camera_limits(false)
	_move_player(player, release_at)
	Sfx.play_ui("clang", -6.0, 1.15)
	if sober and player.has_method("sober_up"):
		player.sober_up()
	var back := ""
	if Game.stored_weapon != "" and player.has_method("has_weapon") and not player.has_weapon():
		player.held_weapon.equip(Game.stored_weapon, "down")
		back = " Sait aseesi takaisin."
	Game.stored_weapon = ""
	if paid > 0:
		_say("Maksoit takuut %d $. Vapautettu.%s" % [paid, back], 3.0)
	elif _push_reps > 0:
		_say("Vapautettu. Punnerrukset lyhensivät tuomiota %d s.%s" % [int(_push_cut), back], 3.5)
	else:
		_say("Vapautettu. Pidä itsesi kurissa.%s" % back, 3.0)
	_push_reps = 0
	_push_cut = 0.0
	if fx:
		await fx.fade_to(0.0, 0.8)
	player.set("police_locked", false)
	serving = false


# ----------------------------------------------------------------------------
#  SELLIKAVERI JA PUNNERRUKSET
# ----------------------------------------------------------------------------
func _build_cellmate() -> void:
	_mate = Sprite2D.new()
	_mate.offset = Vector2(0, -4)
	_mate.z_index = 6
	_mate.position = Vector2(124, 88)
	_interior.add_child(_mate)
	_mate_row = (randi() % 6) * 3
	_mate_bubble = Label.new()
	_mate_bubble.add_theme_font_size_override("font_size", 7)
	_mate_bubble.add_theme_color_override("font_outline_color", Color.BLACK)
	_mate_bubble.add_theme_constant_override("outline_size", 3)
	_mate_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mate_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mate_bubble.size = Vector2(130, 40)
	_mate_bubble.position = Vector2(-100, -52)
	_mate_bubble.z_index = 40
	_mate_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mate.add_child(_mate_bubble)
	_mate_bubble.hide()
	InteractSpot.create(self, INTERIOR_ORIGIN + Vector2(110, 90), Vector2(22, 18),
		"Paina E jutellaksesi sellikaverin kanssa", _talk)
	InteractSpot.create(self, INTERIOR_ORIGIN + Vector2(70, 98), Vector2(26, 18),
		"Paina E tehdäksesi punnerruksia (lyhentää tuomiota)", _begin_pushups)


func _process(_delta: float) -> void:
	if _mate and _mate.texture == null and city and city.has_method("npc_tex"):
		_mate.texture = city.npc_tex(_mate_row, Vector2i.LEFT, 0)


func _talk(_player: Node2D) -> void:
	_mate_bubble.text = TIPS[randi() % TIPS.size()]
	_mate_bubble.show()
	var id := Time.get_ticks_msec()
	_mate_bubble.set_meta("id", id)
	await get_tree().create_timer(5.0).timeout
	if _mate_bubble.get_meta("id", 0) == id:
		_mate_bubble.hide()


func _begin_pushups(player: Node2D) -> void:
	if not serving or _pushing:
		return
	_pushing = true
	_push_side = 0
	_push_idle = 0.0
	_player_ref = player
	player.set("police_locked", true)
	var spr := player.get_node_or_null("AnimatedSprite2D") as Node2D
	if spr:
		_spr_base = spr.position
		spr.rotation = deg_to_rad(90.0)
	_say("Punnerrukset: paina vuorotellen VASEN ja OIKEA. E lopettaa.", 3.0)


## Palauttaa sekunnit, jotka tuomiosta lähtevät tällä ruudulla.
func _update_pushups(player: Node2D, dt: float, total: float) -> float:
	_push_idle += dt
	if Input.is_action_just_pressed("interact") or _push_idle > 4.0:
		_stop_pushups(player)
		return 0.0
	var side := 0
	if Input.is_action_just_pressed("ui_left"):
		side = -1
	elif Input.is_action_just_pressed("ui_right"):
		side = 1
	if side == 0 or side == _push_side:
		return 0.0
	_push_side = side
	_push_idle = 0.0
	var spr := player.get_node_or_null("AnimatedSprite2D") as Node2D
	if spr:
		spr.position = _spr_base + Vector2(0.0, -2.0 if side < 0 else 0.0)
	if side > 0:
		return 0.0   # yksi punnerrus = alas (vasen) + ylös (oikea)
	_push_reps += 1
	Game.fatigue = minf(Game.fatigue + 0.6, 100.0)
	Sfx.play_ui("step", -10.0, 0.8)
	if _push_cut >= total * PUSHUP_MAX_CUT:
		if _push_reps % 5 == 0:
			_say("Vartija: \"Riittää jo, Rambo.\" (ei enää lyhennystä)", 2.0)
		return 0.0
	_push_cut += PUSHUP_SECONDS
	if _push_reps % 5 == 0:
		_say("%d punnerrusta! Tuomio lyheni %d s." % [_push_reps, int(_push_cut)], 1.5)
	return PUSHUP_SECONDS


func _stop_pushups(player: Node2D) -> void:
	_pushing = false
	var spr := player.get_node_or_null("AnimatedSprite2D") as Node2D
	if spr:
		spr.rotation = 0.0
		spr.position = _spr_base
	player.set("police_locked", false)


## Takuiden hinta jäljellä olevasta tuomiosta.
func bail_for(seconds_left: float) -> int:
	return maxi(int(ceil(seconds_left * bail_per_second)), 1)


func _say(text: String, seconds: float) -> void:
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(text, seconds)


func _move_player(player: Node2D, target: Vector2) -> void:
	var col := player.get_node_or_null("CollisionShape2D") as Node2D
	var off := col.position if col else Vector2.ZERO
	player.global_position = target - off
	if "velocity" in player:
		player.velocity = Vector2.ZERO
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


## Sellin kalusteet ja ritilät.
class CellView extends Node2D:
	const BUNK := Rect2(20, 36, 22, 50)
	const TOILET := Rect2(112, 36, 18, 16)
	const SOLIDS: Array[Rect2] = [BUNK, TOILET]

	func _draw() -> void:
		var font := ThemeDB.fallback_font

		# Ikkuna takaseinällä (ritilöity)
		var win := Rect2(66, 6, 28, 16)
		draw_rect(win, Color(0.45, 0.62, 0.85))
		for i in 4:
			draw_line(Vector2(win.position.x + 5.0 + i * 6.0, win.position.y),
				Vector2(win.position.x + 5.0 + i * 6.0, win.end.y), Color(0.15, 0.15, 0.18), 1.0)
		draw_rect(win, Color(0.15, 0.15, 0.18), false, 1.0)

		# Punkka
		draw_rect(BUNK, Color(0.38, 0.38, 0.42))
		draw_rect(Rect2(BUNK.position + Vector2(2, 2), Vector2(BUNK.size.x - 4, 14)), Color(0.85, 0.85, 0.8))
		draw_rect(Rect2(BUNK.position + Vector2(2, 18), Vector2(BUNK.size.x - 4, BUNK.size.y - 20)), Color(0.28, 0.38, 0.55))
		draw_rect(BUNK, Color(0.1, 0.1, 0.12), false, 1.0)

		# Vessa
		draw_rect(TOILET, Color(0.8, 0.82, 0.85))
		draw_rect(Rect2(TOILET.position + Vector2(3, 7), Vector2(12, 8)), Color(0.55, 0.6, 0.68))
		draw_rect(TOILET, Color(0.2, 0.2, 0.25), false, 1.0)

		# Ritilät edessä (alin seinärivi)
		var by := 7.0 * 16.0
		draw_rect(Rect2(0, by, 160, 16), Color(0.1, 0.1, 0.13, 0.55))
		for i in 21:
			draw_line(Vector2(i * 8.0, by - 2.0), Vector2(i * 8.0, by + 16.0), Color(0.55, 0.57, 0.62), 2.0)
		draw_line(Vector2(0, by), Vector2(160, by), Color(0.65, 0.67, 0.72), 2.0)

		# Kyltti
		TextFit.draw(self, font, Vector2(52, 52), "PUTKA", 56, 9, Color(1, 1, 1, 0.35))
