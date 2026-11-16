extends Area2D
## Ammus: lentää suoraan, katoaa osuessaan esteeseen tai kun kantama täyttyy.

@export var speed: float = 450.0
@export var max_distance: float = 320.0
@export var damage: int = 1
@export var hit_radius: float = 7.0

var direction: Vector2 = Vector2.RIGHT
var shooter: Node = null
## Armeijan / SWATin luoti: osuu vain pelaajaan
var enemy := false
var _travelled: float = 0.0

func _ready() -> void:
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)

func setup(dir: Vector2, who: Node, bullet_speed: float = -1.0, bullet_damage: int = -1, bullet_range: float = -1.0) -> void:
	direction = dir.normalized()
	shooter = who
	enemy = who != null and who.is_in_group("enemy_shooter")
	# Aseen omat arvot (WeaponDB) ohittavat oletukset
	if bullet_speed > 0.0:
		speed = bullet_speed
	if bullet_damage > 0:
		damage = bullet_damage
	if bullet_range > 0.0:
		max_distance = bullet_range

func _physics_process(delta: float) -> void:
	var from := global_position
	var step := direction * speed * delta
	global_position += step
	if _check_targets(from, global_position):
		return
	_travelled += step.length()
	if _travelled >= max_distance:
		queue_free()

## Osuuko luoti johonkin ammuttavaan (NPC, poliisi)? Tarkistus janalla, ettei nopea luoti ohita kohdetta.
func _check_targets(from: Vector2, to: Vector2) -> bool:
	# Armeijan / SWATin luodit osuvat vain pelaajaan (tai hänen autoonsa)
	if enemy:
		var pm := get_tree().get_first_node_in_group("police_manager")
		var p := get_tree().get_first_node_in_group("player")
		if pm == null or p == null:
			return false
		var t: Vector2 = pm.target_position()
		var closest_p := Geometry2D.get_closest_point_to_segment(t, from, to)
		var radius := 10.0 if pm.player_in_car() else hit_radius
		if closest_p.distance_to(t) <= radius:
			p.hurt(float(damage) * (0.5 if pm.player_in_car() else 1.0), shooter)
			queue_free()
			return true
		return false
	for n in get_tree().get_nodes_in_group("shootable"):
		if n == shooter or not n.has_method("hit_point"):
			continue
		var c: Vector2 = n.hit_point()
		var closest := Geometry2D.get_closest_point_to_segment(c, from, to)
		if closest.distance_to(c) <= hit_radius:
			n.take_damage(damage, shooter)
			queue_free()
			return true
	# Liikenneautot (eivät ole fysiikkakappaleita): osuma auton laatikkoon
	var mid := (from + to) * 0.5
	for n in get_tree().get_nodes_in_group("car_targets"):
		if n == shooter or not n.has_method("hit_rect"):
			continue
		var r: Rect2 = n.hit_rect()
		if r.has_point(to) or r.has_point(mid):
			n.take_damage(damage, shooter)
			queue_free()
			return true
	return false

func _on_body_entered(body: Node2D) -> void:
	if body == shooter:
		return
	if enemy:
		if body.is_in_group("player"):
			return   # hoidettu _check_targets:ssa
		if body is CharacterBody2D or body is StaticBody2D:
			queue_free()
		return
	# Myöhemmin: viholliset / NPC:t voivat toteuttaa take_damage(amount)
	if body.has_method("take_damage"):
		body.take_damage(damage, shooter)
	queue_free()
