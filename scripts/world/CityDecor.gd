extends Node2D
## Kaupungin koristekerros: tuo 2D-grafiikkaan syvyyttä koskematta kuvatiedostoihin.
## CityGenerator luo tämän maakerroksen (WorldMap) lapseksi, joten kaikki piirtyy
## maatiilien päälle mutta koristetiilien (ikkunat, puut, lamput) ja hahmojen alle.
##
##  1. Varjot: talojen kattoreunasta lankeaa varjo itään (oikealle), puiden, lamppujen
##     ja kalusteiden alla on varjo, hahmojen ja autojen alla soikea varjo (EntityShadows).
##  2. Talon ja maan raja: räystään varjo julkisivun yläreunassa, tumma sokkeli ja
##     kosketusvarjo seinän juuressa, kattoreunan vaalea huullos.
##  3. Reunakivet: vaalea reunakivi jalkakäytävän reunassa ja tumma varjoviiva tiellä.
##  4. Vaihtelu: ruohon ja asfaltin sävyläikät, halkeamat, öljytahrat, paikkaukset,
##     kuluneet suojatiet, kukat ja kivet, talokohtaiset kattosävyt.
##  6. Tuulessa heiluva ruoho vihreillä alueilla (GrassChunk, varjostin + Game.wind).
##  7. Elämän jäljet: graffitit ja julisteet seinissä, roskapussit ovien vieressä,
##     roskat ja liitumaalaukset jalkakäytävillä, kerrostalojen parvekkeet ja kukkalaatikot.
##  5. Päivänvalo: varjot ovat viileän sinisiä (aurinkoinen puoli lämmin, ks. Atmosphere
##     SKY_KEYS), julkisivun itäreuna viileä ja länsireuna lämmin. Auringon varjot
##     haalenevat illalla ja pilvisellä säällä.
##
## SÄÄDÄ NÄITÄ:
const CHUNK := 32                                   ## ruutua per piirtopala (näkymän ulkopuoliset palat karsitaan)
const SHADOW := Color(0.07, 0.09, 0.24, 0.30)       ## auringon varjon väri (viileä sininen)
const SHADOW_SOFT := Color(0.07, 0.09, 0.24, 0.12)  ## varjon pehmeä reuna
const BUILDING_SHADOW_LEN := 14.0                   ## talon varjon pituus itään (px)
const ENTITY_SHADOW := Color(0.05, 0.06, 0.16, 0.34)
const CURB_LIGHT := Color(0.88, 0.86, 0.8, 0.85)
const CURB_DARK := Color(0.0, 0.0, 0.05, 0.28)
const GRASS_BLADES := 95                            ## korsia per 16x16 ruohopala (tiheys)
const FLOWER_CHANCE := 0.14                         ## nurmiruudun kukkaryhmän todennäköisyys
const GRASS_SWAY := 1.0                             ## ruohon heilunnan voimakkuus (px)
const GRAFFITI_CHANCE := 0.16                       ## tyhjän seinäruudun graffitin todennäköisyys
const LITTER_CHANCE := 0.07                         ## jalkakäytäväruudun roskan todennäköisyys

const GRASS_SHADER := """
shader_type canvas_item;
// Tiheä ruohokerros: jokainen nurmiruutu näyttää yhden 16x16-palan ruohotekstuurista.
// height_tex kertoo, kuinka korkealla korressa pikseli on (0 = tyvi, 1 = kärki):
// kärjet siirtyvät tuulessa, tyvet pysyvät paikallaan.
uniform sampler2D height_tex : filter_nearest;
uniform float wind = 0.3;
uniform float strength = 1.0;
uniform float px_scale = 1.0;   // tekstuuripikseleitä / maailman pikseli
varying vec2 world;
void vertex() {
	world = VERTEX;
}
void fragment() {
	float sway = sin(TIME * 2.1 + world.x * 0.08 + world.y * 0.05) * 0.65 + sin(TIME * 3.4 + world.x * 0.15 - world.y * 0.03) * 0.3;
	float off = (wind * 0.9 + sway * (0.45 + abs(wind) * 0.8)) * strength;
	vec2 shift = vec2(off * px_scale * TEXTURE_PIXEL_SIZE.x, 0.0);
	float h = texture(height_tex, UV - shift).r;
	COLOR = texture(TEXTURE, UV - shift * h) * COLOR;
}
"""

var city: Node = null
var _origin := Vector2.ZERO        ## ruudun (0,0) vasen yläkulma maakerroksen koordinaateissa
var _t := 16.0
var _sun_root: Node2D
var _dyn: Node2D
var _asphalt := {}
var _grass := {}
var _cross := {}
var _base_big := {}                ## puun / lampun / kyltin juuritiili -> tyyppi
var _base_small := {}
## Kalusteruutu -> [[ShadowChunk, listan nimi, merkintä], ...] (poisto kun kaluste kaatuu)
var _prop_shadows := {}
var _sidewalk := {}
var _grass_mat: ShaderMaterial
var _grass_base := Color(0.2, 0.75, 0.6)


func setup(c: Node) -> void:
	city = c
	name = "CityDecor"
	_t = float(c.tile)
	var layer: TileMapLayer = c.ground_layer
	_origin = layer.map_to_local(Vector2i.ZERO) - Vector2(_t, _t) * 0.5
	_build_tile_sets()

	var seed_base: int = int(c.rng.seed % 1000000)
	var surf := Node2D.new()
	surf.name = "Surface"
	add_child(surf)
	_sun_root = Node2D.new()
	_sun_root.name = "SunShadows"
	add_child(_sun_root)
	var shadow_chunks := {}
	for cy in range(0, int(c.map_h), CHUNK):
		for cx in range(0, int(c.map_w), CHUNK):
			var r := Rect2i(cx, cy, mini(CHUNK, int(c.map_w) - cx), mini(CHUNK, int(c.map_h) - cy))
			var s := SurfaceChunk.new()
			s.decor = self
			s.cells = r
			s.seed_value = seed_base + cx * 7919 + cy * 104729
			surf.add_child(s)
			var sh := ShadowChunk.new()
			_sun_root.add_child(sh)
			shadow_chunks[Vector2i(cx / CHUNK, cy / CHUNK)] = sh
	_collect_sun_shadows(shadow_chunks)
	_build_grass(seed_base)
	_build_facade_overlays(seed_base)
	_dyn = EntityShadows.new()
	_dyn.decor = self
	_dyn.name = "EntityShadows"
	add_child(_dyn)


func cell_px(c: Vector2i) -> Vector2:
	return _origin + Vector2(c) * _t


func _build_tile_sets() -> void:
	_asphalt[CityGenerator.ROAD] = true
	_asphalt[CityGenerator.ROAD_DASH_V] = true
	_asphalt[CityGenerator.ROAD_DASH_H] = true
	_asphalt[CityGenerator.PARKING_SIGN] = true
	for t: Vector2i in CityGenerator.CROSS_V + CityGenerator.CROSS_H:
		_asphalt[t] = true
		_cross[t] = true
	var ps_o: Vector2i = CityGenerator.PARKING_STALL.o
	var ps_s: Vector2i = CityGenerator.PARKING_STALL.s
	for dy in ps_s.y:
		for dx in ps_s.x:
			_asphalt[ps_o + Vector2i(dx, dy)] = true
	_grass[CityGenerator.GRASS] = true
	_sidewalk[CityGenerator.SIDEWALK] = true
	var pk_o: Vector2i = CityGenerator.PARK.o
	var pk_s: Vector2i = CityGenerator.PARK.s
	for dy in pk_s.y:
		for dx in pk_s.x:
			_grass[pk_o + Vector2i(dx, dy)] = true
	for list: Array in [CityGenerator.TREES, CityGenerator.STREET_TREES]:
		for st: Dictionary in list:
			var o: Vector2i = st.o
			var s: Vector2i = st.s
			for dx in s.x:
				_base_big[o + Vector2i(dx, s.y - 1)] = "tree" if s.y > 1 else "bush"
	for list: Array in [CityGenerator.LAMPS, CityGenerator.SIGNS, CityGenerator.TRAFFIC_LIGHTS]:
		for st: Dictionary in list:
			var o: Vector2i = st.o
			var s: Vector2i = st.s
			_base_big[o + Vector2i(0, s.y - 1)] = "pole"
	for st: Dictionary in CityGenerator.TALL_PROPS:
		var o: Vector2i = st.o
		var s: Vector2i = st.s
		_base_big[o + Vector2i(0, s.y - 1)] = "stall"
	for st: Dictionary in CityGenerator.SMALL_PROPS:
		_base_small[st.o] = true


func ground_tile(c: Vector2i) -> Vector2i:
	return (city.ground_layer as TileMapLayer).get_cell_atlas_coords(c)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < int(city.map_w) and c.y < int(city.map_h)


func is_asphalt(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	return city._is_road(c) or _asphalt.has(ground_tile(c))


func is_grass(c: Vector2i) -> bool:
	return in_bounds(c) and _grass.has(ground_tile(c))


func is_sidewalk(c: Vector2i) -> bool:
	return in_bounds(c) and _sidewalk.has(ground_tile(c))


func is_cross(c: Vector2i) -> bool:
	return in_bounds(c) and _cross.has(ground_tile(c))


## Auringon varjot: talot, puut, lamput, kyltit, kalusteet.
func _collect_sun_shadows(chunks: Dictionary) -> void:
	for b: Dictionary in city.building_rects:
		var lot: Rect2i = b.lot
		var sh: ShadowChunk = chunks.get(Vector2i(lot.position.x / CHUNK, lot.position.y / CHUNK))
		if sh == null:
			continue
		var p0 := cell_px(lot.position)
		var p1 := cell_px(lot.end)
		var length := BUILDING_SHADOW_LEN * (1.6 if bool(b.get("flat", false)) else (1.25 if bool(b.landmark) else 1.0))
		var top := p0.y + 5.0
		var slope := length * 0.35
		sh.polys.append([PackedVector2Array([
			Vector2(p1.x, top), Vector2(p1.x + length, top + slope),
			Vector2(p1.x + length, p1.y + slope * 0.5), Vector2(p1.x + length * 0.4, p1.y + 3.0), Vector2(p1.x, p1.y)]), SHADOW])
		sh.polys.append([PackedVector2Array([
			Vector2(p1.x + length, top + slope), Vector2(p1.x + length + 3.0, top + slope + 2.0),
			Vector2(p1.x + length + 3.0, p1.y + slope * 0.5 + 2.0), Vector2(p1.x + length, p1.y + slope * 0.5)]), SHADOW_SOFT])
	var deco: TileMapLayer = city.deco_layer
	for c: Vector2i in deco.get_used_cells():
		var a := deco.get_cell_atlas_coords(c)
		var sh: ShadowChunk = chunks.get(Vector2i(c.x / CHUNK, c.y / CHUNK))
		if sh == null:
			continue
		var p := cell_px(c)
		var foot := p + Vector2(_t * 0.5, _t - 2.0)
		var n_el := sh.ellipses.size()
		var n_ln := sh.lines.size()
		if _base_big.has(a):
			match str(_base_big[a]):
				"tree":
					sh.ellipses.append([foot + Vector2(5.0, 0.5), 9.0, 3.6, SHADOW])
					sh.ellipses.append([foot + Vector2(6.0, 0.5), 11.0, 4.6, SHADOW_SOFT])
				"bush":
					sh.ellipses.append([foot + Vector2(3.0, 0.5), 7.0, 3.0, SHADOW])
				"pole":
					sh.lines.append([foot, foot + Vector2(13.0, 3.0), 2.0, SHADOW])
					sh.ellipses.append([foot + Vector2(14.0, 3.0), 3.5, 1.6, SHADOW])
				_:
					sh.ellipses.append([foot + Vector2(3.0, 0.5), 8.0, 3.0, SHADOW])
		elif _base_small.has(a):
			sh.ellipses.append([foot + Vector2(2.5, 0.5), 6.0, 2.4, SHADOW])
		var recs: Array = []
		for k in range(n_el, sh.ellipses.size()):
			recs.append([sh, "ellipses", sh.ellipses[k]])
		for k in range(n_ln, sh.lines.size()):
			recs.append([sh, "lines", sh.lines[k]])
		if not recs.is_empty():
			_prop_shadows[c] = recs


## Kaatunut kaluste: sen varjot pois.
func remove_prop_shadows(cells: Array) -> void:
	for c in cells:
		if not _prop_shadows.has(c):
			continue
		for rec: Array in _prop_shadows[c]:
			var sh: ShadowChunk = rec[0]
			if is_instance_valid(sh):
				(sh.get(rec[1]) as Array).erase(rec[2])
				sh.queue_redraw()
		_prop_shadows.erase(c)


## Päivitetään auringon varjojen voimakkuus kellonajan ja pilvisyyden mukaan.
func _process(_delta: float) -> void:
	if _sun_root:
		var k := (1.0 - Game.darkness()) * (1.0 - Game.cloud_amount() * 0.65)
		_sun_root.modulate.a = clampf(k, 0.0, 1.0)
	if _grass_mat:
		var storm := clampf(Game.rain_amount() + Game.snow_amount() * 0.5, 0.0, 1.0)
		_grass_mat.set_shader_parameter("wind", clampf(Game.wind, -1.0, 1.0) * (0.6 + storm * 0.8))
		_grass_mat.set_shader_parameter("strength", GRASS_SWAY * (1.0 + storm * 0.8))


# ----------------------------------------------------------------------------
#  RUOHO (heiluu tuulessa)
# ----------------------------------------------------------------------------
func _build_grass(seed_base: int) -> void:
	# Korsien värit nurmitiilen keskiväristä, jotta ne sopivat alkuperäiseen grafiikkaan
	var src := (city.ground_layer as TileMapLayer).tile_set.get_source(int(city.source_id)) as TileSetAtlasSource
	if src and src.texture:
		var img: Image = city.get("atlas_lo")
		if img == null:
			img = src.texture.get_image()
		if img:
			if img.is_compressed():
				img.decompress()
			var g: Vector2i = CityGenerator.GRASS
			var stride := int(city.stride)
			var sum := Color(0, 0, 0, 0)
			var n := 0
			for y in int(_t):
				for x in int(_t):
					sum += img.get_pixel(g.x * stride + x, g.y * stride + y)
					n += 1
			if n > 0:
				_grass_base = Color(sum.r / n, sum.g / n, sum.b / n)

	# --- Ruohotekstuuri: 8x8 erilaista palaa, tiheästi korsia ---
	# GS = tekstuurin tarkkuus (2 = korret 0.5 px levyisiä, kuten hahmot ja tilemap_hd)
	const V := 8
	const GS := 2
	var ts := int(_t) * GS
	var size := V * ts
	var col_img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var h_img := Image.create(size, size, false, Image.FORMAT_L8)
	var trng := RandomNumberGenerator.new()
	trng.seed = seed_base + 99
	var dark := _grass_base.darkened(0.32)
	var tips: Array[Color] = [_grass_base.lightened(0.22), _grass_base.lightened(0.1), _grass_base.darkened(0.05), _grass_base.lerp(Color(0.85, 0.9, 0.45), 0.3)]
	for vy in V:
		for vx in V:
			var blades: Array = []
			for i in GRASS_BLADES * GS:
				blades.append([trng.randi_range(5 * GS, ts - 1), trng.randi_range(1, ts - 2), trng.randi_range(3 * GS, 7 * GS), trng.randi_range(-1, 1) * GS, trng.randi() % tips.size()])
			blades.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
			for bl in blades:
				var by: int = bl[0]
				var bx: int = bl[1]
				var bh: int = bl[2]
				var lean: int = bl[3]
				var tip: Color = tips[int(bl[4])]
				for k in bh:
					var f := float(k) / float(maxi(bh - 1, 1))
					var px := clampi(bx + int(round(lean * f * f * 1.5)), 0, ts - 1)
					var py := by - k
					if py < 0:
						break
					col_img.set_pixel(vx * ts + px, vy * ts + py, dark.lerp(tip, f))
					h_img.set_pixel(vx * ts + px, vy * ts + py, Color(f, f, f))
	var grass_tex := ImageTexture.create_from_image(col_img)
	var height_tex := ImageTexture.create_from_image(h_img)

	var sh := Shader.new()
	sh.code = GRASS_SHADER
	_grass_mat = ShaderMaterial.new()
	_grass_mat.shader = sh
	_grass_mat.set_shader_parameter("height_tex", height_tex)
	_grass_mat.set_shader_parameter("px_scale", float(GS))
	var root := Node2D.new()
	root.name = "Grass"
	add_child(root)
	move_child(root, 1)   # pinnan päälle, auringon varjojen alle
	var flowers_root := Node2D.new()
	flowers_root.name = "Flowers"
	add_child(flowers_root)
	move_child(flowers_root, 2)
	var noise := FastNoiseLite.new()
	noise.seed = 4321
	noise.frequency = 0.06
	var uv_cell := 1.0 / float(V)
	for cy in range(0, int(city.map_h), CHUNK):
		for cx in range(0, int(city.map_w), CHUNK):
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_base + cx * 3571 + cy * 6007 + 11
			var verts := PackedVector2Array()
			var cols := PackedColorArray()
			var uvs := PackedVector2Array()
			var fl := FlowerChunk.new()
			for y in range(cy, mini(cy + CHUNK, int(city.map_h))):
				for x in range(cx, mini(cx + CHUNK, int(city.map_w))):
					var c := Vector2i(x, y)
					if not is_grass(c):
						continue
					var p := cell_px(c)
					var u0 := Vector2(rng.randi() % V, rng.randi() % V) * uv_cell
					var u1 := u0 + Vector2(uv_cell, uv_cell)
					var v := noise.get_noise_2d(x, y)
					var tint := Color(1, 1, 1).lerp(Color(0.85, 0.9, 0.85), clampf(-v, 0.0, 1.0)).lerp(Color(1.08, 1.06, 0.95), clampf(v, 0.0, 1.0))
					var q0 := p
					var q1 := p + Vector2(_t, 0)
					var q2 := p + Vector2(_t, _t)
					var q3 := p + Vector2(0, _t)
					verts.append_array(PackedVector2Array([q0, q1, q2, q0, q2, q3]))
					uvs.append_array(PackedVector2Array([u0, Vector2(u1.x, u0.y), u1, u0, u1, Vector2(u0.x, u1.y)]))
					for k in 6:
						cols.append(tint)
					if rng.randf() < FLOWER_CHANCE:
						fl.clusters.append([p, rng.randi()])
			if verts.is_empty():
				fl.free()
				continue
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_COLOR] = cols
			arr[Mesh.ARRAY_TEX_UV] = uvs
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mi := MeshInstance2D.new()
			mi.mesh = mesh
			mi.texture = grass_tex
			mi.material = _grass_mat
			mi.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			root.add_child(mi)
			fl.tile = _t
			flowers_root.add_child(fl)


# ----------------------------------------------------------------------------
#  KERROSTALOJEN JULKISIVUT: parvekkeet ja kukkalaatikot ikkunoiden päälle
#  (oma solmu per talo Entities-solmussa, jotta ne piirtyvät ikkunatiilten päälle
#  mutta talon edessä kulkevien hahmojen alle)
# ----------------------------------------------------------------------------
func _build_facade_overlays(seed_base: int) -> void:
	var ents: Node2D = city.entities
	if ents == null:
		return
	var deco: TileMapLayer = city.deco_layer
	var layer: TileMapLayer = city.ground_layer
	for b: Dictionary in city.building_rects:
		if not bool(b.get("flat", false)):
			continue
		var lot: Rect2i = b.lot
		var fy: int = b.fy
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_base + lot.position.x * 131 + lot.position.y * 977
		var items: Array = []
		for y in range(fy, lot.end.y - 1):
			for x in range(lot.position.x, lot.end.x):
				var c := Vector2i(x, y)
				if deco.get_cell_source_id(c) == -1:
					continue
				var r := rng.randf()
				var p := layer.to_global(cell_px(c))
				if r < 0.35:
					items.append(["balcony", p, rng.randi()])
				elif r < 0.55:
					items.append(["flowers", p, rng.randi()])
		if items.is_empty():
			continue
		var ov := FacadeOverlay.new()
		ov.items = items
		ov.tile = _t
		ents.add_child(ov)
		# Järjestetään talon alareunan mukaan (y-sort)
		ov.global_position = layer.to_global(cell_px(Vector2i(lot.position.x, lot.end.y))) - Vector2(0, 1)


# ----------------------------------------------------------------------------
#  PINTA: reunakivet, kuluma, sävyt, talojen räystäät ja sokkelit
# ----------------------------------------------------------------------------
class SurfaceChunk extends Node2D:
	var decor = null
	var cells := Rect2i()
	var seed_value := 0

	func _draw() -> void:
		var d = decor
		var t: float = d._t
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var noise := FastNoiseLite.new()
		noise.seed = 1234
		noise.frequency = 0.045
		var flower_cols := [Color(1.0, 0.92, 0.35), Color(1.0, 1.0, 1.0), Color(1.0, 0.55, 0.7), Color(0.75, 0.6, 1.0)]
		for y in range(cells.position.y, cells.end.y):
			for x in range(cells.position.x, cells.end.x):
				var c := Vector2i(x, y)
				var p: Vector2 = d.cell_px(c)
				if d.is_grass(c):
					_grass_cell(c, p, t, rng, noise, flower_cols)
				elif d.is_asphalt(c):
					_asphalt_cell(c, p, t, rng, noise)
				elif d.is_sidewalk(c):
					_sidewalk_cell(p, t, rng)
		_buildings(t, rng)

	## Roskat ja liitumaalaukset jalkakäytävällä.
	func _sidewalk_cell(p: Vector2, t: float, rng: RandomNumberGenerator) -> void:
		var r := rng.randf()
		if r < LITTER_CHANCE:
			var q := p + Vector2(rng.randi_range(2, int(t) - 4), rng.randi_range(2, int(t) - 3))
			match rng.randi() % 5:
				0:  # paperi
					draw_rect(Rect2(q, Vector2(3, 2)), Color(0.95, 0.95, 0.9))
					draw_rect(Rect2(q + Vector2(0, 2), Vector2(3, 1)), Color(0, 0, 0, 0.2))
				1:  # tölkki
					draw_rect(Rect2(q, Vector2(2, 1)), [Color(0.85, 0.15, 0.15), Color(0.2, 0.45, 0.85), Color(0.75, 0.78, 0.8)][rng.randi() % 3])
					draw_rect(Rect2(q + Vector2(2, 0), Vector2(1, 1)), Color(0.85, 0.85, 0.85))
				2:  # tumpit
					for i in 3:
						draw_rect(Rect2(q + Vector2(rng.randi_range(-3, 3), rng.randi_range(-2, 2)), Vector2(1, 1)), Color(0.95, 0.85, 0.65))
				3:  # pahvimuki
					draw_rect(Rect2(q, Vector2(2, 3)), Color(0.95, 0.95, 0.95))
					draw_rect(Rect2(q, Vector2(2, 1)), Color(0.8, 0.3, 0.2))
				_:  # purkka / tahra
					draw_rect(Rect2(q, Vector2(2, 2)), Color(0.15, 0.12, 0.15, 0.35))
		elif r < LITTER_CHANCE + 0.006:
			# Liitumaalaus: ruutuhyppely tai hymynaama
			var col: Color = [Color(1, 1, 1, 0.55), Color(1.0, 0.7, 0.85, 0.6), Color(0.6, 0.85, 1.0, 0.6)][rng.randi() % 3]
			var q := p + Vector2(3, 3)
			if rng.randf() < 0.5:
				for i in 3:
					draw_rect(Rect2(q + Vector2(0, i * 4), Vector2(5, 4)), col, false, 1.0)
			else:
				draw_arc(q + Vector2(5, 5), 4.0, 0.0, TAU, 12, col, 1.0)
				draw_rect(Rect2(q + Vector2(3, 3), Vector2(1, 1)), col)
				draw_rect(Rect2(q + Vector2(6, 3), Vector2(1, 1)), col)
				draw_arc(q + Vector2(5, 5), 2.0, 0.3, PI - 0.3, 6, col, 1.0)

	## Graffiti tyhjään seinäruutuun: värikäs "tägi" tummalla ääriviivalla, joskus valumia.
	func _graffiti(p: Vector2, t: float, rng: RandomNumberGenerator) -> void:
		var cols := [Color(1.0, 0.3, 0.6), Color(0.3, 0.9, 1.0), Color(1.0, 0.85, 0.2), Color(0.5, 1.0, 0.4), Color(0.8, 0.5, 1.0), Color(1.0, 0.5, 0.2), Color(0.95, 0.95, 0.95)]
		var fill: Color = cols[rng.randi() % cols.size()]
		var ink := Color(0.08, 0.06, 0.12, 0.9)
		var n := rng.randi_range(2, 4)
		var w := (t - 2.0) / n
		var y0 := p.y + rng.randf_range(4.0, 7.0)
		var strokes: Array = []
		for i in n:
			var pts := PackedVector2Array()
			var x0 := p.x + 1.0 + i * w
			for k in rng.randi_range(3, 5):
				pts.append(Vector2(x0 + rng.randf_range(0.0, w - 1.0), y0 + rng.randf_range(0.0, 5.0)))
			strokes.append(pts)
		for pts in strokes:
			draw_polyline(pts, ink, 3.0)
		for pts in strokes:
			draw_polyline(pts, fill, 1.5)
		if rng.randf() < 0.4:
			var dx := p.x + rng.randf_range(3.0, t - 3.0)
			draw_line(Vector2(dx, y0 + 5.0), Vector2(dx, y0 + 5.0 + rng.randf_range(2.0, 4.0)), Color(fill, 0.8), 1.0)

	## Juliste seinässä
	func _poster(p: Vector2, t: float, rng: RandomNumberGenerator) -> void:
		var bg: Color = [Color(0.95, 0.9, 0.75), Color(0.9, 0.3, 0.25), Color(0.25, 0.45, 0.85), Color(1.0, 0.85, 0.3)][rng.randi() % 4]
		var r := Rect2(p + Vector2(rng.randi_range(2, 5), rng.randi_range(2, 4)), Vector2(8, 10))
		draw_rect(r.grow(1.0), Color(0, 0, 0, 0.25))
		draw_rect(r, bg)
		draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(6, 4)), bg.darkened(0.35))
		for i in 2:
			draw_rect(Rect2(r.position + Vector2(1, 6 + i * 2), Vector2(rng.randi_range(3, 6), 1)), Color(0.1, 0.1, 0.1, 0.7))

	func _grass_cell(c: Vector2i, p: Vector2, t: float, rng: RandomNumberGenerator, noise: FastNoiseLite, flower_cols: Array) -> void:
		# Sävyläikät (pehmeä kohina 8 px osissa)
		for sy in 2:
			for sx in 2:
				var v := noise.get_noise_2d(c.x * 2 + sx, c.y * 2 + sy)
				if absf(v) > 0.12:
					var col := Color(0.0, 0.12, 0.05, (absf(v) - 0.12) * 0.22) if v < 0.0 else Color(1.0, 0.95, 0.55, (v - 0.12) * 0.16)
					draw_rect(Rect2(p + Vector2(sx, sy) * t * 0.5, Vector2(t, t) * 0.5), col)
		var r := rng.randf()
		if r < 0.02:
			var q := p + Vector2(rng.randi_range(2, int(t) - 4), rng.randi_range(2, int(t) - 3))
			draw_rect(Rect2(q, Vector2(2, 1)), Color(0.62, 0.62, 0.6))
			draw_rect(Rect2(q + Vector2(0, 1), Vector2(2, 1)), Color(0.3, 0.32, 0.3, 0.8))

	func _asphalt_cell(c: Vector2i, p: Vector2, t: float, rng: RandomNumberGenerator, noise: FastNoiseLite) -> void:
		var d = decor
		var v := noise.get_noise_2d(c.x * 1.3 + 50.0, c.y * 1.3)
		if absf(v) > 0.15:
			draw_rect(Rect2(p, Vector2(t, t)), Color(0, 0, 0, (absf(v) - 0.15) * 0.12) if v < 0.0 else Color(1, 1, 1, (v - 0.15) * 0.06))
		if d.is_cross(c):
			# Kulunut maali suojatiessä
			for i in rng.randi_range(3, 7):
				var q := p + Vector2(rng.randi_range(0, int(t) - 2), rng.randi_range(0, int(t) - 2))
				draw_rect(Rect2(q, Vector2(rng.randi_range(1, 2), 1)), Color(0.33, 0.34, 0.42, 0.75))
		else:
			var r := rng.randf()
			if r < 0.03:
				# Halkeama
				var q := p + Vector2(rng.randf_range(2, t - 2), rng.randf_range(2, t - 2))
				var pts := PackedVector2Array([q])
				for i in rng.randi_range(2, 4):
					q += Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
					pts.append(q)
				draw_polyline(pts, Color(0.1, 0.1, 0.14, 0.6), 1.0)
			elif r < 0.05:
				# Öljytahra
				var q := p + Vector2(rng.randf_range(4, t - 4), rng.randf_range(4, t - 4))
				var rr := rng.randf_range(2.5, 5.5)
				_ellipse(q, rr, rr * rng.randf_range(0.5, 0.8), Color(0.03, 0.03, 0.06, 0.28))
				_ellipse(q + Vector2(-1, -1), rr * 0.5, rr * 0.3, Color(0.4, 0.3, 0.6, 0.12))
			elif r < 0.075:
				# Paikkaus
				var sz := Vector2(rng.randi_range(5, 12), rng.randi_range(4, 9))
				var q := p + Vector2(rng.randi_range(0, int(t - sz.x)), rng.randi_range(0, int(t - sz.y)))
				draw_rect(Rect2(q, sz), Color(0.0, 0.0, 0.05, 0.1))
				draw_rect(Rect2(q, sz), Color(0, 0, 0, 0.15), false, 1.0)
		# Reunakivet: tien ja muun pinnan rajalla
		for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := c + dir
			if not d.in_bounds(n) or d.is_asphalt(n):
				continue
			if dir == Vector2i.UP:
				draw_rect(Rect2(p + Vector2(0, -2), Vector2(t, 2)), CURB_LIGHT)
				draw_rect(Rect2(p, Vector2(t, 2)), CURB_DARK)
			elif dir == Vector2i.DOWN:
				draw_rect(Rect2(p + Vector2(0, t), Vector2(t, 2)), CURB_LIGHT)
				draw_rect(Rect2(p + Vector2(0, t), Vector2(t, 1)), Color(1, 1, 1, 0.25))
				draw_rect(Rect2(p + Vector2(0, t - 1), Vector2(t, 1)), CURB_DARK)
			elif dir == Vector2i.LEFT:
				draw_rect(Rect2(p + Vector2(-2, 0), Vector2(2, t)), CURB_LIGHT)
				draw_rect(Rect2(p, Vector2(2, t)), CURB_DARK)
			else:
				draw_rect(Rect2(p + Vector2(t, 0), Vector2(2, t)), CURB_LIGHT)
				draw_rect(Rect2(p + Vector2(t - 1, 0), Vector2(1, t)), CURB_DARK)

	## Talojen kattosävy, kattoreunan huullos, räystään varjo, sokkeli ja seinän valo/varjopuoli.
	func _buildings(t: float, rng: RandomNumberGenerator) -> void:
		var d = decor
		var deco: TileMapLayer = d.city.deco_layer
		var tints := [Color(0, 0, 0, 0.1), Color(1, 1, 1, 0.07), Color(1.0, 0.7, 0.3, 0.08), Color(0.3, 0.4, 1.0, 0.07), Color(0, 0, 0, 0)]
		for b: Dictionary in d.city.building_rects:
			var lot: Rect2i = b.lot
			if not cells.has_point(lot.position):
				continue
			var fy: int = b.fy
			var p0: Vector2 = d.cell_px(lot.position)
			var p1: Vector2 = d.cell_px(lot.end)
			var roof_end_y: float = d.cell_px(Vector2i(0, fy)).y if fy >= 0 else p1.y
			var roof := Rect2(p0, Vector2(p1.x - p0.x, roof_end_y - p0.y))
			var flat := bool(b.get("flat", false))
			if flat:
				_flat_roof(roof, rng)
			elif not bool(b.landmark):
				var h := absi(hash(lot.position))
				draw_rect(roof, tints[h % tints.size()])
				draw_rect(Rect2(roof.position, Vector2(roof.size.x, 1)), Color(1, 1, 1, 0.22))
				draw_rect(Rect2(roof.position, Vector2(1, roof.size.y)), Color(1, 1, 1, 0.12))
				draw_rect(Rect2(Vector2(roof.end.x - 1, roof.position.y), Vector2(1, roof.size.y)), Color(0, 0, 0, 0.18))
			if fy >= 0:
				var face := Rect2(Vector2(p0.x, roof_end_y), Vector2(p1.x - p0.x, p1.y - roof_end_y))
				# räystään varjo
				draw_rect(Rect2(face.position, Vector2(face.size.x, 3)), Color(0.05, 0.05, 0.15, 0.32))
				draw_rect(Rect2(face.position + Vector2(0, 3), Vector2(face.size.x, 2)), Color(0.05, 0.05, 0.15, 0.13))
				# lämmin länsireuna, viileä itäreuna
				draw_rect(Rect2(face.position, Vector2(2, face.size.y)), Color(1.0, 0.9, 0.7, 0.12))
				draw_rect(Rect2(Vector2(face.end.x - 3, face.position.y), Vector2(3, face.size.y)), Color(0.1, 0.12, 0.35, 0.16))
				# kerrostalon kerrosten välinen reunus
				if flat:
					var yy := face.position.y + t
					while yy < face.end.y - 1.0:
						draw_rect(Rect2(Vector2(face.position.x, yy - 1.0), Vector2(face.size.x, 1)), Color(1, 1, 1, 0.16))
						draw_rect(Rect2(Vector2(face.position.x, yy), Vector2(face.size.x, 1)), Color(0, 0, 0, 0.14))
						yy += t
				# graffitit ja julisteet tyhjiin seinäruutuihin (kahdella alimmalla rivillä)
				for yy in range(maxi(fy, lot.end.y - 2), lot.end.y):
					for xx in range(lot.position.x, lot.end.x):
						var wc := Vector2i(xx, yy)
						if deco.get_cell_source_id(wc) != -1:
							continue
						var rr := rng.randf()
						if rr < GRAFFITI_CHANCE and yy == lot.end.y - 1:
							_graffiti(d.cell_px(wc), t, rng)
						elif rr < GRAFFITI_CHANCE + 0.07:
							_poster(d.cell_px(wc), t, rng)
				# roskapussit oven viereen
				for xx in range(lot.position.x, lot.end.x):
					var dc := Vector2i(xx, lot.end.y - 1)
					var src_id := deco.get_cell_source_id(dc)
					if src_id == -1:
						continue
					var at := deco.get_cell_atlas_coords(dc)
					if CityGenerator.DOORS.has(at) and rng.randf() < 0.4:
						var side := 1.0 if rng.randf() < 0.5 else -1.0
						var q: Vector2 = d.cell_px(dc) + Vector2(t * 0.5 + side * 11.0, t + 1.0)
						for i in rng.randi_range(1, 3):
							var bq := q + Vector2(i * 4.0 * side, rng.randf_range(-1.0, 1.0))
							var bc: Color = [Color(0.12, 0.13, 0.12), Color(0.15, 0.3, 0.18), Color(0.2, 0.2, 0.28)][rng.randi() % 3]
							_ellipse(bq + Vector2(0.5, 1.5), 3.0, 1.4, Color(0, 0, 0, 0.25))
							_ellipse(bq, 2.8, 2.6, bc)
							draw_rect(Rect2(bq + Vector2(-1, -3), Vector2(2, 1)), bc.lightened(0.3))
				# sokkeli
				draw_rect(Rect2(Vector2(face.position.x, face.end.y - 2), Vector2(face.size.x, 2)), Color(0.05, 0.05, 0.1, 0.35))
			# kosketusvarjo seinän juuressa maassa
			draw_rect(Rect2(Vector2(p0.x, p1.y), Vector2(p1.x - p0.x, 2)), Color(0.05, 0.06, 0.18, 0.22))
			draw_rect(Rect2(Vector2(p0.x, p1.y + 2), Vector2(p1.x - p0.x, 1)), Color(0.05, 0.06, 0.18, 0.1))

	## Kerrostalon tasakatto: harmaa bitumi, reunamuuri, ilmanvaihtohormit ja porraskuilu.
	func _flat_roof(roof: Rect2, rng: RandomNumberGenerator) -> void:
		if roof.size.x < 8.0 or roof.size.y < 8.0:
			return
		var base := Color(0.46, 0.47, 0.52).lerp(Color(0.52, 0.48, 0.45), rng.randf())
		draw_rect(roof, base)
		# kuviointi
		for i in int(roof.get_area() / 40.0):
			var q := roof.position + Vector2(rng.randf_range(3, roof.size.x - 4), rng.randf_range(3, roof.size.y - 4))
			draw_rect(Rect2(q, Vector2(rng.randi_range(1, 3), 1)), Color(0, 0, 0, 0.08) if rng.randf() < 0.6 else Color(1, 1, 1, 0.06))
		# reunamuuri
		draw_rect(roof, base.lightened(0.28), false, 2.0)
		draw_rect(roof.grow(-2.0), Color(0, 0, 0, 0.22), false, 1.0)
		# porraskuilu
		var sw := minf(14.0, roof.size.x * 0.35)
		var sh := minf(10.0, roof.size.y * 0.4)
		var sp := roof.position + Vector2(rng.randf_range(4.0, roof.size.x - sw - 4.0), rng.randf_range(4.0, roof.size.y - sh - 4.0))
		draw_rect(Rect2(sp + Vector2(2, 2), Vector2(sw, sh)), Color(0.07, 0.09, 0.24, 0.3))
		draw_rect(Rect2(sp, Vector2(sw, sh)), base.darkened(0.15))
		draw_rect(Rect2(sp, Vector2(sw, 2)), base.lightened(0.2))
		draw_rect(Rect2(sp + Vector2(sw * 0.5 - 2, sh - 5), Vector2(4, 5)), Color(0.3, 0.25, 0.22))
		# hormit ja tuulettimet
		for i in rng.randi_range(2, 4):
			var q := roof.position + Vector2(rng.randf_range(4, roof.size.x - 7), rng.randf_range(4, roof.size.y - 7))
			draw_rect(Rect2(q + Vector2(1, 1), Vector2(4, 4)), Color(0.07, 0.09, 0.24, 0.3))
			draw_rect(Rect2(q, Vector2(4, 4)), Color(0.62, 0.63, 0.66))
			draw_rect(Rect2(q + Vector2(1, 1), Vector2(2, 2)), Color(0.25, 0.26, 0.3))
		# joskus satelliittiantenni
		if rng.randf() < 0.5:
			var q := roof.position + Vector2(rng.randf_range(5, roof.size.x - 6), rng.randf_range(5, roof.size.y - 6))
			draw_circle(q, 2.5, Color(0.9, 0.9, 0.92))
			draw_circle(q + Vector2(0.5, 0.5), 1.0, Color(0.5, 0.5, 0.55))

	func _ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
		draw_set_transform(center, 0.0, Vector2(1.0, ry / maxf(rx, 0.01)))
		draw_circle(Vector2.ZERO, rx, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ----------------------------------------------------------------------------
#  AURINGON VARJOT (staattiset)
# ----------------------------------------------------------------------------
class ShadowChunk extends Node2D:
	var polys: Array = []        ## [PackedVector2Array, Color]
	var ellipses: Array = []     ## [keskipiste, rx, ry, Color]
	var lines: Array = []        ## [a, b, leveys, Color]

	func _draw() -> void:
		for e in polys:
			draw_colored_polygon(e[0], e[1])
		for l in lines:
			draw_line(l[0], l[1], l[3], l[2])
		for e in ellipses:
			var rx: float = e[1]
			var ry: float = e[2]
			draw_set_transform(e[0], 0.0, Vector2(1.0, ry / maxf(rx, 0.01)))
			draw_circle(Vector2.ZERO, rx, e[3])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ----------------------------------------------------------------------------
#  HAHMOJEN JA AUTOJEN VARJOT (päivittyvät joka ruutu, vain näkyvältä alueelta)
# ----------------------------------------------------------------------------
class EntityShadows extends Node2D:
	var decor = null
	const GROUPS := ["player", "shootable", "car_targets", "player_vehicles", "police_wrecks", "police", "bar_patron", "street_thug"]

	func _process(_delta: float) -> void:
		queue_redraw()

	func _view_rect() -> Rect2:
		var cam := get_viewport().get_camera_2d()
		var vs := get_viewport().get_visible_rect().size
		if cam == null:
			return Rect2(-1e6, -1e6, 2e6, 2e6)
		var size := vs / cam.zoom
		return Rect2(cam.get_screen_center_position() - size * 0.5, size).grow(96.0)

	func _sprite_of(n: Node) -> Node2D:
		for prop in ["visual", "sprite", "animated_sprite"]:
			var v = n.get(prop)
			if v is Sprite2D or v is AnimatedSprite2D:
				return v
		for ch in n.get_children():
			if ch is AnimatedSprite2D or ch is Sprite2D:
				return ch
		return null

	func _rect_of(s: Node2D) -> Rect2:
		if s is Sprite2D:
			var sp := s as Sprite2D
			if sp.texture == null:
				return Rect2()
			return sp.get_rect()
		var a := s as AnimatedSprite2D
		if a.sprite_frames == null or not a.sprite_frames.has_animation(a.animation):
			return Rect2()
		var tex := a.sprite_frames.get_frame_texture(a.animation, a.frame)
		if tex == null:
			return Rect2()
		var sz := tex.get_size()
		var pos := a.offset - (sz * 0.5 if a.centered else Vector2.ZERO)
		return Rect2(pos, sz)

	func _draw() -> void:
		var view := _view_rect()
		var seen := {}
		var nodes: Array = []
		for g: String in GROUPS:
			for n in get_tree().get_nodes_in_group(g):
				nodes.append(n)
		var pm := get_tree().get_first_node_in_group("police_manager")
		if pm:
			for n in pm.get("officers"):
				nodes.append(n)
			for n in pm.get("cars"):
				nodes.append(n)
		for n in nodes:
			if not is_instance_valid(n) or not (n is Node2D):
				continue
			var id: int = n.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			var n2 := n as Node2D
			if not n2.is_visible_in_tree() or not view.has_point(n2.global_position):
				continue
			var s := _sprite_of(n)
			if s == null or not s.is_visible_in_tree():
				continue
			var r := _rect_of(s)
			if r.size == Vector2.ZERO:
				continue
			var gp := s.global_position
			var sc := s.global_scale
			var gr := Rect2(gp + r.position * sc, r.size * sc)
			var is_car: bool = n.is_in_group("player_vehicles") or n.is_in_group("car_targets") \
				or n.is_in_group("police_wrecks") or Game.flag(n, "is_car") \
				or (n.get_script() != null and str((n.get_script() as Script).resource_path).get_file().contains("Car"))
			var lying := absf(wrapf(s.global_rotation, -PI, PI)) > 0.5
			if is_car:
				var rr := Rect2(to_local(gr.position) + Vector2(2.0, 3.0), gr.size - Vector2(1.0, 2.0))
				draw_rect(rr.grow(1.0), Color(ENTITY_SHADOW, ENTITY_SHADOW.a * 0.4))
				draw_rect(rr, ENTITY_SHADOW)
			else:
				var foot := to_local(Vector2(gr.get_center().x, gr.end.y - 1.0))
				var rx := gr.size.x * 0.34
				var ry := 2.4
				if lying:
					foot = to_local(gr.get_center() + Vector2(0, gr.size.y * 0.2))
					rx = maxf(gr.size.x, gr.size.y) * 0.45
					ry = 3.0
				foot += Vector2(1.5, 0.0)
				draw_set_transform(foot, 0.0, Vector2(1.0, (ry + 1.0) / (rx + 1.0)))
				draw_circle(Vector2.ZERO, rx + 1.0, Color(ENTITY_SHADOW, ENTITY_SHADOW.a * 0.4))
				draw_set_transform(foot, 0.0, Vector2(1.0, ry / rx))
				draw_circle(Vector2.ZERO, rx, ENTITY_SHADOW)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ----------------------------------------------------------------------------
#  KERROSTALON PARVEKKEET JA KUKKALAATIKOT (ikkunatiilten päällä)
# ----------------------------------------------------------------------------
class FacadeOverlay extends Node2D:
	var items: Array = []     ## [laji, ruudun vasen yläkulma (globaali), siemen]
	var tile := 16.0

	func _draw() -> void:
		for it in items:
			var p: Vector2 = to_local(it[1])
			var rng := RandomNumberGenerator.new()
			rng.seed = int(it[2])
			if str(it[0]) == "balcony":
				var col: Color = [Color(0.85, 0.85, 0.82), Color(0.35, 0.36, 0.4), Color(0.75, 0.55, 0.35)][rng.randi() % 3]
				var r := Rect2(p + Vector2(1, tile - 5), Vector2(tile - 2, 4))
				draw_rect(Rect2(r.position + Vector2(0, 4), Vector2(r.size.x, 1)), Color(0, 0, 0, 0.3))
				draw_rect(Rect2(r.position + Vector2(0, 3), Vector2(r.size.x, 1)), col.darkened(0.3))
				draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), col)
				var x := r.position.x
				while x <= r.end.x:
					draw_rect(Rect2(Vector2(x, r.position.y), Vector2(1, 3)), col)
					x += 3.0
				if rng.randf() < 0.35:
					# pyykkiä tai pyyhe kaiteella
					var pc: Color = [Color(0.95, 0.4, 0.4), Color(0.4, 0.7, 1.0), Color(1.0, 0.9, 0.5)][rng.randi() % 3]
					draw_rect(Rect2(r.position + Vector2(rng.randi_range(1, 6), 0), Vector2(4, 4)), pc)
			else:
				var r := Rect2(p + Vector2(3, tile - 4), Vector2(tile - 6, 3))
				draw_rect(r, Color(0.5, 0.32, 0.2))
				for i in 4:
					var fc: Color = [Color(1.0, 0.35, 0.4), Color(1.0, 0.85, 0.3), Color(0.9, 0.5, 1.0), Color(1, 1, 1)][rng.randi() % 4]
					var q := r.position + Vector2(1 + i * (r.size.x - 2) / 4.0, -1)
					draw_rect(Rect2(q + Vector2(0, 1), Vector2(1, 1)), Color(0.2, 0.55, 0.25))
					draw_rect(Rect2(q, Vector2(2, 1)), fc)


# ----------------------------------------------------------------------------
#  KUKAT nurmikolla (ryhmissä, ruohon päällä)
# ----------------------------------------------------------------------------
class FlowerChunk extends Node2D:
	var clusters: Array = []     ## [ruudun vasen yläkulma, siemen]
	var tile := 16.0
	const COLS := [Color(1.0, 0.35, 0.45), Color(1.0, 0.86, 0.25), Color(0.97, 0.97, 1.0), Color(0.72, 0.5, 1.0),
		Color(1.0, 0.55, 0.2), Color(0.45, 0.65, 1.0), Color(1.0, 0.6, 0.85)]

	func _draw() -> void:
		var stem := Color(0.12, 0.42, 0.2)
		for cl in clusters:
			var p: Vector2 = cl[0]
			var rng := RandomNumberGenerator.new()
			rng.seed = int(cl[1])
			var col: Color = COLS[rng.randi() % COLS.size()]
			var kind := rng.randi() % 3
			# piirretään puolen pikselin tarkkuudella (sama tiheys kuin hahmoissa)
			for i in rng.randi_range(3, 7):
				var q := p + Vector2(rng.randi_range(4, int(tile) * 2 - 6), rng.randi_range(6, int(tile) * 2 - 4)) * 0.5
				draw_set_transform(q, 0.0, Vector2(0.5, 0.5))
				draw_rect(Rect2(Vector2(0, 1), Vector2(1, 3)), stem)
				draw_rect(Rect2(Vector2(1, 2), Vector2(1, 1)), stem.lightened(0.15))
				if kind == 0:
					# pieni kukka: risti + keskusta
					draw_rect(Rect2(Vector2(-1, 0), Vector2(3, 1)), col)
					draw_rect(Rect2(Vector2(0, -1), Vector2(1, 3)), col)
					draw_rect(Rect2(Vector2(-1, -1), Vector2(1, 1)), col.lightened(0.3))
					draw_rect(Rect2(Vector2.ZERO, Vector2(1, 1)), Color(1.0, 0.95, 0.4) if col != COLS[1] else Color(0.6, 0.3, 0.1))
				elif kind == 1:
					# tulppaani
					draw_rect(Rect2(Vector2(-1, -1), Vector2(3, 2)), col)
					draw_rect(Rect2(Vector2(-1, -2), Vector2(1, 1)), col.lightened(0.25))
					draw_rect(Rect2(Vector2(1, -2), Vector2(1, 1)), col)
					draw_rect(Rect2(Vector2(1, 0), Vector2(1, 1)), col.darkened(0.25))
					draw_rect(Rect2(Vector2(-1, 3), Vector2(1, 1)), stem.lightened(0.2))
				else:
					# päivänkakkara / pieni pallokukka
					draw_rect(Rect2(Vector2(-1, -1), Vector2(3, 3)), col)
					draw_rect(Rect2(Vector2(-1, -1), Vector2(1, 1)), col.lightened(0.3))
					draw_rect(Rect2(Vector2(1, 1), Vector2(1, 1)), col.darkened(0.2))
					draw_rect(Rect2(Vector2.ZERO, Vector2(1, 1)), Color(1.0, 0.85, 0.2))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
