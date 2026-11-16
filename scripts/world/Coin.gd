extends Node2D
## Kolikko: lentää kaarella maahan, kimpoaa kerran ja imeytyy pelaajaan kun tämä on lähellä.
## Arvo (value) lisätään pelaajan rahoihin.

const MAGNET_RADIUS := 56.0
const PICKUP_RADIUS := 10.0
const LIFETIME := 45.0

var value := 10

var _vel := Vector2.ZERO   # vaakasuuntainen lentonopeus
var _h := 6.0              # korkeus maasta (näennäinen)
var _vh := 150.0           # pystynopeus
var _bounced := false
var _landed := false
var _age := 0.0
var _spin := 0.0
var _player: Node2D = null


func _ready() -> void:
	z_index = 20
	_spin = randf() * TAU
	_player = get_tree().get_first_node_in_group("player") as Node2D


## Heittää kolikon annettuun suuntaan/nopeuteen.
func toss(velocity: Vector2) -> void:
	_vel = velocity
	_vh = randf_range(120.0, 190.0)


func _process(delta: float) -> void:
	_age += delta
	_spin += delta * 9.0
	if _age > LIFETIME:
		modulate.a = 0.5 + 0.5 * sin(_age * 22.0)
		if _age > LIFETIME + 5.0:
			queue_free()
			return

	if not _landed:
		position += _vel * delta
		_vh -= 520.0 * delta
		_h += _vh * delta
		if _h <= 0.0:
			_h = 0.0
			if not _bounced:
				_bounced = true
				_vh = -_vh * 0.4
				_vel *= 0.5
			else:
				_landed = true
				_vel = Vector2.ZERO
	if _age > 0.3:
		_try_collect(delta)
	queue_redraw()


func _try_collect(delta: float) -> void:
	if not is_instance_valid(_player) or not _player.visible:
		return
	var target: Vector2 = _player.body_center() if _player.has_method("body_center") else _player.global_position
	var d := global_position.distance_to(target)
	if d < PICKUP_RADIUS:
		if _player.has_method("add_money"):
			_player.add_money(value)
			Sfx.play_ui("coin", -10.0, randf_range(0.95, 1.12))
		queue_free()
	elif d < MAGNET_RADIUS and _landed:
		global_position = global_position.move_toward(target, (120.0 + (MAGNET_RADIUS - d) * 6.0) * delta)


func _draw() -> void:
	# Varjo
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 3.0, Color(0, 0, 0, 0.3))
	# Pyörivä kolikko
	var sx := 0.25 + 0.75 * absf(cos(_spin))
	draw_set_transform(Vector2(0.0, -_h - 3.5), 0.0, Vector2(sx, 1.0))
	draw_circle(Vector2.ZERO, 3.4, Color(0.62, 0.4, 0.05))
	draw_circle(Vector2.ZERO, 2.6, Color(1.0, 0.82, 0.18))
	draw_circle(Vector2(-0.8, -0.8), 1.0, Color(1.0, 0.96, 0.7))
	draw_set_transform(Vector2.ZERO)
