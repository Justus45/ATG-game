extends Node2D
## Auton tehosteet: pyörivät renkaat ja pakokaasu. Lisätään auton lapseksi.
##  - renkaat: pyöriminen tehdään auton OMAN tekstuurin renkaista. Skripti etsii kuvasta renkaat
##    (neutraalin harmaat pikselit auton alareunassa), ja piirtää renkaan pikselit samalla
##    pikseliruudukolla ja samoilla väreillä uudelleen: sivukuvassa kaksi kirkasta "mutteria"
##    kiertää navan ympäri (pehmeästi, värit häivytetään pikseliltä toiselle),
##    edestä/takaa kuvassa renkaan pinta vilkkuu. Ei erillistä tekstuuria päällä.
##    Jos kuvasta ei löydy renkaita, auto piirtyy sellaisenaan.
##  - tärinä: kun moottori on käynnissä, auton kuva väpättää pikkuisen (kovempaa kaasutettaessa)
##  - kuvaruudun ulkopuolella olevia autoja ei käsitellä lainkaan (suorituskyky)
##  - pakokaasu: tulee pakoputkesta auton takaa. Mitä enemmän kaasutetaan, sitä enemmän,
##    sitä paksumpaa ja sitä kauemmas savua tulee (kaasun "kierrokset" nousevat pohjassa pidettäessä)
##  - pelaajan auto (Car2D, is_driving): kaasu = WASD/nuolinäppäinten voimakkuus; tyhjäkäynnillä pieniä puuskia
##  - muut autot (liikenne, poliisi): kaasu päätellään nopeudesta, ei seisovilla/pysäköidyillä

# --- Säädettävät arvot ---
const RING_STEP_LEN := 1.96        ## matka (px), jonka verran rengas kääntyy yhden pikselin verran (pyörän ympärys 15.7 px / 8)
const MAX_STEP_PER_FRAME := 0.55   ## nopeammin ei pyöritetä kuvaa (muuten välkkyy), vaan renkaasta tulee "sumea"
const TREAD_PERIOD := 6.0          ## matka (px), jonka aikana edestä kuvatun renkaan pinta vilkkuu kerran
const LUG_STRENGTH := 0.75         ## kuinka kirkkaita pyörivät mutterit ovat
const IDLE_RATE := 5.0             ## pakokaasupuuskia sekunnissa tyhjäkäynnillä
const FULL_RATE := 55.0            ## ... täydellä kaasulla
const REV_UP := 1.6                ## kuinka nopeasti kierrokset nousevat (1/s)
const REV_DOWN := 2.2              ## ... ja laskevat
const BURST_COUNT := 8             ## lisäpuuska kun kaasu painetaan pohjaan paikaltaan
const MAX_PARTICLES := 70
const CULL_DISTANCE := 480.0       ## tätä kauempana kamerasta olevia autoja ei käsitellä
const SHAKE_IDLE := 0.0            ## tärinän voimakkuus (px) tyhjäkäynnillä
const SHAKE_FULL := 0.0            ## ... täydellä kaasulla
const SHAKE_HZ := 40.0             ## kuinka usein tärinän suunta vaihtuu
const SHAKE_NPC := 0.25            ## muiden kuin pelaajan autojen tärinä

var _spr: Node2D
var _last_pos := Vector2.ZERO
var _speed := 0.0
var _dist := 0.0
var _wheel_phase := 0.0            ## 0..8: mutterin paikka navan ympärillä (pikseliä)
var _blur := 0.0                   ## 0..1: nopeassa ajossa rengas muuttuu tasaiseksi
var _fade := 0.0                   ## 0..1: efekti häivytetään pois paikallaan seistessä
var _drawn_fade := 0.0
var _shake := Vector2.ZERO
var _shake_tick := -1
var _shake_time := 0.0
var _rev := 0.0
var _prev_throttle := 0.0
var _emit_acc := 0.0
var _facing := Vector2i.RIGHT
var _particles: Array[Dictionary] = []

## Navan ympärillä olevat 8 pikseliä myötäpäivään (alkaa vasemmasta yläkulmasta)
const RING := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]

## Tekstuurin analyysi kerran per tekstuuri: {"round": [...], "tread": [...]}
static var _analysis_cache := {}


func _ready() -> void:
	_last_pos = global_position


func _find_sprite() -> Node2D:
	for c in get_parent().get_children():
		if c is AnimatedSprite2D or c is Sprite2D:
			return c
	return null


func _tex_size() -> Vector2:
	var tex: Texture2D = null
	if _spr is AnimatedSprite2D:
		var frames := (_spr as AnimatedSprite2D).sprite_frames
		if frames:
			tex = frames.get_frame_texture((_spr as AnimatedSprite2D).animation, (_spr as AnimatedSprite2D).frame)
	elif _spr is Sprite2D:
		tex = (_spr as Sprite2D).texture
	return Vector2(tex.get_size()) if tex else Vector2.ZERO


func _sprite_center() -> Vector2:
	var off := Vector2.ZERO
	if "offset" in _spr:
		off = _spr.offset
	return _spr.position + off


func _update_facing() -> void:
	if _spr is AnimatedSprite2D:
		var n := String((_spr as AnimatedSprite2D).animation)
		if n.ends_with("left"):
			_facing = Vector2i.LEFT
		elif n.ends_with("right"):
			_facing = Vector2i.RIGHT
		elif n.ends_with("up"):
			_facing = Vector2i.UP
		elif n.ends_with("down"):
			_facing = Vector2i.DOWN
		return
	var p := get_parent()
	if "dir" in p and p.dir is Vector2i:
		_facing = p.dir


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	if _spr == null or not is_instance_valid(_spr):
		_spr = _find_sprite()
		if _spr == null:
			return
	_update_facing()

	# Kuvaruudun ulkopuolella: ei tehdä mitään (nollataan tila, jotta paluu on siisti)
	var cam := get_viewport().get_camera_2d()
	if cam and cam.global_position.distance_to(global_position) > CULL_DISTANCE:
		_last_pos = global_position
		_speed = 0.0
		_rev = 0.0
		if not _particles.is_empty():
			_particles.clear()
			queue_redraw()
		if _spr.position != Vector2.ZERO:
			_spr.position = Vector2.ZERO
		return

	# Nopeus todellisesta liikkeestä (teleportit ohitetaan)
	var moved := global_position - _last_pos
	_last_pos = global_position
	var inst := moved.length() / delta if moved.length() < 40.0 else 0.0
	_speed = lerpf(_speed, inst, 0.35)
	if _speed < 0.5:
		_speed = 0.0   # ettei häntä jää loputtomasti piirtämään
	_dist += _speed * delta
	var step_per_frame := _speed * delta / RING_STEP_LEN
	var spin_dir := -1.0 if _facing == Vector2i.LEFT else 1.0
	_blur = clampf((step_per_frame - MAX_STEP_PER_FRAME) / 0.8, 0.0, 1.0)
	_wheel_phase = fposmod(_wheel_phase + spin_dir * minf(step_per_frame, MAX_STEP_PER_FRAME), 8.0)
	_fade = clampf(_speed / 25.0, 0.0, 1.0)

	# Kaasu ja moottorin tila
	var p := get_parent()
	var throttle := 0.0
	var engine_on := false
	if "is_driving" in p:
		engine_on = p.is_driving
		if engine_on:
			throttle = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down").length()
	else:
		engine_on = _speed > 5.0 and not ("dead" in p and p.dead)
		throttle = clampf(_speed / 220.0, 0.0, 1.0) * 0.6

	# Tärinä: moottorin käydessä kuva väpättää (pelaajan auto voimakkaammin, kaasun mukaan)
	if engine_on:
		var amp := SHAKE_NPC
		if "is_driving" in p:
			amp = lerpf(SHAKE_IDLE, SHAKE_FULL, _rev)
		_shake_time += delta
		var tick := int(_shake_time * SHAKE_HZ)
		if tick != _shake_tick:
			_shake_tick = tick
			_shake = Vector2(randf_range(-1.0, 1.0) * amp * 0.6, randf_range(-1.0, 1.0) * amp)
		_spr.position = _shake
	elif _spr.position != Vector2.ZERO:
		_spr.position = Vector2.ZERO

	# Kierrokset: nousevat nopeasti kaasutettaessa, laskevat hitaammin
	_rev = move_toward(_rev, throttle, (REV_UP if throttle > _rev else REV_DOWN) * delta)

	# Pakokaasun päästö
	if engine_on:
		_emit_acc += lerpf(IDLE_RATE, FULL_RATE, _rev) * delta
		if throttle > 0.6 and _prev_throttle < 0.2:
			_emit_acc += BURST_COUNT   # kaasutus paikaltaan: iso puuska
		while _emit_acc >= 1.0:
			_emit_acc -= 1.0
			_spawn_puff()
	else:
		_emit_acc = 0.0
	_prev_throttle = throttle

	# Hiukkasten päivitys
	var i := _particles.size() - 1
	while i >= 0:
		var pt := _particles[i]
		pt.age += delta
		if pt.age >= pt.life:
			_particles.remove_at(i)
		else:
			pt.pos += pt.vel * delta
			pt.vel *= maxf(0.0, 1.0 - 2.2 * delta)
		i -= 1

	if _fade > 0.0 or _drawn_fade > 0.0 or not _particles.is_empty() or engine_on:
		queue_redraw()


## Pakoputken paikka auton paikallisissa koordinaateissa (auton takapää, matalalla).
func _exhaust_local(size: Vector2, center: Vector2) -> Vector2:
	var f := Vector2(_facing)
	if size.x > size.y:
		# sivukuva: putki takapään alareunassa
		return center + Vector2(-f.x * (size.x * 0.5 - 0.5), size.y * 0.5 - 3.5)
	if _facing == Vector2i.UP:
		# takaa katsottuna: putki auton alareunassa, hieman sivussa
		return center + Vector2(4.0, size.y * 0.5 - 2.0)
	# edestä katsottuna: pakokaasu tulee auton takaa (kuvassa ylhäältä)
	return center + Vector2(4.0, -size.y * 0.5 + 3.0)


func _spawn_puff() -> void:
	if _particles.size() >= MAX_PARTICLES:
		return
	var size := _tex_size()
	if size == Vector2.ZERO:
		return
	var rear := -Vector2(_facing)
	if size.x <= size.y:
		# edestä/takaa katsottaessa savu leviää ylös tai alas kuvassa
		rear = Vector2(0.0, -1.0) if _facing == Vector2i.DOWN else Vector2(0.0, 1.0)
	var r := _rev
	var tone := Color(0.82, 0.83, 0.86).lerp(Color(0.36, 0.36, 0.4), r)
	_particles.append({
		"pos": to_global(_exhaust_local(size, _sprite_center())),
		"vel": rear * (6.0 + r * 30.0) + Vector2(randf_range(-5.0, 5.0), -6.0 - r * 8.0 + randf_range(-3.0, 3.0)),
		"age": 0.0,
		"life": 0.35 + r * 0.55 + randf() * 0.15,
		"s0": 1.1 + r * 1.6,
		"s1": 3.0 + r * 5.0,
		"a0": 0.28 + r * 0.45,
		"col": tone,
	})


func _draw() -> void:
	if _spr == null or not is_instance_valid(_spr):
		return
	var size := _tex_size()
	if size == Vector2.ZERO:
		return
	var center := _sprite_center()

	# --- Renkaat: auton oman tekstuurin renkaat uudelleen piirrettynä pikselitarkasti ---
	_drawn_fade = _fade
	# kuva kääntymässä (Car2D:n pehmeä käännös): renkaiden pikselit eivät osuisi kohdalleen
	var rot_ok := absf(_spr.rotation) < 0.05
	if _fade > 0.02 and rot_ok:
		var an := _analysis(_current_texture())
		var top_left := center - size * 0.5   # sama kohta kuin spriten vasen yläkulma
		var fl := _fade
		for wh: Dictionary in an.round:
			var lug: Color = wh.lug
			for j in 8:
				var base: Color = wh.base[j]
				var col := base.lerp(lug, _lug_amount(j) * LUG_STRENGTH * fl)
				draw_rect(Rect2(top_left + Vector2(wh.hub + RING[j]), Vector2.ONE), col)
		var side := 0
		for px_list: Array in an.tread:
			for k in px_list.size():
				var e: Dictionary = px_list[k]
				var base2: Color = e.base
				var osc := 0.5 + 0.5 * sin(_dist * TAU / TREAD_PERIOD + float(k) * PI + float(side) * 0.5)
				osc = lerpf(osc, 0.5, _blur)
				var col2 := base2.lerp(base2.lightened(0.5), osc * 0.9 * fl)
				draw_rect(Rect2(top_left + Vector2(e.p), Vector2.ONE), col2)
			side += 1

	# --- Pakokaasu ---
	for pt in _particles:
		var t: float = pt.age / pt.life
		var rad: float = lerpf(pt.s0, pt.s1, t)
		var col: Color = pt.col
		col.a = pt.a0 * (1.0 - t)
		draw_circle(to_local(pt.pos), rad, col)


## Mutterin kirkkaus navan ympärillä olevalla pikselillä j. Kaksi vastakkaista mutteria, jotka
## kiertävät pehmeästi (kirkkaus jakautuu kahden vierekkäisen pikselin kesken).
func _lug_amount(j: int) -> float:
	var d1 := absf(float(j) - _wheel_phase)
	d1 = minf(d1, 8.0 - d1)
	var d2 := absf(float(j) - fposmod(_wheel_phase + 4.0, 8.0))
	d2 = minf(d2, 8.0 - d2)
	var a := clampf(1.0 - d1, 0.0, 1.0) + clampf(1.0 - d2, 0.0, 1.0)
	return lerpf(a, 0.4, _blur)


func _current_texture() -> Texture2D:
	if _spr is AnimatedSprite2D:
		var asp := _spr as AnimatedSprite2D
		if asp.sprite_frames:
			return asp.sprite_frames.get_frame_texture(asp.animation, asp.frame)
	elif _spr is Sprite2D:
		return (_spr as Sprite2D).texture
	return null


static func _is_tire(c: Color) -> bool:
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	return c.a > 0.5 and mx - mn < 0.07 and mx < 0.85


func _analysis(tex: Texture2D) -> Dictionary:
	if tex == null:
		return {"round": [], "tread": []}
	var key := tex.get_instance_id()
	if not _analysis_cache.has(key):
		_analysis_cache[key] = _analyze(tex)
	return _analysis_cache[key]


## Etsii auton kuvasta renkaat: neutraalin harmaita pikseliryhmiä kuvan alareunasta.
##  - ryhmä, jossa on kirkas napa (sivukuva): "round", napa + sitä ympäröivät 8 pikseliä
##  - pieni ryhmä auton reunassa (edestä/takaa kuva): "tread", renkaan näkyvät pikselit
func _analyze(tex: Texture2D) -> Dictionary:
	var out := {"round": [], "tread": []}
	# HD-kuvilla (HDTex) renkaat etsitään alkuperäisestä 1x-kuvasta: efekti piirretään
	# maailman pikseleinä, jotka vastaavat 1x-kuvan pikseleitä.
	var img: Image = (tex.get_meta("lo_image") as Image).duplicate() if tex.has_meta("lo_image") else tex.get_image()
	if img == null or img.is_empty():
		return out
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var seen := {}
	for y in range(maxi(0, h - 5), h):
		for x in w:
			var start := Vector2i(x, y)
			if seen.has(start) or not _is_tire(img.get_pixelv(start)):
				continue
			var blob: Array[Vector2i] = []
			var stack: Array[Vector2i] = [start]
			seen[start] = true
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				blob.append(c)
				for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var n := c + d
					if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h or seen.has(n):
						continue
					if _is_tire(img.get_pixelv(n)):
						seen[n] = true
						stack.append(n)
			if blob.size() > 24:
				continue
			var hub := Vector2i(-1, -1)
			var best := 0.0
			for c in blob:
				var col := img.get_pixelv(c)
				var l := (col.r + col.g + col.b) / 3.0
				if l > best:
					best = l
					hub = c
			if best > 0.6 and hub.x >= 1 and hub.y >= 1 and hub.x < w - 1 and hub.y < h - 1:
				var ring: Array[Color] = []
				for o: Vector2i in RING:
					ring.append(img.get_pixelv(hub + o))
				out.round.append({"hub": hub, "base": ring, "lug": img.get_pixelv(hub)})
			elif blob.size() >= 2 and blob.size() <= 6:
				# etu-/takarengas näkyy vain auton sivuilla
				var cx := 0.0
				for c in blob:
					cx += float(c.x)
				cx /= float(blob.size())
				if cx < float(w) * 0.25 or cx > float(w) * 0.75:
					var px_list: Array = []
					for c in blob:
						px_list.append({"p": c, "base": img.get_pixelv(c)})
					out.tread.append(px_list)
	return out
