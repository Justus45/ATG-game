class_name InteractSpot
extends Area2D
## Yleinen E-kohde: kun pelaaja astuu alueelle, HUD näyttää kehotteen ja pelaajan
## nearby_portal osoittaa tähän, jolloin E kutsuu use() -> action(player).
## prompt voi olla myös Callable, joka palauttaa tekstin (esim. aukioloajat).
##
## Luonti:  InteractSpot.create(parent, world_center, Vector2(24, 22), "Paina E ...", func(p): ...)

var prompt: Variant = ""
var action: Callable


static func create(parent: Node, center: Vector2, size_px: Vector2, prompt_text: Variant, act: Callable) -> InteractSpot:
	var h := InteractSpot.new()
	h.prompt = prompt_text
	h.action = act
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size_px
	cs.shape = shape
	h.add_child(cs)
	parent.add_child(h)
	h.global_position = center
	return h


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)


func prompt_text() -> String:
	if prompt is Callable:
		return str((prompt as Callable).call())
	return str(prompt)


func _hud() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("Hud") if scene else null


func _on_enter(body: Node2D) -> void:
	if not body.has_method("pickup_weapon"):
		return
	body.nearby_portal = self
	var hud := _hud()
	if hud:
		hud.show_instruction(prompt_text())


func _on_exit(body: Node2D) -> void:
	if not body.has_method("pickup_weapon"):
		return
	if body.nearby_portal != self:
		return
	body.nearby_portal = null
	var hud := _hud()
	# Vierekkäiset kohteet: siirrytään suoraan naapuriin, jos pelaaja on sen päällä
	for n in get_parent().get_children():
		if n != self and n is Area2D and n.has_method("use") and n.has_method("overlaps_body") and n.overlaps_body(body):
			body.nearby_portal = n
			if hud:
				var t: String = n.prompt_text() if n.has_method("prompt_text") else str(n.get("prompt"))
				hud.show_instruction(t)
			return
	if hud:
		hud.hide_instruction()


func use(player: Node2D) -> void:
	if action.is_valid():
		action.call(player)
	# Kehote voi muuttua (esim. jääkaapin sisältö): päivitetään
	var hud := _hud()
	if hud and is_instance_valid(player) and player.get("nearby_portal") == self and not (hud.has_method("menu_open") and hud.menu_open()):
		hud.show_instruction(prompt_text())
