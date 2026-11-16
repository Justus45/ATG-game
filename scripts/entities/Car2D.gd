extends CharacterBody2D

@export var speed: float = 250.0 # Auton ajonopeus
var driver: CharacterBody2D = null
var is_driving: bool = false
var exit_cooldown: float = 0.0
## true = auto kuuluu jollekin muulle (esim. parkkipaikan auto): ensimmäinen
## sisään nouseminen on auton varastus ja nostaa etsintäkuulutuksen.
var is_npc_owned: bool = false
var _drunk_t := 0.0

const CarFXScript := preload("res://scripts/entities/CarFX.gd")
const CarFireScript := preload("res://scripts/entities/CarFire.gd")
const ExplosionScript := preload("res://scripts/core/Explosion.gd")

# --- Kolarit ja vauriot. SÄÄDÄ NÄITÄ ---
const MAX_HEALTH := 100.0
const PROP_KNOCK_SPEED := 45.0     ## tätä kovempaa ajaessa katukaluste irtoaa ja lentää
const CRASH_MIN_SPEED := 120.0      ## tätä hitaampi kosketus (px/s törmäyssuunnassa) ei ole kolari
const CRASH_DAMAGE := 0.045        ## vahinko / (px/s) kynnyksen yli
const BOUNCE := 0.35               ## kuinka paljon auto kimpoaa takaisin (0 = ei lainkaan)
const KNOCK_FRICTION := 420.0      ## kuinka nopeasti töytäisy hiipuu (px/s²)
const SMOKE_BELOW := 0.5           ## alle tämän kunnon (osuus) konepelti savuaa

# --- Ajotuntuma. SÄÄDÄ NÄITÄ ---
## Auto osoittaa aina yhteen neljästä suunnasta (kuvat). Kaasu = nuoli auton keulan suuntaan,
## jarru / peruutus = vastakkainen nuoli, käännös = sivunuoli, vino nuoli = kaistanvaihto.
const ACCEL := 430.0               ## kiihtyvyys paikaltaan (px/s²); hiipuu huippunopeutta kohti
const BRAKE := 760.0               ## jarrutus (px/s²)
const COAST := 80.0               ## rullausvastus + moottorijarrutus ilman kaasua (px/s²)
const REVERSE_MAX := 0.38          ## peruutuksen huippunopeus (osuus huippunopeudesta)
const LATERAL_GRIP := 16.0         ## kuinka nopeasti sivuluisu pysähtyy kuivalla tiellä (1/s)
const HANDBRAKE_GRIP := 1.2        ## ... käsijarru pohjassa (Shift): auto luisuu
const HANDBRAKE_DECEL := 260.0     ## käsijarrun hidastus (px/s²)
const STEER_LATERAL := 0.16        ## vino nuoli: sivuttaisnopeus osuutena ajonopeudesta (kaistanvaihto)
const TURN_KEEP_SLOW := 0.98       ## käännöksessä säilyvä vauhti hitaasti ajaessa
const TURN_KEEP_FAST := 0.88        ## ... täydessä vauhdissa (loput menee luisuun / kitkaan)
const TURN_SLIDE := 0.06           ## kuinka suuri osa vanhasta vauhdista jatkaa luisuna käännöksen jälkeen
const TURN_COOLDOWN := 0.14         ## vähimmäisaika kahden käännöksen välillä (s)
const TURN_HOLD_SLOW := 0.02      ## sivunuolta pidettävä näin kauan ennen käännöstä hitaasti ajaessa (s)
const TURN_HOLD_FAST := 0.05      ## ... täydessä vauhdissa (estää vahinkokäännökset)
const SKID_SLIP := 55.0
const TURN_ASSIST := 12.0           ## käännösavustin: auto siirtyy enintään näin monta px, jotta käännös mahtuu
const LANE_ASSIST := 0.0           ## kaistakeskitys: auto hakeutuu kevyesti tieruudun keskelle (1/s, 0 = pois)
const LANE_ASSIST_MAX := 7.0
const UTURN_SPEED := 45.0          ## tätä hitaammin vastakkainen nuoli kääntää auton ympäri (px/s)
const TURN_VISUAL := 0.0          ## käännöksessä kuva lähtee näin suuresta osasta vanhaa kulmaa ja kääntyy pehmeästi perille
const TURN_VISUAL_RATE := 13.0     ## kuinka nopeasti kuva kääntyy perille (1/s)
const DRIFT_LEAN := 0.0            ## luisussa kuva kallistuu kulkusuuntaan (osuus todellisesta kulmasta)
const DRIFT_LEAN_MAX := 0.22       ## ... enintään (rad)
var _visual_rot := 0.0       ## ... vain jos poikkeama on tätä pienempi (px)            ## tätä suurempi sivuluisu (px/s) kirskuu ja jättää jarrutusjäljet

const BURN_TIME := 5.0             ## kuinka kauan auto palaa ennen räjähdystä (s)
const BURN_HIT_SPEEDUP := 0.04     ## palavaan autoon osuva vahinko lyhentää paloaikaa (s / vahinkopiste)

var health := MAX_HEALTH

## Nimi luksustallin kyltissä
var display_name := "Oma auto"
## Pelaajan oma keltainen taksi: vain sillä voi tehdä taksityötä (TaxiJob.gd)
var is_taxi := false


## Pysäköi paikalleen (luksustalli): seis, annettu suunta, ei luisua.
func park_at(pos: Vector2, anim: StringName = &"car_down") -> void:
	_visual_rot = 0.0
	animated_sprite.rotation = 0.0
	velocity = Vector2.ZERO
	_drive_vel = Vector2.ZERO
	_knock = Vector2.ZERO
	_skid_prev.clear()
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(anim):
		animated_sprite.animation = anim
	animated_sprite.stop()
	_apply_shape(_is_vertical_anim(animated_sprite.animation), true)
	_heading = _anim_heading(animated_sprite.animation)
	global_position = pos


## Siirtää ajettavan auton paikkaan ja jatkaa ajoa annetulla vauhdilla (tallista ulos).
func launch_at(pos: Vector2, anim: StringName, spd: float) -> void:
	park_at(pos, anim)
	_drive_vel = _heading * spd
## Kiihtyvyyden kerroin (superauto kiihtyy rajusti)
var accel_mult := 1.0

# --- SUPERAUTO (torin Auto-Make tuo tilauksesta) ---
const SUPERCAR_SPEED := 430.0
const SUPERCAR_ACCEL := 2.0
var is_supercar := false

# --- KLASSIKKO (torin Auto-Make): musta 80-luvun baijerilainen coupe, matala, kultaiset ristipinnavanteet ---
const CLASSIC_SPEED := 330.0
const CLASSIC_ACCEL := 1.35
var is_classic := false

static var _model_frames := {}   # mallin nimi -> SpriteFrames


## Erikoisautojen kuvat: res://assets/sprites/vehicles/<malli>_<suunta>_hd.png (2x),
## piirretään puolikkaan kokoisina (HDTex). 1x-kuva CarFX:n rengasanalyysiin.
static func model_frames(model: String) -> SpriteFrames:
	if _model_frames.has(model):
		return _model_frames[model]
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	for d: String in ["left", "down", "up", "right"]:
		var img := _load_image("res://assets/sprites/vehicles/%s_%s_hd.png" % [model, d])
		if img == null:
			continue
		# 1x-kuva renkaiden tunnistukseen (CarFX pyörittää renkaita ajaessa). Erillinen
		# <malli>_<suunta>.png on tehty sitä varten; muuten puolitetaan HD-kuva.
		var lo := _load_image("res://assets/sprites/vehicles/%s_%s.png" % [model, d])
		if lo == null or lo.get_size() * 2 != img.get_size():
			lo = img.duplicate() as Image
			lo.resize(maxi(img.get_width() / 2, 1), maxi(img.get_height() / 2, 1), Image.INTERPOLATE_NEAREST)
		var t: ImageTexture = preload("res://scripts/core/HDTex.gd").make(img, lo)
		var n := "car_" + d
		sf.add_animation(n)
		sf.set_animation_loop(n, false)
		sf.add_frame(n, t)
	if not sf.get_animation_names().is_empty():
		_model_frames[model] = sf
	return sf


static func _load_image(path: String) -> Image:
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			img = tex.get_image()
	if img == null and FileAccess.file_exists(path):
		# kuvaa ei ole vielä tuotu editorissa: luetaan PNG suoraan
		img = Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


static func supercar_frames() -> SpriteFrames:
	return model_frames("supercar")


static func classic_frames() -> SpriteFrames:
	return model_frames("classic")


## Muuttaa tämän auton superautoksi (kutsutaan add_child:n jälkeen).
func make_supercar() -> void:
	is_supercar = true
	display_name = "Furia V12"
	speed = SUPERCAR_SPEED
	accel_mult = SUPERCAR_ACCEL
	add_to_group("supercar")
	var anim := animated_sprite.animation
	animated_sprite.sprite_frames = supercar_frames()
	animated_sprite.animation = anim if animated_sprite.sprite_frames.has_animation(anim) else &"car_right"
	_apply_shape(_is_vertical_anim(animated_sprite.animation), true)


## Muuttaa tämän auton klassikoksi (kutsutaan add_child:n jälkeen).
func make_classic() -> void:
	is_classic = true
	display_name = "Bemari 635 CSi"
	speed = CLASSIC_SPEED
	accel_mult = CLASSIC_ACCEL
	add_to_group("classic")
	var anim := animated_sprite.animation
	animated_sprite.sprite_frames = classic_frames()
	animated_sprite.animation = anim if animated_sprite.sprite_frames.has_animation(anim) else &"car_right"
	_apply_shape(_is_vertical_anim(animated_sprite.animation), true)


## Auton keulan suunta (yksi neljästä) ja ajon tila
var _heading := Vector2.RIGHT
var _turn_cd := 0.0
var _turn_hold := 0.0              ## kuinka kauan sivunuolta on pidetty (s)
var _turn_dir := Vector2.ZERO
var _input_s := Vector2.ZERO       ## humalaisen viiveellä reagoiva ohjaus
var _slip := 0.0                   ## sivuluisun / lukkojarrutuksen voimakkuus (px/s), äänet ja jäljet
var _skid_prev: Array = []         ## edelliset takarenkaiden paikat jarrutusjälkiä varten
const SkidMarksScript := preload("res://scripts/entities/SkidMarks.gd")
var wrecked := false

# --- Äänet: moottori (silmukka, sävel nopeuden mukaan) ja renkaiden kirskunta ---
var _engine: AudioStreamPlayer2D
var _engine_level := 0.0
var _screech_cd := 0.0
var _prev_vel := Vector2.ZERO
## Auto palaa (kunto loppui) ja räjähtää kun _burn_t loppuu
var burning := false
## Auto on räjähtänyt: palanut romu
var exploded := false
var _burn_t := 0.0
var _fire = null   # CarFire.gd
## Viimeisin vahinko tuli pelaajalta (räjähdyksen uhrit ovat pelaajan rikoksia)
var _by_player := false
## Ulkoinen töytäisy (kolari, poliisin rammaus): lisätään ajonopeuteen ja hiipuu pois
var _knock := Vector2.ZERO
## Kuljettajan tavoittelema nopeus (ohjauksesta), ilman töytäisyjä
var _drive_vel := Vector2.ZERO
var _crash_cd := 0.0
var _knock_cd := 0.0
var _crash_t := 0.0                # > 0: ohjaus ei pure hetkeen kolarin jälkeen
var _smoke_acc := 0.0

## Törmäysmuoto käännetään auton suunnan mukaan (vaaka / pysty)
var _shape: RectangleShape2D
var _vertical := false

@onready var interaction_area: Area2D = $InteractionArea
@onready var exit_point: Marker2D = $ExitPoint
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	# tarkemmat (2x) autokuvat, jos car_*_hd.png on olemassa
	animated_sprite.sprite_frames = preload("res://scripts/core/HDTex.gd").upgrade_frames(animated_sprite.sprite_frames)
	add_to_group("player_vehicles")
	add_child(CarFXScript.new())  # pyörivät renkaat + pakokaasu
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	# Jokaisella autolla oma muoto (scenen muoto on jaettu kaikkien autojen kesken)
	_shape = (collision.shape as RectangleShape2D).duplicate()
	collision.shape = _shape
	_apply_shape(_is_vertical_anim(animated_sprite.animation), true)

func _physics_process(delta: float) -> void:
	_update_sounds(delta)
	_crash_cd = maxf(_crash_cd - delta, 0.0)
	_knock_cd = maxf(_knock_cd - delta, 0.0)
	_crash_t = maxf(_crash_t - delta, 0.0)
	_knock = _knock.move_toward(Vector2.ZERO, KNOCK_FRICTION * delta)
	_smoke(delta)
	if burning:
		_burn_t -= delta
		if _burn_t <= 0.0:
			_explode()
	# Pysäköidyn auton kuva voidaan vaihtaa ulkopuolelta (kaupungin generointi): muoto perässä
	if _is_vertical_anim(animated_sprite.animation) != _vertical:
		if not _apply_shape(not _vertical):
			animated_sprite.animation = &"car_down" if _vertical else &"car_right"

	if not is_driving:
		if animated_sprite:
			animated_sprite.stop()
		_drive_vel = Vector2.ZERO
		# Tönäisty pysäköity auto liukuu hetken
		if _knock.length() > 2.0:
			_move_with_crashes(_knock)
		else:
			velocity = Vector2.ZERO
		return

	if exit_cooldown > 0:
		exit_cooldown -= delta

	# Poliisi pysäyttänyt: auto seisoo, ei ajoa eikä poistuta
	if driver and driver.get("police_locked"):
		velocity = Vector2.ZERO
		_drive_vel = Vector2.ZERO
		animated_sprite.stop()
		return

	# Ohjaus WASD / nuolinäppäimillä: kaasu, jarru / peruutus, käännökset (_drive_step)
	var input_vector := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if wrecked:
		input_vector = Vector2.ZERO
	_turn_cd = maxf(_turn_cd - delta, 0.0)
	_drive_step(input_vector, Input.is_action_pressed("sprint") and not wrecked, delta)
	# Kolarin jälkeen ohjaus ei pure hetkeen: auto jatkaa kimpoamisen varassa
	var vel := _drive_vel
	if _crash_t > 0.0:
		vel *= 0.6
	_move_with_crashes(vel + _knock)
	_skid_marks()

	# Kuva keulan suunnan mukaan; renkaat pyörivät vauhdin mukaan
	var anim := _heading_anim(_heading)
	var moving := _drive_vel.length() > 4.0
	if animated_sprite.animation != anim:
		animated_sprite.play(anim)
	if moving:
		animated_sprite.speed_scale = clampf(absf(_drive_vel.dot(_heading)) / 120.0, 0.3, 2.0)
		if not animated_sprite.is_playing():
			animated_sprite.play()
	else:
		animated_sprite.stop()

	# Autosta poistuminen E-näppäimellä
	if Input.is_action_just_pressed("interact") and exit_cooldown <= 0:
		exit_car()

## Liikkuu ja tunnistaa kolarit seiniin ja muihin autoihin.
func _move_with_crashes(vel: Vector2) -> void:
	velocity = vel
	var pre := vel
	move_and_slide()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		var impact := -pre.dot(n)     # nopeus kohti estettä
		var other := col.get_collider()
		# Katukaluste (deco-tilemap): irtoaa ja lentää, jos vauhtia on tarpeeksi
		if other is TileMapLayer and impact > PROP_KNOCK_SPEED and _knock_prop(col, pre):
			continue
		if other is CharacterBody2D and other.has_method("apply_knock"):
			# Toinen pelaajan/pysäköity auto: osa vauhdista siirtyy siihen
			var rel: Vector2 = pre - (other as CharacterBody2D).velocity
			impact = -rel.dot(n)
			if impact > CRASH_MIN_SPEED * 0.6:
				other.apply_knock(-n * impact * 0.6, impact)
		if impact > CRASH_MIN_SPEED:
			crash(impact, n, other)
			break
		# Pieni kosketus: auto liukuu esteen pintaa pitkin ja menettää vauhtia
		if _drive_vel.dot(n) < 0.0:
			_drive_vel = _drive_vel.slide(n) * 0.97

## Törmäyskohdan kaluste irti (city_generator.knock_prop). Auto menettää vähän vauhtia.
func _knock_prop(col: KinematicCollision2D, pre: Vector2) -> bool:
	var city := get_tree().current_scene.get_node_or_null("City")
	if city == null or not city.has_method("knock_prop"):
		return false
	var layer := col.get_collider() as TileMapLayer
	if layer == null or layer != city.get("deco_layer"):
		return false
	# piste hieman esteen sisältä -> ruutu
	var p := col.get_position() - col.get_normal() * 2.0
	var cell := layer.local_to_map(layer.to_local(p))
	if not city.knock_prop(cell, pre):
		return false
	_drive_vel *= 0.8
	take_hit(1.0, is_driving)
	var cam := get_viewport().get_camera_2d()
	if is_driving and cam and cam.has_method("shake"):
		cam.shake(1.5)
	return true

## Kolari: kimpoaminen, vauriot, ääni, kipinät ja kameran tärähdys.
## normal osoittaa esteestä poispäin (kohti tätä autoa).
func crash(impact: float, normal: Vector2, _other: Object = null) -> void:
	if _crash_cd > 0.0:
		return
	_crash_cd = 0.3
	var hard := clampf((impact - CRASH_MIN_SPEED) / 220.0, 0.0, 1.0)
	_knock = normal * impact * BOUNCE + _knock.slide(normal)
	_drive_vel = _drive_vel.slide(normal) * 0.5
	velocity = _drive_vel + _knock
	_crash_t = lerpf(0.15, 0.55, hard)
	take_hit((impact - CRASH_MIN_SPEED) * CRASH_DAMAGE, is_driving)
	var at := global_position - normal * 9.0
	Sfx.play("crash", at, lerpf(-8.0, 2.0, hard), 0.12, lerpf(1.25, 0.85, hard))
	_sparks(at, normal, int(lerpf(5.0, 16.0, hard)))
	# Kori nytkähtää
	var tw := create_tween()
	tw.tween_property(animated_sprite, "rotation", randf_range(-0.12, 0.12) * (0.4 + hard), 0.05)
	tw.tween_property(animated_sprite, "rotation", 0.0, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if is_driving:
		var cam := get_viewport().get_camera_2d()
		if cam and cam.has_method("shake"):
			cam.shake(lerpf(1.5, 6.0, hard))

## Ulkoinen töytäisy (toinen auto törmää tähän). impact = törmäysnopeus.
func apply_knock(impulse: Vector2, impact: float = 0.0) -> void:
	if _knock_cd > 0.0:
		return
	_knock_cd = 0.25
	_knock += impulse
	if impact > CRASH_MIN_SPEED:
		take_hit((impact - CRASH_MIN_SPEED) * CRASH_DAMAGE * 0.8)
		if not is_driving:
			Sfx.play("crash", global_position, -6.0, 0.12)
			_sparks(global_position, impulse.normalized(), 6)

## Vahinkoa autolle. Kun kunto loppuu, auto syttyy palamaan ja räjähtää hetken päästä.
## by_player = vahingon aiheutti pelaaja (ammus, pelaajan ajama kolari, pelaajan räjäyttämä auto).
func take_hit(amount: float, by_player: bool = false) -> void:
	if amount <= 0.0 or exploded:
		return
	if by_player:
		_by_player = true
	if burning:
		# lisävahinko (luodit, toinen räjähdys) saa palavan auton räjähtämään nopeammin
		_burn_t -= amount * BURN_HIT_SPEEDUP
		return
	health = maxf(health - amount, 0.0)
	animated_sprite.modulate = Color(1.0, 1.0, 1.0).lerp(Color(0.55, 0.5, 0.48), 1.0 - health / MAX_HEALTH)
	if health <= 0.0:
		_ignite()

## Ammus osuu autoon (luodit kutsuvat body_entered -> take_damage).
func take_damage(amount: int = 1, source: Node = null) -> void:
	take_hit(float(amount) * 4.0, source != null and source.is_in_group("player"))

## Voiko autoon nousta?
func can_enter() -> bool:
	return not wrecked

func is_burning() -> bool:
	return burning

## Kunto osuutena (0..1).
func health_ratio() -> float:
	return health / MAX_HEALTH

## Voiko auton korjata (vaurioita, mutta ei pala eikä ole palanut romu)?
func needs_repair() -> bool:
	return not burning and not exploded and health < MAX_HEALTH

## Korjaussetti (RepairKit.gd): kunto täyteen, vauriot ja savu pois.
func repair() -> void:
	if burning or exploded:
		return
	health = MAX_HEALTH
	wrecked = false
	_smoke_acc = 0.0
	animated_sprite.modulate = Color.WHITE
	_update_prompt()

## Kunto loppui: auto syttyy palamaan. Moottori sammuu, ja räjähdys tulee BURN_TIME sekunnin päästä.
func _ignite() -> void:
	if burning or exploded:
		return
	burning = true
	wrecked = true
	_burn_t = BURN_TIME
	Sfx.play("glass_break", global_position, 0.0, 0.05)
	Sfx.play("ignite", global_position, 2.0, 0.08)
	_fire = CarFireScript.new()
	_fire.half = _shape.size * 0.5 * Vector2(0.75, 0.6)
	_fire.center = collision.position
	_fire.own_smoke = false   # tämä skripti tekee jo mustan savun (_smoke)
	add_child(_fire)
	_fire.set_level(CarFireScript.BURNING)
	if is_driving:
		_hud_message("Auto syttyi palamaan! Paina E ja juokse kauas!", 3.0)
	_update_prompt()

## Palava auto räjähtää: romu jää kytemään, lähellä olevat saavat vahinkoa.
func _explode() -> void:
	if exploded:
		return
	burning = false
	exploded = true
	wrecked = true
	_knock = Vector2.ZERO
	_drive_vel = Vector2.ZERO
	if _fire:
		_fire.set_level(CarFireScript.SMOLDER)
	# palanut romu
	animated_sprite.modulate = Color(0.22, 0.19, 0.18)
	var tw := create_tween()
	tw.tween_property(animated_sprite, "position:y", animated_sprite.position.y - 7.0, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(animated_sprite, "position:y", animated_sprite.position.y, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
	# kuljettaja lentää ulos (räjähdys hoitaa vahingon ja lennon)
	var victim := driver
	if is_driving and victim:
		exit_car()
		if victim.has_method("hurt"):
			victim.hurt(3.0, self)
	var ex := ExplosionScript.new()
	ex.source = self
	ex.by_player = _by_player
	var parent := get_parent()
	if parent:
		parent.add_child(ex)
		ex.global_position = collision.global_position
	_update_prompt()

## Päivittää ohjetekstin, jos pelaaja seisoo auton vieressä.
func _update_prompt() -> void:
	for body in interaction_area.get_overlapping_bodies():
		if body.has_method("enter_car") and body.get("current_car") == self:
			_on_body_entered(body)

## Auton törmäyslaatikko maailmassa (Impacts käyttää jalankulkijoihin osumiseen).
func hit_rect() -> Rect2:
	var sz := _shape.size
	return Rect2(collision.global_position - sz * 0.5, sz)

func is_vertical() -> bool:
	return _vertical

func _is_vertical_anim(anim: StringName) -> bool:
	return anim == &"car_up" or anim == &"car_down"

## Muoto auton kuvan mukaan. Palauttaa false, jos käännetty muoto ei mahdu (seinä tiellä).
func _apply_shape(vertical: bool, force: bool = false) -> bool:
	if vertical == _vertical and not force:
		return true
	var anim := &"car_down" if vertical else &"car_right"
	var tex: Texture2D = null
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(anim):
		tex = animated_sprite.sprite_frames.get_frame_texture(anim, 0)
	var tex_size := tex.get_size() if tex else (Vector2(16, 21) if vertical else Vector2(23, 16))
	# Kuvassa on ohut ääriviiva ja katon perspektiivi: muoto hieman kuvaa pienempi
	var new_size := Vector2(maxf(tex_size.x - 2.0, 8.0), maxf(tex_size.y - (3.0 if vertical else 4.0), 8.0))
	var new_pos := Vector2(0.0, 0.5 if vertical else 1.0)
	if not force and is_inside_tree():
		var test := RectangleShape2D.new()
		test.size = new_size
		var q := PhysicsShapeQueryParameters2D.new()
		q.shape = test
		q.transform = Transform2D(0.0, global_position + new_pos)
		q.collision_mask = collision_mask
		var excl: Array[RID] = [get_rid()]
		if driver:
			excl.append(driver.get_rid())
		q.exclude = excl
		if not get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty():
			return false
	_shape.size = new_size
	collision.position = new_pos
	_vertical = vertical
	return true

## Ajomalli: auton nopeus jaetaan keulan suuntaiseen osaan (kaasu / jarru / peruutus) ja
## sivuttaiseen osaan (luisu), jonka renkaiden pito vaimentaa. Sää vähentää pitoa,
## vauriot huippunopeutta, humala hidastaa reagointia ja saa auton mutkittelemaan.
func _drive_step(input_vector: Vector2, handbrake: bool, delta: float) -> void:
	var grip := Game.road_grip()
	var vmax := speed * Game.car_speed_mult() * lerpf(0.55, 1.0, health / MAX_HEALTH)
	# Humala: ohjaus reagoi viiveellä
	var k := 0.0
	if driver and driver.has_method("drunk_strength"):
		k = driver.drunk_strength()
	if k > 0.0:
		_input_s = _input_s.lerp(input_vector, clampf(delta * lerpf(20.0, 4.0, k), 0.0, 1.0))
	else:
		_input_s = input_vector
	var inp := _input_s if _input_s.length() > 0.2 else Vector2.ZERO

	var h := _heading
	var side := Vector2(-h.y, h.x)
	var fwd := _drive_vel.dot(h)
	var lat := _drive_vel.dot(side)

	# Käännös: pelkkä sivunuoli kääntää auton 90°. Vauhtia katoaa, ja osa jatkaa luisuna.
	# Sivunuolta pitää pitää hetki pohjassa (pidempään kovassa vauhdissa), jotta lyhyt
	# napautus tai näppäinten irrotusjärjestys ei käännä autoa vahingossa.
	var want_turn := inp != Vector2.ZERO and absf(inp.dot(h)) < 0.3
	var new_h := Vector2.ZERO
	if want_turn:
		new_h = Vector2(signf(inp.x), 0.0) if absf(inp.x) >= absf(inp.y) else Vector2(0.0, signf(inp.y))
		if new_h != _turn_dir:
			_turn_dir = new_h
			_turn_hold = 0.0
		_turn_hold += delta
	else:
		_turn_dir = Vector2.ZERO
		_turn_hold = 0.0
	var spd_ratio := clampf(_drive_vel.length() / maxf(vmax, 1.0), 0.0, 1.0)
	if want_turn and _turn_cd <= 0.0 and _turn_hold >= lerpf(TURN_HOLD_SLOW, TURN_HOLD_FAST, spd_ratio):
		var vertical := absf(new_h.y) > 0.5
		if vertical == _vertical or _apply_shape(vertical) or _turn_assist(vertical, h, new_h):
			var ratio := spd_ratio
			var keep := lerpf(TURN_KEEP_SLOW, TURN_KEEP_FAST, ratio * ratio)
			var slide := TURN_SLIDE * ratio * lerpf(1.6, 1.0, grip)
			if handbrake:
				# käsijarrukäännös: vauhti säilyy paremmin, mutta perä heittää enemmän
				keep = minf(keep + 0.15, 0.95)
				slide = minf(slide * 1.6, 0.9)
			var old := _drive_vel
			_visual_rot = -h.angle_to(new_h) * TURN_VISUAL
			_heading = new_h
			h = new_h
			side = Vector2(-h.y, h.x)
			fwd = absf(fwd) * keep * (1.0 if fwd >= 0.0 else 0.5)
			lat = old.dot(side) * slide
			_turn_cd = TURN_COOLDOWN

	var throttle := inp.dot(h)
	var steer := inp.dot(side)
	var braking := false
	if handbrake:
		if throttle < -0.2 and fwd < 30.0:
			# Shift + vastakkainen nuoli: peruutus (keula pysyy samaan suuntaan)
			fwd = move_toward(fwd, -vmax * REVERSE_MAX, ACCEL * 0.6 * delta)
		else:
			fwd = move_toward(fwd, 0.0, HANDBRAKE_DECEL * delta)
			braking = absf(fwd) > 20.0
	elif throttle > 0.2:
		if fwd < -5.0:
			fwd = move_toward(fwd, 0.0, BRAKE * lerpf(0.45, 1.0, grip) * delta)
		elif fwd > vmax:
			fwd = move_toward(fwd, vmax, COAST * 2.0 * delta)   # esim. vaurioitui kesken vauhdin
		else:
			# kiihtyvyys hiipuu huippunopeutta kohti; liukkaalla renkaat sutivat
			var r := clampf(fwd / maxf(vmax, 1.0), 0.0, 1.0)
			fwd = minf(fwd + ACCEL * accel_mult * (1.0 - r * r) * lerpf(0.5, 1.0, grip) * throttle * delta, vmax)
	elif throttle < -0.2:
		if fwd > UTURN_SPEED:
			fwd = move_toward(fwd, 0.0, BRAKE * lerpf(0.45, 1.0, grip) * -throttle * delta)
			braking = fwd > vmax * 0.5
		else:
			# Lähes pysähdyksissä vastakkainen nuoli kääntää auton ympäri ja se lähtee
			# painettuun suuntaan (peruutus: Shift + vastakkainen nuoli).
			_heading = -h
			h = _heading
			side = Vector2(-h.y, h.x)
			fwd = absf(fwd) * 0.5
			lat = 0.0
			_turn_cd = TURN_COOLDOWN
			throttle = 1.0
	else:
		fwd = move_toward(fwd, 0.0, COAST * delta)

	# Sivuttaisliike: vino nuoli = kaistanvaihto (vain liikkeessä), muuten pito pysäyttää luisun
	var lat_grip := (HANDBRAKE_GRIP if handbrake else LATERAL_GRIP) * lerpf(0.25, 1.0, grip)
	var target_lat := 0.0
	if absf(steer) > 0.2 and absf(throttle) > 0.2 and not handbrake:
		target_lat = signf(steer) * absf(fwd) * STEER_LATERAL
	elif absf(steer) <= 0.2 and absf(fwd) > 30.0 and not handbrake and k < 0.3:
		target_lat += _lane_center_pull(side)
	if k > 0.0:
		_drunk_t += delta
		target_lat += (sin(_drunk_t * 1.3) * 0.55 + sin(_drunk_t * 0.45 + 2.0) * 0.45) * 0.45 * k * absf(fwd)
	# kaistanvaihto liukuu tavoitteeseen rauhallisesti, luisu pysähtyy pidon mukaan
	var rate := lat_grip if absf(target_lat) < absf(lat) or signf(target_lat) != signf(lat) else 4.0 * lerpf(0.4, 1.0, grip)
	lat = lerpf(lat, target_lat, 1.0 - exp(-rate * delta))

	_drive_vel = h * fwd + side * lat
	# Kuvan pehmeä kääntyminen ja luisukallistus (törmäysmuoto pysyy suorana)
	var lean := 0.0
	if absf(fwd) > 25.0:
		lean = clampf(atan2(lat, absf(fwd)) * DRIFT_LEAN * signf(fwd), -DRIFT_LEAN_MAX, DRIFT_LEAN_MAX)
	_visual_rot = lerpf(_visual_rot, lean, 1.0 - exp(-TURN_VISUAL_RATE * delta))
	animated_sprite.rotation = _visual_rot
	_slip = maxf(absf(lat - target_lat), (absf(fwd) if braking and absf(fwd) > 90.0 else 0.0))


## Käännösavustin: käännetty muoto ei mahtunut (seinä tai reunakivi vieressä). Kokeillaan
## siirtää autoa hieman eteen-, taakse- tai käännöksen suuntaan; jos muoto mahtuu, siirrytään
## ja käännytään. Näin risteykseen ei tarvitse osua pikselintarkasti.
func _turn_assist(vertical: bool, h: Vector2, new_h: Vector2) -> bool:
	var offs: Array[Vector2] = []
	var s := 2.0
	while s <= TURN_ASSIST:
		offs.append(h * s)
		offs.append(new_h * s)
		offs.append(-h * s)
		offs.append(h * s + new_h * s)
		offs.append(-new_h * s)
		s += 2.0
	for off in offs:
		if _shape_fits(vertical, off):
			global_position += off
			_apply_shape(vertical, true)
			return true
	return false


## Mahtuuko auto (pysty- tai vaakamuodossa) kohtaan nykyinen paikka + off?
func _shape_fits(vertical: bool, off: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var anim := &"car_down" if vertical else &"car_right"
	var tex: Texture2D = null
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(anim):
		tex = animated_sprite.sprite_frames.get_frame_texture(anim, 0)
	var tex_size := tex.get_size() if tex else (Vector2(16, 21) if vertical else Vector2(23, 16))
	var test := RectangleShape2D.new()
	test.size = Vector2(maxf(tex_size.x - 2.0, 8.0), maxf(tex_size.y - (3.0 if vertical else 4.0), 8.0))
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = test
	q.transform = Transform2D(0.0, global_position + off + Vector2(0.0, 0.5 if vertical else 1.0))
	q.collision_mask = collision_mask
	var excl: Array[RID] = [get_rid()]
	if driver:
		excl.append(driver.get_rid())
	q.exclude = excl
	return get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


## Kaistakeskitys: suoraan ajaessa auto hakeutuu kevyesti tieruudun keskelle (sivusuunnassa),
## jolloin risteyksiin ja kaistoille osuu helpommin. Palauttaa sivuttaisnopeuden lisän.
func _lane_center_pull(side: Vector2) -> float:
	if LANE_ASSIST <= 0.0:
		return 0.0
	var city: Node = get_tree().current_scene.get_node_or_null("City") if get_tree().current_scene else null
	if city == null or not city.has_method("world_to_cell") or not city.has_method("cell_to_world"):
		return 0.0
	var c: Vector2i = city.world_to_cell(collision.global_position)
	if not city.is_road(c):
		return 0.0
	var center: Vector2 = city.cell_to_world(c)
	var off := (collision.global_position - center).dot(side)
	if absf(off) > LANE_ASSIST_MAX:
		return 0.0
	return clampf(-off * LANE_ASSIST * 3.0, -35.0, 35.0)


## Keulan suunta -> animaation nimi
func _heading_anim(h: Vector2) -> StringName:
	if absf(h.x) > absf(h.y):
		return &"car_left" if h.x < 0.0 else &"car_right"
	return &"car_up" if h.y < 0.0 else &"car_down"


## Animaatio -> keulan suunta
func _anim_heading(anim: StringName) -> Vector2:
	match anim:
		&"car_left":
			return Vector2.LEFT
		&"car_up":
			return Vector2.UP
		&"car_down":
			return Vector2.DOWN
	return Vector2.RIGHT


## Luisuessa ja lukkojarrutuksessa takarenkaat jättävät mustat jäljet tiehen.
func _skid_marks() -> void:
	if _slip < SKID_SLIP or _drive_vel.length() < 40.0:
		_skid_prev.clear()
		return
	var h := _heading
	var side := Vector2(-h.y, h.x)
	var half := _shape.size * 0.5
	var back := collision.global_position - h * ((half.y if _vertical else half.x) - 3.0)
	var w := (half.x if _vertical else half.y) - 2.0
	var wheels := [back + side * w, back - side * w]
	var alpha := clampf((_slip - SKID_SLIP) / 120.0, 0.15, 0.55)
	if _skid_prev.size() == 2:
		for i in 2:
			SkidMarksScript.add(self, _skid_prev[i], wheels[i], alpha)
	_skid_prev = wheels


func drive(player_node: CharacterBody2D) -> void:
	driver = player_node
	is_driving = true
	_heading = _anim_heading(animated_sprite.animation)
	_turn_cd = 0.0
	_skid_prev.clear()
	exit_cooldown = 0.3
	_drive_vel = Vector2.ZERO
	get_tree().call_group("police_manager", "set_player_car", self)
	Sfx.play("door_close", global_position, -2.0, 0.1)
	if not wrecked:
		Sfx.play("engine_start", global_position, -4.0, 0.05)
		_engine_level = -0.6   # moottori alkaa kuulua käynnistysäänen jälkeen
	if is_npc_owned:
		# Auton varastaminen on rikos: 1 tähti
		is_npc_owned = false
		_hud_message("Varastit auton!", 2.5)
		# Varkaus nostaa tähtiä vain, jos poliisi tai joku ohikulkija näki sen
		get_tree().call_group("police_manager", "commit_crime", 1, global_position, null, false)

func exit_car() -> void:
	if not driver: return
	Sfx.play("door_open", global_position, -2.0, 0.1)
	is_driving = false
	_drive_vel = Vector2.ZERO
	velocity = Vector2.ZERO
	_visual_rot = 0.0
	animated_sprite.rotation = 0.0
	var spot := _free_exit_spot(driver)
	driver.global_position = spot
	driver.velocity = Vector2.ZERO
	driver.show()
	driver.set_physics_process(true)
	driver.set_process_unhandled_input(true)
	driver.get_node("CollisionShape2D").disabled = false
	driver = null
	if animated_sprite:
		animated_sprite.stop()

## Moottorin jatkuva ääni ajaessa (kierrokset nousevat nopeuden mukana) ja
## renkaiden kirskunta jyrkässä käännöksessä tai äkkijarrutuksessa.
func _update_sounds(delta: float) -> void:
	_screech_cd = maxf(_screech_cd - delta, 0.0)
	var running := is_driving and not wrecked and not burning
	var target := 1.0 if running else 0.0
	_engine_level = move_toward(_engine_level, target, delta * (1.6 if running else 3.0))
	if _engine_level > 0.01:
		if _engine == null:
			_engine = AudioStreamPlayer2D.new()
			_engine.stream = Sfx.stream("engine")
			_engine.max_distance = 700.0
			_engine.bus = &"Master"
			add_child(_engine)
		if not _engine.playing:
			_engine.play()
		var spd := clampf(_drive_vel.length() / maxf(speed, 1.0), 0.0, 1.5)
		_engine.pitch_scale = lerpf(0.75, 1.9, spd)
		_engine.volume_db = linear_to_db(clampf(_engine_level, 0.0, 1.0) * lerpf(0.35, 0.6, spd))
	elif _engine and _engine.playing:
		_engine.stop()
	if is_driving and _screech_cd <= 0.0 and _slip > SKID_SLIP * 1.4 and _drive_vel.length() > 60.0:
		Sfx.play("screech", global_position, lerpf(-10.0, -3.0, clampf(_slip / 250.0, 0.0, 1.0)), 0.12)
		_screech_cd = 0.9
	if is_driving and _screech_cd <= 0.0:
		var a := _prev_vel.length()
		var b := _drive_vel.length()
		if a > speed * 0.6:
			var turn := absf(_prev_vel.angle_to(_drive_vel)) if b > 5.0 else 0.0
			var brake := (a - b) / maxf(delta, 0.001)
			if turn > 0.9 or brake > speed * 4.0:
				Sfx.play("screech", global_position, -6.0, 0.12)
				_screech_cd = 1.2
	_prev_vel = _drive_vel


## Etsii auton vierestä paikan, johon kuljettaja mahtuu (ei seinän tai talon sisään).
## Palauttaa pelaajan solmun sijainnin (törmäysmuodon siirtymä huomioituna).
func _free_exit_spot(who: CharacterBody2D) -> Vector2:
	var cs := who.get_node("CollisionShape2D") as CollisionShape2D
	var off := cs.position
	var half := _shape.size * 0.5
	var c := collision.global_position
	var pad := 7.0
	var candidates: Array[Vector2] = [
		c + Vector2(0, -half.y - pad), c + Vector2(0, half.y + pad),
		c + Vector2(-half.x - pad, 0), c + Vector2(half.x + pad, 0),
		c + Vector2(-half.x - pad, -half.y - pad), c + Vector2(half.x + pad, -half.y - pad),
		c + Vector2(-half.x - pad, half.y + pad), c + Vector2(half.x + pad, half.y + pad),
	]
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = cs.shape
	q.collision_mask = who.collision_mask
	var excl: Array[RID] = [who.get_rid()]
	q.exclude = excl
	var space := get_world_2d().direct_space_state
	for p: Vector2 in candidates:
		q.transform = Transform2D(0.0, p)
		if space.intersect_shape(q, 1).is_empty():
			return p - off
	return exit_point.global_position - off

## Kipinät ja peltiromu kolarikohtaan.
func _sparks(at: Vector2, normal: Vector2, count: int) -> void:
	var parent := get_parent()
	if parent == null:
		return
	for i in count:
		var s := Polygon2D.new()
		var r := randf_range(0.6, 1.4)
		s.polygon = PackedVector2Array([Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)])
		s.color = [Color(1.0, 0.85, 0.3), Color(1.0, 0.6, 0.15), Color(0.75, 0.75, 0.8)][randi() % 3]
		s.z_index = 4000
		parent.add_child(s)
		s.global_position = at
		var dir := (normal + Vector2.from_angle(randf() * TAU) * 0.9).normalized()
		var tw := s.create_tween()
		tw.tween_property(s, "global_position", at + dir * randf_range(8.0, 26.0), randf_range(0.2, 0.4)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(s, "modulate:a", 0.0, 0.4)
		tw.tween_callback(s.queue_free)

## Vaurioitunut auto savuaa konepellistä; romu savuaa mustana.
func _smoke(delta: float) -> void:
	if health / MAX_HEALTH > SMOKE_BELOW or burning or exploded:
		return   # palavan / räjähtäneen auton savun tekee CarFire
	var k := 1.0 - health / MAX_HEALTH
	_smoke_acc += delta * lerpf(3.0, 14.0, k)
	while _smoke_acc >= 1.0:
		_smoke_acc -= 1.0
		var p := Polygon2D.new()
		var r := randf_range(1.5, 3.0)
		var pts := PackedVector2Array()
		for j in 6:
			pts.append(Vector2.from_angle(j * TAU / 6.0) * r)
		p.polygon = pts
		var g := 0.25 if wrecked else lerpf(0.75, 0.4, k)
		p.color = Color(g, g, g, 0.7)
		p.z_index = 4001
		get_parent().add_child(p)
		var start := global_position + Vector2(randf_range(-4.0, 4.0), -6.0)
		p.global_position = start
		var tw := p.create_tween()
		var drift := Vector2(Game.wind * 14.0 + randf_range(-4.0, 4.0), randf_range(-22.0, -14.0))
		tw.tween_property(p, "global_position", start + drift, 1.1)
		tw.parallel().tween_property(p, "scale", Vector2(2.4, 2.4), 1.1)
		tw.parallel().tween_property(p, "modulate:a", 0.0, 1.1)
		tw.tween_callback(p.queue_free)

func _hud_message(text: String, seconds: float) -> void:
	var hud_node := get_tree().current_scene.get_node_or_null("Hud")
	if hud_node and hud_node.has_method("show_message"):
		hud_node.show_message(text, seconds)

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("enter_car"):
		body.current_car = self
		var main_level = get_tree().current_scene
		var hud_node = main_level.get_node_or_null("Hud")
		if hud_node:
			var txt := "Paina E noustaksesi autoon"
			if burning:
				txt = "Auto palaa! Pysy kaukana!"
			elif exploded:
				txt = "Palanut romu"
			elif wrecked:
				txt = "Auto on romuna"
			hud_node.show_instruction(txt)

func _on_body_exited(body: Node2D) -> void:
	if body.has_method("enter_car") and body.current_car == self:
		body.current_car = null
		var main_level = get_tree().current_scene
		var hud_node = main_level.get_node_or_null("Hud")
		if hud_node:
			hud_node.hide_instruction()
