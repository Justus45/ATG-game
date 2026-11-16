extends Node2D
## Kartanon ulkoasu (ServiceBuilding "manor"): EI tekstikylttiä.
##  part = "roof":   mansardikatto liuskekivistä, kattoikkunat, savupiiput savuineen,
##                   keskipaviljonki ja pylväikön päätykolmio (z 50, hahmojen päällä)
##  part = "facade": kermanvärinen kivijulkisivu, kaari-ikkunat (yöllä valaistut),
##                   pilasterit, pylväät, pariovi, portaat, lyhdyt ja muotopuut (hahmojen alla)

var part := "roof"
var roof := Rect2()
var door := Vector2.ZERO        ## oven keskipiste (maailma)
var _t := 0.0

const SLATE := Color(0.2, 0.23, 0.29)
const SLATE_L := Color(0.28, 0.31, 0.38)
const LEAD := Color(0.42, 0.45, 0.5)
const GOLD := Color(0.88, 0.72, 0.3)
const STONE := Color(0.93, 0.89, 0.8)
const STONE_D := Color(0.8, 0.75, 0.65)
const WHITE := Color(0.98, 0.97, 0.94)


func _process(delta: float) -> void:
	_t += delta
	var cam := get_viewport().get_camera_2d()
	if cam == null or cam.get_screen_center_position().distance_to(roof.get_center()) < 560.0:
		queue_redraw()


func _draw() -> void:
	if part == "roof":
		_draw_roof()
	else:
		_draw_facade()


func _draw_roof() -> void:
	var r := roof
	draw_rect(Rect2(r.position.x, r.end.y, r.size.x, 3.0), Color(0, 0, 0, 0.3))
	# mansardin jyrkkä lape (liuskekivi) ja loiva yläosa
	draw_rect(r, SLATE)
	var y := r.position.y + 3.0
	while y < r.end.y:
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), SLATE_L, 1.0)
		var x := r.position.x + (4.0 if int(y) % 6 == 0 else 0.0)
		while x < r.end.x:
			draw_line(Vector2(x, y - 3.0), Vector2(x, y), Color(0.15, 0.17, 0.22), 1.0)
			x += 8.0
		y += 4.0
	var top := r.grow_individual(-10.0, -8.0, -10.0, -18.0)
	draw_rect(top, LEAD)
	draw_rect(top, GOLD, false, 1.0)
	draw_rect(r, Color(0.12, 0.13, 0.17), false, 1.0)
	# keskipaviljonki omalla pyramidikatollaan ja kupoli
	var cx := door.x
	var pav := Rect2(cx - 22.0, r.position.y - 6.0, 44.0, r.size.y + 6.0)
	draw_rect(pav, SLATE_L)
	draw_colored_polygon(PackedVector2Array([Vector2(pav.position.x, pav.position.y + 10.0), Vector2(cx, pav.position.y - 4.0), Vector2(pav.end.x, pav.position.y + 10.0)]), SLATE)
	draw_rect(pav, Color(0.12, 0.13, 0.17), false, 1.0)
	draw_circle(Vector2(cx, pav.position.y + 2.0), 5.0, Color(0.35, 0.55, 0.45))   # kuparikupoli
	draw_circle(Vector2(cx - 1.5, pav.position.y + 0.5), 2.0, Color(0.5, 0.72, 0.6))
	draw_line(Vector2(cx, pav.position.y - 3.0), Vector2(cx, pav.position.y - 12.0), GOLD, 1.0)
	# viiri liehuu
	var wv := sin(_t * 3.0) * 1.5
	draw_colored_polygon(PackedVector2Array([Vector2(cx, pav.position.y - 12.0), Vector2(cx + 8.0, pav.position.y - 10.5 + wv), Vector2(cx, pav.position.y - 9.0)]), Color(0.75, 0.1, 0.15))
	# kattoikkunat (yöllä lämmin valo)
	var lit := Game.darkness() > 0.3
	var dx := r.position.x + 14.0
	while dx < r.end.x - 12.0:
		if absf(dx - cx) > 26.0:
			var dw := Rect2(dx - 5.0, r.end.y - 16.0, 10.0, 11.0)
			draw_colored_polygon(PackedVector2Array([Vector2(dw.position.x - 2.0, dw.position.y + 2.0), Vector2(dw.get_center().x, dw.position.y - 5.0), Vector2(dw.end.x + 2.0, dw.position.y + 2.0)]), SLATE_L)
			draw_rect(dw, WHITE)
			draw_rect(dw.grow(-1.5), Color(1.0, 0.85, 0.5) if lit else Color(0.35, 0.5, 0.65))
			draw_line(Vector2(dw.get_center().x, dw.position.y + 1.5), Vector2(dw.get_center().x, dw.end.y - 1.5), WHITE, 1.0)
		dx += 24.0
	# savupiiput ja savu
	for chx: float in [r.position.x + 12.0, r.end.x - 20.0]:
		var ch := Rect2(chx, r.position.y - 4.0, 8.0, 12.0)
		draw_rect(ch, Color(0.55, 0.28, 0.2))
		draw_rect(Rect2(ch.position.x - 1.0, ch.position.y, ch.size.x + 2.0, 2.0), Color(0.4, 0.2, 0.15))
		for k in 3:
			var ph := fmod(_t * 0.4 + k * 0.33 + chx * 0.01, 1.0)
			draw_circle(Vector2(ch.get_center().x + sin(_t + k) * 2.0 + ph * 6.0, ch.position.y - 2.0 - ph * 16.0), 2.0 + ph * 3.0, Color(0.85, 0.85, 0.88, 0.45 * (1.0 - ph)))
	# pylväikön päätykolmio katon alareunassa oven yllä
	var pb := r.end.y
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 26.0, pb + 2.0), Vector2(cx, pb - 14.0), Vector2(cx + 26.0, pb + 2.0)]), WHITE)
	draw_polyline(PackedVector2Array([Vector2(cx - 26.0, pb + 2.0), Vector2(cx, pb - 14.0), Vector2(cx + 26.0, pb + 2.0), Vector2(cx - 26.0, pb + 2.0)]), STONE_D, 1.0)
	draw_circle(Vector2(cx, pb - 4.0), 3.5, GOLD)     # vaakuna
	draw_circle(Vector2(cx, pb - 4.0), 2.0, Color(0.6, 0.1, 0.15))


func _draw_facade() -> void:
	var f := Rect2(roof.position.x, roof.end.y, roof.size.x, door.y + 8.0 - roof.end.y)
	draw_rect(f, STONE)
	draw_rect(Rect2(f.position.x, f.position.y, f.size.x, 3.0), WHITE)                 # reunalista
	draw_rect(Rect2(f.position.x, f.end.y - 4.0, f.size.x, 4.0), STONE_D)              # sokkeli
	# pilasterit
	var px := f.position.x + 2.0
	while px < f.end.x - 2.0:
		draw_rect(Rect2(px, f.position.y + 3.0, 3.0, f.size.y - 7.0), Color(0.97, 0.95, 0.9))
		px += 24.0
	# kaari-ikkunat, ikkunaluukut
	var lit := Game.darkness() > 0.3
	var glass := Color(1.0, 0.85, 0.5) if lit else Color(0.3, 0.45, 0.62)
	# luksustallin nosto-ovi vasemmassa reunassa (LuxuryGarage)
	var gd := Rect2(f.position.x + 7.0, f.position.y + 6.0, 34.0, f.size.y - 6.0)
	draw_rect(gd.grow(2.0), WHITE)
	draw_rect(gd, Color(0.22, 0.23, 0.27))
	var sy := gd.position.y + 2.0
	while sy < gd.end.y:
		draw_line(Vector2(gd.position.x, sy), Vector2(gd.end.x, sy), Color(0.32, 0.33, 0.38), 1.0)
		sy += 3.0
	draw_rect(Rect2(gd.position.x, gd.position.y - 2.0, gd.size.x, 1.5), Color(0.3, 0.85, 1.0))   # LED-lista
	draw_rect(Rect2(gd.position.x, gd.end.y, gd.size.x, 3.0), Color(0.6, 0.6, 0.64))             # ajoluiska
	var wx := f.position.x + 14.0
	while wx < f.end.x - 10.0:
		if absf(wx - door.x) > 24.0 and wx > gd.end.x + 4.0:
			var w := Rect2(wx - 4.0, f.position.y + 7.0, 8.0, f.size.y - 14.0)
			draw_rect(Rect2(w.position.x - 3.0, w.position.y, 2.0, w.size.y), Color(0.15, 0.32, 0.2))
			draw_rect(Rect2(w.end.x + 1.0, w.position.y, 2.0, w.size.y), Color(0.15, 0.32, 0.2))
			draw_rect(w.grow(1.0), WHITE)
			draw_rect(w, glass)
			draw_circle(Vector2(w.get_center().x, w.position.y), 4.0, WHITE)
			draw_circle(Vector2(w.get_center().x, w.position.y + 0.5), 3.0, glass)
			draw_line(Vector2(w.get_center().x, w.position.y - 2.0), Vector2(w.get_center().x, w.end.y), WHITE, 1.0)
			draw_line(Vector2(w.position.x, w.get_center().y), Vector2(w.end.x, w.get_center().y), WHITE, 1.0)
			if lit:
				draw_circle(w.get_center(), 9.0, Color(1.0, 0.8, 0.4, 0.08))
		wx += 24.0
	# pylväät ja pariovi
	var cx := door.x
	for k in 4:
		var colx: float = [cx - 22.0, cx - 14.0, cx + 11.0, cx + 19.0][k]
		draw_rect(Rect2(colx, f.position.y + 1.0, 3.0, f.size.y - 3.0), WHITE)
		draw_rect(Rect2(colx - 1.0, f.position.y + 1.0, 5.0, 2.0), STONE_D)
		draw_rect(Rect2(colx - 1.0, f.end.y - 3.0, 5.0, 2.0), STONE_D)
	var dr := Rect2(cx - 7.0, door.y - 9.0, 14.0, 17.0)
	draw_rect(dr.grow(1.5), GOLD)
	draw_rect(dr, Color(0.32, 0.17, 0.08))
	draw_line(Vector2(cx, dr.position.y), Vector2(cx, dr.end.y), Color(0.2, 0.1, 0.05), 1.0)
	for sx: float in [-1.0, 1.0]:
		draw_rect(Rect2(cx + sx * 4.0 - 1.5, dr.position.y + 3.0, 3.0, 5.0), Color(0.42, 0.24, 0.12), false, 1.0)
		draw_circle(Vector2(cx + sx * 2.0, dr.get_center().y + 2.0), 0.8, GOLD)
	draw_circle(Vector2(cx, dr.position.y - 1.0), 5.0, Color(1.0, 0.85, 0.5, 0.6) if lit else WHITE)
	# portaat
	for k in 2:
		draw_rect(Rect2(cx - 12.0 - k * 3.0, f.end.y + k * 2.0, 24.0 + k * 6.0, 2.0), Color(0.88, 0.86, 0.82) if k == 0 else Color(0.8, 0.78, 0.74))
	# lyhdyt
	for sx: float in [-28.0, 26.0]:
		var lp := Vector2(cx + sx, f.position.y + 10.0)
		draw_rect(Rect2(lp - Vector2(1.5, 3.0), Vector2(3.0, 5.0)), Color(0.1, 0.1, 0.12))
		draw_rect(Rect2(lp - Vector2(1.0, 2.0), Vector2(2.0, 3.0)), Color(1.0, 0.85, 0.45))
		if lit:
			draw_circle(lp, 10.0, Color(1.0, 0.8, 0.4, 0.15))
	# muotoon leikatut puut ruukuissa ovien sivuilla
	for sx: float in [-34.0, 32.0]:
		var tp := Vector2(cx + sx, f.end.y + 2.0)
		draw_rect(Rect2(tp.x - 3.0, tp.y - 4.0, 6.0, 5.0), Color(0.85, 0.82, 0.78))
		draw_line(tp + Vector2(0, -4), tp + Vector2(0, -8), Color(0.4, 0.25, 0.12), 1.0)
		draw_circle(tp + Vector2(0, -11), 4.0, Color(0.15, 0.45, 0.2))
		draw_circle(tp + Vector2(-1, -12), 2.0, Color(0.25, 0.6, 0.3))
