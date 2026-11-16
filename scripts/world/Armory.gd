extends Node2D
## Asekauppa.
##  - ulkopuoli: erottuva katto (tumma + keltamusta varoitusreuna + tähtäinristikko),
##    iso kyltti ja pulssaava merkki oven edessä
##  - ovi: E-näppäin oven edessä vie erilliseen sisätilaan (kartan ulkopuolella)
##  - sisätila: huone, jossa rynnäkkökivääri on jalustalla; ulos pääsee ovesta (E)
##
## CityGenerator luo tämän ja kutsuu setup():ia. Ei viittaa CityGeneratoriin tyypillä,
## ettei skriptien välille synny kehäriippuvuutta.

const WEAPON_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/weapons/weapon_pickup.tscn")

const TILE := 16

# Sisätilan tiilet kaupungin tilemapista (samat kuin city_generator.gd:ssä)
const FLOOR_TILE := Vector2i(1, 4)   # beige lattia, ei törmäystä
const WALL_TILE := Vector2i(19, 2)   # punainen tiiliseinä, kiinteä
const DOOR_TILE := Vector2i(13, 10)

const ROOM_W := 20
const ROOM_H := 12
## Sisätila sijaitsee kartan ulkopuolella, kamera siirretään sinne sisään mentäessä
const INTERIOR_ORIGIN := Vector2(-1800.0, -1800.0)
const EXIT_CELL := Vector2i(10, 11)
const PEDESTAL_CELL := Vector2i(10, 4)
const SPAWN_CELL := Vector2i(10, 8)
## Pistooli myynnissä haulikon vastapuolella
const PISTOL_CELL := Vector2i(14, 5)
## Kranaattilaatikko vasemmalla seinustalla
const GRENADE_CELL := Vector2i(3, 8)
const GRENADE_PRICE := 60

const YELLOW := Color(0.98, 0.8, 0.15)
const CHARCOAL := Color(0.13, 0.14, 0.19)

## Onko pelaaja sisällä (HUD:n minikartta piiloutuu kun tämä on tosi)
var inside := false
## Oven keskipiste maailmassa (HUD:n minikartta näyttää tämän kohdan)
var door_px := Vector2.ZERO

var _busy := false
var _saved_limits := {}
var _interior: Node2D
var _fade: ColorRect


## roof = katon suorakulmio pikseleinä, door_center = ovitiilen keskipiste maailmassa.
func setup(tile_set: TileSet, source_id: int, roof: Rect2, door_center: Vector2) -> void:
	add_to_group("armory")
	global_position = Vector2.ZERO  # kaikki piirtokoordinaatit ovat maailmankoordinaatteja
	door_px = door_center

	# --- ulkopuoli ---
	var ext := ExteriorView.new()
	ext.roof = roof
	ext.sign_rect = Rect2(roof.position.x + 8.0, roof.end.y - 19.0, roof.size.x - 16.0, 14.0)
	ext.door_front = door_center + Vector2(0.0, TILE)
	ext.z_index = 50
	add_child(ext)

	_add_portal(door_center + Vector2(0.0, 17.0), true, "Paina E mennäksesi sisään (asekauppa)")

	# --- sisätila ---
	_build_interior(tile_set, source_id)

	# --- häivytys ---
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	# Turvaverkko: jos pelaaja on siirretty pois sisätilasta (esim. pidätys), palautetaan kamera
	if not inside or _busy:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and player.global_position.distance_to(INTERIOR_ORIGIN) > 1200.0:
		inside = false
		_set_camera_limits(false)


# ----------------------------------------------------------------------------
#  SISÄTILA
# ----------------------------------------------------------------------------
func _cell_center(c: Vector2i) -> Vector2:
	return INTERIOR_ORIGIN + Vector2(c.x * TILE + TILE * 0.5, c.y * TILE + TILE * 0.5)


func _build_interior(tile_set: TileSet, source_id: int) -> void:
	_interior = Node2D.new()
	_interior.name = "Interior"
	_interior.position = INTERIOR_ORIGIN
	add_child(_interior)

	# Musta tausta huoneen ympärille
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04)
	bg.position = Vector2(-1500.0, -1500.0)
	bg.size = Vector2(3000.0 + ROOM_W * TILE, 3000.0 + ROOM_H * TILE)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -20
	_interior.add_child(bg)

	var floor_layer := TileMapLayer.new()
	floor_layer.tile_set = tile_set
	_interior.add_child(floor_layer)
	for y in ROOM_H:
		for x in ROOM_W:
			var wall := x == 0 or x == ROOM_W - 1 or y <= 1 or y == ROOM_H - 1
			floor_layer.set_cell(Vector2i(x, y), source_id, WALL_TILE if wall else FLOOR_TILE)

	var deco_layer := TileMapLayer.new()
	deco_layer.tile_set = tile_set
	_interior.add_child(deco_layer)
	deco_layer.set_cell(EXIT_CELL, source_id, DOOR_TILE)

	var view := InteriorView.new()
	view.armory = self
	view.price = WeaponDB.get_data("rifle").price
	view.pedestal = Vector2(PEDESTAL_CELL.x * TILE + TILE * 0.5, PEDESTAL_CELL.y * TILE + TILE * 0.5)
	view.exit_pos = Vector2(EXIT_CELL.x * TILE + TILE * 0.5, EXIT_CELL.y * TILE + TILE * 0.5)
	_interior.add_child(view)

	_add_portal(_cell_center(EXIT_CELL) + Vector2(0.0, -17.0), false, "Paina E poistuaksesi")

	# Kalusteiden törmäysmuodot (huoneen paikallisissa koordinaateissa)
	var body := StaticBody2D.new()
	_interior.add_child(body)
	for r: Rect2 in InteriorView.SOLIDS:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = r.size
		cs.shape = shape
		cs.position = r.get_center()
		body.add_child(cs)
	# Myyjä Erkki tiskin takana
	var keeper := Sprite2D.new()
	keeper.offset = Vector2(0, -4)
	keeper.texture = CHAR_SPRITES.npc(0, 6)
	keeper.position = InteriorView.KEEPER_POS
	_interior.add_child(keeper)
	view.keeper = keeper
	InteractSpot.create(_interior, INTERIOR_ORIGIN + Vector2(250.0, 128.0), Vector2(18.0, 34.0),
		"Paina E jutellaksesi myyjä Erkin kanssa", _talk_keeper)

	_spawn_rifle()
	_spawn_item("shotgun", Vector2i(5, 5))
	_spawn_item("pistol", PISTOL_CELL)
	view.grenade_pos = Vector2(GRENADE_CELL.x * TILE + TILE * 0.5, GRENADE_CELL.y * TILE + TILE * 0.5)
	InteractSpot.create(_interior, _cell_center(GRENADE_CELL) + Vector2(0.0, 10.0), Vector2(28.0, 24.0),
		_grenade_prompt, _buy_grenade)
	# Kevlarliivi mallinuken päällä
	view.vest_pos = VEST_POS
	var vcs := CollisionShape2D.new()
	var vshape := RectangleShape2D.new()
	vshape.size = Vector2(10.0, 6.0)
	vcs.shape = vshape
	vcs.position = VEST_POS + Vector2(0.0, -3.0)
	body.add_child(vcs)
	InteractSpot.create(_interior, INTERIOR_ORIGIN + VEST_POS + Vector2(0.0, 12.0), Vector2(26.0, 16.0),
		_vest_prompt, _buy_vest)


const CHAR_SPRITES := preload("res://scripts/core/CharSprites.gd")
const KEEPER_LINES := [
	"Erkki: \"Rynnäkkökivääri on myynnin hitti. Kysy vaikka poliisilta.\"",
	"Erkki: \"Kranaatit heitetään, ei syödä. Sanon tän joka päivä.\"",
	"Erkki: \"Pistooli on hyvä alku. Ja usein myös loppu.\"",
	"Erkki: \"Haulikko lähietäisyydeltä on varma kuin vero.\"",
	"Erkki: \"Älä ammu täällä sisällä. Mä just maalasin.\"",
	"Erkki: \"Takuu? Takuu on se, että se pamahtaa.\"",
]

const VEST_POS := Vector2(204.0, 134.0)   ## mallinuken jalusta (huoneen koordinaatit)


func _vest_prompt() -> String:
	if Game.armor >= Game.ARMOR_MAX:
		return "Kevlarliivi on jo päällä ja ehjä"
	if Game.armor > 0.0:
		return "Paina E: vaihda uusi kevlarliivi (%d $, nykyinen %d %%)" % [Game.VEST_PRICE, roundi(Game.armor / Game.ARMOR_MAX * 100.0)]
	return "Paina E: osta ja pue kevlarliivi (%d $)" % Game.VEST_PRICE


func _buy_vest(player: Node2D) -> void:
	if Game.armor >= Game.ARMOR_MAX:
		Game.msg("Erkki: \"Sulla on jo liivi päällä. Ei niitä kahta päällekkäin pueta.\"", 2.5)
		return
	if int(player.money) < Game.VEST_PRICE:
		Sfx.play_ui("denied", -6.0)
		Game.msg("Ei tarpeeksi rahaa: %d $ / %d $" % [int(player.money), Game.VEST_PRICE], 2.0)
		return
	player.add_money(-Game.VEST_PRICE)
	Game.armor = Game.ARMOR_MAX
	Game.vest_carried = 0.0   # vanha (riisuttu) liivi jää kauppaan
	Sfx.play_ui("cash", -4.0)
	Sfx.play("clang", player.global_position, -10.0, 0.05, 0.7)
	Game.msg("Kevlarliivi päällä. Se ottaa suurimman osan luodeista ja iskuista, kunnes hajoaa.", 3.5)
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud:
		hud.show_instruction(_vest_prompt())


## Erkin valikko: juttelu, kommandopipo ja (Kallen pankkikeikan aikana) C4.
func _talk_keeper(player: Node2D) -> void:
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud == null or not hud.has_method("show_menu"):
		Game.msg(KEEPER_LINES[randi() % KEEPER_LINES.size()], 3.5)
		return
	var opts: Array = ["Juttele Erkin kanssa",
		"Kommandopipo (%d $)%s" % [Game.MASK_PRICE, " – sinulla on jo" if Game.has_mask else ""]]
	opts.append("Nippusiteet, %d kpl (%d $, sinulla %d) – Z sitoo" % [Game.ZIP_TIE_PACK, Game.ZIP_TIE_PRICE, Game.zip_ties])
	if _heist_prep():
		opts.append("C4-räjähde (%d $, sinulla %d)" % [Game.C4_PRICE, Game.c4])
	hud.show_menu("ERKKI – ASEKAUPPA\nLompakko %d $" % int(player.money), opts, _keeper_choice.bind(player))


func _heist_prep() -> bool:
	var st := get_tree().get_first_node_in_group("story")
	return st != null and st.has_method("heist_prep") and st.heist_prep()


func _keeper_choice(i: int, player: Node2D) -> void:
	match i:
		0:
			if _heist_prep():
				Game.msg("Erkki: \"Kalle soitti. Iso keikka, vai? Mä en tiedä mitään, mut C4:ää mulla on.\"", 3.5)
			else:
				Game.msg(KEEPER_LINES[randi() % KEEPER_LINES.size()], 3.5)
		1:
			if Game.has_mask:
				Game.msg("Erkki: \"Yks pipo riittää. Päähän mahtuu vaan yks.\"", 2.5)
				return
			if int(player.money) < Game.MASK_PRICE:
				Sfx.play_ui("denied", -6.0)
				Game.msg("Ei tarpeeksi rahaa: %d $ / %d $" % [int(player.money), Game.MASK_PRICE], 2.0)
				return
			player.add_money(-Game.MASK_PRICE)
			Game.has_mask = true
			Sfx.play_ui("cash", -4.0)
			Game.msg("Kommandopipo taskuun. Erkki: \"Talviurheiluun, eiks? Just niin.\"", 3.0)
		2:
			if Game.zip_ties >= 30:
				Game.msg("Erkki: \"Sulla on jo siteitä koko kaupunginosalle.\"", 2.5)
				return
			if int(player.money) < Game.ZIP_TIE_PRICE:
				Sfx.play_ui("denied", -6.0)
				Game.msg("Ei tarpeeksi rahaa: %d $ / %d $" % [int(player.money), Game.ZIP_TIE_PRICE], 2.0)
				return
			player.add_money(-Game.ZIP_TIE_PRICE)
			Game.zip_ties += Game.ZIP_TIE_PACK
			Sfx.play_ui("cash", -4.0)
			Game.msg("Nippusiteitä %d kpl. Z sitoo lähellä olevan. Erkki: \"Sähkötöihin, eiks?\"" % Game.zip_ties, 3.5)
		3:
			if Game.c4 >= 2:
				Game.msg("Erkki: \"Kaks riittää kyllä. Mä en halua tietää mihin.\"", 2.5)
				return
			if int(player.money) < Game.C4_PRICE:
				Sfx.play_ui("denied", -6.0)
				Game.msg("Ei tarpeeksi rahaa: %d $ / %d $" % [int(player.money), Game.C4_PRICE], 2.0)
				return
			player.add_money(-Game.C4_PRICE)
			Game.c4 += 1
			Sfx.play_ui("cash", -4.0)
			Game.msg("C4-räjähde reppuun (%d kpl). Erkki: \"Älä pudota sitä. Ikinä.\"" % Game.c4, 3.0)


func _grenade_prompt() -> String:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return ""
	var have := int(p.grenades)
	var most := int(p.max_grenades())
	if have >= most:
		return "Kranaatteja täysi määrä (%d/%d)" % [have, most]
	return "Paina E ostaaksesi kranaatin – %d $ (sinulla %d/%d)" % [GRENADE_PRICE, have, most]


func _buy_grenade(player: Node2D) -> void:
	if int(player.grenades) >= int(player.max_grenades()):
		Sfx.play_ui("denied", -6.0)
		Game.msg("Taskut täynnä kranaatteja. Heitä ensin (Q).", 2.0)
		return
	if int(player.money) < GRENADE_PRICE:
		Sfx.play_ui("denied", -6.0)
		Game.msg("Ei tarpeeksi rahaa: %d $ / %d $" % [int(player.money), GRENADE_PRICE], 2.0)
		return
	player.add_money(-GRENADE_PRICE)
	player.add_grenades(1)
	Sfx.play_ui("cash", -4.0)
	Game.msg("Kranaatti taskuun (%d/%d). Q tai hiiren keskipainike heittää hiiren suuntaan." % [int(player.grenades), int(player.max_grenades())], 3.0)
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud:
		hud.show_instruction(_grenade_prompt())


func _spawn_rifle() -> void:
	var pickup := WEAPON_PICKUP_SCENE.instantiate()
	pickup.weapon_id = "rifle"
	pickup.highlight = true
	pickup.price = WeaponDB.get_data("rifle").price
	_interior.add_child(pickup)
	pickup.global_position = _cell_center(PEDESTAL_CELL) + Vector2(0.0, -4.0)


func _spawn_item(id: String, cell: Vector2i) -> void:
	var pickup := WEAPON_PICKUP_SCENE.instantiate()
	pickup.weapon_id = id
	pickup.highlight = true
	pickup.price = WeaponDB.get_data(id).price
	_interior.add_child(pickup)
	pickup.global_position = _cell_center(cell) + Vector2(0.0, -4.0)


func _item_present(id: String) -> bool:
	for c in _interior.get_children():
		if "weapon_id" in c and c.weapon_id == id and c.price > 0 and not c.is_queued_for_deletion():
			return true
	return false


## Onko kaupan myyntikivääri (hinnallinen) jalustalla? Ostettu ase tilataan uudelleen
## vasta kun pelaaja menee sisään seuraavan kerran.
func shop_item_present() -> bool:
	for c in _interior.get_children():
		if "weapon_id" in c and c.weapon_id == "rifle" and c.price > 0 and not c.is_queued_for_deletion():
			return true
	return false


# ----------------------------------------------------------------------------
#  OVET
# ----------------------------------------------------------------------------
func _add_portal(center: Vector2, to_inside: bool, prompt: String) -> void:
	var p := Portal.new()
	p.armory = self
	p.to_inside = to_inside
	p.prompt = prompt
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24.0, 22.0)
	cs.shape = shape
	p.add_child(cs)
	add_child(p)
	p.global_position = center


## Portaali kutsuu tätä kun pelaaja painaa E:tä.
const OPEN_HOUR := 9
const CLOSE_HOUR := 21

func use_portal(player: Node2D, to_inside: bool) -> void:
	if _busy:
		return
	if to_inside and not Game.is_open(OPEN_HOUR, CLOSE_HOUR):
		Sfx.play_ui("denied", -6.0)
		Game.msg("Asekauppa on kiinni. Auki %02d–%02d." % [OPEN_HOUR, CLOSE_HOUR], 2.0)
		return
	_busy = true
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	if "velocity" in player:
		player.velocity = Vector2.ZERO
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud:
		hud.hide_instruction()

	await _fade_to(1.0)
	if to_inside:
		inside = true
		_set_camera_limits(true)
		if not shop_item_present():
			_spawn_rifle()
		if not _item_present("shotgun"):
			_spawn_item("shotgun", Vector2i(5, 5))
		if not _item_present("pistol"):
			_spawn_item("pistol", PISTOL_CELL)
		_move_player(player, _cell_center(SPAWN_CELL))
	else:
		inside = false
		_set_camera_limits(false)
		_move_player(player, door_px + Vector2(0.0, 28.0))
	await _fade_to(0.0)

	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	_busy = false


func _fade_to(alpha: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, 0.18)
	await tw.finished


## Siirtää pelaajan niin, että hänen törmäysmuotonsa keskipiste on kohdassa target.
func _move_player(player: Node2D, target: Vector2) -> void:
	var col := player.get_node_or_null("CollisionShape2D") as Node2D
	var off := col.position if col else Vector2.ZERO
	player.global_position = target - off
	var cam := _camera()
	if cam:
		cam.global_position = target


func _camera() -> Camera2D:
	return get_viewport().get_camera_2d()


func _set_camera_limits(in_room: bool) -> void:
	var cam := _camera()
	if cam == null:
		return
	if in_room:
		if _saved_limits.is_empty():
			_saved_limits = {
				"l": cam.limit_left, "t": cam.limit_top,
				"r": cam.limit_right, "b": cam.limit_bottom,
			}
		var r := Rect2(INTERIOR_ORIGIN, Vector2(ROOM_W, ROOM_H) * TILE).grow(260.0)
		cam.limit_left = int(r.position.x)
		cam.limit_top = int(r.position.y)
		cam.limit_right = int(r.end.x)
		cam.limit_bottom = int(r.end.y)
	elif not _saved_limits.is_empty():
		cam.limit_left = _saved_limits.l
		cam.limit_top = _saved_limits.t
		cam.limit_right = _saved_limits.r
		cam.limit_bottom = _saved_limits.b
		_saved_limits = {}


# ----------------------------------------------------------------------------
#  SISÄ-LUOKAT
# ----------------------------------------------------------------------------
## Alue oven edessä: näyttää kehotteen ja kertoo pelaajalle mitä E tekee.
class Portal extends Area2D:
	var armory: Node2D
	var to_inside := true
	var prompt := ""

	func _ready() -> void:
		collision_layer = 0
		collision_mask = 1
		body_entered.connect(_on_enter)
		body_exited.connect(_on_exit)

	func _on_enter(body: Node2D) -> void:
		if not body.has_method("pickup_weapon"):
			return
		body.nearby_portal = self
		var hud := get_tree().current_scene.get_node_or_null("Hud")
		if hud:
			hud.show_instruction(prompt)

	func _on_exit(body: Node2D) -> void:
		if not body.has_method("pickup_weapon"):
			return
		if body.nearby_portal == self:
			body.nearby_portal = null
			var hud := get_tree().current_scene.get_node_or_null("Hud")
			if hud:
				hud.hide_instruction()

	func use(player: Node2D) -> void:
		armory.use_portal(player, to_inside)


## Rakennuksen päälle piirretty erottuva ulkoasu.
class ExteriorView extends Node2D:
	const TILE := 16
	const YELLOW := Color(0.98, 0.8, 0.15)
	const CHARCOAL := Color(0.13, 0.14, 0.19)
	var roof := Rect2()
	var sign_rect := Rect2()
	var door_front := Vector2.ZERO
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _on_screen(roof.grow(200.0)):
			queue_redraw()

	## Optimointi: piirretään uudelleen vain kun alue on kameran näkyvissä
	func _on_screen(r: Rect2) -> bool:
		var cam := get_viewport().get_camera_2d()
		if cam == null:
			return true
		var vs := get_viewport().get_visible_rect().size / cam.zoom
		var view := Rect2(cam.get_screen_center_position() - vs * 0.5, vs).grow(160.0)
		return view.intersects(get_global_transform() * r)

	func _draw() -> void:
		# Tumma katto + saumat
		draw_rect(roof, CHARCOAL)
		var x := roof.position.x + TILE
		while x < roof.end.x:
			draw_line(Vector2(x, roof.position.y), Vector2(x, roof.end.y), Color(1, 1, 1, 0.05), 1.0)
			x += TILE
		var y := roof.position.y + TILE
		while y < roof.end.y:
			draw_line(Vector2(roof.position.x, y), Vector2(roof.end.x, y), Color(1, 1, 1, 0.05), 1.0)
			y += TILE
		_hazard_border(roof, 4.0)

		# Punainen tähtäinristikko katolla
		var red := Color(0.9, 0.2, 0.18)
		var c := roof.get_center() + Vector2(0.0, -6.0)
		var r := minf(roof.size.x, roof.size.y) * 0.22
		draw_arc(c, r, 0.0, TAU, 32, red, 2.0)
		draw_line(c + Vector2(-r * 1.5, 0.0), c + Vector2(-r * 0.45, 0.0), red, 2.0)
		draw_line(c + Vector2(r * 0.45, 0.0), c + Vector2(r * 1.5, 0.0), red, 2.0)
		draw_line(c + Vector2(0.0, -r * 1.5), c + Vector2(0.0, -r * 0.45), red, 2.0)
		draw_line(c + Vector2(0.0, r * 0.45), c + Vector2(0.0, r * 1.5), red, 2.0)
		draw_circle(c, 1.5, red)

		# Kyltti
		draw_rect(sign_rect, Color(0.05, 0.05, 0.08))
		draw_rect(sign_rect, YELLOW, false, 1.0)
		var font := ThemeDB.fallback_font
		TextFit.draw(self, font, Vector2(sign_rect.position.x, sign_rect.position.y + 11.0), "ASEKAUPPA", sign_rect.size.x, 11, YELLOW)

		# Pulssaava merkki oven edessä
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		var rad := 9.0 + 2.0 * pulse
		draw_circle(door_front, rad, Color(1.0, 0.85, 0.2, 0.15 + 0.2 * pulse))
		draw_arc(door_front, rad, 0.0, TAU, 24, Color(1.0, 0.85, 0.2, 0.9), 1.0)
		# Pomppiva nuoli oveen päin
		var bob := absf(sin(_t * 3.0)) * 3.0
		var tip := door_front + Vector2(0.0, 24.0 - bob)
		draw_colored_polygon(PackedVector2Array([
			tip + Vector2(0.0, -8.0), tip + Vector2(-5.0, 0.0), tip + Vector2(5.0, 0.0)]), YELLOW)

	func _hazard_border(r: Rect2, th: float) -> void:
		var dark := Color(0.08, 0.08, 0.1)
		var step := 4.0
		var n := int(r.size.x / step)
		for i in n:
			var col := YELLOW if i % 2 == 0 else dark
			draw_rect(Rect2(r.position.x + i * step, r.position.y, step, th), col)
			draw_rect(Rect2(r.position.x + i * step, r.end.y - th, step, th), col)
		var m := int(r.size.y / step)
		for j in m:
			var col2 := YELLOW if j % 2 == 0 else dark
			draw_rect(Rect2(r.position.x, r.position.y + j * step, th, step), col2)
			draw_rect(Rect2(r.end.x - th, r.position.y + j * step, th, step), col2)


## Sisätilan koristeet: matto, jalusta, kiväärihyllyt, tekstit.
class InteriorView extends Node2D:
	const YELLOW := Color(0.98, 0.8, 0.15)
	var armory: Node2D
	var price := 0
	var pedestal := Vector2.ZERO
	var grenade_pos := Vector2.ZERO
	var vest_pos := Vector2.ZERO
	var exit_pos := Vector2.ZERO
	var keeper: Sprite2D
	var _t := 0.0

	## Kalusteet (huoneen paikalliset koordinaatit; lattia x 16..304, y 32..176)
	const CASE := Rect2(18, 40, 18, 64)         ## lasivitriini vasemmalla seinällä
	const BENCH_WORK := Rect2(42, 34, 38, 12)   ## työpöytä takaseinällä
	const SAFE := Rect2(212, 34, 20, 16)        ## asekaappi
	const COUNTER := Rect2(262, 100, 14, 60)    ## myyntitiski oikealla
	const AMMO := Rect2(18, 150, 28, 22)        ## ammuslaatikkopino
	const BENCH := Rect2(212, 158, 30, 10)      ## odotuspenkki
	const PLANT_A := Rect2(120, 160, 12, 12)
	const PLANT_B := Rect2(286, 162, 12, 12)
	const SOLIDS := [CASE, BENCH_WORK, SAFE, COUNTER, AMMO, BENCH, PLANT_A, PLANT_B]
	const KEEPER_POS := Vector2(290, 126)

	func _process(delta: float) -> void:
		_t += delta
		if _on_screen(Rect2(-100.0, -100.0, 520.0, 400.0)):
			queue_redraw()

	## Optimointi: piirretään uudelleen vain kun alue on kameran näkyvissä
	func _on_screen(r: Rect2) -> bool:
		var cam := get_viewport().get_camera_2d()
		if cam == null:
			return true
		var vs := get_viewport().get_visible_rect().size / cam.zoom
		var view := Rect2(cam.get_screen_center_position() - vs * 0.5, vs).grow(160.0)
		return view.intersects(get_global_transform() * r)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		_draw_room(font)
		# Punainen matto ovelta jalustalle
		var carpet := Rect2(pedestal.x - 16.0, pedestal.y, 32.0, exit_pos.y - pedestal.y - 8.0)
		draw_rect(carpet, Color(0.62, 0.12, 0.14))
		draw_rect(carpet, YELLOW, false, 1.0)
		draw_rect(carpet.grow(-3.0), Color(0.5, 0.08, 0.1), false, 1.0)

		# Kiväärihyllyt takaseinällä
		for i in 3:
			var cx := 56.0 + i * 104.0
			_rack(Vector2(cx, 6.0))

		# Jalusta + valokeila
		var pulse := 0.5 + 0.5 * sin(_t * 3.5)
		draw_circle(pedestal + Vector2(0.0, 2.0), 17.0 + 2.0 * pulse, Color(1.0, 0.85, 0.2, 0.10 + 0.08 * pulse))
		draw_rect(Rect2(pedestal.x - 12.0, pedestal.y + 2.0, 24.0, 8.0), Color(0.16, 0.17, 0.22))
		draw_rect(Rect2(pedestal.x - 12.0, pedestal.y + 2.0, 24.0, 8.0), YELLOW, false, 1.0)

		if armory and armory.shop_item_present():
			# Hintalappu
			var tag := Rect2(pedestal.x - 52.0, pedestal.y - 34.0, 104.0, 24.0)
			draw_rect(tag, Color(0.05, 0.05, 0.08, 0.9))
			draw_rect(tag, YELLOW, false, 1.0)
			TextFit.draw(self, font, Vector2(tag.position.x, tag.position.y + 10.0), "RYNNÄKKÖKIVÄÄRI", tag.size.x, 9, Color.WHITE)
			TextFit.draw(self, font, Vector2(tag.position.x, tag.position.y + 21.0), "%d $" % price, tag.size.x, 11, YELLOW)
		TextFit.draw(self, font, Vector2(exit_pos.x - 30.0, exit_pos.y - 20.0), "ULOS", 60.0, 8, Color(1, 1, 1, 0.8))
		draw_string(font, Vector2(8.0, 12.0), "ASEKAUPPA", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.35))
		if grenade_pos != Vector2.ZERO:
			_grenade_crate(grenade_pos, font)
		if vest_pos != Vector2.ZERO:
			_vest_stand(vest_pos, font)
		_draw_furniture(font)
		# myyjä vilkuilee välillä asiakasta
		if keeper:
			keeper.texture = CHAR_SPRITES_V.npc(1 if fmod(_t, 6.0) < 2.0 else 0, 6)

	const CHAR_SPRITES_V := preload("res://scripts/core/CharSprites.gd")

	## Lattia, seinäkoristeet ja valot (ennen mattoa ja kalusteita).
	func _draw_room(font: Font) -> void:
		# tumma laattalattia
		for y in range(32, 176, 16):
			for x in range(16, 304, 16):
				var dark := ((x / 16) + (y / 16)) % 2 == 0
				draw_rect(Rect2(x, y, 16, 16), Color(0.2, 0.21, 0.25) if dark else Color(0.24, 0.25, 0.29))
				draw_rect(Rect2(x, y, 16, 1), Color(1, 1, 1, 0.04))
				draw_rect(Rect2(x, y, 1, 16), Color(0, 0, 0, 0.12))
		# jalkalista takaseinän alla
		draw_rect(Rect2(16, 30, 288, 2), Color(0.12, 0.1, 0.1))
		# maalitaulut seinällä hyllyjen välissä
		for cx in [108.0, 212.0]:
			draw_rect(Rect2(cx - 10.0, 5.0, 20.0, 22.0), Color(0.93, 0.9, 0.82))
			draw_rect(Rect2(cx - 10.0, 5.0, 20.0, 22.0), Color(0.3, 0.25, 0.2), false, 1.0)
			for k in 4:
				draw_arc(Vector2(cx, 15.0), 8.0 - k * 2.0, 0.0, TAU, 16, Color(0.15, 0.15, 0.15) if k % 2 == 0 else Color(0.8, 0.15, 0.12), 1.0)
			draw_circle(Vector2(cx, 15.0), 1.0, Color(0.8, 0.15, 0.12))
			# luodinreiät
			draw_circle(Vector2(cx + 2.5, 13.0), 0.7, Color(0.1, 0.1, 0.1))
			draw_circle(Vector2(cx - 3.0, 18.0), 0.7, Color(0.1, 0.1, 0.1))
		# valvontakamera oikeassa yläkulmassa, punainen valo vilkkuu
		draw_rect(Rect2(292, 33, 10, 5), Color(0.75, 0.75, 0.8))
		draw_rect(Rect2(288, 34, 5, 3), Color(0.25, 0.25, 0.3))
		if fmod(_t, 1.2) < 0.4:
			draw_circle(Vector2(300, 35.5), 1.0, Color(1.0, 0.2, 0.2))
		# kattovalojen valokeilat
		for p in [Vector2(88, 84), Vector2(168, 116), Vector2(248, 84)]:
			for i in 4:
				draw_circle(p, 46.0 - i * 10.0, Color(1.0, 0.92, 0.7, 0.03))

	## Vitriini, työpöytä, kaappi, tiski kassoineen, ammuslaatikot, penkki ja kasvit.
	func _draw_furniture(font: Font) -> void:
		var ol := Color(0, 0, 0, 0.55)
		# lasivitriini: pistooleja ja veitsiä lasin alla
		draw_rect(CASE, Color(0.35, 0.36, 0.42))
		var glass := CASE.grow(-2.0)
		draw_rect(glass, Color(0.55, 0.75, 0.85, 0.35))
		for k in 4:
			var y := glass.position.y + 6.0 + k * 14.0
			draw_rect(Rect2(glass.position.x + 3.0, y, 8.0, 2.5), Color(0.2, 0.2, 0.24))
			draw_rect(Rect2(glass.position.x + 3.0, y + 2.0, 2.5, 3.0), Color(0.15, 0.15, 0.18))
			draw_rect(Rect2(glass.position.x + 3.0, y + 7.0, 9.0, 1.2), Color(0.8, 0.82, 0.88))
			draw_rect(Rect2(glass.position.x + 3.0, y + 7.0, 3.0, 1.5), Color(0.2, 0.12, 0.08))
		draw_line(glass.position + Vector2(2, 3), glass.position + Vector2(8, 15), Color(1, 1, 1, 0.35), 1.0)
		draw_rect(CASE, ol, false, 1.0)
		# työpöytä: ruuvipuristin, työkaluja, öljypullo
		draw_rect(BENCH_WORK, Color(0.45, 0.3, 0.17))
		draw_rect(Rect2(BENCH_WORK.position.x, BENCH_WORK.end.y - 3.0, BENCH_WORK.size.x, 3.0), Color(0.33, 0.21, 0.11))
		draw_rect(Rect2(BENCH_WORK.position.x + 4.0, BENCH_WORK.position.y + 2.0, 8.0, 5.0), Color(0.4, 0.45, 0.55))
		draw_rect(Rect2(BENCH_WORK.position.x + 16.0, BENCH_WORK.position.y + 4.0, 10.0, 1.5), Color(0.75, 0.75, 0.8))
		draw_rect(Rect2(BENCH_WORK.position.x + 16.0, BENCH_WORK.position.y + 4.0, 3.0, 1.5), Color(0.8, 0.2, 0.15))
		draw_rect(Rect2(BENCH_WORK.position.x + 30.0, BENCH_WORK.position.y + 1.0, 3.0, 6.0), Color(0.85, 0.7, 0.2))
		draw_rect(BENCH_WORK, ol, false, 1.0)
		# asekaappi: teräs, kahva, numerolukko
		draw_rect(SAFE, Color(0.3, 0.33, 0.38))
		draw_rect(SAFE.grow(-2.0), Color(0.36, 0.39, 0.45))
		draw_circle(SAFE.get_center() + Vector2(2, 0), 2.5, Color(0.7, 0.7, 0.75))
		draw_rect(Rect2(SAFE.position.x + 4.0, SAFE.position.y + 6.0, 1.5, 5.0), Color(0.75, 0.75, 0.8))
		draw_rect(SAFE, ol, false, 1.0)
		# myyntitiski: puuta, lasikansi, kassakone, mainoskyltti
		draw_rect(COUNTER, Color(0.42, 0.27, 0.15))
		draw_rect(Rect2(COUNTER.position.x + 1.0, COUNTER.position.y + 1.0, COUNTER.size.x - 2.0, COUNTER.size.y - 2.0), Color(0.55, 0.75, 0.85, 0.25))
		draw_rect(Rect2(COUNTER.position.x - 1.0, COUNTER.position.y + 6.0, 16.0, 12.0), Color(0.2, 0.21, 0.25))
		draw_rect(Rect2(COUNTER.position.x + 1.0, COUNTER.position.y + 7.0, 12.0, 4.0), Color(0.3, 0.8, 0.45))
		for k in 3:
			draw_rect(Rect2(COUNTER.position.x + 1.5 + k * 4.0, COUNTER.position.y + 13.0, 3.0, 2.0), Color(0.75, 0.75, 0.8))
		for k in 2:
			draw_rect(Rect2(COUNTER.position.x + 3.0, COUNTER.position.y + 30.0 + k * 12.0, 8.0, 3.0), Color(0.2, 0.2, 0.24))
		draw_rect(COUNTER, ol, false, 1.0)
		var sign_r := Rect2(COUNTER.position.x - 24.0, COUNTER.end.y - 14.0, 22.0, 12.0)
		draw_rect(sign_r, Color(0.95, 0.85, 0.2))
		TextFit.draw(self, font, Vector2(sign_r.position.x, sign_r.position.y + 9.0), "KASSA", sign_r.size.x, 6, Color(0.1, 0.1, 0.1))
		# ammuslaatikot
		for k in 3:
			var b := Rect2(AMMO.position.x + (k % 2) * 13.0, AMMO.position.y + (1 - k / 2) * 11.0, 14.0, 11.0)
			draw_rect(b, Color(0.33, 0.38, 0.22))
			draw_rect(Rect2(b.position.x, b.position.y, b.size.x, 3.0), Color(0.4, 0.46, 0.28))
			draw_rect(Rect2(b.position.x + 3.0, b.position.y + 5.0, 8.0, 3.0), Color(0.9, 0.82, 0.3))
			draw_rect(b, ol, false, 1.0)
		# odotuspenkki
		draw_rect(BENCH, Color(0.5, 0.33, 0.18))
		draw_line(Vector2(BENCH.position.x, BENCH.position.y + 4.0), Vector2(BENCH.end.x, BENCH.position.y + 4.0), Color(0.35, 0.22, 0.12), 1.0)
		draw_rect(BENCH, ol, false, 1.0)
		# kasvit
		for pr: Rect2 in [PLANT_A, PLANT_B]:
			draw_rect(Rect2(pr.position.x + 2.0, pr.position.y + 6.0, pr.size.x - 4.0, 6.0), Color(0.55, 0.32, 0.2))
			draw_circle(pr.get_center() + Vector2(0, -2), 5.5, Color(0.2, 0.5, 0.25))
			draw_circle(pr.get_center() + Vector2(-2, -4), 3.0, Color(0.3, 0.62, 0.32))
			draw_circle(pr.get_center() + Vector2(2.5, -1), 2.5, Color(0.16, 0.42, 0.2))

	## Puulaatikko täynnä kranaatteja + hintalappu.
	func _grenade_crate(p: Vector2, font: Font) -> void:
		var r := Rect2(p.x - 11.0, p.y - 6.0, 22.0, 14.0)
		draw_rect(Rect2(r.position + Vector2(1, 2), r.size), Color(0, 0, 0, 0.3))
		draw_rect(r, Color(0.42, 0.28, 0.15))
		draw_rect(r, Color(0.2, 0.12, 0.06), false, 1.0)
		draw_line(Vector2(r.position.x, r.position.y + 7.0), Vector2(r.end.x, r.position.y + 7.0), Color(0.3, 0.19, 0.1), 1.0)
		draw_rect(Rect2(r.position.x + 1.0, r.position.y + 1.0, r.size.x - 2.0, 5.0), Color(0.12, 0.1, 0.08))
		# kranaatit laatikossa (puolen pikselin tarkkuudella)
		for k in 4:
			var c := Vector2(r.position.x + 4.0 + k * 4.7, r.position.y + 3.2)
			draw_circle(c, 2.1, Color(0.11, 0.1, 0.14))
			draw_circle(c, 1.6, Color(0.33, 0.4, 0.2))
			draw_rect(Rect2(c.x - 0.9, c.y - 0.9, 0.7, 0.7), Color(0.5, 0.58, 0.3))
			draw_rect(Rect2(c.x - 0.6, c.y - 2.8, 1.2, 1.0), Color(0.62, 0.64, 0.7))
		var tag := Rect2(p.x - 26.0, p.y - 26.0, 52.0, 16.0)
		draw_rect(tag, Color(0.05, 0.05, 0.08, 0.9))
		draw_rect(tag, YELLOW, false, 1.0)
		TextFit.draw(self, font, Vector2(tag.position.x, tag.position.y + 7.0), "KRANAATIT", tag.size.x, 6, Color.WHITE)
		TextFit.draw(self, font, Vector2(tag.position.x, tag.position.y + 14.0), "60 $", tag.size.x, 7, YELLOW)

	## Mallinukke kevlarliivin kanssa + hintalappu.
	func _vest_stand(p: Vector2, font: Font) -> void:
		var worn := Game.armor >= Game.ARMOR_MAX
		draw_set_transform(p + Vector2(0, 1), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.3))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(p.x - 5.0, p.y - 2.0, 10.0, 3.0), Color(0.16, 0.17, 0.22))
		draw_rect(Rect2(p.x - 0.75, p.y - 10.0, 1.5, 8.0), Color(0.55, 0.57, 0.62))
		# nuken vartalo ja pää
		var torso := Rect2(p.x - 6.0, p.y - 22.0, 12.0, 12.0)
		draw_rect(torso.grow(0.5), Color(0.72, 0.68, 0.6))
		draw_circle(Vector2(p.x, p.y - 25.0), 3.5, Color(0.78, 0.74, 0.66))
		if not worn:
			# liivi
			draw_rect(torso, Color(0.2, 0.24, 0.15))
			draw_rect(Rect2(torso.position.x, torso.position.y, 3.0, 3.0), Color(0.72, 0.68, 0.6))
			draw_rect(Rect2(torso.end.x - 3.0, torso.position.y, 3.0, 3.0), Color(0.72, 0.68, 0.6))
			draw_rect(Rect2(torso.position.x, torso.position.y + 7.0, torso.size.x, 1.5), Color(0.09, 0.1, 0.08))
			draw_rect(Rect2(p.x - 2.0, torso.position.y + 3.5, 4.0, 2.0), Color(0.45, 0.5, 0.35))
			draw_rect(torso, Color(0.05, 0.06, 0.04), false, 1.0)
		var tag := Rect2(p.x - 26.0, p.y - 46.0, 52.0, 16.0)
		draw_rect(tag, Color(0.05, 0.05, 0.08, 0.9))
		draw_rect(tag, YELLOW, false, 1.0)
		TextFit.draw(self, font, Vector2(tag.position.x, tag.position.y + 7.0), "KEVLARLIIVI", tag.size.x, 6, Color.WHITE)
		TextFit.draw(self, font, Vector2(tag.position.x, tag.position.y + 14.0), "PÄÄLLÄ" if worn else "%d $" % Game.VEST_PRICE, tag.size.x, 7, YELLOW)

	## Seinälle kiinnitetty hylly, jossa on kolme kivääriä.
	func _rack(p: Vector2) -> void:
		draw_rect(Rect2(p.x - 36.0, p.y, 72.0, 20.0), Color(0.22, 0.14, 0.09))
		draw_rect(Rect2(p.x - 36.0, p.y, 72.0, 20.0), Color(0.1, 0.06, 0.04), false, 1.0)
		for k in 3:
			var gy := p.y + 4.0 + k * 5.0
			draw_line(Vector2(p.x - 32.0, gy), Vector2(p.x + 32.0, gy), Color(0.36, 0.38, 0.47), 2.0)
			draw_line(Vector2(p.x - 32.0, gy), Vector2(p.x - 20.0, gy), Color(0.53, 0.3, 0.15), 2.0)
