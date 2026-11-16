extends CharacterBody2D

const WEAPON_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/weapons/weapon_pickup.tscn")

@export var speed: float = 100.0
var current_car: Node2D = null
var nearby_weapon: Node2D = null
var nearby_portal: Node = null
var money: int = 0
## Käsikranaatit: oma varasto aseen lisäksi (Q / hiiren keskipainike heittää)
const MAX_GRENADES := 5
const GRENADE_RANGE := 150.0
const GRENADE_SCRIPT := preload("res://scripts/weapons/Grenade.gd")
var grenades: int = 0
var _grenade_ready_ms := 0
var police_locked := false
var menu_locked := false


const BLOCK_FACTOR := 0.25           
const COMBO_WINDOW := 0.75           
const COMBO_POWER_HIT := 3           
## Juoksu (Shift)
const SPRINT_MULT := 1.7            ## nopeuskerroin juostessa
const SPRINT_ANIM := 1.8            ## kävelyanimaation nopeus juostessa
const SPRINT_FATIGUE := 0.5         ## väsymys % / sekunti juostessa
const SPRINT_MAX_FATIGUE := 95.0    ## tätä väsyneempi ei jaksa juosta
var sprinting := false
const DODGE_SPEED := 520.0
const DODGE_TIME := 0.16
const DODGE_COOLDOWN := 0.8
var blocking := false
var _combo := 0
var _combo_t := 0.0
var _dodge_t := 0.0
var _dodge_cd := 0.0
var _dodge_dir := Vector2.ZERO
var _invuln_t := 0.0
var _stun_t := 0.0
var _starve_msg_t := 0.0

# --- Auton alle jääminen: pelaaja lentää ilmassa ja kaatuu. SÄÄDÄ NÄITÄ ---
const CAR_HIT_MIN_DAMAGE := 2.0
const CAR_HIT_MAX_DAMAGE := 8.0
const CAR_HIT_LIE_TIME := 0.7        ## kuinka kauan maataan maassa laskeutumisen jälkeen
var _fly_t := 0.0
var _fly_dur := 0.0
var _fly_vel := Vector2.ZERO
var _fly_height := 0.0
var _fly_spin := 0.0
var _fly_damage := 0.0
var _fly_source: Node = null
var _car_hit_cd := 0.0

const ROB_RANGE := 52.0

const MAX_HP := 12
const REGEN_DELAY := 6.0             
const REGEN_RATE := 0.25             
const PUNCH_RANGE := 26.0
const PUNCH_COOLDOWN := 0.38
const CAR_PUNCH_DAMAGE := 3.0       ## nyrkin vahinko autolle (pelaajan auton kunto 100, liikenneauton 60)
const CAR_MELEE_DAMAGE := 7.0       ## lähiaseen (pullo, keppi, veitsi) vahinko autolle / vahinkopiste
var hp: float = MAX_HP
var _since_hurt := 99.0
var _punch_cd := 0.0

const DrunkFXScript := preload("res://scripts/entities/DrunkFX.gd")

# --- Humala (promilleja). Bar.gd:n ryyppy kutsuu drink(). SÄÄDÄ NÄITÄ ---
const SOBER_RATE := 0.012            ## promillea sekunnissa (selviäminen)
const DRUNK_MAX := 4.0
const PASS_OUT_AT := 3.6             ## tästä ylöspäin pelaaja sammuu
const PASS_OUT_ROBBED := 0.3         ## osuus rahoista, jonka sammunut menettää
const PASS_OUT_WAKE_LEVEL := 1.0     ## promillet herätessä
## Humalan portaat: rajat (promillea), nimet ja viestit portaaseen noustessa
const STAGE_LIMITS := [0.3, 0.8, 1.5, 2.4]
const STAGE_NAMES := ["Selvä", "Hiprakassa", "Känni", "Tosi känni", "Tuiterissa"]
const STAGE_MESSAGES := ["", "Alkaa lämmittää...", "Känni alkaa nousta päähän", "Maailma alkaa heilua", "Et seiso enää suorassa..."]

## Humalatila promilleina. Nousee baarissa juodusta kossusta ja laskee ajan myötä.
var drunk: float = 0.0
## Vatsassa oleva, vielä imeytymätön alkoholi: [[promilleja jäljellä, promillea/s], ...]
## Olut imeytyy hitaasti, shotti nopeasti (Bar.gd:n juomalista).
var _absorbing: Array = []

# --- Krapula: sammumisen (tai rajun humalan putkassa) jälkeen. SÄÄDÄ NÄITÄ ---
const HANGOVER_SECONDS := 150.0      ## täyden krapulan kesto sekunteina
const HANGOVER_SPEED := 0.35         ## kävelyn hidastus täydessä krapulassa (0.35 = -35 %)
const HANGOVER_SPREAD := 0.14        ## ampumisen lisähajonta radiaaneina
const HANGOVER_FIRE_SLOW := 0.6      ## tulinopeuden hidastus (+60 % laukausten väliin)
const HANGOVER_PUNCH_SLOW := 0.5     ## lyöntien hidastus (+50 %)
const HANGOVER_CURE := 1.5           ## "tasoittava": juotu promille vähentää krapulaa tämän verran
## Krapula 0..1 (1 = täysi). Laskee ajan myötä.
var hangover: float = 0.0
var _shown_hang := -1.0
var _drunk_t := 0.0
var _stage := 0
var _passing_out := false
var _stumble := Vector2.ZERO
var _stumble_timer := 2.0
var _shown_drunk := -1.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
const CHAR_SPRITES := preload("res://scripts/core/CharSprites.gd")
var _frames_src: SpriteFrames
var _frames_pose := {}
var _weapon_pose := 0
@onready var held_weapon: Node2D = $HeldWeapon

func _ready() -> void:
	add_to_group("player")
	# tarkemmat 32 px hahmokuvat 16 px kokoon (+ aseasennot, ks. set_weapon_pose)
	_frames_src = animated_sprite.sprite_frames
	_frames_pose[0] = CHAR_SPRITES.upgrade_frames(_frames_src)
	animated_sprite.sprite_frames = _frames_pose[0]
	if held_weapon.equipped:
		set_weapon_pose(WeaponDB.hold_pose(held_weapon.weapon_id))
	var fx := DrunkFXScript.new()
	fx.name = "DrunkFX"
	add_child(fx)
	animated_sprite.frame_changed.connect(_on_frame_changed)
	# Ryöstönäppäin (R), jos sitä ei ole vielä määritelty Project Settings -> Input Map
	if not InputMap.has_action("rob"):
		InputMap.add_action("rob")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_R
		InputMap.action_add_event("rob", ev)
	_ensure_key_action("block", KEY_F, MOUSE_BUTTON_RIGHT)
	_ensure_key_action("sprint", KEY_SHIFT)
	_ensure_key_action("throw_grenade", KEY_Q, MOUSE_BUTTON_MIDDLE)
	_ensure_key_action("smoke", KEY_C)
	_ensure_key_action("toggle_vest", KEY_V)
	_ensure_key_action("tie_up", KEY_Z)
	# Kampaus (torin kampaamo) piirretään pään päälle
	var hv := HairView.new()
	hv.name = "HairView"
	hv.spr = animated_sprite
	animated_sprite.add_child(hv)
	# Liikkuminen myös WASD:llä (nuolinäppäinten lisäksi): kävely, autolla ajo ja valikot
	_add_key_to_action("ui_up", KEY_W)
	_add_key_to_action("ui_left", KEY_A)
	_add_key_to_action("ui_down", KEY_S)
	_add_key_to_action("ui_right", KEY_D)

## Lisää näppäimen olemassa olevaan toimintoon, jos sitä ei siinä vielä ole.
func _add_key_to_action(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == key:
			return
	var k := InputEventKey.new()
	k.physical_keycode = key
	InputMap.action_add_event(action, k)

func _ensure_key_action(action: String, key: Key, mouse: MouseButton = MOUSE_BUTTON_NONE) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)
	if mouse != MOUSE_BUTTON_NONE:
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse
		InputMap.action_add_event(action, mb)

func _physics_process(delta: float) -> void:
	if _fly_t > 0.0:
		_update_flight(delta)
		return
	if police_locked or menu_locked or _stun_t > 0.0:
		velocity = Vector2.ZERO
		animated_sprite.stop()
		_set_blocking(false)
		return
	# Liikkuminen WASD / Nuolinäppäimillä
	var input_vector := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	# Torjunta (F / hiiren oikea): hidastaa kävelyä, iskut tekevät vähemmän vahinkoa
	_set_blocking(Input.is_action_pressed("block") and not has_ranged_weapon())

	# Juoksu (Shift pohjassa): nopeampi liike ja animaatio, väsyttää
	sprinting = Input.is_action_pressed("sprint") and input_vector != Vector2.ZERO and not blocking \
		and Game.fatigue < SPRINT_MAX_FATIGUE
	if sprinting:
		Game.fatigue = minf(Game.fatigue + SPRINT_FATIGUE * delta, 100.0)
	animated_sprite.speed_scale = SPRINT_ANIM if sprinting else 1.0

	var mult := needs_speed_mult() * (0.45 if blocking else 1.0) * (SPRINT_MULT if sprinting else 1.0)
	velocity = _drunk_velocity(input_vector, delta, mult)
	move_and_slide()

	# Tähtäys + ampuminen / lyönti lähiaseella (jos ase kädessä)
	held_weapon.update(delta, input_vector)

	# Ei asetta kädessä: ammu-näppäin (välilyönti / hiiri) lyö nyrkillä, pito toistaa
	if not has_weapon() and not blocking and Input.is_action_pressed("shoot"):
		punch()

	_update_animation(input_vector)

func _set_blocking(value: bool) -> void:
	if value == blocking:
		return
	blocking = value
	queue_redraw()

## Torjunnan kuvake: kaari hahmon edessä.
func _draw() -> void:
	if not blocking:
		return
	var c := Vector2.ZERO
	var face := _facing_vec()
	draw_arc(c + face * 5.0, 8.0, face.angle() - 1.1, face.angle() + 1.1, 10, Color(0.6, 0.85, 1.0, 0.9), 2.0)

## Onko kädessä ampuma-ase (lähiaseella voi torjua)?
func has_ranged_weapon() -> bool:
	return has_weapon() and not held_weapon.is_melee()

## Nälkä ja väsymys hidastavat liikkumista.
func needs_speed_mult() -> float:
	var m := 1.0
	if Game.hunger > 70.0:
		m -= 0.18 * (Game.hunger - 70.0) / 30.0
	if Game.fatigue > 75.0:
		m -= 0.22 * (Game.fatigue - 75.0) / 25.0
	return m

## Poliisin sähköase: pelaaja jähmettyy hetkeksi.
func stun(seconds: float) -> void:
	if _invuln_t > 0.0 or _passing_out:
		return
	_stun_t = maxf(_stun_t, seconds)
	Sfx.play("taser", body_center(), 0.0, 0.05)
	animated_sprite.modulate = Color(0.6, 0.8, 1.6)
	create_tween().tween_property(animated_sprite, "modulate", Color.WHITE, seconds)
	_show_message("Sähköase! Lihakset jumittuvat...", 1.5)

# ----------------------------------------------------------------------------
#  HUMALA
# ----------------------------------------------------------------------------
## Selviäminen, HUD:n päivitys ja sammuminen. _process pyörii myös autossa istuessa.
func _process(delta: float) -> void:
	_update_vest_look()
	_vitutus_lines(delta)
	_drunk_t += delta
	_punch_cd = maxf(_punch_cd - delta, 0.0)
	_combo_t = maxf(_combo_t - delta, 0.0)
	_dodge_cd = maxf(_dodge_cd - delta, 0.0)
	_invuln_t = maxf(_invuln_t - delta, 0.0)
	_stun_t = maxf(_stun_t - delta, 0.0)
	_car_hit_cd = maxf(_car_hit_cd - delta, 0.0)
	_regen(delta)
	# Nälkä: täysin tyhjä vatsa vie voimia
	if Game.hunger >= 100.0 and hp > 0.0 and not _passing_out and visible:
		hp = maxf(hp - 0.06 * delta, 0.0)
		_refresh_health_hud()
		_starve_msg_t -= delta
		if _starve_msg_t <= 0.0:
			_starve_msg_t = 25.0
			_show_message("Nälkä heikentää! Syö jotain (jääkaappi kotona, kauppa).", 2.5)
		if hp <= 0.0:
			_pass_out(true)
	_absorb_alcohol(delta)
	if hangover > 0.0:
		hangover = maxf(hangover - delta / HANGOVER_SECONDS, 0.0)
		if hangover <= 0.0:
			_show_message("Krapula hellitti.", 2.0)
	if drunk > 0.0:
		drunk = maxf(drunk - SOBER_RATE * delta, 0.0)
		var s := _stage_for(drunk)
		if s < _stage:
			_stage = s
	_refresh_drunk_hud()
	if drunk >= PASS_OUT_AT and not _passing_out and visible and is_physics_processing():
		_pass_out()

# ----------------------------------------------------------------------------
#  TAPPELU
# ----------------------------------------------------------------------------
## Pelaaja saa iskun (baarin asiakas). Nollaan mennessä pelaaja pökertyy.
func hurt(amount: float, _source: Node = null) -> void:
	if _passing_out or hp <= 0.0:
		return
	if _invuln_t > 0.0:
		return   # väistö: isku menee ohi
	if blocking:
		amount *= BLOCK_FACTOR
		Sfx.play("block", body_center(), -2.0, 0.08)
		Game.fatigue = minf(Game.fatigue + 0.3, 100.0)
	# kevlarliivi ottaa osan iskusta
	if Game.armor > 0.0:
		var absorbed := minf(amount * Game.ARMOR_ABSORB, Game.armor)
		Game.armor -= absorbed
		amount -= absorbed
		if Game.armor <= 0.05:
			Game.armor = 0.0
			Sfx.play("clang", body_center(), -4.0, 0.05, 0.8)
			_show_message("Kevlarliivi hajosi!", 2.0)
	hp = maxf(hp - amount, 0.0)
	_since_hurt = 0.0
	Sfx.play("punch_hit", body_center(), 0.0, 0.05, 0.75)
	animated_sprite.modulate = Color(1.0, 0.45, 0.45)
	create_tween().tween_property(animated_sprite, "modulate", Color.WHITE, 0.2)
	_refresh_health_hud()
	if hp <= 0.0:
		_pass_out(true)

func _regen(delta: float) -> void:
	_since_hurt += delta
	if hp < MAX_HP and hp > 0.0 and _since_hurt > REGEN_DELAY:
		hp = minf(hp + REGEN_RATE * delta, MAX_HP)
		_refresh_health_hud()

func get_max_hp() -> float:
	return float(MAX_HP)

func _refresh_health_hud() -> void:
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud and hud.has_method("set_health"):
		hud.set_health(hp, MAX_HP)

## Lyönti nyrkillä (kun ase ei ole kädessä). Toimii kaikkialla: osuu lähimpään
## edessä olevaan kohteeseen, jolla on fist_hit() (baarin asiakas, ohikulkija, poliisi).
func punch() -> void:
	if _punch_cd > 0.0 or police_locked or _passing_out or has_weapon():
		return
	# Kombo: nopeasti peräkkäiset lyönnit, joka kolmas on tuplavahinkoinen koukku
	_combo = _combo + 1 if _combo_t > 0.0 else 1
	_combo_t = COMBO_WINDOW
	var power := _combo >= COMBO_POWER_HIT
	if power:
		_combo = 0
	_punch_cd = PUNCH_COOLDOWN * (1.0 + HANGOVER_PUNCH_SLOW * hangover) * (1.5 if power else 1.0)
	var face := _facing_vec()
	var center := body_center()
	var best: Node = null
	var best_d := PUNCH_RANGE
	for n in get_tree().get_nodes_in_group("shootable"):
		if not is_instance_valid(n) or not n.has_method("fist_hit") or not n.has_method("hit_point"):
			continue
		if n.has_method("is_punchable") and not n.is_punchable():
			continue
		var to: Vector2 = n.hit_point() - center
		var d := to.length()
		# kohteen pitää olla edessä (tai aivan vieressä)
		if d < best_d and (d < 8.0 or to.normalized().dot(face) > -0.2):
			best_d = d
			best = n
	_punch_fx(center + face * 9.0, face)
	if best == null:
		# Ei ketään edessä: osuuko nyrkki autoon?
		var car := _car_in_front(center, face)
		if car:
			_hit_car(car, center + face * 9.0, CAR_PUNCH_DAMAGE * (2.0 if power else 1.0))
			return
	if best:
		_impact_fx(best.hit_point())
		Sfx.play("punch_hit", best.hit_point(), 2.0 if power else 0.0, 0.08, 0.85 if power else 1.0)
		best.fist_hit(self)
		if power and is_instance_valid(best) and (not best.has_method("is_punchable") or best.is_punchable()):
			best.fist_hit(self)
			_float_text("KOUKKU!", best.hit_point() + Vector2(0, -10))
	else:
		Sfx.play("punch_miss", center, -4.0)

## Lähiase (pullo, biljardikeppi, kynä, veitsi): HeldWeapon kutsuu. Palauttaa true jos osui.
## lethal = osuma tekee oikeaa vahinkoa (take_damage), muuten isku on kuin lyönti (fist_hit).
func melee_swing(reach: float, damage: int, lethal: bool) -> bool:
	if police_locked or menu_locked or _passing_out:
		return false
	var face := _facing_vec()
	var center := body_center()
	var best: Node = null
	var best_d := reach
	for n in get_tree().get_nodes_in_group("shootable"):
		if not is_instance_valid(n) or not n.has_method("hit_point"):
			continue
		if n.has_method("is_punchable") and not n.is_punchable():
			continue
		var to: Vector2 = n.hit_point() - center
		var d := to.length()
		if d < best_d and (d < 8.0 or to.normalized().dot(face) > -0.1):
			best_d = d
			best = n
	_punch_fx(center + face * 12.0, face)
	if best == null:
		var car := _car_in_front(center, face)
		if car:
			_hit_car(car, center + face * 12.0, float(damage) * (CAR_MELEE_DAMAGE if lethal else CAR_PUNCH_DAMAGE))
			return true
		Sfx.play("punch_miss", center, -2.0, 0.1, 0.8)
		return false
	_impact_fx(best.hit_point())
	Sfx.play("punch_hit", best.hit_point(), 2.0, 0.08, 0.7)
	if lethal and best.has_method("take_damage"):
		best.take_damage(damage, self)
	elif best.has_method("fist_hit"):
		for i in damage:
			if not is_instance_valid(best):
				break
			if best.has_method("is_punchable") and not best.is_punchable():
				break
			best.fist_hit(self)
	return true

## Auto, johon lyönti osuu (pelaajan edessä). Liikenneautot ja pysäköidyt / pelaajan autot.
func _car_in_front(center: Vector2, face: Vector2) -> Node2D:
	var tip := center + face * 11.0
	var near := center + face * 5.0
	var best: Node2D = null
	var best_d := INF
	for g in ["car_targets", "player_vehicles"]:
		for c in get_tree().get_nodes_in_group(g):
			if not is_instance_valid(c) or not (c is Node2D) or not c.has_method("hit_rect") or not c.has_method("take_hit"):
				continue
			if Game.flag(c, "is_driving"):
				continue
			var r: Rect2 = c.hit_rect()
			if r.grow(3.0).has_point(tip) or r.grow(2.0).has_point(near):
				var d := r.get_center().distance_to(center)
				if d < best_d:
					best_d = d
					best = c
	return best

## Lyönti / lähiase osuu autoon: auto ottaa vahinkoa (voi syttyä palamaan ja räjähtää).
func _hit_car(car: Node2D, at: Vector2, amount: float) -> void:
	car.take_hit(amount, true)
	_impact_fx(at)
	Sfx.play("clang", at, -2.0, 0.12, 0.75)
	Sfx.play("punch_hit", at, -6.0, 0.08, 0.6)
	# kori heilahtaa
	var spr: Node2D = null
	for key in ["visual", "animated_sprite"]:
		var v = car.get(key)
		if v is Node2D:
			spr = v
			break
	if spr:
		var tw := spr.create_tween()
		tw.tween_property(spr, "rotation", randf_range(-0.08, 0.08), 0.04)
		tw.tween_property(spr, "rotation", 0.0, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Pieni kelluva teksti maailmassa (kombo, osumat).
func _float_text(text: String, at: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	l.z_index = 4095
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_parent().add_child(l)
	l.global_position = at - Vector2(20, 6)
	l.size = Vector2(40, 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tw := create_tween()
	tw.tween_property(l, "global_position:y", at.y - 22.0, 0.6)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)

## Suunta johon hahmo katsoo (viimeisimmän kävelyanimaation mukaan).
func _facing_vec() -> Vector2:
	match str(animated_sprite.animation):
		"walk_left":
			return Vector2.LEFT
		"walk_right":
			return Vector2.RIGHT
		"walk_up":
			return Vector2.UP
	return Vector2.DOWN

## Nyrkki lyö eteenpäin: pieni ihonvärinen nelikulmio + hahmon töytäys.
func _punch_fx(at: Vector2, face: Vector2) -> void:
	var base := animated_sprite.position
	var tw := create_tween()
	tw.tween_property(animated_sprite, "position", base + face * 3.0, 0.05)
	tw.tween_property(animated_sprite, "position", base, 0.09)

	var fist := Polygon2D.new()
	fist.polygon = PackedVector2Array([Vector2(-2.5, -2.5), Vector2(2.5, -2.5), Vector2(2.5, 2.5), Vector2(-2.5, 2.5)])
	fist.color = Color(0.96, 0.78, 0.62)
	fist.z_index = 4090
	get_parent().add_child(fist)
	fist.global_position = at
	var ft := create_tween()
	ft.tween_property(fist, "global_position", at + face * 8.0, 0.07)
	ft.tween_property(fist, "modulate:a", 0.0, 0.06)
	ft.tween_callback(fist.queue_free)

## Osumakohdan tähtisalama.
func _impact_fx(at: Vector2) -> void:
	var star := Polygon2D.new()
	var pts := PackedVector2Array()
	for k in 8:
		var r := 6.0 if k % 2 == 0 else 2.5
		var a := k * PI / 4.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	star.polygon = pts
	star.color = Color(1.0, 0.92, 0.35)
	star.z_index = 4095
	get_parent().add_child(star)
	star.global_position = at
	var tw := create_tween()
	tw.tween_property(star, "scale", Vector2(1.6, 1.6), 0.12)
	tw.parallel().tween_property(star, "modulate:a", 0.0, 0.12)
	tw.tween_callback(star.queue_free)

## Juo alkoholia (Bar.gd kutsuu). amount = promillea yhteensä,
## absorb_seconds = kuinka kauan imeytyminen kestää (0 = heti).
## Juominen myös tasoittaa krapulaa.
func drink(amount: float, absorb_seconds: float = 0.0) -> void:
	if hangover > 0.0:
		var before := hangover
		hangover = maxf(hangover - amount * HANGOVER_CURE, 0.0)
		if before > 0.15 and hangover <= 0.0:
			_show_message("Tasoittava teki tehtävänsä. Krapula hellitti.", 2.5)
	if absorb_seconds <= 0.0:
		_add_drunk(amount)
	else:
		_absorbing.append([amount, amount / absorb_seconds])

## Vatsasta imeytyy alkoholia vereen jokaisen juoman omaa tahtia.
func _absorb_alcohol(delta: float) -> void:
	if _absorbing.is_empty():
		return
	var total := 0.0
	for i in range(_absorbing.size() - 1, -1, -1):
		var e: Array = _absorbing[i]
		var take := minf(float(e[0]), float(e[1]) * delta)
		e[0] = float(e[0]) - take
		total += take
		if float(e[0]) <= 0.0001:
			_absorbing.remove_at(i)
	if total > 0.0:
		_add_drunk(total)

## Vatsassa vielä imeytymättä oleva alkoholi (promillea).
func pending_alcohol() -> float:
	var total := 0.0
	for e: Array in _absorbing:
		total += float(e[0])
	return total

func _add_drunk(amount: float) -> void:
	drunk = minf(drunk + amount, DRUNK_MAX)
	var s := _stage_for(drunk)
	if s > _stage:
		_stage = s
		if STAGE_MESSAGES[s] != "":
			_show_message(STAGE_MESSAGES[s], 2.5)
	_refresh_drunk_hud(true)

## Krapulan vaikutus ampumiseen (HeldWeapon kysyy).
func hangover_spread() -> float:
	return HANGOVER_SPREAD * hangover

func hangover_fire_mult() -> float:
	return 1.0 + HANGOVER_FIRE_SLOW * hangover

## Krapula alkaa (1.0 = täysi). Ei koskaan pienennä olemassa olevaa krapulaa.
func start_hangover(amount: float = 1.0) -> void:
	hangover = maxf(hangover, clampf(amount, 0.0, 1.0))
	_refresh_drunk_hud(true)

## Humalan voimakkuus 0..1 (0 = ei vaikutuksia, 1 = täysi tuiterrus).
## Kamera, ruutuefekti ja auto lukevat tätä.
func drunk_strength() -> float:
	return clampf((drunk - 0.3) / 2.7, 0.0, 1.0)

## Selviää heti (esim. yö putkassa). Kova humala jättää krapulan.
func sober_up() -> void:
	var was := drunk + pending_alcohol()
	drunk = 0.0
	_absorbing.clear()
	_stage = 0
	if was >= 1.0:
		start_hangover(clampf(was / 2.5, 0.3, 1.0))
	_refresh_drunk_hud(true)

func _stage_for(value: float) -> int:
	var s := 0
	for limit: float in STAGE_LIMITS:
		if value >= limit:
			s += 1
	return s

func _refresh_drunk_hud(force: bool = false) -> void:
	var v := snappedf(drunk, 0.01)
	var h := snappedf(hangover, 0.01)
	if not force and is_equal_approx(v, _shown_drunk) and is_equal_approx(h, _shown_hang):
		return
	_shown_drunk = v
	_shown_hang = h
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud and hud.has_method("set_drunk"):
		hud.set_drunk(drunk, STAGE_NAMES[_stage], hangover)

## Kännissä kävely: kaartelu, hidas reagointi, satunnaiset kompastelut ja hoiperrus.
## mult = nopeuskerroin (juoksu, torjunta, nälkä). Pehmennetty nopeus pidetään omassa
## muuttujassaan: aiemmin juoksukerroin kertautui joka ruudussa ja kännissä juoksu karkasi käsistä.
var _walk_vel := Vector2.ZERO

func _drunk_velocity(input_vector: Vector2, delta: float, mult: float = 1.0) -> Vector2:
	var k := drunk_strength()
	var wanted := input_vector * speed * (1.0 - HANGOVER_SPEED * hangover) * mult
	if k <= 0.0:
		_stumble = Vector2.ZERO
		_walk_vel = wanted
		return wanted
	wanted *= 1.0 - 0.15 * k
	if input_vector != Vector2.ZERO:
		var ang := (sin(_drunk_t * 1.7) * 0.6 + sin(_drunk_t * 0.55 + 1.3) * 0.4) * 0.9 * k
		wanted = wanted.rotated(ang)
	_stumble_timer -= delta
	if _stumble_timer <= 0.0:
		_stumble_timer = randf_range(1.5, 4.5) / (0.4 + k)
		_stumble = Vector2.from_angle(randf() * TAU) * randf_range(60.0, 130.0) * k
	_stumble = _stumble.move_toward(Vector2.ZERO, 160.0 * delta)
	wanted += _stumble
	wanted += Vector2(sin(_drunk_t * 2.1), cos(_drunk_t * 1.7)) * 18.0 * k
	# juostessa kaatuilu on vähän rajumpaa, mutta nopeus pysyy aina hallinnassa
	_walk_vel = _walk_vel.lerp(wanted, clampf(delta * lerpf(14.0, 4.5, k), 0.0, 1.0))
	_walk_vel = _walk_vel.limit_length(speed * maxf(mult, 1.0) * 1.15 + 130.0 * k)
	return _walk_vel

## Liikaa kossua tai turpaan: ruutu pimenee, joku käy lompakolla ja herätään baarin ovelta.
func _pass_out(from_fight: bool = false) -> void:
	if _passing_out:
		return
	_passing_out = true
	set_physics_process(false)
	set_process_unhandled_input(false)
	velocity = Vector2.ZERO
	animated_sprite.stop()
	if not from_fight:
		_absorbing.clear()   # loput juomat eivät enää nosta promilleja
	if from_fight:
		_show_message("Saat nyrkistä... silmissä pimenee.", 2.5)
	else:
		_show_message("Silmissä pimenee... sammuit.", 2.5)
	var fx := get_node_or_null("DrunkFX")
	if fx:
		await fx.fade_to(1.0, 1.6)
	var lost := int(money * PASS_OUT_ROBBED)
	if lost > 0:
		add_money(-lost)
	if not from_fight:
		drunk = PASS_OUT_WAKE_LEVEL
		_stage = _stage_for(drunk)
		start_hangover(1.0)   # seuraava "päivä" alkaa krapulassa
		_refresh_drunk_hud(true)
	hp = MAX_HP
	_since_hurt = 99.0
	_refresh_health_hud()
	# kartanon hovimestari hakee kadulle jääneet autot talliin
	Game.butler_fetch_cars(4.0)
	var bar := get_tree().get_first_node_in_group("bar")
	var in_bar: bool = bar != null and Game.flag(bar, "inside")

	# Pökerryit jahdin aikana: poliisi korjaa sinut putkaan
	var pm := get_tree().get_first_node_in_group("police_manager")
	if from_fight and pm and pm.wanted > 0:
		if fx:
			await fx.fade_to(0.0, 0.5)
		set_physics_process(true)
		set_process_unhandled_input(true)
		_passing_out = false
		pm.arrest("Pökerryit, ja poliisi otti sinut kiinni.", -1)
		return

	# Hävitty tappelu kadulla (tai nälkä): herätään sairaalasta, ja lasku maksetaan
	var hospital := get_tree().get_first_node_in_group("hospital")
	if from_fight and not in_bar and hospital and hospital.has_method("admit"):
		var bill: int = hospital.admit(self)
		await get_tree().create_timer(1.0).timeout
		if lost > 0:
			_show_message("Heräsit sairaalasta. Joku vei %d $, ja hoito maksoi %d $." % [lost, bill], 4.0)
		else:
			_show_message("Heräsit sairaalasta. Hoitolasku: %d $." % bill, 3.5)
		if fx:
			await fx.fade_to(0.0, 1.4)
		set_physics_process(true)
		set_process_unhandled_input(true)
		_passing_out = false
		return

	if bar and bar.has_method("wake_up_player"):
		bar.wake_up_player(self)
	await get_tree().create_timer(1.0).timeout
	if from_fight:
		if lost > 0:
			_show_message("Heräsit baarin ovelta. Nenä vuotaa ja lompakko on %d $ kevyempi." % lost, 3.5)
		else:
			_show_message("Heräsit baarin ovelta. Nenä vuotaa.", 3.5)
	elif lost > 0:
		_show_message("Heräsit baarin ovelta krapulassa. Lompakko on %d $ kevyempi." % lost, 3.5)
	else:
		_show_message("Heräsit baarin ovelta. Päätä särkee: krapula hidastaa liikkeitä.", 3.5)
	if fx:
		await fx.fade_to(0.0, 1.4)
	set_physics_process(true)
	set_process_unhandled_input(true)
	_passing_out = false

## Askeleen ääni jokaisella kävelyanimaation ruudulla.
func _on_frame_changed() -> void:
	if not visible or police_locked or not is_physics_processing() or not animated_sprite.is_playing():
		return
	if not str(animated_sprite.animation).begins_with("walk_"):
		return
	Sfx.play("step", body_center(), -14.0, 0.15, 1.0 - 0.15 * drunk_strength())

func _update_animation(input_vector: Vector2) -> void:
	# Ampumisen aikana pelaaja katsoo hetken ampumasuuntaan
	if held_weapon.is_aiming():
		var anim := "walk_" + str(held_weapon.facing)
		if input_vector != Vector2.ZERO:
			animated_sprite.play(anim)
		else:
			animated_sprite.animation = anim
			animated_sprite.stop()
			animated_sprite.frame = 0
		return

	# Animaatioiden hallinta liikkeen perusteella
	if input_vector != Vector2.ZERO:
		# Liikutaan johonkin suuntaan, valitaan animaatio
		if abs(input_vector.x) > abs(input_vector.y):
			if input_vector.x < 0:
				animated_sprite.play("walk_left")
			else:
				animated_sprite.play("walk_right")
		else:
			if input_vector.y < 0:
				animated_sprite.play("walk_up")
			else:
				animated_sprite.play("walk_down")
	else:
		# Ei liiku, pysäytetään animaatio tai näytetään paikallaan olo
		animated_sprite.stop()

func _unhandled_input(event: InputEvent) -> void:
	if police_locked or menu_locked or _stun_t > 0.0 or _fly_t > 0.0:
		return
	if event.is_action_pressed("interact"):
		# Ase maassa on etusijalla, sitten ovi, muuten noustaan autoon
		# (kaupan aseen voi ostaa vaikka kädessä olisi ase: vanha pudotetaan)
		if is_instance_valid(nearby_weapon) and (not has_weapon() or nearby_weapon.price > 0):
			pickup_weapon()
		elif is_instance_valid(nearby_portal):
			nearby_portal.use(self)
		elif is_instance_valid(current_car):
			enter_car()
	elif event.is_action_pressed("drop_weapon") and has_weapon():
		drop_weapon()
	elif event.is_action_pressed("rob"):
		try_rob()
	elif event.is_action_pressed("throw_grenade"):
		throw_grenade()
	elif event.is_action_pressed("toggle_vest"):
		toggle_vest()
	elif event.is_action_pressed("tie_up"):
		try_tie()
	elif event.is_action_pressed("smoke"):
		start_smoke()
	elif event.is_action_released("smoke"):
		_smoke_release()


## Nippusiteet (Z): sitoo kaupan myyjän ryöstön aikana (ei hälytystä) tai lähimmän
## ohikulkijan (ei pääse soittamaan poliisille). Sitominen on rikos, jos joku näkee.
const TIE_RANGE := 22.0
const TIE_TIME := 90.0

func try_tie() -> void:
	if Game.zip_ties <= 0:
		_show_message("Ei nippusiteitä. Asekaupan Erkiltä saa.", 2.0)
		return
	# kaupan ryöstö: myyjä
	for room in get_tree().get_nodes_in_group("indoor_room"):
		if Game.flag(room, "inside") and room.has_method("try_tie_in_room"):
			var res := str(room.call("try_tie_in_room", self))
			if res != "":
				_used_tie(res)
			return
	var city := get_tree().current_scene.get_node_or_null("City")
	var ents: Node = city.get("entities") if city else null
	if ents == null:
		return
	var best: Node2D = null
	var best_d := TIE_RANGE
	for m in ents.get_children():
		if not m.has_method("tie_up") or Game.flag(m, "is_car") or Game.flag(m, "dead"):
			continue
		if bool(m.call("is_tied")) or not (m as Node2D).visible:
			continue
		var d := (m as Node2D).global_position.distance_to(body_center())
		if d < best_d:
			best_d = d
			best = m
	if best == null:
		_show_message("Ketään ei ole tarpeeksi lähellä sidottavaksi.", 1.8)
		return
	best.call("tie_up", TIE_TIME)
	_used_tie("Sidoit ohikulkijan nippusiteillä. Hän ei pääse soittamaan poliisille.")
	get_tree().call_group("police_manager", "commit_crime", 1, best.global_position, best, false)


func _used_tie(text: String) -> void:
	Game.zip_ties -= 1
	Sfx.play("clink", body_center(), -6.0, 0.05, 1.6)
	_show_message("%s Siteitä jäljellä %d." % [text, Game.zip_ties], 2.5)


## Kevlarliivi pois päältä kokonaan / takaisin päälle (V). Riisuttu liivi kulkee mukana
## kestävyytensä säilyttäen; uuden liivin ostaminen korvaa sen.
func toggle_vest() -> void:
	if Game.armor > 0.0:
		Game.vest_carried = Game.armor
		Game.armor = 0.0
		Sfx.play_ui("clink", -8.0, 0.7)
		_show_message("Riisuit kevlarliivin (%d %%). V: pue takaisin." % roundi(Game.vest_carried / Game.ARMOR_MAX * 100.0), 2.5)
	elif Game.vest_carried > 0.0:
		Game.armor = Game.vest_carried
		Game.vest_carried = 0.0
		Sfx.play("clang", body_center(), -10.0, 0.05, 0.7)
		_show_message("Puit kevlarliivin päälle (%d %%)." % roundi(Game.armor / Game.ARMOR_MAX * 100.0), 2.0)
	else:
		_show_message("Sinulla ei ole kevlarliiviä. Asekaupasta saa.", 2.0)
	_update_vest_look()


func max_grenades() -> int:
	return MAX_GRENADES


## Lisää (tai vähentää) kranaatteja ja päivittää HUD:n. Palauttaa todellisen muutoksen.
func add_grenades(n: int) -> int:
	var before := grenades
	grenades = clampi(grenades + n, 0, MAX_GRENADES)
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud and hud.has_method("set_grenades"):
		hud.set_grenades(grenades)
	return grenades - before


## Heittää kranaatin hiiren suuntaan (enintään GRENADE_RANGE px).
func throw_grenade() -> void:
	if grenades <= 0:
		_show_message("Ei kranaatteja. Asekaupasta saa lisää.", 1.8)
		return
	if Time.get_ticks_msec() < _grenade_ready_ms:
		return
	if Game.player_indoors():
		_show_message("Ei sisällä! Täällä on liian ahdasta.", 1.8)
		return
	var from := body_center()
	var to := get_global_mouse_position()
	if from.distance_to(to) > GRENADE_RANGE:
		to = from + (to - from).normalized() * GRENADE_RANGE
	var g := GRENADE_SCRIPT.new()
	g.start = from + Vector2(0.0, -4.0)
	g.target = to
	get_tree().current_scene.add_child(g)
	add_grenades(-1)
	_grenade_ready_ms = Time.get_ticks_msec() + 700


## Ase kädessä: 0 = ei asetta, 1 = yhden käden ote, 2 = kahden käden ote.
## Vaihtaa animaatioruudut niin, että käsi ojentuu aseen kahvalle.
func set_weapon_pose(pose: int) -> void:
	if _frames_src == null or pose == _weapon_pose:
		return
	_weapon_pose = pose
	_swap_frames(_frames_for(pose))


## Ulkoasu: vaatteet (Game.outfit) ja kevlarliivi näkyvät hahmossa (CharSprites.outfit_frames)
const BASE_LOOK := "grey|black|0|0"
var _look := BASE_LOOK
var _look_frames := {}

func _look_key() -> String:
	return "%s|%s|%d|%d" % [str(Game.outfit.get("shirt", "grey")), str(Game.outfit.get("pants", "black")), int(Game.armor > 0.0), int(Game.mask_on)]

func _frames_for(pose: int) -> SpriteFrames:
	if not _frames_pose.has(pose):
		_frames_pose[pose] = CHAR_SPRITES.armed_frames(_frames_src, pose)
	if _look == BASE_LOOK:
		return _frames_pose[pose]
	var key := "%d:%s" % [pose, _look]
	if not _look_frames.has(key):
		var sh: Array = Game.SHIRTS.get(str(Game.outfit.get("shirt", "grey")), Game.SHIRTS["grey"])
		var pa: Array = Game.PANTS.get(str(Game.outfit.get("pants", "black")), Game.PANTS["black"])
		var sid := str(Game.outfit.get("shirt", "grey"))
		var style := sid if Game.SHIRT_STYLES.has(sid) else ""
		_look_frames[key] = CHAR_SPRITES.outfit_frames(_frames_pose[pose], sh[2], pa[2], Game.armor > 0.0, Game.mask_on, style)
	return _look_frames[key]

func _update_vest_look() -> void:
	if _frames_src == null:
		return
	var key := _look_key()
	if key == _look:
		return
	_look = key
	_swap_frames(_frames_for(_weapon_pose))

func _swap_frames(sf: SpriteFrames) -> void:
	var anim := animated_sprite.animation
	var fr := animated_sprite.frame
	var playing := animated_sprite.is_playing()
	animated_sprite.sprite_frames = sf
	if animated_sprite.sprite_frames.has_animation(anim):
		animated_sprite.animation = anim
		animated_sprite.frame = fr
		if playing:
			animated_sprite.play(anim)

func has_weapon() -> bool:
	return held_weapon.equipped

## Poimii lähellä olevan aseen käteen.
func pickup_weapon() -> void:
	if not is_instance_valid(nearby_weapon):
		return
	var price: int = nearby_weapon.price
	if has_weapon() and price <= 0:
		return
	if price > 0:
		if money < price:
			_show_message("Ei tarpeeksi rahaa: %d $ / %d $" % [money, price], 2.0)
			return
		add_money(-price)
		if has_weapon():
			drop_weapon()  # vanha ase jalkoihin
	var pickup := nearby_weapon
	nearby_weapon = null
	held_weapon.equip(pickup.weapon_id, str(animated_sprite.animation).trim_prefix("walk_"))
	var fx := str(pickup.get("fixture")) if pickup.get("fixture") != null else ""
	if fx != "":
		held_weapon.fixture = fx
		Game.fixtures[fx] = "out"
	pickup.remove_from_group("fixture_pickups")
	pickup.picked_up()

## Pudottaa aseen pelaajan jalkoihin.
func drop_weapon() -> void:
	if not has_weapon():
		return
	var pickup := WEAPON_PICKUP_SCENE.instantiate()
	pickup.weapon_id = held_weapon.weapon_id
	# paikalleen kuuluva esine pysyy samana esineenä maassa (ei monistu)
	pickup.fixture = held_weapon.fixture
	held_weapon.fixture = ""
	held_weapon.unequip()
	get_tree().current_scene.add_child(pickup)
	pickup.global_position = body_center() + Vector2(0, 4)

func enter_car() -> void:
	if current_car.has_method("can_enter") and not current_car.can_enter():
		_show_message("Auto on romuna, se ei enää liiku.", 2.0)
		return
	hide()
	set_physics_process(false)
	set_process_unhandled_input(false)
	$CollisionShape2D.disabled = true
	velocity = Vector2.ZERO
	if current_car.has_method("drive"):
		current_car.drive(self)

## Hahmon vartalon keskipiste maailmassa (kolikot, ryöstö, osumat käyttävät tätä).
## Pelaajan solmu on hahmon keskellä; törmäysmuoto on jaloissa.
func body_center() -> Vector2:
	return global_position

# ----------------------------------------------------------------------------
#  AUTON ALLE JÄÄMINEN
# ----------------------------------------------------------------------------
## Auto osui pelaajaan (Impacts kutsuu). car_vel = auton nopeus osumahetkellä.
## Palauttaa true, jos osuma tuli perille (ei väistössä, ei jo ilmassa).
func hit_by_car(car_vel: Vector2, source: Node = null) -> bool:
	if _fly_t > 0.0 or _dodge_t > 0.0 or _passing_out or _car_hit_cd > 0.0:
		return false
	if not visible or not is_physics_processing():
		return false
	var spd := car_vel.length()
	var k := clampf((spd - 40.0) / 220.0, 0.0, 1.0)
	_car_hit_cd = 1.2
	_set_blocking(false)
	_fly_dur = lerpf(0.35, 0.75, k)
	_fly_t = _fly_dur
	var dir := car_vel.normalized().rotated(randf_range(-0.4, 0.4))
	_fly_vel = dir * lerpf(150.0, 420.0, k)
	_fly_height = lerpf(6.0, 26.0, k)
	_fly_spin = (TAU * lerpf(1.0, 2.5, k)) * (1.0 if randf() < 0.5 else -1.0)
	_fly_damage = lerpf(CAR_HIT_MIN_DAMAGE, CAR_HIT_MAX_DAMAGE, k)
	_fly_source = source
	velocity = Vector2.ZERO
	animated_sprite.stop()
	Sfx.play("thud", body_center(), 2.0, 0.08)
	Sfx.play("punch_hit", body_center(), 0.0, 0.05, 0.6)
	animated_sprite.modulate = Color(1.0, 0.45, 0.45)
	create_tween().tween_property(animated_sprite, "modulate", Color.WHITE, 0.3)
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method("shake"):
		cam.shake(lerpf(2.0, 6.0, k))
	return true

## Lento ilmassa: liike kimpoaa seinistä, hahmo pyörii ja nousee kaarella.
func _update_flight(delta: float) -> void:
	_fly_t -= delta
	velocity = _fly_vel
	var pre := _fly_vel
	move_and_slide()
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if pre.dot(n) < 0.0:
			_fly_vel = pre.bounce(n) * 0.45
			Sfx.play("thud", body_center(), -4.0, 0.1)
			break
	_fly_vel = _fly_vel.move_toward(Vector2.ZERO, 380.0 * delta)
	var ph := clampf(1.0 - _fly_t / maxf(_fly_dur, 0.01), 0.0, 1.0)
	animated_sprite.position = Vector2(0.0, -sin(ph * PI) * _fly_height)
	animated_sprite.rotation = _fly_spin * ph
	if _fly_t <= 0.0:
		_land()

func _land() -> void:
	_fly_t = 0.0
	velocity = Vector2.ZERO
	animated_sprite.position = Vector2.ZERO
	# Maataan hetki kyljellään ja noustaan ylös
	var side := 1.0 if _fly_vel.x >= 0.0 else -1.0
	animated_sprite.rotation = PI * 0.5 * side
	_stun_t = maxf(_stun_t, CAR_HIT_LIE_TIME)
	Sfx.play("thud", body_center(), 0.0, 0.08, 0.8)
	var tw := create_tween()
	tw.tween_interval(CAR_HIT_LIE_TIME * 0.7)
	tw.tween_property(animated_sprite, "rotation", 0.0, CAR_HIT_LIE_TIME * 0.3)
	# Vahinko vasta laskeutuessa (pökertyminen kesken lennon jättäisi hahmon vinoon)
	var dmg := _fly_damage
	_fly_damage = 0.0
	hp = maxf(hp - dmg, 0.0)
	_since_hurt = 0.0
	_refresh_health_hud()
	if hp <= 0.0:
		animated_sprite.rotation = 0.0
		_pass_out(true)

func add_money(amount: int) -> void:
	money = maxi(money + amount, 0)
	if amount < 0:
		Sfx.play_ui("cash", -8.0)
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud and hud.has_method("set_money"):
		hud.set_money(money)

# ----------------------------------------------------------------------------
#  TUPAKKA JA VITUTUS
# ----------------------------------------------------------------------------
const SmokeFXScript := preload("res://scripts/core/SmokeFX.gd")
const SWEARS := ["Perkele...", "Vittu mikä päivä.", "Saatana sentään.", "Ei jaksa, ei jaksa.", "Nyt kyllä kiehuu.", "Hitto vie..."]
var _smoke: Node2D = null
var _swear_t := 12.0


## C: sytyttää tupakan (yksi savuke taskusta). Kun tupakka palaa, C pohjassa = henkonen:
## savuke nousee suulle ja vitutus laskee niin kauan kuin vedät. Napin irrotus laskee
## savukkeen käteen ja puhaltaa savut. Savuke palaa henkosista (ja hitaasti itsestään).
var _lit_this_press := false

func start_smoke() -> void:
	if is_instance_valid(_smoke) and _smoke.call("is_burning"):
		_smoke.call("set_inhale", true)
		return
	if Game.cigarettes <= 0:
		_show_message("Ei röökiä. Kaupasta saa askin (%d $)." % Game.CIG_PRICE, 2.0)
		return
	if not visible or police_locked or menu_locked:
		return
	Game.cigarettes -= 1
	var fx := SmokeFXScript.new()
	fx.sprite = animated_sprite
	fx.manual = true
	fx.on_inhale = func(dt: float) -> void:
		Game.add_vitutus(-6.0 * dt)
	fx.on_end = func() -> void:
		_show_message("Tumppi maahan. Röökiä jäljellä %d." % Game.cigarettes, 1.8)
	animated_sprite.add_child(fx)
	_smoke = fx
	_lit_this_press = true
	Sfx.play("clink", global_position, -14.0, 0.05, 2.2)   # sytkärin napsahdus
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud and hud.has_method("set_cigarettes"):
		hud.set_cigarettes(Game.cigarettes)
	_show_message("Sytytit röökin. Pidä C pohjassa vetääksesi henkosen.", 2.2)


func _smoke_release() -> void:
	if _lit_this_press:
		_lit_this_press = false
		return
	if is_instance_valid(_smoke):
		_smoke.call("set_inhale", false)


## Kova vitutus: pelaaja kiroilee itsekseen.
func _vitutus_lines(delta: float) -> void:
	# varmistus: nappi irti -> savuke käteen (irrotus voi jäädä huomaamatta valikossa)
	if is_instance_valid(_smoke) and InputMap.has_action("smoke") and not Input.is_action_pressed("smoke"):
		_smoke.call("set_inhale", false)
	if Game.vitutus < 85.0 or not visible:
		return
	_swear_t -= delta
	if _swear_t <= 0.0:
		_swear_t = randf_range(14.0, 26.0)
		var hud := get_tree().current_scene.get_node_or_null("Hud")
		if hud and hud.has_method("show_message"):
			hud.show_message("Sinä: \"%s\"" % SWEARS[randi() % SWEARS.size()], 1.8)


func _show_message(text: String, seconds: float = 2.0) -> void:
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(text, seconds)

## Ryöstää lähimmän ohikulkijan aseella uhaten (R).
func try_rob() -> void:
	if not has_weapon():
		_show_message("Tarvitset aseen ryöstöön", 1.5)
		return
	var best: Node = null
	var best_d := ROB_RANGE
	for n in get_tree().get_nodes_in_group("shootable"):
		if not is_instance_valid(n) or not n.has_method("can_be_robbed") or not n.can_be_robbed():
			continue
		var d := body_center().distance_to(n.hit_point())
		if d < best_d:
			best_d = d
			best = n
	if best == null:
		_show_message("Ei ketään ryöstettävää lähellä", 1.5)
		return
	best.rob(self)


## Kampaus pelaajan pään päällä (Game.hair). Lapsena AnimatedSprite2D:llä, joten seuraa
## kuvan paikkaa, lentoa, väriä ja hengitystä. Kommandopipo peittää kampauksen.
class HairView extends Node2D:
	const CS4 := preload("res://scripts/core/CharSprites.gd")
	var spr: AnimatedSprite2D = null

	func _process(_delta: float) -> void:
		# Pidetään kampaus aina viimeisenä (päällimmäisenä): räpytyksen silmäkuva (IdleLife)
		# ym. myöhemmin lisätyt lapset piirtäisivät muuten koko hahmon hiusten päälle.
		var par := get_parent()
		if par and par.get_child(par.get_child_count() - 1) != self:
			par.move_child(self, -1)
		queue_redraw()

	func _draw() -> void:
		if Game.mask_on or spr == null or spr.sprite_frames == null or not spr.sprite_frames.has_animation(spr.animation):
			return
		var tex := spr.sprite_frames.get_frame_texture(spr.animation, spr.frame)
		if tex == null:
			return
		var hat := str(Game.outfit.get("hat", "hat_none"))
		var gl := str(Game.outfit.get("glasses", "gl_none"))
		var style := str(Game.hair)
		# korkeat kampaukset jäävät hatun alle
		if hat != "hat_none" and style in ["banana", "mohawk", "afro"]:
			style = "bald"
		var info: Array = Game.HAIRS.get(style, [])
		var a := str(spr.animation)
		var col := 1
		if a.ends_with("left"):
			col = 0
		elif a.ends_with("up"):
			col = 2
		elif a.ends_with("right"):
			col = 3
		var sz := tex.get_size()
		var tl := spr.offset - sz * 0.5 if spr.centered else spr.offset
		var pad := float(CS4.HAIR_PAD) * sz.y / 32.0
		var r := Rect2(tl - Vector2(0.0, pad), Vector2(sz.x, sz.y + pad))
		if style != "bald" and info.size() >= 3:
			var h := CS4.hair_overlay(tex, col, style, info[2])
			if h:
				draw_texture_rect(h, r, false)
		if hat != "hat_none" or gl != "gl_none":
			var hc: Color = (Game.HATS.get(hat, Game.HATS["hat_none"]) as Array)[2]
			var gc: Color = (Game.GLASSES.get(gl, Game.GLASSES["gl_none"]) as Array)[2]
			var acc := CS4.accessory_overlay(tex, col, hat, hc, gl, gc)
			if acc:
				draw_texture_rect(acc, r, false)
