extends Node2D
## PANKKIKEIKKA – Kallen viimeinen keikka (Story.gd käynnistää: start()).
##  1. Elokuvamainen välianimaatio: nimikortti, yleiskuva pankista, pakoauto ajaa paikalle,
##     jengi (Pera, Tuukka, Jarno + sinä) nousee autosta pipot päässä, sisällä varoituslaukaus
##     hidastettuna, virkailija painaa hälytysnappia -> HÄLYTYS (välianimaatio päättyy).
##  2. C4 holvin oveen: sytytin 1 minuutti. Sillä välin katolta laskeutuu köysillä raskaasti
##     aseistettuja poliiseja kolmessa aallossa – ne tapetaan yhdessä jengin kanssa.
##  3. Räjähdys -> rahat holvista kassiin -> ulos ovesta.
##  4. Loppuvälianimaatio: katolla on tarkka-ampuja. Jarno kuolee pankin portailla.
## Pelaajan tajunnan menetys = keikka epäonnistuu (C4 menetetään, Kallelta voi yrittää uudestaan).
## Kaupungin poliisi ei reagoi keikan aikana (Game.heist_active): pankin oma iskuryhmä hoitaa sen.

const CS := preload("res://scripts/core/CharSprites.gd")
const EXPLOSION := preload("res://scripts/core/Explosion.gd")
const BLOOD := preload("res://scripts/core/Blood.gd")
const LOOT_TOTAL := 24000
const PLAYER_SHARE := 8000
const FUSE := 60.0
const LOOT_TIME := 6.0
const VAULT := Vector2(262.0, 16.0)        ## holvin ovi (huoneen koordinaatit)
const PLANT_SPOT := Vector2(262.0, 44.0)
## Poliisien laskeutumispaikat ja aallot (sekuntia sytytyksestä)
const SWAT_SPOTS := [Vector2(100, 105), Vector2(210, 105), Vector2(150, 128), Vector2(250, 128),
	Vector2(70, 150), Vector2(190, 165), Vector2(130, 165), Vector2(240, 150),
	Vector2(110, 140), Vector2(200, 140), Vector2(160, 100), Vector2(60, 108)]
const WAVES := [4.0, 22.0, 40.0]
const PER_WAVE := 4
const COVER := [Vector2(100, 105), Vector2(150, 128), Vector2(210, 105), Vector2(250, 128), Vector2(70, 150),
	Vector2(130, 165), Vector2(190, 165), Vector2(240, 150), Vector2(110, 140), Vector2(200, 140), Vector2(160, 100)]
const CREW := [
	["Pera", Color(0.2, 0.18, 0.19), Color(0, 0, 0, 0)],
	["Tuukka", Color(0.33, 0.38, 0.2), Color(0.2, 0.31, 0.55)],
	["Jarno", Color(0.16, 0.2, 0.36), Color(0.48, 0.48, 0.52)],
]

var bank: Node2D = null        ## ServiceBuilding (pankki)
var room: Node2D = null        ## ServiceInterior (pankin sisätila)
var player: Node2D = null
var stage := ""
var allies: Array = []
var swats: Array = []
var _van: Sprite2D = null
var _me: Node2D = null
var _ui: CanvasLayer
var _bar_top: ColorRect
var _bar_bot: ColorRect
var _fade: ColorRect
var _vignette: TextureRect
var _title: Label
var _sub: Label
var _obj: Label
var _sub_t := 0.0
var _alarm_t := 0.0
var _fuse_t := 0.0
var _fuse_on := false
var _wave := 0
var _loot_t := 0.0
var _looted := false
var _beep_t := 0.0
var _orig_zoom := 3.0


# ----------------------------------------------------------------------------
#  KÄYNNISTYS JA KÄYTTÖLIITTYMÄ
# ----------------------------------------------------------------------------
func start(p_bank: Node2D, p_player: Node2D) -> void:
	bank = p_bank
	room = bank.get("interior") as Node2D
	player = p_player
	add_to_group("bank_heist")
	Game.heist_active = true
	var cam := get_viewport().get_camera_2d()
	if cam and cam.get("zoom_level") != null:
		_orig_zoom = float(cam.get("zoom_level"))
	_build_ui()
	_intro()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	# varmistus: keikka ei jää "käyntiin" (estäisi tallennuksen ja poliisin pysyvästi)
	Game.heist_active = false
	var cam := get_viewport().get_camera_2d() if is_inside_tree() else null
	if cam and cam.get("zoom_level") != null:
		cam.set("zoom_level", _orig_zoom)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 80
	add_child(_ui)
	# reunojen tummennus (vinjetti) elokuvatunnelmaan
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.8))
	g.add_point(0.55, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 0.5)
	gt.width = 256
	gt.height = 256
	_vignette = TextureRect.new()
	_vignette.texture = gt
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	_ui.add_child(_vignette)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar_top = _rect(Color.BLACK)
	_bar_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar_top.offset_bottom = 0.0
	_bar_bot = _rect(Color.BLACK)
	_bar_bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_bot.offset_top = 0.0
	# tekstitys alareunassa ja tavoite ylhäällä: sivumarginaalit, rivitys, ei koskaan ruudun yli
	_sub = _label(20, Color(1.0, 0.95, 0.8))
	_sub.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_sub.offset_left = 90.0
	_sub.offset_right = -90.0
	_sub.offset_top = -150.0
	_sub.offset_bottom = -78.0
	_sub.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_obj = _label(17, Color(1.0, 0.85, 0.3))
	_obj.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_obj.offset_left = 260.0
	_obj.offset_right = -260.0
	_obj.offset_top = 64.0
	_obj.offset_bottom = 112.0
	_fade = _rect(Color(0, 0, 0, 0))
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title = _label(44, Color(0.95, 0.9, 0.8))
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.modulate.a = 0.0


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(r)
	return r


func _label(fs: int, c: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = false
	var ls := LabelSettings.new()
	ls.font_size = fs
	ls.font_color = c
	ls.outline_size = 6
	ls.outline_color = Color(0, 0, 0, 0.95)
	l.label_settings = ls
	_ui.add_child(l)
	return l


## Elokuvamoodi: mustat palkit + vinjetti
func _cinema(on: bool, secs: float = 0.8) -> void:
	Sfx.bgm_override = "cutscene" if on else ""
	var h := 72.0 if on else 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_bar_top, "offset_bottom", h, secs)
	tw.tween_property(_bar_bot, "offset_top", -h, secs)
	tw.tween_property(_vignette, "modulate:a", 1.0 if on else 0.0, secs)


func _fade_to(a: float, secs: float = 0.5) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", a, secs)
	await tw.finished


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


## Odotus oikeassa ajassa (hidastuksen aikana)
func _wait_real(secs: float) -> void:
	await get_tree().create_timer(secs, true, false, true).timeout


func _say(text: String, secs: float = 3.0) -> void:
	_sub.text = text
	_sub_t = secs


func _card(text: String, hold: float) -> void:
	_title.text = text
	var tw := create_tween()
	tw.tween_property(_title, "modulate:a", 1.0, 1.0)
	tw.tween_interval(hold)
	tw.tween_property(_title, "modulate:a", 0.0, 1.0)
	await tw.finished


func _objective(text: String) -> void:
	_obj.text = text


func _lock(on: bool) -> void:
	player.set_physics_process(not on)
	player.set_process_unhandled_input(not on)
	if "velocity" in player:
		player.velocity = Vector2.ZERO
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud and hud.has_method("hide_instruction"):
		hud.hide_instruction()


func _snap_cam(p: Vector2) -> void:
	player.global_position = p
	var cam := get_viewport().get_camera_2d()
	if cam:
		cam.global_position = p


## Kameran ajo: kamera seuraa (piilotetun) pelaajan paikkaa pehmeästi
func _dolly(to: Vector2, secs: float) -> void:
	var tw := create_tween()
	tw.tween_property(player, "global_position", to, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _zoom(k: float, secs: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null or cam.get("zoom_level") == null:
		return
	var tw := create_tween()
	tw.tween_property(cam, "zoom_level", _orig_zoom * k, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _shake(a: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method("shake"):
		cam.shake(a)


func _r(local: Vector2) -> Vector2:
	return (room.get("origin") as Vector2) + local


func _car_tex(d: Vector2i) -> Texture2D:
	var city := bank.get_parent().get_parent() if bank.get_parent() else null
	if city and city.has_method("car_texture"):
		return city.car_texture("green", d)
	return null


func _actor(p_name: String, shirt: Color, pants: Color, at: Vector2) -> Node2D:
	var a := HeistActor.new()
	a.set("display_name", p_name)
	a.set("shirt", shirt)
	a.set("pants", pants)
	a.set("heist", self)
	add_child(a)
	a.global_position = at
	return a


func _me_colors() -> Array:
	var sh: Color = (Game.SHIRTS.get(str(Game.outfit.get("shirt", "grey")), Game.SHIRTS["grey"]) as Array)[2]
	var pa: Color = (Game.PANTS.get(str(Game.outfit.get("pants", "black")), Game.PANTS["black"]) as Array)[2]
	return [sh, pa]


func _ally(n: String) -> Node2D:
	for a: Node2D in allies:
		if is_instance_valid(a) and str(a.get("display_name")) == n:
			return a
	return null


# ----------------------------------------------------------------------------
#  1. VÄLIANIMAATIO: PANKKIIN JA HÄLYTYS
# ----------------------------------------------------------------------------
func _intro() -> void:
	stage = "intro"
	_lock(true)
	await _fade_to(1.0, 0.8)
	player.hide()
	_cinema(true, 0.01)
	Game.mask_on = true
	await _card("KALLEN VIIMEINEN KEIKKA", 1.8)
	var door: Vector2 = bank.get("door_px")
	var roof: Rect2 = bank.get("roof")
	var van_stop := door + Vector2(-34.0, 46.0)
	_van = Sprite2D.new()
	_van.texture = _car_tex(Vector2i.RIGHT)
	_van.z_index = 2
	add_child(_van)
	_van.global_position = van_stop + Vector2(-300.0, 0.0)
	# yleiskuva: kaukaa pankin katolta alas oveen
	_snap_cam(roof.get_center() + Vector2(0.0, -30.0))
	_zoom(0.62, 0.01)
	await _wait(0.1)
	await _fade_to(0.0, 1.4)
	_say("Kaupungin Säästöpankki. Torstai, kello %02d:%02d." % [Game.hour(), int(fmod(Game.minutes, 60.0))], 3.5)
	_dolly(door + Vector2(-60.0, 40.0), 4.0)
	_zoom(0.85, 4.0)
	await _wait(1.2)
	# pakoauto ajaa kuvaan
	Sfx.play("engine_start", _van.global_position, -4.0, 0.05, 0.9)
	var tw := create_tween()
	tw.tween_property(_van, "global_position", van_stop, 2.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _wait(2.9)
	Sfx.play("screech", van_stop, -10.0, 0.05, 1.2)
	_dolly(van_stop + Vector2(10.0, 4.0), 1.5)
	_zoom(1.25, 2.0)
	_say("Kalle (radiossa): \"Okei jätkät. Sisään, holvi auki, ulos. Ei sankareita.\"", 3.6)
	await _wait(3.6)
	# jengi nousee autosta yksi kerrallaan
	var lines := ["Pipot päähän. Nyt ollaan töissä.", "Kymmenen minuuttia. Ei sekuntiakaan enempää.", "Viimeinen keikka... sit mä lopetan. Ihan oikeesti."]
	for i in CREW.size():
		var c: Array = CREW[i]
		var a := _actor(str(c[0]), c[1], c[2], van_stop + Vector2(-14.0 + i * 12.0, 15.0))
		a.modulate.a = 0.0
		a.create_tween().tween_property(a, "modulate:a", 1.0, 0.35)
		Sfx.play("door_open", van_stop, -10.0, 0.1)
		allies.append(a)
		await _wait(0.5)
		a.call("say", lines[i], 2.6)
		await _wait(2.4)
	var mc := _me_colors()
	_me = _actor("Sinä", mc[0], mc[1], van_stop + Vector2(22.0, 15.0))
	(_ally("Pera") as Node2D).call("say", "Mennään.", 1.5)
	await _wait(0.8)
	for i in allies.size():
		(allies[i] as Node2D).call("walk_to", door + Vector2(-12.0 + i * 12.0, 6.0))
	_me.call("walk_to", door + Vector2(4.0, 12.0))
	_dolly(door + Vector2(0.0, 10.0), 2.2)
	_zoom(1.4, 2.2)
	await _wait(2.3)
	await _fade_to(1.0, 0.4)
	# --- sisällä pankissa ---
	room.set("inside", true)
	room.call("_set_camera_limits", true)
	room.set("heist", "in")
	_van.hide()
	var inside_pos := [Vector2(120.0, 140.0), Vector2(200.0, 140.0), Vector2(150.0, 118.0)]
	for i in allies.size():
		(allies[i] as Node2D).global_position = _r(inside_pos[i])
		(allies[i] as Node2D).call("stop")
		(allies[i] as Node2D).set("col", 2)
	_me.global_position = _r(Vector2(160.0, 156.0))
	_me.call("stop")
	_me.set("col", 2)
	_snap_cam(_r(Vector2(160.0, 112.0)))
	_zoom(1.0, 0.01)
	await _fade_to(0.0, 0.4)
	await _wait(0.5)
	# varoituslaukaus hidastettuna
	var pera := _ally("Pera")
	Engine.time_scale = 0.35
	_zoom(1.5, 0.4)
	_dolly(pera.global_position + Vector2(0.0, -6.0), 0.4)
	Sfx.play("gun", pera.global_position, 0.0, 0.0, 0.7)
	pera.set("_flash", 0.2)
	tracer(pera.global_position + Vector2(0.0, -8.0), _r(Vector2(150.0, 34.0)))
	_shake(3.0)
	pera.call("say", "KAIKKI MAAHAN! TÄÄ ON RYÖSTÖ!", 1.2)
	await _wait_real(1.4)
	Engine.time_scale = 1.0
	_zoom(1.15, 1.0)
	_dolly(_r(Vector2(160.0, 112.0)), 1.0)
	await _wait(1.6)
	(_ally("Tuukka") as Node2D).call("say", "Kädet ylös ja turvat kiinni!", 2.0)
	await _wait(2.0)
	# lähikuva virkailijaan: sormi hälytysnapille
	_dolly(_r(Vector2(160.0, 66.0)), 1.6)
	_zoom(1.8, 1.6)
	_say("...virkailijan sormi hakeutuu hiljaa tiskin alle.", 2.6)
	await _wait(2.6)
	room.set("heist", "alarm")
	_alarm_t = 0.0
	_shake(2.0)
	_zoom(1.0, 0.6)
	_dolly(_r(Vector2(160.0, 120.0)), 0.6)
	_say("HÄLYTYS! Kalle: \"Perkele, nyt on kiire! C4 holvin oveen!\"", 3.0)
	await _wait(2.6)
	# välianimaatio päättyy: pelaaja ottaa ohjat "sinun" hahmosi paikalla
	room.call("_move_player", player, _me.global_position)
	_me.queue_free()
	_me = null
	player.show()
	_zoom(1.0, 0.01)
	_cinema(false)
	_lock(false)
	stage = "plant"
	_objective("Aseta C4 holvin oveen (tiskin takana oikealla)")
	InteractSpot.create(self, _r(PLANT_SPOT), Vector2(30.0, 14.0), _spot_prompt, _spot_use)
	for a: Node2D in allies:
		a.call("guard")


# ----------------------------------------------------------------------------
#  2. C4 (1 MIN) JA POLIISIAALLOT
# ----------------------------------------------------------------------------
func _spot_prompt() -> String:
	match stage:
		"plant":
			return "Paina E: aseta C4 holvin oveen"
		"loot":
			return "Paina E: lastaa rahat holvista kassiin"
		"looting":
			return "Lastataan rahoja... pysy holvilla!"
	return ""


func _spot_use(_p: Node2D) -> void:
	if stage == "plant":
		Game.c4 = maxi(Game.c4 - 1, 0)
		stage = "fuse"
		_fuse_t = FUSE
		_fuse_on = true
		_wave = 0
		_beep_t = 0.0
		room.set("heist", "bomb")
		Sfx.play("clink", _r(VAULT), -4.0, 0.0, 0.7)
		_say("C4 viritetty. Sytytin: 1 minuutti.", 2.5)
		(_ally("Tuukka") as Node2D).call("say", "Minuutti?! Pidetään pintamme siihen asti!", 2.5)
	elif stage == "loot":
		stage = "looting"


func _fmt(t: float) -> String:
	var s := maxi(ceili(t), 0)
	return "%d:%02d" % [s / 60, s % 60]


func _process(delta: float) -> void:
	if _sub_t > 0.0:
		_sub_t -= delta
		if _sub_t <= 0.0:
			_sub.text = ""
	if room == null:
		return
	# hälytyskello soi
	var h := str(room.get("heist"))
	if h != "" and h != "in":
		_alarm_t -= delta
		if _alarm_t <= 0.0:
			_alarm_t = 1.2
			Sfx.play("siren", _r(Vector2(160.0, 60.0)), -10.0, 0.0, 1.7)
	# epäonnistuminen: pelaaja menetti tajuntansa
	if stage in ["plant", "fuse", "loot", "looting", "escape"]:
		if Game.flag(player, "_passing_out") or float(player.get("hp")) <= 0.0:
			_fail()
			return
	# sytytin ja poliisiaallot
	if _fuse_on:
		_fuse_t -= delta
		var elapsed := FUSE - _fuse_t
		if _wave < WAVES.size() and elapsed >= float(WAVES[_wave]):
			_spawn_wave(_wave)
			_wave += 1
		_beep_t -= delta
		if _beep_t <= 0.0:
			_beep_t = 0.25 if _fuse_t < 5.0 else (0.6 if _fuse_t < 15.0 else 1.0)
			Sfx.play("denied", _r(VAULT), -9.0, 0.0, 2.2)
		if _fuse_t <= 0.0:
			_fuse_on = false
			_blow_vault()
	var left := _alive_swats()
	match stage:
		"fuse":
			_objective("C4 räjähtää: %s   |   Poliiseja sisällä: %d" % [_fmt(_fuse_t), left])
		"loot", "looting":
			if stage == "looting":
				if player.global_position.distance_to(_r(PLANT_SPOT)) < 40.0:
					_loot_t += delta
					if int((_loot_t - delta) * 2.0) != int(_loot_t * 2.0):
						Sfx.play_ui("coin", -10.0, 0.8 + randf() * 0.4)
					if _loot_t >= LOOT_TIME:
						_loot_done()
				else:
					stage = "loot"
			if stage != "looted":
				_objective("Holvi auki! Lastaa rahat kassiin: %d %%   |   Poliiseja: %d" % [roundi(_loot_t / LOOT_TIME * 100.0), left])
		"looted":
			if left > 0:
				_objective("Rahat kassissa! Tapa loput poliisit: %d" % left)
			else:
				_ready_to_escape()


func _spawn_wave(w: int) -> void:
	if stage == "failed":
		return
	var callouts := ["Katolla liikettä!! Ne tulee köysillä!", "Lisää niitä! Raskaat aseet!", "Viimeinen aalto, kestäkää!"]
	(allies[w % allies.size()] as Node2D).call("say", callouts[w % callouts.size()], 2.5)
	Sfx.play("glass_break", _r(Vector2(160.0, 40.0)), -2.0, 0.1)
	_shake(2.0)
	if w == 0:
		_say("Katon luukuista laskeutuu raskaasti aseistettu iskuryhmä!", 3.0)
		for a: Node2D in allies:
			a.call("fight")
	for k in PER_WAVE:
		var i := w * PER_WAVE + k
		var s := HeistSwat.new()
		s.set("heist", self)
		add_child(s)
		s.call("rappel", _r(SWAT_SPOTS[i % SWAT_SPOTS.size()]), (room.get("origin") as Vector2).y - 40.0)
		swats.append(s)
		await _wait(0.45)
		if stage == "failed":
			return


func _blow_vault() -> void:
	var ex := EXPLOSION.new()
	get_tree().current_scene.add_child(ex)
	ex.global_position = _r(VAULT + Vector2(0.0, 10.0))
	room.set("heist", "blown")
	_shake(6.0)
	stage = "loot"
	(_ally("Pera") as Node2D).call("say", "BOOM! Holvi auki, rahat kassiin!", 2.5)


func _loot_done() -> void:
	_looted = true
	stage = "looted"
	room.set("heist", "looted")
	Sfx.play_ui("cash", -2.0)
	_say("Rahat kassissa: %d $!" % LOOT_TOTAL, 2.5)


## Pomminpaikka ja holvi: SWAT-luettelot hahmoille
func _alive_swats() -> int:
	var n := 0
	for s: Node2D in swats:
		if is_instance_valid(s) and not Game.flag(s, "dead"):
			n += 1
	return n


## Satunnainen suojapaikka poliisille (maailman koordinaateissa)
func cover_point() -> Vector2:
	return _r(COVER[randi() % COVER.size()])


func alive_swat_list() -> Array:
	var out: Array = []
	for s: Node2D in swats:
		if is_instance_valid(s) and not Game.flag(s, "dead"):
			out.append(s)
	return out


func _ready_to_escape() -> void:
	if _wave < WAVES.size():
		return
	stage = "escape"
	for a: Node2D in allies:
		a.call("guard")
	(_ally("Pera") as Node2D).call("say", "Puhdasta! Kalle on ovella, ULOS!", 3.0)
	_say("Kalle (radiossa): \"Auto on ovella! NYT!\"", 3.0)
	_objective("Juokse ulos ovesta pakoautoon!")


# ----------------------------------------------------------------------------
#  4. PAKO JA JARNON KUOLEMA
# ----------------------------------------------------------------------------
## ServiceInterior._exit_door kutsuu keikan aikana.
func on_exit_door(_p: Node2D) -> void:
	if stage != "escape":
		Game.msg("Ei vielä – keikka on kesken!", 1.5)
		return
	_escape()


func _escape() -> void:
	stage = "outro"
	_lock(true)
	_objective("")
	_cinema(true)
	await _fade_to(1.0, 0.5)
	room.set("heist", "")
	room.set("inside", false)
	room.call("_set_camera_limits", false)
	for s: Node2D in swats:
		if is_instance_valid(s):
			s.queue_free()
	swats.clear()
	var door: Vector2 = bank.get("door_px")
	player.hide()
	_snap_cam(door + Vector2(-10.0, 30.0))
	_zoom(1.2, 0.01)
	_van.show()
	var mc := _me_colors()
	_me = _actor("Sinä", mc[0], mc[1], door + Vector2(4.0, 8.0))
	for i in allies.size():
		(allies[i] as Node2D).global_position = door + Vector2(-12.0 + i * 12.0, 4.0)
		(allies[i] as Node2D).call("stop")
	var jarno := _ally("Jarno")
	var pera := _ally("Pera")
	var tuukka := _ally("Tuukka")
	await _fade_to(0.0, 0.5)
	Sfx.play("siren", door + Vector2(-260.0, 60.0), -8.0, 0.0, 1.0)
	pera.call("say", "AJOON!", 1.2)
	for a: Node2D in [pera, tuukka, jarno, _me]:
		a.call("walk_to", _van.global_position + Vector2(0.0, -14.0))
	await _wait(0.7)
	# --- laukaus katolta: hidastus ---
	Engine.time_scale = 0.25
	for a: Node2D in [pera, tuukka, _me]:
		a.call("stop")
	jarno.call("stop")
	Sfx.play("gun", jarno.global_position + Vector2(0.0, -80.0), 2.0, 0.0, 0.55)
	tracer(jarno.global_position + Vector2(30.0, -110.0), jarno.global_position + Vector2(0.0, -8.0))
	BLOOD.spray(jarno, jarno.global_position + Vector2(0.0, -8.0), Vector2(-0.4, 1.0), 12, true)
	_dolly(jarno.global_position + Vector2(0.0, -6.0), 0.5)
	_zoom(2.2, 0.6)
	_shake(2.0)
	jarno.call("fall")
	await _wait_real(2.2)
	Engine.time_scale = 1.0
	tuukka.call("say", "JARNO!!", 1.8)
	tuukka.call("walk_to", jarno.global_position + Vector2(10.0, 2.0))
	pera.call("aim_up")
	pera.call("say", "KATOLLA! Tarkka-ampuja!", 1.6)
	for k in 3:
		tracer(pera.global_position + Vector2(0.0, -8.0), pera.global_position + Vector2(20.0 + k * 6.0, -120.0))
		Sfx.play("gun", pera.global_position, -4.0, 0.08, 1.0)
		await _wait(0.18)
	await _wait(1.0)
	_me.call("walk_to", jarno.global_position + Vector2(-10.0, 4.0))
	_zoom(2.6, 3.0)
	await _wait(1.4)
	jarno.call("say", "...ei se mitään... Mä tiesin et tää oli liian hyvää ollakseen totta.", 3.4)
	await _wait(3.6)
	tuukka.call("say", "Älä puhu noin! Me viedään sut lääkäriin!", 2.6)
	await _wait(2.8)
	jarno.call("say", "Sanokaa mun mutsille... et mä yritin lopettaa.", 3.4)
	await _wait(3.6)
	jarno.call("say", "Menkää... Elkää jääkö tänne mun takia...", 3.0)
	await _wait(3.2)
	_say("Jarno sulkee silmänsä.", 2.6)
	jarno.set("still", true)
	await _wait(2.8)
	Sfx.play("siren", door + Vector2(-200.0, 40.0), -4.0, 0.0, 1.0)
	_say("Kalle (radiossa): \"Pojat... sireenit on kahden korttelin päässä. Meidän on pakko mennä. Nyt.\"", 4.0)
	await _wait(4.0)
	tuukka.call("say", "Me ei jätetä sitä tänne!", 2.2)
	await _wait(2.3)
	pera.call("say", "...Se on poissa, Tuukka. Tule.", 2.6)
	await _wait(2.6)
	for a: Node2D in [pera, tuukka, _me]:
		a.call("walk_to", _van.global_position + Vector2(0.0, -14.0))
	_zoom(1.6, 3.0)
	await _wait(1.8)
	for a: Node2D in [pera, tuukka, _me]:
		a.hide()
	Sfx.play("door_close", _van.global_position, -2.0, 0.1)
	await _wait(0.6)
	Sfx.play("engine_start", _van.global_position, -2.0, 0.05)
	var tw := create_tween()
	tw.tween_property(_van, "global_position", _van.global_position + Vector2(460.0, 0.0), 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# kamera jää Jarnon luo
	_dolly(jarno.global_position + Vector2(0.0, -4.0), 3.0)
	_zoom(2.0, 4.0)
	await _wait(3.2)
	_say("", 0.1)
	await _card("JARNO\n1999 – 2026", 2.5)
	await _fade_to(1.0, 1.2)
	await _card("Lepää rauhassa.", 1.5)
	# --- jälkimaininki: Kallen kulmilla ---
	for a: Node2D in allies:
		if is_instance_valid(a):
			a.queue_free()
	allies.clear()
	if is_instance_valid(_me):
		_me.queue_free()
	_van.queue_free()
	var story := get_tree().get_first_node_in_group("story")
	var dest: Vector2 = story.call("_bar_front") if story else player.global_position
	_snap_cam(dest)
	_zoom(1.0, 0.01)
	player.show()
	Game.mask_on = false
	Game.heist_active = false
	player.add_money(PLAYER_SHARE)
	Game.add_rep("criminals", 30)
	if story and story.has_method("on_heist_done"):
		story.on_heist_done()
	Sfx.play_ui("cash", -2.0)
	await _fade_to(0.0, 1.0)
	_say("PANKKIKEIKKA ONNISTUI – mutta hinta oli kova.\nSaalis %d $, sinun osuutesi %d $." % [LOOT_TOTAL, PLAYER_SHARE], 6.0)
	_lock(false)
	await _wait(1.5)
	_cinema(false, 1.5)
	await _wait(4.5)
	Game.msg("Kalle: \"Jarnon osuus menee sen mutsille. Se olis halunnu niin. ...Pidä pää matalana, kundi.\"", 6.0)
	await _wait(1.0)
	queue_free()


func _fail() -> void:
	stage = "failed"
	_fuse_on = false
	Engine.time_scale = 1.0
	Game.heist_active = false
	Game.mask_on = false
	if room:
		room.set("heist", "")
	for s: Node2D in swats:
		if is_instance_valid(s):
			s.queue_free()
	for a: Node2D in allies:
		if is_instance_valid(a):
			a.queue_free()
	if is_instance_valid(_me):
		_me.queue_free()
	if is_instance_valid(_van):
		_van.queue_free()
	Game.msg("Keikka kusi. Kalle: \"Jätkät haki sut ulos... Hanki uus C4 ja yritetään uudestaan.\"", 5.0)
	_objective("")
	_cinema(false)
	await _wait(5.0)
	queue_free()


# ----------------------------------------------------------------------------
#  APUTOIMINNOT HAHMOILLE
# ----------------------------------------------------------------------------
func tracer(from: Vector2, to: Vector2) -> void:
	var l := Line2D.new()
	l.width = 1.0
	l.default_color = Color(1.0, 0.9, 0.5, 0.9)
	l.points = PackedVector2Array([from, to])
	l.z_index = 20
	get_tree().current_scene.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 0.0, 0.1)
	tw.tween_callback(l.queue_free)


## Hahmon tekstuurisarake suunnasta
static func col_for(v: Vector2) -> int:
	if absf(v.x) > absf(v.y):
		return 3 if v.x > 0.0 else 0
	return 1 if v.y > 0.0 else 2


# ----------------------------------------------------------------------------
#  JENGIN JÄSEN (pipo, liivi, rynnäkkökivääri). Ei voi kuolla.
# ----------------------------------------------------------------------------
class HeistActor extends Node2D:
	const CS2 := preload("res://scripts/core/CharSprites.gd")
	var display_name := ""
	var shirt := Color(0, 0, 0, 0)
	var pants := Color(0, 0, 0, 0)
	var heist: Node2D = null
	var mode := "idle"
	var col := 1
	var _target := Vector2.ZERO
	var _walking := false
	var _anim := 0.0
	var _shoot_t := 1.0
	var _flash := 0.0
	var _home := Vector2.ZERO
	var _sheet: Texture2D = null
	var fallen := false
	var still := false
	var _fall_k := 0.0
	var _aim_up := false

	func _ready() -> void:
		_sheet = load(CS2.ARMED_PATH) as Texture2D
		z_index = 1

	func walk_to(p: Vector2) -> void:
		_target = p
		_walking = true

	func stop() -> void:
		_walking = false
		mode = "idle"
		_aim_up = false

	## Kaatuu maahan (osuma). still = true: ei enää hengitä.
	func fall() -> void:
		_walking = false
		mode = "idle"
		fallen = true
		col = 1
		var tw := create_tween()
		tw.tween_property(self, "_fall_k", 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	func aim_up() -> void:
		_aim_up = true
		col = 2

	func guard() -> void:
		mode = "guard"
		_home = global_position

	func fight() -> void:
		mode = "fight"
		_home = global_position
		_shoot_t = randf_range(0.6, 1.4)

	## Repliikki tekstityksenä ruudun alareunaan (rivittyy, ei mene ruudun yli);
	## puhujan pään päällä pieni puhekupla.
	var _talk_t := 0.0

	func say(text: String, secs: float = 2.0) -> void:
		_talk_t = secs
		if heist:
			heist.call("_say", "%s: \"%s\"" % [display_name, text], secs + 0.6)

	func _process(delta: float) -> void:
		_flash = maxf(_flash - delta, 0.0)
		_talk_t = maxf(_talk_t - delta, 0.0)
		if _walking:
			var to := _target - global_position
			if to.length() < 1.5:
				_walking = false
			else:
				global_position += to.normalized() * minf(62.0 * delta, to.length())
				col = heist.col_for(to)
				_anim += delta
		if mode == "fight" and heist:
			_shoot_t -= delta
			if _shoot_t <= 0.0:
				_shoot_t = randf_range(0.9, 1.7)
				var targets: Array = heist.alive_swat_list()
				if not targets.is_empty():
					var best: Node2D = null
					var bd := 1.0e9
					for s: Node2D in targets:
						var d := global_position.distance_to(s.global_position)
						if d < bd and not Game.flag(s, "rappelling"):
							bd = d
							best = s
					if best:
						var from := global_position + Vector2(0.0, -7.0)
						col = heist.col_for(best.global_position - global_position)
						var hit := randf() < 0.4
						var to_p: Vector2 = best.call("hit_point")
						if not hit:
							to_p += Vector2(randf_range(-12.0, 12.0), randf_range(-10.0, 10.0))
						heist.tracer(from, to_p)
						Sfx.play("gun", global_position, -9.0, 0.08, 1.05)
						_flash = 0.06
						if hit:
							best.call("take_damage", 2, self)
		queue_redraw()

	func _draw() -> void:
		var step := (1 + int(_anim * 7.0) % 2) if _walking else 0
		var tex: Texture2D = null
		if _sheet:
			tex = CS2.outfit(CS2.frame(_sheet, col, 3 + step), shirt, pants, true, true)
		draw_set_transform(Vector2(0, -0.5), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 5.0, Color(0, 0, 0, 0.25))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if fallen:
			# makaa selällään: kuva kierretään jalkojen ympäri, rintakehä nousee kunnes ei enää
			var breath := 0.0 if still else 0.5 * maxf(sin(Time.get_ticks_msec() / 260.0), 0.0)
			draw_set_transform(Vector2(-2.0 * _fall_k, -1.0), -PI * 0.5 * _fall_k, Vector2(1.0, 1.0 + breath * 0.06))
			if tex:
				draw_texture_rect(tex, Rect2(Vector2(-8.0, -16.0), Vector2(16.0, 16.0)), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			# kivääri maassa vieressä
			draw_line(Vector2(4.0, 2.0), Vector2(13.0, 4.0), Color(0.1, 0.1, 0.12), 1.6)
			_draw_bubble()
			return
		# kivääri
		var hand := Vector2(4.5, -6.0)
		var v := Vector2.DOWN
		match col:
			3:
				hand = Vector2(4.0, -8.0)
				v = Vector2.RIGHT
			0:
				hand = Vector2(-4.0, -8.0)
				v = Vector2.LEFT
			2:
				hand = Vector2(4.5, -9.0)
				v = Vector2.UP
		if _aim_up:
			hand = Vector2(3.0, -12.0)
			v = Vector2(0.25, -1.0).normalized()
		if col == 2:
			draw_line(hand - v * 2.0, hand + v * 7.0, Color(0.1, 0.1, 0.12), 1.6)
		if tex:
			draw_texture_rect(tex, Rect2(Vector2(-8.0, -16.0), Vector2(16.0, 16.0)), false)
		if col != 2:
			draw_line(hand - v * 2.0, hand + v * 7.0, Color(0.1, 0.1, 0.12), 1.6)
			draw_line(hand, hand + v * 1.5 + Vector2(0, 1.5), Color(0.35, 0.22, 0.12), 1.4)
		if _flash > 0.0:
			draw_circle(hand + v * 8.5, 2.0, Color(1.0, 0.85, 0.3))
		_draw_bubble()

	func _draw_bubble() -> void:
		if _talk_t <= 0.0:
			return
		var b := Rect2(Vector2(-6.0, -27.0), Vector2(12.0, 7.0))
		draw_rect(b.grow(0.5), Color(0, 0, 0, 0.6))
		draw_rect(b, Color(0.98, 0.97, 0.92))
		draw_colored_polygon(PackedVector2Array([Vector2(-2.0, -20.0), Vector2(1.0, -20.0), Vector2(-2.5, -17.5)]), Color(0.98, 0.97, 0.92))
		var ph := int(Time.get_ticks_msec() / 250) % 3
		for k in 3:
			draw_circle(Vector2(-3.0 + k * 3.0, -23.5), 0.8 if k != ph else 1.1, Color(0.15, 0.15, 0.18))


# ----------------------------------------------------------------------------
#  SWAT: laskeutuu köydellä katolta, liikkuu suojasta toiseen ja ampuu
# ----------------------------------------------------------------------------
class HeistSwat extends Node2D:
	const CS2 := preload("res://scripts/core/CharSprites.gd")
	const BULLET: PackedScene = preload("res://scenes/entities/weapons/bullet.tscn")
	const BLOOD2 := preload("res://scripts/core/Blood.gd")
	var heist: Node2D = null
	var hp := 7                  ## raskas suojavarustus
	var dead := false
	var _burst := 0
	var _burst_t := 0.0
	var _flash := 0.0
	const ARMOR := Color(0.3, 0.32, 0.38)
	var rappelling := false
	var sprite: Sprite2D
	var _top := 0.0
	var _land := Vector2.ZERO
	var _target := Vector2.ZERO
	var _move_t := 2.0
	var _shoot_t := 2.0
	var _anim := 0.0
	var _col := 1
	var _rope_a := 1.0

	func _ready() -> void:
		sprite = Sprite2D.new()
		sprite.offset = Vector2(0, -4)
		sprite.modulate = ARMOR
		add_child(sprite)
		add_to_group("shootable")
		add_to_group("enemy_shooter")
		z_index = 1
		_refresh(0)

	func hit_point() -> Vector2:
		return global_position + Vector2(0, -4)

	func is_punchable() -> bool:
		return not dead

	func fist_hit(from: Node2D) -> void:
		take_damage(1, from)

	func rappel(land: Vector2, top_y: float) -> void:
		_land = land
		_top = top_y
		rappelling = true
		global_position = Vector2(land.x, top_y)
		_target = land
		var tw := create_tween()
		tw.tween_property(self, "global_position", land, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_callback(_landed)

	func _landed() -> void:
		rappelling = false
		_shoot_t = randf_range(0.8, 2.0)
		var tw := create_tween()
		tw.tween_property(self, "_rope_a", 0.0, 1.0)

	func _refresh(step: int) -> void:
		sprite.texture = CS2.police(_col, step)

	func _process(delta: float) -> void:
		queue_redraw()
		if dead or rappelling or heist == null:
			return
		var player := get_tree().get_first_node_in_group("player") as Node2D
		# suojasta toiseen
		_move_t -= delta
		if _move_t <= 0.0:
			_move_t = randf_range(2.5, 4.5)
			_target = heist.call("cover_point")
		var to := _target - global_position
		if to.length() > 1.5:
			global_position += to.normalized() * minf(42.0 * delta, to.length())
			_anim += delta
			_col = heist.col_for(to)
			_refresh(1 + int(_anim * 7.0) % 2)
		elif player:
			_col = heist.col_for(player.global_position - global_position)
			_refresh(0)
		# ammunta: kolmen laukauksen sarjoja, useimmiten pelaajaa, joskus jengiä
		_flash = maxf(_flash - delta, 0.0)
		_shoot_t -= delta
		if _shoot_t <= 0.0 and _burst <= 0:
			_shoot_t = randf_range(2.2, 3.4)
			_burst = 3
			_burst_t = 0.0
		if _burst > 0:
			_burst_t -= delta
			if _burst_t > 0.0:
				return
			_burst -= 1
			_burst_t = 0.13
			_flash = 0.06
			var allies: Array = heist.allies
			if player and (randf() < 0.55 or allies.is_empty()):
				var bc: Vector2 = player.call("body_center")
				var dir: Vector2 = (bc - hit_point()).normalized().rotated(randf_range(-0.17, 0.17))
				_col = heist.col_for(dir)
				var b := BULLET.instantiate()
				b.setup(dir, self, 360.0, 1, 320.0)
				get_tree().current_scene.add_child(b)
				b.global_position = hit_point() + dir * 6.0
			else:
				var a: Node2D = allies[randi() % allies.size()]
				if is_instance_valid(a):
					heist.tracer(hit_point(), a.global_position + Vector2(randf_range(-8, 8), randf_range(-14, 2)))
			Sfx.play("gun", global_position, -7.0, 0.08, 0.95)

	func take_damage(amount: int = 1, source: Node = null) -> void:
		if dead:
			return
		var bdir: Vector2 = (global_position - (source as Node2D).global_position) if source is Node2D else Vector2.ZERO
		BLOOD2.spray(self, hit_point(), bdir, 4 if hp - amount > 0 else 9, hp - amount <= 0)
		hp -= amount
		sprite.modulate = Color(1.0, 0.55, 0.55)
		create_tween().tween_property(sprite, "modulate", ARMOR, 0.15)
		if hp <= 0:
			dead = true
			rappelling = false
			remove_from_group("shootable")
			remove_from_group("enemy_shooter")
			sprite.rotation = deg_to_rad(90.0 if _col != 0 else -90.0)
			sprite.modulate = Color(0.32, 0.32, 0.38)
			Sfx.play("punch_hit", global_position, -4.0, 0.05, 0.6)

	func _draw() -> void:
		if _rope_a > 0.01:
			# köysi katon luukusta
			var top_local := Vector2(0.0, _top - global_position.y - 40.0)
			draw_line(top_local, Vector2(0.0, -12.0), Color(0.75, 0.68, 0.5, _rope_a), 1.0)
		if dead:
			return
		# raskas varustus: kypärän visiiri ja rynnäkkökivääri
		var hand := Vector2(4.5, -6.0)
		var v := Vector2.DOWN
		match _col:
			3:
				hand = Vector2(4.0, -8.0)
				v = Vector2.RIGHT
			0:
				hand = Vector2(-4.0, -8.0)
				v = Vector2.LEFT
			2:
				hand = Vector2(4.5, -9.0)
				v = Vector2.UP
		draw_line(hand - v * 2.0, hand + v * 8.0, Color(0.06, 0.06, 0.08), 1.8)
		draw_rect(Rect2(hand + v * 1.5 - Vector2(0.8, 0.8), Vector2(1.6, 1.6)), Color(0.15, 0.15, 0.18))
		if _col != 2:
			draw_rect(Rect2(Vector2(-3.0, -15.5), Vector2(6.0, 1.6)), Color(0.12, 0.13, 0.16, 0.9))
		if _flash > 0.0:
			draw_circle(hand + v * 9.5, 2.2, Color(1.0, 0.8, 0.25))
