extends Node
## Ajoneuvojen törmäykset. Game liittää tämän kenttään.
##
## Liikenne, poliisiautot ja jalankulkijat liikkuvat koodilla (Node2D), eivät fysiikalla,
## joten osumat tarkistetaan tässä suorakulmioilla joka fysiikkatikillä:
##   - pelaajan auto osuu jalankulkijaan (ohikulkija, poliisi, roisto):
##       kovaa -> hahmo lentää ilmaan pyörien ja kuolee laskeutuessaan (henkirikos)
##       hiljaa -> hahmo tönäistään sivuun
##   - liikenne- tai poliisiauto osuu jalan kulkevaan pelaajaan -> pelaaja lentää (Player2D.hit_by_car)
##   - pelaajan auto törmää liikenne- tai poliisiautoon -> kolari: auto kimpoaa, vaurioituu,
##     toinen auto nytkähtää ja pysähtyy hetkeksi, kuljettaja tööttää
##   - liikenneauto ei aja pelaajan (tai pysäköidyn) auton läpi: se jarruttaa, tööttää
##     ja kääntyy lopulta takaisin (car_blocked, kaupungin Mover kysyy)
## Pelaajan auto <-> seinät / toiset pelaajan autot hoidetaan Car2D:ssä (move_and_slide).

# --- SÄÄDÄ NÄITÄ ---
const PED_LAUNCH_SPEED := 60.0     ## tätä kovempaa (px/s) ajettu jalankulkija lentää ilmaan
const PED_PUSH_SPEED := 6.0        ## hitaampi kosketus ei tee mitään
const HIT_PLAYER_SPEED := 45.0     ## liikenne-/poliisiauto heittää pelaajan tätä kovemmasta vauhdista
const CAR_CRASH_SPEED := 50.0      ## suhteellinen nopeus, josta autojen kosketus on kolari
const PED_SIZE := Vector2(8, 10)   ## jalankulkijan osumalaatikko (vartalon keskipisteen ympärillä)
const AI_STOP_AFTER_CRASH := 2.5   ## kolariin joutunut liikenneauto seisoo näin kauan (s)

# --- Jalankulkijan väistö. SÄÄDÄ NÄITÄ ---
## Hahmo huomaa kohti tulevan auton, kun törmäykseen on alle DODGE_LOOKAHEAD sekuntia, ja
## hyppää sivuun reaktioajan jälkeen. Kova vauhti = vähemmän aikaa = useampi jää alle.
const DODGE_MIN_SPEED := 50.0      ## hitaampaa autoa ei väistetä (se vain tönäisee)
const DODGE_LOOKAHEAD := 0.75      ## kuinka aikaisin vaara huomataan (s ennen osumaa)
const DODGE_REACT_MIN := 0.1       ## nopein reaktioaika (s)
const DODGE_REACT_MAX := 0.65      ## hitain reaktioaika (s)
const DODGE_OBLIVIOUS := 0.15      ## todennäköisyys, ettei hahmo huomaa autoa lainkaan (puhelin, ajatuksissaan)
const DODGE_TIME := 0.2            ## hypyn kesto (s); auto voi osua kesken hypyn
const DODGE_MARGIN := 6.0          ## kuinka kauas auton reunasta hypätään (px)
const DODGE_MAX_DIST := 30.0       ## pidempää hyppyä ei yritetä (auton keskellä seisova ei ehdi)

var _city: Node
var _player: Node2D
var _flying := {}      # jalankulkija -> true (ilmassa, ei osumia)
var _holds := {}       # AI-auto -> sekunteja jäljellä (pysähtynyt kolarin jälkeen)
## Poliisiauto, joka ei jahtaa pelaajaa ja ajoi tämän yli: seisoo ja odottaa, kunnes pelaaja
## on väistänyt (auto -> sekunteja, jotka pelaaja on ollut poissa edestä)
var _yield := {}
const YIELD_DIST := 52.0       ## näin lähellä oleva pelaaja pitää auton paikallaan (px)
const YIELD_CLEAR := 1.2       ## pelaajan pitää olla poissa näin kauan, ennen kuin auto jatkaa (s)
var _cool := {}        # "a_b" -> sekunteja (ettei samasta kosketuksesta tule monta kolaria)
var _last := {}        # AI-auto -> edellinen sijainti
var _vel := {}         # AI-auto -> pehmennetty nopeus
var _threat := {}      # jalankulkija -> {"t": reaktioaikaa jäljellä, "car": auto}
var _dodge_cd := {}    # jalankulkija -> s (ei uutta väistöä / huomaamista heti perään)
var _dodging := {}     # jalankulkija -> {"tw": Tween, "spr": kuva, "base": kuvan paikka, "proc": bool, "phys": bool}
const BLOOD := preload("res://scripts/core/Blood.gd")


func _ready() -> void:
	add_to_group("impacts")
	process_physics_priority = 10   # autojen liikkumisen jälkeen
	var scene := get_tree().current_scene
	_city = scene.get_node_or_null("City")
	_player = scene.get_node_or_null("Player") as Node2D


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if _city == null or not is_instance_valid(_city):
		return
	var others := _ai_cars(delta)
	# optimointi: jalankulkijalista kerätään vasta kun jokin pelaajan auto liikkuu
	var peds: Array[Dictionary] = []
	var peds_ready := false

	# 1. Pelaajan autot (ajettava tai tönäisty pysäköity auto)
	for c in get_tree().get_nodes_in_group("player_vehicles"):
		if not is_instance_valid(c) or not c.has_method("hit_rect") or not c.is_inside_tree():
			continue
		var r: Rect2 = c.hit_rect()
		var v: Vector2 = c.velocity
		var spd := v.length()
		var by_player: bool = c.is_driving
		if (spd > DODGE_MIN_SPEED or spd > PED_PUSH_SPEED) and not peds_ready:
			peds = _peds()
			peds_ready = true
		if spd > DODGE_MIN_SPEED:
			_spot_threats(c, r, v, spd, peds)
		if spd > PED_PUSH_SPEED:
			for p: Dictionary in peds:
				var pn: Node2D = p.n
				if _flying.has(pn) or not r.grow(1.0).intersects(p.rect):
					continue
				if spd >= PED_LAUNCH_SPEED:
					_launch(pn, v, by_player)
				else:
					_shove(pn, r, p.rect)
		for o: Dictionary in others:
			if r.intersects(o.rect):
				_car_vs_ai(c, o)
				r = c.hit_rect()

	_update_dodges(delta)

	# 2. Liikenne- ja poliisiautot osuvat jalan kulkevaan pelaajaan
	if is_instance_valid(_player) and _player.visible and _player.has_method("hit_by_car"):
		var center: Vector2 = _player.body_center()
		var pr := Rect2(center - PED_SIZE * 0.5 + Vector2(0, 1), PED_SIZE)
		for o: Dictionary in others:
			var ov: Vector2 = o.vel
			if ov.length() < HIT_PLAYER_SPEED or not o.rect.intersects(pr):
				continue
			# Puhalluskokeeseen ajava partio ei aja pelaajan päälle
			var mode = o.n.get("mode")
			if o.police and mode != null and (int(mode) == 1 or int(mode) == 2):
				continue
			var chasing: bool = o.police and _police_chasing(o.n)
			if o.police and not chasing and _yield.has(o.n):
				continue
			if _player.hit_by_car(ov, o.n):
				_hold(o.n, 0.6 if o.police else 1.8)
				if o.police and not chasing:
					_yield[o.n] = 0.0
					_honk(o.n, ["Hups! Väistä, väistä.", "Pois tieltä, kansalainen!", "Katso eteesi!"][randi() % 3], -8.0)
				if not o.police:
					_honk(o.n, ["Katso eteesi!", "Mitä sä teet tiellä?!", "Hups!"][randi() % 3])

	_update_yields(delta)

	# 3. Jalan kulkeva pelaaja ei kävele liikenne- eikä poliisiautojen läpi (ne eivät ole
	#    fysiikkakappaleita): pelaaja työnnetään auton laatikon ulkopuolelle.
	if is_instance_valid(_player) and _player.visible and _player is CharacterBody2D and _player.is_physics_processing():
		for o: Dictionary in others:
			_push_player_out(o.rect)


# ----------------------------------------------------------------------------
#  LIIKENNE: JARRUTUS PELAAJAN AUTON TAKANA
# ----------------------------------------------------------------------------
## Onko liikenneauton edessä pelaajan (tai pysäköity) auto? Kaupungin Mover kysyy tätä.
func car_blocked(m: Node2D) -> bool:
	var spr := _visual(m) as Sprite2D
	if spr == null:
		return false
	var r := _sprite_rect(m, spr)
	if r.size == Vector2.ZERO:
		return false
	var dv: Vector2i = m.get("dir")
	var d := Vector2(dv)
	var look := 7.0
	var front: Rect2
	if d.x > 0.0:
		front = Rect2(r.end.x, r.position.y + 2.0, look, r.size.y - 4.0)
	elif d.x < 0.0:
		front = Rect2(r.position.x - look, r.position.y + 2.0, look, r.size.y - 4.0)
	elif d.y > 0.0:
		front = Rect2(r.position.x + 2.0, r.end.y, r.size.x - 4.0, look)
	else:
		front = Rect2(r.position.x + 2.0, r.position.y - look, r.size.x - 4.0, look)
	for c in get_tree().get_nodes_in_group("player_vehicles"):
		if is_instance_valid(c) and c.has_method("hit_rect") and front.intersects(c.hit_rect()):
			return true
	return false


# ----------------------------------------------------------------------------
#  KERÄYS
# ----------------------------------------------------------------------------
## Työntää jalan kulkevan pelaajan (jalkojen laatikko) ulos auton laatikosta lyhintä reittiä.
func _push_player_out(car: Rect2) -> void:
	var feet := Rect2(_player.global_position + Vector2(-4.0, 1.0), Vector2(8.0, 6.0))
	var ox := minf(feet.end.x, car.end.x) - maxf(feet.position.x, car.position.x)
	var oy := minf(feet.end.y, car.end.y) - maxf(feet.position.y, car.position.y)
	if ox <= 0.0 or oy <= 0.0:
		return
	var fc := feet.get_center()
	var cc := car.get_center()
	var push := Vector2.ZERO
	if ox < oy:
		push = Vector2((ox + 0.1) * (1.0 if fc.x >= cc.x else -1.0), 0.0)
	else:
		push = Vector2(0.0, (oy + 0.1) * (1.0 if fc.y >= cc.y else -1.0))
	(_player as CharacterBody2D).move_and_collide(push)


## Liikenne- ja poliisiautot: [{n, rect, vel, police}]
func _ai_cars(delta: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ents: Node = _city.get("entities")
	if ents:
		for m in ents.get_children():
			if Game.flag(m, "is_car") and m.is_inside_tree():
				_add_ai(out, m, false, delta)
	var pm := get_tree().get_first_node_in_group("police_manager")
	if pm and "cars" in pm:
		for c in pm.cars:
			_add_ai(out, c, true, delta)
	var patrol := get_tree().get_first_node_in_group("police_patrol")
	if patrol and "patrols" in patrol:
		for c in patrol.patrols:
			_add_ai(out, c, true, delta)
	# Tuhoutuneet poliisiautot (eivät enää poliisin listoilla, mutta ovat yhä esteitä)
	for c in get_tree().get_nodes_in_group("police_wrecks"):
		_add_ai(out, c, true, delta, true)
	return out


## obj on tyypittämätön: poliisin listoilla voi olla jo vapautettu auto, ja tyypitetty
## parametri kaatuisi siihen ennen kuin is_instance_valid ehtii tarkistaa.
func _add_ai(out: Array[Dictionary], obj: Variant, police: bool, delta: float, wreck: bool = false) -> void:
	if not is_instance_valid(obj) or not (obj is Node2D):
		return
	var n: Node = obj
	if Game.flag(n, "dead") and not wreck:
		return
	var spr := _visual(n) as Sprite2D
	if spr == null or spr.texture == null:
		return
	var n2 := n as Node2D
	var pos := n2.global_position
	# Nopeus sijainnin muutoksesta (autot liikkuvat _process:ssa, eri tahdissa kuin fysiikka)
	var inst := Vector2.ZERO
	if _last.has(n) and not _holds.has(n):
		var moved: Vector2 = pos - _last[n]
		if moved.length() < 40.0:    # isompi hyppy = siirto/teleporttaus, ei vauhtia
			inst = moved / maxf(delta, 0.0001)
	_last[n] = pos
	var prev_v: Vector2 = _vel.get(n, Vector2.ZERO)
	var v := prev_v.lerp(inst, 0.5)
	_vel[n] = v
	out.append({"n": n2, "rect": _sprite_rect(n2, spr), "vel": v, "police": police})


## Jalankulkijat: kaikki ammuttavat hahmot (ohikulkijat, poliisit, roistot).
func _peds() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in get_tree().get_nodes_in_group("shootable"):
		if not (n is Node2D) or not is_instance_valid(n) or n == _player:
			continue
		if Game.flag(n, "is_car") or Game.flag(n, "dead") or not n.has_method("hit_point"):
			continue
		if not (n as Node2D).is_visible_in_tree():
			continue
		var c: Vector2 = n.hit_point()
		out.append({"n": n, "rect": Rect2(c - PED_SIZE * 0.5 + Vector2(0, 1), PED_SIZE)})
	return out


## Auton kuvan (Sprite2D, keskitetty) laatikko maailmassa, hieman kuvaa pienempänä.
func _sprite_rect(n: Node2D, spr: Sprite2D) -> Rect2:
	if spr.texture == null:
		return Rect2()
	var sz := spr.texture.get_size()
	var center := n.global_position + spr.offset   # ei spr.position: CarFX täristää sitä
	var r := Rect2(center - sz * 0.5, sz)
	# ääriviiva pois reunoilta, katon perspektiivi yläreunasta
	return r.grow_individual(-1.0, -3.0, -1.0, -1.0)


func _visual(n: Node) -> Node2D:
	for key in ["visual", "sprite", "animated_sprite"]:
		var v = n.get(key)
		if v is Node2D and is_instance_valid(v):
			return v
	for ch in n.get_children():
		if ch is Sprite2D or ch is AnimatedSprite2D:
			return ch
	return null


# ----------------------------------------------------------------------------
#  KOLARI: PELAAJAN AUTO <-> LIIKENNE / POLIISI
# ----------------------------------------------------------------------------
func _car_vs_ai(c: Node, o: Dictionary) -> void:
	var r: Rect2 = c.hit_rect()
	var orr: Rect2 = o.rect
	var ox := minf(r.end.x, orr.end.x) - maxf(r.position.x, orr.position.x)
	var oy := minf(r.end.y, orr.end.y) - maxf(r.position.y, orr.position.y)
	if ox <= 0.0 or oy <= 0.0:
		return
	var rc := r.get_center()
	var oc := orr.get_center()
	var n := Vector2.ZERO
	var depth := 0.0
	if ox < oy:
		n = Vector2(1.0 if rc.x >= oc.x else -1.0, 0.0)
		depth = ox
	else:
		n = Vector2(0.0, 1.0 if rc.y >= oc.y else -1.0)
		depth = oy
	var ov: Vector2 = o.vel
	var cv: Vector2 = c.velocity
	var impact := -(cv - ov).dot(n)
	# AI-autot eivät ole fysiikkakappaleita: pelaajan auto työnnetään ulos niiden sisältä
	(c as CharacterBody2D).move_and_collide(n * (depth + 0.2))
	var on: Node2D = o.n
	var key := "%d_%d" % [c.get_instance_id(), on.get_instance_id()]
	if impact < CAR_CRASH_SPEED or _cool.has(key):
		return
	_cool[key] = 0.6
	c.crash(impact, n, on)
	if not c.is_driving and c.has_method("apply_knock"):
		c.apply_knock(ov * 0.4, impact)
	_jolt(o, -n, impact)
	# Liikenne- ja poliisiauto vaurioituu kolarissa (voi syttyä palamaan ja räjähtää)
	if on.has_method("take_hit"):
		on.take_hit((impact - CAR_CRASH_SPEED) * 0.12 + 2.0, c.is_driving)
	# Vahingossa poliisiautoon törmääminen ei aloita jahtia (vasta auton räjäyttäminen, PoliceCar).
	# Jo käynnissä olevassa jahdissa poliisiauton rammaaminen kuitenkin kiristää jahtia.
	if o.police and c.is_driving and cv.dot(-n) > ov.dot(n) and impact > CAR_CRASH_SPEED * 1.5:
		var pm := get_tree().get_first_node_in_group("police_manager")
		if pm and int(pm.get("wanted")) > 0 and pm.has_method("report_crime"):
			pm.report_crime(1)


## Toinen auto nytkähtää ja pysähtyy hetkeksi; liikenteen kuski tööttää.
func _jolt(o: Dictionary, dir: Vector2, impact: float) -> void:
	var on: Node2D = o.n
	var hard := clampf((impact - CAR_CRASH_SPEED) / 200.0, 0.0, 1.0)
	_hold(on, lerpf(0.6, 1.2, hard) if o.police else lerpf(1.2, AI_STOP_AFTER_CRASH, hard))
	var spr := _visual(on)
	if spr:
		var side := 1.0 if (dir.x + dir.y) >= 0.0 else -1.0
		var tw := create_tween()
		tw.tween_property(spr, "rotation", 0.18 * side * (0.4 + hard), 0.05)
		tw.tween_property(spr, "rotation", 0.0, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if not o.police:
		_honk(on, ["Hei!!", "Mun auto!", "Opettele ajamaan!", "Mitä helvettiä?!"][randi() % 4], 0.35)


# ----------------------------------------------------------------------------
#  JALANKULKIJAT
# ----------------------------------------------------------------------------
## Hahmo lentää ilmaan pyörien ja kuolee laskeutuessaan.
func _launch(p: Node2D, vel: Vector2, by_player: bool) -> void:
	_cancel_dodge(p)
	_flying[p] = true
	var spd := vel.length()
	var k := clampf((spd - PED_LAUNCH_SPEED) / 240.0, 0.0, 1.0)
	var dir := vel.normalized().rotated(randf_range(-0.45, 0.45))
	var start := p.global_position
	var end := _landing(start, dir, lerpf(26.0, 100.0, k))
	var spr := _visual(p)
	var base_pos := spr.position if spr else Vector2.ZERO
	var h := lerpf(8.0, 28.0, k)
	var spin := TAU * lerpf(1.0, 3.0, k) * (1.0 if randf() < 0.5 else -1.0)
	var dur := lerpf(0.4, 0.8, k)
	p.set_process(false)   # tekoäly ei liikuta hahmoa lennon aikana
	var hp: Vector2 = p.hit_point()
	BLOOD.spray(p, hp, vel, 7)
	Sfx.play("thud", hp, 2.0, 0.08)
	Sfx.play("punch_hit", hp, 0.0, 0.08, 0.6)
	# alle jäänyt huutaa: kova vauhti = kiljaisu, hiljainen = ähkäisy
	Sfx.play("scream" if k > 0.35 else "oof", hp, -1.0, 0.0, randf_range(0.8, 1.25))
	_impact_star(hp)
	if by_player:
		var cam := get_viewport().get_camera_2d()
		if cam and cam.has_method("shake"):
			cam.shake(lerpf(1.5, 4.0, k))
	var tw := create_tween()
	tw.tween_method(_fly_step.bind(p, spr, start, end, base_pos, h, spin), 0.0, 1.0, dur)
	tw.tween_callback(_land.bind(p, spr, base_pos, by_player))


func _fly_step(t: float, p, spr, start: Vector2, end: Vector2, base_pos: Vector2, h: float, spin: float) -> void:
	if not is_instance_valid(p):
		return
	p.global_position = start.lerp(end, 1.0 - (1.0 - t) * (1.0 - t))
	if is_instance_valid(spr):
		spr.position = base_pos + Vector2(0.0, -sin(t * PI) * h)
		spr.rotation = spin * t


func _land(p, spr, base_pos: Vector2, by_player: bool) -> void:
	_flying.erase(p)
	if not is_instance_valid(p):
		return
	if is_instance_valid(spr):
		spr.position = base_pos
		spr.rotation = 0.0
	if not Game.flag(p, "dead"):
		p.set_process(true)
	Sfx.play("thud", p.global_position, -2.0, 0.1, 0.85)
	if p.has_method("take_damage"):
		# Pelaajan ajama: henkirikos (take_damage hoitaa todistajat ja etsintäkuulutuksen)
		p.take_damage(99, _player if by_player else null)


## Lentoradan loppupiste: ei talon tai veden sisään.
func _landing(start: Vector2, dir: Vector2, dist: float) -> Vector2:
	var last := start
	var d := 4.0
	while d <= dist:
		var pt := start + dir * d
		if _city.has_method("is_walkable") and not _city.is_walkable(_city.world_to_cell(pt)):
			break
		last = pt
		d += 4.0
	return last


## Hidas kosketus: hahmo väistyy auton tieltä.
func _shove(p: Node2D, car: Rect2, pr: Rect2) -> void:
	var away := pr.get_center() - car.get_center()
	if away == Vector2.ZERO:
		away = Vector2.DOWN
	var to := p.global_position + away.normalized() * 1.5
	if not _city.has_method("is_walkable") or _city.is_walkable(_city.world_to_cell(to)):
		p.global_position = to


# ----------------------------------------------------------------------------
#  JALANKULKIJAN VÄISTÖ
# ----------------------------------------------------------------------------
## Auton (laatikko r, nopeus v) edessä olevat hahmot huomaavat vaaran ja saavat reaktioajan.
func _spot_threats(car: Node, r: Rect2, v: Vector2, spd: float, peds: Array[Dictionary]) -> void:
	var fwd := v / spd
	var perp := Vector2(-fwd.y, fwd.x)
	var cc := r.get_center()
	var half_len := (absf(fwd.x) * r.size.x + absf(fwd.y) * r.size.y) * 0.5
	var half_w := (absf(perp.x) * r.size.x + absf(perp.y) * r.size.y) * 0.5
	var reach := half_len + spd * DODGE_LOOKAHEAD
	for p: Dictionary in peds:
		var pn: Node2D = p.n
		if _flying.has(pn) or _dodging.has(pn) or _threat.has(pn) or _dodge_cd.has(pn):
			continue
		var rel: Vector2 = (p.rect as Rect2).get_center() - cc
		var along := rel.dot(fwd)
		if along <= 0.0 or along > reach:
			continue
		if absf(rel.dot(perp)) > half_w + PED_SIZE.x * 0.5 + 2.0:
			continue
		# Osa ei huomaa autoa ollenkaan
		if randf() < DODGE_OBLIVIOUS:
			_dodge_cd[pn] = 1.5
			continue
		_threat[pn] = {"t": randf_range(DODGE_REACT_MIN, DODGE_REACT_MAX), "car": car}


## Reaktioajat kuluvat; kun aika on täynnä, hahmo hyppää sivuun (jos ei jo jäänyt alle).
func _update_dodges(delta: float) -> void:
	for pn in _dodge_cd.keys():
		var t: float = float(_dodge_cd[pn]) - delta
		if t <= 0.0 or not is_instance_valid(pn):
			_dodge_cd.erase(pn)
		else:
			_dodge_cd[pn] = t
	for pn in _threat.keys():
		var th: Dictionary = _threat[pn]
		th["t"] = float(th.t) - delta
		if not is_instance_valid(pn) or _flying.has(pn) or Game.flag(pn, "dead"):
			_threat.erase(pn)
			continue
		if float(th.t) > 0.0:
			continue
		_threat.erase(pn)
		_dodge_cd[pn] = 1.2
		var car = th.car
		if is_instance_valid(car) and car.has_method("hit_rect"):
			_dodge(pn, car)


## Hyppy sivuun auton ajolinjalta. Ei hypätä taloon / veteen; jos kumpikaan puoli ei käy,
## hahmo jähmettyy paikalleen.
func _dodge(p: Node2D, car: Node) -> void:
	var v: Vector2 = car.velocity
	if v.length() < DODGE_MIN_SPEED * 0.5:
		return   # auto ehti jo pysähtyä
	var fwd := v.normalized()
	var perp := Vector2(-fwd.y, fwd.x)
	var r: Rect2 = car.hit_rect()
	var half_w := (absf(perp.x) * r.size.x + absf(perp.y) * r.size.y) * 0.5
	var hp: Vector2 = p.hit_point()
	var lat := (hp - r.get_center()).dot(perp)
	var first := signf(lat) if absf(lat) > 1.0 else (1.0 if randf() < 0.5 else -1.0)
	var target := Vector2.INF
	for side: float in [first, -first]:
		var move := side * (half_w + PED_SIZE.x * 0.5 + DODGE_MARGIN) - lat
		if absf(move) > DODGE_MAX_DIST:
			continue
		# sivuun ja hieman taaksepäin (pois auton edestä)
		var to := p.global_position + perp * move - fwd * 3.0
		if _city.has_method("is_walkable") and not _city.is_walkable(_city.world_to_cell(to)):
			continue
		target = to
		break
	if target == Vector2.INF:
		return
	var spr := _visual(p)
	var base := spr.position if spr else Vector2.ZERO
	var info := {"spr": spr, "base": base, "proc": p.is_processing(), "phys": p.is_physics_processing()}
	p.set_process(false)          # tekoäly ei liikuta hahmoa hypyn aikana
	p.set_physics_process(false)
	var tw := create_tween()
	tw.tween_property(p, "global_position", target, DODGE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if spr:
		tw.parallel().tween_property(spr, "position", base + Vector2(0.0, -5.0), DODGE_TIME * 0.5).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(spr, "position", base, DODGE_TIME * 0.5).set_ease(Tween.EASE_IN).set_delay(DODGE_TIME * 0.5)
	tw.tween_interval(0.25)   # hetken hengähdys ennen kuin jatkaa matkaa
	tw.tween_callback(_end_dodge.bind(p))
	info["tw"] = tw
	_dodging[p] = info
	Sfx.play("punch_miss", p.global_position, -6.0, 0.15, 0.9)
	if randf() < 0.6:
		var line: String = ["Varo!", "Hei!!", "Hullu!", "Katso eteesi!", "Huh!", "Opettele ajamaan!"][randi() % 6]
		if p.has_method("_say"):
			p._say(line)
		elif p.has_method("say"):
			p.say(line)


func _end_dodge(p) -> void:
	if not _dodging.has(p):
		return
	var info: Dictionary = _dodging[p]
	_dodging.erase(p)
	if not is_instance_valid(p):
		return
	var spr = info.spr
	if is_instance_valid(spr):
		spr.position = info.base
	if not Game.flag(p, "dead") and not _flying.has(p):
		p.set_process(bool(info.proc))
		p.set_physics_process(bool(info.phys))


## Auto ehti osua kesken hypyn: hyppy keskeytetään (lento ottaa hahmon hoitaakseen).
func _cancel_dodge(p) -> void:
	_threat.erase(p)
	if not _dodging.has(p):
		return
	var info: Dictionary = _dodging[p]
	_dodging.erase(p)
	var tw = info.tw
	if tw is Tween and (tw as Tween).is_valid():
		(tw as Tween).kill()
	var spr = info.spr
	if is_instance_valid(spr):
		spr.position = info.base
	if is_instance_valid(p):
		p.set_physics_process(bool(info.phys))


# ----------------------------------------------------------------------------
#  APUFUNKTIOT
# ----------------------------------------------------------------------------
## Pysäyttää AI-auton hetkeksi (sen _process ei aja).
## Jahtaako poliisiauto pelaajaa (etsintäkuulutus ja auto mukana jahdissa)?
func _police_chasing(n: Node) -> bool:
	var pm := get_tree().get_first_node_in_group("police_manager")
	if pm == null or int(pm.get("wanted")) <= 0:
		return false
	var mode = n.get("mode")
	return mode == null or int(mode) == 3   # PatrolCar.Mode.CHASE


## Pelaajan yli ajanut (ei jahtaava) poliisiauto seisoo, kunnes pelaaja on väistänyt.
func _update_yields(delta: float) -> void:
	for n in _yield.keys():
		if not is_instance_valid(n) or Game.flag(n, "dead") or _police_chasing(n):
			_yield.erase(n)
			continue
		var near: bool = is_instance_valid(_player) and _player.visible \
			and (n as Node2D).global_position.distance_to(_player.global_position) < YIELD_DIST
		if near:
			_yield[n] = 0.0
			_hold(n, 0.25)
		else:
			_yield[n] = float(_yield[n]) + delta
			if float(_yield[n]) >= YIELD_CLEAR:
				_yield.erase(n)


func _hold(n: Node, seconds: float) -> void:
	if not is_instance_valid(n):
		return
	n.set_process(false)
	_holds[n] = maxf(float(_holds.get(n, 0.0)), seconds)


func _honk(n: Node, text: String = "", volume_db: float = -4.0) -> void:
	if not is_instance_valid(n):
		return
	Sfx.play("horn", (n as Node2D).global_position, volume_db, 0.06)
	if text != "":
		if n.has_method("_say"):
			n._say(text)
		elif n.has_method("say"):
			n.say(text)


func _tick_timers(delta: float) -> void:
	for n in _holds.keys():
		var t: float = float(_holds[n]) - delta
		if not is_instance_valid(n):
			_holds.erase(n)
		elif t <= 0.0:
			_holds.erase(n)
			if not Game.flag(n, "dead"):
				n.set_process(true)
		else:
			_holds[n] = t
	for k in _cool.keys():
		var t2: float = float(_cool[k]) - delta
		if t2 <= 0.0:
			_cool.erase(k)
		else:
			_cool[k] = t2
	if Engine.get_physics_frames() % 120 == 0:
		for n in _last.keys():
			if not is_instance_valid(n):
				_last.erase(n)
				_vel.erase(n)
		for n in _flying.keys():
			if not is_instance_valid(n):
				_flying.erase(n)


## Osumakohdan tähtisalama.
func _impact_star(at: Vector2) -> void:
	var star := Polygon2D.new()
	var pts := PackedVector2Array()
	for k in 8:
		var r := 7.0 if k % 2 == 0 else 2.5
		pts.append(Vector2.from_angle(k * PI / 4.0) * r)
	star.polygon = pts
	star.color = Color(1.0, 0.92, 0.35)
	star.z_index = 4095
	var parent := _city.get("entities") as Node
	if parent == null:
		parent = get_tree().current_scene
	parent.add_child(star)
	star.global_position = at
	var tw := star.create_tween()
	tw.tween_property(star, "scale", Vector2(1.7, 1.7), 0.14)
	tw.parallel().tween_property(star, "modulate:a", 0.0, 0.14)
	tw.tween_callback(star.queue_free)
