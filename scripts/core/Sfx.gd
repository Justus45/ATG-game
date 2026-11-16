extends Node
## Pelin äänet. Autoload "Sfx" (project.godot -> [autoload]).
## Kaikki äänet syntetisoidaan koodissa käynnistyksen yhteydessä, joten peli ei tarvitse
## äänitiedostoja. Jos haluat myöhemmin oikeat äänet, korvaa _streams-sanakirjan arvo
## ladatulla tiedostolla, esim. _streams["punch_hit"] = load("res://assets/sfx/punch.wav").
##
## Käyttö muista skripteistä:
##   Sfx.play("punch_hit", global_position)     # paikkasidottu ääni (kuuluu hiljempaa kaukaa)
##   Sfx.play_ui("cash")                         # ääni ilman sijaintia (käyttöliittymä)
##   Sfx.set_siren(0.0 .. 1.0)                   # PoliceManager säätää joka ruudussa
##   Sfx.play_music(0, jukebox_pos) / Sfx.stop_music()
##   Taustamusiikki (BGM): Sfx.set_bgm_auto("city") (Game päättää joka ruudussa) ja
##   Sfx.bgm_override = "menu" / "cutscene" (päävalikko, välianimaatiot) – "" = ei ohitusta.

const RATE := 22050
const MUSIC_RATE := 11025          ## jukeboksi soi lo-fi-laadulla (kevyempi laskea)
const POOL_SIZE := 16
const WORLD_HEARING := 650.0       ## pikseliä: kauempaa ei kuulu mitään

## Jukeboksin kappaleet (nimi näytetään HUD:ssa)
const TUNE_NAMES := ["Humppa-Heikki", "Tango Tammisaari"]

var _streams := {}
var _pool2d: Array[AudioStreamPlayer2D] = []
var _pool: Array[AudioStreamPlayer] = []
var _next2d := 0
var _next := 0
var _siren: AudioStreamPlayer
var _siren_target := 0.0
var _siren_level := 0.0
var _rain: AudioStreamPlayer
var _rain_target := 0.0
var _rain_level := 0.0
## Kaupungin taustaäänet: jatkuva liikenteen humina + satunnaiset kaukaiset äänet
var _hum: AudioStreamPlayer
var _hum_level := 0.0
var _amb_t := 4.0
var _music: AudioStreamPlayer2D
var _tunes: Array[AudioStreamWAV] = []
var _music_task := -1
var _wanted_tune := -1
var _wanted_tune_pos := Vector2.ZERO
var _mb := PackedFloat32Array()   # musiikin työpuskuri (vain taustasäie käyttää)
## --- Taustamusiikki: "menu", "city", "cutscene" (lasketaan samassa taustasäikeessä) ---
const BGM_DB := -15.0
const BGM_FADE := 0.8             ## häivytys sekunneissa
var _bgm: AudioStreamPlayer
var _bgm_tracks := {}
var _bgm_cur := ""
var _bgm_level := 0.0
var _bgm_auto := ""
var bgm_override := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_streams["punch_hit"] = _wav(_gen_punch_hit())
	_streams["punch_miss"] = _wav(_gen_whoosh())
	_streams["step"] = _wav(_gen_step())
	_streams["gun"] = _wav(_gen_gun())
	_streams["coin"] = _wav(_gen_coin())
	_streams["clink"] = _wav(_gen_clink())
	_streams["can"] = _wav(_gen_can())
	_streams["gulp"] = _wav(_gen_gulp())
	_streams["cash"] = _wav(_gen_cash())
	_streams["clang"] = _wav(_gen_clang())
	_streams["phone"] = _wav(_gen_phone())
	_streams["denied"] = _wav(_gen_denied())
	_streams["siren"] = _wav(_gen_siren(), RATE, true)
	_streams["block"] = _wav(_gen_block())
	_streams["taser"] = _wav(_gen_taser())
	_streams["glass_break"] = _wav(_gen_glass_break())
	_streams["rain"] = _wav(_gen_rain(), RATE, true)
	_streams["dart"] = _wav(_gen_dart())
	_streams["pool"] = _wav(_gen_pool())
	_streams["thunder"] = _wav(_gen_thunder())
	_streams["crash"] = _wav(_gen_crash())
	_streams["thud"] = _wav(_gen_thud())
	_streams["horn"] = _wav(_gen_horn())
	_streams["explosion"] = _wav(_gen_explosion())
	_streams["ignite"] = _wav(_gen_ignite())
	# autot, ihmiset ja kaupungin taustaäänet
	_streams["door_open"] = _wav(_gen_door(false))
	_streams["door_close"] = _wav(_gen_door(true))
	_streams["engine_start"] = _wav(_gen_engine_start())
	_streams["engine"] = _wav(_gen_engine_loop(), RATE, true)
	_streams["screech"] = _wav(_gen_screech())
	_streams["oof"] = _wav(_gen_voice(170.0, 110.0, 0.22, 500.0))
	_streams["scream"] = _wav(_gen_voice(420.0, 260.0, 0.55, 900.0))
	_streams["bird"] = _wav(_gen_bird())
	_streams["bark"] = _wav(_gen_bark())
	_streams["far_siren"] = _wav(_gen_far_siren())
	_streams["city_hum"] = _wav(_gen_city_hum(), RATE, true)

	for i in POOL_SIZE:
		var p2 := AudioStreamPlayer2D.new()
		p2.max_distance = WORLD_HEARING
		p2.attenuation = 1.4
		add_child(p2)
		_pool2d.append(p2)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)

	_siren = AudioStreamPlayer.new()
	_siren.stream = _streams["siren"]
	add_child(_siren)

	_rain = AudioStreamPlayer.new()
	_rain.stream = _streams["rain"]
	add_child(_rain)

	_hum = AudioStreamPlayer.new()
	_hum.stream = _streams["city_hum"]
	_hum.volume_db = -80.0
	add_child(_hum)

	_bgm = AudioStreamPlayer.new()
	_bgm.volume_db = -80.0
	add_child(_bgm)

	_music = AudioStreamPlayer2D.new()
	_music.max_distance = 900.0
	_music.attenuation = 0.7
	add_child(_music)

	# Jukeboksin kappaleet lasketaan taustalla, ettei peli nyki käynnistyessä
	_music_task = WorkerThreadPool.add_task(_build_tunes)


## Pelin sulkeutuessa odotetaan taustalaskenta loppuun (muuten Godot varoittaa
## keskeneräisestä säikeestä ja voi kaatua sulkiessa).
func _exit_tree() -> void:
	if _music_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1


func _process(delta: float) -> void:
	# Sireeni nousee ja laskee pehmeästi
	_siren_level = move_toward(_siren_level, _siren_target, delta * 1.5)
	if _siren_level > 0.01:
		if not _siren.playing:
			_siren.play()
		_siren.volume_db = linear_to_db(_siren_level * 0.45)
	elif _siren.playing:
		_siren.stop()

	_rain_level = move_toward(_rain_level, _rain_target, delta * 0.4)
	if _rain_level > 0.01:
		if not _rain.playing:
			_rain.play()
		_rain.volume_db = linear_to_db(_rain_level * 0.35)
	elif _rain.playing:
		_rain.stop()

	_update_ambience(delta)
	_update_bgm(delta)

	if _music_task >= 0 and WorkerThreadPool.is_task_completed(_music_task):
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1
		if _wanted_tune >= 0:
			play_music(_wanted_tune, _wanted_tune_pos)


# ----------------------------------------------------------------------------
#  JULKINEN RAJAPINTA
# ----------------------------------------------------------------------------
## Paikkasidottu ääni. pitch_var = satunnainen sävelkorkeuden vaihtelu (+-).
func play(sound: String, at: Vector2, volume_db: float = 0.0, pitch_var: float = 0.08, pitch: float = 1.0) -> void:
	if not _streams.has(sound):
		return
	var p := _pool2d[_next2d]
	_next2d = (_next2d + 1) % _pool2d.size()
	p.stream = _streams[sound]
	p.global_position = at
	p.volume_db = volume_db
	p.pitch_scale = maxf(pitch + randf_range(-pitch_var, pitch_var), 0.05)
	p.play()


## Valmis äänivirta (esim. auton moottorin oma soitin).
func stream(sound: String) -> AudioStream:
	return _streams.get(sound, null)


## Kaupungin elävyys: liikenteen humina ulkona (hiljaa sisällä) ja satunnaiset äänet
## kameran ympäriltä: linnut päivällä, koirat, kaukaiset tööttäykset ja sireenit.
func _update_ambience(delta: float) -> void:
	var scene := get_tree().current_scene
	var active := scene != null and scene.get_node_or_null("City") != null and not get_tree().paused \
		and get_tree().get_first_node_in_group("main_menu") == null
	var indoors := false
	if active:
		indoors = Game.player_indoors()
	var night := active and Game.darkness() > 0.6
	var target := 0.0
	if active:
		target = (0.12 if indoors else 0.45) * (0.6 if night else 1.0)
	_hum_level = move_toward(_hum_level, target, delta * 0.5)
	if _hum_level > 0.01:
		if not _hum.playing:
			_hum.play()
		_hum.volume_db = linear_to_db(_hum_level * 0.5)
	elif _hum.playing:
		_hum.stop()
	if not active or indoors:
		return
	_amb_t -= delta
	if _amb_t > 0.0:
		return
	_amb_t = randf_range(3.5, 9.0)
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var at := cam.get_screen_center_position() + Vector2.from_angle(randf() * TAU) * randf_range(280.0, 520.0)
	var r := randf()
	var rain := Game.rain_amount() if Game.has_method("rain_amount") else 0.0
	if not night:
		if r < 0.45 and rain < 0.3:
			play("bird", at, -10.0, 0.15)
		elif r < 0.75:
			play("horn", at, -14.0, 0.2)
		elif r < 0.88:
			play("bark", at, -10.0, 0.12)
		else:
			play("far_siren", at, -12.0, 0.05)
	else:
		if r < 0.35:
			play("bark", at, -8.0, 0.12)
		elif r < 0.6:
			play("far_siren", at, -10.0, 0.05)
		elif r < 0.8:
			play("horn", at, -15.0, 0.2)


## Ääni ilman sijaintia (rahan maksu, viestit).
func play_ui(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _streams.has(sound):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## 0 = hiljaa, 1 = poliisiauto aivan vieressä.
func set_siren(strength: float) -> void:
	_siren_target = clampf(strength, 0.0, 1.0)


## Ukkosen jyrinä viiveellä (salama ensin, ääni perässä).
func thunder(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	play_ui("thunder", randf_range(-6.0, 0.0), randf_range(0.85, 1.1))


## Sateen kohina 0..1 (Atmosphere säätää).
func set_rain(strength: float) -> void:
	_rain_target = clampf(strength, 0.0, 1.0)


func tune_count() -> int:
	return TUNE_NAMES.size()


func tune_name(i: int) -> String:
	return TUNE_NAMES[i] if i >= 0 and i < TUNE_NAMES.size() else ""


func play_music(tune: int, at: Vector2) -> void:
	_wanted_tune = tune
	_wanted_tune_pos = at
	if _music_task >= 0:
		return   # kappaleet vielä laskussa: alkaa soida kun valmista
	if tune < 0 or tune >= _tunes.size():
		return
	_music.global_position = at
	if _music.stream != _tunes[tune] or not _music.playing:
		_music.stream = _tunes[tune]
		_music.volume_db = -6.0
		_music.play()


## Taustamusiikki, jonka Game valitsee tilanteen mukaan ("city" kävellessä kaupungilla, "" = hiljaa).
func set_bgm_auto(track: String) -> void:
	_bgm_auto = track


func _update_bgm(delta: float) -> void:
	var want := bgm_override if bgm_override != "" else _bgm_auto
	# jukeboksi (baari) soi: taustamusiikki hiljaa
	if _music.playing and bgm_override == "":
		want = ""
	var tracks: Dictionary = _bgm_tracks
	if want != "" and not tracks.has(want):
		return   # kappale vielä laskussa taustalla
	if want != _bgm_cur:
		_bgm_level = move_toward(_bgm_level, 0.0, delta / BGM_FADE)
		if _bgm_level <= 0.0:
			_bgm_cur = want
			if want != "" and tracks.has(want):
				_bgm.stream = tracks[want]
				_bgm.play()
			else:
				_bgm.stop()
	elif _bgm_cur != "":
		_bgm_level = move_toward(_bgm_level, 1.0, delta / BGM_FADE)
		if not _bgm.playing and tracks.has(_bgm_cur):
			_bgm.stream = tracks[_bgm_cur]
			_bgm.play()
	_bgm.volume_db = linear_to_db(maxf(_bgm_level, 0.0001)) + BGM_DB


func stop_music() -> void:
	_wanted_tune = -1
	_music.stop()


func music_playing() -> bool:
	return _music.playing or (_music_task >= 0 and _wanted_tune >= 0)


# ----------------------------------------------------------------------------
#  APUFUNKTIOT
# ----------------------------------------------------------------------------
static func _buf(seconds: float, rate: int = RATE) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * rate))
	b.fill(0.0)
	return b


static func _wav(buf: PackedFloat32Array, rate: int = RATE, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w


static func _normalize(b: PackedFloat32Array, peak: float = 0.9) -> PackedFloat32Array:
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in b.size():
		b[i] *= k
	return b


# ----------------------------------------------------------------------------
#  ÄÄNTEN SYNTEESI
# ----------------------------------------------------------------------------
## Nyrkki osuu: matala tömähdys + lyhyt rätinä.
func _gen_punch_hit() -> PackedFloat32Array:
	var b := _buf(0.16)
	var ph := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := lerpf(140.0, 45.0, minf(t / 0.08, 1.0))
		ph += TAU * f / RATE
		var body := sin(ph) * exp(-t * 28.0)
		lp += 0.35 * (randf_range(-1.0, 1.0) - lp)
		var crack := lp * exp(-t * 90.0) * 0.9
		b[i] = body + crack
	return _normalize(b)


## Huti: kohiseva suhahdus.
func _gen_whoosh() -> PackedFloat32Array:
	var b := _buf(0.15)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / b.size()
		var a := lerpf(0.05, 0.35, t)
		lp += a * (randf_range(-1.0, 1.0) - lp)
		lp2 += 0.5 * (lp - lp2)
		b[i] = (lp - lp2 * 0.6) * sin(PI * t)
	return _normalize(b, 0.5)


## Askel: pehmeä, matala napsahdus.
func _gen_step() -> PackedFloat32Array:
	var b := _buf(0.06)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += 0.18 * (randf_range(-1.0, 1.0) - lp)
		b[i] = lp * exp(-t * 70.0) + sin(TAU * 90.0 * t) * exp(-t * 60.0) * 0.4
	return _normalize(b, 0.6)


## Laukaus: terävä kohinapamaus + matala jysähdys.
func _gen_gun() -> PackedFloat32Array:
	var b := _buf(0.32)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += lerpf(0.9, 0.15, minf(t / 0.1, 1.0)) * (randf_range(-1.0, 1.0) - lp)
		b[i] = lp * exp(-t * 16.0) + sin(TAU * 70.0 * t) * exp(-t * 22.0) * 0.8
	return _normalize(b)


## Kolikko: kaksi korkeaa piippausta.
func _gen_coin() -> PackedFloat32Array:
	var b := _buf(0.16)
	for i in b.size():
		var t := float(i) / RATE
		var f := 1320.0 if t < 0.05 else 1760.0
		var env := exp(-maxf(t - (0.0 if t < 0.05 else 0.05), 0.0) * 25.0)
		b[i] = signf(sin(TAU * f * t)) * 0.3 * env
	return _normalize(b, 0.45)


## Lasi kilahtaa tiskiin.
func _gen_clink() -> PackedFloat32Array:
	var b := _buf(0.35)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (sin(TAU * 2450.0 * t) + 0.6 * sin(TAU * 3710.0 * t) + 0.3 * sin(TAU * 5300.0 * t)) * exp(-t * 14.0)
	return _normalize(b, 0.4)


## Oluttölkki aukeaa: "pssh".
func _gen_can() -> PackedFloat32Array:
	var b := _buf(0.4)
	var hp := 0.0
	var prev := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var x := randf_range(-1.0, 1.0)
		hp = 0.7 * (hp + x - prev)   # ylipäästö: kirkas sihinä
		prev = x
		var click := 0.0
		if t < 0.006:
			click = 1.0 - t / 0.006
		b[i] = hp * exp(-t * 7.0) * minf(t / 0.01, 1.0) * 0.6 + click
	return _normalize(b, 0.45)


## Kulaus: matala, kupliva "glug".
func _gen_gulp() -> PackedFloat32Array:
	var b := _buf(0.22)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 180.0 + 220.0 * sin(PI * t / 0.22)
		ph += TAU * f / RATE
		b[i] = sin(ph) * sin(PI * t / 0.22)
	return _normalize(b, 0.4)


## Kassakone: "ka-tsing".
func _gen_cash() -> PackedFloat32Array:
	var b := _buf(0.7)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += 0.6 * (randf_range(-1.0, 1.0) - lp)
		var click := lp * exp(-t * 60.0) * 0.8
		var tb := maxf(t - 0.07, 0.0)
		var bell := 0.0
		if t >= 0.07:
			bell = (sin(TAU * 2093.0 * tb) + 0.7 * sin(TAU * 2637.0 * tb) + 0.4 * sin(TAU * 4186.0 * tb)) * exp(-tb * 6.0)
		b[i] = click + bell * 0.5
	return _normalize(b, 0.5)


## Sellin ovi: raskas metallinen kalahdus.
func _gen_clang() -> PackedFloat32Array:
	var b := _buf(1.1)
	var lp := 0.0
	var partials := [[110.0, 1.0, 3.0], [263.0, 0.7, 4.0], [431.0, 0.5, 5.0], [697.0, 0.35, 7.0], [1130.0, 0.25, 9.0]]
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for p: Array in partials:
			v += sin(TAU * float(p[0]) * t) * float(p[1]) * exp(-t * float(p[2]))
		lp += 0.5 * (randf_range(-1.0, 1.0) - lp)
		v += lp * exp(-t * 40.0) * 1.2
		b[i] = v
	return _normalize(b, 0.7)


## Puhelin: kolme lyhyttä 425 Hz:n merkkiääntä (suomalainen soittoääni).
func _gen_phone() -> PackedFloat32Array:
	var b := _buf(0.9)
	for i in b.size():
		var t := float(i) / RATE
		var slot := fmod(t, 0.3)
		var on := 1.0 if slot < 0.16 else 0.0
		b[i] = sin(TAU * 425.0 * t) * on * 0.5
	return _normalize(b, 0.35)


## Ei onnistu: matala surina.
func _gen_denied() -> PackedFloat32Array:
	var b := _buf(0.25)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = signf(sin(TAU * 140.0 * t)) * 0.3 * (1.0 - t / 0.25)
	return _normalize(b, 0.3)


## Poliisin sireeni: kaksisävel (ii-aa), silmukka. Sävelet ovat kokonaisia jaksoja,
## joten silmukka saumautuu ilman napsahdusta.
func _gen_siren() -> PackedFloat32Array:
	var b := _buf(1.2)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 740.0 if t < 0.6 else 555.0
		ph += TAU * f / RATE
		# pyöristetty kanttiaalto (parittomat harmoniset)
		b[i] = sin(ph) + sin(ph * 3.0) / 3.0 + sin(ph * 5.0) / 5.0
	return _normalize(b, 0.6)


## Torjunta: tylppä tömähdys + napsahdus.
func _gen_block() -> PackedFloat32Array:
	var b := _buf(0.12)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * 70.0 * t) * exp(-t * 35.0) + randf_range(-1.0, 1.0) * exp(-t * 200.0) * 0.6
	return _normalize(b, 0.6)


## Sähköase: rätisevä surina.
func _gen_taser() -> PackedFloat32Array:
	var b := _buf(0.7)
	for i in b.size():
		var t := float(i) / RATE
		var buzz := signf(sin(TAU * 95.0 * t)) * 0.4
		var crackle := randf_range(-1.0, 1.0) * (1.0 if randf() < 0.08 else 0.15)
		b[i] = (buzz + crackle) * (1.0 - t / 0.7)
	return _normalize(b, 0.55)


## Lasi särkyy.
func _gen_glass_break() -> PackedFloat32Array:
	var b := _buf(0.6)
	var prev := 0.0
	var tinkles: Array = []
	for k in 10:
		tinkles.append([randf_range(0.0, 0.35), randf_range(2500.0, 6000.0)])
	for i in b.size():
		var t := float(i) / RATE
		var x := randf_range(-1.0, 1.0)
		var hp := x - prev
		prev = x
		var v := hp * exp(-t * 12.0) * 0.6
		for tk: Array in tinkles:
			var st: float = tk[0]
			if t >= st:
				v += sin(TAU * float(tk[1]) * (t - st)) * exp(-(t - st) * 30.0) * 0.25
		b[i] = v
	return _normalize(b, 0.55)


## Kolari: matala jysähdys, rätisevä pelti ja kilahtelevia metallinsiruja.
func _gen_crash() -> PackedFloat32Array:
	var b := _buf(0.7)
	var ph := 0.0
	var lp := 0.0
	var prev := 0.0
	var partials := [[180.0, 0.5, 9.0], [377.0, 0.35, 12.0], [610.0, 0.3, 14.0], [1290.0, 0.18, 18.0]]
	var rattles: Array = []
	for k in 7:
		rattles.append([randf_range(0.04, 0.4), randf_range(1800.0, 4200.0)])
	for i in b.size():
		var t := float(i) / RATE
		var f := lerpf(110.0, 38.0, minf(t / 0.12, 1.0))
		ph += TAU * f / RATE
		var v := sin(ph) * exp(-t * 14.0) * 1.1
		var x := randf_range(-1.0, 1.0)
		lp += 0.25 * (x - lp)
		v += lp * exp(-t * 7.0) * 1.3
		var hp := x - prev
		prev = x
		v += hp * exp(-t * 22.0) * 0.5
		for p: Array in partials:
			v += sin(TAU * float(p[0]) * t) * float(p[1]) * exp(-t * float(p[2]))
		for r: Array in rattles:
			var st: float = r[0]
			if t >= st:
				v += sin(TAU * float(r[1]) * (t - st)) * exp(-(t - st) * 35.0) * 0.2
		b[i] = v
	return _normalize(b, 0.9)


## Tömähdys: vartalo osuu konepeltiin / maahan.
func _gen_thud() -> PackedFloat32Array:
	var b := _buf(0.22)
	var ph := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := lerpf(95.0, 40.0, minf(t / 0.1, 1.0))
		ph += TAU * f / RATE
		lp += 0.15 * (randf_range(-1.0, 1.0) - lp)
		b[i] = sin(ph) * exp(-t * 18.0) + lp * exp(-t * 30.0) * 0.8
	return _normalize(b, 0.85)


## Räjähdys: terävä pamaus, matala jyrinä ja rätisevä jälkikaiku.
func _gen_explosion() -> PackedFloat32Array:
	var b := _buf(1.8)
	var ph := 0.0
	var lp := 0.0
	var lp2 := 0.0
	var prev := 0.0
	var crackles: Array = []
	for k in 40:
		crackles.append([randf_range(0.05, 1.3), randf_range(0.3, 1.0)])
	for i in b.size():
		var t := float(i) / RATE
		# matala pamaus, joka laskee
		var f := lerpf(70.0, 26.0, minf(t / 0.35, 1.0))
		ph += TAU * f / RATE
		var v := sin(ph) * exp(-t * 3.2) * 1.2
		var x := randf_range(-1.0, 1.0)
		# jyrinä: voimakkaasti alipäästetty kohina
		lp += 0.06 * (x - lp)
		lp2 += 0.03 * (lp - lp2)
		v += lp2 * exp(-t * 1.8) * 5.0
		# terävä alku
		var hp := x - prev
		prev = x
		v += hp * exp(-t * 40.0) * 0.9
		v += lp * exp(-t * 6.0) * 1.2
		# palavan romun rätinä
		for c: Array in crackles:
			var st: float = c[0]
			if t >= st and t < st + 0.012:
				v += randf_range(-1.0, 1.0) * float(c[1]) * 0.35 * exp(-t * 1.5)
		b[i] = v * minf(t / 0.002, 1.0)
	return _normalize(b, 0.98)


## Syttyminen: humahdus (kohina, joka nousee ja laskee).
func _gen_ignite() -> PackedFloat32Array:
	var b := _buf(0.7)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += 0.12 * (randf_range(-1.0, 1.0) - lp)
		var env := minf(t / 0.08, 1.0) * exp(-maxf(t - 0.08, 0.0) * 4.5)
		b[i] = lp * env
	return _normalize(b, 0.7)


## Auton tööttäys: kaksi epävireistä sahalaitaa yhdessä.
func _gen_horn() -> PackedFloat32Array:
	var b := _buf(0.38)
	for i in b.size():
		var t := float(i) / RATE
		var a := minf(t / 0.02, 1.0) * minf((0.38 - t) / 0.04, 1.0)
		var s1 := fmod(t * 392.0, 1.0) * 2.0 - 1.0
		var s2 := fmod(t * 494.0, 1.0) * 2.0 - 1.0
		b[i] = (s1 + s2) * 0.5 * a
	return _normalize(b, 0.45)


## Autonovi: salvan naksahdus (+ kiinni: matala tömähdys).
func _gen_door(closing: bool) -> PackedFloat32Array:
	var b := _buf(0.28 if closing else 0.18)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		# kaksi metallista napsausta
		for c: float in ([0.0, 0.035] if not closing else [0.03, 0.06]):
			if t >= c:
				v += sin(TAU * 2400.0 * (t - c)) * exp(-(t - c) * 160.0) * 0.6
		if closing:
			lp += 0.12 * (randf_range(-1.0, 1.0) - lp)
			v += (sin(TAU * 70.0 * t) * 1.2 + lp * 1.5) * exp(-t * 22.0)
		else:
			# kevyt narahdus
			v += sin(TAU * (300.0 + 200.0 * t) * t) * 0.15 * exp(-t * 12.0) * minf(t / 0.03, 1.0)
		b[i] = v
	return _normalize(b, 0.7)


## Käynnistys: startti pyörittää kolme kertaa, sitten moottori käy ja kierrokset nousevat.
func _gen_engine_start() -> PackedFloat32Array:
	var b := _buf(1.3)
	var ph := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		if t < 0.6:
			# startin vinkuna sykkii
			var crank := 0.5 + 0.5 * sin(TAU * 5.0 * t)
			ph += TAU * (150.0 + 30.0 * crank) / RATE
			v = signf(sin(ph)) * 0.25 * crank
		else:
			var tt := t - 0.6
			var f := lerpf(35.0, 55.0, minf(tt / 0.3, 1.0)) - maxf(tt - 0.3, 0.0) * 15.0
			ph += TAU * f / RATE
			lp += 0.1 * (randf_range(-1.0, 1.0) - lp)
			var fire := pow(absf(sin(ph * 0.5)), 6.0)
			v = (fmod(ph / TAU, 1.0) * 2.0 - 1.0) * 0.6 + fire * 0.8 + lp * 0.5
			v *= minf(tt / 0.05, 1.0) * (1.0 - maxf(tt - 0.5, 0.0) / 0.2)
		b[i] = v
	return _normalize(b, 0.7)


## Moottorin silmukka (0.5 s, saumaton): matala sahalaita + sytytysiskut.
func _gen_engine_loop() -> PackedFloat32Array:
	var b := _buf(0.5)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var saw := fmod(t * 42.0, 1.0) * 2.0 - 1.0
		var fire := pow(absf(sin(TAU * 21.0 * t)), 8.0)
		lp += 0.08 * (randf_range(-1.0, 1.0) - lp)
		b[i] = saw * 0.5 + fire * 0.9 + sin(TAU * 84.0 * t) * 0.2 + lp * 0.3
	return _normalize(b, 0.6)


## Renkaiden kirskunta: kapea korkea kohina, joka värisee.
func _gen_screech() -> PackedFloat32Array:
	var b := _buf(0.6)
	var y1 := 0.0
	var y2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 1900.0 + 220.0 * sin(TAU * 13.0 * t)
		var w := TAU * f / RATE
		var r := 0.995
		var x := randf_range(-1.0, 1.0)
		var y := x * 0.05 + 2.0 * r * cos(w) * y1 - r * r * y2
		y2 = y1
		y1 = y
		b[i] = y * minf(t / 0.03, 1.0) * minf((0.6 - t) / 0.15, 1.0)
	return _normalize(b, 0.5)


## Ihmisääni (huudahdus/kiljaisu): sahalaita formanttisuotimen läpi, sävel laskee.
func _gen_voice(f0: float, f1: float, dur: float, formant: float) -> PackedFloat32Array:
	var b := _buf(dur)
	var ph := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var z1 := 0.0
	var z2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var k := t / dur
		var f := lerpf(f0, f1, k) * (1.0 + 0.03 * sin(TAU * 7.0 * t))
		ph += f / RATE
		var x := (fmod(ph, 1.0) * 2.0 - 1.0) + randf_range(-0.15, 0.15)
		var w1 := TAU * formant / RATE
		var y := x * 0.1 + 2.0 * 0.97 * cos(w1) * y1 - 0.97 * 0.97 * y2
		y2 = y1
		y1 = y
		var w2 := TAU * formant * 2.4 / RATE
		var z := x * 0.06 + 2.0 * 0.96 * cos(w2) * z1 - 0.96 * 0.96 * z2
		z2 = z1
		z1 = z
		b[i] = (y + z * 0.6) * minf(t / 0.02, 1.0) * pow(1.0 - k, 0.7)
	return _normalize(b, 0.6)


## Lintu: muutama nopea korkea liukusävel.
func _gen_bird() -> PackedFloat32Array:
	var b := _buf(0.7)
	var chirps: Array = []
	var st := 0.0
	for k in randi_range(2, 4):
		chirps.append([st, randf_range(0.05, 0.09), randf_range(2600.0, 3600.0), randf_range(800.0, 1600.0)])
		st += randf_range(0.1, 0.18)
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for c: Array in chirps:
			var s0: float = c[0]
			var d: float = c[1]
			if t >= s0 and t < s0 + d:
				var u := (t - s0) / d
				var f: float = float(c[2]) + float(c[3]) * sin(PI * u)
				v += sin(TAU * f * (t - s0)) * sin(PI * u)
		b[i] = v
	return _normalize(b, 0.4)


## Koira haukkuu kahdesti.
func _gen_bark() -> PackedFloat32Array:
	var b := _buf(0.6)
	var y1 := 0.0
	var y2 := 0.0
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for s0: float in [0.0, 0.28]:
			var tt := t - s0
			if tt >= 0.0 and tt < 0.16:
				var f := lerpf(480.0, 260.0, tt / 0.16)
				ph += f / RATE
				var x := (fmod(ph, 1.0) * 2.0 - 1.0) * 0.7 + randf_range(-0.5, 0.5)
				v += x * exp(-tt * 14.0) * minf(tt / 0.01, 1.0)
		var w := TAU * 900.0 / RATE
		var y := v * 0.15 + 2.0 * 0.93 * cos(w) * y1 - 0.93 * 0.93 * y2
		y2 = y1
		y1 = y
		b[i] = y + v * 0.3
	return _normalize(b, 0.55)


## Kaukainen sireeni: muutama ulvonta, vaimea ja tasainen.
func _gen_far_siren() -> PackedFloat32Array:
	var b := _buf(2.6)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 700.0 + 220.0 * sin(TAU * 0.8 * t)
		ph += f / RATE
		var env := minf(t / 0.6, 1.0) * minf((2.6 - t) / 0.8, 1.0)
		b[i] = sin(TAU * ph) * env
	return _normalize(b, 0.35)


## Liikenteen humina (silmukka 3 s): matala suodatettu kohina ja hiljainen jyrinä.
func _gen_city_hum() -> PackedFloat32Array:
	var b := _buf(3.0)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += 0.02 * (randf_range(-1.0, 1.0) - lp)
		lp2 += 0.2 * (randf_range(-1.0, 1.0) - lp2)
		var swell := 0.75 + 0.25 * sin(TAU * t / 3.0)
		b[i] = lp * 6.0 * swell + lp2 * 0.08
	# saumaton silmukka: häivytetään alku ja loppu ristiin
	var n := int(0.25 * RATE)
	for i in n:
		var k := float(i) / n
		var a := b[i]
		var z := b[b.size() - n + i]
		b[i] = a * k + z * (1.0 - k)
	return _normalize(b, 0.5)


## Sade: pehmeä kohina (silmukka).
func _gen_rain() -> PackedFloat32Array:
	var b := _buf(2.0)
	var lp := 0.0
	for i in b.size():
		lp += 0.25 * (randf_range(-1.0, 1.0) - lp)
		var drop := 0.0
		if randf() < 0.002:
			drop = randf_range(0.3, 0.8)
		b[i] = lp + drop * randf_range(-1.0, 1.0)
	return _normalize(b, 0.5)


## Ukkonen: matala, vyöryvä jyrinä.
func _gen_thunder() -> PackedFloat32Array:
	var b := _buf(3.2)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += 0.04 * (randf_range(-1.0, 1.0) - lp)
		lp2 += 0.08 * (lp - lp2)
		var env := minf(t / 0.08, 1.0) * exp(-t * 1.1) * (0.7 + 0.3 * sin(t * 9.0) * sin(t * 2.3))
		var crack := randf_range(-1.0, 1.0) * exp(-t * 25.0) * 0.4
		b[i] = lp2 * env * 6.0 + crack
	return _normalize(b, 0.85)


## Tikka osuu tauluun.
func _gen_dart() -> PackedFloat32Array:
	var b := _buf(0.12)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (sin(TAU * 900.0 * t) * 0.3 + randf_range(-1.0, 1.0) * 0.6) * exp(-t * 60.0)
	return _normalize(b, 0.5)


## Biljardipallot kopsahtavat.
func _gen_pool() -> PackedFloat32Array:
	var b := _buf(0.15)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (sin(TAU * 1800.0 * t) + 0.5 * sin(TAU * 3100.0 * t)) * exp(-t * 45.0)
	return _normalize(b, 0.5)


# ----------------------------------------------------------------------------
#  JUKEBOKSIN MUSIIKKI (lasketaan taustasäikeessä)
# ----------------------------------------------------------------------------
func _build_tunes() -> void:
	# päävalikon kappale ensin, jotta se soi heti käynnistyksessä
	_bgm_tracks = {"menu": _wav(_gen_bgm("menu"), MUSIC_RATE, true)}
	var list: Array[AudioStreamWAV] = []
	list.append(_wav(_gen_tune(0), MUSIC_RATE, true))
	list.append(_wav(_gen_tune(1), MUSIC_RATE, true))
	_tunes = list
	var bgm := {"menu": _bgm_tracks["menu"]}
	for id: String in ["city", "cutscene"]:
		bgm[id] = _wav(_gen_bgm(id), MUSIC_RATE, true)
	_bgm_tracks = bgm


## Lisää sävelen puskuriin. wave: 0 = sini, 1 = haitari (kaksi hieman eri vireistä
## pulssiaaltoa), 2 = basso (pehmeä kolmio).
func _note(start: float, dur: float, midi: float, amp: float, wave: int) -> void:
	var f := 440.0 * pow(2.0, (midi - 69.0) / 12.0)
	var s0 := int(start * MUSIC_RATE)
	var n := int(dur * MUSIC_RATE)
	var rel := mini(int(0.03 * MUSIC_RATE), n / 2)
	for k in n:
		var i := s0 + k
		if i >= _mb.size():
			break
		var t := float(k) / MUSIC_RATE
		var env := minf(float(k) / 40.0, 1.0)
		if k > n - rel:
			env *= float(n - k) / float(rel)
		var v := 0.0
		match wave:
			0:
				v = sin(TAU * f * t)
			1:
				var p1 := fmod(f * t, 1.0)
				var p2 := fmod(f * 1.006 * t, 1.0)
				v = (0.5 if p1 < 0.35 else -0.5) + (0.5 if p2 < 0.35 else -0.5)
				v *= 0.6
			2:
				var p := fmod(f * t, 1.0)
				v = 4.0 * absf(p - 0.5) - 1.0
		_mb[i] += v * amp * env


func _drum(start: float, kick: bool, amp: float) -> void:
	var s0 := int(start * MUSIC_RATE)
	var n := int((0.18 if kick else 0.09) * MUSIC_RATE)
	var lp := 0.0
	var ph := 0.0
	for k in n:
		var i := s0 + k
		if i >= _mb.size():
			break
		var t := float(k) / MUSIC_RATE
		if kick:
			ph += TAU * lerpf(110.0, 45.0, minf(t / 0.1, 1.0)) / MUSIC_RATE
			_mb[i] += sin(ph) * exp(-t * 22.0) * amp
		else:
			# säieturvallinen pseudokohina (ei globaalia satunnaislukugeneraattoria)
			var noise := fmod(sin(float(i) * 12.9898) * 43758.5453, 1.0) * 2.0
			lp += 0.7 * (noise - lp)
			_mb[i] += lp * exp(-t * 45.0) * amp * 0.6


## tune 0 = humppa (A-molli, 140 bpm), tune 1 = tango (D-molli, 104 bpm).
func _gen_tune(tune: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 + tune * 77
	# soinnut: [basson pohjasävel, soinnun sävelet]
	var chords := {
		"Am": [45, [57, 60, 64]], "Dm": [38, [57, 62, 65]], "E": [40, [56, 59, 64]],
		"Gm": [43, [55, 58, 62]], "A": [45, [57, 61, 64]], "C": [48, [55, 60, 64]],
	}
	var prog: Array
	var bpm: float
	if tune == 0:
		prog = ["Am", "Am", "Dm", "Am", "E", "E", "Am", "Am", "C", "C", "Dm", "Am", "Dm", "E", "Am", "Am"]
		bpm = 140.0
	else:
		prog = ["Dm", "Dm", "A", "A", "A", "A", "Dm", "Dm", "Gm", "Gm", "Dm", "Dm", "A", "A", "Dm", "Dm"]
		bpm = 104.0
	var beat := 60.0 / bpm
	var bar := beat * 4.0
	_mb = _buf(bar * prog.size(), MUSIC_RATE)

	var melody_prev := 72
	for bi in prog.size():
		var ch: Array = chords[prog[bi]]
		var root: int = ch[0]
		var tones: Array = ch[1]
		var t0 := bi * bar
		if tune == 0:
			# Humppa: umpa-umpa. Basso iskuilla 1 ja 3, sointu iskuilla 2 ja 4
			_note(t0, beat * 0.8, root, 0.55, 2)
			_note(t0 + beat * 2.0, beat * 0.8, root + 7, 0.5, 2)
			for off: float in [1.0, 3.0]:
				for m: int in tones:
					_note(t0 + beat * off, beat * 0.45, m, 0.12, 1)
			_drum(t0, true, 0.5)
			_drum(t0 + beat * 2.0, true, 0.45)
			_drum(t0 + beat, false, 0.45)
			_drum(t0 + beat * 3.0, false, 0.45)
		else:
			# Tango: basso 3-3-2-rytmillä, haitarisointu taustalla
			for e: float in [0.0, 1.5, 3.0]:
				_note(t0 + beat * e, beat * 0.5, root + (7 if e == 1.5 else 0), 0.55, 2)
			for m: int in tones:
				_note(t0, bar * 0.95, m - 12, 0.05, 1)
			_drum(t0, true, 0.4)
			_drum(t0 + beat * 1.5, true, 0.3)
			_drum(t0 + beat * 3.0, false, 0.35)

		# Melodia: soinnun säveliä oktaavi ylempänä, kahdeksasosia ja neljäsosia
		var pos := 0.0
		while pos < 4.0 - 0.01:
			var step := 0.5 if rng.randf() < 0.6 else 1.0
			if tune == 1 and rng.randf() < 0.3:
				step = 1.5
			step = minf(step, 4.0 - pos)
			if rng.randf() < 0.85:
				var cands: Array[int] = []
				for m: int in tones:
					for o: int in [12, 24]:
						cands.append(m + o)
				# valitaan lähin sävel edellisestä (laulava melodia), välillä hyppy
				cands.sort_custom(func(a: int, c: int) -> bool: return absi(a - melody_prev) < absi(c - melody_prev))
				var pick: int = cands[mini(rng.randi_range(0, 2), cands.size() - 1)]
				_note(t0 + pos * beat, step * beat * 0.92, pick, 0.22, 1 if tune == 0 else 0)
				melody_prev = pick
			pos += step
	var out := _normalize(_mb, 0.8)
	_mb = PackedFloat32Array()
	return out


# ----------------------------------------------------------------------------
#  TAUSTAMUSIIKKI (BGM): päävalikko, kaupunki ja välianimaatiot
# ----------------------------------------------------------------------------
## Sävel pehmeällä alulla ja lopulla. wave: 2 = basso, 3 = matto (pad), 4 = sähköpiano, 5 = näppäily
func _tone(start: float, dur: float, midi: float, amp: float, wave: int, attack: float = 0.01, release: float = 0.08) -> void:
	var f := 440.0 * pow(2.0, (midi - 69.0) / 12.0)
	var s0 := int(start * MUSIC_RATE)
	var n := int(dur * MUSIC_RATE)
	var a := maxi(int(attack * MUSIC_RATE), 1)
	var r := mini(maxi(int(release * MUSIC_RATE), 1), n)
	for k in n:
		var i := s0 + k
		if i >= _mb.size():
			break
		var t := float(k) / MUSIC_RATE
		var env := minf(float(k) / float(a), 1.0)
		if k > n - r:
			env *= float(n - k) / float(r)
		var v := 0.0
		match wave:
			2:
				var p := fmod(f * t, 1.0)
				v = (4.0 * absf(p - 0.5) - 1.0) * 0.8 + sin(TAU * f * t) * 0.4
			3:
				v = (sin(TAU * f * t) + sin(TAU * f * 1.004 * t + 1.0) * 0.8 + sin(TAU * f * 2.0 * t) * 0.25) * 0.45
				v *= 0.85 + 0.15 * sin(TAU * 0.4 * t)
			4:
				v = (sin(TAU * f * t) + 0.35 * sin(TAU * f * 3.0 * t) * exp(-t * 6.0)) * exp(-t * 2.2)
			5:
				var p2 := fmod(f * t, 1.0)
				v = (4.0 * absf(p2 - 0.5) - 1.0) * exp(-t * 7.0)
		_mb[i] += v * amp * env


## Hi-hat: lyhyt korkea kohina.
func _hat(start: float, amp: float) -> void:
	var s0 := int(start * MUSIC_RATE)
	var n := int(0.04 * MUSIC_RATE)
	var prev := 0.0
	for k in n:
		var i := s0 + k
		if i >= _mb.size():
			break
		var noise := fmod(sin(float(i) * 78.233) * 12543.5453, 1.0) * 2.0
		var hp := noise - prev
		prev = noise
		_mb[i] += hp * 0.25 * amp * exp(-float(k) / float(n) * 4.0)


func _gen_bgm(id: String) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	# [basson sävel, soinnun sävelet]
	var chords := {
		"Am": [45, [57, 60, 64]], "Fmaj7": [41, [57, 60, 64, 65]], "Dm": [38, [57, 62, 65]], "E": [40, [56, 59, 64]],
		"Dm7": [38, [60, 62, 65, 69]], "G7": [43, [59, 62, 65, 67]], "Cmaj7": [36, [59, 60, 64, 67]], "Am7": [45, [60, 64, 67, 69]],
		"Em": [40, [55, 59, 64]], "C": [36, [55, 60, 64]], "B": [47, [54, 59, 63]],
	}
	var prog: Array
	var bpm := 84.0
	match id:
		"menu":
			prog = ["Am", "Fmaj7", "Dm", "E", "Am", "Fmaj7", "Dm", "E"]
			bpm = 84.0
		"city":
			prog = ["Dm7", "G7", "Cmaj7", "Am7", "Dm7", "G7", "Cmaj7", "Am7", "Dm7", "G7", "Cmaj7", "Am7", "Dm7", "G7", "Em", "Am7"]
			bpm = 88.0
		_:
			prog = ["Em", "C", "Am", "B", "Em", "C", "Am", "B"]
			bpm = 66.0
	var beat := 60.0 / bpm
	var bar := beat * 4.0
	_mb = _buf(bar * prog.size() + 0.05, MUSIC_RATE)
	var pent := [62, 65, 67, 69, 72, 74, 77]   # D-molli pentatoninen (kaupungin melodia)
	for bi in prog.size():
		var ch: Array = chords[prog[bi]]
		var root: int = ch[0]
		var tones: Array = ch[1]
		var t0 := bi * bar
		match id:
			"menu":
				# Noir-synth: matto, basso iskuilla 1 ja 3, sähköpianon arpeggio, pehmeä rumpu
				for m: int in tones:
					_tone(t0, bar, m - 12, 0.07, 3, 0.6, 0.6)
				_tone(t0, beat * 1.8, root, 0.42, 2, 0.01, 0.2)
				_tone(t0 + beat * 2.0, beat * 1.8, root, 0.36, 2, 0.01, 0.2)
				for e in 8:
					var m2: int = tones[e % tones.size()] + (12 if e >= 4 else 0)
					_tone(t0 + e * beat * 0.5, beat * 0.5, m2, 0.11, 4, 0.005, 0.1)
				_drum(t0, true, 0.35)
				_drum(t0 + beat * 2.0, false, 0.2)
				for h in 4:
					_hat(t0 + (h + 0.5) * beat, 0.5)
			"city":
				# Lo-fi kävelygroove: sähköpianon synkooppisoinnut, walking-basso, kevyet rummut
				var sw := beat * 0.08   # svengi
				for off: float in [0.0, 1.5]:
					for m: int in tones:
						_tone(t0 + off * beat, beat * 1.3, m, 0.07, 4, 0.005, 0.2)
				var walk := [root, root + 7, root + 12, root + 10]
				for k in 4:
					_tone(t0 + k * beat, beat * 0.9, walk[k], 0.38, 2, 0.01, 0.12)
				_drum(t0, true, 0.4)
				_drum(t0 + beat * 2.5 + sw, true, 0.3)
				_drum(t0 + beat, false, 0.28)
				_drum(t0 + beat * 3.0, false, 0.28)
				for h in 8:
					_hat(t0 + h * beat * 0.5 + (sw if h % 2 == 1 else 0.0), 0.6 if h % 2 == 0 else 0.35)
				# harva melodia pentatonisella asteikolla
				var pos := 0.0
				while pos < 3.99:
					var step := 0.5 if rng.randf() < 0.55 else 1.0
					if rng.randf() < 0.55:
						var note: int = pent[rng.randi_range(0, pent.size() - 1)]
						_tone(t0 + pos * beat + (sw if fmod(pos, 1.0) > 0.1 else 0.0), beat * step * 0.9, note, 0.13, 5, 0.005, 0.1)
					pos += step
			_:
				# Välianimaatio: jännittävä matto, sykkivä basso, kellomainen melodia, patarumpu
				for m: int in tones:
					_tone(t0, bar, m - 12, 0.08, 3, 1.0, 0.8)
				for e in 8:
					_tone(t0 + e * beat * 0.5, beat * 0.45, root, 0.22 if e % 2 == 0 else 0.14, 2, 0.01, 0.08)
				_drum(t0, true, 0.45)
				if bi % 2 == 1:
					_drum(t0 + beat * 3.5, true, 0.3)
				if rng.randf() < 0.8:
					var bell: int = tones[rng.randi_range(0, tones.size() - 1)] + 12
					_tone(t0 + beat * float(rng.randi_range(0, 2)), beat * 1.5, bell, 0.12, 4, 0.005, 0.4)
	var out := _normalize(_mb, 0.75)
	_mb = PackedFloat32Array()
	return out
