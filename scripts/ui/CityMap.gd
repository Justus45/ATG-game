extends CanvasLayer
## Koko kaupungin kartta: M avaa ja sulkee (myös Esc sulkee). Peli pysähtyy kartan ajaksi.
## Kartta on sama kuin oikean yläkulman minikartta (Minimap.gd, full_view = true), mutta
## iso, ruudun keskellä, näyttää koko kaupungin ja kaikkien merkittyjen paikkojen nimet.
## Kiinni olevien paikkojen nimet näkyvät punaisina. Game liittää tämän kenttään.

const MinimapScript := preload("res://scripts/ui/Minimap.gd")

var _dim: ColorRect
var _map: Control
var _title: Label
var _open := false
var _was_paused := false


func _ready() -> void:
	add_to_group("city_map")
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_map = MinimapScript.new()
	_map.full_view = true
	add_child(_map)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_title.add_theme_constant_override("outline_size", 6)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	_set_visible(false)


func _set_visible(v: bool) -> void:
	_dim.visible = v
	_map.visible = v
	_title.visible = v


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("full_map"):
		get_viewport().set_input_as_handled()
		if _open:
			close()
		else:
			open()
	elif _open and event is InputEventKey and event.is_pressed() and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func open() -> void:
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud and hud.has_method("menu_open") and hud.menu_open():
		return
	var games := get_tree().get_first_node_in_group("bar_games")
	if games and games.has_method("busy") and games.busy():
		return
	_open = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_layout()
	_set_visible(true)
	Sfx.play_ui("step", -8.0, 1.6)


func close() -> void:
	_open = false
	_set_visible(false)
	get_tree().paused = _was_paused


func _process(_delta: float) -> void:
	if _open:
		_layout()


## Koot suoraan näkymän koosta (ei ankkureita).
func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	_dim.position = Vector2.ZERO
	_dim.size = vs
	var side := floorf(minf(vs.x, vs.y) * 0.86)
	var top := (vs.y - side) * 0.5
	_title.position = Vector2(0.0, maxf(top - 34.0, 2.0))
	_title.size = Vector2(vs.x, 30.0)
	_title.text = "KAUPUNGIN KARTTA   ·   %s %s   ·   M tai Esc sulkee" % [Game.weekday(), Game.clock_text()]
