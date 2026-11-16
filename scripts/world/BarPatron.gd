extends Node2D
const BLOOD := preload("res://scripts/core/Blood.gd")
## Baarin asiakas: känninen örvelö joka huutelee solvauksia, haastaa pelaajan tappeluun
## ja käy päälle nyrkein. Pelaaja lyö välilyönnillä / hiirellä (kun ei asetta kädessä).
##
## Tilat:
##   IDLE      -> seisoskelee, huutelee pelaajalle, voi haastaa tappeluun
##   CHALLENGE -> huutaa haasteen ja kävelee pelaajan luo
##   FIGHT     -> lyö pelaajaa nyrkillä
##   DOWN      -> kaatunut (pudottaa rahaa), nousee hetken päästä ylös mököttämään
##   DEAD      -> ammuttu kuoliaaksi (rikos: etsintäkuulutus)
##
## Bar.gd luo nämä ja asettaa bar, city ja base_row ennen add_child:ia.

const COIN_SCRIPT := preload("res://scripts/world/Coin.gd")

enum S { IDLE, CHALLENGE, FIGHT, DOWN, DEAD }

## -- SÄÄDÄ NÄITÄ --
const MAX_HP := 4                  ## nyrkki-iskuja kaatumiseen
const WALK_SPEED := 52.0
const FIGHT_SPEED := 80.0
const PUNCH_RANGE := 19.0
const PUNCH_INTERVAL := 1.0        ## sekuntia iskujen välillä
const PUNCH_CHANCE := 0.75         ## todennäköisyys osua
const TAUNT_RANGE := 240.0         ## tästä etäisyydestä huutelu kuuluu
const CHALLENGE_RANGE := 260.0
const DOWN_TIME := 10.0
const SULK_TIME := 30.0            ## kaatumisen jälkeen ei haasta uudestaan tämän aikaa

const TAUNTS := [
	"Mitä vittua sä tuijotat?",
	"Toi kaveri haisee paskalle!",
	"Saatana, taas joku kakara!",
	"Kenen luulet olevas, ääliö?",
	"Sun naamasi on ihan paska!",
	"Mene kotiin äidin luo!",
	"Perkele, mikä luuseri!",
	"Maksa mun kossu, pelle!",
	"Hei sä! Joo, sä paskapää!",
	"Täällä ei tarvita sun kaltaisia!",
	"Kato nyt tuota horjujaa!",
	"Mun koira on fiksumpi kuin sä!",
	"Ei kukaan kysyny sun mielipidettä!",
	"Vitun turisti...",
]
const ARMED_TAUNTS := [
	"Iso mies pistoolin kanssa, joo joo!",
	"Pelkäätkö ilman asetta, ressukka?",
	"Pistooli housuissa vai ilahtuiko?",
]
const CHALLENGES := [
	"Haluutsä turpaan, vai?",
	"Tuu tänne, mä näytän sulle!",
	"Nosta ne nyrkit, paska!",
	"Mä hakkaan sut tohjoksi!",
	"Tapellaan! Heti!",
	"Sä tuut nyt tappelemaan!",
]
const FIGHT_LINES := ["Ota tästä!", "Perkele, tuu tänne!", "Ai sattuuko?", "Turpaan tulee!"]
const HIT_LINES := ["Auts!", "Mun hammas!", "Saatana!", "Ai vittu!"]
const DOWN_LINES := ["Okei okei, riittää...", "Aah... mun naama...", "Älä enää...", "Mä luovutan..."]
## Oman baarin omistajalle (Game.owns_bar): asiakkaat kunnioittavat pomoa
const BOSS_GREETINGS := ["Moi pomo!", "Hyvä baari, pomo!", "Kiitti kun pidät tän paikan pystyssä!",
	"Pomo! Kippis!", "Paras mesta koko kaupungissa!", "Tarjoot kierroksen, pomo?", "Hei, se on omistaja!"]
const BOSS_HIT_LINES := ["Anteeks pomo!", "Okei okei, mä rauhotun!", "Sori, sori!", "Mä en tee mitään, pomo!"]

var bar: Node2D
var city: Node2D   # CityGenerator
var base_row := 0
## Rähinöitsijä: vain nämä huutelevat ja haastavat tappeluun (Bar arpoo, ei kaikkia).
## Rauhalliset asiakkaat istuskelevat hiljaa ja puolustautuvat vain jos heitä lyödään.
var rowdy := false
## Tuttu naama: {"name", "row", "beaten"} (Game.grudges). Muistaa edellisen tappelun.
var grudge: Dictionary = {}
var _hit_by_player := false
var hp := MAX_HP
var state := S.IDLE
var dir := Vector2i.DOWN

var sprite: Sprite2D
var player: Node2D
var _step := 0
var _anim := 0.0
var _t := 0.0
var _phase := 0.0
var _taunt_t := 0.0
var _challenge_t := 0.0
var _punch_t := 0.0
var _down_t := 0.0
var _sulk_t := 0.0
var _join_t := -1.0
var _greet_t := 0.0
var _bubble: Label


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.offset = Vector2(0, -4)
	add_child(sprite)
	z_index = 10
	add_to_group("shootable")
	add_to_group("bar_patron")
	player = get_tree().get_first_node_in_group("player") as Node2D
	_taunt_t = randf_range(3.0, 9.0)
	_challenge_t = randf_range(10.0, 20.0)
	if not grudge.is_empty():
		rowdy = true
		_challenge_t = randf_range(2.5, 5.0)
		_taunt_t = 0.8
		call_deferred("say", "%s: Sä taas! Viimeksi jäi kesken!" % str(grudge.get("name", "")), 2.6)
	_phase = randf() * TAU
	var dirs: Array[Vector2i] = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	dir = dirs[randi() % dirs.size()]
	_refresh()


func hit_point() -> Vector2:
	return global_position + Vector2(0, -4)


func is_fighting() -> bool:
	return state == S.CHALLENGE or state == S.FIGHT


func can_join() -> bool:
	return rowdy and state == S.IDLE and _sulk_t <= 0.0


func is_punchable() -> bool:
	return state == S.IDLE or state == S.CHALLENGE or state == S.FIGHT


## Kaveri aloitti tappelun: voi liittyä mukaan hetken päästä.
func join_fight() -> void:
	_join_t = randf_range(1.5, 3.5)


func _pp() -> Vector2:
	if player.has_method("body_center"):
		return player.body_center()
	return player.global_position


func _process(delta: float) -> void:
	if state == S.DEAD or player == null:
		return
	_t += delta
	_sulk_t = maxf(_sulk_t - delta, 0.0)
	_punch_t = maxf(_punch_t - delta, 0.0)
	match state:
		S.IDLE:
			_idle(delta)
		S.CHALLENGE:
			_challenge(delta)
		S.FIGHT:
			_fight(delta)
		S.DOWN:
			_down_t -= delta
			if _down_t <= 0.0:
				_get_up()


# ----------------------------------------------------------------------------
#  TILAT
# ----------------------------------------------------------------------------
func _idle(delta: float) -> void:
	var to := _pp() - global_position
	var d := to.length()
	_face(to)
	sprite.position.x = sin(_t * 1.6 + _phase) * 0.7   # hoippuu paikallaan
	_set_step(0)

	if _join_t > 0.0:
		_join_t -= delta
		if _join_t <= 0.0:
			_join_t = -1.0
			_begin_fight("Mä tuun mukaan!", false)
			return

	# Oma baari: asiakkaat tervehtivät pomoa, kukaan ei haasta tappeluun
	if Game.owns_bar:
		rowdy = false
		_greet_t -= delta
		if _greet_t <= 0.0:
			_greet_t = randf_range(12.0, 30.0)
			if d < 90.0 and randf() < 0.5 and bar.can_shout():
				bar.note_shout()
				say(BOSS_GREETINGS[randi() % BOSS_GREETINGS.size()], 2.0)
		return

	if not rowdy:
		return   # rauhallinen asiakas: ei huuda eikä haasta

	_taunt_t -= delta
	if _taunt_t <= 0.0:
		_taunt_t = randf_range(7.0, 16.0)
		# huutelee vain välillä, ja vain jos kukaan muu ei juuri huutanut
		if d < TAUNT_RANGE and randf() < 0.6 and bar.can_shout():
			_taunt()

	if _sulk_t <= 0.0 and d < CHALLENGE_RANGE:
		_challenge_t -= delta
		if _challenge_t <= 0.0:
			if bar.can_challenge():
				_begin_challenge()
			else:
				_challenge_t = 4.0


func _taunt() -> void:
	var pool: Array = TAUNTS.duplicate()
	if player.has_method("has_weapon") and player.has_weapon():
		pool.append_array(ARMED_TAUNTS)
	bar.note_shout()
	say(pool[randi() % pool.size()])


func _begin_challenge() -> void:
	state = S.CHALLENGE
	sprite.position.x = 0.0
	say(CHALLENGES[randi() % CHALLENGES.size()], 2.4)
	bar.brawl_alarm(self)
	bar.hud_message("Baarin asiakas haastaa sinut tappeluun! Lyö välilyönnillä tai hiirellä.", 3.5)


func _challenge(delta: float) -> void:
	var d := _approach(WALK_SPEED, delta)
	if d <= PUNCH_RANGE + 6.0:
		_begin_fight(FIGHT_LINES[randi() % FIGHT_LINES.size()], false)


func _begin_fight(line: String, alarm: bool) -> void:
	state = S.FIGHT
	sprite.position.x = 0.0
	_punch_t = 0.5
	say(line, 1.6)
	if alarm:
		bar.brawl_alarm(self)


func _fight(delta: float) -> void:
	var d := _approach(FIGHT_SPEED, delta)
	if not player.is_physics_processing():
		return   # pelaaja on sammumassa
	if d <= PUNCH_RANGE + 4.0 and _punch_t <= 0.0:
		_punch_t = PUNCH_INTERVAL * randf_range(0.8, 1.3)
		_lunge()
		if randf() < PUNCH_CHANCE:
			player.hurt(1, self)
			if randf() < 0.35:
				say(FIGHT_LINES[randi() % FIGHT_LINES.size()], 1.2)
		elif randf() < 0.4:
			say("Ohi meni!", 0.9)


## Kävelee pelaajaa kohti. Palauttaa etäisyyden pelaajaan.
func _approach(speed: float, delta: float) -> float:
	var to := _pp() - global_position
	var d := to.length()
	_face(to)
	if d > PUNCH_RANGE - 4.0:
		_move(to.normalized() * speed * delta)
		_walk_anim(delta)
	else:
		_set_step(0)
	return d


# ----------------------------------------------------------------------------
#  OSUMAT
# ----------------------------------------------------------------------------
## Pelaajan nyrkki osuu.
func fist_hit(from: Node2D) -> void:
	if not is_punchable():
		return
	if from and from.is_in_group("player"):
		if state == S.IDLE and not rowdy and not _hit_by_player:
			bar.note_unprovoked()   # rauhallisen asiakkaan lyöminen: portsari huomaa
		_hit_by_player = true
	BLOOD.spray(self, hit_point(), (global_position - from.global_position) if from else Vector2.ZERO, 3)
	hp -= 1
	_flash()
	_move((global_position - from.global_position).normalized() * 5.0)
	if randf() < 0.5:
		say(HIT_LINES[randi() % HIT_LINES.size()], 1.0)
	if hp <= 0:
		_go_down()
		return
	if Game.owns_bar and from and from.is_in_group("player"):
		# pomoa ei lyödä takaisin
		say(BOSS_HIT_LINES[randi() % BOSS_HIT_LINES.size()], 1.4)
		if state != S.IDLE:
			state = S.IDLE
		return
	if state == S.IDLE:
		_begin_fight("Sä löit mua, paska!", true)
	elif state == S.CHALLENGE:
		state = S.FIGHT


## Luoti osuu (Bullet2D kutsuu).
func take_damage(amount: int = 1, source: Node = null) -> void:
	if state == S.DEAD:
		return
	var bdir: Vector2 = (global_position - (source as Node2D).global_position) if source is Node2D else Vector2.ZERO
	BLOOD.spray(self, hit_point(), bdir, 4 if hp - amount > 0 else 9, hp - amount <= 0)
	hp -= amount
	_flash()
	if source and source.is_in_group("player"):
		bar.note_weapon_violence()
	if hp <= 0:
		_die(source)
		return
	if Game.owns_bar and source and source.is_in_group("player"):
		say("Älä ammu, pomo!", 1.4)
		return
	if state == S.IDLE:
		_begin_fight("Sä ammuit mua!", true)


func _go_down() -> void:
	state = S.DOWN
	hp = 0
	_down_t = DOWN_TIME
	sprite.position.x = 0.0
	sprite.rotation = deg_to_rad(90.0 if dir != Vector2i.LEFT else -90.0)
	say(DOWN_LINES[randi() % DOWN_LINES.size()], 2.0)
	_drop_coins()
	if _hit_by_player:
		bar.note_knockdown(self)
	bar.fight_ended()


func _get_up() -> void:
	state = S.IDLE
	hp = MAX_HP
	sprite.rotation = 0.0
	_sulk_t = SULK_TIME
	_challenge_t = randf_range(10.0, 20.0)
	say("Joo joo... ei jaksa enää.", 2.0)


func _die(source: Node) -> void:
	state = S.DEAD
	remove_from_group("shootable")
	remove_from_group("bar_patron")
	sprite.rotation = deg_to_rad(90.0 if dir != Vector2i.LEFT else -90.0)
	if source and source.is_in_group("player"):
		# Baari on täynnä todistajia: ilmoitus menee heti (henkirikos, ei sakkoa)
		get_tree().call_group("police_manager", "report_crime", 1, true)
	_drop_coins()
	bar.fight_ended()
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(self, "modulate:a", 0.0, 1.0)
	tw.tween_callback(queue_free)


func _drop_coins() -> void:
	for i in randi_range(2, 4):
		var coin = COIN_SCRIPT.new()
		coin.value = randi_range(5, 12)
		coin.position = position + Vector2(0.0, -4.0)
		get_parent().add_child(coin)
		coin.toss(Vector2.from_angle(randf() * TAU) * randf_range(25.0, 60.0))
	bar.hud_message("Vastustaja pudotti rahaa. Kerää kolikot!", 2.0)


# ----------------------------------------------------------------------------
#  LIIKE JA PIIRTO
# ----------------------------------------------------------------------------
## Liikkuu baarin lattialla (akseli kerrallaan, jotta kalusteiden vierestä liukuu).
func _move(step: Vector2) -> void:
	for axis: Vector2 in [Vector2(step.x, 0.0), Vector2(0.0, step.y)]:
		var np := position + axis
		if bar.is_free(np):
			position = np


func _lunge() -> void:
	var push := (_pp() - global_position).normalized() * 3.0
	var tw := create_tween()
	tw.tween_property(sprite, "position", push, 0.06)
	tw.tween_property(sprite, "position", Vector2.ZERO, 0.1)


func _flash() -> void:
	sprite.modulate = Color(1.0, 0.5, 0.5)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)


func _face(v: Vector2) -> void:
	var d := dir
	if absf(v.x) > absf(v.y):
		d = Vector2i.RIGHT if v.x > 0.0 else Vector2i.LEFT
	else:
		d = Vector2i.DOWN if v.y > 0.0 else Vector2i.UP
	if d != dir:
		dir = d
		_refresh()


func _walk_anim(delta: float) -> void:
	_anim += delta
	_set_step(1 + (int(_anim * 7.0) % 2))


func _set_step(st: int) -> void:
	if st != _step:
		_step = st
		_refresh()


func _refresh() -> void:
	sprite.texture = city.npc_tex(base_row, dir, _step)


## Puhekupla asiakkaan yläpuolelle.
func say(text: String, seconds: float = 1.8) -> void:
	if is_instance_valid(_bubble):
		_bubble.queue_free()
	var l := Label.new()
	l.text = text
	l.position = Vector2(-75.0, -34.0)
	l.size = Vector2(150.0, 12.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.z_index = 30
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	_bubble = l
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)
