extends Node2D
## Renkaiden jarrutusjäljet tiellä. Yksi yhteinen solmu autojen vanhemman (y-lajiteltu kerros)
## alla, piirretään kaukana "ylhäällä" y-lajittelussa, jotta jäljet jäävät kaiken alle.
## Jäljet haalistuvat FADE_TIME sekunnissa pois.
##
## Käyttö: preload("res://scripts/entities/SkidMarks.gd").add(auto, alku, loppu, alfa)

const FADE_TIME := 14.0       ## kuinka kauan jälki näkyy (s)
const MAX_SEGMENTS := 900     ## vanhimmat poistetaan, kun raja täyttyy
const SINK_Y := -50000.0      ## solmun paikka: y-lajittelussa kaiken alla
const PATH := "res://scripts/entities/SkidMarks.gd"

var _segs: Array = []         ## [a, b, alfa, ikä]
var _redraw_t := 0.0


static func add(car: Node2D, a: Vector2, b: Vector2, alpha: float) -> void:
	var parent := car.get_parent()
	if parent == null:
		return
	var marks: Node2D = null
	for n in car.get_tree().get_nodes_in_group("skid_marks"):
		if n.get_parent() == parent:
			marks = n
			break
	if marks == null:
		marks = (load(PATH) as GDScript).new()
		marks.add_to_group("skid_marks")
		parent.add_child(marks)
		parent.move_child(marks, 0)   # piirretään ennen autoja (myös ilman y-lajittelua)
		marks.global_position = Vector2(0.0, SINK_Y)
	marks.push(a, b, alpha)


func push(a: Vector2, b: Vector2, alpha: float) -> void:
	_segs.append([a, b, alpha, 0.0])
	if _segs.size() > MAX_SEGMENTS:
		_segs = _segs.slice(_segs.size() - MAX_SEGMENTS)
	queue_redraw()


func _process(delta: float) -> void:
	if _segs.is_empty():
		return
	for s in _segs:
		s[3] = float(s[3]) + delta
	while not _segs.is_empty() and float(_segs[0][3]) > FADE_TIME:
		_segs.pop_front()
	# haalistus: piirretään uudelleen muutaman kerran sekunnissa riittää
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 0.25
		queue_redraw()


func _draw() -> void:
	var off := Vector2(0.0, -SINK_Y)
	for s in _segs:
		var k := 1.0 - clampf(float(s[3]) / FADE_TIME, 0.0, 1.0)
		draw_line(s[0] + off, s[1] + off, Color(0.04, 0.04, 0.05, float(s[2]) * k), 2.0)
