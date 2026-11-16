extends Node
## Partioivat poliisiautot: ylläpitää muutamaa teillä ajelevaa poliisiautoa
## pelaajan lähellä. Poliisiauto pysäyttää pelaajan satunnaisesti ja tekee puhalluskokeen:
##   - pelaaja pysähtyy ja on juonut  -> pidätys
##   - pelaaja pysähtyy ja on selvä   -> saa jatkaa
##   - pelaaja ei pysähdy             -> etsintäkuulutus (PoliceManager hoitaa jahdin)

const PatrolScript := preload("res://scripts/police/PatrolCar.gd")

## Montako partiopoliisiautoa on pelaajan lähellä
@export var patrol_count: int = 3
## Syntyetäisyys ruutuina pelaajasta
@export var spawn_min_cells: int = 12
@export var spawn_max_cells: int = 22
## Tätä kauemmas jääneet partiot poistetaan (ja luodaan uusia lähelle)
@export var despawn_distance: float = 800.0
## Kuinka lähellä poliisin pitää olla pelaajaa ennen kuin hän voi pysäyttää tämän (px)
@export var check_range: float = 170.0
## Todennäköisyys pysäyttää pelaaja jokaisella tarkistuksella (0.4 s välein), kun ehdot täyttyvät
@export var check_chance: float = 0.11
## Tarkastusten väli sekunteina (alkaa pelin alusta ja jokaisen tarkastuksen jälkeen)
@export var cooldown_seconds: float = 60.0
@export var first_check_delay: float = 15.0
## Tästä promillemäärästä ylöspäin puhalluskoe on positiivinen
@export var breath_limit: float = 0.05
## Rattijuopumuksen putkatuomio (s) = base + promillet * per_promille
@export var drunk_jail_base: float = 15.0
@export var drunk_jail_per_promille: float = 15.0
## Lievä rattijuopumus (alle tämän promillemäärän) kuitataan sakolla, jos rahat riittävät
@export var drunk_fine_limit: float = 0.5
@export var drunk_fine_base: int = 40
@export var drunk_fine_per_promille: int = 120

var manager: Node
var city: CityGenerator
var player: Node2D
var patrols: Array[Node2D] = []
var active_officer: Node2D = null
var _cooldown := 0.0
var _spawn_timer := 0.0


func _ready() -> void:
	add_to_group("police_patrol")
	var level := get_parent()
	manager = level.get_node("PoliceManager")
	city = level.get_node("City")
	player = level.get_node("Player")
	_cooldown = first_check_delay
	_base_check_chance = check_chance


var _base_check_chance := 0.11

## Partioiden määrä ja tarkastusten tiheys vaihtelevat vuorokaudenajan, maineen ja
## kuljetettavan lastin mukaan (salakuljetuskeikka).
func _update_intensity() -> void:
	match Game.period():
		"päivä":
			patrol_count = 2
		"ilta":
			patrol_count = 3
		_:
			patrol_count = 4
	var c := _base_check_chance
	if Game.is_night():
		c *= 1.5   # yöllä etsitään rattijuoppoja
	if int(Game.rep.police) <= -30:
		c *= 1.4
	if _carrying_contraband():
		c *= 2.0
	check_chance = c


func _carrying_contraband() -> bool:
	var jm := get_tree().get_first_node_in_group("job_manager")
	return jm != null and Game.flag(jm, "contraband")


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_update_intensity()
	_prune()

	# Etsintäkuulutus päällä: kaikki lähellä olevat partiot liittyvät jahtiin
	if manager.wanted > 0:
		var t: Vector2 = manager.target_position()
		for o in patrols:
			if is_instance_valid(o) and not o.dead and o.global_position.distance_to(t) < 600.0:
				o.join_chase()
		return

	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and patrols.size() < patrol_count:
		_spawn_timer = 1.0
		var c := _find_spawn_cell()
		if c != Vector2i(-1, -1):
			_add_patrol(city.cell_to_world(c))


# ----------------------------------------------------------------------------
#  LUONTI
# ----------------------------------------------------------------------------
func _prune() -> void:
	var t: Vector2 = manager.target_position()
	for i in range(patrols.size() - 1, -1, -1):
		var o := patrols[i]
		if not is_instance_valid(o) or o.dead:
			patrols.remove_at(i)
		elif o != active_officer and o.mode != PatrolScript.Mode.CHASE \
				and o.global_position.distance_to(t) > despawn_distance:
			o.queue_free()
			patrols.remove_at(i)
	if active_officer != null and (not is_instance_valid(active_officer) or active_officer.dead):
		active_officer = null


## Tieruutu sopivalla etäisyydellä pelaajasta.
func _find_spawn_cell() -> Vector2i:
	var tcell := city.world_to_cell(manager.target_position())
	for i in 60:
		var offset := Vector2.from_angle(randf() * TAU) * randf_range(spawn_min_cells, spawn_max_cells)
		var c := tcell + Vector2i(offset.round())
		if city.is_road(c):
			return c
	return Vector2i(-1, -1)


func _add_patrol(world_pos: Vector2) -> void:
	var o = PatrolScript.new()
	o.speed = 70.0
	o.city = city
	o.manager = manager
	o.patrol = self
	o.position = city.entities.to_local(world_pos)
	city.entities.add_child(o)
	patrols.append(o)


# ----------------------------------------------------------------------------
#  TARKASTUKSEN EHDOT
# ----------------------------------------------------------------------------
## Saako tämä poliisi pysäyttää pelaajan juuri nyt?
func can_check(o: Node2D) -> bool:
	if _cooldown > 0.0 or active_officer != null or manager.wanted > 0:
		return false
	if not player_available():
		return false
	var t: Vector2 = manager.target_position()
	if o.global_position.distance_to(t) > check_range:
		return false
	return manager._line_clear(o.global_position, t)


## Pelaaja ajaa autoa kadulla. Jalan liikkuvaa ei pysäytetä. Ei myöskään sisätiloissa,
## putkassa, sammumassa eikä oven siirtymässä.
func player_available() -> bool:
	if player.get("police_locked"):
		return false
	if Game.player_indoors():
		return false
	return manager.player_in_car()


## Pelaaja on pysähtynyt = ei paina liikenappeja.
func player_is_stopped() -> bool:
	return Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down").length() < 0.1


func begin_check(o: Node2D) -> void:
	active_officer = o
	_cooldown = cooldown_seconds


func end_check(o: Node2D) -> void:
	if active_officer == o:
		active_officer = null


func hud_message(text: String, seconds: float = 2.5) -> void:
	var hud := get_parent().get_node_or_null("Hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(text, seconds)


# ----------------------------------------------------------------------------
#  PUHALLUSKOE
# ----------------------------------------------------------------------------
func run_breath_test(o: Node2D) -> void:
	_lock_player(true)
	o.say("Puhalluskoe!", 2.0)
	hud_message("Puhalluskoe...", 2.2)
	await get_tree().create_timer(PatrolScript.TEST_TIME).timeout

	var promille: float = player.drunk if "drunk" in player else 0.0
	var is_drunk := promille >= breath_limit
	var reading := "Puhalluskoe: %.2f ‰" % promille

	if not is_instance_valid(o) or o.dead:
		# Auto poistettiin kesken kokeen: koe raukeaa
		_lock_player(false)
		end_check(o)
		return

	# Salakuljetuskeikka: poliisi tarkastaa auton ja löytää lastin
	if _carrying_contraband():
		o.say("Mitäs täällä on?!", 2.0)
		hud_message("Poliisi löysi salakuljetuslastin!", 3.0)
		var jm := get_tree().get_first_node_in_group("job_manager")
		if jm and jm.has_method("contraband_found"):
			jm.contraband_found()
		await get_tree().create_timer(1.2).timeout
		manager.heat = maxi(manager.heat, 6)
		manager.arrest("Pidätetty salakuljetuksesta.", -1)
		end_check(o)
		if is_instance_valid(o):
			o.resume_patrol()
		return

	if not is_drunk:
		o.say("Kaikki OK.", 2.0)
		hud_message(reading + " – selvä. Voit jatkaa.", 3.0)
		await get_tree().create_timer(0.8).timeout
		_lock_player(false)
		end_check(o)
		if is_instance_valid(o):
			o.resume_patrol()
		return

	# Humalassa: pidätys ja putka (tuomio kasvaa promillejen mukana).
	# Lievä rattijuopumus kuitataan sakolla, jos rahat riittävät.
	if promille < drunk_fine_limit:
		o.say("Lievä rattijuopumus!", 2.0)
		hud_message(reading + " – lievä rattijuopumus.", 3.0)
	else:
		o.say("Olet pidätetty!", 2.0)
		hud_message(reading + " – olet pidätetty!", 3.0)
	await get_tree().create_timer(1.3).timeout
	var seconds := int(round(drunk_jail_base + promille * drunk_jail_per_promille))
	if promille < drunk_fine_limit:
		var fine := drunk_fine_base + int(round(promille * drunk_fine_per_promille))
		manager.arrest(reading + " – lievä rattijuopumus.", seconds, true, fine)
	else:
		manager.arrest(reading + " – pidätetty rattijuopumuksesta.", seconds, true)
	end_check(o)
	if is_instance_valid(o):
		o.resume_patrol()   # Jail.serve hoitaa pelaajan lukituksen ja vapautuksen


func _lock_player(value: bool) -> void:
	player.set("police_locked", value)
