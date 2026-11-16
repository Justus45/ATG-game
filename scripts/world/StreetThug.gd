extends Node2D
## Kadun hahmo, joka tappelee pelaajan kanssa:
##   - grudge:  baarista tuttu rähinöitsijä, joka kostaa kadulla (StreetEvents)
##   - target:  "hoida tyyppi" -tehtävän kohde, seisoo paikallaan kunnes häntä lyödään
##   - courier: ryöstökeikan kuriiri baarin takana, rahat ryöstetään (R) tai hakataan irti
## Lyöminen on itsepuolustusta (ei rikos), mutta tappaminen on henkirikos.
##
## Luoja asettaa city, base_row ja moodin ennen add_child:ia.

const COIN_SCRIPT := preload("res://scripts/world/Coin.gd")
const BLOOD := preload("res://scripts/core/Blood.gd")

enum S { IDLE, FIGHT, DOWN, DEAD, FLEE }

const SPEED := 72.0
const PUNCH_RANGE := 18.0
const PUNCH_INTERVAL := 1.1
const PUNCH_CHANCE := 0.65

signal defeated(thug: Node)   ## kaadettiin nyrkein (tai ryöstettiin)
signal killed(thug: Node)

var city: Node
var base_row := 0
var mode := "grudge"          # "grudge", "target", "courier"
var display_name := ""
var cash := 0                 # pudotettavat rahat kaatuessa
var hp := 5
var state := S.IDLE
var dir := Vector2i.DOWN

var sprite: Sprite2D
var player: Node2D
var _punch_t := 0.8
var _anim := 0.0
var _step := 0
var _life := 0.0
var _robbed := false


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.offset = Vector2(0, -4)
	add_child(sprite)
	add_to_group("shootable")
	add_to_group("street_thug")
	player = get_tree().get_first_node_in_group("player") as Node2D
	if mode == "grudge":
		state = S.FIGHT
		hp = 5
	elif mode == "courier":
		hp = 4
	else:
		hp = 6
	_refresh()


func hit_point() -> Vector2:
	return global_position + Vector2(0, -4)


func is_punchable() -> bool:
	return state == S.IDLE or state == S.FIGHT or state == S.FLEE


func _pp() -> Vector2:
	if player and player.has_method("body_center"):
		return player.body_center()
	return global_position


func _process(delta: float) -> void:
	if state == S.DEAD or state == S.DOWN or player == null:
		return
	_life += delta
	_punch_t = maxf(_punch_t - delta, 0.0)
	var to := _pp() - global_position
	var d := to.length()
	match state:
		S.IDLE:
			_face(to)
			_set_step(0)
		S.FIGHT:
			if not player.visible or not player.is_physics_processing():
				_set_step(0)
				return   # pelaaja autossa tai sammumassa
			if d > PUNCH_RANGE - 4.0:
				_move(to.normalized() * SPEED * delta)
				_walk_anim(delta)
			else:
				_set_step(0)
			_face(to)
			if d <= PUNCH_RANGE + 4.0 and _punch_t <= 0.0:
				_punch_t = PUNCH_INTERVAL * randf_range(0.8, 1.3)
				var base := sprite.position
				var tw := create_tween()
				tw.tween_property(sprite, "position", base + to.normalized() * 3.0, 0.06)
				tw.tween_property(sprite, "position", base, 0.1)
				if randf() < PUNCH_CHANCE and player.has_method("hurt"):
					player.hurt(1, self)
			# Karannut pelaaja: luovuttaa
			if d > 420.0 and mode == "grudge":
				_despawn()
		S.FLEE:
			_move(-to.normalized() * SPEED * 1.3 * delta)
			_walk_anim(delta)
			if d > 400.0:
				_despawn()


## Liikkuu vain kävelykelpoisille ruuduille (akseli kerrallaan).
func _move(step: Vector2) -> void:
	for axis in [Vector2(step.x, 0.0), Vector2(0.0, step.y)]:
		var np: Vector2 = global_position + axis
		if city == null or city.is_walkable(city.world_to_cell(np)):
			global_position = np


func _face(v: Vector2) -> void:
	var nd := dir
	if absf(v.x) > absf(v.y):
		nd = Vector2i.RIGHT if v.x > 0.0 else Vector2i.LEFT
	else:
		nd = Vector2i.DOWN if v.y > 0.0 else Vector2i.UP
	if nd != dir:
		dir = nd
		_refresh()


func _walk_anim(delta: float) -> void:
	_anim += delta
	_set_step(1 + (int(_anim * 7.0) % 2))


func _set_step(st: int) -> void:
	if st != _step:
		_step = st
		_refresh()


func _refresh() -> void:
	if city and city.has_method("npc_tex"):
		sprite.texture = city.npc_tex(base_row, dir, _step)


func say(text: String, seconds: float = 1.8) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(-60.0, -30.0)
	l.size = Vector2(120.0, 12.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.z_index = 30
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


func fist_hit(from: Node2D) -> void:
	if not is_punchable():
		return
	BLOOD.spray(self, hit_point(), (global_position - from.global_position) if from else Vector2.ZERO, 3)
	hp -= 1
	sprite.modulate = Color(1.0, 0.5, 0.5)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.15)
	_move((global_position - from.global_position).normalized() * 5.0)
	if state == S.IDLE:
		state = S.FIGHT
		say(["Mitä sä luulet tekeväs?!", "Nyt tuli virhe!", "Tuu vaan!"][randi() % 3])
	if hp <= 0:
		_go_down()


func take_damage(amount: int = 1, source: Node = null) -> void:
	if state == S.DEAD:
		return
	var bdir: Vector2 = (global_position - (source as Node2D).global_position) if source is Node2D else Vector2.ZERO
	BLOOD.spray(self, hit_point(), bdir, 4 if hp - amount * 2 > 0 else 9, hp - amount * 2 <= 0)
	hp -= amount * 2
	if hp > 0:
		if state == S.IDLE:
			state = S.FIGHT
		return
	state = S.DEAD
	remove_from_group("shootable")
	sprite.rotation = deg_to_rad(90.0)
	_drop_coins(cash / 2)
	if source and source.is_in_group("player"):
		get_tree().call_group("police_manager", "commit_crime", 1, global_position, null, true)
	killed.emit(self)
	_fade_out(5.0)


## Ryöstökeikan kuriiri: aseella uhattuna rahat maahan.
func can_be_robbed() -> bool:
	return mode == "courier" and not _robbed and (state == S.IDLE or state == S.FIGHT)


func rob(_player: Node2D) -> void:
	if not can_be_robbed():
		return
	_robbed = true
	say("Okei, okei! Ota ne!", 2.0)
	_drop_coins(cash)
	cash = 0
	state = S.FLEE
	get_tree().call_group("police_manager", "commit_crime", 2, global_position, null, false)
	defeated.emit(self)


func _go_down() -> void:
	state = S.DOWN
	remove_from_group("shootable")
	sprite.rotation = deg_to_rad(90.0 if dir != Vector2i.LEFT else -90.0)
	say(["Okei... riittää...", "Älä enää...", "Mä luovutan!"][randi() % 3], 2.0)
	if cash > 0:
		_drop_coins(cash)
		cash = 0
	Sfx.play("punch_hit", hit_point(), 0.0, 0.0, 0.6)
	defeated.emit(self)
	_fade_out(4.0)


func _drop_coins(total: int) -> void:
	if total <= 0:
		return
	var n := clampi(total / 15, 2, 14)
	var each := maxi(total / n, 1)
	for i in n:
		var coin = COIN_SCRIPT.new()
		coin.value = each
		get_parent().add_child(coin)
		coin.global_position = global_position + Vector2(0.0, -4.0)
		coin.toss(Vector2.from_angle(randf() * TAU) * randf_range(25.0, 70.0))


func _despawn() -> void:
	if state == S.DEAD:
		return
	state = S.DEAD
	remove_from_group("shootable")
	_fade_out(0.2)


func _fade_out(wait: float) -> void:
	var tw := create_tween()
	tw.tween_interval(wait)
	tw.tween_property(self, "modulate:a", 0.0, 1.0)
	tw.tween_callback(queue_free)
