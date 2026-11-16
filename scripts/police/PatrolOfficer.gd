extends "res://scripts/police/PoliceOfficer.gd"
## Partioiva poliisi: kävelee jalkakäytävillä, pysäyttää pelaajan satunnaisesti
## ja tekee puhalluskokeen.
##
## Tilat:
##   PATROL  -> kävelee ympäriinsä
##   ORDER   -> huutaa "Seis!", kävelee pelaajan luo. Pelaajan pitää pysähtyä (ei liikenappeja).
##   TEST    -> puhalluskoe, pelaaja lukitaan paikalleen hetkeksi
##   CHASE   -> pelaaja pakeni: etsintäkuulutus ja normaali poliisin jahti
##
## PolicePatrol luo tämän ja asettaa city, manager ja patrol ennen add_child:ia.

enum Mode { PATROL, ORDER, TEST, CHASE }

const PATROL_SPEED := 55.0
const CHASE_SPEED := 105.0
const SCAN_INTERVAL := 0.4
const ORDER_TIME := 4.0        ## kuinka kauan pelaajalla on aikaa pysähtyä
const STILL_NEEDED := 0.4      ## kuinka kauan pelaajan pitää olla paikallaan
const REACH_DIST := 26.0       ## tästä etäisyydestä puhalluskoe alkaa
const ESCAPE_DIST := 260.0     ## tätä kauemmas = pelaaja karkasi
const TEST_TIME := 2.2

var patrol: Node
var mode: Mode = Mode.PATROL
var wait := 0.0
var _scan := 0.0
var _order_left := 0.0
var _still := 0.0
var _complied := false


func _ready() -> void:
	super()
	speed = PATROL_SPEED
	wait = randf_range(0.0, 2.0)
	_scan = randf_range(0.0, SCAN_INTERVAL)


func _process(delta: float) -> void:
	if dead:
		return
	match mode:
		Mode.PATROL:
			_patrol(delta)
		Mode.ORDER:
			_order(delta)
		Mode.TEST:
			pass   # PolicePatrol hoitaa kokeen (await), poliisi seisoo paikallaan
		Mode.CHASE:
			super(delta)


# ----------------------------------------------------------------------------
#  PARTIOINTI
# ----------------------------------------------------------------------------
func _patrol(delta: float) -> void:
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_INTERVAL
		if _try_stop_player():
			return

	if wait > 0.0:
		wait -= delta
		_set_walking(false, delta)
		return

	if not moving:
		if path.is_empty():
			path = city.ped_path(cell)
			if path.is_empty():
				wait = randf_range(0.5, 1.5)
				return
		next_cell = path.pop_front()
		target_pos = city.cell_to_world(next_cell)
		_set_dir(target_pos - global_position)
		moving = true

	if not _move_towards(target_pos, delta):
		cell = next_cell
		moving = false
		if path.is_empty():
			wait = randf_range(1.0, 3.5)
	_set_walking(true, delta)


func _set_walking(walking: bool, delta: float) -> void:
	if walking:
		anim += delta
		var st := 1 + (int(anim * 7.0) % 2)
		if st != step:
			step = st
			_refresh()
	elif step != 0:
		step = 0
		_refresh()


## Huomaako pelaajan lähellä ja päättää (satunnaisesti) pysäyttää hänet.
func _try_stop_player() -> bool:
	if not patrol.can_check(self):
		return false
	if randf() > patrol.check_chance:
		return false
	_start_order()
	return true


# ----------------------------------------------------------------------------
#  PYSÄYTYSKÄSKY
# ----------------------------------------------------------------------------
func _start_order() -> void:
	patrol.begin_check(self)
	mode = Mode.ORDER
	speed = CHASE_SPEED
	path.clear()
	repath = 0.0
	_order_left = ORDER_TIME
	_still = 0.0
	_complied = false
	say("Seis! Poliisi!")
	patrol.hud_message("Poliisi käskee pysähtymään! Pysähdy.", 2.5)


func _order(delta: float) -> void:
	# Pelaaja meni sisälle / sammui: käsky raukeaa
	if not patrol.player_available():
		patrol.end_check(self)
		resume_patrol()
		return
	super._process(delta)   # kävelee pelaajaa kohti (PoliceOfficer-liike)
	var tgt: Vector2 = manager.target_position()
	var dist := global_position.distance_to(tgt)

	if patrol.player_is_stopped():
		_still += delta
	else:
		_still = 0.0
		if _complied and dist > REACH_DIST:
			_complied = false   # lähti liikkeelle uudelleen
	if _still >= STILL_NEEDED:
		_complied = true

	if _complied and dist <= REACH_DIST:
		_start_test()
		return

	_order_left -= delta
	if dist > ESCAPE_DIST or (_order_left <= 0.0 and not _complied):
		_player_fled()


# ----------------------------------------------------------------------------
#  PUHALLUSKOE
# ----------------------------------------------------------------------------
func _start_test() -> void:
	mode = Mode.TEST
	moving = false
	path.clear()
	_set_walking(false, 0.0)
	_set_dir(manager.target_position() - global_position)
	patrol.run_breath_test(self)


## PolicePatrol kutsuu kun koe on ohi.
func resume_patrol() -> void:
	if dead:
		return
	mode = Mode.PATROL
	speed = PATROL_SPEED
	path.clear()
	moving = false
	repath = 0.0
	cell = city.world_to_cell(global_position)
	wait = 1.0


## Pelaaja ei pysähtynyt: etsintäkuulutus ja jahti.
func _player_fled() -> void:
	mode = Mode.CHASE
	speed = CHASE_SPEED
	path.clear()
	repath = 0.0
	say("Pysähdy!")
	patrol.end_check(self)
	manager.adopt_officer(self)
	patrol.hud_message("Pakenit poliisia! Etsintäkuulutus.", 3.0)
	manager.report_crime(1)


func _chasing() -> bool:
	return mode == Mode.CHASE


## Etsintäkuulutus alkoi muusta syystä: partio liittyy jahtiin.
func join_chase() -> void:
	if mode == Mode.CHASE or dead:
		return
	if mode == Mode.TEST:
		return
	if mode == Mode.ORDER:
		patrol.end_check(self)
	mode = Mode.CHASE
	speed = CHASE_SPEED
	path.clear()
	repath = 0.0
	manager.adopt_officer(self)


## Puhekupla poliisin yläpuolelle.
func say(text: String, seconds: float = 1.6) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(-44.0, -30.0)
	l.size = Vector2(88.0, 12.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.z_index = 30
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


func _die() -> void:
	if mode == Mode.ORDER or mode == Mode.TEST:
		patrol.end_check(self)
	super()
