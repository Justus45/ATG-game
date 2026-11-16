extends Node
## Kadun tapahtumat: baarista tutut rähinöitsijät (Game.grudges) kostavat illalla ja yöllä.
## Game liittää tämän kenttään. Kun kostaja kaadetaan, kauna laimenee; kolmannen
## häviön jälkeen hän jättää pelaajan rauhaan.

const ThugScript := preload("res://scripts/world/StreetThug.gd")

const CHECK_MIN := 50.0
const CHECK_MAX := 110.0
const SPAWN_CHANCE := 0.45

var _timer := 60.0
var _active: Node = null
var _city: Node
var _player: Node2D


func _ready() -> void:
	add_to_group("street_events")
	var scene := get_tree().current_scene
	_city = scene.get_node_or_null("City")
	_player = scene.get_node_or_null("Player")


func _process(delta: float) -> void:
	if _city == null or _player == null:
		return
	if is_instance_valid(_active):
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = randf_range(CHECK_MIN, CHECK_MAX)
	if Game.grudges.is_empty() or Game.period() == "päivä":
		return
	if not _player_on_street():
		return
	if randf() > SPAWN_CHANCE:
		return
	_spawn_revenge(Game.random_grudge())


## Pelaaja kävelee kadulla (ei autossa, ei sisätiloissa, ei putkassa eikä jahdissa).
func _player_on_street() -> bool:
	if not _player.visible or not _player.is_physics_processing():
		return false
	if _player.get("police_locked") or _player.get("menu_locked"):
		return false
	if Game.player_indoors():
		return false
	var pm := get_tree().get_first_node_in_group("police_manager")
	if pm and pm.wanted > 0:
		return false
	return true


func _spawn_revenge(g: Dictionary) -> void:
	if g.is_empty():
		return
	var pc: Vector2i = _city.world_to_cell(_player.body_center())
	var cell := Vector2i(-1, -1)
	for i in 40:
		var off := Vector2.from_angle(randf() * TAU) * randf_range(9.0, 13.0)
		var c := pc + Vector2i(off.round())
		if _city.is_walkable(c):
			cell = c
			break
	if cell == Vector2i(-1, -1):
		return
	var t = ThugScript.new()
	t.city = _city
	t.mode = "grudge"
	t.base_row = int(g.get("row", 0))
	t.display_name = str(g.get("name", ""))
	t.cash = randi_range(10, 30)
	t.position = _city.entities.to_local(_city.cell_to_world(cell))
	_city.entities.add_child(t)
	_active = t
	t.say("%s: Muistatko mut baarista?! Nyt kostetaan!" % t.display_name, 2.8)
	Game.msg("%s tuli kostamaan baarin tappelun! Torju (F) tai juokse karkuun (Shift)." % t.display_name, 3.5)
	t.defeated.connect(_on_defeated.bind(g))


func _on_defeated(_thug: Node, g: Dictionary) -> void:
	var beaten := int(g.get("beaten", 1)) + 1
	g["beaten"] = beaten
	if beaten >= 3 or randf() < 0.4:
		Game.remove_grudge(g)
		Game.msg("%s luovutti lopullisesti. Hän ei enää kiusaa sinua." % str(g.get("name", "")), 3.0)
	else:
		Game.msg("%s kaatui, mutta kauna jäi." % str(g.get("name", "")), 2.5)
	Game.add_rep("criminals", 2)
