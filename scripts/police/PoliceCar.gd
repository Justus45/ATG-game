extends Node2D
## Poliisiauto: ajaa tieverkkoa pitkin pelaajaa kohti. Jos pelaaja on jalan,
## auto pysähtyy lähimmälle tielle ja päästää poliisit ulos.

const TEX := {
	"right": preload("res://assets/sprites/police/police_car_right.png"),
	"left": preload("res://assets/sprites/police/police_car_left.png"),
	"up": preload("res://assets/sprites/police/police_car_up.png"),
	"down": preload("res://assets/sprites/police/police_car_down.png"),
}
const CarFXScript := preload("res://scripts/entities/CarFX.gd")
const CarFireScript := preload("res://scripts/entities/CarFire.gd")
const ExplosionScript := preload("res://scripts/core/Explosion.gd")
## Kestävyys tyypeittäin (liikenneauto 60, pelaajan auto 100). SÄÄDÄ NÄITÄ
const MAX_HEALTH := {"police": 90.0, "swat": 140.0, "army": 240.0}
const BURN_TIME := 5.0             ## palava poliisiauto räjähtää näin monen sekunnin päästä
const WRECK_REMOVE_TIME := 70.0    ## romu katoaa näin kauan räjähdyksen jälkeen
const LIGHT_RED := Color(0.86, 0.22, 0.22)
const LIGHT_BLUE := Color(0.25, 0.45, 1.0)

var city: CityGenerator
var manager: Node
var speed: float = 130.0
var dead: bool = false   # PoliceManager lukee tämän
## "police", "swat" (musta pakettiauto) tai "army" (panssariauto)
var kind := "police"

var dir := Vector2i.DOWN
var cell := Vector2i.ZERO
var next_cell := Vector2i.ZERO
var path: Array[Vector2i] = []
var moving := false
var target_pos := Vector2.ZERO
var repath := 0.0
var unloaded := false
var _light_t := 0.0
# Jumiutumisvahti: jos auto ei etene muutamaan sekuntiin, se siirretään lähimmälle
# tielle; jos sekään ei auta, auto poistetaan ja tilalle tulee uusi.
const STUCK_CHECK := 3.0
var _anchor := Vector2.ZERO
var _anchor_t := 0.0
var _stuck_count := 0
var _at_goal := false

# --- Vauriot, tulipalo ja räjähdys ---
var health := 90.0
var burning := false
var wrecked := false
var exploded := false
var _burn_t := 0.0
var _fire = null   # CarFire.gd
var _by_player := false

var sprite: Sprite2D
var light_a: ColorRect
var light_b: ColorRect

func _ready() -> void:
	sprite = Sprite2D.new()
	add_child(sprite)
	light_a = ColorRect.new()
	light_b = ColorRect.new()
	for l: ColorRect in [light_a, light_b]:
		l.size = Vector2(2, 2)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
	add_child(CarFXScript.new())  # pyörivät renkaat + pakokaasu
	add_to_group("car_targets")   # luodit, lyönnit ja räjähdykset osuvat
	health = float(MAX_HEALTH.get(kind, 90.0))
	cell = city.world_to_cell(global_position)
	if kind == "swat":
		sprite.modulate = Color(0.35, 0.35, 0.42)
	elif kind == "army":
		sprite.modulate = Color(0.55, 0.72, 0.42)
	_refresh()

func _process(delta: float) -> void:
	if wrecked:
		_wreck_process(delta)
		return
	if dead:
		return
	# vilkkuvat valot
	_light_t += delta
	var phase := int(_light_t * 5.0) % 2 == 0
	light_a.color = LIGHT_RED if phase else LIGHT_BLUE
	light_b.color = LIGHT_BLUE if phase else LIGHT_RED

	repath -= delta
	var tgt: Vector2 = manager.target_position()
	if moving:
		var to := target_pos - global_position
		var dist := speed * delta
		if to.length() <= dist:
			global_position = target_pos
			cell = next_cell
			moving = false
		else:
			global_position += to.normalized() * dist
	else:
		_choose_next(tgt)
	_watchdog(delta, tgt)

func _choose_next(tgt: Vector2) -> void:
	if path.is_empty() or repath <= 0.0:
		repath = 0.7
		var goal := _nearest_road(city.world_to_cell(tgt))
		_at_goal = goal == cell
		if goal != Vector2i(-1, -1):
			path = _find_path(cell, goal)
		else:
			path.clear()
	if path.is_empty():
		# Perillä (lähin tieruutu pelaajaa): päästetään poliisit ulos, jos pelaaja on
		# jalan lähistöllä tai tieltä ei pääse lähemmäs
		if not unloaded and (global_position.distance_to(tgt) < 180.0 or (_at_goal and global_position.distance_to(tgt) < 320.0)):
			unloaded = true
			manager.unload_officers(global_position, 3 if kind == "army" else 2, kind)
		return
	next_cell = path.pop_front()
	target_pos = city.cell_to_world(next_cell)
	var d := next_cell - cell
	if d != Vector2i.ZERO:
		dir = d
		_refresh()
	moving = true

func _find_path(from: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not city.is_road(from):
		# Auto on päätynyt tien ulkopuolelle: siirretään lähimmälle tieruudulle
		var r := _nearest_road(from)
		if r == Vector2i(-1, -1):
			return empty
		_snap_to(r)
		from = r
	if from == goal:
		return empty
	# Osittainen reitti: jos maaliin ei pääse, ajetaan niin lähelle kuin voi
	var p: Array[Vector2i] = manager.road_astar.get_id_path(from, goal, true)
	if not p.is_empty() and p[0] == from:
		p.remove_at(0)
	return p

func _snap_to(c: Vector2i) -> void:
	cell = c
	next_cell = c
	global_position = city.cell_to_world(c)
	moving = false

## Tarkistaa muutaman sekunnin välein, eteneekö auto. Paikallaan seisominen
## pelaajan lähellä tai maalissa on normaalia, muuten auto on jumissa.
func _watchdog(delta: float, tgt: Vector2) -> void:
	_anchor_t += delta
	if _anchor_t < STUCK_CHECK:
		return
	var moved := global_position.distance_to(_anchor)
	_anchor = global_position
	_anchor_t = 0.0
	var waiting_ok := global_position.distance_to(tgt) < 200.0 or (_at_goal and path.is_empty())
	if moved < 10.0 and not waiting_ok:
		_unstick()
	else:
		_stuck_count = 0

func _unstick() -> void:
	_stuck_count += 1
	if _stuck_count >= 3:
		dismiss()   # PoliceManager / PolicePatrol luo tilalle uuden
		return
	var r := _nearest_road(city.world_to_cell(global_position))
	if r != Vector2i(-1, -1):
		_snap_to(r)
	path.clear()
	repath = 0.0
	_on_unstuck()

## Aliluokat (PatrolCar) voivat valita uuden suunnan.
func _on_unstuck() -> void:
	pass

## Lähin tieruutu annetulle ruudulle (pelaaja voi olla jalkakäytävällä).
func _nearest_road(c: Vector2i) -> Vector2i:
	if city.is_road(c):
		return c
	for r in range(1, 12):
		var best := Vector2i(-1, -1)
		var best_d := 1.0e9
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if city.is_road(n) and float(dx * dx + dy * dy) < best_d:
					best_d = float(dx * dx + dy * dy)
					best = n
		if best != Vector2i(-1, -1):
			return best
	return Vector2i(-1, -1)

func _refresh() -> void:
	var key := "down"
	if dir == Vector2i.UP:
		key = "up"
	elif dir == Vector2i.LEFT:
		key = "left"
	elif dir == Vector2i.RIGHT:
		key = "right"
	var tex: Texture2D = preload("res://scripts/core/HDTex.gd").upgrade(TEX[key])
	sprite.texture = tex
	# korkeammat kuvat nostetaan niin että renkaat pysyvät tiellä (kuten liikenneautoilla)
	sprite.offset = Vector2(0, -floorf((tex.get_height() - 16) * 0.5))
	var c := sprite.offset
	if key == "left" or key == "right":
		light_a.position = c + Vector2(-1, -3)
		light_b.position = c + Vector2(-1, 1)
	else:
		light_a.position = c + Vector2(-3, -1)
		light_b.position = c + Vector2(1, -1)

# ----------------------------------------------------------------------------
#  VAURIOT: luodit, lyönnit, kolarit ja räjähdykset. Kunnon loppuessa auto syttyy
#  palamaan, poliisit hyppäävät ulos ja auto räjähtää BURN_TIME sekunnin päästä.
# ----------------------------------------------------------------------------
func hit_rect() -> Rect2:
	if sprite == null or sprite.texture == null:
		return Rect2(global_position - Vector2(8.0, 8.0), Vector2(16.0, 16.0))
	var sz := sprite.texture.get_size()
	var c := global_position + sprite.offset
	return Rect2(c - sz * 0.5, sz).grow_individual(-1.0, -3.0, -1.0, -1.0)

func take_damage(amount: int = 1, source: Node = null) -> void:
	take_hit(float(amount) * 4.0, source != null and source.is_in_group("player"))

func take_hit(amount: float, by_player: bool = false) -> void:
	if amount <= 0.0 or exploded:
		return
	if by_player:
		_by_player = true
	if burning:
		_burn_t -= amount * 0.04
		return
	var max_h := float(MAX_HEALTH.get(kind, 90.0))
	health = maxf(health - amount, 0.0)
	sprite.modulate = _base_tint().lerp(Color(0.5, 0.46, 0.44), 1.0 - health / max_h)
	if health <= 0.0:
		_ignite()
	elif health < max_h * 0.5:
		_ensure_fire().set_level(CarFireScript.SMOKE)

func is_burning() -> bool:
	return burning

func _base_tint() -> Color:
	if kind == "swat":
		return Color(0.35, 0.35, 0.42)
	elif kind == "army":
		return Color(0.55, 0.72, 0.42)
	return Color.WHITE

func _ensure_fire():
	if _fire == null:
		_fire = CarFireScript.new()
		var sz: Vector2 = sprite.texture.get_size() if sprite.texture else Vector2(16.0, 16.0)
		_fire.half = sz * 0.5 * Vector2(0.7, 0.5)
		_fire.center = sprite.offset
		add_child(_fire)
	return _fire

func _ignite() -> void:
	if burning or exploded:
		return
	burning = true
	wrecked = true
	_burn_t = BURN_TIME
	moving = false
	path.clear()
	light_a.visible = false
	light_b.visible = false
	_ensure_fire().set_level(CarFireScript.BURNING)
	Sfx.play("glass_break", global_position, -2.0, 0.05)
	Sfx.play("ignite", global_position, 2.0, 0.08)
	# Poliisit hyppäävät palavasta autosta ulos (jos jahti on käynnissä)
	if not unloaded and is_instance_valid(manager) and int(manager.get("wanted")) > 0 and manager.has_method("unload_officers"):
		unloaded = true
		manager.unload_officers(global_position, 3 if kind == "army" else 2, kind)
	# Romu pysyy esteenä liikenteelle ja pelaajalle, vaikka poliisi ei sitä enää käytä
	add_to_group("police_wrecks")
	_on_wrecked()
	dead = true   # PoliceManager / PolicePatrol poistavat auton listoiltaan ja lähettävät uuden

## Aliluokat (PatrolCar) voivat siivota tilansa.
func _on_wrecked() -> void:
	pass

func _wreck_process(delta: float) -> void:
	if burning:
		_burn_t -= delta
		if _burn_t <= 0.0:
			_explode()

func _explode() -> void:
	if exploded:
		return
	burning = false
	exploded = true
	_ensure_fire().set_level(CarFireScript.SMOLDER)
	# Poliisiauton räjäyttäminen on vakava rikos: poliisi lähtee perään
	if _by_player:
		get_tree().call_group("police_manager", "commit_crime", 2, global_position, null, true)
	sprite.modulate = Color(0.22, 0.19, 0.18)
	var ex := ExplosionScript.new()
	ex.source = self
	ex.by_player = _by_player
	get_parent().add_child(ex)
	ex.global_position = global_position + sprite.offset
	var tw := create_tween()
	tw.tween_property(sprite, "position:y", -8.0, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "position:y", 0.0, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
	tw.tween_interval(WRECK_REMOVE_TIME)
	tw.tween_property(self, "modulate:a", 0.0, 3.0)
	tw.tween_callback(queue_free)

func dismiss() -> void:
	if dead:
		return
	dead = true
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(self, "modulate:a", 0.0, 1.0)
	tw.tween_callback(queue_free)
