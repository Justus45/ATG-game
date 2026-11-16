extends Node2D
## Käsikranaatti: lentää kaaressa heittokohteeseen, pomppii ja vierii, räjähtää sytyttimen
## palettua (Explosion.gd: autot, jalankulkijat ja pelaaja saavat vahinkoa).
## Seinä tai talo pysäyttää lennon ja kranaatti kimpoaa hieman takaisin.
## Piirretään puolen pikselin tarkkuudella, kuten hahmot ja aseet.
##
## Luonti: g.start = paikka; g.target = kohde; parent.add_child(g)

const EXPLOSION := preload("res://scripts/core/Explosion.gd")

const FUSE := 1.9            ## sekuntia heitosta räjähdykseen
const FLIGHT := 0.55         ## lentoaika kohteeseen
const ARC_H := 26.0          ## lentokaaren korkeus (px)
const GRAVITY := 320.0

const OUTLINE := Color(0.11, 0.1, 0.14)
const OLIVE := Color(0.33, 0.4, 0.2)
const OLIVE_D := Color(0.22, 0.27, 0.13)
const OLIVE_L := Color(0.5, 0.58, 0.3)
const METAL := Color(0.62, 0.64, 0.7)
const METAL_D := Color(0.38, 0.4, 0.46)

var start := Vector2.ZERO
var target := Vector2.ZERO

var _t := 0.0
var _height := 0.0
var _landed := false
var _vel := Vector2.ZERO
var _vz := 0.0
var _spin := 0.0
var _city: Node


func _ready() -> void:
	z_index = 6
	global_position = start
	_city = get_tree().current_scene.get_node_or_null("City")
	Sfx.play("punch_miss", start, -4.0, 0.1, 0.55)


func _passable(p: Vector2) -> bool:
	if _city == null or not _city.has_method("world_to_cell"):
		return true
	var c: Vector2i = _city.world_to_cell(p)
	return _city.is_walkable(c) or _city.is_road(c)


func _physics_process(delta: float) -> void:
	_t += delta
	if not _landed:
		var f := clampf(_t / FLIGHT, 0.0, 1.0)
		var p := start.lerp(target, f)
		_height = sin(f * PI) * ARC_H
		if not _passable(p):
			# osui seinään: putoaa seinän viereen ja kimpoaa takaisin
			_landed = true
			_vel = (start - target).normalized() * 35.0
			_vz = 0.0
		else:
			global_position = p
			if f >= 1.0:
				_landed = true
				_vel = (target - start).normalized() * 45.0
				_vz = 60.0
				_height = 0.0
				Sfx.play("clink", global_position, -6.0, 0.1, 0.8)
	else:
		# pomppiminen ja vieriminen
		_vz -= GRAVITY * delta
		_height += _vz * delta
		if _height <= 0.0:
			_height = 0.0
			if absf(_vz) > 25.0:
				Sfx.play("clink", global_position, -12.0, 0.1, 0.9)
			_vz = -_vz * 0.35 if absf(_vz) > 25.0 else 0.0
		var np := global_position + _vel * delta
		if _passable(np):
			global_position = np
		else:
			_vel = -_vel * 0.4
		_vel *= maxf(1.0 - 3.0 * delta, 0.0)
	_spin += delta * (16.0 if not _landed else _vel.length() * 0.25)
	if _t >= FUSE:
		_explode()
		return
	queue_redraw()


func _explode() -> void:
	var ex := EXPLOSION.new()
	ex.by_player = true
	var parent := get_parent()
	if parent:
		parent.add_child(ex)
		ex.global_position = global_position
	# räjähdys on aina rikos (kuolemat hoitaa Impacts)
	get_tree().call_group("police_manager", "commit_crime", 3, global_position, null, false)
	queue_free()


func _draw() -> void:
	# varjo maassa, pienenee kranaatin noustessa
	var sh := clampf(1.0 - _height / (ARC_H * 1.6), 0.35, 1.0)
	draw_set_transform(Vector2(0.0, 1.5), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 3.0 * sh, Color(0, 0, 0, 0.35 * sh))
	# itse kranaatti puolen pikselin yksiköissä (1 = 0.5 px)
	draw_set_transform(Vector2(0.0, -_height - 2.0), _spin, Vector2(0.5, 0.5))
	draw_circle(Vector2(0, 1), 5.0, OUTLINE)
	draw_circle(Vector2(0, 1), 4.0, OLIVE)
	draw_circle(Vector2(0.8, 2.0), 3.0, OLIVE_D)
	draw_circle(Vector2(-0.6, 0.4), 2.6, OLIVE)
	draw_rect(Rect2(-4.0, 0.5, 8.0, 1.0), OLIVE_D)          # uurre
	draw_rect(Rect2(-0.5, -3.0, 1.0, 8.0), OLIVE_D)
	draw_rect(Rect2(-2.5, -1.5, 1.5, 1.5), OLIVE_L)          # kiilto
	draw_rect(Rect2(-2.5, -6.5, 5.0, 3.5), OUTLINE)          # sytytin
	draw_rect(Rect2(-1.5, -5.5, 3.0, 2.0), METAL)
	draw_rect(Rect2(1.5, -6.0, 1.5, 6.0), METAL_D)           # vipu
	# sytytin palaa: punainen kipinä välkkyy yhä nopeammin
	var rate := lerpf(4.0, 18.0, clampf(_t / FUSE, 0.0, 1.0))
	if fmod(_t * rate, 1.0) < 0.5:
		draw_circle(Vector2(0, -7.0), 1.3, Color(1.0, 0.35, 0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
