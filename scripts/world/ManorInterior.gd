extends Node2D
## KARTANON SISÄTILA (iso huone kartan ulkopuolella, ServiceBuilding "manor" luo tämän).
##  - makuuhuone: kultainen pyöreä parisänky (nuku + tallenna, Home._sleep)
##  - olohuone: takka, flyygeli, valkoinen nahkasohva, kattokruunut, asekaappi, hovimestari Hemmo
##  - paniikkihuone kirjahyllyn takana (etsintäkuulutus pois kerran päivässä)
##  - baari: tiski täynnä shampanjaa, shampanjatorni, jääkaappi (Home), lasi kuplivaa (E)
##  - POREALLAS: kauniit naiset lillumassa shampanjalasit kädessä (E = hyppää poreisiin)
##  - juhlavieraat juttelevat, kun kävelet ohi
## Kaikki kodin tavarat ovat täällä: jääkaappi, sänky, keittiöveitsi, asekaappi, saaliit.

const CS := preload("res://scripts/core/CharSprites.gd")
const WEAPON_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/weapons/weapon_pickup.tscn")
const GUN_CABINET := preload("res://scripts/world/GunCabinet.gd")
const W := 480.0
const H := 288.0
const ORIGIN := Vector2(-5600.0, -1400.0)

const BED := Rect2(28.0, 50.0, 72.0, 52.0)
const NIGHTSTAND_L := Rect2(16.0, 52.0, 10.0, 12.0)
const NIGHTSTAND_R := Rect2(102.0, 52.0, 10.0, 12.0)
const PIANO := Rect2(140.0, 52.0, 40.0, 26.0)
const FIREPLACE := Rect2(208.0, 40.0, 64.0, 8.0)
const SOFA := Rect2(196.0, 92.0, 88.0, 16.0)
const COFFEE := Rect2(214.0, 116.0, 52.0, 12.0)
const BACKBAR := Rect2(332.0, 40.0, 86.0, 12.0)
const FRIDGE := Rect2(424.0, 40.0, 30.0, 14.0)
const BAR := Rect2(336.0, 96.0, 124.0, 14.0)
const TOWER := Rect2(296.0, 128.0, 20.0, 12.0)
const POOL := Rect2(112.0, 164.0, 160.0, 84.0)
const PALMS := [Vector2(26.0, 262.0), Vector2(454.0, 262.0), Vector2(26.0, 150.0), Vector2(454.0, 150.0)]
const PHONE := Vector2(296.0, 22.0)
## Juhlavieraat: [paikka, hiukset, mekko, tila, suunta]
const LADIES := [
	[Vector2(150.0, 200.0), Color(0.98, 0.85, 0.45), Color(0.95, 0.75, 0.25), "pool", 3],
	[Vector2(232.0, 214.0), Color(0.15, 0.12, 0.12), Color(0.8, 0.1, 0.15), "pool", 0],
	[Vector2(190.0, 232.0), Color(0.6, 0.2, 0.1), Color(0.95, 0.45, 0.65), "pool", 2],
	[Vector2(366.0, 128.0), Color(0.45, 0.25, 0.12), Color(0.1, 0.55, 0.35), "stand", 1],
	[Vector2(414.0, 132.0), Color(0.92, 0.9, 0.85), Color(0.12, 0.1, 0.14), "stand", 0],
	[Vector2(222.0, 102.0), Color(0.15, 0.12, 0.12), Color(0.85, 0.7, 0.3), "sofa", 1],
	[Vector2(310.0, 196.0), Color(0.98, 0.85, 0.45), Color(0.3, 0.15, 0.6), "dance", 1],
]
const LINES := ["Kippis, komistus!", "Ihana kartano!", "Lisää kuplivaa!", "Tuu poreisiin!", "Mitkä bileet!", "Skool!", "Sä oot legenda!"]

var building: Node2D = null
var kind := "manor"
var inside := false
var origin := ORIGIN
var _busy := false
var _saved_limits := {}
var _fade: ColorRect
var _view: Node2D
var _knife: Node = null
var _ring_t := 0.0


func setup(b: Node2D) -> void:
	building = b
	add_to_group("indoor_room")
	add_to_group("manor_interior")
	position = origin
	z_index = -10
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04)
	bg.position = Vector2(-1500.0, -1500.0)
	bg.size = Vector2(3000.0 + W, 3000.0 + H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -20
	add_child(bg)
	_view = ManorView.new()
	_view.set("room", self)
	_view.set("L", layout())
	add_child(_view)
	for r: Rect2 in [Rect2(0, 0, W, 40), Rect2(0, 0, 16, H), Rect2(W - 16, 0, 16, H), Rect2(0, H - 16, W, 16),
			BED, NIGHTSTAND_L, NIGHTSTAND_R, PIANO, FIREPLACE, SOFA, COFFEE, BACKBAR, FRIDGE, BAR, TOWER, POOL]:
		_block(r)
	for p: Vector2 in PALMS:
		_block(Rect2(p - Vector2(6.0, 6.0), Vector2(12.0, 8.0)))
	# Asekaappi takaseinällä takan oikealla puolella (sama sisältö kuin vanhassa kodissa)
	var gc := GUN_CABINET.new()
	gc.z_index = 1
	add_child(gc)
	gc.setup(origin + Vector2(278.0, 40.0), Vector2(20.0, 14.0), origin + Vector2(288.0, 62.0))
	var home := get_tree().get_first_node_in_group("home")
	InteractSpot.create(self, origin + Vector2(W * 0.5, H - 26.0), Vector2(26.0, 18.0), "Paina E poistuaksesi", func(p: Node2D) -> void: leave(p))
	InteractSpot.create(self, origin + Vector2(64.0, 110.0), Vector2(64.0, 12.0), "Paina E: nuku kultaisessa sängyssä (tallentaa)", _sleep)
	InteractSpot.create(self, origin + Vector2(439.0, 60.0), Vector2(30.0, 12.0), _fridge_prompt, _eat)
	# Hovimestari Hemmo oven oikealla puolella ja paniikkihuone (kirjahylly vasemmalla seinällä)
	_butler = ButlerView.new()
	_butler.z_index = 1
	add_child(_butler)
	_butler.position = BUTLER
	InteractSpot.create(self, origin + BUTLER + Vector2(0.0, 10.0), Vector2(26.0, 14.0), "Paina E: hovimestari Hemmo", _butler_menu)
	_block(PANIC)
	InteractSpot.create(self, origin + Vector2(PANIC.end.x + 9.0, PANIC.get_center().y), Vector2(14.0, 26.0), _panic_prompt, _panic_room)
	InteractSpot.create(self, origin + Vector2(398.0, 118.0), Vector2(110.0, 12.0), "Paina E: kaada lasi shampanjaa", _champagne)
	InteractSpot.create(self, origin + Vector2(192.0, 256.0), Vector2(70.0, 12.0), "Paina E: hyppää poreammeeseen naisten seuraan", _jacuzzi)
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)


## Huoneen mitat piirtonäkymälle (sisäluokka ei lue ulkoluokan vakioita)
func layout() -> Dictionary:
	return {"BED": BED, "NIGHTSTAND_L": NIGHTSTAND_L, "NIGHTSTAND_R": NIGHTSTAND_R, "PIANO": PIANO,
		"FIREPLACE": FIREPLACE, "SOFA": SOFA, "COFFEE": COFFEE, "BACKBAR": BACKBAR, "FRIDGE": FRIDGE,
		"BAR": BAR, "TOWER": TOWER, "POOL": POOL, "PALMS": PALMS, "PHONE": PHONE, "LADIES": LADIES, "LINES": LINES}


func _block(r: Rect2) -> void:
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	body.position = r.get_center()


func _home() -> Node:
	return get_tree().get_first_node_in_group("home")


func _process(delta: float) -> void:
	if not inside or _busy:
		return
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p and p.global_position.distance_to(origin) > 1400.0:
		inside = false
		_set_camera_limits(false)
		return


# ----------------------------------------------------------------------------
#  SISÄÄN JA ULOS
# ----------------------------------------------------------------------------
func enter(player: Node2D) -> void:
	await _move(player, true)


## Pelin alussa (tallennus ladattu): kartanon omistaja herää kultaisen sängyn vierestä.
func start_inside(player: Node2D) -> void:
	if player == null:
		return
	_fade.color.a = 1.0
	inside = true
	_set_camera_limits(true)
	_move_player(player, origin + Vector2(BED.end.x + 16.0, BED.get_center().y + 14.0))
	_respawn_knife()
	await get_tree().create_timer(0.15).timeout
	await _fade_to(0.0)


func leave(player: Node2D) -> void:
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
		_respawn_knife()
		var home := _home()
		if home and home.has_method("_deliver_loot"):
			home.call("_deliver_loot", self, origin + Vector2(300.0, 160.0))
	else:
		inside = false
		_set_camera_limits(false)
		_move_player(player, (building.get("door_px") as Vector2) + Vector2(0.0, 28.0))
	await _fade_to(0.0)
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	_busy = false


func _fade_to(alpha: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, 0.2)
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
		var r := Rect2(origin, Vector2(W, H)).grow(24.0)
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
#  TAVARAT JA TEKEMISET
# ----------------------------------------------------------------------------
func _sleep(player: Node2D) -> void:
	var home := _home()
	if home and home.has_method("_sleep"):
		home.call("_sleep", player)


func _fridge_prompt() -> String:
	var home := _home()
	return str(home.call("_fridge_prompt")) if home else ""


func _eat(player: Node2D) -> void:
	var home := _home()
	if home:
		home.call("_eat", player)


# ----------------------------------------------------------------------------
#  KARTANON EDUT: hovimestari (ilmainen hoito, hieronta, auto oven eteen),
#  paniikkihuone (etsintäkuulutus nollautuu kerran päivässä) ja päivittäinen tuotto
#  (Game.MANOR_INCOME, Game._on_new_day). Jääkaappi täyttyy joka aamu.
# ----------------------------------------------------------------------------
const BUTLER := Vector2(318.0, 78.0)   ## olohuoneessa asekaapin ja baaritiskin välissä
const PANIC := Rect2(16.0, 112.0, 14.0, 30.0)
var _butler: Node2D = null


func _menu(title: String, opts: Array, cb: Callable) -> void:
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud and hud.has_method("show_menu"):
		hud.show_menu(title, opts, cb)


func _butler_menu(player: Node2D) -> void:
	var massage_ok := int(Game.story.get("manor_massage_day", -1)) != Game.day
	var opts: Array = [
		"Hoida haavat ja krapula (ilmainen)",
		"Hieronta – vitutus ja väsymys pois%s" % ("" if massage_ok else " (huomenna uudestaan)"),
		"Tuo autoni kartanon eteen",
		"Miten kartanolla menee?",
	]
	_menu("HOVIMESTARI HEMMO\n\"Herra kutsui? Kartanon tuotto tänään %d $, jääkaapissa %d annosta.\"" % [Game.MANOR_INCOME, Game.fridge],
		opts, _butler_choice.bind(player))


func _butler_choice(i: int, player: Node2D) -> void:
	match i:
		0:
			player.hp = player.get_max_hp()
			player.hangover = 0.0
			if player.has_method("_refresh_health_hud"):
				player._refresh_health_hud()
			if player.has_method("_refresh_drunk_hud"):
				player._refresh_drunk_hud(true)
			Sfx.play_ui("clink", -6.0, 1.2)
			Game.msg("Hemmo sitoi haavat ja toi särkylääkettä. \"Herra on taas kuin uusi.\"", 3.0)
		1:
			if int(Game.story.get("manor_massage_day", -1)) == Game.day:
				Game.msg("Hemmo: \"Hierojat tulevat taas huomenna, herra.\"", 2.5)
				return
			Game.story["manor_massage_day"] = Game.day
			Game.add_vitutus(-100.0)
			Game.fatigue = maxf(Game.fatigue - 40.0, 0.0)
			Game.skip_minutes(30.0)
			Sfx.play_ui("clink", -8.0, 0.9)
			Game.msg("Puolen tunnin hieronta takan ääressä. Vitutus on poissa ja olo levännyt.", 3.0)
		2:
			_summon_car_menu(player)
		3:
			Game.msg("Hemmo: \"Sijoitukset ja vuokralaiset tuottavat %d $ päivässä, jääkaappi täytetään aamuisin, ja paniikkihuone kirjahyllyn takana pitää kytät loitolla.\"" % Game.MANOR_INCOME, 5.0)


func _summon_car_menu(_player: Node2D) -> void:
	var garage: Node = building.get("garage") if building else null
	if garage == null or not garage.has_method("owned_vehicles"):
		return
	var cars: Array = []
	var opts: Array = []
	for v in garage.call("owned_vehicles"):
		if is_instance_valid(v) and not Game.flag(v, "is_driving"):
			cars.append(v)
			opts.append(str(v.get("display_name")))
	if cars.is_empty():
		Game.msg("Hemmo: \"Herralla ei ole yhtään ehjää autoa noudettavaksi.\"", 2.5)
		return
	var cb := func(k: int) -> void:
		if k < 0 or k >= cars.size() or not is_instance_valid(cars[k]):
			return
		var car: Node2D = cars[k]
		var spot: Vector2 = building.call("parking_spot", 0)
		car.call("park_at", spot, &"car_down")
		Sfx.play_ui("clink", -8.0, 1.0)
		Game.msg("Hemmo: \"%s odottaa kartanon portailla, avaimet virtalukossa.\"" % str(car.get("display_name")), 3.0)
	_menu("HOVIMESTARI HEMMO – AUTO OVEN ETEEN", opts, cb)


func _panic_prompt() -> String:
	return "Paina E: paniikkihuone (kirjahyllyn takana)"


func _panic_room(player: Node2D) -> void:
	var pm := get_tree().get_first_node_in_group("police_manager")
	if pm == null or int(pm.get("wanted")) <= 0:
		Game.msg("Paniikkihuone: teräsovi, ruokaa ja valvontakamerat. Kun kytät on perässä, täällä ne kadottaa jäljet.", 3.5)
		return
	if int(Game.story.get("panic_day", -1)) == Game.day:
		Game.msg("Paniikkihuoneen ovi on lukittu ajastimella – käytössä taas huomenna.", 2.5)
		return
	if _busy:
		return
	Game.story["panic_day"] = Game.day
	_busy = true
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	Sfx.play("door_close", player.global_position, -2.0, 0.05, 0.6)
	await _fade_to(1.0)
	Game.skip_minutes(60.0)
	pm.set("heat", 0)
	pm.set("calm_timer", 0.0)
	if pm.has_method("_set_searching"):
		pm.call("_set_searching", false)
	pm.call("_set_wanted", 0)
	if pm.has_method("_stand_down"):
		pm.call("_stand_down")
	await get_tree().create_timer(0.6).timeout
	await _fade_to(0.0)
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	_busy = false
	Game.msg("Tunnin päästä teräsovi aukeaa. Poliisi luovutti – etsintäkuulutus on poissa.", 3.5)


## Hovimestari oven vieressä: frakki, tarjotin ja kumarrus kun pelaaja tulee lähelle.
class ButlerView extends Node2D:
	const CS3 := preload("res://scripts/core/CharSprites.gd")
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var tex := CS3.staff(CS3.WAITER, 0, 1, 0)
		if tex == null:
			return
		var p := get_tree().get_first_node_in_group("player") as Node2D
		var near := p != null and p.global_position.distance_to(global_position) < 40.0
		var bow := 1.0
		draw_set_transform(Vector2(0, -0.5), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 5.0, Color(0, 0, 0, 0.25))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_texture_rect(tex, Rect2(Vector2(-8.0, -16.0 * bow), Vector2(16.0, 16.0 * bow)), false)
		# hopeatarjotin ja shampanjalasi
		draw_line(Vector2(5.0, -7.0), Vector2(11.0, -7.0), Color(0.85, 0.86, 0.9), 1.4)
		draw_rect(Rect2(Vector2(7.5, -10.5), Vector2(1.2, 3.0)), Color(1.0, 0.9, 0.55, 0.9))
		if near:
			var font := ThemeDB.fallback_font
			var txt := "Herra kutsui?"
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x + 6.0
			var r := Rect2(-tw * 0.5, -28.0, tw, 9.0)
			draw_rect(r, Color(1, 1, 1, 0.92))
			draw_string(font, Vector2(r.position.x + 3.0, r.end.y - 2.2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.1, 0.1, 0.12))


func _champagne(player: Node2D) -> void:
	Sfx.play("clink", player.global_position, -6.0, 0.1, 1.3)
	Sfx.play("gulp", player.global_position, -6.0, 0.1)
	if player.has_method("drink"):
		player.drink(0.15, 3.0)
	Game.add_vitutus(-6.0)
	Game.msg(["Kuplivaa! Elämä on hyvää.", "Skool! Shampanja kihelmöi nenässä.", "Vielä yks lasi... tai kaks."][randi() % 3], 2.0)


func _jacuzzi(player: Node2D) -> void:
	if _busy:
		return
	_busy = true
	player.set_physics_process(false)
	await _fade_to(1.0)
	Game.skip_minutes(45.0)
	Game.add_vitutus(-40.0)
	Game.fatigue = maxf(Game.fatigue - 15.0, 0.0)
	if player.has_method("drink"):
		player.drink(0.3, 4.0)
	Sfx.play("gulp", player.global_position, -8.0, 0.1)
	await get_tree().create_timer(0.5).timeout
	await _fade_to(0.0)
	player.set_physics_process(true)
	_busy = false
	Game.msg("Lilluit poreissa shampanjalasi kädessä, naiset nauroivat vitseillesi. Vitutus on poissa.", 3.5)


## Keittiöveitsi baaritiskin päädyssä (kuten vanhassa kodissa).
func _respawn_knife() -> void:
	if is_instance_valid(_knife):
		return
	if not Game.fixture_should_spawn("manor_knife"):
		return
	_knife = WEAPON_PICKUP_SCENE.instantiate()
	_knife.set("weapon_id", "knife")
	_knife.set("fixture", "manor_knife")
	add_child(_knife)
	(_knife as Node2D).global_position = origin + Vector2(456.0, 70.0)


# ----------------------------------------------------------------------------
#  PIIRTO
# ----------------------------------------------------------------------------
class ManorView extends Node2D:
	const CS2 := preload("res://scripts/core/CharSprites.gd")
	const VW := 480.0
	const VH := 288.0
	var room: Node2D = null
	var L := {}
	var _t := 0.0
	var _talk := {}      # vieras -> [teksti, aika]
	var _talk_cd := 0.0

	const GOLD := Color(0.88, 0.72, 0.3)
	const BOTTLE := Color(0.12, 0.3, 0.16)
	const FOIL := Color(0.95, 0.82, 0.4)

	func _process(delta: float) -> void:
		_t += delta
		if room == null or not room.get("inside"):
			return
		# vieraat juttelevat, kun pelaaja kulkee ohi
		_talk_cd -= delta
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if p and _talk_cd <= 0.0:
			var lp := p.global_position - global_position
			for i in L.LADIES.size():
				var l: Array = L.LADIES[i]
				if lp.distance_to(l[0]) < 40.0 and not _talk.has(i):
					_talk[i] = [L.LINES[randi() % L.LINES.size()], 2.2]
					_talk_cd = 1.6
					break
		for k in _talk.keys():
			var v: Array = _talk[k]
			v[1] = float(v[1]) - delta
			if float(v[1]) <= 0.0:
				_talk.erase(k)
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var night := Game.darkness()
		_floor()
		_walls(night)
		_bedroom()
		_living()
		_bar()
		_pool()
		for p: Vector2 in L.PALMS:
			_palm(p)
		# kattokruunut
		for cx: float in [96.0, 240.0, 384.0]:
			draw_circle(Vector2(cx, 120.0), 70.0, Color(1.0, 0.9, 0.6, 0.05))
		# vieraat
		for i in L.LADIES.size():
			_lady(i, L.LADIES[i])
		# ovi
		var d := Rect2(VW * 0.5 - 14.0, VH - 16.0, 28.0, 16.0)
		draw_rect(d, Color(0.35, 0.2, 0.1))
		draw_rect(d, GOLD, false, 1.0)
		draw_line(Vector2(VW * 0.5, d.position.y), Vector2(VW * 0.5, d.end.y), GOLD, 1.0)
		TextFit.draw(self, font, Vector2(VW * 0.5 - 30.0, VH - 20.0), "ULOS", 60.0, 7, Color(1, 1, 1, 0.75))

	func _floor() -> void:
		var fr := Rect2(16, 40, VW - 32, VH - 56)
		draw_rect(fr, Color(0.93, 0.91, 0.86))
		var y := fr.position.y
		var r := 0
		while y < fr.end.y:
			var x := fr.position.x
			var c := 0
			while x < fr.end.x:
				if (r + c) % 2 == 0:
					draw_rect(Rect2(x, y, minf(24.0, fr.end.x - x), minf(24.0, fr.end.y - y)), Color(0.85, 0.82, 0.76))
				x += 24.0
				c += 1
			y += 24.0
			r += 1
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for k in 40:
			var a := Vector2(rng.randf_range(fr.position.x, fr.end.x), rng.randf_range(fr.position.y, fr.end.y))
			draw_line(a, a + Vector2(rng.randf_range(-16, 16), rng.randf_range(-6, 6)), Color(0.8, 0.7, 0.45, 0.35), 1.0)
		# punainen matto ovelta saliin
		var carpet := Rect2(VW * 0.5 - 14.0, 130.0, 28.0, VH - 146.0)
		draw_rect(carpet, Color(0.55, 0.05, 0.1))
		draw_rect(carpet.grow(-2.0), GOLD, false, 1.0)

	func _walls(night: float) -> void:
		draw_rect(Rect2(0, 0, VW, 40), Color(0.3, 0.17, 0.1))
		var px := 4.0
		while px < VW:
			draw_rect(Rect2(px, 6.0, 26.0, 26.0), Color(0.36, 0.21, 0.12), false, 1.0)
			px += 30.0
		draw_rect(Rect2(0, 35, VW, 3), GOLD)
		draw_rect(Rect2(0, 40, 16, VH - 40), Color(0.28, 0.16, 0.09))
		draw_rect(Rect2(VW - 16, 40, 16, VH - 40), Color(0.28, 0.16, 0.09))
		draw_rect(Rect2(0, VH - 16, VW, 16), Color(0.28, 0.16, 0.09))
		# korkeat ikkunat verhoineen
		var sky := Color(0.45, 0.65, 0.9).lerp(Color(0.05, 0.07, 0.18), night)
		for wx: float in [130.0, 186.0, 318.0]:
			var w := Rect2(wx, 6.0, 16.0, 26.0)
			draw_rect(w.grow(1.5), GOLD)
			draw_rect(w, sky)
			draw_line(Vector2(w.get_center().x, w.position.y), Vector2(w.get_center().x, w.end.y), Color(0.95, 0.95, 0.9), 1.0)
			if night > 0.4:
				draw_circle(w.position + Vector2(4, 5), 0.6, Color(1, 1, 0.9))
			draw_rect(Rect2(w.position.x - 5.0, 4.0, 5.0, 30.0), Color(0.6, 0.06, 0.1))
			draw_rect(Rect2(w.end.x, 4.0, 5.0, 30.0), Color(0.6, 0.06, 0.1))
		# taulut
		for pr: Rect2 in [Rect2(40.0, 8.0, 28.0, 20.0), Rect2(400.0, 8.0, 26.0, 18.0)]:
			draw_rect(pr.grow(2.0), GOLD)
			draw_rect(pr, Color(0.3, 0.2, 0.15))
			draw_circle(pr.get_center() + Vector2(0, -1), 5.0, Color(0.9, 0.75, 0.6))
			draw_rect(Rect2(pr.position.x + 6.0, pr.get_center().y + 3.0, pr.size.x - 12.0, 6.0), Color(0.15, 0.12, 0.2))
		# paniikkihuoneen kirjahylly vasemmalla seinällä (ovi sen takana)
		var bk := Rect2(16.0, 112.0, 14.0, 30.0)
		draw_rect(bk, Color(0.3, 0.18, 0.1))
		for k in 4:
			var sy := bk.position.y + 2.0 + k * 7.0
			draw_line(Vector2(bk.position.x, sy + 6.0), Vector2(bk.end.x, sy + 6.0), GOLD, 1.0)
			for b in 4:
				draw_rect(Rect2(bk.position.x + 1.5 + b * 3.0, sy, 2.5, 5.5), [Color(0.6, 0.1, 0.12), Color(0.15, 0.3, 0.5), Color(0.2, 0.4, 0.2), Color(0.75, 0.6, 0.3)][(b + k) % 4] as Color)
		draw_rect(bk, GOLD, false, 1.0)
		draw_circle(Vector2(bk.end.x - 2.0, bk.get_center().y), 0.9, Color(0.9, 0.2, 0.2, 0.5 + 0.5 * sin(_t * 3.0)))

	func _bedroom() -> void:
		var b: Rect2 = L.BED
		draw_rect(Rect2(b.position + Vector2(2, 3), b.size), Color(0, 0, 0, 0.25))
		draw_rect(Rect2(b.position.x - 2.0, b.position.y - 8.0, b.size.x + 4.0, 12.0), GOLD)   # päätyrauta
		draw_rect(Rect2(b.position.x + 4.0, b.position.y - 6.0, b.size.x - 8.0, 6.0), Color(0.95, 0.85, 0.5))
		draw_rect(b, Color(0.95, 0.94, 0.92))
		draw_rect(Rect2(b.position.x, b.position.y + 18.0, b.size.x, b.size.y - 18.0), Color(0.62, 0.05, 0.12))   # satiinipeitto
		draw_rect(Rect2(b.position.x, b.position.y + 18.0, b.size.x, 3.0), Color(0.75, 0.15, 0.2))
		for k in 3:
			draw_rect(Rect2(b.position.x + 6.0 + k * 22.0, b.position.y + 4.0, 18.0, 10.0), Color(0.98, 0.97, 0.95))
		draw_circle(Vector2(b.get_center().x, b.position.y + 32.0), 5.0, Color(0.8, 0.1, 0.2))   # sydäntyyny
		for ns: Rect2 in [L.NIGHTSTAND_L, L.NIGHTSTAND_R]:
			draw_rect(ns, Color(0.3, 0.18, 0.1))
			draw_rect(ns, GOLD, false, 1.0)
			draw_circle(ns.get_center() + Vector2(0, -4), 3.0, Color(1.0, 0.9, 0.6, 0.9))
			draw_circle(ns.get_center() + Vector2(0, -4), 8.0, Color(1.0, 0.9, 0.6, 0.12))
		# shampanjapullot sängyn vieressä
		_bottle(Vector2(108.0, 78.0), false)
		_bottle(Vector2(112.0, 84.0), true)

	func _living() -> void:
		# takka ja tuli
		var f: Rect2 = L.FIREPLACE
		var fp := Rect2(f.position.x, 14.0, f.size.x, 34.0)
		draw_rect(fp, Color(0.85, 0.82, 0.78))
		draw_rect(Rect2(fp.position.x + 12.0, 24.0, fp.size.x - 24.0, 22.0), Color(0.1, 0.06, 0.05))
		for k in 5:
			var fx := fp.position.x + 16.0 + k * 7.0
			var fh := 8.0 + 4.0 * sin(_t * 9.0 + k * 1.7)
			draw_colored_polygon(PackedVector2Array([Vector2(fx - 3.0, 45.0), Vector2(fx + 3.0, 45.0), Vector2(fx, 45.0 - fh)]), Color(1.0, 0.55, 0.1))
			draw_colored_polygon(PackedVector2Array([Vector2(fx - 1.5, 45.0), Vector2(fx + 1.5, 45.0), Vector2(fx, 45.0 - fh * 0.6)]), Color(1.0, 0.9, 0.4))
		draw_circle(Vector2(fp.get_center().x, 50.0), 34.0, Color(1.0, 0.6, 0.2, 0.08 + 0.03 * sin(_t * 7.0)))
		draw_rect(Rect2(fp.position.x - 2.0, 12.0, fp.size.x + 4.0, 3.0), GOLD)
		# flyygeli
		var pi: Rect2 = L.PIANO
		draw_rect(Rect2(pi.position + Vector2(2, 3), pi.size), Color(0, 0, 0, 0.3))
		draw_rect(pi, Color(0.06, 0.06, 0.08))
		draw_arc(Vector2(pi.end.x - 6.0, pi.get_center().y), 13.0, -PI * 0.5, PI * 0.5, 10, Color(0.06, 0.06, 0.08), 6.0)
		draw_rect(Rect2(pi.position.x + 2.0, pi.end.y - 6.0, pi.size.x - 10.0, 4.0), Color(0.97, 0.97, 0.95))
		for k in 8:
			draw_line(Vector2(pi.position.x + 4.0 + k * 3.5, pi.end.y - 6.0), Vector2(pi.position.x + 4.0 + k * 3.5, pi.end.y - 4.0), Color(0.1, 0.1, 0.1), 1.0)
		draw_line(pi.position + Vector2(4, 4), pi.position + Vector2(30, 4), Color(1, 1, 1, 0.2), 1.0)
		# sohva, sohvapöytä ja pullot
		var so: Rect2 = L.SOFA
		draw_rect(Rect2(so.position + Vector2(2, 3), so.size), Color(0, 0, 0, 0.25))
		draw_rect(so, Color(0.95, 0.94, 0.9))
		draw_rect(Rect2(so.position.x, so.position.y - 6.0, so.size.x, 8.0), Color(0.88, 0.86, 0.82))
		for k in 4:
			draw_rect(Rect2(so.position.x + 4.0 + k * 21.0, so.position.y + 2.0, 18.0, 10.0), Color(0.98, 0.97, 0.95))
		draw_rect(Rect2(so.position.x + 10.0, so.position.y - 3.0, 8.0, 6.0), GOLD)
		draw_rect(Rect2(so.end.x - 18.0, so.position.y - 3.0, 8.0, 6.0), Color(0.8, 0.1, 0.2))
		var co: Rect2 = L.COFFEE
		draw_rect(co, Color(0.7, 0.85, 0.95, 0.6))
		draw_rect(co, GOLD, false, 1.0)
		for k in 4:
			_bottle(Vector2(co.position.x + 8.0 + k * 11.0, co.position.y + 6.0), k == 2)
		for k in 3:
			_glass(Vector2(co.position.x + 13.0 + k * 11.0, co.position.y + 9.0))

	func _bar() -> void:
		# takahylly täynnä shampanjaa
		var bb: Rect2 = L.BACKBAR
		draw_rect(Rect2(bb.position.x, 10.0, bb.size.x, 40.0), Color(0.22, 0.12, 0.07))
		for row in 3:
			draw_rect(Rect2(bb.position.x + 2.0, 20.0 + row * 10.0, bb.size.x - 4.0, 1.5), GOLD)
			for k in 12:
				_bottle(Vector2(bb.position.x + 6.0 + k * 6.8, 19.0 + row * 10.0), false, 0.8)
		TextFit.draw(self, ThemeDB.fallback_font, Vector2(bb.position.x, 18.0), "CHAMPAGNE", bb.size.x, 6, GOLD)
		# jääkaappi (kaksiovinen teräs)
		var fr: Rect2 = L.FRIDGE
		draw_rect(Rect2(fr.position.x, 8.0, fr.size.x, fr.end.y - 8.0), Color(0.75, 0.77, 0.8))
		draw_line(Vector2(fr.get_center().x, 8.0), Vector2(fr.get_center().x, fr.end.y), Color(0.5, 0.52, 0.56), 1.0)
		draw_rect(Rect2(fr.get_center().x - 3.0, 24.0, 1.5, 10.0), Color(0.4, 0.42, 0.46))
		draw_rect(Rect2(fr.get_center().x + 1.5, 24.0, 1.5, 10.0), Color(0.4, 0.42, 0.46))
		# baaritiski ja jakkarat
		var b: Rect2 = L.BAR
		draw_rect(Rect2(b.position + Vector2(2, 3), b.size), Color(0, 0, 0, 0.3))
		draw_rect(b, Color(0.25, 0.13, 0.07))
		draw_rect(Rect2(b.position, Vector2(b.size.x, 4.0)), Color(0.95, 0.94, 0.9))
		draw_line(Vector2(b.position.x, b.end.y - 2.0), Vector2(b.end.x, b.end.y - 2.0), GOLD, 1.0)
		for k in 9:
			_bottle(Vector2(b.position.x + 8.0 + k * 13.0, b.position.y + 1.0), k % 3 == 1)
			if k % 2 == 0:
				_glass(Vector2(b.position.x + 13.0 + k * 13.0, b.position.y + 2.0))
		for k in 5:
			var sp := Vector2(b.position.x + 12.0 + k * 24.0, b.end.y + 8.0)
			draw_circle(sp, 4.0, Color(0.8, 0.1, 0.2))
			draw_circle(sp, 4.0, GOLD, false, 1.0)
		# shampanjatorni
		var t: Rect2 = L.TOWER
		draw_circle(t.get_center() + Vector2(0, 4), 10.0, Color(0.95, 0.94, 0.9))
		draw_arc(t.get_center() + Vector2(0, 4), 10.0, 0.0, TAU, 16, GOLD, 1.0)
		for row in 4:
			var n := 4 - row
			for k in n:
				_glass(t.get_center() + Vector2(-n * 2.5 + k * 5.0 + 2.5, 4.0 - row * 5.0))
		_bottle(t.get_center() + Vector2(0, -18.0), false)
		var pour := fmod(_t * 1.5, 1.0)
		draw_line(t.get_center() + Vector2(0, -16.0), t.get_center() + Vector2(0, -13.0 + pour * 2.0), Color(1.0, 0.92, 0.55, 0.8), 1.0)

	func _pool() -> void:
		var p: Rect2 = L.POOL
		draw_rect(p.grow(4.0), Color(0.95, 0.93, 0.88))
		draw_rect(p.grow(4.0), GOLD, false, 1.0)
		draw_rect(p, Color(0.15, 0.55, 0.7))
		draw_rect(p.grow(-3.0), Color(0.2, 0.7, 0.82))
		# aaltoilu ja kuplat
		for k in 7:
			var wy := p.position.y + 10.0 + k * 11.0
			var off := sin(_t * 2.0 + k) * 6.0
			draw_line(Vector2(p.position.x + 10.0 + off, wy), Vector2(p.end.x - 10.0 + off, wy), Color(1, 1, 1, 0.12), 1.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for k in 40:
			var bx := rng.randf_range(p.position.x + 6.0, p.end.x - 6.0)
			var speed := rng.randf_range(4.0, 10.0)
			var by := p.end.y - 4.0 - fmod(_t * speed + rng.randf() * 80.0, p.size.y - 8.0)
			draw_circle(Vector2(bx, by), rng.randf_range(0.6, 1.4), Color(1, 1, 1, 0.55))
		# höyry
		for k in 4:
			var sx := p.position.x + 30.0 + k * 34.0
			var sy := p.position.y - fmod(_t * 6.0 + k * 9.0, 22.0)
			draw_circle(Vector2(sx + sin(_t + k) * 3.0, sy), 4.0, Color(1, 1, 1, 0.08))
		# jääsangot pulloineen kulmissa
		for c: Vector2 in [p.position + Vector2(-2, -2), Vector2(p.end.x + 2.0, p.position.y - 2.0), Vector2(p.end.x + 2.0, p.end.y + 2.0)]:
			draw_rect(Rect2(c - Vector2(5, 3), Vector2(10, 7)), Color(0.8, 0.82, 0.86))
			_bottle(c + Vector2(-2, -2), false)
			_bottle(c + Vector2(2, -1), true)
		# kelluva shampanjapullo
		_bottle(p.position + Vector2(80.0 + sin(_t * 0.7) * 10.0, 30.0), true)

	func _palm(p: Vector2) -> void:
		draw_rect(Rect2(p - Vector2(6.0, 4.0), Vector2(12.0, 8.0)), GOLD)
		draw_line(p + Vector2(0, -2), p + Vector2(1, -18), Color(0.45, 0.3, 0.15), 2.0)
		for k in 6:
			var a := -PI * 0.5 + (k - 2.5) * 0.5 + sin(_t * 0.8 + k) * 0.05
			draw_line(p + Vector2(1, -18), p + Vector2(1, -18) + Vector2.from_angle(a) * 12.0, Color(0.15, 0.55, 0.25), 2.0)

	func _bottle(p: Vector2, open: bool, s: float = 1.0) -> void:
		draw_rect(Rect2(p + Vector2(-1.2, -4.0) * s, Vector2(2.4, 5.0) * s), BOTTLE)
		draw_rect(Rect2(p + Vector2(-0.6, -6.0) * s, Vector2(1.2, 2.2) * s), FOIL)
		draw_rect(Rect2(p + Vector2(-1.2, -2.5) * s, Vector2(2.4, 1.2) * s), Color(0.95, 0.92, 0.8))
		if open:
			var k := fmod(_t * 2.0 + p.x, 1.0)
			draw_circle(p + Vector2(0, -7.0 - k * 3.0) * s, 0.6 * s, Color(1.0, 0.95, 0.7, 1.0 - k))

	func _glass(p: Vector2) -> void:
		draw_line(p, p + Vector2(0, -2), Color(0.9, 0.95, 1.0, 0.8), 0.6)
		draw_rect(Rect2(p + Vector2(-1.0, -5.0), Vector2(2.0, 3.0)), Color(1.0, 0.88, 0.45, 0.85))
		draw_line(p + Vector2(-1.2, 0), p + Vector2(1.2, 0), Color(0.9, 0.95, 1.0, 0.8), 0.6)

	func _lady(i: int, l: Array) -> void:
		var pos: Vector2 = l[0]
		var md := str(l[3])
		var col := int(l[4])
		var step := 0
		if md == "dance":
			col = [1, 3, 2, 0][int(_t * 1.5) % 4]
			pos += Vector2(sin(_t * 3.0) * 2.0, -absf(sin(_t * 6.0)) * 1.5)
		var tex := CS2.lady(col, step, l[1], l[2])
		if tex == null:
			return
		var t := tex
		if fmod(_t + i * 1.7, 4.1 + i * 0.3) < 0.12:
			var bl := CS2.blink(tex)
			if bl:
				t = bl
		if md == "pool" or md == "sofa":
			var up := CS2.seated(t)
			if up:
				draw_texture_rect(up, Rect2(pos - Vector2(8.0, 12.0), Vector2(16.0, 12.0)), false)
			if md == "pool":
				# vesi peittää vartalon, lasi kädessä
				draw_rect(Rect2(pos.x - 9.0, pos.y - 5.0, 18.0, 6.0), Color(0.2, 0.7, 0.82, 0.85))
				draw_line(Vector2(pos.x - 8.0, pos.y - 5.0), Vector2(pos.x + 8.0, pos.y - 5.0), Color(1, 1, 1, 0.4), 1.0)
				_glass(pos + Vector2(6.0, -6.0 + sin(_t * 1.3 + i) * 0.5))
		else:
			draw_set_transform(pos + Vector2(0, -0.5), 0.0, Vector2(1.0, 0.4))
			draw_circle(Vector2.ZERO, 5.0, Color(0, 0, 0, 0.25))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var br := 1.0 + 0.03 * maxf(sin(_t * 0.9 + i), 0.0)
			draw_texture_rect(t, Rect2(pos - Vector2(8.0, 16.0 * br), Vector2(16.0, 16.0 * br)), false)
			_glass(pos + Vector2(5.0 if col != 0 else -5.0, -6.0))
		if _talk.has(i):
			var txt := str((_talk[i] as Array)[0])
			var font := ThemeDB.fallback_font
			var tp := pos + Vector2(-40.0, -20.0)
			TextFit.draw_outline(self, font, tp, txt, 80.0, 6, 3, Color(0, 0, 0, 0.8))
			TextFit.draw(self, font, tp, txt, 80.0, 6, Color(1.0, 0.85, 0.9))
