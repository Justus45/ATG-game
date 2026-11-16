extends "res://scripts/police/PoliceCar.gd"
## Partioiva poliisiauto: ajaa tieverkolla kuin liikenne (ei valoja). Satunnaisesti
## se päättää pysäyttää pelaajan: valot päälle, ajaa pelaajan viereen ja tekee puhalluskokeen.
##
## Tilat:
##   PATROL -> ajelee teillä
##   ORDER  -> valot päällä, ajaa pelaajan luo. Pelaajan pitää pysähtyä (ei liikenappeja).
##   TEST   -> puhalluskoe, pelaaja lukitaan paikalleen hetkeksi
##   CHASE  -> pelaaja pakeni: etsintäkuulutus ja normaali poliisiauton jahti
##
## PolicePatrol luo tämän ja asettaa city, manager ja patrol ennen add_child:ia.

enum Mode { PATROL, ORDER, TEST, CHASE }

const PATROL_SPEED := 70.0
const CHASE_SPEED := 135.0
const SCAN_INTERVAL := 0.4
const ORDER_TIME := 6.0        ## kuinka kauan pelaajalla on aikaa pysähtyä
const STILL_NEEDED := 0.4      ## kuinka kauan pelaajan pitää olla paikallaan
const REACH_DIST := 44.0       ## tästä etäisyydestä puhalluskoe alkaa
const ESCAPE_DIST := 320.0     ## tätä kauemmas = pelaaja karkasi
const TEST_TIME := 2.2

var patrol: Node
var mode: Mode = Mode.PATROL
var _scan := 0.0
var _order_left := 0.0
var _still := 0.0
var _stuck := 0.0
var _complied := false
## Partioreitti oikealla kaistalla (city.lane_route): ruudut ja niiden suunnat
var _route: Array = []
var _route_faces: Array = []


func _ready() -> void:
	super()
	speed = PATROL_SPEED
	_scan = randf_range(0.0, SCAN_INTERVAL)
	_set_lights(false)
	_pick_dir()


func _process(delta: float) -> void:
	if wrecked:
		_wreck_process(delta)
		return
	if dead:
		return
	match mode:
		Mode.PATROL:
			_patrol(delta)
			_watchdog(delta, global_position + Vector2(10000.0, 0.0))
		Mode.ORDER:
			_order(delta)
			# käsky kestää vain hetken; jos auto ei pääse pelaajan luo, koe tehdään paikalta
		Mode.TEST:
			pass   # PolicePatrol hoitaa kokeen (await), auto seisoo
		Mode.CHASE:
			super(delta)


func _set_lights(on: bool) -> void:
	light_a.visible = on
	light_b.visible = on


## Valitsee tien suuntaisen ajosuunnan, jossa on tietä edessä. Poikittainen suunta
## (leveän tien kaistalta toiselle) jumitti auton aiemmin heilumaan paikallaan.
func _pick_dir() -> void:
	var c := city.world_to_cell(global_position)
	if not city.is_road(c):
		var r := _nearest_road(c)
		if r != Vector2i(-1, -1):
			_snap_to(r)
			c = r
	var dirs: Array[Vector2i] = []
	var vertical: bool = city.col_road[c.x] == 1 if city._in_bounds(c) else false
	var horizontal: bool = city.row_road[c.y] == 1 if city._in_bounds(c) else false
	if vertical:
		dirs.append_array([Vector2i.DOWN, Vector2i.UP])
	if horizontal:
		dirs.append_array([Vector2i.RIGHT, Vector2i.LEFT])
	if dirs.has(dir):
		dirs.erase(dir)
		dirs.push_front(dir)
	for d in dirs:
		if city.is_road(c + d):
			dir = d
			break
	cell = c
	_route.clear()
	_route_faces.clear()
	_refresh()

## Partioauto tuhoutui: kesken ollut pysäytys / puhalluskoe raukeaa.
func _on_wrecked() -> void:
	if mode == Mode.ORDER or mode == Mode.TEST:
		if is_instance_valid(patrol) and patrol.has_method("end_check"):
			patrol.end_check(self)

func _on_unstuck() -> void:
	if mode == Mode.PATROL:
		_pick_dir()


# ----------------------------------------------------------------------------
#  PARTIOINTI
# ----------------------------------------------------------------------------
func _patrol(delta: float) -> void:
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_INTERVAL
		if _try_stop_player():
			return

	if not moving:
		# Pysytään omalla kaistalla (ei ajeta vastaantulevien kaistalla)
		if _route.is_empty():
			var r: Dictionary = city.lane_route(cell, dir)
			if r.is_empty():
				return
			_route = (r["cells"] as Array).duplicate()
			_route_faces = (r["faces"] as Array).duplicate()
		var n: Vector2i = _route.pop_front()
		var f: Vector2i = _route_faces.pop_front()
		var d := n - cell
		if d == Vector2i.ZERO:
			return
		next_cell = n
		target_pos = city.cell_to_world(n)
		var nd := dir
		if f != Vector2i.ZERO:
			nd = f
		elif d.x == 0 or d.y == 0:
			nd = Vector2i(signi(d.x), signi(d.y))
		if nd != dir:
			dir = nd
			_refresh()
		moving = true

	var to := target_pos - global_position
	var dist := speed * delta
	if to.length() <= dist:
		global_position = target_pos
		cell = next_cell
		moving = false
	else:
		global_position += to.normalized() * dist


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
	unloaded = true   # ei päästetä poliiseja ulos, tarkastus tehdään autosta
	path.clear()
	repath = 0.0
	_order_left = ORDER_TIME
	_still = 0.0
	_stuck = 0.0
	_complied = false
	_set_lights(true)
	say("Pysähdy tien laitaan!")
	patrol.hud_message("Poliisiauto vilkuttaa valoja! Pysähdy.", 2.5)


func _order(delta: float) -> void:
	# Pelaaja meni sisälle / sammui: käsky raukeaa
	if not patrol.player_available():
		patrol.end_check(self)
		resume_patrol()
		return
	var tgt: Vector2 = manager.target_position()
	var dist := global_position.distance_to(tgt)
	# Pysähtynyttä pelaajaa ei rammata: partio ajaa lähelle ja jää odottamaan viereen
	var halt: bool = dist <= REACH_DIST * 1.25 and (bool(patrol.player_is_stopped()) or _complied)
	if halt:
		if moving:
			cell = city.world_to_cell(global_position)
			moving = false
		path.clear()
	else:
		super._process(delta)   # ajaa pelaajaa kohti (PoliceCar-liike)

	if patrol.player_is_stopped():
		_still += delta
	else:
		_still = 0.0
		if _complied and dist > REACH_DIST:
			_complied = false   # lähti liikkeelle uudelleen
	if _still >= STILL_NEEDED:
		_complied = true

	# Auto on perillä lähimmällä tieruudulla vaikkei ihan vieressä (esim. pelaaja puistossa)
	if _complied and not moving and path.is_empty():
		_stuck += delta
	else:
		_stuck = 0.0
	if _complied and not moving and (dist <= REACH_DIST or _stuck > 1.0):
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
	path.clear()
	patrol.run_breath_test(self)


## PolicePatrol kutsuu kun koe on ohi.
func resume_patrol() -> void:
	if dead:
		return
	mode = Mode.PATROL
	speed = PATROL_SPEED
	_set_lights(false)
	unloaded = true
	path.clear()
	repath = 0.0
	if not moving:
		cell = city.world_to_cell(global_position)
		_pick_dir()


## Pelaaja ei pysähtynyt: etsintäkuulutus ja jahti.
func _player_fled() -> void:
	mode = Mode.CHASE
	speed = CHASE_SPEED
	unloaded = false
	path.clear()
	repath = 0.0
	say("Pysähdy!")
	patrol.end_check(self)
	manager.adopt_car(self)
	patrol.hud_message("Pakenit poliisia! Etsintäkuulutus.", 3.0)
	manager.report_crime(1)


## Etsintäkuulutus alkoi muusta syystä: partioauto liittyy jahtiin.
func join_chase() -> void:
	if mode == Mode.CHASE or mode == Mode.TEST or dead:
		return
	if mode == Mode.ORDER:
		patrol.end_check(self)
	mode = Mode.CHASE
	speed = CHASE_SPEED
	unloaded = false
	path.clear()
	repath = 0.0
	_set_lights(true)
	manager.adopt_car(self)


## Puhekupla auton yläpuolelle.
func say(text: String, seconds: float = 1.6) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(-50.0, -34.0)
	l.size = Vector2(100.0, 12.0)
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
