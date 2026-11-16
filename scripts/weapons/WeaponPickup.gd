extends Area2D
## Maassa oleva ase. Pelaaja nostaa sen E-näppäimellä (Player2D hoitaa nostamisen).
## weapon_id viittaa WeaponDB:n aseeseen ("pistol", "rifle", ...).

@export var weapon_id: String = "pistol"
## Pulssaava hohde + keinuva sprite, jotta ase huomataan helposti
@export var highlight: bool = false
## Hinta dollareina. 0 = ilmainen (esim. pudotettu ase). Asekauppa asettaa tämän.
@export var price: int = 0
## Paikalleen kuuluvan esineen tunniste (esim. "bar_cue"). Kulkee aseen mukana
## kädestä maahan ja takaisin, jotta esine ei monistu.
var fixture: String = ""

var _t: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	sprite.texture = WeaponDB.icon(weapon_id)
	# Kartan aloituspistooli on yksi ja sama esine (ei monistu latauksissa)
	if fixture == "" and name == "Pistol":
		fixture = "start_pistol"
	if fixture != "":
		add_to_group("fixture_pickups")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	set_process(highlight)

func _process(delta: float) -> void:
	_t += delta
	sprite.position.y = sin(_t * 3.0) * 1.5
	queue_redraw()

func _draw() -> void:
	if not highlight:
		return
	var pulse := 0.5 + 0.5 * sin(_t * 3.5)
	draw_circle(Vector2.ZERO, 13.0 + 2.0 * pulse, Color(1.0, 0.85, 0.2, 0.12 + 0.14 * pulse))
	draw_arc(Vector2.ZERO, 13.0 + 2.0 * pulse, 0.0, TAU, 28, Color(1.0, 0.85, 0.2, 0.85), 1.0)

func _hud() -> Node:
	return get_tree().current_scene.get_node_or_null("Hud")

func _on_body_entered(body: Node2D) -> void:
	if not body.has_method("pickup_weapon"):
		return
	body.nearby_weapon = self
	var holding: bool = body.has_method("has_weapon") and body.has_weapon()
	if holding and price <= 0:
		return # kädessä on jo ase, ei kehotetta
	var hud := _hud()
	if hud:
		hud.show_instruction(_prompt(holding))

func _prompt(holding: bool) -> String:
	var n := WeaponDB.display_name(weapon_id).to_lower()
	if price > 0:
		var text := "Paina E ostaaksesi: %s – %d $" % [n, price]
		if holding:
			text += "\n(nykyinen ase pudotetaan)"
		return text
	return "Paina E poimiaksesi aseen (%s)\nAmpuminen: hiiren vasen / välilyönti, pudotus: G, ryöstö: R" % n

func _on_body_exited(body: Node2D) -> void:
	if not body.has_method("pickup_weapon"):
		return
	if body.nearby_weapon == self:
		body.nearby_weapon = null
	var hud := _hud()
	if hud:
		hud.hide_instruction()

## Kutsutaan kun pelaaja on poiminut aseen.
func picked_up() -> void:
	var hud := _hud()
	if hud:
		hud.hide_instruction()
	queue_free()
