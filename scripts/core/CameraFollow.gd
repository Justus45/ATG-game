extends Camera2D

@export var follow_speed: float = 5.0
@export var zoom_level: float = 3.0

var _t := 0.0
var _drunk_k := 0.0   # pehmennetty humalan voimakkuus 0..1
var _shake := 0.0     # kolarin / osuman tärähdys (px), hiipuu nopeasti
## Ajaessa kamera katsoo hieman menosuuntaan ja zoomaa vauhdissa vähän ulos
const LEAD_TIME := 0.32        ## kuinka monen sekunnin päähän katsotaan
const LEAD_MAX := 70.0         ## enimmäisennakointi (px)
const SPEED_ZOOM := 0.1       ## zoomaus ulos täydessä vauhdissa (osuus)
var _lead := Vector2.ZERO
var _speed_k := 0.0

## Tärähdys (kolari, auton alle jääminen). amount = enimmäissiirtymä pikseleinä.
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

func _ready() -> void:
	zoom = Vector2(zoom_level, zoom_level)
	# Kamera saa kallistua, kun pelaaja on kännissä (muuten rotation ei vaikuta kuvaan)
	ignore_rotation = false
	# Kamera seuraa samassa tahdissa kuin auto/pelaaja liikkuvat (fysiikkatikki).
	# Kun kamera liikkui _process:ssa mutta auto _physics_process:ssa, näytön ja fysiikan
	# eri tahti aiheutti nykimistä varsinkin kovassa vauhdissa.
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS

func _physics_process(delta: float) -> void:
	var target: Node2D = null

	# 1. Ajaako pelaaja jotain autoa (oma auto tai parkkipaikalta varastettu)?
	for car in get_tree().get_nodes_in_group("player_vehicles"):
		if "is_driving" in car and car.is_driving:
			target = car
			break

	# 2. Jos autoa ei ajeta, seurataan pelaajaa
	if target == null:
		target = get_node_or_null("../Player")

	# Ajaessa: ennakointi menosuuntaan ja vauhtizoomi (pehmeästi)
	var lead_to := Vector2.ZERO
	var spd_to := 0.0
	if target and target != get_node_or_null("../Player") and "velocity" in target:
		var v: Vector2 = target.velocity
		lead_to = (v * LEAD_TIME).limit_length(LEAD_MAX)
		var vmax: float = maxf(float(target.get("speed")) if target.get("speed") != null else 250.0, 1.0)
		spd_to = clampf(v.length() / vmax, 0.0, 1.0)
	_lead = _lead.lerp(lead_to, clampf(delta * 2.2, 0.0, 1.0))
	_speed_k = lerpf(_speed_k, spd_to, clampf(delta * 1.5, 0.0, 1.0))
	# Siirretään kameraa pehmeästi kohteeseen (lerp)
	# Kamera pysyy keskitettynä pelaajaan / autoon (ei jää jälkeen eikä ennakoi)
	if target:
		global_position = target.global_position

	# Humala: kamera keinuu, kallistuu ja zoomaa hitaasti sisään-ulos
	_t += delta
	var player := get_node_or_null("../Player")
	var k := 0.0
	if player and player.has_method("drunk_strength"):
		k = player.drunk_strength()
	_drunk_k = lerpf(_drunk_k, k, clampf(delta * 2.0, 0.0, 1.0))
	rotation = (sin(_t * 0.7) * 0.7 + sin(_t * 1.9 + 1.0) * 0.3) * 0.07 * _drunk_k
	offset = Vector2(sin(_t * 0.9), cos(_t * 1.3)) * 5.0 * _drunk_k
	if _shake > 0.05:
		offset += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
		_shake = move_toward(_shake, 0.0, delta * maxf(_shake * 6.0, 8.0))
	var z := zoom_level * (1.0 + 0.05 * sin(_t * 0.6) * _drunk_k) * (1.0 - SPEED_ZOOM * _speed_k)
	zoom = Vector2(z, z)
