extends Node2D
## Auton räjähdys: välähdys, tulipallo, paineaalto, romunpalat, savu, nokijälki,
## ääni ja kameran tärähdys. Vahingoittaa kaikkea lähellä olevaa:
##   - autot (pelaajan/pysäköidyt ja liikenne) saavat vahinkoa -> voivat syttyä ja räjähtää ketjussa
##   - jalankulkijat (ohikulkijat, poliisit, roistot) lentävät ilmaan
##   - jalan oleva pelaaja lentää ja menettää terveyttä
##
## Käyttö:
##   var ex := ExplosionScript.new()
##   ex.source = auto; ex.by_player = true
##   parent.add_child(ex); ex.global_position = paikka

# --- SÄÄDÄ NÄITÄ ---
const RADIUS := 64.0             ## vahinkosäde (px)
const CAR_DAMAGE_MAX := 95.0     ## vahinko autolle keskellä (Car2D:n kunto 100)
const CAR_DAMAGE_MIN := 12.0     ## vahinko autolle säteen reunalla
const PLAYER_DAMAGE_MAX := 6.0   ## pelaajan lisävahinko keskellä (lennon vahinko tulee päälle)
const SHAKE_MAX := 9.0

## Räjähtävä auto (ei vahingoiteta uudestaan)
var source: Node = null
## Räjähdyksen aiheutti pelaaja -> kuolemat ovat pelaajan rikoksia
var by_player := false


func _ready() -> void:
	z_index = 4005
	_sound_and_shake()
	_flash()
	_fireball()
	_shockwave()
	_debris()
	_smoke()
	_scorch()
	_glow()
	# vahinko seuraavalla fysiikkatikillä (kaikki solmut ovat valmiina)
	_apply_damage.call_deferred()
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_callback(queue_free)


# ----------------------------------------------------------------------------
#  VAHINKO
# ----------------------------------------------------------------------------
func _apply_damage() -> void:
	if not is_inside_tree():
		return
	var at := global_position
	var impacts := get_tree().get_first_node_in_group("impacts")

	# Pelaajan ja pysäköidyt autot
	for c in get_tree().get_nodes_in_group("player_vehicles"):
		if c == source or not is_instance_valid(c) or not (c is Node2D):
			continue
		var k := _falloff((c as Node2D).global_position, at)
		if k <= 0.0:
			continue
		if c.has_method("take_hit"):
			c.take_hit(lerpf(CAR_DAMAGE_MIN, CAR_DAMAGE_MAX, k), by_player)
		if c.has_method("apply_knock"):
			var away: Vector2 = ((c as Node2D).global_position - at).normalized()
			c.apply_knock(away * lerpf(60.0, 260.0, k), 0.0)

	# Liikenne- ja poliisiautot
	for m in get_tree().get_nodes_in_group("car_targets"):
		if m == source or not is_instance_valid(m) or not (m is Node2D):
			continue
		var k := _falloff((m as Node2D).global_position, at)
		if k > 0.0 and m.has_method("take_hit"):
			m.take_hit(lerpf(CAR_DAMAGE_MIN, CAR_DAMAGE_MAX, k) * 0.75, by_player)

	# Jalankulkijat lentävät
	var player := get_tree().get_first_node_in_group("player") as Node2D
	for n in get_tree().get_nodes_in_group("shootable"):
		if not (n is Node2D) or not is_instance_valid(n) or n == player:
			continue
		if Game.flag(n, "is_car") or Game.flag(n, "dead") or not n.has_method("hit_point"):
			continue
		if not (n as Node2D).is_visible_in_tree():
			continue
		var hp: Vector2 = n.hit_point()
		var k := _falloff(hp, at, RADIUS * 0.9)
		if k <= 0.0:
			continue
		var away := (hp - at).normalized()
		if away == Vector2.ZERO:
			away = Vector2.from_angle(randf() * TAU)
		if impacts and impacts.has_method("_launch") and not impacts._flying.has(n):
			impacts._launch(n, away * lerpf(150.0, 320.0, k), by_player)
		elif n.has_method("take_damage"):
			n.take_damage(99, player if by_player else null)

	# Jalan oleva pelaaja
	if player and player.visible and player.is_physics_processing():
		var center: Vector2 = player.body_center() if player.has_method("body_center") else player.global_position
		var k := _falloff(center, at, RADIUS * 1.1)
		if k > 0.0:
			var away := (center - at).normalized()
			if away == Vector2.ZERO:
				away = Vector2.from_angle(randf() * TAU)
			if player.has_method("hurt"):
				player.hurt(lerpf(1.0, PLAYER_DAMAGE_MAX, k), source)
			if player.has_method("hit_by_car"):
				player.hit_by_car(away * lerpf(120.0, 300.0, k), source)


## 1 keskellä, 0 säteen reunalla ja sen ulkopuolella.
func _falloff(p: Vector2, at: Vector2, radius: float = RADIUS) -> float:
	var d := p.distance_to(at)
	if d >= radius:
		return 0.0
	return 1.0 - d / radius


# ----------------------------------------------------------------------------
#  EFEKTIT
# ----------------------------------------------------------------------------
func _sound_and_shake() -> void:
	Sfx.play("explosion", global_position, 6.0, 0.1)
	Sfx.play("glass_break", global_position, -2.0, 0.1, 0.8)
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method("shake"):
		var d := cam.get_screen_center_position().distance_to(global_position)
		var k := clampf(1.0 - d / 600.0, 0.0, 1.0)
		if k > 0.0:
			cam.shake(SHAKE_MAX * k)


func _circle(r: float, n: int = 14) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		pts.append(Vector2.from_angle(i * TAU / n) * r)
	return pts


func _flash() -> void:
	var f := Polygon2D.new()
	f.polygon = _circle(10.0, 18)
	f.color = Color(1.0, 1.0, 0.9)
	f.z_index = 6
	add_child(f)
	var tw := f.create_tween()
	tw.tween_property(f, "scale", Vector2(4.5, 4.5), 0.12).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(f, "modulate:a", 0.0, 0.16)
	tw.tween_callback(f.queue_free)


func _fireball() -> void:
	var cols := [Color(1.0, 0.95, 0.5), Color(1.0, 0.7, 0.2), Color(1.0, 0.45, 0.1), Color(0.9, 0.2, 0.05)]
	for i in 14:
		var b := Polygon2D.new()
		var r := randf_range(5.0, 10.0)
		b.polygon = _circle(r, 10)
		b.color = cols[randi() % cols.size()]
		b.z_index = 4 - (i % 3)
		add_child(b)
		var off := Vector2.from_angle(randf() * TAU) * randf_range(0.0, 10.0)
		b.position = off
		b.scale = Vector2(0.3, 0.3)
		var end := off * 2.2 + Vector2(0.0, -randf_range(4.0, 16.0))
		var life := randf_range(0.45, 0.85)
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE * randf_range(1.3, 2.0), life * 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.parallel().tween_property(b, "position", end, life).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "color", Color(0.25, 0.1, 0.05), life * 0.4)
		tw.parallel().tween_property(b, "modulate:a", 0.0, life * 0.65)
		tw.tween_callback(b.queue_free)


func _shockwave() -> void:
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = Color(1.0, 0.9, 0.7, 0.8)
	ring.z_index = 5
	add_child(ring)
	_ring_step(6.0, ring)
	var tw := ring.create_tween()
	tw.tween_method(_ring_step.bind(ring), 6.0, RADIUS, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.35)
	tw.tween_callback(ring.queue_free)


func _ring_step(r: float, ring: Line2D) -> void:
	if not is_instance_valid(ring):
		return
	var pts := _circle(r, 28)
	pts.append(pts[0])
	ring.points = pts


func _debris_step(t: float, d: Node2D, start: Vector2, travel: Vector2, h: float, spin: float) -> void:
	if not is_instance_valid(d):
		return
	d.global_position = start + travel * (1.0 - (1.0 - t) * (1.0 - t)) + Vector2(0.0, -sin(t * PI) * h)
	d.rotation = spin * t


func _debris() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for i in 16:
		var d := Polygon2D.new()
		var s := randf_range(0.8, 2.0)
		d.polygon = PackedVector2Array([Vector2(-s, -s * 0.6), Vector2(s, -s), Vector2(s * 0.7, s), Vector2(-s, s * 0.8)])
		d.color = [Color(0.2, 0.2, 0.22), Color(0.35, 0.33, 0.3), Color(1.0, 0.6, 0.2), Color(0.55, 0.55, 0.6)][randi() % 4]
		d.z_index = 4004
		parent.add_child(d)
		var start := global_position
		d.global_position = start
		var dir := Vector2.from_angle(randf() * TAU)
		var dist := randf_range(18.0, 60.0)
		var h := randf_range(8.0, 26.0)
		var dur := randf_range(0.45, 0.8)
		var spin := randf_range(-12.0, 12.0)
		var tw := d.create_tween()
		tw.tween_method(_debris_step.bind(d, start, dir * dist, h, spin), 0.0, 1.0, dur)
		tw.tween_interval(randf_range(1.5, 3.0))
		tw.tween_property(d, "modulate:a", 0.0, 0.6)
		tw.tween_callback(d.queue_free)


func _smoke() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for i in 12:
		var p := Polygon2D.new()
		p.polygon = _circle(randf_range(3.0, 5.0), 8)
		var g := randf_range(0.1, 0.25)
		p.color = Color(g, g, g, 0.85)
		p.z_index = 4003
		parent.add_child(p)
		var start := global_position + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 10.0)
		p.global_position = start
		p.modulate.a = 0.0
		var delay := randf_range(0.05, 0.3)
		var life := randf_range(1.6, 2.6)
		var drift := Vector2(Game.wind * 30.0 + randf_range(-14.0, 14.0), -randf_range(30.0, 55.0))
		var tw := p.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(p, "modulate:a", 1.0, 0.1)
		tw.tween_property(p, "global_position", start + drift, life).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(p, "scale", Vector2(3.0, 3.0), life)
		tw.parallel().tween_property(p, "modulate:a", 0.0, life).set_ease(Tween.EASE_IN)
		tw.tween_callback(p.queue_free)


## Nokijälki maahan (piirretään maan päälle, hahmojen alle). Haalistuu hiljalleen.
func _scorch() -> void:
	var city := get_tree().current_scene.get_node_or_null("City")
	var ground: Node2D = city.get("ground_layer") if city else null
	if ground == null:
		return
	var s := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 16:
		pts.append(Vector2.from_angle(i * TAU / 16.0) * Vector2(19.0, 13.0) * randf_range(0.75, 1.1))
	s.polygon = pts
	s.color = Color(0.05, 0.04, 0.04, 0.55)
	ground.add_child(s)
	s.global_position = global_position + Vector2(0.0, 3.0)
	var tw := s.create_tween()
	tw.tween_interval(40.0)
	tw.tween_property(s, "modulate:a", 0.0, 15.0)
	tw.tween_callback(s.queue_free)


func _glow() -> void:
	var l := PointLight2D.new()
	var tex := GradientTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	l.texture = tex
	l.texture_scale = RADIUS * 3.0 / 128.0
	l.color = Color(1.0, 0.65, 0.3)
	l.energy = 2.5
	l.range_z_min = -4096
	l.range_z_max = 4096
	add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "energy", 0.0, 0.9).set_ease(Tween.EASE_IN)
