extends Node2D
## Jalkautunut poliisi: jahtaa pelaajaa kaupungin A*-ruudukkoa pitkin.
## PoliceManager luo ja asettaa city + manager ennen add_child:ia.

const CHAR_SPRITES := preload("res://scripts/core/CharSprites.gd")
const CELL := 16
const COL := {"left": 0, "down": 1, "up": 2, "right": 3}
const BULLET_SCENE: PackedScene = preload("res://scenes/entities/weapons/bullet.tscn")
const BLOOD := preload("res://scripts/core/Blood.gd")
static var _tex_cache := {}

## "police" = tavallinen, "swat" = sähköase (4 tähteä), "army" = sotilas, ampuu (5 tähteä)
## Neljän tähden etsinnässä myös tavalliset poliisit ja SWAT vetävät pistoolit esiin ja ampuvat.
const ARMED_LEVEL := 4
const PISTOL_RANGE := 165.0
const PISTOL_SPREAD := 0.13
var _gun: Node2D = null
var kind := "police"
var _ability_t := 2.5

var city: CityGenerator
var manager: Node
var speed: float = 105.0
var hp: int = 3
var dead: bool = false

var dir: String = "down"
var cell := Vector2i.ZERO
var next_cell := Vector2i.ZERO
var path: Array[Vector2i] = []
var moving := false
var target_pos := Vector2.ZERO
var repath := 0.0
var anim := 0.0
var step := 0

var sprite: Sprite2D

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.offset = Vector2(0, -4)
	add_child(sprite)
	_gun = GunView.new()
	_gun.set("officer", self)
	add_child(_gun)
	add_to_group("shootable")
	add_to_group("police")
	cell = city.world_to_cell(global_position)
	match kind:
		"swat":
			hp = 5
			speed = 115.0
			modulate = Color(0.42, 0.42, 0.5)
		"army":
			hp = 7
			speed = 98.0
			modulate = Color(0.6, 0.8, 0.45)
			add_to_group("enemy_shooter")
	_ability_t = randf_range(1.5, 3.0)
	_refresh()

func hit_point() -> Vector2:
	return global_position + Vector2(0, -4)

func _process(delta: float) -> void:
	if dead:
		return
	if manager and manager.get("wanted") != null and manager.wanted > 0 and (kind != "police" or armed()):
		_ability_t -= delta
		if _ability_t <= 0.0:
			_use_ability()
	repath -= delta
	var tgt: Vector2 = manager.target_position()
	var moved := false

	if moving:
		moved = true
		if not _move_towards(target_pos, delta):
			cell = next_cell
			moving = false
	else:
		var to := tgt - global_position
		if to.length() < 24.0:
			# Lähellä: kävellään suoraan pelaajaa kohti
			if to.length() > 9.0:
				_set_dir(to)
				global_position += to.normalized() * speed * delta
				cell = city.world_to_cell(global_position)
				moved = true
		elif _choose_next(tgt):
			moved = true

	if moved:
		anim += delta
		var st := 1 + (int(anim * 7.0) % 2)
		if st != step:
			step = st
			_refresh()
	elif step != 0:
		step = 0
		_refresh()

## Palauttaa true jos liike on yhä kesken.
func _move_towards(p: Vector2, delta: float) -> bool:
	var to := p - global_position
	var dist := speed * delta
	if to.length() <= dist:
		global_position = p
		return false
	global_position += to.normalized() * dist
	return true

func _choose_next(tgt: Vector2) -> bool:
	if path.is_empty() or repath <= 0.0:
		path = _find_path(cell, city.world_to_cell(tgt))
		repath = 0.5
	if path.is_empty():
		return false
	next_cell = path.pop_front()
	target_pos = city.cell_to_world(next_cell)
	_set_dir(target_pos - global_position)
	moving = true
	return true

func _find_path(from: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not city.is_walkable(from):
		return empty
	if not city.is_walkable(goal):
		goal = _nearest_free(goal)
		if goal == Vector2i(-1, -1):
			return empty
	var p := city.astar.get_id_path(from, goal)
	if not p.is_empty() and p[0] == from:
		p.remove_at(0)
	return p

func _nearest_free(c: Vector2i) -> Vector2i:
	for r in range(1, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if city.is_walkable(n):
					return n
	return Vector2i(-1, -1)

func _set_dir(v: Vector2) -> void:
	var d := dir
	if absf(v.x) > absf(v.y):
		d = "right" if v.x > 0.0 else "left"
	else:
		d = "down" if v.y > 0.0 else "up"
	if d != dir:
		dir = d
		_refresh()

func _refresh() -> void:
	var key := "%s_%d" % [dir, step]
	if not _tex_cache.has(key):
		_tex_cache[key] = CHAR_SPRITES.police(COL[dir], step)
	sprite.texture = _tex_cache[key]

## SWAT: sähköase lähietäisyydeltä. Armeija: ampuu pelaajaa.
func _use_ability() -> void:
	var tgt: Vector2 = manager.target_position()
	var d := global_position.distance_to(tgt)
	if not manager._line_clear(global_position, tgt):
		_ability_t = 0.6
		return
	if kind == "police":
		# 4 tähteä: pistooli
		_ability_t = 0.5
		if d > PISTOL_RANGE:
			return
		_ability_t = randf_range(1.5, 2.6)
		_shoot(tgt, PISTOL_SPREAD, PISTOL_RANGE + 60.0, 1.0)
		return
	if kind == "swat":
		_ability_t = 0.5
		if armed() and (d > 95.0 or manager.player_in_car()) and d <= PISTOL_RANGE:
			_ability_t = randf_range(1.2, 2.0)
			_shoot(tgt, PISTOL_SPREAD * 0.8, PISTOL_RANGE + 60.0, 1.0)
			return
		if d > 95.0 or d < 10.0 or manager.player_in_car():
			return
		_ability_t = randf_range(4.5, 6.5)
		_zap(tgt)
		var p := get_tree().get_first_node_in_group("player")
		if p and p.has_method("stun"):
			p.stun(1.3)
		manager.bust_meter += 0.7
	elif kind == "army":
		_ability_t = 0.5
		if d > 175.0:
			return
		_ability_t = randf_range(0.9, 1.5)
		_shoot(tgt, 0.08, 260.0, 1.1)


## Onko poliisilla ase esillä (armeija aina, muut 4 tähden jahdissa)?
func armed() -> bool:
	if dead:
		return false
	if kind == "army":
		return true
	return is_instance_valid(manager) and int(manager.get("wanted")) >= ARMED_LEVEL and _chasing()


## Partiopoliisi (PatrolOfficer) jahtaa vain CHASE-tilassa
func _chasing() -> bool:
	return true


func _shoot(tgt: Vector2, spread: float, rng: float, pitch: float) -> void:
	var dir_v := (tgt - hit_point()).normalized().rotated(randf_range(-spread, spread))
	_set_dir(dir_v)
	var b := BULLET_SCENE.instantiate()
	b.setup(dir_v, self, 380.0, 1, rng)
	b.enemy = true   # poliisin luoti osuu vain pelaajaan (tai hänen autoonsa)
	get_tree().current_scene.add_child(b)
	b.global_position = hit_point() + dir_v * 6.0
	Sfx.play("gun", global_position, -4.0, 0.08, pitch)
	if _gun:
		_gun.set("flash", 0.07)


## Pistooli poliisin kädessä (piirretään hahmon päälle, selin ollessa taakse).
class GunView extends Node2D:
	var officer: Node2D = null
	var flash := 0.0

	func _process(delta: float) -> void:
		flash = maxf(flash - delta, 0.0)
		var on: bool = officer != null and officer.call("armed")
		if on != visible:
			visible = on
		if on:
			queue_redraw()

	func _draw() -> void:
		var d := str(officer.get("dir"))
		var p := Vector2(4.5, -2.5)
		var v := Vector2.DOWN
		match d:
			"right":
				p = Vector2(4.0, -3.5)
				v = Vector2.RIGHT
			"left":
				p = Vector2(-4.0, -3.5)
				v = Vector2.LEFT
			"up":
				p = Vector2(4.5, -5.5)
				v = Vector2.UP
		z_index = -1 if d == "up" else 0
		var tip := p + v * 3.0
		draw_line(p, tip, Color(0.07, 0.07, 0.09), 1.6)
		draw_rect(Rect2(p - Vector2(0.8, 0.8), Vector2(1.6, 1.6)), Color(0.16, 0.16, 0.2))
		if flash > 0.0:
			draw_circle(tip + v * 1.4, 1.8, Color(1.0, 0.8, 0.25, 0.9))
			draw_circle(tip + v * 1.4, 0.9, Color(1.0, 1.0, 0.9))

## Sähköaseen salama pelaajaan.
func _zap(to: Vector2) -> void:
	var line := Line2D.new()
	line.width = 1.5
	line.default_color = Color(0.6, 0.85, 1.0)
	line.z_index = 4090
	var from := hit_point()
	var pts := PackedVector2Array([from])
	for i in range(1, 6):
		pts.append(from.lerp(to, i / 6.0) + Vector2(randf_range(-3, 3), randf_range(-3, 3)))
	pts.append(to)
	line.points = pts
	get_tree().current_scene.add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.35)
	tw.tween_callback(line.queue_free)

func is_punchable() -> bool:
	return not dead

## Pelaajan nyrkki: tekee yhden pisteen vahinkoa (kuten luoti).
func fist_hit(from: Node2D) -> void:
	take_damage(1, from)

func take_damage(amount: int = 1, _source: Node = null) -> void:
	if dead:
		return
	var bdir: Vector2 = (global_position - (_source as Node2D).global_position) if _source is Node2D else Vector2.ZERO
	BLOOD.spray(self, hit_point(), bdir, 4 if hp - amount > 0 else 9, hp - amount <= 0)
	hp -= amount
	sprite.modulate = Color(1.0, 0.55, 0.55)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.15)
	if hp <= 0:
		_die()

func _die() -> void:
	dead = true
	remove_from_group("shootable")
	remove_from_group("police")
	sprite.rotation = deg_to_rad(90.0 if dir != "left" else -90.0)
	if is_instance_valid(manager):
		manager.officer_killed(self)
	_fade_out(4.0)

## Poliisi lopettaa jahdin (etsintäkuulutus päättyi).
func dismiss() -> void:
	if dead:
		return
	dead = true
	remove_from_group("shootable")
	remove_from_group("police")
	_fade_out(0.5)

func _fade_out(wait: float) -> void:
	var tw := create_tween()
	tw.tween_interval(wait)
	tw.tween_property(self, "modulate:a", 0.0, 1.0)
	tw.tween_callback(queue_free)
