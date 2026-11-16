extends Control
## Etsintäkuulutustähdet: yksi täytetty tähti = yksi etsintäkuulutustaso.
## Tyhjät tähdet näyttävät puuttuvan tason. Tähdet vilkkuvat kun poliisit
## ovat menettäneet pelaajan näkyvistä (kuulutus on katoamassa).

@export var max_level: int = 3
@export var star_radius: float = 13.0
@export var gap: float = 6.0
@export var filled_color := Color(1.0, 0.82, 0.15)
@export var filled_outline := Color(0.45, 0.28, 0.0, 1.0)
@export var empty_color := Color(0.1, 0.1, 0.12, 0.55)
@export var empty_outline := Color(0.75, 0.75, 0.8, 0.7)

var level: int = 0:
	set(value):
		level = clampi(value, 0, max_level)
		queue_redraw()

## true = poliisit eivät näe pelaajaa, tähdet vilkkuvat
var searching: bool = false:
	set(value):
		searching = value
		_blink_t = 0.0
		if not searching:
			modulate.a = 1.0

var _blink_t := 0.0

func _process(delta: float) -> void:
	if searching:
		_blink_t += delta
		modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(_blink_t * 9.0))

func _draw() -> void:
	var total_w := max_level * star_radius * 2.0 + (max_level - 1) * gap
	# Tasataan oikealle, koska kontrolli on kiinni ruudun oikeassa yläkulmassa
	var x := size.x - total_w + star_radius
	var y := star_radius + 2.0
	for i in max_level:
		var filled := i < level
		_draw_star(Vector2(x, y),
			filled_color if filled else empty_color,
			filled_outline if filled else empty_outline)
		x += star_radius * 2.0 + gap

func _draw_star(center: Vector2, fill: Color, outline: Color) -> void:
	var pts := PackedVector2Array()
	var inner := star_radius * 0.42
	for k in 10:
		var r := star_radius if k % 2 == 0 else inner
		var a := -PI * 0.5 + k * PI / 5.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, fill)
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, outline, 2.0, true)
