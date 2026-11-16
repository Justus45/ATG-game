extends Node2D
## Tupakka: savuke kädessä tai suussa, hehkuva pää, tuhka ja savu. Lisätään hahmon kuvan
## (Sprite2D / AnimatedSprite2D) lapseksi, joten seuraa hahmoa ja sen suuntaa.
##
##  - manual = false (NPC:t, Kalle): nostaa savukkeen itse suulle välillä, polttaa loputtomiin.
##  - manual = true (pelaaja): savuke on kädessä; set_inhale(true) nostaa sen suulle ja vetää
##    henkosta niin kauan kuin nappia pidetään, set_inhale(false) laskee sen ja puhaltaa savut.
##    Savuke lyhenee henkosista (ja hitaasti itsestään). Loppuun palanut tumppi heitetään maahan.
##  - on_inhale(delta): kutsutaan henkosen aikana joka ruutu (pelaajan vitutus laskee).
## Suunta luetaan kuvan metatiedosta "cs_col" (CharSprites): 0 vasen, 1 alas, 2 ylös, 3 oikea.

# --- SÄÄDÄ NÄITÄ ---
const AUTO_EVERY := 3.2        ## NPC: henkosten väli (s)
const AUTO_DRAG := 1.0         ## NPC: henkosen kesto (s)
const INHALE_BURN := 14.0      ## pelaaja: savuke kestää näin monta sekuntia henkosia
const PASSIVE_BURN := 240.0    ## ... ja näin kauan, jos sitä ei polteta ollenkaan
const RAISE_TIME := 0.28       ## käden nosto suulle (s)

var sprite: Node2D = null
var manual := false
var duration := -1.0           ## (vanha rajapinta: < 0 = loputon)
var on_inhale: Callable = Callable()
var on_drag: Callable = Callable()   ## (vanha rajapinta: kutsutaan kerran henkosen alussa)
var on_end: Callable = Callable()
var active := true

var length := 1.0              ## jäljellä oleva savuke 0..1
var _want_mouth := false
var _raise := 0.0              ## 0 = kädessä, 1 = suulla
var _drag_time := 0.0          ## tämänhetkisen henkosen kesto
var _auto_t := 1.0
var _t := 0.0
var _wisp_t := 0.0
var _puffs: Array = []         ## savu: {p, v, age, max, r}
var _butt: Dictionary = {}     ## pois heitetty tumppi
var _ending := false


func _ready() -> void:
	z_index = 1
	_auto_t = randf_range(0.5, AUTO_EVERY)


func set_inhale(on: bool) -> void:
	if _ending:
		return
	_want_mouth = on


func is_burning() -> bool:
	return active and not _ending


func stop() -> void:
	if _ending:
		return
	_ending = true
	_want_mouth = false
	# tumppi lentää maahan kipinöiden
	var m := _cig_pose()
	_butt = {"p": m[0], "v": Vector2(randf_range(-10.0, 10.0), -14.0), "age": 0.0}
	if on_end.is_valid():
		on_end.call()


func _col() -> int:
	var tex: Texture2D = null
	if sprite is Sprite2D:
		tex = (sprite as Sprite2D).texture
	elif sprite is AnimatedSprite2D:
		var a := sprite as AnimatedSprite2D
		if a.sprite_frames and a.sprite_frames.has_animation(a.animation):
			tex = a.sprite_frames.get_frame_texture(a.animation, a.frame)
	if tex and tex.has_meta("cs_col"):
		return int(tex.get_meta("cs_col"))
	return 1


func _top_left() -> Vector2:
	var off: Vector2 = sprite.get("offset") if sprite and sprite.get("offset") != null else Vector2.ZERO
	var centered: bool = bool(sprite.get("centered")) if sprite else true
	return off - (Vector2(8, 8) if centered else Vector2.ZERO)


## Savukkeen asento: [filtterin pää, suunta (pää osoittaa tähän), näkyykö]
func _cig_pose() -> Array:
	var tl := _top_left()
	var col := _col()
	var mouth := Vector2(8.7, 7.5)
	var hand := Vector2(12.4, 11.6)
	var dm := Vector2(0.55, 0.85)
	var dh := Vector2(0.55, -0.55)
	match col:
		0:
			mouth = Vector2(4.4, 7.5)
			hand = Vector2(5.2, 11.4)
			dm = Vector2(-1.0, 0.18)
			dh = Vector2(-0.75, -0.65)
		3:
			mouth = Vector2(11.6, 7.5)
			hand = Vector2(10.8, 11.4)
			dm = Vector2(1.0, 0.18)
			dh = Vector2(0.75, -0.65)
		2:
			return [tl + Vector2(8.0, 6.0), Vector2(0, -1), false]
	var k := smoothstep(0.0, 1.0, _raise)
	return [tl + hand.lerp(mouth, k), dh.lerp(dm, k).normalized(), true]


func _mouth_pos() -> Vector2:
	var tl := _top_left()
	match _col():
		0:
			return tl + Vector2(4.4, 7.5)
		3:
			return tl + Vector2(11.6, 7.5)
		2:
			return tl + Vector2(8.0, 4.0)
	return tl + Vector2(8.7, 7.5)


func _process(delta: float) -> void:
	_t += delta
	if not is_instance_valid(sprite):
		queue_free()
		return
	if not sprite.is_visible_in_tree():
		return
	if not _ending:
		if not manual:
			# NPC: nostaa itse suulle välillä
			_auto_t -= delta
			if _auto_t <= 0.0:
				_want_mouth = not _want_mouth
				_auto_t = AUTO_DRAG if _want_mouth else AUTO_EVERY * randf_range(0.7, 1.4)
		_raise = move_toward(_raise, 1.0 if _want_mouth else 0.0, delta / RAISE_TIME)
		var at_mouth := _raise >= 0.95
		if at_mouth and _want_mouth:
			if _drag_time == 0.0 and on_drag.is_valid():
				on_drag.call()
			_drag_time += delta
			if manual:
				length -= delta / INHALE_BURN
				if on_inhale.is_valid():
					on_inhale.call(delta)
		elif not _want_mouth and _drag_time > 0.0:
			_exhale(_drag_time)
			_drag_time = 0.0
		if manual:
			length -= delta / PASSIVE_BURN
			if length <= 0.0:
				stop()
		# ohut savu palavasta päästä (henkosen aikana vähemmän)
		_wisp_t -= delta
		if _wisp_t <= 0.0:
			_wisp_t = 0.5 if (at_mouth and _want_mouth) else 0.18
			var pose := _cig_pose()
			var tip: Vector2 = (pose[0] as Vector2) + (pose[1] as Vector2) * _cig_len()
			_puffs.append({"p": tip, "v": Vector2(randf_range(-1.2, 1.2), -6.5), "age": 0.0, "max": 1.6, "r": 0.4})
	# savun liike
	var wind := Game.wind * 6.0
	for p: Dictionary in _puffs:
		p["age"] = float(p.age) + delta
		var v: Vector2 = p.v
		v.x = lerpf(v.x, wind, delta * 0.8)
		v.y = lerpf(v.y, -5.0, delta * 0.6)
		p["v"] = v
		p["p"] = (p.p as Vector2) + v * delta
	_puffs = _puffs.filter(func(p: Dictionary) -> bool: return float(p.age) < float(p.max))
	if not _butt.is_empty():
		_butt["age"] = float(_butt.age) + delta
		var bv: Vector2 = _butt.v
		bv.y += 60.0 * delta
		_butt["v"] = bv
		if float(_butt.age) < 0.45:
			_butt["p"] = (_butt.p as Vector2) + bv * delta
	if _ending and _puffs.is_empty() and (_butt.is_empty() or float(_butt.age) > 1.6):
		active = false
		queue_free()
		return
	queue_redraw()


## Uloshengitys: pitkä henkonen = iso pilvi
func _exhale(drag: float) -> void:
	var m := _mouth_pos()
	var col := _col()
	var dir := Vector2(0.35, 0.6)
	if col == 0:
		dir = Vector2(-1, 0.1)
	elif col == 3:
		dir = Vector2(1, 0.1)
	elif col == 2:
		dir = Vector2(0, -1)
	var n := clampi(int(2.0 + drag * 3.0), 2, 7)
	for k in n:
		var d := dir.rotated(randf_range(-0.45, 0.45))
		_puffs.append({"p": m, "v": d * randf_range(7.0, 13.0) + Vector2(0, -3.0), "age": 0.0,
			"max": randf_range(1.6, 2.6), "r": randf_range(0.9, 1.5) * (0.8 + minf(drag, 2.0) * 0.25)})


func _cig_len() -> float:
	return 1.3 + 2.4 * clampf(length, 0.0, 1.0)


func _draw() -> void:
	if not is_instance_valid(sprite):
		return
	# savu
	for p: Dictionary in _puffs:
		var k := float(p.age) / float(p.max)
		var r := float(p.r) + k * 3.2
		draw_circle(p.p, r, Color(0.86, 0.86, 0.9, 0.32 * (1.0 - k)))
	# poisheitetty tumppi
	if not _butt.is_empty():
		var bp: Vector2 = _butt.p
		var a := clampf(1.6 - float(_butt.age), 0.0, 1.0)
		draw_line(bp, bp + Vector2(1.0, 0.0), Color(0.85, 0.55, 0.25, a), 0.9)
		if float(_butt.age) < 0.6:
			draw_circle(bp + Vector2(1.2, 0), 0.5, Color(1.0, 0.5, 0.1, a))
	if _ending:
		return
	var pose := _cig_pose()
	if not bool(pose[2]):
		return
	var base: Vector2 = pose[0]
	var dir: Vector2 = pose[1]
	var L := _cig_len()
	var tip := base + dir * L
	var inhale := _raise >= 0.95 and _want_mouth
	# ääriviiva, filtteri, paperi, tuhka ja hehkuva pää
	draw_line(base - dir * 0.15, tip + dir * 0.15, Color(0.15, 0.12, 0.1, 0.55), 1.5)
	var f_end := base + dir * 0.9
	draw_line(base, f_end, Color(0.86, 0.55, 0.26), 1.0)
	draw_circle(base + dir * 0.45, 0.18, Color(0.65, 0.38, 0.18))
	draw_line(f_end, tip - dir * 0.35, Color(0.98, 0.97, 0.94), 1.0)
	draw_line(f_end, f_end + dir * 0.12, Color(0.95, 0.85, 0.4), 1.0)   # kultaraita
	draw_line(tip - dir * 0.35, tip, Color(0.55, 0.53, 0.52), 1.0)       # tuhka
	var glow := 1.0 if inhale else 0.45 + 0.15 * sin(_t * 7.0)
	draw_circle(tip, 0.55, Color(1.0, 0.3 + 0.35 * glow, 0.08))
	draw_circle(tip, 1.4 + 0.9 * glow, Color(1.0, 0.45, 0.12, 0.18 + 0.2 * glow))
