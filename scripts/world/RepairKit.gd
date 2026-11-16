extends Node2D
## Korjaussetti kodin autotallin vieressä.
##  - Aja vaurioitunut auto tallin eteen, nouse ulos ja paina E työkalulaatikon luona.
##  - Korjaus kestää REPAIR_TIME sekuntia. Pysy laatikon luona; E uudelleen keskeyttää.
##  - Palavaa tai palanutta autoa ei voi korjata.
##
## Home.gd luo tämän add_details():ssa (vain jos kodilla on autotalli).

const REPAIR_TIME := 10.0     ## korjauksen kesto (s)
const CAR_RANGE := 72.0       ## kuinka lähellä laatikkoa auton pitää olla (px)
const STAY_RANGE := 60.0      ## pelaaja ei saa korjauksen aikana mennä tätä kauemmas laatikosta (px)

var _car: Node2D = null
var _player: Node2D = null
var _t := 0.0
var _sound_t := 0.0
var _bar: ProgressView = null


## center = laatikon keskipiste maailmassa
func setup(center: Vector2) -> void:
	global_position = center
	InteractSpot.create(self, center, Vector2(30.0, 30.0), _prompt, _use)


func repairing() -> bool:
	return _car != null


## Lähin auto, jota voi korjata (ei ajossa). Palauttaa myös palavan / romun, jotta kehote osaa kertoa syyn.
func _nearest_car() -> Node2D:
	var best: Node2D = null
	var best_d := CAR_RANGE
	for c in get_tree().get_nodes_in_group("player_vehicles"):
		var car := c as Node2D
		if car == null or not is_instance_valid(car) or Game.flag(car, "is_driving"):
			continue
		var d := car.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = car
	return best


func _prompt() -> String:
	if repairing():
		return "Korjataan autoa... (E keskeyttää)"
	var car := _nearest_car()
	if car == null:
		return "Korjaussetti: aja vaurioitunut auto tallin eteen"
	if Game.flag(car, "exploded"):
		return "Palanutta romua ei voi enää korjata"
	if Game.flag(car, "burning"):
		return "Auto palaa! Sitä ei voi korjata"
	var k: float = car.call("health_ratio") if car.has_method("health_ratio") else 1.0
	if k >= 1.0:
		return "Auto on ehjä (paina E noustaksesi autoon)"
	return "Paina E korjataksesi auto (kunto %d %%, kestää %d s)" % [roundi(k * 100.0), int(REPAIR_TIME)]


func _use(player: Node2D) -> void:
	if repairing():
		_stop("Korjaus keskeytettiin.")
		return
	var car := _nearest_car()
	if car == null or not car.has_method("needs_repair") or not car.needs_repair():
		# Ei korjattavaa: E toimii kuten tavallisesti auton vieressä (noustaan autoon)
		if car and not Game.flag(car, "burning") and player.get("current_car") and player.has_method("enter_car"):
			player.enter_car()
		elif car == null:
			_msg("Tuo vaurioitunut auto tallin eteen, niin voit korjata sen.")
		return
	_car = car
	_player = player
	_t = 0.0
	_sound_t = 0.0
	Sfx.play("clang", car.global_position, -6.0, 0.1, 1.3)
	_bar = ProgressView.new()
	_bar.z_index = 4002
	get_parent().add_child(_bar)
	_bar.global_position = car.global_position + Vector2(0.0, -22.0)
	_msg("Korjataan autoa... pysy auton luona %d s." % int(REPAIR_TIME))


func _process(delta: float) -> void:
	if not repairing():
		return
	# Keskeytys: auto ajettiin pois / syttyi / pelaaja lähti
	if not is_instance_valid(_car) or Game.flag(_car, "burning") or Game.flag(_car, "exploded"):
		_stop("Korjaus keskeytyi.")
		return
	if Game.flag(_car, "is_driving") or _car.global_position.distance_to(global_position) > CAR_RANGE + 8.0:
		_stop("Korjaus keskeytyi: auto siirtyi.")
		return
	if not is_instance_valid(_player) or not _player.visible or _player.global_position.distance_to(global_position) > STAY_RANGE:
		_stop("Korjaus keskeytyi: menit liian kauas.")
		return
	_t += delta
	_bar.global_position = _car.global_position + Vector2(0.0, -22.0)
	_bar.progress = _t / REPAIR_TIME
	_bar.seconds_left = maxi(ceili(REPAIR_TIME - _t), 0)
	_bar.queue_redraw()
	# Työkalujen kilinää ja kipinöitä
	_sound_t -= delta
	if _sound_t <= 0.0:
		_sound_t = randf_range(0.5, 1.0)
		var at := _car.global_position + Vector2(randf_range(-8.0, 8.0), randf_range(-3.0, 4.0))
		Sfx.play("clang" if randf() < 0.6 else "clink", at, -10.0, 0.15, randf_range(1.1, 1.6))
		if _car.has_method("_sparks") and randf() < 0.5:
			_car.call("_sparks", at, Vector2.UP, 4)
	if _t >= REPAIR_TIME:
		_car.repair()
		Sfx.play("engine_start", _car.global_position, -4.0, 0.05)
		_stop("Auto korjattu! Kunto 100 %.")


func _stop(text: String) -> void:
	_car = null
	_player = null
	if is_instance_valid(_bar):
		_bar.queue_free()
	_bar = null
	_msg(text)
	# Kehote ajan tasalle, jos pelaaja seisoo yhä laatikon luona
	var p := get_tree().get_first_node_in_group("player")
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if p and hud:
		for n in get_children():
			if n is InteractSpot and p.get("nearby_portal") == n:
				hud.show_instruction(n.prompt_text())


func _msg(text: String) -> void:
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(text, 2.5)


## Työkalulaatikko, nosturi ja vararengas maan tasolla (paikalliset koordinaatit, laatikko keskellä).
func _draw() -> void:
	# varjo
	draw_rect(Rect2(-6.0, 1.0, 14.0, 4.0), Color(0, 0, 0, 0.25))
	# punainen työkalulaatikko
	var box := Rect2(-6.0, -6.0, 12.0, 8.0)
	draw_rect(box, Color(0.78, 0.13, 0.12))
	draw_rect(Rect2(box.position, Vector2(box.size.x, 2.0)), Color(0.92, 0.3, 0.25))
	draw_rect(Rect2(-6.0, -2.0, 12.0, 1.0), Color(0.45, 0.06, 0.06))
	draw_rect(Rect2(-1.0, -3.0, 2.0, 2.0), Color(0.85, 0.85, 0.8))   # lukko
	draw_rect(box, Color(0.25, 0.04, 0.04), false, 1.0)
	# kahva
	draw_rect(Rect2(-3.0, -9.0, 6.0, 1.0), Color(0.2, 0.2, 0.22))
	draw_rect(Rect2(-3.0, -9.0, 1.0, 3.0), Color(0.2, 0.2, 0.22))
	draw_rect(Rect2(2.0, -9.0, 1.0, 3.0), Color(0.2, 0.2, 0.22))
	# jakoavain laatikon päällä
	draw_line(Vector2(-5.0, -7.0), Vector2(2.0, -10.0), Color(0.75, 0.77, 0.8), 1.0)
	draw_rect(Rect2(1.0, -11.5, 3.0, 2.0), Color(0.75, 0.77, 0.8))
	# vararengas vieressä
	var tyre := Vector2(12.0, -1.0)
	draw_circle(tyre, 4.5, Color(0.08, 0.08, 0.09))
	draw_circle(tyre, 2.0, Color(0.6, 0.62, 0.66))
	draw_circle(tyre, 0.8, Color(0.3, 0.3, 0.32))
	# keltainen tunkki
	draw_rect(Rect2(-14.0, -1.0, 6.0, 3.0), Color(0.95, 0.75, 0.1))
	draw_rect(Rect2(-12.0, -5.0, 2.0, 4.0), Color(0.8, 0.6, 0.05))
	draw_rect(Rect2(-13.0, -6.0, 4.0, 1.0), Color(0.3, 0.3, 0.32))


## Edistymispalkki korjattavan auton yllä.
class ProgressView extends Node2D:
	var progress := 0.0
	var seconds_left := 10

	func _draw() -> void:
		var w := 30.0
		var bg := Rect2(-w * 0.5 - 1.0, -1.0, w + 2.0, 6.0)
		draw_rect(bg, Color(0.05, 0.05, 0.07, 0.85))
		draw_rect(Rect2(-w * 0.5, 0.0, w * clampf(progress, 0.0, 1.0), 4.0), Color(0.3, 0.85, 0.35))
		draw_rect(bg, Color(0.9, 0.9, 0.9, 0.9), false, 1.0)
		var font := ThemeDB.fallback_font
		var txt := "KORJAUS %d s" % seconds_left
		var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
		draw_string(font, Vector2(-sz.x * 0.5 + 0.5, -2.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(-sz.x * 0.5, -3.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(1.0, 0.95, 0.6))
