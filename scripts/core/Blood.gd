extends Node2D
## Veri: roiskepisarat ja maahan jäävät tahrat / lätäkkö.
##
## Käyttö (mistä tahansa skriptistä):
##   const BLOOD := preload("res://scripts/core/Blood.gd")
##   BLOOD.spray(self, osumakohta, suunta, pisaroiden_määrä)        # osuma
##   BLOOD.spray(self, osumakohta, suunta, 10, true)                # kuolema: myös lätäkkö
##
## Tahrat lisätään osuman saaneen hahmon vanhemman (y-lajiteltu kerros) lapsiksi, ja ne
## piirretään hahmojen alle. Ne haalistuvat hiljalleen pois.

# --- SÄÄDÄ NÄITÄ ---
const STAIN_TIME := 45.0       ## kuinka kauan tahrat pysyvät ennen haalistumista (s)
const POOL_SIZE := 7.0         ## kuolleen hahmon alle leviävän lätäkön säde (px)
const SINK := 12.0             ## tahra piirretään näin paljon "ylempänä" y-lajittelussa (hahmojen alle)

const PATH := "res://scripts/core/Blood.gd"

var at := Vector2.ZERO
var dir := Vector2.ZERO
var amount := 6
var pool := false
var floor_y := 0.0


## Roiske kohdasta at (maailmassa). dir = osuman suunta (pisarat lentävät siihen), voi olla (0,0).
static func spray(who: Node, hit_at: Vector2, hit_dir: Vector2 = Vector2.ZERO, count: int = 6, with_pool: bool = false) -> void:
	if who == null or not is_instance_valid(who) or not who.is_inside_tree():
		return
	var parent := who.get_parent()
	if parent == null:
		return
	var b: Node2D = (load(PATH) as GDScript).new()
	b.at = hit_at
	b.dir = hit_dir
	b.amount = count
	b.pool = with_pool
	# maa hahmon jalkojen kohdalla
	b.floor_y = (who as Node2D).global_position.y + 4.0 if who is Node2D else hit_at.y + 6.0
	parent.add_child(b)


func _ready() -> void:
	for i in amount:
		_drop()
	if pool:
		_pool()
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(queue_free)


func _drop() -> void:
	var parent := get_parent()
	var d := Polygon2D.new()
	var s := randf_range(0.5, 1.1)
	d.polygon = PackedVector2Array([Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)])
	d.color = Color(randf_range(0.55, 0.78), 0.02, 0.03)
	d.z_index = 4000
	parent.add_child(d)
	d.global_position = at
	var base := dir.normalized() if dir.length() > 0.01 else Vector2.from_angle(randf() * TAU)
	var v := base.rotated(randf_range(-0.9, 0.9)) * randf_range(5.0, 20.0)
	var land := Vector2(at.x + v.x, floor_y + v.y * 0.4 + randf_range(-3.0, 3.0))
	var h := randf_range(3.0, 9.0)
	var dur := randf_range(0.22, 0.42)
	var tw := d.create_tween()
	tw.tween_property(d, "global_position:x", land.x, dur)
	tw.parallel().tween_property(d, "global_position:y", minf(at.y, land.y) - h, dur * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_property(d, "global_position:y", land.y, dur * 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(_stain.bind(land, randf_range(0.8, 1.8)))
	tw.tween_callback(d.queue_free)


## Pieni tahra maahan.
func _stain(where: Vector2, r: float) -> void:
	var parent := get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	var s := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 6:
		pts.append(Vector2.from_angle(i * TAU / 6.0) * Vector2(r * 1.3, r) * randf_range(0.7, 1.1))
	s.polygon = pts
	s.offset = Vector2(0.0, SINK)
	s.color = Color(0.45, 0.02, 0.03, 0.85)
	parent.add_child(s)
	s.global_position = where - Vector2(0.0, SINK)
	_fade(s)


## Kuolleen hahmon alle leviävä lätäkkö.
func _pool() -> void:
	var parent := get_parent()
	var s := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 12:
		pts.append(Vector2.from_angle(i * TAU / 12.0) * Vector2(POOL_SIZE * 1.4, POOL_SIZE * 0.8) * randf_range(0.75, 1.1))
	s.polygon = pts
	s.offset = Vector2(0.0, SINK)
	s.color = Color(0.38, 0.0, 0.02, 0.9)
	parent.add_child(s)
	s.global_position = Vector2(at.x, floor_y) - Vector2(0.0, SINK)
	s.scale = Vector2(0.15, 0.15)
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector2.ONE, 2.5).set_ease(Tween.EASE_OUT)
	_fade(s)


func _fade(s: Polygon2D) -> void:
	var tw := s.create_tween()
	tw.tween_interval(STAIN_TIME)
	tw.tween_property(s, "modulate:a", 0.0, 8.0)
	tw.tween_callback(s.queue_free)
