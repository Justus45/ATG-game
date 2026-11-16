extends Node
## Työt, pimeät keikat ja tehtävät. Game liittää tämän kenttään (ryhmä "job_manager").
##
## Sivutehtävät (päätavoite: osta oma baari tai lähde kaupungista, ks. Game.gd):
##   fetch    Baarimikon tehtävä: hae paketti kaupalta baarille
##   (taksi: TaxiJob.gd, T autossa)
## Pimeät keikat (Kalle baarin kulmalla):
##   smuggle  salakuljetus: partioiden tarkastus löytää lastin -> pidätys
##   beatdown "hoida tyyppi": kaada velallinen (StreetThug "target")
##   robbery  ryöstö baarin takana: kuriiri rahojen kanssa, ryöstä (R) tai hakkaa
##
## Yksi keikka kerrallaan. Keikka keskeytyy pidätykseen; rehelliset työt myös jahtiin.

const ThugScript := preload("res://scripts/world/StreetThug.gd")

const ARRIVE := 32.0

## Salakuljetuslasti autossa (PolicePatrol tarkastaa)
var contraband := false

var _job: Dictionary = {}
var _marker: JobMarker
var _hud: Node
var _city: Node
var _player: Node2D
var _police: Node
var _stop_hold := 0.0
var _hint_t := 0.0
var _last_text := ""
var _thug: Node = null


func _ready() -> void:
	add_to_group("job_manager")
	var scene := get_tree().current_scene
	_hud = scene.get_node_or_null("Hud")
	_city = scene.get_node_or_null("City")
	_player = scene.get_node_or_null("Player")
	_police = scene.get_node_or_null("PoliceManager")
	_marker = JobMarker.new()
	_marker.visible = false
	scene.add_child.call_deferred(_marker)


func busy() -> bool:
	return not _job.is_empty()


# ----------------------------------------------------------------------------
#  ALOITUS
# ----------------------------------------------------------------------------
## Palvelurakennus tai kontakti aloittaa keikan. source = ServiceBuilding tai Bar.
func start_job(type: String, source: Node = null) -> void:
	if busy():
		_menu("Sinulla on jo keikka kesken: %s" % str(_job.title), ["Peruuta nykyinen keikka"], _cancel_choice)
		return
	var taxi := get_tree().get_first_node_in_group("taxi_job")
	if taxi and Game.flag(taxi, "_on_shift"):
		_msg("Lopeta ensin taksivuoro (T).", 2.0)
		return
	if _police and _police.wanted > 0 and type in ["fetch"]:
		_msg("Kukaan ei palkkaa etsintäkuulutettua.", 2.0)
		return
	var origin: Vector2 = source.door_px if source and "door_px" in source else _player.body_center()
	match type:
		"fetch":
			var shop := get_tree().get_first_node_in_group("shop")
			var bar := get_tree().get_first_node_in_group("bar")
			if shop == null or bar == null:
				return
			_begin({"type": type, "title": "Paketti baarille", "legit": true, "rep": "regulars",
				"stops": [
					{"pos": shop.door_px + Vector2(0, 28), "car": false, "text": "Hae paketti kaupalta", "pay": 0, "time": -1.0},
					{"pos": bar.door_px + Vector2(0, 28), "car": false, "text": "Vie paketti baariin", "pay": 60, "time": 150.0},
				]})
		"smuggle":
			var p := _random_road_point(origin, 50.0, 100.0)
			contraband = true
			_begin({"type": type, "title": "Salakuljetus", "rep": "criminals", "crime": true,
				"stops": [{"pos": p, "car": true, "text": "Vie lasti Kallen kaverille (varo partioita!)", "pay": 220, "time": _drive_time(origin, p) + 25.0}]})
		"beatdown":
			var p := _random_walk_point(origin, 30.0, 60.0)
			var t := _spawn_thug(p, "target", randi_range(20, 40))
			t.display_name = "Velallinen"
			_begin({"type": type, "title": "Hoida tyyppi", "rep": "criminals", "crime": true,
				"stops": [{"pos": p, "follow": t, "car": false, "text": "Etsi velallinen ja kaada hänet", "pay": 0, "time": 240.0, "manual": true}]})
			t.defeated.connect(_on_thug_done.bind(120, "Velallinen sai opetuksen. Kalle: \"Kliffaa, tos massit.\" (120 $)"))
			t.killed.connect(_on_thug_done.bind(50, "Kalle: \"Liian rajuu, jäbä. Saat vaan viiskymppii.\" (50 $)"))
		"robbery":
			var bar := get_tree().get_first_node_in_group("bar")
			var p: Vector2 = bar.back_alley_point() if bar else origin
			var t := _spawn_thug(p, "courier", randi_range(220, 320))
			t.display_name = "Kuriiri"
			_begin({"type": type, "title": "Ryöstö baarin takana", "rep": "criminals", "crime": true,
				"stops": [{"pos": p, "follow": t, "car": false, "text": "Ryöstä kuriiri baarin takana (R aseella) tai kaada hänet", "pay": 0, "time": 120.0, "manual": true}]})
			t.defeated.connect(_on_thug_done.bind(0, "Ryöstö onnistui! Kerää rahat."))
			t.killed.connect(_on_thug_done.bind(0, "Kuriiri kuoli. Kerää rahat ja häivy."))


func _begin(job: Dictionary) -> void:
	_job = job
	_job["idx"] = 0
	_job["earned"] = 0
	_set_stop_timer()
	_marker.visible = true
	_marker.marker_color = Color(0.95, 0.35, 0.3) if job.get("crime", false) else Color(0.3, 0.75, 1.0)
	var st: Dictionary = _cur()
	_msg("%s: %s" % [str(job.title), str(st.text)], 3.0)
	_stop_hold = 0.0


func _cur() -> Dictionary:
	var stops: Array = _job.stops
	return stops[int(_job.idx)]


func _set_stop_timer() -> void:
	var st: Dictionary = _cur()
	_job["stop_time"] = float(st.get("time", -1.0))
	_job["stop_total"] = float(st.get("time", -1.0))


# ----------------------------------------------------------------------------
#  KULKU
# ----------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _job.is_empty():
		return
	if _police and _police.jail.serving:
		_fail("Pidätys keskeytti keikan.")
		return
	if _job.get("legit", false) and _police and _police.wanted > 0:
		_fail("Poliisi jahtaa sinua: keikka keskeytyi.")
		return
	var st: Dictionary = _cur()
	var follow: Variant = st.get("follow", null)
	if follow != null:
		if is_instance_valid(follow):
			st["pos"] = (follow as Node2D).global_position
		elif not st.get("manual", false):
			_fail("Kohde katosi.")
			return
	_marker.global_position = st.pos

	# Aikarajat
	if float(_job.stop_time) > 0.0:
		_job["stop_time"] = float(_job.stop_time) - delta
		if float(_job.stop_time) <= 0.0:
			_fail("Aika loppui!")
			return
	if _job.has("deadline"):
		_job["deadline"] = float(_job.deadline) - delta
		if float(_job.deadline) <= 0.0:
			_fail("Aika loppui!")
			return

	var driving := _driven_car()
	var here: Vector2 = driving.global_position if driving else _player.body_center()
	var dist := here.distance_to(st.pos)
	_hint_t -= delta

	if st.get("manual", false):
		_update_text(st, dist)
		return
	if st.has("enter"):
		if driving == st.enter:
			_advance()
		_update_text(st, dist)
		return
	if st.get("car", false) and driving == null:
		if dist < 200.0 and _hint_t <= 0.0:
			_hint_t = 5.0
			_msg("Tähän tarvitaan auto.", 1.5)
		_update_text(st, dist)
		return
	if st.has("only_car") and driving != st.only_car:
		_update_text(st, dist)
		return
	if dist <= ARRIVE + (6.0 if driving else 0.0):
		var hold := float(st.get("hold", 0.0))
		if hold > 0.0:
			var spd: float = driving.velocity.length() if driving and "velocity" in driving else 0.0
			if spd < 30.0:
				_stop_hold += delta
				if _stop_hold >= hold:
					Sfx.play("clang", here, -10.0, 0.1, 1.6)
					_advance()
			else:
				_stop_hold = 0.0
		else:
			_advance()
	else:
		_stop_hold = 0.0
	_update_text(st, dist)


func _advance() -> void:
	var st: Dictionary = _cur()
	var pay := int(st.get("pay", 0))
	if _job.get("tip", false) and float(_job.stop_time) > float(_job.stop_total) * 0.4:
		pay += 5
	if pay > 0:
		_player.add_money(pay)
		_job["earned"] = int(_job.earned) + pay
		Sfx.play_ui("coin", -6.0)
	_job["idx"] = int(_job.idx) + 1
	_stop_hold = 0.0
	if int(_job.idx) >= (_job.stops as Array).size():
		_complete()
		return
	_set_stop_timer()
	var nxt: Dictionary = _cur()
	_msg(("+%d $  " % pay if pay > 0 else "") + str(nxt.text), 2.5)


func _complete() -> void:
	var title := str(_job.title)
	var earned := int(_job.earned)
	var rep_kind := str(_job.get("rep", "police"))
	if _job.get("crime", false):
		Game.add_rep("criminals", 6)
		Game.add_rep("police", -2)
	else:
		Game.add_rep(rep_kind, 4 if rep_kind != "police" else 2)
	Game.missions_done += 1
	Game.add_vitutus(Game.VITUTUS_WORK)
	var was_crime := bool(_job.get("crime", false))
	var jtype := str(_job.get("type", ""))
	_end()
	_msg("%s valmis! Yhteensä %d $." % [title, earned], 3.0)
	_notify_story(jtype, was_crime)


func _notify_story(jtype: String, crime: bool) -> void:
	var story := get_tree().get_first_node_in_group("story")
	if story and story.has_method("on_job_done"):
		story.on_job_done(jtype, crime)


func _cancel_choice(i: int) -> void:
	if i == 0:
		_fail("Peruit keikan.")


func _on_thug_done(thug_node: Node, pay: int, text: String) -> void:
	if thug_node != _thug:
		return   # vanhan keikan kohde
	_complete_manual(pay, text)


## Tappelu / ryöstö ratkesi (StreetThug-signaali).
func _complete_manual(pay: int, text: String) -> void:
	if _job.is_empty():
		return
	if pay > 0:
		_player.add_money(pay)
	_job["earned"] = int(_job.earned) + pay
	Game.add_rep("criminals", 6)
	Game.add_rep("police", -2)
	Game.missions_done += 1
	Game.add_vitutus(Game.VITUTUS_WORK)
	var jtype := str(_job.get("type", ""))
	_end()
	_msg(text, 3.0)
	_notify_story(jtype, true)


func _fail(text: String) -> void:
	Game.add_vitutus(Game.VITUTUS_FAIL)
	if _job.get("crime", false):
		Game.add_rep("criminals", -3)
	_end()
	_msg(text, 2.5)


## Partio löysi salakuljetuslastin (PolicePatrol kutsuu).
func contraband_found() -> void:
	contraband = false
	if not _job.is_empty() and str(_job.type) == "smuggle":
		_job["crime"] = true
		_fail("Lasti takavarikoitiin. Kalle: \"Kytät vei kaiken? Ei hyvä, kundi.\"")


func _end() -> void:
	if is_instance_valid(_thug) and _thug.get("mode") == "courier":
		_thug.call("_despawn")
	_thug = null
	_job = {}
	contraband = false
	_marker.visible = false
	_set_hud("")


func _update_text(st: Dictionary, dist: float) -> void:
	# Keikka saattoi juuri päättyä (_advance -> _complete -> _end): ei enää mitään näytettävää
	if _job.is_empty():
		return
	var parts: PackedStringArray = [str(_job.title).to_upper(), str(st.text)]
	if float(_job.get("stop_time", -1.0)) > 0.0:
		parts.append("%d s" % ceili(float(_job.stop_time)))
	if _job.has("deadline"):
		parts.append("%d s" % ceili(float(_job.deadline)))
	parts.append("%d m" % int(dist / 16.0))
	_set_hud("  ".join(parts))


func _set_hud(text: String) -> void:
	if text == _last_text:
		return
	_last_text = text
	if _hud and _hud.has_method("set_job_info"):
		_hud.set_job_info(text)


# ----------------------------------------------------------------------------
#  KONTAKTIT
# ----------------------------------------------------------------------------
const GOSSIP := [
	"Baarimikko: \"Kalle tuolla kulmalla tietää aina keikoista.\"",
	"Baarimikko: \"Pankkiin kannattaa viedä rahat ennen ku vetää perskännit.\"",
	"Baarimikko: \"Kiinteistövälittäjä myy tätä paikkaa. Viis tonnia.\"",
	"Baarimikko: \"Kallelta saa rahaa nopeasti, mut poliisi muistaa naamat.\"",
	"Baarimikko: \"Portsari ei tykkää, jos hakkaat rauhallisia.\"",
]


func bartender_menu() -> void:
	_menu("BAARIMIKKO", ["Tehtävä: hae paketti kaupalta baariin (60 $)", "Kysy juoruja"], _bartender_choice)


func _bartender_choice(i: int) -> void:
	if i == 0:
		start_job("fetch", get_tree().get_first_node_in_group("bar"))
	elif i == 1:
		_msg(GOSSIP[randi() % GOSSIP.size()], 4.0)


func kalle_menu(bar: Node) -> void:
	var crim := int(Game.rep.criminals)
	_menu("KALLE (rikollisporukka: %s)" % Game.rep_word("criminals"),
		["Salakuljetus autolla (220 $, partiot vaarallisia)", "Hoida tyyppi (120 $)",
		 "Ryöstö baarin takana (n. 250 $%s)" % ("" if crim >= 10 else ", vaatii mainetta 10")],
		_kalle_choice.bind(bar))


func _kalle_choice(i: int, bar: Node) -> void:
	match i:
		0:
			start_job("smuggle", bar)
		1:
			start_job("beatdown", bar)
		2:
			if int(Game.rep.criminals) >= 10:
				start_job("robbery", bar)
			else:
				_msg("Kalle: \"Sä et oo viel valmis isoihin duuneihin. Näytä eka, jäbä.\"", 3.0)


func status_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	out.append("TEHTÄVÄT JA KEIKAT (tehty %d):" % Game.missions_done)
	if busy():
		var st: Dictionary = _cur()
		out.append("  KÄYNNISSÄ: %s – %s" % [str(_job.title), str(st.text)])
	out.append("  Baarimikko: hae paketti  ·  Taksi: T autossa")
	out.append("  Kalle baarin kulmalla: salakuljetus, hoida tyyppi, ryöstö baarin takana")
	return out


# ----------------------------------------------------------------------------
#  APUFUNKTIOT
# ----------------------------------------------------------------------------
func _driven_car() -> Node2D:
	for car in get_tree().get_nodes_in_group("player_vehicles"):
		if "is_driving" in car and car.is_driving:
			return car
	return null


## Aikaraja ajomatkalle (sama mitoitus kuin taksissa, vähän väljempi).
func _drive_time(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b) / 16.0 * 0.16 + 18.0


func _random_road_point(from: Vector2, min_tiles: float, max_tiles: float) -> Vector2:
	var fc: Vector2i = _city.world_to_cell(from)
	var best: Vector2i = fc
	for attempt in 300:
		var off := Vector2.from_angle(randf() * TAU) * randf_range(min_tiles, max_tiles)
		var c := fc + Vector2i(off.round())
		if _city.is_road(c) and _city.is_walkable(c):
			return _city.cell_to_world(c)
		if _city.is_road(c):
			best = c
	return _city.cell_to_world(best)


func _random_walk_point(from: Vector2, min_tiles: float, max_tiles: float) -> Vector2:
	var fc: Vector2i = _city.world_to_cell(from)
	for attempt in 300:
		var off := Vector2.from_angle(randf() * TAU) * randf_range(min_tiles, max_tiles)
		var c := fc + Vector2i(off.round())
		if _city.is_walkable(c) and not _city.is_road(c):
			return _city.cell_to_world(c)
	return _random_road_point(from, min_tiles, max_tiles)


func _spawn_thug(world_pos: Vector2, mode: String, cash: int) -> Node:
	var t = ThugScript.new()
	t.city = _city
	t.mode = mode
	t.base_row = (randi() % 6) * 3
	t.cash = cash
	t.position = _city.entities.to_local(world_pos)
	_city.entities.add_child(t)
	_thug = t
	return t


func _menu(title: String, options: Array, cb: Callable) -> void:
	if _hud and _hud.has_method("show_menu"):
		_hud.show_menu(title, options, cb)


func _msg(text: String, seconds: float) -> void:
	if _hud and _hud.has_method("show_message"):
		_hud.show_message(text, seconds)


## Pulssaava kohdemerkki maailmassa (näkyy myös minikartalla).
class JobMarker extends Node2D:
	var marker_color := Color(0.3, 0.75, 1.0)

	func _init() -> void:
		z_index = 200
		add_to_group("minimap_marker")

	func _process(_delta: float) -> void:
		if visible:
			queue_redraw()

	func _draw() -> void:
		var t := float(Time.get_ticks_msec()) / 1000.0
		var pulse := 0.5 + 0.5 * sin(t * 4.0)
		var r := 18.0 + pulse * 4.0
		draw_circle(Vector2.ZERO, r, Color(marker_color, 0.22))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 36, Color(0, 0, 0, 0.8), 4.0)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 36, marker_color, 2.5)
		draw_circle(Vector2.ZERO, 3.5, marker_color)
