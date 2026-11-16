extends Node
## Hahmon elävyys: silmien räpsytys ja syvä hengitys, kun hahmo seisoo pitkään paikallaan.
##
## Game.gd liittää tämän kaikkiin hahmoihin (pelaaja, jalankulkijat, poliisit, baarin asiakkaat...).
## Toimii Sprite2D:n ja AnimatedSprite2D:n kanssa: kiinni olevat silmät piirretään päälle
## omana kuvanaan (CharSprites.blink), joten hahmon omaa animaatiota ei kosketa.

const CS := preload("res://scripts/core/CharSprites.gd")
const SmokeFXScript := preload("res://scripts/core/SmokeFX.gd")
const SMOKER_CHANCE := 0.3       ## osuus kaupungin jalankulkijoista, jotka polttavat pysähtyessään

# --- SÄÄDÄ NÄITÄ ---
const BLINK_MIN := 2.0        ## räpäytysten väli (s)
const BLINK_MAX := 5.5
const BLINK_TIME := 0.11      ## silmät kiinni (s)
const STILL_BEFORE_BREATH := 2.5   ## paikallaan näin kauan ennen syvää henkäystä (s)
const BREATH_EVERY_MIN := 4.0
const BREATH_EVERY_MAX := 8.0
const BREATH_TIME := 2.0      ## sisään + ulos (s)
const BREATH_Y := 0.07        ## rintakehän nousu (y-skaala)
const ACTIVE_RANGE := 650.0   ## kauempana kamerasta ei tehdä mitään

var body: Node2D = null
var sprite: Node2D = null     ## Sprite2D tai AnimatedSprite2D

var _eyes: Sprite2D
var _outline: Array[Sprite2D] = []
var _blink_t := 0.0
var _blink_left := 0.0
var _blink_src: Texture2D = null
var _still_t := 0.0
var _last_pos := Vector2.ZERO
var _breath_wait := 0.0
var _breath := -1.0
var _base_scale := Vector2.ONE
var _outline_tex: Texture2D = null
var _smoker := false
var _smoke: Node2D = null
var _moving_t := 0.0
var _stop_extended := false


func _ready() -> void:
	_blink_t = randf_range(0.5, BLINK_MAX)
	_breath_wait = randf_range(BREATH_EVERY_MIN, BREATH_EVERY_MAX)
	if not is_instance_valid(sprite):
		return
	_base_scale = sprite.scale
	_eyes = Sprite2D.new()
	_eyes.visible = false
	sprite.add_child(_eyes)
	if body:
		_last_pos = body.global_position
		# kaupungin jalankulkija (Mover): osa polttaa tupakkaa pysähtyessään
		_smoker = body.get("wait") != null and not Game.flag(body, "is_car") and not body.is_in_group("player") \
			and randf() < SMOKER_CHANCE


func _cur_tex() -> Texture2D:
	if sprite is Sprite2D:
		return (sprite as Sprite2D).texture
	if sprite is AnimatedSprite2D:
		var a := sprite as AnimatedSprite2D
		if a.sprite_frames and a.sprite_frames.has_animation(a.animation):
			return a.sprite_frames.get_frame_texture(a.animation, a.frame)
	return null


## Kopioi kuvan asettelun (keskitys, siirtymä, peilaus) päällä piirrettävälle kuvalle.
func _match(s: Sprite2D, tex: Texture2D, shift: Vector2 = Vector2.ZERO) -> void:
	s.texture = tex
	s.centered = bool(sprite.get("centered"))
	s.offset = (sprite.get("offset") as Vector2) + shift
	s.flip_h = bool(sprite.get("flip_h"))
	s.flip_v = bool(sprite.get("flip_v"))


func _process(delta: float) -> void:
	if not is_instance_valid(sprite) or not is_instance_valid(body):
		queue_free()
		return
	if not sprite.is_visible_in_tree() or Game.flag(body, "dead"):
		_eyes.visible = false
		_stop_breath()
		return
	var cam := get_viewport().get_camera_2d()
	if cam and cam.global_position.distance_to(body.global_position) > ACTIVE_RANGE:
		return
	# liikkuuko hahmo?
	var moved := body.global_position.distance_to(_last_pos) > 0.25
	_last_pos = body.global_position
	_still_t = 0.0 if moved else _still_t + delta
	var tex := _cur_tex()

	# --- Räpsytys ---
	if _blink_left > 0.0:
		_blink_left -= delta
		if _blink_left <= 0.0 or tex != _blink_src:
			_eyes.visible = false
			_blink_left = 0.0
	else:
		_blink_t -= delta
		if _blink_t <= 0.0:
			# välillä kaksoisräpäytys
			_blink_t = 0.28 if randf() < 0.18 else randf_range(BLINK_MIN, BLINK_MAX)
			var b := CS.blink(tex)
			if b:
				_match(_eyes, b)
				_eyes.visible = true
				_blink_src = tex
				_blink_left = BLINK_TIME

	# --- Tupakoivat jalankulkijat ---
	if _smoker:
		_update_smoking(delta, moved)

	# --- Syvä henkäys paikallaan seistessä ---
	if moved:
		_stop_breath()
		_breath_wait = randf_range(1.0, BREATH_EVERY_MAX)
	elif _still_t > STILL_BEFORE_BREATH:
		if _breath < 0.0:
			_breath_wait -= delta
			if _breath_wait <= 0.0:
				_breath = 0.0
				_base_scale = sprite.scale
		else:
			_breath += delta
			var k := clampf(_breath / BREATH_TIME, 0.0, 1.0)
			# nopea sisäänhengitys, pidätys, hidas uloshengitys
			var a := sin(minf(k * 1.6, 1.0) * PI * 0.5) if k < 0.45 else cos((k - 0.45) / 0.55 * PI * 0.5)
			sprite.scale = _base_scale * Vector2(1.0 + 0.02 * a, 1.0 + BREATH_Y * a)
			if k >= 1.0:
				_stop_breath()
				_breath_wait = randf_range(BREATH_EVERY_MIN, BREATH_EVERY_MAX)



## Pysähtynyt tupakoitsija sytyttää röökin ja jää polttamaan hetkeksi; liikkeelle
## lähtiessä tupakka sammuu pian.
func _update_smoking(delta: float, moved: bool) -> void:
	if moved:
		_moving_t += delta
		_stop_extended = false
		if _moving_t > 1.5 and is_instance_valid(_smoke) and _smoke.call("is_burning"):
			_smoke.call("stop")
		return
	_moving_t = 0.0
	if _still_t < 0.6 or Game.flag(body, "calling"):
		return
	if not is_instance_valid(_smoke) or not _smoke.call("is_burning"):
		var fx := SmokeFXScript.new()
		fx.sprite = sprite
		fx.duration = -1.0
		sprite.add_child(fx)
		_smoke = fx
	# polttaja seisoo pidempään paikallaan (Moverin odotus)
	if not _stop_extended:
		_stop_extended = true
		var w: Variant = body.get("wait")
		if w is float and float(w) > 0.0:
			body.set("wait", float(w) + randf_range(4.0, 9.0))


func _stop_breath() -> void:
	if _breath >= 0.0 and is_instance_valid(sprite):
		sprite.scale = _base_scale
	_breath = -1.0


func _set_outline(on: bool) -> void:
	for o in _outline:
		if o.visible != on:
			o.visible = on


## Baarin sisällä ääriviiva: tummalla / kirjavalla lattialla vaalea, puulattialla tumma.
func _bar_outline_color() -> Color:
	var bar := get_tree().get_first_node_in_group("bar")
	if bar == null or not bar.get("inside"):
		return Color(0, 0, 0, 0)
	var origin: Vector2 = bar.get("INTERIOR_ORIGIN") if bar.get("INTERIOR_ORIGIN") != null else Vector2(-1800.0, 1400.0)
	var lp := body.global_position - origin
	if lp.x < -40.0 or lp.y < -40.0 or lp.x > 560.0 or lp.y > 760.0:
		return Color(0, 0, 0, 0)
	var dec := 0
	if Game.owns_bar and bar.get("biz") != null:
		dec = int(bar.biz.level("decor"))
	return Color(1, 1, 1, 0.55) if dec >= 2 else Color(0.05, 0.03, 0.02, 0.45)
