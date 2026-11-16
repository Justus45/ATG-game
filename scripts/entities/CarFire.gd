extends Node2D
## Auton tuli ja savu. Lisätään auton lapseksi (Car2D tai liikenneauto).
##
## Tasot (set_level):
##   SMOKE    -> vaurioitunut auto savuaa konepellistä (vain liikenneautot, Car2D:llä on oma savu)
##   BURNING  -> auto palaa: liekit, musta savu ja oranssi hehku. Räjähtää pian.
##   SMOLDER  -> räjähtänyt romu kytee: pienet liekit ja savu, sammuu hiljalleen
##   OUT      -> ei mitään

enum { OUT, SMOKE, BURNING, SMOLDER }

# --- SÄÄDÄ NÄITÄ ---
const FLAMES_PER_SEC := 34.0      ## liekkejä sekunnissa täysin palavassa autossa
const SMOKE_PER_SEC := 9.0        ## mustan savun tupruja sekunnissa
const SMOLDER_TIME := 25.0        ## kuinka kauan räjähtänyt romu kytee (s)
const GLOW_RADIUS := 70.0         ## hehkun säde (px)

## Liekkien alue auton keskeltä (puolikoko) ja keskipisteen siirtymä
var half := Vector2(7.0, 6.0)
var center := Vector2.ZERO
## false = omistaja hoitaa savun itse (Car2D)
var own_smoke := true

var level := OUT
var _flame_acc := 0.0
var _smoke_acc := 0.0
var _smolder_t := 0.0
var _t := 0.0
var _light: PointLight2D

static var _glow_tex: GradientTexture2D


func set_level(l: int) -> void:
	level = l
	if l == SMOLDER:
		_smolder_t = SMOLDER_TIME
	_update_light()


func _ready() -> void:
	z_index = 0
	_light = PointLight2D.new()
	_light.texture = _get_glow_tex()
	_light.texture_scale = GLOW_RADIUS * 2.0 / 128.0
	_light.color = Color(1.0, 0.55, 0.2)
	_light.range_z_min = -4096
	_light.range_z_max = 4096
	_light.position = center
	add_child(_light)
	_update_light()


static func _get_glow_tex() -> GradientTexture2D:
	if _glow_tex == null:
		_glow_tex = GradientTexture2D.new()
		_glow_tex.width = 128
		_glow_tex.height = 128
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_glow_tex.gradient = g
	return _glow_tex


func _update_light() -> void:
	if _light == null:
		return
	_light.enabled = level == BURNING or level == SMOLDER


func _process(delta: float) -> void:
	_t += delta
	var flames := 0.0
	var smoke := 0.0
	var glow := 0.0
	match level:
		OUT:
			return
		SMOKE:
			smoke = 3.0 if own_smoke else 0.0
		BURNING:
			# tuli yltyy ensimmäisen sekunnin aikana
			var grow := clampf(_t * 1.5, 0.3, 1.0)
			flames = FLAMES_PER_SEC * grow
			smoke = SMOKE_PER_SEC * grow
			glow = 1.1 * grow
		SMOLDER:
			_smolder_t -= delta
			var k := clampf(_smolder_t / SMOLDER_TIME, 0.0, 1.0)
			flames = FLAMES_PER_SEC * 0.35 * k
			smoke = SMOKE_PER_SEC * lerpf(0.25, 0.7, k)
			glow = 0.6 * k
			if _smolder_t <= -SMOLDER_TIME:
				# vain ohut savu jää, lopulta sekin loppuu
				set_level(OUT)
				return
	if _light:
		_light.energy = glow * (0.8 + 0.25 * sin(_t * 23.0) + 0.15 * sin(_t * 7.3))
	_flame_acc += delta * flames
	while _flame_acc >= 1.0:
		_flame_acc -= 1.0
		_spawn_flame(level == BURNING)
	if own_smoke or level != SMOKE:
		_smoke_acc += delta * smoke
		while _smoke_acc >= 1.0:
			_smoke_acc -= 1.0
			_spawn_smoke(level == SMOKE)


func _spawn_flame(big: bool) -> void:
	var parent: Node = get_parent().get_parent() if get_parent() else null
	if parent == null:
		return
	var f := Polygon2D.new()
	var s := randf_range(1.6, 3.2) * (1.0 if big else 0.7)
	# pisaran muotoinen liekki (kärki ylöspäin)
	f.polygon = PackedVector2Array([
		Vector2(0, -s * 2.2), Vector2(s * 0.8, -s * 0.4), Vector2(s, s * 0.4),
		Vector2(0, s), Vector2(-s, s * 0.4), Vector2(-s * 0.8, -s * 0.4)])
	f.color = Color(1.0, 0.95, 0.55)
	f.z_index = 4002
	parent.add_child(f)
	var start := global_position + center + Vector2(randf_range(-half.x, half.x), randf_range(-half.y, half.y * 0.6))
	f.global_position = start
	var life := randf_range(0.35, 0.6)
	var rise := Vector2(Game.wind * 6.0 + randf_range(-3.0, 3.0), -randf_range(9.0, 17.0) * (1.0 if big else 0.6))
	var tw := f.create_tween()
	tw.tween_property(f, "global_position", start + rise, life).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(f, "scale", Vector2(0.3, 0.3), life).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(f, "modulate:a", 0.0, life).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(f.queue_free)
	# väri: keltainen -> oranssi -> punainen
	var tw2 := f.create_tween()
	tw2.tween_property(f, "color", Color(1.0, 0.5, 0.1), life * 0.4)
	tw2.tween_property(f, "color", Color(0.85, 0.15, 0.05), life * 0.6)


func _spawn_smoke(light: bool) -> void:
	var parent: Node = get_parent().get_parent() if get_parent() else null
	if parent == null:
		return
	var p := Polygon2D.new()
	var r := randf_range(1.8, 3.4)
	var pts := PackedVector2Array()
	for j in 7:
		pts.append(Vector2.from_angle(j * TAU / 7.0) * r * randf_range(0.8, 1.1))
	p.polygon = pts
	var g := randf_range(0.55, 0.7) if light else randf_range(0.08, 0.2)
	p.color = Color(g, g, g, 0.75)
	p.z_index = 4003
	parent.add_child(p)
	var start := global_position + center + Vector2(randf_range(-half.x, half.x) * 0.7, -6.0)
	p.global_position = start
	var life := randf_range(1.4, 2.2)
	var drift := Vector2(Game.wind * 26.0 + randf_range(-6.0, 6.0), -randf_range(26.0, 40.0))
	var tw := p.create_tween()
	tw.tween_property(p, "global_position", start + drift, life).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(p, "scale", Vector2(3.2, 3.2), life)
	tw.parallel().tween_property(p, "modulate:a", 0.0, life).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(p.queue_free)
