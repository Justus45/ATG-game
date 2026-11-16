extends Node

const OfficerScript := preload("res://scripts/police/PoliceOfficer.gd")
const CarScript := preload("res://scripts/police/PoliceCar.gd")
const JailScript := preload("res://scripts/world/Jail.gd")
const PICKUP_SCENE: PackedScene = preload("res://scenes/entities/weapons/weapon_pickup.tscn")

@export var heat_for_level: Array[int] = [0, 1, 4, 8, 13, 20]
const FOOT_KINDS := [[], ["police", "police"], ["police", "police", "police"],
	["police", "police", "police", "police"], ["police", "police", "swat", "swat"],
	["police", "swat", "swat", "army", "army", "army"]]
const CAR_KINDS := [[], [], ["police"], ["police", "police"], ["police", "swat"], ["swat", "army", "army"]]
@export var calm_seconds: float = 20.0
@export var sight_range: float = 260.0
@export var bust_seconds: float = 2.0
@export var jail_base: float = 12.0
@export var jail_per_heat: float = 6.0
@export var jail_max: float = 120.0
@export var spawn_min_cells: int = 20
@export var spawn_max_cells: int = 28
@export var fine_max_heat: int = 2
@export var fine_base: int = 25
@export var fine_per_heat: int = 20
@export var bail_per_second: float = 2.0
@export var witness_range: float = 170.0
@export var max_callers: int = 3

var city: CityGenerator
var level_root: Node
var player: Node2D
var car: Node2D
var hud: Node

var heat := 0
var wanted := 0
var calm_timer := 0.0
var searching := false   
var bust_meter := 0.0
var road_astar := AStarGrid2D.new()
var officers: Array[Node2D] = []
var cars: Array[Node2D] = []
var _respawn_timer := 0.0
var jail: Node2D
var _serious := false
var _fining := false   
var _crime_id := 0
var _reported: Dictionary = {}  

func _ready() -> void:
	add_to_group("police_manager")
	level_root = get_parent()
	city = level_root.get_node("City")
	player = level_root.get_node("Player")
	car = level_root.get_node_or_null("Car")
	hud = level_root.get_node_or_null("Hud")
	jail = JailScript.new()
	jail.city = city
	add_child(jail)
	jail.setup(city.ground_layer.tile_set, city.source_id)
	jail.bail_per_second = bail_per_second
	_build_road_graph()
	_update_hud()

func _build_road_graph() -> void:
	road_astar.region = Rect2i(0, 0, city.map_w, city.map_h)
	road_astar.cell_size = Vector2(city.tile, city.tile)
	road_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	road_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	road_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	road_astar.update()
	for y in city.map_h:
		for x in city.map_w:
			var c := Vector2i(x, y)
			if not city.is_road(c):
				road_astar.set_point_solid(c)

func player_in_car() -> bool:
	return is_instance_valid(car) and "is_driving" in car and car.is_driving


func set_player_car(c: Node2D) -> void:
	
	if wanted > 0 and c != car and is_instance_valid(car) and searching:
		calm_timer = minf(calm_timer, 3.0)
		_hud_message("Vaihdoit autoa! Poliisi etsii väärää autoa.", 2.5)
	car = c

func target_position() -> Vector2:
	if player_in_car():
		return car.global_position
	return player.body_center()

func report_crime(points: int, serious: bool = false) -> void:
	if jail.serving or Game.heist_active:
		return
	heat += points
	Game.note_crime()
	Game.add_rep("criminals", 1)
	if serious:
		_serious = true
	calm_timer = eff_calm_seconds()
	_set_wanted(_level_for_heat())

func commit_crime(points: int, at: Vector2, victim: Node = null, serious: bool = false) -> void:
	if jail.serving or Game.heist_active:
		return
	Game.add_vitutus(Game.VITUTUS_CRIME * points * (1.5 if serious else 1.0))
	if wanted > 0 or _police_sees_point(at):
		report_crime(points, serious)
		return
	_crime_id += 1
	var callers := 0
	if is_instance_valid(victim) and victim.has_method("start_call") and victim.can_witness():
		victim.start_call(self, _crime_id, points, serious, 2.5)
		callers += 1
	for w in _find_witnesses(at, victim):
		if callers >= max_callers:
			break
		w.start_call(self, _crime_id, points, serious, randf_range(0.2, 0.8))
		callers += 1
	if callers == 0:
		_hud_message("Kukaan ei nähnyt.", 1.6)
	elif callers == 1:
		_hud_message("Todistaja soittaa poliisille! Vaienna hänet tai häivy näkyvistä.", 3.0)
	else:
		_hud_message("%d todistajaa soittaa poliisille! Vaienna tai häivy näkyvistä." % callers, 3.0)

func _find_witnesses(at: Vector2, exclude: Node) -> Array[Node2D]:
	var found: Array[Node2D] = []
	for n in get_tree().get_nodes_in_group("shootable"):
		if n == exclude or not is_instance_valid(n) or not n.has_method("start_call"):
			continue
		if not n.can_witness():
			continue
		var nd := n as Node2D
		if nd.global_position.distance_to(at) > witness_range * Game.visibility():
			continue
		if _line_clear(nd.global_position, at):
			found.append(nd)
	found.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.global_position.distance_squared_to(at) < b.global_position.distance_squared_to(at))
	return found

func witness_report(crime_id: int, points: int, serious: bool, saw_player: bool) -> bool:
	if jail.serving or _reported.has(crime_id):
		return false
	if not saw_player:
		_hud_message("Todistaja soitti, mutta olit jo poissa näkyvistä.", 2.4)
		return false
	_reported[crime_id] = true
	if _reported.size() > 64:
		_reported.clear()
		_reported[crime_id] = true
	_hud_message("Todistaja soitti poliisille! Sinusta on tuntomerkit.", 2.8)
	report_crime(points, serious)
	return true

func can_see_player_from(from: Vector2, max_dist: float) -> bool:
	var t := target_position()
	return from.distance_to(t) <= max_dist and _line_clear(from, t)

func _police_sees_point(at: Vector2) -> bool:
	var units: Array = officers + cars
	var patrol := get_tree().get_first_node_in_group("police_patrol")
	if patrol and "patrols" in patrol:
		units.append_array(patrol.patrols)
	for u in units:
		if not is_instance_valid(u) or u.dead:
			continue
		var un := u as Node2D
		if un.global_position.distance_to(at) > eff_sight_range():
			continue
		if _line_clear(un.global_position, at):
			return true
	return false

func _hud_message(text: String, seconds: float) -> void:
	if hud and hud.has_method("show_message"):
		hud.show_message(text, seconds)

func _level_for_heat() -> int:
	var lvl := 0
	for i in heat_for_level.size():
		if heat >= heat_for_level[i]:
			lvl = i
	return lvl

func _set_wanted(level: int) -> void:
	level = clampi(level, 0, heat_for_level.size() - 1)
	if level == wanted:
		return
	var rising := level > wanted
	wanted = level
	_update_hud()
	if rising and wanted == 4:
		_hud_message("Neljä tähteä: poliisit vetivät aseet esiin ja SWAT hälytetty! Ne ampuvat.", 3.0)
	elif rising and wanted == 5:
		_hud_message("Viisi tähteä: armeija kutsuttiin paikalle! Sotilaat ampuvat.", 3.0)
	if wanted == 0:
		_serious = false
		_set_searching(false)
		_stand_down()

func _update_hud() -> void:
	if hud and hud.has_method("set_wanted"):
		hud.set_wanted(wanted)

func _set_searching(value: bool) -> void:
	if value == searching:
		return
	searching = value
	if hud and hud.has_method("set_searching"):
		hud.set_searching(searching)

func _process(delta: float) -> void:
	_update_siren()
	if wanted <= 0 or jail.serving:
		return
	_update_bust(delta)
	_update_calm(delta)
	_maintain_police(delta)

func eff_sight_range() -> float:
	return sight_range * Game.visibility() + 15.0 * Game.recognition()

func eff_calm_seconds() -> float:
	return calm_seconds + 3.0 * Game.recognition()

func eff_bust_seconds() -> float:
	return bust_seconds * (1.0 - 0.08 * Game.recognition())

var _hide_msg_shown := false

func _update_calm(delta: float) -> void:
	var hiding: bool = city.home != null and Game.flag(city.home, "inside")
	if not hiding and Game.owns_manor:
		var mi := get_tree().get_first_node_in_group("manor_interior")
		hiding = mi != null and Game.flag(mi, "inside")
	if not hiding and _police_sees_player():
		calm_timer = eff_calm_seconds()
		_set_searching(false)
		_hide_msg_shown = false
		return
	if hiding:
		delta *= 4.0
		if not _hide_msg_shown:
			_hide_msg_shown = true
			_hud_message("Piiloudut kotona. Poliisi menettää jäljet nopeammin.", 2.5)
	_set_searching(true)
	calm_timer -= delta
	if calm_timer <= 0.0:
		calm_timer = eff_calm_seconds()
		heat = heat_for_level[maxi(wanted - 1, 0)]
		_set_wanted(_level_for_heat())

func _update_siren() -> void:
	if wanted <= 0 or jail.serving:
		Sfx.set_siren(0.0)
		return
	var t := target_position()
	var best := 99999.0
	for c in cars:
		if is_instance_valid(c) and not c.dead:
			best = minf(best, c.global_position.distance_to(t))
	Sfx.set_siren(clampf(1.0 - best / 700.0, 0.0, 1.0))

func _police_sees_player() -> bool:
	var t := target_position()
	for u in officers + cars:
		if not is_instance_valid(u) or u.dead:
			continue
		if u.global_position.distance_to(t) > eff_sight_range():
			continue
		if _line_clear(u.global_position, t):
			return true
	return false

func _line_clear(from: Vector2, to: Vector2) -> bool:
	var steps := int(from.distance_to(to) / (city.tile * 0.5))
	if steps < 2:
		return true
	var last := Vector2i(-99999, -99999)
	for i in range(1, steps):
		var c := city.world_to_cell(from.lerp(to, float(i) / float(steps)))
		if c == last:
			continue
		last = c
		if not city.is_walkable(c):
			return false
	return true

func _update_bust(delta: float) -> void:
	var t := target_position()
	var near := 0
	for o in officers:
		if is_instance_valid(o) and not o.dead and o.global_position.distance_to(t) < 20.0:
			near += 1
	for c in cars:
		if is_instance_valid(c) and not c.dead and c.global_position.distance_to(t) < 26.0:
			near += 1
	if near > 0:
		bust_meter += delta * (0.6 + 0.4 * near)
	else:
		bust_meter = maxf(bust_meter - delta * 1.5, 0.0)
	if bust_meter >= eff_bust_seconds():
		_bust()

func _maintain_police(delta: float) -> void:
	_respawn_timer -= delta
	if _respawn_timer > 0.0:
		return
	_prune(officers)
	_prune(cars)
	var foot_kind := _missing_kind(officers, FOOT_KINDS[wanted])
	var car_kind := _missing_kind(cars, CAR_KINDS[wanted])
	if foot_kind != "":
		var c := _find_spawn_cell(false)
		if c != Vector2i(-1, -1):
			_add_officer(city.cell_to_world(c), foot_kind)
		_respawn_timer = 1.2
	elif car_kind != "":
		var c := _find_spawn_cell(true)
		if c != Vector2i(-1, -1):
			_add_car(city.cell_to_world(c), car_kind)
		_respawn_timer = 2.5

func _missing_kind(list: Array[Node2D], wanted_kinds: Array) -> String:
	var have := {}
	for u in list:
		if is_instance_valid(u) and not u.dead:
			var k: String = str(u.get("kind")) if u.get("kind") != null else "police"
			have[k] = int(have.get(k, 0)) + 1
	var need := {}
	for k: String in wanted_kinds:
		need[k] = int(need.get(k, 0)) + 1
	for k: String in ["army", "swat", "police"]:
		if int(need.get(k, 0)) > int(have.get(k, 0)):
			return k
	return ""

func _prune(list: Array[Node2D]) -> void:
	var t := target_position()
	for i in range(list.size() - 1, -1, -1):
		var u := list[i]
		if not is_instance_valid(u) or u.dead:
			list.remove_at(i)
		elif u.global_position.distance_to(t) > 800.0:
			u.queue_free()
			list.remove_at(i)

func _find_spawn_cell(on_road: bool) -> Vector2i:
	var tcell := city.world_to_cell(target_position())
	for i in 40:
		var offset := Vector2.from_angle(randf() * TAU) * randf_range(spawn_min_cells, spawn_max_cells)
		var c := tcell + Vector2i(offset.round())
		if on_road:
			if city.is_road(c):
				return c
		elif city.is_walkable(c):
			return c
	return Vector2i(-1, -1)

func _add_officer(world_pos: Vector2, kind: String = "police") -> void:
	var o = OfficerScript.new()
	o.kind = kind
	o.city = city
	o.manager = self
	o.position = city.entities.to_local(world_pos)
	city.entities.add_child(o)
	officers.append(o)

func _add_car(world_pos: Vector2, kind: String = "police") -> void:
	var c = CarScript.new()
	c.kind = kind
	c.city = city
	c.manager = self
	c.speed = 115.0 + 15.0 * mini(wanted, 3) + (20.0 if kind == "army" else 0.0)
	c.position = city.entities.to_local(world_pos)
	city.entities.add_child(c)
	cars.append(c)

## Poliisiauto on perillä: poliisit hyppäävät ulos.
func unload_officers(world_pos: Vector2, count: int, kind: String = "police") -> void:
	var c := city.world_to_cell(world_pos)
	var spots: Array[Vector2i] = []
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if city.is_walkable(c + d):
			spots.append(c + d)
	for i in count:
		var cell := spots[i % spots.size()] if not spots.is_empty() else c
		_add_officer(city.cell_to_world(cell), kind)

func officer_killed(o: Node2D) -> void:
	officers.erase(o)
	_respawn_timer = maxf(_respawn_timer, 4.0)
	report_crime(2, true)

func arrest(message: String, seconds: int, sober: bool = false, fine: int = 0) -> void:
	_bust(message, seconds, sober, fine)
	
func sentence_for_heat(h: int) -> int:
	return int(clampf(round(jail_base + h * jail_per_heat), jail_base, jail_max))

func fine_for_heat(h: int) -> int:
	if h > fine_max_heat or _serious:
		return 0
	return fine_base + h * fine_per_heat

func adopt_officer(o: Node2D) -> void:
	if not officers.has(o):
		officers.append(o)

func adopt_car(c: Node2D) -> void:
	if not cars.has(c):
		cars.append(c)

func _bust(message: String = "", seconds: int = -1, sober: bool = false, fine: int = 0) -> void:
	if jail.serving or _fining:
		return
	Game.add_vitutus(Game.VITUTUS_ARREST)
	bust_meter = 0.0
	# varastettu saalis (juoksuostokset, ryöstö) takavarikoidaan
	if not Game.loot.is_empty():
		Game.loot.clear()
		_hud_message("Poliisi takavarikoi varastetut tavarat.", 2.5)
	# Tuomio ja sakko lasketaan ennen kuin lämpö nollataan
	if seconds < 0:
		seconds = sentence_for_heat(heat)
		fine = fine_for_heat(heat)
	if player_in_car():
		car.exit_car()

	# Lievä rikos: sakko paikan päällä, jos rahat riittävät
	var fine_note := ""
	if fine > 0:
		if player.money >= fine:
			_pay_fine(fine, message)
			return
		fine_note = " Sakko %d $, mutta rahat eivät riittäneet: sakko muunnettiin vankeudeksi." % fine
	# Putkaan: kartanon hovimestari hakee kadulle jääneet autot talliin
	Game.butler_fetch_cars(4.0)

	# Rikosrekisteri pidentää tuomiota
	seconds = int(round(float(seconds) * Game.sentence_mult()))
	var had_weapon: bool = player.has_weapon()
	var weapon_kept := false
	if had_weapon:
		var wid: String = player.held_weapon.weapon_id
		player.held_weapon.unequip()
		if not _serious:
			# Ase säilytykseen: palautetaan vapautuksen jälkeen
			Game.stored_weapon = wid
			weapon_kept = true
		else:
			# Henkirikos: ase jää todisteeksi (uuden saa asekaupasta)
			Game.stored_weapon = ""
	# Kranaatit takavarikoidaan aina
	if int(player.grenades) > 0:
		player.add_grenades(-int(player.grenades))
	# Lompakosta takavarikoidaan osa rikoshyötynä (pankin rahat ovat turvassa)
	var seized := int(player.money * 0.15) if not sober else 0
	if seized > 0:
		player.add_money(-seized)
	Game.note_arrest(seconds)
	player.velocity = Vector2.ZERO
	player.nearby_weapon = null
	_clear_police()
	heat = 0
	calm_timer = 0.0
	_set_searching(false)
	_set_wanted(0)

	var weapon_note := ""
	if had_weapon:
		weapon_note = " Ase otettiin säilöön." if weapon_kept else " Ase takavarikoitiin todisteeksi."
	var intro := message
	if intro == "":
		intro = "Sinut pidätettiin!"
	intro += weapon_note
	if seized > 0:
		intro += " Lompakosta takavarikoitiin %d $." % seized
	if Game.recognition() >= 2:
		intro += " Vanha tuttu – tuomio on pidempi."
	intro += fine_note
	# Vapautus: kodin oven eteen (kartanon omistajalla kartanon ovelle, Home.door_px siirtyy sinne).
	# Jail._move_player vähentää törmäysmuodon siirron itse, joten annetaan jalkojen kohta.
	var release_at: Vector2 = city.player_start_global
	if city.home != null:
		release_at = (city.home.get("door_px") as Vector2) + Vector2(0.0, 28.0)
	jail.serve(player, seconds, intro, release_at, sober)

## Sakko maksetaan paikan päällä: poliisi pitää pelaajaa hetken, ottaa rahat ja päästää menemään.
func _pay_fine(fine: int, message: String) -> void:
	_fining = true
	player.velocity = Vector2.ZERO
	player.set("police_locked", true)
	_clear_police()
	heat = 0
	calm_timer = 0.0
	_set_searching(false)
	_set_wanted(0)
	var text := message if message != "" else "Pysähdy, poliisi!"
	_hud_message(text + " Sakko %d $." % fine, 3.0)
	await get_tree().create_timer(1.4).timeout
	player.add_money(-fine)
	Game.note_fine()
	_hud_message("Maksoit sakon %d $. Saat jatkaa – pidä itsesi kurissa." % fine, 3.0)
	await get_tree().create_timer(0.6).timeout
	player.set("police_locked", false)
	_fining = false

func _stand_down() -> void:
	_clear_police()
	bust_meter = 0.0

func _clear_police() -> void:
	for u in officers + cars:
		if is_instance_valid(u):
			u.dismiss()
	officers.clear()
	cars.clear()
