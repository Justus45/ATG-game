extends Node2D
## LUKSUSAUTOTALLI kartanon alla (ServiceBuilding "manor" luo tämän).
##  - kaikki omat kulkuneuvot (oma auto, Bemari 635 CSi, Furia V12) säilyvät omilla valaistuilla paikoillaan
##  - kartanon julkisivun vasemmassa reunassa nosto-ovi: aja omalla autolla oven eteen -> auto
##    ajaa talliin ja pysäköityy, kävellen E vie sisään
##  - tallissa nouse autoon (E) ja aja ulos-ovesta suoraan kadulle
##  - ladattaessa omat kulkuneuvot palaavat talliin (Home.gd / Market.gd kutsuvat store())

const W := 480.0
const H := 256.0
const ORIGIN := Vector2(-5600.0, -2600.0)
const BAYS := [Vector2(64.0, 104.0), Vector2(152.0, 104.0), Vector2(240.0, 104.0), Vector2(328.0, 104.0), Vector2(416.0, 104.0)]
const EXIT_ZONE := Rect2(200.0, 214.0, 80.0, 26.0)     ## ajetaan tästä ulos
const LOUNGE := Rect2(386.0, 196.0, 74.0, 22.0)
const TOOLS := Rect2(20.0, 196.0, 60.0, 14.0)

var building: Node2D = null
var inside := false
var origin := ORIGIN
var _busy := false
var _cd := 0.0
var _saved_limits := {}
var _fade: ColorRect
var _view: Node2D


func setup(b: Node2D) -> void:
	building = b
	add_to_group("indoor_room")
	add_to_group("luxury_garage")
	position = origin
	z_index = -10
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04)
	bg.position = Vector2(-1500.0, -1500.0)
	bg.size = Vector2(3000.0 + W, 3000.0 + H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -20
	add_child(bg)
	_view = GarageView.new()
	_view.set("garage", self)
	_view.set("L", {"BAYS": BAYS, "EXIT_ZONE": EXIT_ZONE, "LOUNGE": LOUNGE, "TOOLS": TOOLS})
	add_child(_view)
	# seinät (ulos-ovi alareunan keskellä jää auki -> ajetaan EXIT_ZONE:en)
	for r: Rect2 in [Rect2(0, 0, W, 40), Rect2(0, 0, 16, H), Rect2(W - 16, 0, 16, H),
			Rect2(0, H - 16, EXIT_ZONE.position.x, 16), Rect2(EXIT_ZONE.end.x, H - 16, W - EXIT_ZONE.end.x, 16),
			Rect2(EXIT_ZONE.position.x, H - 4, EXIT_ZONE.size.x, 4), LOUNGE, TOOLS]:
		_block(r)
	# kävellen ulos
	InteractSpot.create(self, origin + Vector2(W * 0.5, H - 30.0), Vector2(60.0, 16.0), "Paina E: kävele ulos (tai aja autolla ovesta)", func(p: Node2D) -> void: walk_out(p))
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)


func _block(r: Rect2) -> void:
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	body.position = r.get_center()


## Tallin oven kohta ulkona (kartanon julkisivun vasen reuna)
func door_outside() -> Vector2:
	return building.call("garage_door_px") as Vector2


func _outside_zone() -> Rect2:
	var d := door_outside()
	return Rect2(d.x - 18.0, d.y + 2.0, 36.0, 22.0)


# ----------------------------------------------------------------------------
#  OMAT KULKUNEUVOT
# ----------------------------------------------------------------------------
func owned_vehicles() -> Array:
	var out: Array = []
	var car := get_tree().current_scene.get_node_or_null("Car")
	if car and is_instance_valid(car) and not Game.flag(car, "exploded"):
		out.append(car)
	for g: String in ["classic", "supercar"]:
		for v in get_tree().get_nodes_in_group(g):
			if is_instance_valid(v) and not Game.flag(v, "exploded") and not out.has(v):
				out.append(v)
	return out


func _is_owned(v: Node) -> bool:
	return owned_vehicles().has(v)


func _bay_taken(i: int, except: Node) -> bool:
	var p := origin + (BAYS[i] as Vector2)
	for v in owned_vehicles():
		if v != except and (v as Node2D).global_position.distance_to(p) < 20.0:
			return true
	return false


## Pysäköi kulkuneuvon vapaalle paikalle. Palauttaa false, jos talli on täynnä.
func store(v: Node2D) -> bool:
	for i in BAYS.size():
		if not _bay_taken(i, v):
			v.call("park_at", origin + (BAYS[i] as Vector2), &"car_down")
			return true
	return false


## Mikä kulkuneuvo on missäkin paikassa (piirtoa varten)
func bay_vehicle(i: int) -> Node2D:
	var p := origin + (BAYS[i] as Vector2)
	for v in owned_vehicles():
		if (v as Node2D).global_position.distance_to(p) < 20.0:
			return v
	return null


# ----------------------------------------------------------------------------
#  SISÄÄN JA ULOS
# ----------------------------------------------------------------------------
func _process(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)
	if _busy or not Game.owns_manor:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	# ajettava auto haetaan ajotilasta (pelaajan current_car nollautuu autoon noustessa)
	var driven: Node2D = null
	for v in get_tree().get_nodes_in_group("player_vehicles"):
		if is_instance_valid(v) and Game.flag(v, "is_driving"):
			driven = v as Node2D
			break
	var driving: bool = driven != null
	# Turvaverkko: pelaaja on tallissa, mutta tila sanoo "ulkona" -> kamerarajat talliin
	var here: Node2D = driven if driving else player
	if not inside and Rect2(origin, Vector2(W, H)).grow(8.0).has_point(here.global_position):
		inside = true
		_set_camera_limits(true)
		var cam := get_viewport().get_camera_2d()
		if cam:
			cam.global_position = here.global_position
		return
	if inside:
		if driving and Rect2(origin + EXIT_ZONE.position, EXIT_ZONE.size).has_point(driven.global_position):
			_drive_out(driven)
		elif not driving and player.global_position.distance_to(origin) > 1400.0:
			inside = false
			_set_camera_limits(false)
	elif driving and _cd <= 0.0 and _outside_zone().has_point(driven.global_position) and _is_owned(driven):
		var pm := get_tree().get_first_node_in_group("police_manager")
		if pm and int(pm.get("wanted")) > 0:
			if _cd <= 0.0:
				Game.msg("Kytät on perässä – tallin ovi ei aukea nyt.", 2.0)
				_cd = 3.0
			return
		_drive_in(driven, player)


func _drive_in(car: Node2D, player: Node2D) -> void:
	_busy = true
	car.set("exit_cooldown", 2.0)   # E ei pudota kuskia ulos kesken siirtymän
	Sfx.play("door_open", car.global_position, -6.0, 0.1, 0.6)
	await _fade_to(1.0)
	inside = true
	_set_camera_limits(true)
	if not store(car):
		car.call("park_at", origin + Vector2(W * 0.5, 170.0), &"car_down")
	if car.has_method("exit_car"):
		car.call("exit_car")
	var cam := get_viewport().get_camera_2d()
	if cam:
		cam.global_position = player.global_position
	await _fade_to(0.0)
	Game.msg("%s pysäköity luksustalliin." % str(car.get("display_name")), 2.0)
	_busy = false


func _drive_out(car: Node2D) -> void:
	_busy = true
	car.set("exit_cooldown", 2.0)   # E ei pudota kuskia talliin kesken siirtymän
	Sfx.play("door_open", car.global_position, -6.0, 0.1, 0.6)
	await _fade_to(1.0)
	if not is_instance_valid(car) or not Game.flag(car, "is_driving"):
		# kuski ehti nousta autosta: jäädään talliin (kamera pysyy tallissa pelaajan luona)
		var pl := get_tree().get_first_node_in_group("player") as Node2D
		var cam0 := get_viewport().get_camera_2d()
		if cam0 and pl:
			cam0.global_position = pl.global_position
		await _fade_to(0.0)
		_cd = 1.0
		_busy = false
		return
	inside = false
	_set_camera_limits(false)
	var out := door_outside() + Vector2(0.0, 40.0)
	car.call("launch_at", out, &"car_down", 60.0)
	var cam := get_viewport().get_camera_2d()
	if cam:
		cam.global_position = out
	_cd = 3.0
	await _fade_to(0.0)
	_busy = false


## Kävellen sisään (tallin ovelta ulkoa)
func walk_in(player: Node2D) -> void:
	if _busy:
		return
	_busy = true
	_lock(player, true)
	await _fade_to(1.0)
	inside = true
	_set_camera_limits(true)
	_move_player(player, origin + Vector2(W * 0.5, H - 46.0))
	await _fade_to(0.0)
	_lock(player, false)
	_busy = false


func walk_out(player: Node2D) -> void:
	if _busy:
		return
	_busy = true
	_lock(player, true)
	await _fade_to(1.0)
	inside = false
	_set_camera_limits(false)
	_move_player(player, door_outside() + Vector2(0.0, 30.0))
	_cd = 2.0
	await _fade_to(0.0)
	_lock(player, false)
	_busy = false


func _lock(player: Node2D, on: bool) -> void:
	player.set_physics_process(not on)
	player.set_process_unhandled_input(not on)
	if "velocity" in player:
		player.velocity = Vector2.ZERO
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud and on:
		hud.hide_instruction()


func _fade_to(alpha: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, 0.25)
	await tw.finished


func _move_player(player: Node2D, target: Vector2) -> void:
	var col := player.get_node_or_null("CollisionShape2D") as Node2D
	var off := col.position if col else Vector2.ZERO
	player.global_position = target - off
	var cam := get_viewport().get_camera_2d()
	if cam:
		cam.global_position = target


func _set_camera_limits(in_room: bool) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	if in_room:
		if _saved_limits.is_empty():
			_saved_limits = {"l": cam.limit_left, "t": cam.limit_top, "r": cam.limit_right, "b": cam.limit_bottom}
		var r := Rect2(origin, Vector2(W, H)).grow(24.0)
		cam.limit_left = int(r.position.x)
		cam.limit_top = int(r.position.y)
		cam.limit_right = int(r.end.x)
		cam.limit_bottom = int(r.end.y)
	elif not _saved_limits.is_empty():
		cam.limit_left = _saved_limits.l
		cam.limit_top = _saved_limits.t
		cam.limit_right = _saved_limits.r
		cam.limit_bottom = _saved_limits.b
		_saved_limits = {}


# ----------------------------------------------------------------------------
#  PIIRTO
# ----------------------------------------------------------------------------
class GarageView extends Node2D:
	const VW := 480.0
	const VH := 256.0
	const GOLD := Color(0.88, 0.72, 0.3)
	const NEON := Color(0.3, 0.85, 1.0)
	var garage: Node2D = null
	var L := {}
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if garage and garage.get("inside"):
			queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		# kiiltävä epoksilattia heijastuksineen
		var fr := Rect2(16, 40, VW - 32, VH - 56)
		draw_rect(fr, Color(0.14, 0.15, 0.18))
		for k in 9:
			var x := fr.position.x + 20.0 + k * 52.0
			draw_line(Vector2(x, fr.position.y), Vector2(x - 30.0, fr.end.y), Color(1, 1, 1, 0.035), 6.0)
		# seinät: tumma betoni, neonlistat
		draw_rect(Rect2(0, 0, VW, 40), Color(0.1, 0.1, 0.12))
		draw_rect(Rect2(0, 36, VW, 2), NEON)
		draw_rect(Rect2(0, 38, VW, 4), Color(NEON.r, NEON.g, NEON.b, 0.15))
		draw_rect(Rect2(0, 40, 16, VH - 40), Color(0.09, 0.09, 0.11))
		draw_rect(Rect2(VW - 16, 40, 16, VH - 40), Color(0.09, 0.09, 0.11))
		draw_rect(Rect2(14, 40, 2, VH - 56), NEON)
		draw_rect(Rect2(VW - 16, 40, 2, VH - 56), NEON)
		draw_rect(Rect2(0, VH - 16, VW, 16), Color(0.09, 0.09, 0.11))
		# takaseinän logo ja julisteet
		TextFit.draw(self, font, Vector2(0.0, 26.0), "PRIVATE  COLLECTION", VW, 12, GOLD)
		for px: float in [40.0, 400.0]:
			var pr := Rect2(px, 8.0, 40.0, 22.0)
			draw_rect(pr.grow(1.0), Color(0.3, 0.3, 0.34))
			draw_rect(pr, Color(0.15, 0.12, 0.08))
			draw_colored_polygon(PackedVector2Array([pr.position + Vector2(4, 18), pr.position + Vector2(20, 8), pr.position + Vector2(36, 18)]), Color(1.0, 0.75, 0.1))
		# autopaikat: valokeilat, kääntölevyt, viivat ja nimikyltit
		var bays: Array = L.BAYS
		for i in bays.size():
			var b: Vector2 = bays[i]
			var v: Node2D = garage.call("bay_vehicle", i)
			draw_colored_polygon(PackedVector2Array([b + Vector2(-8, -64), b + Vector2(8, -64), b + Vector2(34, 22), b + Vector2(-34, 22)]), Color(1.0, 0.97, 0.85, 0.05))
			draw_set_transform(b + Vector2(0, 6), 0.0, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, 30.0, Color(0.22, 0.23, 0.27))
			draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 32, Color(0.75, 0.77, 0.82, 0.6), 1.5)
			draw_arc(Vector2.ZERO, 26.0, _t * 0.4, _t * 0.4 + 1.2, 12, Color(1, 1, 1, 0.15), 1.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_line(b + Vector2(-38, -28), b + Vector2(-38, 30), Color(0.95, 0.95, 0.9, 0.6), 1.0)
			draw_line(b + Vector2(38, -28), b + Vector2(38, 30), Color(0.95, 0.95, 0.9, 0.6), 1.0)
			var plate := Rect2(b.x - 30.0, b.y + 34.0, 60.0, 11.0)
			draw_rect(plate, Color(0.06, 0.06, 0.08))
			draw_rect(plate, GOLD if v else Color(0.4, 0.4, 0.45), false, 1.0)
			var nm := str(v.get("display_name")) if v else "VAPAA"
			TextFit.draw(self, font, plate.position + Vector2(0, 8.5), nm, plate.size.x, 7, GOLD if v else Color(0.6, 0.6, 0.65))
			draw_circle(b + Vector2(0, -60), 3.0, Color(1.0, 0.97, 0.85))
		# työkaluseinä ja rengasteline
		var tl: Rect2 = L.TOOLS
		draw_rect(tl, Color(0.75, 0.1, 0.1))
		for k in 5:
			draw_rect(Rect2(tl.position.x + 3.0 + k * 11.0, tl.position.y + 2.0, 9.0, 4.0), Color(0.2, 0.2, 0.22))
		for k in 4:
			draw_circle(Vector2(tl.position.x + 8.0 + k * 13.0, tl.position.y - 8.0), 5.0, Color(0.08, 0.08, 0.1))
			draw_circle(Vector2(tl.position.x + 8.0 + k * 13.0, tl.position.y - 8.0), 2.5, Color(0.6, 0.62, 0.68))
		# lounge: nahkasohva ja shampanjajääkaappi
		var lo: Rect2 = L.LOUNGE
		draw_rect(lo, Color(0.35, 0.18, 0.08))
		draw_rect(Rect2(lo.position.x, lo.position.y - 6.0, lo.size.x, 7.0), Color(0.28, 0.14, 0.06))
		for k in 3:
			draw_rect(Rect2(lo.position.x + 3.0 + k * 23.0, lo.position.y + 3.0, 20.0, 9.0), Color(0.45, 0.24, 0.1))
		var cf := Rect2(lo.position.x - 16.0, lo.position.y - 6.0, 12.0, 26.0)
		draw_rect(cf, Color(0.75, 0.77, 0.8))
		draw_rect(cf.grow(-2.0), Color(0.3, 0.6, 0.8, 0.5))
		for k in 3:
			draw_rect(Rect2(cf.position.x + 3.0 + k * 2.5, cf.position.y + 6.0, 1.6, 5.0), Color(0.12, 0.3, 0.16))
		# nosto-ovi ulos
		var ez: Rect2 = L.EXIT_ZONE
		draw_rect(Rect2(ez.position.x, VH - 16.0, ez.size.x, 16.0), Color(0.55, 0.57, 0.62))
		for k in 5:
			draw_line(Vector2(ez.position.x, VH - 14.0 + k * 3.0), Vector2(ez.end.x, VH - 14.0 + k * 3.0), Color(0.4, 0.42, 0.46), 1.0)
		draw_rect(Rect2(ez.position.x, ez.position.y, ez.size.x, ez.size.y), Color(1.0, 0.85, 0.1, 0.06 + 0.04 * sin(_t * 3.0)))
		for k in 8:
			draw_rect(Rect2(ez.position.x + k * 10.0, ez.position.y - 2.0, 5.0, 2.0), Color(1.0, 0.85, 0.1) if k % 2 == 0 else Color(0.1, 0.1, 0.1))
		TextFit.draw(self, font, Vector2(ez.position.x, ez.get_center().y + 3.0), "ULOS", ez.size.x, 8, Color(1.0, 0.9, 0.4))
