extends Node2D
## Auton alle jäänyt katukaluste (lamppu, kyltti, roskis, penkki, laatikko...).
## Kaluste irtoaa tilemapista ja lentää törmäysnopeuden mukaan: korkeat kalusteet
## kaatuvat kyljelleen tyvensä ympäri, pienet lentävät pyörien ja pomppivat.
## Lopuksi kaluste jää makaamaan maahan ja häivytetään hetken päästä.
## city_generator.knock_prop() luo tämän.

const GRAVITY := 520.0
const LIFETIME := 40.0          ## sekuntia maassa ennen häivytystä

var city: Node
var vel := Vector2.ZERO
var tall := false
var metal := false

var _z := 0.0
var _vz := 0.0
var _spin := 0.0
var _rot := 0.0
var _target_rot := 0.0
var _resting := false
var _life := 0.0
var _root: Node2D
var _w := 16.0


## tiles: [[maailmapiste (ruudun keskipiste), Texture2D], ...]; ground = kalusteen tyven kohta maassa
func setup(tiles: Array, ground: Vector2, hit_vel: Vector2, is_tall: bool) -> void:
	global_position = ground
	tall = is_tall
	_root = Node2D.new()
	add_child(_root)
	var minx := INF
	var maxx := -INF
	for t: Array in tiles:
		var s := Sprite2D.new()
		s.texture = t[1]
		s.position = (t[0] as Vector2) - ground
		_root.add_child(s)
		minx = minf(minx, s.position.x - 8.0)
		maxx = maxf(maxx, s.position.x + 8.0)
	_w = maxx - minx
	var spd := hit_vel.length()
	var dir := hit_vel.normalized() if spd > 1.0 else Vector2.RIGHT
	if tall:
		# kaatuu menosuuntaan (sivuttain ruudulla), liukuu hieman
		vel = dir * spd * 0.35
		_vz = 30.0
		_target_rot = PI * 0.5 * (1.0 if dir.x >= 0.0 else -1.0)
		if absf(dir.x) < 0.3:
			_target_rot = PI * 0.5 * (1.0 if randf() < 0.5 else -1.0)
	else:
		vel = dir.rotated(randf_range(-0.35, 0.35)) * spd * randf_range(0.7, 1.0)
		_vz = clampf(spd * 0.7, 70.0, 230.0)
		_spin = randf_range(6.0, 14.0) * (1.0 if randf() < 0.5 else -1.0)
	Sfx.play("clang" if metal else "thud", ground, -2.0, 0.15, randf_range(0.8, 1.1))


func _passable(p: Vector2) -> bool:
	if city == null:
		return true
	var c: Vector2i = city.world_to_cell(p)
	return city.is_walkable(c) or city.is_road(c)


func _physics_process(delta: float) -> void:
	if _resting:
		_life += delta
		if _life > LIFETIME:
			modulate.a = maxf(1.0 - (_life - LIFETIME) / 2.0, 0.0)
			if modulate.a <= 0.0:
				queue_free()
		return
	# liike maassa / ilmassa
	var np := global_position + vel * delta
	if _passable(np):
		global_position = np
	else:
		vel = -vel * 0.3
	_vz -= GRAVITY * delta
	_z += _vz * delta
	if _z <= 0.0:
		_z = 0.0
		if absf(_vz) > 60.0 and not tall:
			_vz = -_vz * 0.35
			_spin *= 0.5
			vel *= 0.6
			Sfx.play("clang" if metal else "thud", global_position, -10.0, 0.15, 1.1)
		else:
			_vz = 0.0
		vel *= maxf(1.0 - 5.0 * delta, 0.0)
	if tall:
		# kaatuminen tyven ympäri: nopeutuu kuin putoava tanko
		var k := 1.0 - absf(_target_rot - _rot) / (PI * 0.5)
		_rot = move_toward(_rot, _target_rot, (2.0 + 9.0 * k) * delta)
		if _rot == _target_rot and _z <= 0.0:
			_settle()
	else:
		_rot += _spin * delta
		if _z <= 0.0 and _vz == 0.0 and vel.length() < 8.0:
			_settle()
	_root.rotation = _rot
	_root.position = Vector2(0.0, -_z)
	queue_redraw()


func _settle() -> void:
	if _resting:
		return
	_resting = true
	if tall:
		Sfx.play("clang" if metal else "thud", global_position, -4.0, 0.1, 0.7)
		var cam := get_viewport().get_camera_2d()
		if cam and cam.has_method("shake") and cam.global_position.distance_to(global_position) < 200.0:
			cam.shake(1.5)
	queue_redraw()


func _draw() -> void:
	# varjo maassa; pienenee ilmassa
	var k := clampf(1.0 - _z / 60.0, 0.3, 1.0)
	var w := (_w * 0.55 if not tall or _resting or absf(_rot) > 1.0 else 6.0) * k
	draw_set_transform(Vector2(0.0, 1.0), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, w, Color(0, 0, 0, 0.28 * k))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
