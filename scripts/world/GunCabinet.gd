extends Node2D
## ASEKAAPPI (vanha koti ja kartano): aseita voi säilöä kaappiin ja ottaa sieltä.
## Sisältö on yhteinen (muuttofirma kantoi kaapin kartanoon) ja tallentuu pelin mukana
## (Game.gun_cabinet). Kaappi piirtää lasiovien takana sisällä olevat aseet.
##
## Käyttö: var gc := GUN_CABINET.new(); parent.add_child(gc); gc.setup(vasen_yläkulma_maailmassa, koko, e_kohta_maailmassa)

const CAPACITY := 8
const WOOD := Color(0.24, 0.15, 0.09)
const WOOD_L := Color(0.36, 0.23, 0.13)
const WOOD_D := Color(0.14, 0.09, 0.05)
const GLASS := Color(0.55, 0.72, 0.85, 0.28)
const FELT := Color(0.22, 0.08, 0.08)

var size := Vector2(20.0, 16.0)
## Kuinka paljon kaappi nousee törmäysalueen yläpuolelle (seinää vasten, px)
var top_h := 10.0
var _t := 0.0
static var _icons := {}


func setup(top_left: Vector2, p_size: Vector2, spot: Vector2, p_top_h: float = 10.0, spot_w: float = 26.0) -> void:
	size = p_size
	top_h = p_top_h
	global_position = top_left
	add_to_group("gun_cabinet")
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	body.position = size * 0.5
	InteractSpot.create(self, spot, Vector2(spot_w, 14.0), _prompt, _use)


func _process(delta: float) -> void:
	_t += delta
	if fmod(_t, 0.25) < delta:
		queue_redraw()


func _prompt() -> String:
	return "Paina E: asekaappi (%d/%d asetta)" % [Game.gun_cabinet.size(), CAPACITY]


func _hud() -> Node:
	var sc := get_tree().current_scene
	return sc.get_node_or_null("Hud") if sc else null


func _use(player: Node2D) -> void:
	var opts: Array = []
	var acts: Array = []
	var holding: bool = player.has_method("has_weapon") and player.has_weapon()
	var held_id: String = str(player.held_weapon.weapon_id) if holding else ""
	if holding:
		if Game.gun_cabinet.size() < CAPACITY:
			opts.append("Laita kaappiin: %s" % WeaponDB.display_name(held_id))
			acts.append(_store.bind(player))
		else:
			opts.append("(Kaappi on täynnä – ota ensin jokin pois)")
			acts.append(Callable())
	for i in Game.gun_cabinet.size():
		var id := str(Game.gun_cabinet[i])
		if holding:
			opts.append("Vaihda: ota %s, jätä %s" % [WeaponDB.display_name(id), WeaponDB.display_name(held_id)])
		else:
			opts.append("Ota: %s" % WeaponDB.display_name(id))
		acts.append(_take.bind(player, i))
	if opts.is_empty():
		Game.msg("Asekaappi on tyhjä. Tuo ase käteen ja laita se tänne talteen.", 2.5)
		return
	var cb := func(i: int) -> void:
		if i >= 0 and i < acts.size() and (acts[i] as Callable).is_valid():
			(acts[i] as Callable).call()
	var hud := _hud()
	if hud and hud.has_method("show_menu"):
		hud.show_menu("ASEKAAPPI  %d/%d\nAseet säilyvät kaapissa myös tallennuksessa." % [Game.gun_cabinet.size(), CAPACITY], opts, cb)


func _store(player: Node2D) -> void:
	if not player.has_weapon() or Game.gun_cabinet.size() >= CAPACITY:
		return
	var id := str(player.held_weapon.weapon_id)
	player.held_weapon.unequip()
	Game.gun_cabinet.append(id)
	Sfx.play_ui("clink", -6.0, 0.8)
	Game.msg("%s kaappiin. Kaapissa nyt %d asetta." % [WeaponDB.display_name(id), Game.gun_cabinet.size()], 2.0)
	queue_redraw()


func _take(player: Node2D, i: int) -> void:
	if i < 0 or i >= Game.gun_cabinet.size():
		return
	var id := str(Game.gun_cabinet[i])
	Game.gun_cabinet.remove_at(i)
	var note := ""
	if player.has_weapon():
		var old := str(player.held_weapon.weapon_id)
		player.held_weapon.unequip()
		Game.gun_cabinet.insert(i, old)
		note = " (%s jäi kaappiin)" % WeaponDB.display_name(old)
	var face := "down"
	var spr := player.get("animated_sprite") as AnimatedSprite2D
	if spr:
		face = str(spr.animation).trim_prefix("walk_")
	player.held_weapon.equip(id, face)
	Sfx.play_ui("clink", -6.0, 1.1)
	Game.msg("Otit kaapista: %s%s." % [WeaponDB.display_name(id), note], 2.0)
	queue_redraw()


func _icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var path := "res://assets/sprites/weapons/%s.png" % id
	var t: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_icons[id] = t
	return t


func _draw() -> void:
	var w := size.x
	var h := size.y
	# varjo ja runko (seisoo seinää vasten, katsotaan hieman ylhäältä)
	draw_rect(Rect2(1.0, h - 1.0, w, 3.0), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(0.0, -top_h, w, h + top_h), WOOD)
	draw_rect(Rect2(0.0, -top_h, w, 3.0), WOOD_L)                 # kansi
	draw_rect(Rect2(0.0, h - 3.0, w, 3.0), WOOD_D)               # sokkeli
	# lasiovet, verhoiltu tausta ja aseet telineessä
	var inner := Rect2(2.0, -top_h + 4.0, w - 4.0, h + top_h - 9.0)
	draw_rect(inner, FELT)
	var n := Game.gun_cabinet.size()
	if n > 0:
		var slot_w := inner.size.x / float(n)
		for i in n:
			var tex := _icon(str(Game.gun_cabinet[i]))
			var cx := inner.position.x + slot_w * (i + 0.5)
			if tex:
				# ase pystyssä (piippu ylös), mahtuu kaapin korkeuteen
				var ts := tex.get_size()
				var sc := minf((inner.size.y - 2.0) / maxf(ts.x, 1.0), minf(slot_w * 1.6, 7.0) / maxf(ts.y, 1.0))
				draw_set_transform(Vector2(cx, inner.get_center().y), -PI * 0.5, Vector2(sc, sc))
				draw_texture(tex, -ts * 0.5)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				draw_line(Vector2(cx, inner.end.y - 1.0), Vector2(cx, inner.position.y + 2.0), Color(0.1, 0.1, 0.12), 1.5)
	else:
		TextFit.draw(self, ThemeDB.fallback_font, Vector2(inner.position.x, inner.get_center().y + 2.0), "TYHJÄ", inner.size.x, 4, Color(1, 1, 1, 0.35))
	draw_rect(inner, GLASS)
	var gx := fmod(_t * 6.0, inner.size.x + 10.0) - 5.0
	if gx > 0.0 and gx < inner.size.x - 2.0:
		draw_line(Vector2(inner.position.x + gx, inner.position.y + 1.0), Vector2(inner.position.x + gx + 2.0, inner.end.y - 1.0), Color(1, 1, 1, 0.2), 1.0)
	draw_line(Vector2(w * 0.5, inner.position.y), Vector2(w * 0.5, inner.end.y), WOOD_L, 1.0)   # ovien sauma
	draw_rect(inner, WOOD_D, false, 1.0)
	draw_rect(Rect2(w * 0.5 - 2.0, inner.get_center().y, 1.0, 2.0), Color(0.85, 0.72, 0.35))   # vetimet
	draw_rect(Rect2(w * 0.5 + 1.0, inner.get_center().y, 1.0, 2.0), Color(0.85, 0.72, 0.35))
	draw_rect(Rect2(w * 0.5 - 1.0, inner.get_center().y + 3.0, 2.0, 2.0), Color(0.7, 0.7, 0.75))  # lukko
	draw_rect(Rect2(0.0, -top_h, w, h + top_h), Color(0, 0, 0, 0.6), false, 1.0)
