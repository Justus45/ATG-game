extends Control
## Rahalaskuri ruudun vasemmassa yläkulmassa: kolikkokuvake + summa. Näkyy koko ajan.

const GOLD := Color(1.0, 0.82, 0.18)

var money := 0

var _style := StyleBoxFlat.new()
var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style.bg_color = Color(0.08, 0.09, 0.13, 0.8)
	_style.set_border_width_all(2)
	_style.border_color = GOLD
	_style.set_corner_radius_all(8)

	_label = Label.new()
	_label.position = Vector2(40.0, 6.0)
	_label.size = Vector2(110.0, 32.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)
	_refresh()


func set_money(value: int) -> void:
	var gained := value - money
	money = value
	_refresh()
	if gained > 0:
		_label.modulate = GOLD
		var tw := create_tween()
		tw.tween_property(_label, "modulate", Color.WHITE, 0.4)
		_float_text("+%d" % gained, Color(0.5, 1.0, 0.5))
	elif gained < 0:
		_label.modulate = Color(1.0, 0.45, 0.4)
		var tw2 := create_tween()
		tw2.tween_property(_label, "modulate", Color.WHITE, 0.5)
		_float_text("%d" % gained, Color(1.0, 0.5, 0.45))


func _refresh() -> void:
	if _label:
		_label.text = "%d $" % money


## Pieni nouseva teksti summan vieressä (esim. "+12").
func _float_text(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(44.0, 38.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.modulate = color
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", 56.0, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(l.queue_free)


func _draw() -> void:
	draw_style_box(_style, Rect2(Vector2.ZERO, Vector2(160.0, 44.0)))
	# Kolikkokuvake
	draw_circle(Vector2(22.0, 22.0), 13.0, Color(0.62, 0.4, 0.05))
	draw_circle(Vector2(22.0, 22.0), 10.5, GOLD)
	draw_circle(Vector2(18.5, 18.5), 3.5, Color(1.0, 0.96, 0.7))
	var font := ThemeDB.fallback_font
	TextFit.draw(self, font, Vector2(17.0, 28.0), "$", -1, 15, Color(0.55, 0.35, 0.03))
