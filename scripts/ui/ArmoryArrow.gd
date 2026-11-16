extends Control
## Keltainen nuoli ruudun reunalla, joka osoittaa asekauppaan kun se ei ole ruudulla.
## Piiloutuu, kun pelaaja on sisällä tai jo kantaa rynnäkkökivääriä.

const GOLD := Color(0.98, 0.8, 0.15)
const MARGIN := 44.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var armory := get_tree().get_first_node_in_group("armory")
	if armory == null or armory.inside:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("has_weapon") and player.has_weapon() \
			and player.held_weapon.weapon_id == "rifle":
		return

	var vp := get_viewport()
	var sp: Vector2 = vp.get_canvas_transform() * armory.door_px
	var screen := Rect2(Vector2.ZERO, vp.get_visible_rect().size)
	if screen.grow(-MARGIN).has_point(sp):
		return  # rakennus on jo näkyvissä

	var area := screen.grow(-MARGIN)
	var center := area.get_center()
	var dir := (sp - center).normalized()
	var t := INF
	if absf(dir.x) > 0.001:
		t = minf(t, area.size.x * 0.5 / absf(dir.x))
	if absf(dir.y) > 0.001:
		t = minf(t, area.size.y * 0.5 / absf(dir.y))
	var p := center + dir * t

	var ang := dir.angle()
	var pts := PackedVector2Array()
	for v: Vector2 in [Vector2(16, 0), Vector2(-9, -11), Vector2(-4, 0), Vector2(-9, 11)]:
		pts.append(p + v.rotated(ang))
	draw_colored_polygon(pts, GOLD)
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0, 0.8), 2.0)

	var cam := vp.get_camera_2d()
	var from_pos: Vector2 = cam.get_screen_center_position() if cam else sp
	var meters := int(from_pos.distance_to(armory.door_px) / 16.0)
	var label_pos := p - dir * 34.0
	var font := ThemeDB.fallback_font
	var text := "Asekauppa %d m" % meters
	TextFit.draw_outline(self, font, label_pos + Vector2(-60.0, 5.0), text, 120.0, 15, 4, Color.BLACK)
	TextFit.draw(self, font, label_pos + Vector2(-60.0, 5.0), text, 120.0, 15, GOLD)
