extends Node2D
## Pelaajan kädessä oleva ase. Näyttää aseen, tähtää hiirellä ja ampuu.
## Pelaaja kutsuu update():a omasta _physics_process:ista, joten ase
## ei toimi kun pelaaja on autossa (pelaajan prosessointi on silloin pois).
## Aseen ominaisuudet (tulinopeus, vahinko, sprite...) tulevat WeaponDB:stä.

const BULLET_SCENE: PackedScene = preload("res://scenes/entities/weapons/bullet.tscn")

# Ruutujen järjestys aseen sprite-arkissa
const CELL_PICKUP := 0
const CELL_HELD := {"right": 1, "left": 2, "up": 3, "down": 4}
const CELL_FLASH := 5

## Suun paikka suhteessa pelaajan spriten keskipisteeseen
const MUZZLE := {
	"right": Vector2(7, 1),
	"left": Vector2(-7, 1),
	"up": Vector2(5, -7),
	"down": Vector2(5, 9),
}

@export var flash_time: float = 0.05

var equipped: bool = false
var weapon_id: String = ""
var weapon_name: String = ""
## Paikalleen kuuluvan esineen tunniste (esim. "bar_cue"), "" = tavallinen ase
var fixture: String = ""
var facing: String = "down"

var _fire_interval: float = 0.25
var _damage: int = 1
var _bullet_speed: float = 450.0
var _range: float = 320.0
var _spread: float = 0.0
var _pellets: int = 1
## Lähiase (pullo, keppi, kynä, veitsi): ei luoteja, isku osuu edessä olevaan
var _melee := false
var _reach := 24.0
var _lethal := false
## Kestävyys: pullo hajoaa muutaman osuman jälkeen (-1 = ei hajoa)
var durability := -1
var _swing_t := 0.0

var _cooldown: float = 0.0
var _flash_left: float = 0.0
var _aim_hold: float = 0.0  # kuinka kauan ampumasuunta ohittaa kävelysuunnan
var _textures: Dictionary = {}

@onready var sprite: Sprite2D = $Sprite2D
@onready var flash: Sprite2D = $Flash

func _ready() -> void:
	flash.centered = false
	flash.offset = Vector2(0, -WeaponDB.CELL * 0.5)  # kierto suun kohdalta
	flash.hide()
	sprite.hide()

func _hud() -> Node:
	return get_tree().current_scene.get_node_or_null("Hud")

## Lataa aseen tiedot ja tekstuurit WeaponDB:stä.
func _load_weapon(id: String) -> void:
	var data := WeaponDB.get_data(id)
	weapon_id = id if WeaponDB.DATA.has(id) else "pistol"
	weapon_name = data.name
	_fire_interval = data.fire_interval
	_damage = data.damage
	_bullet_speed = data.bullet_speed
	_range = data.range
	_spread = data.spread
	_pellets = int(data.get("pellets", 1))
	_melee = bool(data.get("melee", false))
	_reach = float(data.get("reach", 24.0))
	_lethal = bool(data.get("lethal", false))
	durability = int(data.get("durability", -1))
	for dir: String in CELL_HELD:
		_textures[dir] = WeaponDB.cell(weapon_id, CELL_HELD[dir])
	flash.texture = WeaponDB.cell(weapon_id, CELL_FLASH)
	flash.offset = Vector2(0, -flash.texture.get_height() * 0.5)  # kierto suun kohdalta

func equip(id: String = "pistol", start_facing: String = "down") -> void:
	fixture = ""
	_load_weapon(id)
	equipped = true
	facing = start_facing if CELL_HELD.has(start_facing) else "down"
	_cooldown = 0.15  # estää välittömän laukauksen poimintaklikistä
	_apply_facing()
	sprite.show()
	_set_pose(WeaponDB.hold_pose(weapon_id))
	var hud := _hud()
	if hud and hud.has_method("set_weapon"):
		hud.set_weapon(weapon_id)

func unequip() -> void:
	# Paikalleen kuuluva esine lähti kädestä muuten kuin pudottamalla
	# (kaappiin, takavarikkoon, säilöön): se ei enää ilmesty omalle paikalleen.
	if fixture != "":
		Game.fixtures[fixture] = "gone"
		fixture = ""
	equipped = false
	_swing_t = 0.0
	sprite.rotation = 0.0
	weapon_id = ""
	weapon_name = ""
	sprite.hide()
	flash.hide()
	_set_pose(0)
	var hud := _hud()
	if hud and hud.has_method("set_weapon"):
		hud.set_weapon("")

## Suunta seuraa liikettä (kuten ilman asetta). Vain ampuessa pelaaja
## kääntyy hetkeksi hiiren suuntaan. Kutsutaan joka fysiikkaruudussa.
func update(delta: float, move: Vector2 = Vector2.ZERO) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_aim_hold = maxf(_aim_hold - delta, 0.0)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			flash.hide()
	if not equipped:
		return

	if _aim_hold <= 0.0 and move != Vector2.ZERO:
		facing = _facing_from(move)
	_apply_facing()

	# Lähiaseen heilautus: ase kääntyy hetkeksi
	if _swing_t > 0.0:
		_swing_t -= delta
		sprite.rotation = sin((1.0 - _swing_t / 0.18) * PI) * (1.2 if facing != "left" else -1.2)
		if _swing_t <= 0.0:
			sprite.rotation = 0.0

	var p := get_parent()
	if p and p.get("blocking"):
		return
	if _cooldown <= 0.0 and Input.is_action_pressed("shoot"):
		_fire()

## Onko pelaaja juuri ampunut (animaatio seuraa silloin ampumasuuntaa)?
func is_aiming() -> bool:
	return equipped and _aim_hold > 0.0 and not _melee

func is_melee() -> bool:
	return equipped and _melee

func _facing_from(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "right" if v.x > 0.0 else "left"
	return "down" if v.y > 0.0 else "up"

func _apply_facing() -> void:
	sprite.texture = _textures[facing]
	# Ylös katsoessa ase jää vartalon taakse
	sprite.z_index = -1 if facing == "up" else 0

func _fire() -> void:
	# Krapula: hitaampi tulitus ja käsi tärisee (Player2D.hangover)
	var owner_node := get_parent()
	var fire_mult := 1.0
	var extra_spread := 0.0
	if owner_node and owner_node.has_method("hangover_fire_mult"):
		fire_mult = owner_node.hangover_fire_mult()
		extra_spread = owner_node.hangover_spread()
	_cooldown = _fire_interval * fire_mult
	if _melee:
		_swing()
		return
	_aim_hold = 0.35
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > 4.0:
		facing = _facing_from(to_mouse)
	_apply_facing()

	var muzzle_global: Vector2 = global_position + _muzzle()
	var dir := get_global_mouse_position() - muzzle_global
	if dir.length() < 2.0:
		dir = _facing_vector()
	dir = dir.normalized()
	var spread := _spread + extra_spread
	if spread > 0.0:
		dir = dir.rotated(randf_range(-spread, spread))

	for i in _pellets:
		var d := dir
		if _pellets > 1:
			d = dir.rotated(randf_range(-spread, spread))
		var bullet := BULLET_SCENE.instantiate()
		bullet.setup(d, get_parent(), _bullet_speed * randf_range(0.9, 1.0) if _pellets > 1 else _bullet_speed, _damage, _range)
		get_tree().current_scene.add_child(bullet)
		bullet.global_position = muzzle_global

	flash.position = _muzzle()
	flash.rotation = dir.angle()
	flash.show()
	_flash_left = flash_time
	var pitch := 1.0
	if weapon_id == "rifle":
		pitch = 1.25
	elif weapon_id == "shotgun":
		pitch = 0.7
	Sfx.play("gun", muzzle_global, -3.0 if _pellets == 1 else 1.0, 0.06, pitch)

## Lähiaseen isku. Pullo hajoaa, kun kestävyys loppuu.
func _swing() -> void:
	_swing_t = 0.18
	var p := get_parent()
	if p == null or not p.has_method("melee_swing"):
		return
	var hit: bool = p.melee_swing(_reach, _damage, _lethal)
	if hit and durability > 0:
		durability -= 1
		if durability <= 0:
			Sfx.play("glass_break", global_position, 0.0, 0.1)
			var hud := _hud()
			if hud and hud.has_method("show_message"):
				hud.show_message("%s hajosi!" % weapon_name, 1.8)
			if fixture != "":
				Game.fixtures[fixture] = "broken"
				fixture = ""
			unequip()

## Pelaajan kuva aseasentoon (käsi ojennettuna kahvalle) tai takaisin.
func _set_pose(pose: int) -> void:
	var p := get_parent()
	if p and p.has_method("set_weapon_pose"):
		p.set_weapon_pose(pose)

func _muzzle() -> Vector2:
	var m = WeaponDB.muzzle(weapon_id, facing)
	return m if m != null else MUZZLE[facing]

func _facing_vector() -> Vector2:
	match facing:
		"right": return Vector2.RIGHT
		"left": return Vector2.LEFT
		"up": return Vector2.UP
	return Vector2.DOWN
