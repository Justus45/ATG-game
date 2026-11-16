extends CanvasLayer
## Vuorokausi ja sää. Game liittää tämän kenttään.
##
## Pimeys toteutetaan Godotin vakiotavalla: CanvasModulate sävyttää koko maailman
## (taivaan väri kellonajan ja pilvisyyden mukaan) ja PointLight2D-valot valaisevat sitä:
##   - katulamput ja ovet (lämmin valo), pelaajan ympäristö
##   - ajettavan auton ajovalot (keila eteen), liikenteen ajovalot
##   - poliisiautojen punasiniset vilkut
## Sade, roiskeet, lumi ja sumu piirretään tämän CanvasLayerin päälle.
## Ukkosmyrskyssä salama valaisee koko kaupungin hetkeksi ja jyrinä kuuluu perässä.
## Sisätiloissa (koti, baari, asekauppa, putka) pimeys ja sää eivät näy.
## Kerros 1: maailman päällä, humalaefektin (2) ja HUD:n (10) alla.

## Taivaan väri pelin minuutin mukaan (interpoloidaan pisteiden välillä). SÄÄDÄ NÄITÄ:
## mitä tummempi väri, sitä pimeämpi. Yön väri on rivillä 0 ja 1350-1440.
const SKY_KEYS := [
	[0.0, Color(0.13, 0.15, 0.3)],
	[270.0, Color(0.13, 0.15, 0.3)],
	[330.0, Color(0.36, 0.3, 0.48)],
	[390.0, Color(0.95, 0.74, 0.64)],
	[480.0, Color(1.0, 0.985, 0.94)],   # päivä: hieman lämmin auringonvalo (varjot ovat viileitä, CityDecor)
	[1020.0, Color(1.0, 0.985, 0.94)],
	[1110.0, Color(1.0, 0.82, 0.6)],
	[1185.0, Color(0.66, 0.45, 0.58)],
	[1260.0, Color(0.27, 0.27, 0.45)],
	[1350.0, Color(0.13, 0.15, 0.3)],
	[1440.0, Color(0.13, 0.15, 0.3)],
]

const LAMP_LIGHTS := 36
const DOOR_LIGHTS := 10
const TRAFFIC_LIGHTS := 12
const POLICE_LIGHTS := 8

const WARM := Color(1.0, 0.82, 0.55)
const DOOR := Color(1.0, 0.72, 0.42)
const HEAD := Color(0.92, 0.95, 1.0)
const RED := Color(1.0, 0.15, 0.15)
const BLUE := Color(0.2, 0.35, 1.0)

const FOG_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;
uniform vec4 tint : source_color = vec4(0.8, 0.82, 0.86, 1.0);
uniform vec2 drift = vec2(0.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void fragment() {
	vec2 p = SCREEN_UV * vec2(3.0, 2.0) + drift;
	float n = noise(p) * 0.6 + noise(p * 2.3 - drift * 0.7) * 0.4;
	COLOR = vec4(tint.rgb, amount * (0.45 + 0.55 * n));
}
"""

var _mod: CanvasModulate
var _light_tex: GradientTexture2D
var _lights_root: Node2D
var _lamps: Array[PointLight2D] = []
var _doors: Array[PointLight2D] = []
var _traffic: Array[PointLight2D] = []
var _police: Array[PointLight2D] = []
var _head: Array[PointLight2D] = []
var _player_light: PointLight2D

var _snow_rect: ColorRect
var _fog_rect: ColorRect
var _fog_mat: ShaderMaterial
var _drops: Drops
var _city: Node
var _indoor_k := 0.0
var _flash := 0.0
var _next_lightning := 8.0
var _last_car_dir := {}
var _fog_drift := Vector2.ZERO
var _night := 0.0


func _ready() -> void:
	layer = 1
	var scene := get_tree().current_scene
	_city = scene.get_node_or_null("City")

	# --- Maailman sävytys ja valot (oletuskanvaasilla, eli kentän juuren lapsina) ---
	_mod = CanvasModulate.new()
	_mod.name = "DayNightModulate"
	_mod.color = Color.WHITE
	scene.add_child.call_deferred(_mod)

	_light_tex = GradientTexture2D.new()
	_light_tex.width = 256
	_light_tex.height = 256
	_light_tex.fill = GradientTexture2D.FILL_RADIAL
	_light_tex.fill_from = Vector2(0.5, 0.5)
	_light_tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	_light_tex.gradient = g

	_lights_root = Node2D.new()
	_lights_root.name = "NightLights"
	scene.add_child.call_deferred(_lights_root)
	for i in LAMP_LIGHTS:
		_lamps.append(_make_light(WARM, 72.0))
	for i in DOOR_LIGHTS:
		_doors.append(_make_light(DOOR, 44.0))
	for i in TRAFFIC_LIGHTS:
		_traffic.append(_make_light(HEAD, 40.0))
	for i in POLICE_LIGHTS:
		_police.append(_make_light(RED, 58.0))
	for r: float in [30.0, 46.0, 62.0, 56.0]:
		_head.append(_make_light(HEAD, r))
	_player_light = _make_light(WARM, 58.0)

	# --- Sää ruudun päällä: lumen valkaisu, sumu, pisarat ---
	_snow_rect = ColorRect.new()
	_snow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_snow_rect.color = Color(0.93, 0.96, 1.0, 0.0)
	add_child(_snow_rect)
	_snow_rect.set_anchors_preset(Control.PRESET_FULL_RECT)

	_fog_rect = ColorRect.new()
	_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsh := Shader.new()
	fsh.code = FOG_SHADER
	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = fsh
	_fog_rect.material = _fog_mat
	add_child(_fog_rect)
	_fog_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fog_rect.hide()

	_drops = Drops.new()
	_drops.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_drops)
	_drops.set_anchors_preset(Control.PRESET_FULL_RECT)


## Pistemäinen valo; radius = säde maailman pikseleinä.
func _make_light(col: Color, radius: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = _light_tex
	l.texture_scale = radius * 2.0 / 256.0
	l.color = col
	l.energy = 0.0
	l.shadow_enabled = false
	l.range_z_min = -4096
	l.range_z_max = 4096
	l.enabled = false
	l.set_meta("radius", radius)
	_lights_root.add_child(l)
	return l


func _indoors() -> bool:
	return Game.player_indoors()


## Taivaan väri kellonajan ja pilvisyyden mukaan.
func sky_color() -> Color:
	var m := Game.minutes
	var col: Color = SKY_KEYS[0][1]
	for i in range(SKY_KEYS.size() - 1):
		var a: Array = SKY_KEYS[i]
		var b: Array = SKY_KEYS[i + 1]
		var ma: float = a[0]
		var mb: float = b[0]
		if m >= ma and m <= mb:
			var ca: Color = a[1]
			var cb: Color = b[1]
			col = ca.lerp(cb, (m - ma) / maxf(mb - ma, 0.001))
			break
	# Pilvet: harmaampi ja tummempi; myrsky tummin
	var c := Game.cloud_amount()
	var lum := (col.r + col.g + col.b) / 3.0
	var overcast := Color(0.66, 0.69, 0.76).lerp(Color(0.46, 0.49, 0.56), clampf((c - 0.6) / 0.4, 0.0, 1.0))
	return col.lerp(Color(lum * overcast.r, lum * overcast.g, lum * overcast.b), c)


func _process(delta: float) -> void:
	var indoors := _indoors()
	_indoor_k = move_toward(_indoor_k, 1.0 if indoors else 0.0, delta * 4.0)
	var out_k := 1.0 - _indoor_k

	var sky := Color.WHITE.lerp(sky_color(), out_k)
	var lum := (sky.r + sky.g + sky.b) / 3.0
	_night = clampf((0.85 - lum) / 0.6, 0.0, 1.0)

	# Ukkosmyrsky: salama välähtää, jyrinä kuuluu perässä
	_flash = move_toward(_flash, 0.0, delta * 3.0)
	if Game.weather == "storm" and Game.weather_k > 0.5 and out_k > 0.5:
		_next_lightning -= delta
		if _next_lightning <= 0.0:
			_next_lightning = randf_range(6.0, 16.0)
			_flash = randf_range(0.6, 0.9)
			Sfx.thunder(randf_range(0.25, 1.6))
	else:
		_next_lightning = randf_range(4.0, 9.0)

	if is_instance_valid(_mod):
		_mod.color = sky.lerp(Color(1.0, 1.0, 1.0), _flash)
	_update_lights(out_k)

	# Sääkerrokset peittävät aina koko ruudun. Pelkät ankkurit eivät riittäneet: piilotettu
	# Control ei saanut kokoa, jolloin pisarat piirtyivät 0x0-alueelle ruudun vasempaan yläkulmaan.
	_fit_to_screen()

	var rain := Game.rain_amount() * out_k
	var snow := Game.snow_amount() * out_k
	var fog := Game.fog_amount() * out_k

	# Sumu ajelehtii tuulen mukana; yöllä sumu on tummaa
	_fog_drift += Vector2(0.04 + Game.wind * 0.08, 0.01) * delta
	_fog_mat.set_shader_parameter("amount", fog * 0.75)
	_fog_mat.set_shader_parameter("drift", _fog_drift)
	_fog_mat.set_shader_parameter("tint", Color(0.82, 0.84, 0.88).lerp(Color(0.22, 0.25, 0.34), _night))
	_fog_rect.visible = fog > 0.01

	# Maahan kertynyt lumi valkaisee kaupunkia (yöllä vähemmän, ettei pimeä valkene)
	_snow_rect.color.a = (Game.snow_cover * 0.3 + snow * 0.06) * out_k * (1.0 - 0.75 * _night)
	_snow_rect.visible = _snow_rect.color.a > 0.005

	_drops.rain = rain
	_drops.snow = snow
	_drops.wind = Game.wind
	_drops.brightness = lerpf(1.0, 0.5, _night)
	Sfx.set_rain(rain * (1.25 if Game.weather == "storm" else 1.0))


## Asettaa sään piirtokerrokset koko näkymän kokoisiksi (myös ikkunan koon muuttuessa).
func _fit_to_screen() -> void:
	var vs := get_viewport().get_visible_rect().size
	for c: Control in [_snow_rect, _fog_rect, _drops]:
		if c.position != Vector2.ZERO:
			c.position = Vector2.ZERO
		if c.size != vs:
			c.size = vs


# ----------------------------------------------------------------------------
#  VALOT
# ----------------------------------------------------------------------------
## col = Color.TRANSPARENT pitää valon nykyisen värin.
func _set_light(l: PointLight2D, pos: Vector2, energy: float, col: Color = Color.TRANSPARENT) -> void:
	l.global_position = pos
	l.energy = energy
	l.enabled = energy > 0.01
	if col.a > 0.0:
		l.color = col


func _off(list: Array, from: int) -> void:
	for i in range(from, list.size()):
		(list[i] as PointLight2D).enabled = false


func _update_lights(out_k: float) -> void:
	if not _lights_root.is_inside_tree():
		return   # valot lisätään kenttään viiveellä (call_deferred)
	var e := _night * out_k
	if e < 0.02:
		for list in [_lamps, _doors, _traffic, _police, _head]:
			_off(list, 0)
		_player_light.enabled = false
		return
	var cam := get_viewport().get_camera_2d()
	var center: Vector2 = cam.get_screen_center_position() if cam else Vector2.ZERO
	var view := get_viewport().get_visible_rect().size / (cam.zoom if cam else Vector2.ONE)
	var area := Rect2(center - view * 0.5, view).grow(120.0)

	# Katulamput: lähimmät näkymässä
	var used := 0
	if _city and "lamp_points" in _city:
		var near: Array = []
		for wp: Vector2 in _city.lamp_points:
			if area.has_point(wp):
				near.append(wp)
		if near.size() > _lamps.size():
			near.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(center) < b.distance_squared_to(center))
		for wp: Vector2 in near:
			if used >= _lamps.size():
				break
			_set_light(_lamps[used], wp + Vector2(0, 10), 1.1 * e)
			used += 1
	_off(_lamps, used)

	# Ovet (palvelut, baari, koti, asekauppa)
	used = 0
	for grp in ["service", "bar", "armory", "home"]:
		for b in get_tree().get_nodes_in_group(grp):
			if used >= _doors.size() or not ("door_px" in b):
				continue
			var dp: Vector2 = b.door_px
			if area.has_point(dp):
				_set_light(_doors[used], dp + Vector2(0, 12), 0.9 * e)
				used += 1
	_off(_doors, used)

	# Pelaaja tai ajettava auto (ajovalokeila eteen)
	var car := _driven_car()
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if car:
		var fwd := _car_dir(car)
		var offs := [6.0, 34.0, 68.0, 104.0]
		for i in _head.size():
			_set_light(_head[i], car.global_position + fwd * float(offs[i]), (1.2 if i > 0 else 0.7) * e)
		_player_light.enabled = false
	else:
		_off(_head, 0)
		if player:
			var pp: Vector2 = player.body_center() if player.has_method("body_center") else player.global_position
			_set_light(_player_light, pp, 0.75 * e)

	# Poliisiautot: punasininen vilkku + ajovalo
	used = 0
	var units: Array = []
	var pm := get_tree().get_first_node_in_group("police_manager")
	if pm and "cars" in pm:
		units.append_array(pm.cars)
	var patrol := get_tree().get_first_node_in_group("police_patrol")
	if patrol and "patrols" in patrol:
		units.append_array(patrol.patrols)
	var blink := (Time.get_ticks_msec() / 180) % 2 == 0
	for u in units:
		if used >= _police.size():
			break
		if not is_instance_valid(u) or u.dead:
			continue
		var up: Vector2 = (u as Node2D).global_position
		if not area.has_point(up):
			continue
		var on: bool = true
		if "light_a" in u and u.light_a:
			on = u.light_a.visible
		if on:
			_set_light(_police[used], up, 1.3 * e, RED if blink else BLUE)
			used += 1
	_off(_police, used)

	# Liikenteen ajovalot
	used = 0
	if _city and "entities" in _city and _city.entities:
		for m in _city.entities.get_children():
			if used >= _traffic.size():
				break
			if not ("is_car" in m) or not m.is_car or Game.flag(m, "wrecked"):
				continue
			var mp: Vector2 = (m as Node2D).global_position
			if not area.has_point(mp):
				continue
			_set_light(_traffic[used], mp + Vector2(m.dir) * 24.0, 0.9 * e)
			used += 1
	_off(_traffic, used)


func _driven_car() -> Node2D:
	for c in get_tree().get_nodes_in_group("player_vehicles"):
		if "is_driving" in c and c.is_driving:
			return c
	return null


## Auton ajosuunta nopeudesta (seisoessa viimeisin suunta).
func _car_dir(car: Node2D) -> Vector2:
	var v := Vector2.ZERO
	if "velocity" in car:
		v = car.velocity
	if v.length() > 15.0:
		var d := v.normalized()
		_last_car_dir[car] = d
		return d
	var last: Vector2 = _last_car_dir.get(car, Vector2.UP)
	return last


## Sadepisarat, roiskeet ja lumihiutaleet ruutukoordinaateissa.
class Drops extends Control:
	var rain := 0.0
	var snow := 0.0
	var wind := 0.3
	var brightness := 1.0
	var _pts: Array = []       # [Vector2 pos (0..1), float nopeus, float vaihe, float koko]
	var _splash: Array = []    # [Vector2 pos (0..1), float ikä]
	const COUNT := 420

	func _ready() -> void:
		for i in COUNT:
			_pts.append([Vector2(randf(), randf()), randf_range(0.75, 1.25), randf() * TAU, randf()])

	func _process(delta: float) -> void:
		if rain <= 0.01 and snow <= 0.01 and _splash.is_empty():
			if visible:
				hide()
			return
		show()
		var t := float(Time.get_ticks_msec()) / 1000.0
		var raining := rain >= snow
		for p: Array in _pts:
			var pos: Vector2 = p[0]
			if raining:
				pos += Vector2(wind * 0.9, 2.2) * delta * float(p[1])
			else:
				pos += Vector2(wind * 0.12 + sin(t * 1.3 + float(p[2])) * 0.03, 0.12 + 0.08 * float(p[3])) * delta * float(p[1])
			if pos.y > 1.05:
				pos = Vector2(randf() * 1.2 - 0.1, -0.05)
			if pos.x > 1.08:
				pos.x -= 1.15
			elif pos.x < -0.08:
				pos.x += 1.15
			p[0] = pos
		# Roiskeet maassa sateessa
		if raining and rain > 0.05:
			var spawn := int(rain * 700.0 * delta) + (1 if randf() < rain else 0)
			for i in spawn:
				_splash.append([Vector2(randf(), randf()), 0.0])
		for i in range(_splash.size() - 1, -1, -1):
			var sp: Array = _splash[i]
			sp[1] = float(sp[1]) + delta
			if float(sp[1]) > 0.35:
				_splash.remove_at(i)
		queue_redraw()

	func _draw() -> void:
		# Koko näkymä (ei Controlin omaa kokoa, joka voi olla 0 kun kerros on ollut piilossa)
		var s := get_viewport_rect().size
		var raining := rain >= snow
		var amount := maxf(rain, snow)
		var active := int(COUNT * clampf(amount, 0.0, 1.0))
		var b := brightness
		if raining:
			var slant := Vector2(wind * 9.0, 22.0)
			for i in active:
				var p: Array = _pts[i]
				var pos: Vector2 = (p[0] as Vector2) * s
				var len_k := 0.7 + 0.6 * float(p[3])
				draw_line(pos, pos + slant * len_k, Color(0.72 * b, 0.8 * b, 0.95 * b, 0.35 + 0.25 * rain), 1.2 + float(p[3]))
			for sp: Array in _splash:
				var age: float = sp[1]
				var c := (sp[0] as Vector2) * s
				draw_arc(c, 2.0 + age * 18.0, 0.0, TAU, 10, Color(0.75 * b, 0.82 * b, 0.95 * b, 0.5 * (1.0 - age / 0.35)), 1.0)
		else:
			for i in active:
				var p: Array = _pts[i]
				var pos: Vector2 = (p[0] as Vector2) * s
				draw_circle(pos, 1.2 + float(p[3]) * 2.6, Color(b, b, b * 1.02, 0.55 + 0.35 * float(p[3])))
