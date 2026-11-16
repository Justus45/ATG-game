extends Node
## Rehellinen työ: taksikuski.
##  - T (autoa ajaessa) aloittaa / lopettaa työvuoron
##  - matkustaja haluaa tietylle kohteelle: aja vihreään ympyrään ennen ajan loppumista
##  - palkka = perusmaksu + matka-ajan mukaan; nopeasta kyydistä tulee tippiä
##  - uusi kyyti alkaa automaattisesti, kunnes vuoro päättyy
##  - vuoro päättyy kun astut autosta, ajat liian myöhään tai saat etsintäkuulutuksen
##
## Minikartta lukee tämän ryhmän "taxi_job": active ja destination.

## Säädettävät arvot
const BASE_FARE := 8
const FARE_PER_TILE := 0.7        ## $ per ruutu (linnuntie)
const TIP_RATIO := 0.25           ## tippi, jos aikaa jäi yli 35 %
const MIN_TRIP_TILES := 30
const MAX_TRIP_TILES := 100
const ARRIVE_DISTANCE := 30.0     ## pikseliä
const TIME_PER_TILE := 16.0 / 170.0   ## sekuntia per ruutu (liikennekaupungissa ei aja suoraan)
const TIME_BONUS := 15.0
const NEXT_FARE_DELAY := 1.5

## Onko kyyti käynnissä (minikartta käyttää)
var active := false
var destination := Vector2.ZERO

var _on_shift := false
var _fare := 0
var _time_total := 0.0
var _time_left := 0.0
var _delay := 0.0
var _was_driving := false
var _hint_shown := false
var _marker: Node2D
var _city: Node
var _hud: Node
var _player: Node
var _police: Node


func _ready() -> void:
	add_to_group("taxi_job")
	if not InputMap.has_action("taxi"):
		InputMap.add_action("taxi")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_T
		InputMap.action_add_event("taxi", ev)
	var level := get_parent()
	_city = level.get_node_or_null("City")
	_hud = level.get_node_or_null("Hud")
	_player = level.get_node_or_null("Player")
	_police = level.get_node_or_null("PoliceManager")
	_marker = TaxiMarker.new()
	_marker.visible = false
	level.add_child.call_deferred(_marker)


func _driven_car() -> Node2D:
	for car in get_tree().get_nodes_in_group("player_vehicles"):
		if "is_driving" in car and car.is_driving:
			return car
	return null


## Onko auto pelaajan taksi? (Jos kaupungissa ei ole taksia lainkaan, kelpaa pelaajan oma auto.)
func _is_taxi(car: Node2D) -> bool:
	if car == null:
		return false
	if Game.flag(car, "is_taxi"):
		return true
	for v in get_tree().get_nodes_in_group("player_vehicles"):
		if is_instance_valid(v) and Game.flag(v, "is_taxi"):
			return false
	return car.name == "Car"


func _process(delta: float) -> void:
	var car := _driven_car()
	var driving := car != null

	var is_taxi: bool = driving and _is_taxi(car)
	# Vihje, kun pelaaja nousee taksiin ensimmäistä kertaa
	if is_taxi and not _was_driving and not _hint_shown and not _on_shift:
		_hint_shown = true
		_msg("Paina T aloittaaksesi taksityön", 4.0)
	_was_driving = driving

	# Partio pysäytti humalaisen taksikuskin: matkustaja lähtee, eikä kyydistä makseta
	if _on_shift and _player and _player.get("police_locked") and float(_player.get("drunk")) >= 0.05:
		Game.add_rep("police", -2)
		_end_shift("Poliisi pysäytti sinut humalassa: matkustaja lähti kävellen. Ei palkkaa.")
	if _on_shift and not driving:
		_end_shift("Työvuoro päättyi")
	elif _on_shift and not is_taxi:
		_end_shift("Taksityötä voi tehdä vain taksilla: työvuoro päättyi")
	if _on_shift and _police and "wanted" in _police and _police.wanted > 0:
		_end_shift("Poliisi etsii sinua: työvuoro päättyi")

	if driving and Input.is_action_just_pressed("taxi"):
		if _on_shift:
			_end_shift("Työvuoro päättyi")
		elif not is_taxi:
			_msg("Taksityötä voi tehdä vain taksilla. Keltainen taksisi odottaa kotipihassa.", 3.0)
		elif _police and "wanted" in _police and _police.wanted > 0:
			_msg("Et voi ottaa kyytejä etsintäkuulutettuna", 2.5)
		elif get_tree().get_first_node_in_group("job_manager") and get_tree().get_first_node_in_group("job_manager").busy():
			_msg("Hoida ensin nykyinen keikka loppuun.", 2.5)
		else:
			_on_shift = true
			_msg("Työvuoro alkoi! Etsitään matkustajaa...", 2.5)
			_delay = 1.0

	if not _on_shift:
		_update_hud("")
		return

	if not active:
		_delay -= delta
		_update_hud("TAKSI: etsitään matkustajaa...")
		if _delay <= 0.0:
			_start_fare(car)
		return

	_time_left -= delta
	var dist := car.global_position.distance_to(destination)
	if dist <= ARRIVE_DISTANCE:
		_complete_fare()
		return
	if _time_left <= 0.0:
		_fail_fare()
		return
	_update_hud("TAKSI  %d $   %d s   %d m" % [_fare, ceili(_time_left), int(dist / 16.0)])


func _start_fare(car: Node2D) -> void:
	if _city == null or not ("col_road" in _city) or _city.col_road.is_empty():
		_end_shift("Kaupunkia ei löytynyt")
		return
	var from_cell: Vector2i = _city.world_to_cell(car.global_position)
	var cell := _pick_destination(from_cell)
	destination = _city.cell_to_world(cell)
	var tiles := Vector2(from_cell).distance_to(Vector2(cell))
	_fare = BASE_FARE + int(round(tiles * FARE_PER_TILE))
	_time_total = tiles * 1.4 * TIME_PER_TILE + TIME_BONUS
	_time_left = _time_total
	active = true
	_marker.visible = true
	_marker.global_position = destination
	_msg("Uusi kyyti! Aja vihreään ympyrään. Palkka %d $" % _fare, 3.0)


## Satunnainen tieruutu sopivan matkan päässä (ei rakennuksen sisällä).
func _pick_destination(from_cell: Vector2i) -> Vector2i:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var best := from_cell
	for attempt in 400:
		var c := Vector2i(rng.randi_range(0, _city.map_w - 1), rng.randi_range(0, _city.map_h - 1))
		if not _city.is_walkable(c) or not _city.is_road(c):
			continue
		var d := Vector2(from_cell).distance_to(Vector2(c))
		# Löystetään vaatimuksia, jos sopivaa ei löydy heti
		var lo := MIN_TRIP_TILES if attempt < 300 else 10
		if d >= lo and d <= MAX_TRIP_TILES:
			return c
		best = c
	return best


func _complete_fare() -> void:
	var tip := 0
	if _time_left > _time_total * 0.35:
		tip = int(round(_fare * TIP_RATIO))
	var total := _fare + tip
	if _player and _player.has_method("add_money"):
		_player.add_money(total)
	Game.add_vitutus(Game.VITUTUS_WORK * 0.5)   # taksin ajaminen on duunia
	Game.add_rep("police", 1)
	if tip > 0:
		_msg("Perillä! +%d $ (tippi %d $)" % [total, tip], 2.5)
	else:
		_msg("Perillä! +%d $" % total, 2.5)
	active = false
	_marker.visible = false
	_delay = NEXT_FARE_DELAY


func _fail_fare() -> void:
	_end_shift("Matkustaja kyllästyi odottamaan. Ei palkkaa.")


func _end_shift(text: String) -> void:
	_on_shift = false
	active = false
	if _marker:
		_marker.visible = false
	_update_hud("")
	_msg(text, 2.5)


var _last_hud := "-"

func _update_hud(text: String) -> void:
	# Päivitetään vain muutoksesta, ettei taksi pyyhi muiden töiden (JobManager) tekstiä
	if text == _last_hud:
		return
	_last_hud = text
	if _hud and _hud.has_method("set_job_info"):
		_hud.set_job_info(text)


func _msg(text: String, seconds: float) -> void:
	if _hud and _hud.has_method("show_message"):
		_hud.show_message(text, seconds)


## Vihreä pulssaava ympyrä kohteen päällä maailmassa.
class TaxiMarker extends Node2D:
	func _init() -> void:
		z_index = 200

	func _process(_delta: float) -> void:
		if visible:
			queue_redraw()

	func _draw() -> void:
		var t := float(Time.get_ticks_msec()) / 1000.0
		var pulse := 0.5 + 0.5 * sin(t * 4.0)
		var green := Color(0.2, 0.9, 0.35)
		draw_circle(Vector2.ZERO, 22.0 + pulse * 4.0, Color(green, 0.25))
		draw_arc(Vector2.ZERO, 22.0 + pulse * 4.0, 0.0, TAU, 40, Color(0, 0, 0, 0.8), 4.0)
		draw_arc(Vector2.ZERO, 22.0 + pulse * 4.0, 0.0, TAU, 40, green, 2.5)
		draw_circle(Vector2.ZERO, 4.0, green)
