extends Control
## Minikartta ruudun oikeassa yläkulmassa (pyöristetty).
##  - näyttää pelaajan ympäristön (tiet, rakennukset, nurmi) kaupunkigeneraattorin datasta
##  - pelaaja valkoisena pisteenä, asekauppa kultaisena merkkinä (reunaan kiinnitettynä jos kaukana)
##  - näkymä rajataan kartan sisään, joten tyhjää aluetta ei näy
##  - piiloutuu asekaupan sisällä (sisätila on kaukana kartan ulkopuolella)

const VIEW_RADIUS := 32            ## ruutuja pelaajasta joka suuntaan
const MAP_PX := 120.0              ## kartan sisäosan koko ruudulla
const PAD := 3.0                   ## reunus
const CORNER := 14.0               ## kulmien pyöristys
const TOP_OFFSET := 110.0          ## yläpuolella kello+sää (HUD.CLOCK_TOP) ja etsintäkuulutustähdet (HUD.STARS_TOP)
const GOLD := Color(0.98, 0.8, 0.15)

const COL_GRASS := Color(0.30, 0.45, 0.28)
const COL_ROAD := Color(0.62, 0.64, 0.68)
const COL_SOLID := Color(0.20, 0.22, 0.30)

var _city: Node
var _tex: ImageTexture
var _world_origin := Vector2.ZERO
var _tile := 16.0
var _map_w := 0
var _map_h := 0

## Koko kaupungin kartta (CityMap.gd, M-näppäin): sama ulkoasu, mutta iso, keskellä
## ruutua ja näyttää koko kaupungin sekä kaikkien merkittyjen paikkojen nimet.
var full_view := false
var _bg: StyleBoxFlat = null
var _map_px := MAP_PX
var _k := 1.0          # kuvakkeiden koko


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if full_view:
		return   # koko ja paikka asetetaan _process:ssa näkymän koosta
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	var size_px := MAP_PX + PAD * 2.0
	offset_left = -size_px - 20.0
	offset_right = -20.0
	offset_top = TOP_OFFSET
	offset_bottom = TOP_OFFSET + size_px
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	if _tex == null:
		_try_build()
	if full_view:
		# Neliö ruudun keskellä, 86 % lyhyemmästä sivusta
		var vs := get_viewport().get_visible_rect().size
		var side := floorf(minf(vs.x, vs.y) * 0.86)
		position = (vs - Vector2(side, side)) * 0.5
		size = Vector2(side, side)
		_map_px = side - PAD * 2.0
		_k = clampf(side / 420.0, 1.4, 3.0)
	queue_redraw()


## Rakentaa kartan kuvan kun kaupunki on generoitu.
func _try_build() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_city = scene.get_node_or_null("City")
	if _city == null or not ("solid" in _city) or _city.solid.is_empty():
		return
	_map_w = _city.map_w
	_map_h = _city.map_h
	_tile = float(_city.tile)
	_world_origin = _city.world_rect().position

	var img := Image.create(_map_w, _map_h, false, Image.FORMAT_RGBA8)
	for y in _map_h:
		for x in _map_w:
			var c := COL_GRASS
			if _city.solid[y * _map_w + x] == 1:
				c = COL_SOLID
			elif _city.col_road[x] == 1 or _city.row_road[y] == 1:
				c = COL_ROAD
			img.set_pixel(x, y, c)
	_tex = ImageTexture.create_from_image(img)


## Pelaajan (tai ajettavan auton) paikka maailmassa.
func _focus_position() -> Variant:
	for car in get_tree().get_nodes_in_group("player_vehicles"):
		if "is_driving" in car and car.is_driving:
			return car.global_position
	var player := get_tree().get_first_node_in_group("player")
	if player:
		return player.global_position
	return null


func _draw() -> void:
	if _tex == null:
		return
	var armory := get_tree().get_first_node_in_group("armory")
	var home := get_tree().get_first_node_in_group("home")
	var bar := get_tree().get_first_node_in_group("bar")
	var jail := get_tree().get_first_node_in_group("jail")
	if not full_view:
		if Game.player_indoors():
			return
	var focus_v: Variant = _focus_position()
	if focus_v == null:
		return
	var focus: Vector2 = focus_v

	var inner := Rect2(Vector2(PAD, PAD), Vector2(_map_px, _map_px))
	var span := float(VIEW_RADIUS * 2)
	if full_view:
		span = float(maxi(_map_w, _map_h))
	var px_per_tile := _map_px / span
	var k := _k
	var edge_pad := 10.0 * k

	# Taustapaneeli ja kehys (pyöristetty)
	if _bg == null:   # optimointi: tyylilaatikko luodaan kerran, ei joka ruutu
		_bg = StyleBoxFlat.new()
		_bg.bg_color = Color(0, 0, 0, 0.7)
		_bg.border_color = Color(1, 1, 1, 0.6)
		_bg.set_border_width_all(2)
	_bg.set_corner_radius_all(int(CORNER * (2.0 if full_view else 1.0) + PAD))
	draw_style_box(_bg, Rect2(Vector2.ZERO, size))

	# Pelaajan paikka ruutukoordinaatteina. Näkymä rajataan kartan sisään,
	# joten tyhjää aluetta ei koskaan näy (pelaaja siirtyy pois keskeltä reunalla).
	var ftile := (focus - _world_origin) / _tile
	var half := Vector2(VIEW_RADIUS, VIEW_RADIUS)
	var src_pos := (ftile - half).clamp(Vector2.ZERO, Vector2(_map_w, _map_h) - half * 2.0)
	var src := Rect2(src_pos, half * 2.0)
	if full_view:
		src = Rect2(Vector2.ZERO, Vector2(span, span))

	# Kartta pyöristettynä monikulmiona, jonka UV-koordinaatit osoittavat kuvan osaan
	var pts := _rounded_rect_points(inner, CORNER * (2.0 if full_view else 1.0))
	var uvs := PackedVector2Array()
	var tex_size := Vector2(_tex.get_size())
	for pt in pts:
		uvs.append((src.position + (pt - inner.position) / px_per_tile) / tex_size)
	draw_colored_polygon(pts, Color.WHITE, uvs, _tex)

	# Asekauppa (kiinnitetään reunaan, jos ei mahdu näkymään)
	if armory:
		var ap: Vector2 = inner.position + ((armory.door_px - _world_origin) / _tile - src.position) * px_per_tile
		var on_edge := not inner.grow(-8.0).has_point(ap)
		ap = ap.clamp(inner.position + Vector2(edge_pad, edge_pad), inner.end - Vector2(edge_pad, edge_pad))
		var r := (4.0 if on_edge else 5.0) * k
		var box := Rect2(ap - Vector2(r, r), Vector2(r, r) * 2.0)
		draw_rect(box.grow(1.5), Color(0, 0, 0, 0.9))
		draw_rect(box, GOLD)
		var ink := Color(0.13, 0.14, 0.19)
		draw_line(ap + Vector2(-r + 1.5, 0), ap + Vector2(r - 1.5, 0), ink, k)
		draw_line(ap + Vector2(0, -r + 1.5), ap + Vector2(0, r - 1.5), ink, k)
		_label(ap, r, "Asekauppa", Game.is_open(9, 21))

	# Koti (sininen talokuvake)
	if home:
		var hp: Vector2 = inner.position + ((home.door_px - _world_origin) / _tile - src.position) * px_per_tile
		var h_edge := not inner.grow(-8.0).has_point(hp)
		hp = hp.clamp(inner.position + Vector2(edge_pad, edge_pad), inner.end - Vector2(edge_pad, edge_pad))
		_draw_house_icon(hp, (0.85 if h_edge else 1.0) * k)
		_label(hp, 8.0 * k, "Koti", not Game.rent_overdue)

	# Baari (magenta lasikuvake)
	if bar:
		var bp: Vector2 = inner.position + ((bar.door_px - _world_origin) / _tile - src.position) * px_per_tile
		var b_edge := not inner.grow(-8.0).has_point(bp)
		bp = bp.clamp(inner.position + Vector2(edge_pad, edge_pad), inner.end - Vector2(edge_pad, edge_pad))
		_draw_glass_icon(bp, (0.85 if b_edge else 1.0) * k)
		_label(bp, 7.0 * k, Game.bar_name().capitalize(), Game.owns_bar or (Game.is_open(12, 4) and not Game.bar_banned()))
		# Kalle baarin kulmalla (vain isolla kartalla)
		var kalle: Variant = bar.get("_kalle")
		if full_view and kalle != null and is_instance_valid(kalle):
			var kp: Vector2 = inner.position + (((kalle as Node2D).global_position - _world_origin) / _tile - src.position) * px_per_tile
			kp += Vector2(9.0, 0.0) * k
			draw_circle(kp, 5.5 * k, Color(0, 0, 0, 0.9))
			draw_circle(kp, 4.0 * k, Color(0.95, 0.3, 0.25))
			TextFit.draw(self, ThemeDB.fallback_font, kp + Vector2(-4, 4) * k, "!", 8.0 * k, int(9 * k), Color.WHITE)

	# Palvelurakennukset: värillinen ruutu ja kirjain (vain näkymän sisällä)
	var font := ThemeDB.fallback_font
	for sv in get_tree().get_nodes_in_group("service"):
		var sp: Vector2 = inner.position + ((sv.door_px - _world_origin) / _tile - src.position) * px_per_tile
		if full_view:
			# Isolla kartalla kaikki palvelut näkyvät aina (reunan lähelläkin)
			sp = sp.clamp(inner.position + Vector2(edge_pad, edge_pad), inner.end - Vector2(edge_pad, edge_pad))
		elif not inner.grow(-6.0).has_point(sp):
			continue
		var sbox := Rect2(sp - Vector2(5, 5) * k, Vector2(10, 10) * k)
		draw_rect(sbox.grow(1.5 * k), Color(0, 0, 0, 0.9))
		draw_rect(sbox, sv.map_color)
		TextFit.draw(self, font, sbox.position + Vector2(0, 8.5) * k, str(sv.letter), 10.0 * k, int(9 * k), Color(0.05, 0.05, 0.08))
		_label(sp, 5.0 * k, sv.display_name() if sv.has_method("display_name") else "", sv.is_open() if sv.has_method("is_open") else true)

	# Työn / tehtävän kohteet (kiinnitetään reunaan, jos kaukana)
	for mk in get_tree().get_nodes_in_group("minimap_marker"):
		if not mk.visible:
			continue
		var mp: Vector2 = inner.position + ((mk.global_position - _world_origin) / _tile - src.position) * px_per_tile
		var m_edge := not inner.grow(-8.0).has_point(mp)
		mp = mp.clamp(inner.position + Vector2(edge_pad, edge_pad), inner.end - Vector2(edge_pad, edge_pad))
		var m_r := (4.0 if m_edge else 5.0) * k
		var mc: Color = mk.get("marker_color") if mk.get("marker_color") != null else Color(0.2, 0.9, 0.35)
		draw_circle(mp, m_r + 1.5, Color(0, 0, 0, 0.9))
		draw_circle(mp, m_r, mc)

	# Taksikyydin kohde (vihreä)
	var job := get_tree().get_first_node_in_group("taxi_job")
	if job and job.active:
		var tp: Vector2 = inner.position + ((job.destination - _world_origin) / _tile - src.position) * px_per_tile
		var t_edge := not inner.grow(-8.0).has_point(tp)
		tp = tp.clamp(inner.position + Vector2(edge_pad, edge_pad), inner.end - Vector2(edge_pad, edge_pad))
		var t_r := (4.0 if t_edge else 5.0) * k
		draw_circle(tp, t_r + 1.5, Color(0, 0, 0, 0.9))
		draw_circle(tp, t_r, Color(0.2, 0.9, 0.35))

	# Pelaaja
	# Poliisit jahdin aikana (vain isolla kartalla)
	if full_view:
		var pm := get_tree().get_first_node_in_group("police_manager")
		if pm and pm.wanted > 0:
			var blink := int(Time.get_ticks_msec() / 250) % 2 == 0
			for u in pm.officers + pm.cars:
				if is_instance_valid(u) and not u.dead:
					var up: Vector2 = inner.position + (((u as Node2D).global_position - _world_origin) / _tile - src.position) * px_per_tile
					draw_circle(up, 3.0 * k, Color(0, 0, 0, 0.9))
					draw_circle(up, 2.2 * k, Color(0.25, 0.45, 1.0) if blink else Color(1.0, 0.25, 0.25))

	var pp := inner.position + (ftile - src.position) * px_per_tile
	draw_circle(pp, 4.5 * k, Color(0, 0, 0, 0.9))
	draw_circle(pp, 3.2 * k, Color(1, 1, 1))
	if full_view:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0)
		draw_arc(pp, (6.0 + pulse * 4.0) * k, 0.0, TAU, 24, Color(1, 1, 1, 0.8), 1.5 * k)


## Paikan nimi kuvakkeen alle (vain isolla kartalla). Kiinni olevat punaisella.
func _label(p: Vector2, r: float, text: String, open_now: bool) -> void:
	if not full_view or text == "":
		return
	var font := ThemeDB.fallback_font
	var fs := int(7.0 * _k)
	var col := Color(1, 1, 1) if open_now else Color(1.0, 0.55, 0.5)
	var t := text if open_now else text + " (kiinni)"
	var w := 140.0 * _k
	TextFit.draw_outline(self, font, p + Vector2(-w * 0.5, r + fs + 2.0), t, w, fs, int(3.0 * _k), Color(0, 0, 0, 0.9))
	TextFit.draw(self, font, p + Vector2(-w * 0.5, r + fs + 2.0), t, w, fs, col)


## Pyöristetyn suorakulmion reunapisteet (myötäpäivään).
func _rounded_rect_points(rect: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 8
	var centers := [
		[rect.position + Vector2(radius, radius), PI],                     # vasen ylä
		[Vector2(rect.end.x - radius, rect.position.y + radius), PI * 1.5],  # oikea ylä
		[rect.end - Vector2(radius, radius), 0.0],                         # oikea ala
		[Vector2(rect.position.x + radius, rect.end.y - radius), PI * 0.5],  # vasen ala
	]
	for c in centers:
		for i in steps + 1:
			var a: float = c[1] + (PI * 0.5) * float(i) / float(steps)
			pts.append((c[0] as Vector2) + Vector2(cos(a), sin(a)) * radius)
	return pts


## Baarin kuvake: magenta ruutu ja valkoinen cocktaillasi.
func _draw_glass_icon(p: Vector2, k: float) -> void:
	var box := Rect2(p + Vector2(-6, -6) * k, Vector2(12, 12) * k)
	draw_rect(box.grow(1.5 * k), Color(0, 0, 0, 0.9))
	draw_rect(box, Color(1.0, 0.25, 0.7))
	var w := Color.WHITE
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-4, -4) * k, p + Vector2(4, -4) * k, p + Vector2(0, 1) * k]), w)
	draw_line(p + Vector2(0, 1) * k, p + Vector2(0, 4.5) * k, w, 1.0)
	draw_line(p + Vector2(-2.5, 4.5) * k, p + Vector2(2.5, 4.5) * k, w, 1.0)

## Pieni talokuvake (katto + runko + ovi) mustalla reunalla.
func _draw_house_icon(p: Vector2, k: float) -> void:
	var roof := PackedVector2Array([p + Vector2(-8, -0.5) * k, p + Vector2(0, -8) * k, p + Vector2(8, -0.5) * k])
	var roof_o := PackedVector2Array([p + Vector2(-9.5, 0.5) * k, p + Vector2(0, -9.5) * k, p + Vector2(9.5, 0.5) * k])
	var body := Rect2(p + Vector2(-5, -1) * k, Vector2(10, 7) * k)
	draw_colored_polygon(roof_o, Color(0, 0, 0, 0.9))
	draw_rect(body.grow(1.5 * k), Color(0, 0, 0, 0.9))
	draw_colored_polygon(roof, Color(0.35, 0.75, 1.0))
	draw_rect(body, Color(0.9, 0.95, 1.0))
	draw_rect(Rect2(p + Vector2(-1.5, 2) * k, Vector2(3, 4) * k), Color(0.2, 0.3, 0.45))
