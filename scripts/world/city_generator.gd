class_name CityGenerator
extends Node2D
## Proseduraalinen top-down kaupunkigeneraattori (Godot 4.3+, TileMapLayer).
##
## Scene:
##   City (Node2D, tämä scripti, y_sort_enabled = true)
##    ├─ Ground   (TileMapLayer, TileSet = tilemap_packed)
##    ├─ Deco     (TileMapLayer, y_sort_enabled = true)
##    └─ Entities (Node2D, y_sort_enabled = true)

# ----------------------------------------------------------------------------
#  EXPORTIT
# ----------------------------------------------------------------------------
@export_group("Nodes")
@export var ground_layer: TileMapLayer
@export var deco_layer: TileMapLayer
@export var entities: Node2D
@export var source_id := 0

@export_group("Map")
@export var map_size := Vector2i(256, 256)
## 0 = satunnainen siemen joka kerta
@export var seed_value := 0
@export var generate_on_ready := true
## Atlaksen asetukset (tilemap.png: 16 px tiilet, 1 px väli). Scripti korjaa TileSetin näihin.
@export var atlas_tile_size := 16
@export var atlas_separation := 1

@export_group("Roads & blocks")
## Tien leveys ruutuina. Käytä PARITONTA lukua (3, 5, 7...): keskiviiva jää keskelle ja
## kumpaankin suuntaan tulee yhtä monta kaistaa (5 = 2+2 kaistaa, 7 = 3+3, 3 = 1+1).
@export var road_width := 5
@export var avenue_width := 7
@export var avenue_every := 4
@export var block_min := 12
@export var block_max := 22
@export var sidewalk_width := 2

@export_group("Block content")
@export_range(0.0, 1.0) var park_chance := 0.15
@export_range(0.0, 1.0) var plaza_chance := 0.08
@export var lot_min := 4
@export var lot_max := 10
@export var lamp_spacing := 7

@export_group("Entities & physics")
@export var npc_count := 250
@export var car_count := 100
## Lisää TileSetiin törmäys- ja navigaatiopolygonit ajonaikaisesti
@export var setup_tileset_physics := true

@export_group("Parking lots")
## Todennäköisyys että (muu kuin aloitus-) kortteli on parkkipaikka
@export_range(0.0, 1.0) var parking_chance := 0.08
## Kuinka suuri osa parkkiruuduista on varattu autolla
@export_range(0.0, 1.0) var parking_fill_chance := 0.75
## Tekee pelaajan aloituspaikan viereisestä korttelista aina parkkipaikan
@export var start_parking_lot := true

# ----------------------------------------------------------------------------
#  TILE-KOORDINAATIT ATLAKSESSA (sarake, rivi)  (tarkistettu tilemap.png:stä, 27x18 tiiltä)
#  Käytä atlas_viewer.gd:tä ja korjaa arvot oikeiksi.
#  "o" = patchin vasen yläkulma, "s" = koko tiileinä (9-slice: kulmat,
#  reunat ja keskitiili)
# ----------------------------------------------------------------------------
const GRASS := Vector2i(1, 1)
const ROAD := Vector2i(9, 16)
const SIDEWALK := Vector2i(1, 4)   # keltainen: käytetään vain kapeana jalkakäytävänä ja ovipolkuina
## Julkisivun seinä (harmaa, täysin tasainen tiili; käyttämätön 3x3-alueen keskus)
const WALL := Vector2i(9, 4)

## Tiemerkinnät
const ROAD_DASH_V := Vector2i(3, 17)   # keskiviiva pystytielle
const ROAD_DASH_H := Vector2i(1, 16)   # keskiviiva vaakatielle
## Suojatie pystytien yli: [vasen reuna, keski, oikea reuna]
const CROSS_V := [Vector2i(2, 16), Vector2i(3, 16), Vector2i(4, 16)]
## Suojatie vaakatien yli: [ylä, keski, ala]
const CROSS_H := [Vector2i(0, 15), Vector2i(0, 16), Vector2i(0, 17)]

const PARK := {"o": Vector2i(0, 0), "s": Vector2i(3, 3)}
const PLAZA := {"o": Vector2i(8, 0), "s": Vector2i(3, 3)}
const WATER := {"o": Vector2i(8, 6), "s": Vector2i(3, 3)}
## "mx" = keskisarakkeet joista arvotaan, "my" = keskirivi (pelkkä katto, ei harjaa)
const ROOFS := [
	{"o": Vector2i(17, 0), "s": Vector2i(6, 4), "mx": [1, 2, 3, 4], "my": 2}, # punainen
	{"o": Vector2i(17, 4), "s": Vector2i(6, 4), "mx": [1, 2, 3, 4], "my": 2}, # oranssi
]
## Puistopuut (1x2 = latvus + runko, 1x1 = yksittäinen)
const TREES := [
	{"o": Vector2i(16, 8), "s": Vector2i(1, 2)},
	{"o": Vector2i(17, 8), "s": Vector2i(1, 2)},
	{"o": Vector2i(16, 11), "s": Vector2i(1, 2)},
	{"o": Vector2i(17, 11), "s": Vector2i(1, 2)},
	{"o": Vector2i(22, 10), "s": Vector2i(1, 1)},
	{"o": Vector2i(22, 13), "s": Vector2i(1, 1)},
]
## Katupuut istutuslaatikossa (1x1)
const STREET_TREES := [
	{"o": Vector2i(16, 10), "s": Vector2i(1, 1)},
	{"o": Vector2i(17, 10), "s": Vector2i(1, 1)},
	{"o": Vector2i(16, 13), "s": Vector2i(1, 1)},
	{"o": Vector2i(17, 13), "s": Vector2i(1, 1)},
	{"o": Vector2i(21, 10), "s": Vector2i(1, 1)},
	{"o": Vector2i(21, 13), "s": Vector2i(1, 1)},
]
const LAMPS := [
	{"o": Vector2i(2, 6), "s": Vector2i(1, 2)},
	{"o": Vector2i(3, 6), "s": Vector2i(1, 2)},
	{"o": Vector2i(7, 6), "s": Vector2i(1, 2)},
]
## Katukilvet (1x2)
const SIGNS := [
	{"o": Vector2i(4, 6), "s": Vector2i(1, 2)},
	{"o": Vector2i(5, 6), "s": Vector2i(1, 2)},
	{"o": Vector2i(6, 6), "s": Vector2i(1, 2)},
]
## Liikennevalot (1x1, sijoitetaan risteysten kulmiin)
const TRAFFIC_LIGHTS := [
	{"o": Vector2i(3, 15), "s": Vector2i(1, 1)},
	{"o": Vector2i(4, 15), "s": Vector2i(1, 1)},
]
## Pienet katu- ja puistokalusteet (1x1): penkit, roskikset, postilaatikot,
## paloposti, pensasaidat, laatikot/istutukset, tiesulut
const SMALL_PROPS := [
	{"o": Vector2i(7, 8), "s": Vector2i(1, 1)},   # penkki
	{"o": Vector2i(7, 9), "s": Vector2i(1, 1)},   # penkki
	{"o": Vector2i(8, 9), "s": Vector2i(1, 1)},   # punainen roskis/paloposti
	{"o": Vector2i(9, 9), "s": Vector2i(1, 1)},   # roskis
	{"o": Vector2i(10, 9), "s": Vector2i(1, 1)},  # roskis
	{"o": Vector2i(8, 10), "s": Vector2i(1, 1)},
	{"o": Vector2i(9, 10), "s": Vector2i(1, 1)},
	{"o": Vector2i(10, 10), "s": Vector2i(1, 1)},
	{"o": Vector2i(8, 11), "s": Vector2i(1, 1)},  # postilaatikko
	{"o": Vector2i(9, 11), "s": Vector2i(1, 1)},  # postilaatikko
	{"o": Vector2i(10, 11), "s": Vector2i(1, 1)},
	{"o": Vector2i(4, 12), "s": Vector2i(1, 1)},  # pensas
	{"o": Vector2i(5, 12), "s": Vector2i(1, 1)},
	{"o": Vector2i(6, 12), "s": Vector2i(1, 1)},
	{"o": Vector2i(7, 12), "s": Vector2i(1, 1)},
	{"o": Vector2i(8, 12), "s": Vector2i(1, 1)},
	{"o": Vector2i(3, 10), "s": Vector2i(1, 1)},  # laatikot / kukkalaatikot
	{"o": Vector2i(4, 10), "s": Vector2i(1, 1)},
	{"o": Vector2i(5, 10), "s": Vector2i(1, 1)},
	{"o": Vector2i(6, 10), "s": Vector2i(1, 1)},
	{"o": Vector2i(3, 11), "s": Vector2i(1, 1)},
	{"o": Vector2i(4, 11), "s": Vector2i(1, 1)},
	{"o": Vector2i(5, 11), "s": Vector2i(1, 1)},
	{"o": Vector2i(6, 11), "s": Vector2i(1, 1)},
	{"o": Vector2i(3, 14), "s": Vector2i(1, 1)},  # puupenkki
	{"o": Vector2i(5, 8), "s": Vector2i(1, 1)},   # tiesulku
	{"o": Vector2i(6, 8), "s": Vector2i(1, 1)},
	{"o": Vector2i(5, 9), "s": Vector2i(1, 1)},
	{"o": Vector2i(6, 9), "s": Vector2i(1, 1)},
]
## Isommat kalusteet (1x2)
const TALL_PROPS := [
	{"o": Vector2i(7, 10), "s": Vector2i(1, 2)},  # hedelmäkoju
]
## Kattolaitteet (ilmastointi yms.)
const ROOF_PROPS := [Vector2i(9, 12), Vector2i(10, 12)]

## Julkisivu: [ylärivin ikkuna, alarivin ikkuna]
const WINDOW_SETS := [
	[Vector2i(12, 13), Vector2i(13, 13)],
	[Vector2i(12, 12), Vector2i(13, 13)],
	[Vector2i(12, 14), Vector2i(13, 14)],
	[Vector2i(13, 12), Vector2i(13, 13)],
	[Vector2i(11, 13), Vector2i(12, 13)],
]
const DOORS := [Vector2i(13, 10), Vector2i(14, 10)]
## Kaupan näyteikkuna 3x2 (vihreä markiisi)
const SHOPFRONT := {"o": Vector2i(8, 13), "s": Vector2i(3, 2)}

## NPC:t: sarakkeet = [vasen, alas, ylös, oikea]; jokaisella hahmolla 3 riviä
## (seisova, kävely 1, kävely 2)
const NPC_FIRST_COL := 23
## Tarkka (2x) versio tilemapista: piirretään alkuperäisen kokoisena (size override)
const ATLAS_HD_PATH := "res://assets/sprites/tilemap_hd.png"
const CHAR_SPRITES := preload("res://scripts/core/CharSprites.gd")
const HD_TEX := preload("res://scripts/core/HDTex.gd")
const NPC_TYPES := 6
## Autot rakennetaan ajonaikaisesti tilemapista (saumattomasti).
## Arvot: [sarake_alku, sarake_loppu, rivi_alku, rivi_loppu] (tiiliä)
const CAR_SETS := {
	"green": {"down": [21, 21, 14, 15], "up": [22, 22, 14, 15], "left": [21, 22, 16, 16], "right": [21, 22, 17, 17]},
	"yellow": {"down": [17, 17, 14, 15], "up": [20, 20, 14, 15], "left": [15, 16, 14, 15], "right": [18, 19, 14, 15]},
	"red": {"down": [17, 17, 16, 17], "up": [20, 20, 16, 17], "left": [15, 16, 16, 17], "right": [18, 19, 16, 17]},
}

## Parkkipaikka: 2x2-ruudun parkkiruutu (pyöristetty kehys) ja P-merkki
const PARKING_STALL := {"o": Vector2i(5, 16), "s": Vector2i(2, 2)}
const PARKING_SIGN := Vector2i(10, 16)
const CAR_SCENE: PackedScene = preload("res://scenes/entities/vehicles/car.tscn")
## Asekauppa: erottuva rakennus + sisätila (rynnäkkökivääri)
const ARMORY_SCRIPT := preload("res://scripts/world/Armory.gd")
## Pelaajan koti: peli alkaa sen sisältä
const CAR_FX_SCRIPT := preload("res://scripts/entities/CarFX.gd")
const HOME_SCRIPT := preload("res://scripts/world/Home.gd")
## Baari: Koskenkorvaa tiskillä, kännissä kamera heiluu
const BAR_SCRIPT := preload("res://scripts/world/Bar.gd")
## Palvelurakennukset (sairaala, pankki, kauppa, päätavoitteen kiinteistövälitys, tori ja kartano)
const SERVICE_SCRIPT := preload("res://scripts/world/ServiceBuilding.gd")
const SERVICE_ORDER := ["shop", "hospital", "bank", "realtor", "market", "manor"]
const MARKET_SCRIPT := preload("res://scripts/world/Market.gd")
## Palvelut sijoitetaan korkeintaan näin monen ruudun päähän kodista (jos tilaa riittää)
const SERVICE_RADIUS := 110.0
## Osuus tavallisista tonteista, joille rakennetaan kerrostalo (3-5 kerrosta, tasakatto)
const APARTMENT_CHANCE := 0.4
## Kodin autotallin leveys ruutuina
const GARAGE_W := 3
## Parkkipaikan autotyypit. color "" = pelaajan oma autokuva (car.tscn).
## Eri autoilla on eri huippunopeus.
const PARKED_CAR_TYPES := [
	{"color": "", "speed": 250.0},
	{"color": "green", "speed": 210.0},
	{"color": "yellow", "speed": 270.0},
	{"color": "red", "speed": 310.0},
]

# ----------------------------------------------------------------------------
#  TILA
# ----------------------------------------------------------------------------
var rng := RandomNumberGenerator.new()
var map_w := 0
var map_h := 0
var tile := 16
var stride := 17
var atlas_src: TileSetAtlasSource

var col_road := PackedByteArray()   # x on pystytiellä
var row_road := PackedByteArray()   # y on vaakatiellä
var solid := PackedByteArray()      # este (talo, vesi, puun runko, lamppu)
var ped_spawns: Array[Vector2i] = []
var astar := AStarGrid2D.new()
## Jalankulkijoiden reitinhaku: tie on kiellettyä muualla kuin suojateillä
var ped_astar := AStarGrid2D.new()
## Suojatieruudut (tieruutuja, joita jalankulkijat saavat käyttää): ruutu -> true
var crosswalk_cells := {}
var road_x: Array[Vector2i] = []
var road_y: Array[Vector2i] = []
var _tex_cache := {}
var _car_tex := {}            # väri -> suunta -> Texture2D
var door_cells: Array[Vector2i] = []
## Kaikkien rakennusten ovet ja erikoisrakennusten tontit (edustan siivous lopuksi)
var _all_doors: Array[Vector2i] = []
var _landmark_lots: Array[Rect2i] = []
## Tavalliset talokorttelit: varapaikka, jos jokin erikoisrakennus jäi puuttumaan
var _plain_blocks: Array[Rect2i] = []
## Kaikki talot koristekerrosta (CityDecor.gd) varten: {lot: Rect2i, fy: julkisivun ylärivi tai -1, landmark: bool}
var building_rects: Array[Dictionary] = []
## Sijoitetut kalusteet: ruutu -> {"cells": [...], "base": Vector2i, "lamp": bool}
var _prop_at := {}
var armory_block := Vector2i(-1, -1)   # korttelin sijainti, johon asekauppa rakennetaan
var armory: Node2D = null
var home_block := Vector2i(-1, -1)     # korttelin sijainti, johon pelaajan koti rakennetaan
var home: Node2D = null
var bar_block := Vector2i(-1, -1)      # korttelin sijainti, johon baari rakennetaan
var bar: Node2D = null
var home_door_cell := Vector2i(-1, -1)
var home_yard_cell := Vector2i(-1, -1)   # pihan ruutu talon sivulla, johon aloitustaksi pysäköidään
## Pelaajan ja aloituspistoolin paikat (maailmankoordinaatit), poliisi käyttää näitä pidätyksen jälkeen
var player_start_global := Vector2.ZERO
var pistol_start_global := Vector2.ZERO
var _path_cells := {}
## Parkkiruudut: {"cell": ruudun vasen yläkulma, "facing": auton suunta}
var parking_slots: Array[Dictionary] = []
## Palvelurakennusten korttelit: korttelin vasen yläkulma -> laji
var service_blocks := {}
## Valmiit palvelurakennukset: laji -> ServiceBuilding
var services := {}
## Alkuperäinen 16 px atlaskuva pikselianalyyseihin (törmäysmuodot, autot, ruohon väri)
var atlas_lo: Image
## Tarkka (2x) atlaskuva autojen kokoamiseen
var atlas_hd: Image
## Katulamppujen paikat maailmassa (yövalaistus, Atmosphere.gd)
var lamp_points := PackedVector2Array()


func _ready() -> void:
	if generate_on_ready:
		generate()


## Jos exportteja ei ole asetettu, etsitään lapsista nimillä tai luodaan puuttuvat.
func _resolve_nodes() -> void:
	if ground_layer == null:
		for n in ["WorldMap", "Ground"]:
			ground_layer = get_node_or_null(n) as TileMapLayer
			if ground_layer:
				break
	if ground_layer == null:
		for c in get_children():
			if c is TileMapLayer:
				ground_layer = c
				break
	if deco_layer == null:
		deco_layer = get_node_or_null("Deco") as TileMapLayer
	if deco_layer == null:
		deco_layer = TileMapLayer.new()
		deco_layer.name = "Deco"
		deco_layer.y_sort_enabled = true
		add_child(deco_layer)
	if entities == null:
		entities = get_node_or_null("Entities") as Node2D
	if entities == null:
		entities = Node2D.new()
		entities.name = "Entities"
		entities.y_sort_enabled = true
		add_child(entities)


func generate() -> void:
	_resolve_nodes()
	assert(ground_layer, "Ground Layer puuttuu: lisää TileMapLayer City-noodin lapseksi tai aseta export")
	atlas_src = ground_layer.tile_set.get_source(source_id) as TileSetAtlasSource
	assert(atlas_src, "TileSetissä ei ole atlas-lähdettä id:llä %d" % source_id)

	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = hash(seed_value)
	print("City seed: ", rng.seed)

	map_w = map_size.x
	map_h = map_size.y
	_use_hd_atlas()
	_fix_atlas()
	tile = atlas_tile_size
	stride = tile + atlas_separation

	_clear()
	if setup_tileset_physics:
		_setup_tileset()
	_setup_prop_y_sort()

	var xr := _road_ranges(map_w, true)
	var yr := _road_ranges(map_h)
	road_x = xr
	road_y = yr
	col_road.resize(map_w)
	col_road.fill(0)
	row_road.resize(map_h)
	row_road.fill(0)
	for r in xr:
		for x in range(r.x, r.y):
			col_road[x] = 1
	for r in yr:
		for y in range(r.x, r.y):
			row_road[y] = 1
	_build_lane_index()

	# Asekauppa aloituskorttelin viereen (seuraavan pystytien jälkeen)
	armory_block = Vector2i(-1, -1)
	if road_x.size() > 1 and not road_y.is_empty():
		armory_block = Vector2i(road_x[1].y, road_y[0].y)
	armory = null

	# Pelaajan koti aloituskorttelissa
	home_block = Vector2i(-1, -1)
	if not road_x.is_empty() and not road_y.is_empty():
		home_block = Vector2i(road_x[0].y, road_y[0].y)
	home = null
	home_door_cell = Vector2i(-1, -1)
	home_yard_cell = Vector2i(-1, -1)

	# Baari kodin eteläpuoliseen kortteliin (varalla asekaupan viereen)
	bar_block = Vector2i(-1, -1)
	if not road_x.is_empty() and road_y.size() > 1:
		bar_block = Vector2i(road_x[0].y, road_y[1].y)
	elif road_x.size() > 2 and not road_y.is_empty():
		bar_block = Vector2i(road_x[2].y, road_y[0].y)
	bar = null
	services.clear()
	_assign_service_blocks(xr, yr)

	_paint_ground()
	_paint_road_markings()
	for bx in _gaps(xr, map_w):
		for by in _gaps(yr, map_h):
			_fill_block(Rect2i(bx.x, by.x, bx.y - bx.x, by.y - by.x))

	_ensure_landmarks()
	_clear_frontages()
	_build_astar()
	_spawn_npcs()
	_spawn_cars()
	_spawn_parked_cars()
	_build_world_bounds()
	_build_roadworks()
	_place_player_and_car()
	_build_decor()


## Varjot, reunakivet, kuluma ja sävyt (CityDecor.gd) maakerroksen päälle.
func _build_decor() -> void:
	var old := ground_layer.get_node_or_null("CityDecor")
	if old:
		old.free()
	var decor: Node2D = (load("res://scripts/world/CityDecor.gd") as Script).new()
	ground_layer.add_child(decor)
	decor.setup(self)
	decor_node = decor


# ----------------------------------------------------------------------------
#  KARTAN RAKENNE
# ----------------------------------------------------------------------------
## Korjaa TileSetin atlaksen 16 px tiileiksi + 1 px väli ja luo kaikki tiilet.
func _fix_atlas() -> void:
	ground_layer.tile_set.tile_size = Vector2i(atlas_tile_size, atlas_tile_size)
	atlas_src.texture_region_size = Vector2i(atlas_tile_size, atlas_tile_size)
	atlas_src.separation = Vector2i(atlas_separation, atlas_separation)
	# Rakennetaan tiilet puhtaasti uudelleen: tallennetun scenen tiilet voivat olla
	# rikkinäisiä (esim. vanha 17 px ruudukko), jolloin osa tiilistä ei renderöidy.
	for i in range(atlas_src.get_tiles_count() - 1, -1, -1):
		atlas_src.remove_tile(atlas_src.get_tile_id(i))
	var grid := atlas_src.get_atlas_grid_size()
	for y in grid.y:
		for x in grid.x:
			var c := Vector2i(x, y)
			if not atlas_src.has_tile(c) and atlas_src.get_tile_at_coords(c) == Vector2i(-1, -1):
				atlas_src.create_tile(c)


## Vaihtaa atlaksen kuvan 2x-tarkkaan versioon. Kuva raportoi kokonsa alkuperäisenä
## (ImageTexture.set_size_override), joten ruudukko, alueet ja koordinaatit pysyvät
## ennallaan, mutta jokainen ruutu piirretään 32x32 pikselin tarkkuudella.
func _use_hd_atlas() -> void:
	var cur := atlas_src.texture
	if cur == null:
		return
	if cur.has_meta("atg_lo_image"):
		atlas_lo = cur.get_meta("atg_lo_image")
		atlas_hd = cur.get_meta("atg_hd_image") if cur.has_meta("atg_hd_image") else null
		atlas_src.use_texture_padding = false
		return
	atlas_lo = cur.get_image()
	if atlas_lo == null:
		return
	if atlas_lo.is_compressed():
		atlas_lo.decompress()
	atlas_lo.convert(Image.FORMAT_RGBA8)
	if not ResourceLoader.exists(ATLAS_HD_PATH):
		return
	var hd_src := load(ATLAS_HD_PATH) as Texture2D
	if hd_src == null:
		return
	var hd_img := hd_src.get_image()
	if hd_img == null:
		return
	if hd_img.is_compressed():
		hd_img.decompress()
	var hd := ImageTexture.create_from_image(hd_img)
	hd.set_size_override(Vector2i(cur.get_size()))
	hd.set_meta("atg_lo_image", atlas_lo)
	hd_img.convert(Image.FORMAT_RGBA8)
	atlas_hd = hd_img
	hd.set_meta("atg_hd_image", hd_img)
	# Godotin oma täyte kopioisi ruudut 16 px koordinaateilla; tilemap_hd.png:ssä
	# on jo 1 px täyte ruutujen ympärillä.
	atlas_src.use_texture_padding = false
	atlas_src.texture = hd


func _clear() -> void:
	ground_layer.clear()
	deco_layer.clear()
	if entities:
		for c in entities.get_children():
			c.queue_free()
	ped_spawns.clear()
	lamp_points.clear()
	_all_doors.clear()
	_landmark_lots.clear()
	_plain_blocks.clear()
	building_rects.clear()
	_prop_at.clear()
	solid.resize(map_w * map_h)
	solid.fill(0)


## Palauttaa tiet (alku, loppu-exclusive) yhdellä akselilla.
func _road_ranges(length: int, wide_first: bool = false) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var pos := rng.randi_range(block_min, block_max)
	var i := 0
	while true:
		var w := avenue_width if i % avenue_every == 0 else road_width
		if pos + w + block_min > length:
			break
		out.append(Vector2i(pos, pos + w))
		# Kodin kortteli (ensimmäisen ja toisen pystytien välissä) on leveä, jotta autotalli mahtuu
		if wide_first and i == 0:
			pos += w + rng.randi_range(maxi(block_min, 17), maxi(block_max, 20))
		else:
			pos += w + rng.randi_range(block_min, block_max)
		i += 1
	return out


## Tilat teiden välissä (alku, loppu-exclusive).
func _gaps(ranges: Array[Vector2i], length: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var prev := 0
	for r in ranges:
		if r.x - prev > 0:
			out.append(Vector2i(prev, r.x))
		prev = r.y
	if length - prev > 0:
		out.append(Vector2i(prev, length))
	return out


func _paint_ground() -> void:
	for y in map_h:
		for x in map_w:
			var is_road := col_road[x] == 1 or row_road[y] == 1
			_put_tile(ground_layer, Vector2i(x, y), ROAD if is_road else GRASS)


## Tiemerkinnät: keskiviivat ja suojatiet risteysten molemmin puolin.
func _paint_road_markings() -> void:
	crosswalk_cells.clear()
	for r in road_x:
		var cx := r.x + (r.y - r.x) / 2
		for y in map_h:
			if row_road[y] == 0:
				_put_tile(ground_layer, Vector2i(cx, y), ROAD_DASH_V)
	for r in road_y:
		var cy := r.x + (r.y - r.x) / 2
		for x in map_w:
			if col_road[x] == 0:
				_put_tile(ground_layer, Vector2i(x, cy), ROAD_DASH_H)
	for rx in road_x:
		for ry in road_y:
			# suojatie pystytien yli (vaakatien reunoilla)
			for y: int in [ry.x - 1, ry.y]:
				for x in range(rx.x, rx.y):
					var k := 0 if x == rx.x else (2 if x == rx.y - 1 else 1)
					if _in_bounds(Vector2i(x, y)):
						_put_tile(ground_layer, Vector2i(x, y), CROSS_V[k])
						crosswalk_cells[Vector2i(x, y)] = true
			# suojatie vaakatien yli (pystytien reunoilla)
			for x: int in [rx.x - 1, rx.y]:
				for y in range(ry.x, ry.y):
					var k := 0 if y == ry.x else (2 if y == ry.y - 1 else 1)
					if _in_bounds(Vector2i(x, y)):
						_put_tile(ground_layer, Vector2i(x, y), CROSS_H[k])
						crosswalk_cells[Vector2i(x, y)] = true


func _fill_block(block: Rect2i) -> void:
	_sidewalk_ring(block)
	_place_street_furniture(block)
	var inner := block.grow(-sidewalk_width)
	if inner.size.x < 3 or inner.size.y < 3:
		return
	var roll := rng.randf()
	var lot_fits := inner.size.x >= 4 and inner.size.y >= 4
	var is_start_block := start_parking_lot and not road_x.is_empty() and not road_y.is_empty() \
		and block.position == Vector2i(road_x[0].y, road_y[0].y)
	var is_armory_block := block.position == armory_block and inner.size.x >= 7 and inner.size.y >= 6
	var is_home_block := block.position == home_block and inner.size.x >= 7 and inner.size.y >= 6
	var is_bar_block := block.position == bar_block and inner.size.x >= 7 and inner.size.y >= 6
	if is_home_block:
		_make_home(inner)
		_paint_door_paths()
		_scatter_ring_props(block)
	elif is_start_block and lot_fits:
		_make_parking(inner)
	elif is_armory_block:
		_make_armory(inner)
		_paint_door_paths()
		_scatter_ring_props(block)
	elif is_bar_block:
		_make_bar(inner)
		_paint_door_paths()
		_scatter_ring_props(block)
	elif service_blocks.has(block.position) and inner.size.x >= 7 and inner.size.y >= 6:
		_make_service(str(service_blocks[block.position]), inner)
		_paint_door_paths()
		_scatter_ring_props(block)
	elif roll < park_chance:
		_make_park(inner)
	elif roll < park_chance + plaza_chance:
		_make_plaza(inner)
	elif roll < park_chance + plaza_chance + parking_chance and lot_fits:
		_make_parking(inner)
	else:
		if inner.size.x >= 7 and inner.size.y >= 6:
			_plain_blocks.append(block)
		_make_buildings(inner)
		_paint_door_paths()
		_scatter_ring_props(block)


## Jalkakäytävä: vain uloin rivi (tien vieressä) on keltaista, loput vihreää.
func _sidewalk_ring(block: Rect2i) -> void:
	for y in range(block.position.y, block.end.y):
		for x in range(block.position.x, block.end.x):
			var d := mini(
				mini(x - block.position.x, block.end.x - 1 - x),
				mini(y - block.position.y, block.end.y - 1 - y))
			if d < sidewalk_width:
				if d == 0:
					_put_tile(ground_layer, Vector2i(x, y), SIDEWALK)
				ped_spawns.append(Vector2i(x, y))


## Katukalusteet jalkakäytävän uloimmalle riville (kaikki neljä sivua):
## lamput/kilvet, puut, penkit/roskikset sekä liikennevalot kulmiin.
func _place_street_furniture(block: Rect2i) -> void:
	if sidewalk_width < 2:
		return
	var half := int(lamp_spacing * 0.5)
	var x0 := block.position.x
	var x1 := block.end.x - 1
	var y0 := block.position.y
	var y1 := block.end.y - 1
	# liikennevalot kulmiin. Itse kulmaruutu on suojatien sisäänkäynti jalankulkijoille, joten
	# valo asetetaan viereiseen ruutuun reunaa pitkin (sisäänpäin).
	for c: Vector2i in [Vector2i(x0, y0), Vector2i(x1, y0), Vector2i(x0, y1), Vector2i(x1, y1)]:
		if rng.randf() < 0.7:
			var inward_x := 1 if c.x == x0 else -1
			_place_prop(TRAFFIC_LIGHTS, c + Vector2i(inward_x, 0))
	# ylä- ja alareuna
	for y: int in [y0, y1]:
		var x := x0 + sidewalk_width
		while x < x1 + 1 - sidewalk_width:
			_place_lamp_or_sign(Vector2i(x, y))
			if x + half < x1 + 1 - sidewalk_width:
				_place_between(Vector2i(x + half, y))
			x += lamp_spacing
	# vasen ja oikea reuna
	for x: int in [x0, x1]:
		var y := y0 + sidewalk_width
		while y < y1 + 1 - sidewalk_width:
			_place_lamp_or_sign(Vector2i(x, y))
			if y + half < y1 + 1 - sidewalk_width:
				_place_between(Vector2i(x, y + half))
			y += lamp_spacing


func _place_lamp_or_sign(c: Vector2i) -> void:
	var is_lamp := rng.randf() >= 0.22
	var placed := _place_prop_at(LAMPS if is_lamp else SIGNS, c)
	if placed != Vector2i(-1, -1) and is_lamp:
		lamp_points.append(cell_to_world(placed) + Vector2(0.0, -14.0))
		_prop_at[placed]["lamp"] = true


## Lamppujen välissä: puu, penkki/roskis tai pieni kaluste.
func _place_between(c: Vector2i) -> void:
	var r := rng.randf()
	if r < 0.55:
		_place_prop(STREET_TREES, c)
	elif r < 0.85:
		_place_prop(SMALL_PROPS, c)
	else:
		_place_prop(TALL_PROPS, c)


## Kalusteita vihreälle sisäreunalle (taloja vasten).
func _scatter_ring_props(block: Rect2i) -> void:
	var x0 := block.position.x + 1
	var x1 := block.end.x - 2
	var y0 := block.position.y + 1
	var y1 := block.end.y - 2
	var cells: Array[Vector2i] = []
	for x in range(x0, x1 + 1):
		cells.append(Vector2i(x, y0))
		cells.append(Vector2i(x, y1))
	for y in range(y0 + 1, y1):
		cells.append(Vector2i(x0, y))
		cells.append(Vector2i(x1, y))
	for c in cells:
		if rng.randf() > 0.13:
			continue
		if _path_cells.has(c) or ground_layer.get_cell_atlas_coords(c) != GRASS:
			continue
		_place_prop(SMALL_PROPS if rng.randf() < 0.8 else TALL_PROPS, c)


## base = kohteen alin tiili; ylempi osa tulee sen yläpuolelle.
func _place_prop(list: Array, base: Vector2i) -> bool:
	return _place_prop_at(list, base) != Vector2i(-1, -1)


## Kuten _place_prop, mutta palauttaa todellisen alimman ruudun (tai (-1, -1)).
## Kaluste ei koskaan peitä tieruutuja: jos korkea kaluste ulottuisi tielle
## (korttelin yläreuna), se siirretään ruudun alemmas jalkakäytävälle.
func _place_prop_at(list: Array, base: Vector2i) -> Vector2i:
	if list.is_empty():
		return Vector2i(-1, -1)
	var st: Dictionary = list[rng.randi() % list.size()]
	var s: Vector2i = st.s
	var b := base
	for attempt in 2:
		var origin := b - Vector2i(0, s.y - 1)
		if _stamp_touches_road(origin, s):
			b += Vector2i.DOWN
			continue
		if not _stamp_free(origin, s):
			return Vector2i(-1, -1)
		_stamp(deco_layer, st, origin)
		_set_solid(b)
		var cells: Array[Vector2i] = []
		for dy in s.y:
			for dx in s.x:
				cells.append(origin + Vector2i(dx, dy))
		var rec := {"cells": cells, "base": b, "lamp": false}
		for c in cells:
			_prop_at[c] = rec
		return b
	return Vector2i(-1, -1)


func _stamp_touches_road(origin: Vector2i, size: Vector2i) -> bool:
	for dy in size.y:
		for dx in size.x:
			if _is_road(origin + Vector2i(dx, dy)):
				return true
	return false


## Poistaa kalusteen, jonka jokin ruutu on c (jos on).
func _remove_prop_at(c: Vector2i) -> void:
	if not _prop_at.has(c):
		return
	var rec: Dictionary = _prop_at[c]
	for pc: Vector2i in rec.cells:
		deco_layer.erase_cell(pc)
		_prop_at.erase(pc)
	var b: Vector2i = rec.base
	if _in_bounds(b):
		solid[b.y * map_w + b.x] = 0
	if rec.lamp:
		var lp := cell_to_world(b) + Vector2(0.0, -14.0)
		var idx := lamp_points.find(lp)
		if idx >= 0:
			lamp_points.remove_at(idx)


## Auto ajoi kalusteen päälle: kaluste irtoaa ja lentää (FlyingProp.gd).
## Puut ja istutuslaatikot eivät irtoa. Palauttaa true, jos jotain irtosi.
const FLYING_PROP := preload("res://scripts/world/FlyingProp.gd")
var decor_node: Node = null

func knock_prop(c: Vector2i, hit_vel: Vector2) -> bool:
	if not _prop_at.has(c):
		return false
	var rec: Dictionary = _prop_at[c]
	var cells: Array = rec.cells
	var tiles: Array = []
	var metal := false
	for pc: Vector2i in cells:
		var a := deco_layer.get_cell_atlas_coords(pc)
		if a == Vector2i(-1, -1):
			continue
		if _atlas_in(TREES, a) or _atlas_in(STREET_TREES, a):
			return false
		if _atlas_in(LAMPS, a) or _atlas_in(SIGNS, a) or _atlas_in(TRAFFIC_LIGHTS, a):
			metal = true
		tiles.append([cell_to_world(pc), _tile_tex(a)])
	if tiles.is_empty():
		return false
	var base: Vector2i = rec.base
	var ground := cell_to_world(base) + Vector2(0.0, 6.0)
	var tall := cells.size() > 1
	_remove_prop_at(c)
	if decor_node and decor_node.has_method("remove_prop_shadows"):
		decor_node.remove_prop_shadows(cells)
	var fp := FLYING_PROP.new()
	fp.city = self
	fp.metal = metal
	entities.add_child(fp)
	fp.setup(tiles, ground, hit_vel, tall)
	return true


func _atlas_in(list: Array, a: Vector2i) -> bool:
	for st: Dictionary in list:
		var o: Vector2i = st.o
		var s: Vector2i = st.s
		if a.x >= o.x and a.y >= o.y and a.x < o.x + s.x and a.y < o.y + s.y:
			return true
	return false


func _clear_rect_props(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_remove_prop_at(Vector2i(x, y))


## Rakennusten edustat vapaiksi: oven edestä tielle asti 3 ruudun levyinen käytävä,
## erikoisrakennusten (koti, baari, palvelut...) koko etupiha sekä sivut oven korkeudelta.
func _clear_frontages() -> void:
	for d in _all_doors:
		var depth := 0
		var c := d + Vector2i.DOWN
		while depth < 8 and _in_bounds(c) and not _is_road(c):
			depth += 1
			c += Vector2i.DOWN
		_clear_rect_props(Rect2i(d.x - 1, d.y + 1, 3, depth))
	for lot in _landmark_lots:
		var depth := 0
		var c := Vector2i(lot.position.x + lot.size.x / 2, lot.end.y)
		while depth < 8 and _in_bounds(c) and not _is_road(c):
			depth += 1
			c += Vector2i.DOWN
		_clear_rect_props(Rect2i(lot.position.x - 2, lot.end.y, lot.size.x + 4, depth))
		_clear_rect_props(Rect2i(lot.position.x - 2, lot.end.y - 3, 2, 3))
		_clear_rect_props(Rect2i(lot.end.x, lot.end.y - 3, 2, 3))


func _make_park(inner: Rect2i) -> void:
	_patch(ground_layer, inner, PARK)
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			ped_spawns.append(Vector2i(x, y))
	for i in int(inner.get_area() / 14.0):
		_try_place_tree(inner)
	for i in int(inner.get_area() / 30.0):
		_try_place_small(inner)


## Parkkipaikka: asfalttia, parkkiruutuja ylä- ja alareunassa (jos tilaa) ja
## ajokaista välissä. Autot luodaan myöhemmin _spawn_parked_cars():ssa.
@warning_ignore("integer_division")
func _make_parking(inner: Rect2i) -> void:
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			_put_tile(ground_layer, Vector2i(x, y), ROAD)
	var cols := inner.size.x / 2
	var x0 := inner.position.x + (inner.size.x - cols * 2) / 2
	var rows: Array[int] = [inner.position.y]
	if inner.size.y >= 7:
		rows.append(inner.end.y - 2)
	for ri in rows.size():
		for i in cols:
			var origin := Vector2i(x0 + i * 2, rows[ri])
			_stamp(ground_layer, PARKING_STALL, origin)
			parking_slots.append({
				"cell": origin,
				"facing": Vector2i.DOWN if ri == 0 else Vector2i.UP,
			})
	# P-merkki ajokaistan keskelle
	var lane_top := inner.position.y + 2
	var lane_bottom := inner.end.y - 2 if rows.size() == 2 else inner.end.y
	if lane_bottom > lane_top:
		var sign_cell := Vector2i(inner.position.x + inner.size.x / 2, lane_top + (lane_bottom - lane_top - 1) / 2)
		_put_tile(ground_layer, sign_cell, PARKING_SIGN)


@warning_ignore("integer_division")
func _make_plaza(inner: Rect2i) -> void:
	_patch(ground_layer, inner, PLAZA)
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			ped_spawns.append(Vector2i(x, y))
	if inner.size.x >= 8 and inner.size.y >= 8:
		var pond := Rect2i(inner.position + Vector2i(inner.size.x / 2, inner.size.y / 2) - Vector2i(2, 2), Vector2i(4, 4))
		_patch(ground_layer, pond, WATER)
		_mark_solid(pond)
	for i in int(inner.get_area() / 24.0):
		_try_place_small(inner)


## Sijoittaa satunnaisen pienen kalusteen (penkki, roskis, pensas...) alueen sisälle.
func _try_place_small(area: Rect2i) -> void:
	var a := area.grow(-1)
	if a.size.x < 1 or a.size.y < 2:
		return
	var c := Vector2i(rng.randi_range(a.position.x, a.end.x - 1), rng.randi_range(a.position.y + 1, a.end.y - 1))
	_place_prop(SMALL_PROPS if rng.randf() < 0.8 else TALL_PROPS, c)


func _make_buildings(inner: Rect2i) -> void:
	door_cells.clear()
	_path_cells.clear()
	var lots: Array[Rect2i] = []
	_split(inner, lots)
	for lot in lots:
		var roof: Dictionary = ROOFS[rng.randi() % ROOFS.size()]
		# Talon alimmat rivit ovat julkisivu (seinä + ikkunat + ovi), yläosa on katto.
		# Omakotitalossa julkisivu on 2 riviä; kerrostalossa 3-5 kerrosta ja tasakatto.
		var tall := lot.size.y >= 7 and lot.size.x >= 4 and rng.randf() < APARTMENT_CHANCE
		var face_rows := clampi(lot.size.y - 3, 3, 5) if tall else 2
		var facade := lot.size.y >= face_rows + 2 and lot.size.x >= 3
		var roof_rect := Rect2i(lot.position, Vector2i(lot.size.x, lot.size.y - face_rows)) if facade else lot
		_patch(ground_layer, roof_rect, roof)
		_mark_solid(lot)
		building_rects.append({"lot": lot, "fy": roof_rect.end.y if facade else -1, "landmark": false, "flat": tall and facade})
		if facade:
			if face_rows == 2:
				_build_facade(lot, roof_rect.end.y)
			else:
				_build_tall_facade(lot, roof_rect.end.y, face_rows)
			_add_roof_props(roof_rect)


## Asekauppa: yksi kiinteä rakennus (7-9 leveä), jonka katto ja kyltti piirtää Armory.gd.
## Ovi on keskellä; E oven edessä vie sisätilaan.
@warning_ignore("integer_division")
func _make_armory(inner: Rect2i) -> void:
	var b := _make_landmark(inner)
	armory = ARMORY_SCRIPT.new()
	entities.add_child(armory)
	armory.setup(ground_layer.tile_set, source_id, b.roof, b.door_center)


## Baari: sama rakennusrunko kuin asekaupassa, oma katto, kyltti ja sisätila (Bar.gd).
func _make_bar(inner: Rect2i) -> void:
	# Baarin pihalle varataan tilaa terassille: rakennus kapeammaksi, jos kortteli on leveä
	const YARD_W := 6   # terassi 5 ruutua + 1 ruudun väli seinään
	var house_inner := inner
	if inner.size.x >= 7 + YARD_W:
		house_inner = Rect2i(inner.position.x + YARD_W, inner.position.y, inner.size.x - YARD_W, inner.size.y)
	var b := _make_landmark(house_inner)
	var lot: Rect2i = b.lot
	var yard := Rect2i()
	var free_l := lot.position.x - inner.position.x
	var free_r := inner.end.x - lot.end.x
	var free_top := lot.position.y - inner.position.y
	if free_l >= YARD_W and free_l >= free_r:
		yard = Rect2i(inner.position.x, lot.end.y - 3, free_l - 1, 3)
	elif free_r >= YARD_W:
		yard = Rect2i(lot.end.x + 1, lot.end.y - 3, free_r - 1, 3)
	elif free_top >= 3:
		# kapea kortteli: terassi talon taakse (takapiha)
		yard = Rect2i(lot.position.x, lot.position.y - 3, lot.size.x, 3)
	if yard.size.x > 0:
		_clear_rect_props(yard)
		for y in range(yard.position.y, yard.end.y):
			for x in range(yard.position.x, yard.end.x):
				deco_layer.erase_cell(Vector2i(x, y))
	bar = BAR_SCRIPT.new()
	bar.city = self
	bar.roof_rect = b.roof
	bar.yard_px = _cells_px(yard) if yard.size.x > 0 else Rect2()
	entities.add_child(bar)
	bar.setup(ground_layer.tile_set, source_id, b.roof, b.door_center)


## Palvelurakennus: sama rakennusrunko kuin asekaupassa, katon ja kyltin piirtää ServiceBuilding.gd.
func _make_service(kind: String, inner: Rect2i) -> void:
	if kind == "market":
		_make_market(inner)
		return
	var b := _make_landmark(inner)
	if kind == "manor":
		# kartanon julkisivu piirretään itse (ManorExterior): ikkuna- ja ovilaatat pois
		var lot: Rect2i = b.lot
		for dy in [lot.end.y - 2, lot.end.y - 1]:
			for x in range(lot.position.x, lot.end.x):
				deco_layer.erase_cell(Vector2i(x, int(dy)))
	var sb = SERVICE_SCRIPT.new()
	entities.add_child(sb)
	sb.setup(kind, b.roof, b.door_center)
	services[kind] = sb


## Tori: kiveys ja kaksi kojua (Market.gd): autokauppias (Auto-Make) ja vaatekauppias.
func _make_market(inner: Rect2i) -> void:
	_patch(ground_layer, inner, PLAZA)
	var mk = MARKET_SCRIPT.new()
	entities.add_child(mk)
	mk.setup(inner, _cells_px(inner))
	for r: Rect2i in mk.stall_cells:
		_mark_solid(r)
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			var c := Vector2i(x, y)
			if not _is_solid(c):
				ped_spawns.append(c)
	services["market"] = mk


## Valitsee palvelurakennuksille korttelit ympäri kaupunkia: jokainen uusi palvelu
## sijoitetaan kortteliin, joka on mahdollisimman kaukana jo valituista (koti, asekauppa,
## baari ja aiemmat palvelut). Kolmen kaukaisimman välillä arvotaan, jotta kartta vaihtelee.
func _assign_service_blocks(xr: Array[Vector2i], yr: Array[Vector2i]) -> void:
	service_blocks.clear()
	var reserved := [home_block, armory_block, bar_block]
	# Ehdokkaat: ei kartan reunakortteleita (niihin ei ole tietä ulkoreunalta ja ne jäävät
	# kartan laidalle) ja korkeintaan SERVICE_RADIUS ruudun päässä kodista. Jos tilaa ei
	# riitä, rajoja löysennetään, joten jokainen palvelu saa aina paikan.
	var home_v := Vector2(home_block) if home_block != Vector2i(-1, -1) else Vector2(map_w, map_h) * 0.5
	var cands: Array[Vector2i] = []
	for pass_i in 3:
		cands.clear()
		for bx in _gaps(xr, map_w):
			for by in _gaps(yr, map_h):
				var pos := Vector2i(bx.x, by.x)
				if reserved.has(pos):
					continue
				if bx.y - bx.x < 7 + 2 * sidewalk_width or by.y - by.x < 6 + 2 * sidewalk_width:
					continue
				var edge := bx.x == 0 or by.x == 0 or bx.y >= map_w or by.y >= map_h
				if pass_i < 2 and edge:
					continue
				if pass_i == 0 and Vector2(pos).distance_to(home_v) > SERVICE_RADIUS:
					continue
				cands.append(pos)
		if cands.size() >= SERVICE_ORDER.size():
			break
	var anchors: Array[Vector2] = []
	for r: Vector2i in reserved:
		if r != Vector2i(-1, -1):
			anchors.append(Vector2(r))
	var order: Array = SERVICE_ORDER.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	for kind in order:
		if cands.is_empty():
			break
		var scored: Array = []
		for c in cands:
			var best := 1.0e12
			for a in anchors:
				best = minf(best, Vector2(c).distance_squared_to(a))
			scored.append([best, c])
		scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var pick: Vector2i = scored[rng.randi_range(0, mini(2, scored.size() - 1))][1]
		service_blocks[pick] = kind
		anchors.append(Vector2(pick))
		cands.erase(pick)


## Pelaajan koti: sama rakennusrunko kuin asekaupassa, oma katto ja sisätila (Home.gd).
func _make_home(inner: Rect2i) -> void:
	# Talo vasemmalle, autotalli sen oikealle puolelle (1 ruudun väli)
	var garage := Rect2i()
	var house_inner := inner
	if inner.size.x >= 7 + GARAGE_W + 1:
		house_inner = Rect2i(inner.position, Vector2i(inner.size.x - GARAGE_W - 1, inner.size.y))
	var b := _make_landmark(house_inner)
	home_door_cell = b.door_cell
	var lot: Rect2i = b.lot
	var drive := Rect2i()
	if house_inner != inner:
		garage = Rect2i(lot.end.x + 1, lot.end.y - 3, GARAGE_W, 3)
		drive = _make_garage(garage, inner)
		home_yard_cell = Vector2i(garage.position.x + 1, garage.end.y)
	else:
		# Ei tilaa tallille: auto talon sivulle pihalle (se puoli, jolla on enemmän tilaa)
		var left_room := lot.position.x - inner.position.x
		var right_room := inner.end.x - lot.end.x
		var yard_x := lot.end.x + 1 if right_room >= left_room else lot.position.x - 2
		home_yard_cell = Vector2i(yard_x, lot.end.y - 3)
	home = HOME_SCRIPT.new()
	entities.add_child(home)
	home.setup(ground_layer.tile_set, source_id, b.roof, b.door_center)
	home.add_details(_cells_px(lot), _cells_px(garage) if garage.size.x > 0 else Rect2(), _cells_px(drive) if drive.size.x > 0 else Rect2())


## Kodin autotalli: kiinteä 3x3-rakennus ja asfaltoitu ajoluiska tielle asti.
## Palauttaa ajoluiskan ruudut.
func _make_garage(garage: Rect2i, inner: Rect2i) -> Rect2i:
	for y in range(garage.position.y, garage.end.y):
		for x in range(garage.position.x, garage.end.x):
			var c := Vector2i(x, y)
			_remove_prop_at(c)
			deco_layer.erase_cell(c)
			_put_tile(ground_layer, c, WALL)
	_mark_solid(garage)
	building_rects.append({"lot": garage, "fy": -1, "landmark": true})
	# Ajoluiska tallin ovelta korttelin reunaan (jalkakäytävän yli)
	var drive := Rect2i(garage.position.x, garage.end.y, garage.size.x, inner.end.y + sidewalk_width - garage.end.y)
	_clear_rect_props(drive)
	for y in range(drive.position.y, drive.end.y):
		for x in range(drive.position.x, drive.end.x):
			var c := Vector2i(x, y)
			if _in_bounds(c) and not _is_road(c):
				_put_tile(ground_layer, c, ROAD)
				_path_cells[c] = true
	return drive


## Ruutualue maailman pikseleinä.
func _cells_px(r: Rect2i) -> Rect2:
	var half := Vector2(tile, tile) * 0.5
	var tl := ground_layer.to_global(ground_layer.map_to_local(r.position)) - half
	return Rect2(tl, Vector2(r.size) * float(tile))


## Kiinteä erikoisrakennus (7-9 leveä): seinät, ovi keskellä, katto. Palauttaa
## {"roof": Rect2, "door_center": Vector2, "door_cell": Vector2i, "lot": Rect2i}.
func _make_landmark(inner: Rect2i) -> Dictionary:
	door_cells.clear()
	_path_cells.clear()
	var w := mini(inner.size.x, 9)
	if w % 2 == 0:
		w -= 1  # pariton leveys -> ovi tasan keskellä, symmetrinen julkisivu
	var h := mini(inner.size.y, 7)
	var lot := Rect2i(inner.position.x + (inner.size.x - w) / 2, inner.end.y - h, w, h)
	var fy := lot.end.y - 2
	var roof_rect := Rect2i(lot.position, Vector2i(w, h - 2))
	_patch(ground_layer, roof_rect, ROOFS[0])
	_mark_solid(lot)

	var door_dx := w / 2
	var ws: Array = WINDOW_SETS[0]
	for dx in w:
		_put_tile(ground_layer, Vector2i(lot.position.x + dx, fy), WALL)
		_put_tile(ground_layer, Vector2i(lot.position.x + dx, fy + 1), WALL)
		var upper := Vector2i(lot.position.x + dx, fy)
		var lower := Vector2i(lot.position.x + dx, fy + 1)
		if dx == door_dx:
			_put_tile(deco_layer, upper, ws[0])
			_put_tile(deco_layer, lower, DOORS[0])
		elif dx > 0 and dx < w - 1 and absi(dx - door_dx) % 2 == 1:
			_put_tile(deco_layer, upper, ws[0])
			_put_tile(deco_layer, lower, ws[1])
	var door_cell := Vector2i(lot.position.x + door_dx, fy + 1)
	door_cells.append(door_cell)
	_all_doors.append(door_cell)
	_landmark_lots.append(lot)
	building_rects.append({"lot": lot, "fy": fy, "landmark": true})

	# Katon pikselisuorakulmio maailmassa
	var half := Vector2(tile, tile) * 0.5
	var tl := ground_layer.to_global(ground_layer.map_to_local(roof_rect.position)) - half
	var roof_px := Rect2(tl, Vector2(roof_rect.size) * float(tile))

	return {
		"roof": roof_px,
		"door_center": ground_layer.to_global(ground_layer.map_to_local(door_cell)),
		"door_cell": door_cell,
		"lot": lot,
	}


## Julkisivu: seinä, ikkunat kahdessa rivissä, ovi ja joskus kaupan näyteikkuna.
func _build_facade(lot: Rect2i, fy: int) -> void:
	var w := lot.size.x
	var ox := lot.position.x
	var ws: Array = WINDOW_SETS[rng.randi() % WINDOW_SETS.size()]
	var door_dx := rng.randi_range(1, w - 2)
	for dx in w:
		_put_tile(ground_layer, Vector2i(ox + dx, fy), WALL)
		_put_tile(ground_layer, Vector2i(ox + dx, fy + 1), WALL)

	# Kaupan näyteikkuna (3 leveä) oven vierelle, jos tilaa
	var shop_dx := -1
	if w >= 6 and rng.randf() < 0.3:
		var left_ok := door_dx >= 3
		var right_ok := w - 1 - door_dx >= 3
		if left_ok and (not right_ok or rng.randf() < 0.5):
			shop_dx = rng.randi_range(0, door_dx - 3)
		elif right_ok:
			shop_dx = rng.randi_range(door_dx + 1, w - 3)
	if shop_dx >= 0:
		_stamp(deco_layer, SHOPFRONT, Vector2i(ox + shop_dx, fy))

	for dx in w:
		if shop_dx >= 0 and dx >= shop_dx and dx < shop_dx + 3:
			continue
		var upper := Vector2i(ox + dx, fy)
		var lower := Vector2i(ox + dx, fy + 1)
		if dx == door_dx:
			_put_tile(deco_layer, upper, ws[0])
			_put_tile(deco_layer, lower, DOORS[rng.randi() % DOORS.size()])
		elif dx > 0 and dx < w - 1 and absi(dx - door_dx) % 2 == 1:
			_put_tile(deco_layer, upper, ws[0])
			_put_tile(deco_layer, lower, ws[1])
	door_cells.append(Vector2i(ox + door_dx, fy + 1))
	_all_doors.append(Vector2i(ox + door_dx, fy + 1))


## Varmistus: koti, asekauppa, baari ja jokainen palvelurakennus (SERVICE_ORDER) on
## AINA kartalla. Jos jokin jäi puuttumaan, se rakennetaan tavallisen talokorttelin
## paikalle (lähimpänä kotia). Lopuksi lista rakennuksista tulostuu Output-paneeliin.
func _ensure_landmarks() -> void:
	var missing: Array[String] = []
	if home == null:
		missing.append("home")
	if armory == null:
		missing.append("armory")
	if bar == null:
		missing.append("bar")
	for k: String in SERVICE_ORDER:
		if not services.has(k):
			missing.append(k)
	if not missing.is_empty():
		push_warning("CityGenerator: puuttui %s, rakennetaan varapaikalle." % ", ".join(missing))
		var ref := Vector2(home_block) if home_block != Vector2i(-1, -1) else Vector2(map_w, map_h) * 0.5
		_plain_blocks.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return Vector2(a.position).distance_squared_to(ref) < Vector2(b.position).distance_squared_to(ref))
		for k: String in missing:
			var placed := false
			while not _plain_blocks.is_empty():
				var block: Rect2i = _plain_blocks.pop_front()
				var inner := block.grow(-sidewalk_width)
				if inner.size.x < 7 or inner.size.y < 6:
					continue
				_wipe_inner(inner)
				match k:
					"home":
						home_block = block.position
						_make_home(inner)
					"armory":
						armory_block = block.position
						_make_armory(inner)
					"bar":
						bar_block = block.position
						_make_bar(inner)
					_:
						service_blocks[block.position] = k
						_make_service(k, inner)
				_paint_door_paths()
				placed = true
				break
			if not placed:
				push_error("CityGenerator: rakennusta '%s' ei saatu kartalle (ei vapaata korttelia)." % k)
	var built: PackedStringArray = []
	if home:
		built.append("koti")
	if armory:
		built.append("asekauppa")
	if bar:
		built.append("baari")
	for k: String in SERVICE_ORDER:
		if services.has(k):
			built.append(k)
	print("Kaupungin rakennukset (%d/%d): %s" % [built.size(), SERVICE_ORDER.size() + 3, ", ".join(built)])


## Tyhjentää korttelin sisäosan (talot, katot, ikkunat, ovet, kalusteet) uutta rakennusta varten.
func _wipe_inner(inner: Rect2i) -> void:
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			var c := Vector2i(x, y)
			if not _in_bounds(c):
				continue
			_put_tile(ground_layer, c, GRASS)
			deco_layer.erase_cell(c)
			solid[c.y * map_w + c.x] = 0
			_prop_at.erase(c)
	var keep: Array[Vector2i] = []
	for d in _all_doors:
		if not inner.has_point(d):
			keep.append(d)
	_all_doors = keep
	var kept: Array[Dictionary] = []
	for b in building_rects:
		if not inner.intersects(b.lot):
			kept.append(b)
	building_rects = kept


## Kerrostalon julkisivu: rows kerrosta ikkunoita, alimmassa ovi ja alaikkunat.
func _build_tall_facade(lot: Rect2i, fy: int, rows: int) -> void:
	var w := lot.size.x
	var ox := lot.position.x
	var ws: Array = WINDOW_SETS[rng.randi() % WINDOW_SETS.size()]
	var door_dx := rng.randi_range(1, w - 2)
	var bottom := fy + rows - 1
	for r in rows:
		for dx in w:
			var c := Vector2i(ox + dx, fy + r)
			_put_tile(ground_layer, c, WALL)
			var window_col := dx > 0 and dx < w - 1 and (absi(dx - door_dx) % 2 == 1 or dx == door_dx)
			if r == rows - 1:
				if dx == door_dx:
					_put_tile(deco_layer, c, DOORS[rng.randi() % DOORS.size()])
				elif window_col:
					_put_tile(deco_layer, c, ws[1])
			elif window_col:
				_put_tile(deco_layer, c, ws[0])
	door_cells.append(Vector2i(ox + door_dx, bottom))
	_all_doors.append(Vector2i(ox + door_dx, bottom))


## Kaksiruutuiset kalusteet (puut, lamput, kyltit, kojut) järjestetään piirrossa niiden
## alimman ruudun mukaan. Muuten yläosa (puun latvus, lampun pää) järjestyy omalla
## rivillään ja sen takaa kulkeva hahmo tai auto piirtyy sen päälle ("leikkaa" kuvan).
func _setup_prop_y_sort() -> void:
	for list: Array in [TREES, STREET_TREES, LAMPS, SIGNS, TALL_PROPS, TRAFFIC_LIGHTS]:
		for st: Dictionary in list:
			var o: Vector2i = st.o
			var sz: Vector2i = st.s
			for dy in sz.y:
				for dx in sz.x:
					var td := _tile_data(o + Vector2i(dx, dy))
					if td:
						td.y_sort_origin = (sz.y - 1 - dy) * tile


## Ilmastointilaitteita katolle.
func _add_roof_props(roof_rect: Rect2i) -> void:
	var a := roof_rect.grow(-1)
	if a.size.x < 1 or a.size.y < 1 or rng.randf() < 0.35:
		return
	for i in rng.randi_range(1, 2):
		var c := Vector2i(rng.randi_range(a.position.x, a.end.x - 1), rng.randi_range(a.position.y, a.end.y - 1))
		if deco_layer.get_cell_source_id(c) == -1:
			_put_tile(deco_layer, c, ROOF_PROPS[rng.randi() % ROOF_PROPS.size()])


## Keltainen ovipolku oven edestä jalkakäytävälle (vain tämä ja uloin rivi ovat keltaisia).
func _paint_door_paths() -> void:
	for d in door_cells:
		var c := d + Vector2i.DOWN
		for i in 8:
			if not _in_bounds(c) or _is_solid(c) or _is_road(c):
				break
			if ground_layer.get_cell_atlas_coords(c) == SIDEWALK:
				break
			_put_tile(ground_layer, c, SIDEWALK)
			_path_cells[c] = true
			c += Vector2i.DOWN


## Jakaa alueen rekursiivisesti tonteiksi, väliin jää 1 tiilen kuja.
func _split(rect: Rect2i, out: Array[Rect2i]) -> void:
	var w := rect.size.x
	var h := rect.size.y
	var can_x := w >= lot_min * 2 + 1
	var can_y := h >= lot_min * 2 + 1
	var too_big := w > lot_max or h > lot_max
	if (not can_x and not can_y) or (not too_big and rng.randf() < 0.4):
		out.append(rect)
		return
	var split_x := (w >= h) if (can_x and can_y) else can_x
	if split_x:
		var cut := rng.randi_range(lot_min, w - lot_min - 1)
		_split(Rect2i(rect.position, Vector2i(cut, h)), out)
		_split(Rect2i(rect.position + Vector2i(cut + 1, 0), Vector2i(w - cut - 1, h)), out)
	else:
		var cut := rng.randi_range(lot_min, h - lot_min - 1)
		_split(Rect2i(rect.position, Vector2i(w, cut)), out)
		_split(Rect2i(rect.position + Vector2i(0, cut + 1), Vector2i(w, h - cut - 1)), out)


func _try_place_tree(area: Rect2i) -> void:
	if TREES.is_empty():
		return
	var t: Dictionary = TREES[rng.randi() % TREES.size()]
	var s: Vector2i = t.s
	var min_p := area.position + Vector2i.ONE
	var max_p := area.end - Vector2i.ONE - s
	if max_p.x < min_p.x or max_p.y < min_p.y:
		return
	var origin := Vector2i(rng.randi_range(min_p.x, max_p.x), rng.randi_range(min_p.y, max_p.y))
	if not _stamp_free(origin, s):
		return
	_stamp(deco_layer, t, origin)
	for i in s.x:
		_set_solid(origin + Vector2i(i, s.y - 1))  # vain runko estää


# ----------------------------------------------------------------------------
#  TILE-APUFUNKTIOT
# ----------------------------------------------------------------------------
func _put_tile(layer: TileMapLayer, cell: Vector2i, atlas_coords: Vector2i) -> void:
	layer.set_cell(cell, source_id, atlas_coords)


## 9-slice: kulmat, reunat ja keskitiili. Valinnaiset "mx"/"my" valitsevat keskitiilet.
func _patch(layer: TileMapLayer, rect: Rect2i, patch: Dictionary) -> void:
	var o: Vector2i = patch.o
	var s: Vector2i = patch.s
	var mx: Array = patch.get("mx", [])
	var my: int = patch.get("my", -1)
	var my_list: Array = [] if my < 0 else [my]
	for ry in rect.size.y:
		var ay := _slice(ry, rect.size.y, s.y, my_list)
		for rx in rect.size.x:
			var ax := _slice(rx, rect.size.x, s.x, mx)
			_put_tile(layer, rect.position + Vector2i(rx, ry), o + Vector2i(ax, ay))


func _slice(i: int, count: int, size: int, mids: Array) -> int:
	if size == 1 or i == 0:
		return 0
	if i == count - 1:
		return size - 1
	if not mids.is_empty():
		return mids[rng.randi() % mids.size()]
	return 1 if size > 2 else 0


## Asettaa monitiilisen kohteen (puu, lamppu) sellaisenaan.
func _stamp(layer: TileMapLayer, st: Dictionary, origin: Vector2i) -> void:
	var o: Vector2i = st.o
	var s: Vector2i = st.s
	for dy in s.y:
		for dx in s.x:
			_put_tile(layer, origin + Vector2i(dx, dy), o + Vector2i(dx, dy))


func _stamp_free(origin: Vector2i, size: Vector2i) -> bool:
	for dy in size.y:
		for dx in size.x:
			var c := origin + Vector2i(dx, dy)
			if not _in_bounds(c) or _is_solid(c) or deco_layer.get_cell_source_id(c) != -1:
				return false
	return true


func _patch_tiles(patch: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var o: Vector2i = patch.o
	var s: Vector2i = patch.s
	for y in s.y:
		for x in s.x:
			out.append(o + Vector2i(x, y))
	return out


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < map_w and c.y < map_h


func _is_solid(c: Vector2i) -> bool:
	return solid[c.y * map_w + c.x] == 1


func _set_solid(c: Vector2i) -> void:
	if _in_bounds(c):
		solid[c.y * map_w + c.x] = 1


func _mark_solid(rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_set_solid(Vector2i(x, y))


func _is_road(c: Vector2i) -> bool:
	return _in_bounds(c) and (col_road[c.x] == 1 or row_road[c.y] == 1)


# ----------------------------------------------------------------------------
#  TILESET: TÖRMÄYKSET + NAVIGAATIO (ajonaikaisesti)
# ----------------------------------------------------------------------------
func _setup_tileset() -> void:
	var ts := ground_layer.tile_set
	deco_layer.tile_set = ts  # sama TileSet molemmille
	if ts.get_physics_layers_count() == 0:
		ts.add_physics_layer()
	if ts.get_navigation_layers_count() == 0:
		ts.add_navigation_layer()

	var h := tile * 0.5
	var sq := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	var nav := NavigationPolygon.new()
	nav.vertices = sq
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))

	# Törmäysmuodot: talot, vesi ja seinät koko ruutu; kalusteet, lamput ja puut vain
	# siltä osin kuin kuvassa on jalustaa/runkoa (ennen koko 16x16-ruutu, eli ohuen
	# lampun tai puun ympärillä oli näkymätön seinä).
	var atlas_img: Image = atlas_lo
	if atlas_img == null and atlas_src.texture:
		atlas_img = atlas_src.texture.get_image()
	if atlas_img and atlas_img.is_compressed():
		atlas_img.decompress()
	var footprints := _solid_footprints(atlas_img, sq)
	for c: Vector2i in footprints:
		var td := _tile_data(c)
		if td and td.get_collision_polygons_count(0) == 0:
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, footprints[c])
	for c in _walkable_tiles():
		var td := _tile_data(c)
		if td:
			td.set_navigation_polygon(0, nav)


func _tile_data(c: Vector2i) -> TileData:
	if not Rect2i(Vector2i.ZERO, atlas_src.get_atlas_grid_size()).has_point(c):
		push_warning("Atlas-koordinaatti %s on atlaksen ulkopuolella, ohitetaan." % c)
		return null
	if not atlas_src.has_tile(c):
		# Onko tiili jo osa isompaa tiiltä, tai ei tilaa uudelle?
		if atlas_src.get_tile_at_coords(c) != Vector2i(-1, -1) \
				or not atlas_src.has_room_for_tile(c, Vector2i.ONE, 1, Vector2i.ZERO, 1):
			push_warning("Tiilelle %s ei voi luoda tile-dataa (päällekkäinen tiili tai ei tilaa), ohitetaan." % c)
			return null
		atlas_src.create_tile(c)
	return atlas_src.get_tile_data(c, 0)


## Ruutu -> törmäyspolygoni. Kalusteille jalanjälki lasketaan kuvan pikseleistä.
func _solid_footprints(img: Image, full: PackedVector2Array) -> Dictionary:
	var out := {}
	for r in ROOFS:
		for c in _patch_tiles(r):
			out[c] = full
	for c in _patch_tiles(WATER):
		out[c] = full
	out[WALL] = full
	# [ryhmä, kuinka monta alinta pikseliriviä otetaan huomioon, pienin koko]
	var groups := [[LAMPS, 4, 4.0], [SIGNS, 4, 4.0], [TRAFFIC_LIGHTS, 4, 4.0],
		[TREES, 5, 6.0], [STREET_TREES, 7, 8.0], [SMALL_PROPS, 9, 6.0], [TALL_PROPS, 9, 8.0]]
	for g: Array in groups:
		for st in g[0]:
			var o: Vector2i = st.o
			var s: Vector2i = st.s
			for i in s.x:
				var c := o + Vector2i(i, s.y - 1)  # alin rivi
				if not out.has(c):
					out[c] = _footprint(img, c, int(g[1]), float(g[2]), full)
	return out


## Ruudun alimpien `rows` pikselirivin näkyvien pikselien rajaama laatikko (ruudun
## keskipisteen koordinaateissa). Jos kuvaa ei saada, palautetaan koko ruutu.
func _footprint(img: Image, c: Vector2i, rows: int, min_size: float, full: PackedVector2Array) -> PackedVector2Array:
	if img == null:
		return full
	var ox := atlas_src.margins.x + c.x * stride
	var oy := atlas_src.margins.y + c.y * stride
	var x0 := tile
	var x1 := -1
	var y0 := tile
	for y in range(tile - rows, tile):
		for x in tile:
			if ox + x >= img.get_width() or oy + y >= img.get_height():
				continue
			if img.get_pixel(ox + x, oy + y).a > 0.5:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
	if x1 < 0:
		return full
	var h := tile * 0.5
	var left := float(x0) - h
	var right := float(x1 + 1) - h
	var top := float(y0) - h
	var bottom := h
	# vähimmäiskoko (ohut tolppa ei saa olla liian ohut, ettei sen läpi pääse)
	if right - left < min_size:
		var mid := (left + right) * 0.5
		left = mid - min_size * 0.5
		right = mid + min_size * 0.5
	if bottom - top < 3.0:
		top = bottom - 3.0
	return PackedVector2Array([Vector2(left, top), Vector2(right, top), Vector2(right, bottom), Vector2(left, bottom)])


func _solid_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in ROOFS:
		out.append_array(_patch_tiles(r))
	out.append_array(_patch_tiles(WATER))
	out.append(WALL)
	for group in [TREES, LAMPS, STREET_TREES, SIGNS, TRAFFIC_LIGHTS, SMALL_PROPS, TALL_PROPS]:
		for st in group:
			var o: Vector2i = st.o
			var s: Vector2i = st.s
			for i in s.x:
				out.append(o + Vector2i(i, s.y - 1))  # alin rivi
	return out


func _walkable_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = [GRASS, ROAD, SIDEWALK, ROAD_DASH_V, ROAD_DASH_H, PARKING_SIGN]
	out.append_array(_patch_tiles(PARKING_STALL))
	out.append_array(CROSS_V)
	out.append_array(CROSS_H)
	out.append_array(_patch_tiles(PARK))
	out.append_array(_patch_tiles(PLAZA))
	return out


# ----------------------------------------------------------------------------
#  POLUNETSINTÄ (jalankulkijat) JA AUTOJEN REITIT
# ----------------------------------------------------------------------------
## Suojatien sisäänkäynti (kulmaruutu tien vieressä) ja sen takana oleva käytävä pidetään
## vapaina kalusteista, ettei suojatie jää käyttökelvottomaksi.
func _clear_crosswalk_entries() -> void:
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var done := {}
	for cw: Vector2i in crosswalk_cells:
		for d in dirs:
			var e: Vector2i = cw + d
			if done.has(e) or not _in_bounds(e) or _is_road(e):
				continue
			done[e] = true
			# sisäänpäin johtavat naapurit (tien puoleiset naapurit ovat tietä)
			var inward: Array[Vector2i] = []
			for d2 in dirs:
				if _in_bounds(e + d2) and not _is_road(e + d2):
					inward.append(d2)
			_remove_prop_at(e)
			# pystysuuntainen sisäänpäin-naapuri ja vino ruutu vapaiksi (liikennevalo on vaakasuunnassa)
			for d2 in inward:
				if d2.y != 0:
					_remove_prop_at(e + d2)
					for d3 in inward:
						if d3.x != 0:
							_remove_prop_at(e + d2 + d3)


func _build_astar() -> void:
	_clear_crosswalk_entries()
	astar.region = Rect2i(0, 0, map_w, map_h)
	astar.cell_size = Vector2(tile, tile)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	for y in map_h:
		for x in map_w:
			var c := Vector2i(x, y)
			if _is_solid(c):
				astar.set_point_solid(c)
			elif _is_road(c):
				astar.set_point_weight_scale(c, 4.0)  # suosi jalkakäytäviä
	# Jalankulkijat: tie on seinä, paitsi suojatiet (siellä tie ylitetään)
	ped_astar.region = Rect2i(0, 0, map_w, map_h)
	ped_astar.cell_size = Vector2(tile, tile)
	ped_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	ped_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	ped_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	ped_astar.update()
	for y in map_h:
		for x in map_w:
			var c := Vector2i(x, y)
			if not ped_walkable(c):
				ped_astar.set_point_solid(c)


## Saako tavallinen jalankulkija seistä ruudussa? Tie kelpaa vain suojatieruutuna.
func ped_walkable(c: Vector2i) -> bool:
	if not _in_bounds(c) or _is_solid(c):
		return false
	return not _is_road(c) or crosswalk_cells.has(c)


## Lähin ruutu, jossa jalankulkija saa olla (esim. kun hahmo on joutunut keskelle tietä).
func _nearest_ped_cell(from: Vector2i) -> Vector2i:
	for r in range(1, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := from + Vector2i(dx, dy)
				if ped_walkable(c):
					return c
	return from


## Jalankulkijan satunnainen reitti. Tien yli mennään vain suojatietä pitkin.
func ped_path(from: Vector2i) -> Array[Vector2i]:
	# Hahmo on tiellä muualla kuin suojatiellä (kuski ulos autosta, pakeneva, kolarin jälkeen):
	# kävellään ensin lähimmälle sallitulle ruudulle (tässä saa ylittää tietä).
	if not ped_walkable(from):
		var out := _nearest_ped_cell(from)
		if out != from:
			var back := astar.get_id_path(from, out)
			if back.size() > 1:
				back.remove_at(0)
				return back
		return []
	for i in 12:
		var to := from + Vector2i(rng.randi_range(-30, 30), rng.randi_range(-30, 30))
		if not ped_walkable(to):
			continue
		var p := ped_astar.get_id_path(from, to)
		if p.size() > 1:
			p.remove_at(0)
			return p
	return []


## Onko suojatieruudun c tiellä liikkuvia autoja lähellä? Jalankulkija odottaa reunalla.
func crosswalk_busy(c: Vector2i) -> bool:
	if not _in_bounds(c) or not _is_road(c):
		return false
	var vertical_road := col_road[c.x] == 1 and row_road[c.y] == 0
	var horizontal_road := row_road[c.y] == 1 and col_road[c.x] == 0
	if not vertical_road and not horizontal_road:
		return false
	var here := cell_to_world(c)
	var cars: Array[Node2D] = []
	if entities:
		for m in entities.get_children():
			if m is Mover and m.is_car and not m.dead and not m.wrecked and m.cur_speed > 8.0:
				cars.append(m)
	for v in get_tree().get_nodes_in_group("player_vehicles"):
		if is_instance_valid(v) and v is CharacterBody2D and (v as CharacterBody2D).velocity.length() > 8.0:
			cars.append(v)
	for car in cars:
		var d: Vector2 = car.global_position - here
		var cc := world_to_cell(car.global_position)
		var on_same_road := false
		var along := 0.0
		if vertical_road:
			on_same_road = _in_bounds(cc) and col_road[cc.x] == 1 and _rx_of[cc.x] == _rx_of[c.x]
			along = absf(d.y)
		else:
			on_same_road = _in_bounds(cc) and row_road[cc.y] == 1 and _ry_of[cc.y] == _ry_of[c.y]
			along = absf(d.x)
		if on_same_road and along < 56.0:
			return true
	return false


## Auto jatkaa suoraan, kääntyy vain risteyksissä.
func car_next_cell(cell: Vector2i, dir: Vector2i) -> Vector2i:
	if not _in_bounds(cell):
		return cell
	var at_junction := col_road[cell.x] == 1 and row_road[cell.y] == 1
	if not at_junction:
		# Suunta poikittain tiehen nähden (esim. pysäytyksen jälkeen): käännytään tien
		# suuntaiseksi. Muuten auto heiluisi leveän tien kaistojen välillä.
		var along_ok := (dir.x != 0 and row_road[cell.y] == 1) or (dir.y != 0 and col_road[cell.x] == 1)
		if not along_ok:
			var axis: Array[Vector2i] = []
			if col_road[cell.x] == 1:
				axis = [Vector2i.UP, Vector2i.DOWN]
			else:
				axis = [Vector2i.LEFT, Vector2i.RIGHT]
			if rng.randf() < 0.5:
				axis.reverse()
			for d in axis:
				if _is_road(cell + d):
					return cell + d
			return cell
	var ahead := cell + dir
	if not at_junction:
		if _is_road(ahead):
			return ahead
		return cell - dir if _is_road(cell - dir) else cell
	var options: Array[Vector2i] = []
	for d: Vector2i in [dir, Vector2i(-dir.y, dir.x), Vector2i(dir.y, -dir.x)]:
		if _is_road(cell + d):
			options.append(d)
	if options.is_empty():
		return cell - dir
	if _is_road(ahead) and rng.randf() < 0.65:
		return ahead
	return cell + options[rng.randi() % options.size()]


# ----------------------------------------------------------------------------
#  NPC:T JA AUTOT
# ----------------------------------------------------------------------------
func _tile_tex(c: Vector2i) -> AtlasTexture:
	if _tex_cache.has(c):
		return _tex_cache[c]
	var t := AtlasTexture.new()
	t.atlas = atlas_src.texture
	t.region = Rect2(Vector2(atlas_src.margins) + Vector2(c * stride), Vector2(tile, tile))
	_tex_cache[c] = t
	return t


## NPC-kuva: base_row = hahmon ensimmäinen rivi, step 0 = seisoo, 1/2 = kävely
func npc_tex(base_row: int, dir: Vector2i, step: int) -> Texture2D:
	var col := 1  # alas
	if dir == Vector2i.LEFT:
		col = 0
	elif dir == Vector2i.UP:
		col = 2
	elif dir == Vector2i.RIGHT:
		col = 3
	# tarkat 32 px kuvat (piirretään 16 px kokoon); vanhat tilemapin ruudut sarakkeesta NPC_FIRST_COL
	return CHAR_SPRITES.npc(col, base_row + step)


func car_texture(color: String, dir: Vector2i) -> Texture2D:
	var key := "down"
	if dir == Vector2i.UP:
		key = "up"
	elif dir == Vector2i.LEFT:
		key = "left"
	elif dir == Vector2i.RIGHT:
		key = "right"
	return _car_tex[color][key]


## Rakentaa autokuvat suoraan tilemapista: liittää tiilet yhteen ilman atlaksen
## 1 px väliä (siksi kuvassa ei ole halkaisevaa saumaa) ja rajaa tyhjät reunat pois.
func _build_car_textures() -> void:
	_car_tex.clear()
	var atlas_img: Image = (atlas_lo.duplicate() as Image) if atlas_lo else atlas_src.texture.get_image()
	if atlas_img == null:
		return
	if atlas_img.is_compressed():
		atlas_img.decompress()
	atlas_img.convert(Image.FORMAT_RGBA8)
	for color in CAR_SETS:
		_car_tex[color] = {}
		for d in CAR_SETS[color]:
			var b: Array = CAR_SETS[color][d]
			var cols: int = b[1] - b[0] + 1
			var rows: int = b[3] - b[2] + 1
			var img := Image.create(cols * tile, rows * tile, false, Image.FORMAT_RGBA8)
			for r in rows:
				for c in cols:
					var src := Rect2i((b[0] + c) * stride, (b[2] + r) * stride, tile, tile)
					img.blit_rect(atlas_img, src, Vector2i(c * tile, r * tile))
			var used := img.get_used_rect()
			img = img.get_region(used)
			if atlas_hd:
				# sama auto tilemap_hd:stä (2x), piirretään 1x-kokoisena
				var hd := Image.create(cols * tile * 2, rows * tile * 2, false, Image.FORMAT_RGBA8)
				for r in rows:
					for c in cols:
						var src2 := Rect2i((b[0] + c) * stride * 2, (b[2] + r) * stride * 2, tile * 2, tile * 2)
						hd.blit_rect(atlas_hd, src2, Vector2i(c * tile * 2, r * tile * 2))
				hd = hd.get_region(Rect2i(used.position * 2, used.size * 2))
				_car_tex[color][d] = HD_TEX.make(hd, img)
			else:
				_car_tex[color][d] = ImageTexture.create_from_image(img)


## Julkiset apufunktiot poliisille ym.
func world_to_cell(p: Vector2) -> Vector2i:
	return ground_layer.local_to_map(ground_layer.to_local(p))


func cell_to_world(c: Vector2i) -> Vector2:
	return ground_layer.to_global(ground_layer.map_to_local(c))


func is_walkable(c: Vector2i) -> bool:
	return _in_bounds(c) and not _is_solid(c)


func is_road(c: Vector2i) -> bool:
	return _is_road(c)


func _cell_center(c: Vector2i) -> Vector2:
	return entities.to_local(ground_layer.to_global(ground_layer.map_to_local(c)))


func _spawn_npcs() -> void:
	if not entities or ped_spawns.is_empty():
		return
	for i in npc_count:
		var c := ped_spawns[rng.randi() % ped_spawns.size()]
		if _is_solid(c):
			continue
		var m := _make_ped(c)
		entities.add_child(m)
		m.refresh()


func _make_ped(c: Vector2i) -> Mover:
	var m := Mover.new()
	m.city = self
	m.cell = c
	m.speed = rng.randf_range(25.0, 45.0)
	m.base_row = (rng.randi() % NPC_TYPES) * 3
	m.position = _cell_center(c)
	m.add_to_group("shootable")
	var spr := Sprite2D.new()
	spr.offset = Vector2(0, -4)
	m.visual = spr
	m.add_child(spr)
	m.wait = rng.randf_range(0.0, 3.0)
	return m


func _spawn_cars() -> void:
	if not entities:
		return
	_build_car_textures()
	if _car_tex.is_empty():
		push_warning("Autojen kuvia ei saatu tilemapista, autoja ei luoda.")
		return
	var colors: Array = _car_tex.keys()
	var taken := {}
	for i in car_count:
		# Auto omalle kaistalleen (oikeanpuoleinen liikenne), ei risteykseen eikä toisen päälle
		var c := Vector2i.ZERO
		var d := Vector2i.DOWN
		var found := false
		for t in 60:
			c = Vector2i(rng.randi() % map_w, rng.randi() % map_h)
			if not _is_road(c) or is_junction(c) or is_edge(c):
				continue
			if col_road[c.x] == 1:
				d = Vector2i.UP if rng.randf() < 0.5 else Vector2i.DOWN
			else:
				d = Vector2i.LEFT if rng.randf() < 0.5 else Vector2i.RIGHT
			var lanes := traffic_lanes(traffic_road(c, d), d)
			if lanes.is_empty():
				continue
			c = set_lane(c, d, lanes[rng.randi() % lanes.size()])
			var ok := true
			for k in range(-2, 3):
				var cc := c + d * k
				if taken.has(cc) or is_junction(cc) or not _is_road(cc):
					ok = false
					break
			if ok:
				found = true
				break
		if not found:
			continue
		taken[c] = true

		var m := Mover.new()
		m.city = self
		m.is_car = true
		m.car_color = colors[rng.randi() % colors.size()]
		m.cell = c
		m.dir = d
		m.plan_cell = c
		m.plan_dir = d
		m.speed = rng.randf_range(60.0, 90.0)
		m.cur_speed = m.speed * 0.5
		m.position = _cell_center(c)
		m.add_to_group("car_targets")
		var spr := Sprite2D.new()
		m.visual = spr
		m.add_child(spr)
		entities.add_child(m)
		m.refresh()
		m.add_child(CAR_FX_SCRIPT.new())  # pyörivät renkaat + pakokaasu


## Luo parkkiruutuihin autoja. Autot ovat varastettavissa (Car2D.is_npc_owned):
## ensimmäinen sisään nouseminen nostaa etsintäkuulutuksen.
func _spawn_parked_cars() -> void:
	if not entities or parking_slots.is_empty():
		return
	var half := Vector2(tile, tile) * 0.5
	for slot in parking_slots:
		if rng.randf() > parking_fill_chance:
			continue
		var t: Dictionary = PARKED_CAR_TYPES[rng.randi() % PARKED_CAR_TYPES.size()]
		var car = CAR_SCENE.instantiate()  # Car2D.gd
		car.speed = t.speed
		car.is_npc_owned = true
		var spr := car.get_node("AnimatedSprite2D") as AnimatedSprite2D
		var color: String = t.color
		if color != "" and _car_tex.has(color):
			spr.sprite_frames = _make_car_frames(color)
		spr.animation = &"car_down" if slot.facing == Vector2i.DOWN else &"car_up"
		# parkkiruutu on 2x2 ruutua: auto ruudun keskelle
		var origin: Vector2i = slot.cell
		var world := ground_layer.to_global(ground_layer.map_to_local(origin) + half)
		car.position = entities.to_local(world)
		entities.add_child(car)


## Rakentaa auton animaatiot (yksi kuva / suunta) tilemapista rakennetuista autokuvista.
func _make_car_frames(color: String) -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	var names := {"car_up": Vector2i.UP, "car_down": Vector2i.DOWN, "car_left": Vector2i.LEFT, "car_right": Vector2i.RIGHT}
	for n: String in names:
		sf.add_animation(n)
		sf.set_animation_loop(n, false)
		sf.add_frame(n, car_texture(color, names[n]))
	return sf


## Kartan reunat globaalissa koordinaatistossa (ruutujen ulkoreunat).
func world_rect() -> Rect2:
	var half := Vector2(tile, tile) * 0.5
	var tl := ground_layer.to_global(ground_layer.map_to_local(Vector2i.ZERO) - half)
	var br := ground_layer.to_global(ground_layer.map_to_local(Vector2i(map_w - 1, map_h - 1)) + half)
	return Rect2(tl, br - tl).abs()


## Näkymättömät seinät kartan ympärille (pelaaja ja auto eivät pääse tyhjään)
## sekä kameran rajat, jotta tyhjää aluetta ei koskaan näy.
## Kartan reunan työmaavyöhyke (ruutuja): tiet päättyvät tietyömaahan, jonka läpi ei pääse.
const EDGE_WORKS := 2

## Onko ruutu kartan reunan työmaavyöhykkeellä? Liikenne kääntyy ympäri ennen sitä.
func is_edge(c: Vector2i) -> bool:
	return c.x < EDGE_WORKS or c.y < EDGE_WORKS or c.x >= map_w - EDGE_WORKS or c.y >= map_h - EDGE_WORKS


## Tietyömaat kaikkien teiden päihin kartan reunoilla: puomit, kartiot, kaivuri,
## hiekkakasa ja TIETYÖ-kyltti. Kiinteä este, jotta kartalta ei pääse pois.
func _build_roadworks() -> void:
	var old := get_node_or_null("RoadWorks")
	if old:
		old.free()
	var view := RoadWorks.new()
	view.name = "RoadWorks"
	add_child(view)
	var body := StaticBody2D.new()
	view.add_child(body)
	var half := Vector2(tile, tile) * 0.5
	var zones: Array = []
	for rx: Vector2i in road_x:
		for top: bool in [true, false]:
			var y0 := 0 if top else map_h - EDGE_WORKS
			var a := cell_to_world(Vector2i(rx.x, y0)) - half
			var b := cell_to_world(Vector2i(rx.y - 1, y0 + EDGE_WORKS - 1)) + half
			zones.append([Rect2(a, b - a), Vector2.DOWN if top else Vector2.UP])
	for ry: Vector2i in road_y:
		for left: bool in [true, false]:
			var x0 := 0 if left else map_w - EDGE_WORKS
			var a2 := cell_to_world(Vector2i(x0, ry.x)) - half
			var b2 := cell_to_world(Vector2i(x0 + EDGE_WORKS - 1, ry.y - 1)) + half
			zones.append([Rect2(a2, b2 - a2), Vector2.RIGHT if left else Vector2.LEFT])
	for z: Array in zones:
		var r: Rect2 = z[0]
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = r.size
		cs.shape = shape
		body.add_child(cs)
		cs.global_position = r.get_center()
	view.zones = zones
	view.queue_redraw()


func _build_world_bounds() -> void:
	var old := get_node_or_null("WorldBounds")
	if old:
		old.free()
	var r := world_rect()
	var body := StaticBody2D.new()
	body.name = "WorldBounds"
	add_child(body)
	var t := 256.0  # seinän paksuus
	var sides := [
		Rect2(r.position.x - t, r.position.y - t, r.size.x + 2.0 * t, t),   # ylä
		Rect2(r.position.x - t, r.end.y, r.size.x + 2.0 * t, t),            # ala
		Rect2(r.position.x - t, r.position.y, t, r.size.y),                 # vasen
		Rect2(r.end.x, r.position.y, t, r.size.y),                          # oikea
	]
	for s: Rect2 in sides:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = s.size
		cs.shape = shape
		cs.global_position = s.get_center()
		body.add_child(cs)

	var level := get_parent()
	var cam := level.get_node_or_null("Camera2D") as Camera2D if level else null
	if cam:
		cam.limit_left = int(floor(r.position.x))
		cam.limit_top = int(floor(r.position.y))
		cam.limit_right = int(ceil(r.end.x))
		cam.limit_bottom = int(ceil(r.end.y))


## Siirtää pelaajan ja pelaajan auton ensimmäisen risteyksen viereen.
@warning_ignore("integer_division")
func _place_player_and_car() -> void:
	if road_x.is_empty() or road_y.is_empty():
		return
	var level := get_parent()
	if level == null:
		return
	var rx := road_x[0]
	var ry := road_y[0]
	var car_cell := Vector2i(rx.y - 1, ry.y - 1)
	var player_cell := Vector2i(rx.y + 1, ry.y + 1)
	var pistol_cell := Vector2i(rx.y - 1, ry.y + 2)
	var has_home := home != null and home_door_cell.x >= 0

	# Koti: taksi talon sivulle pihalle
	var taxi_frames: SpriteFrames = null
	if has_home:
		if home_yard_cell.x >= 0:
			car_cell = home_yard_cell
		pistol_cell = Vector2i(home_door_cell.x - 2, home_door_cell.y + 1)
		if _car_tex.has("yellow"):
			taxi_frames = _make_car_frames("yellow")

	var player := level.get_node_or_null("Player") as Node2D
	if player:
		var col := player.get_node_or_null("CollisionShape2D") as Node2D
		var off := col.position if col else Vector2.ZERO
		if has_home:
			# Poistuttaessa/pidätyksen jälkeen pelaaja palaa kodin oven eteen;
			# pelin alussa hän syntyy kodin sisälle.
			player.global_position = home.door_px + Vector2(0.0, 28.0) - off
			home.call_deferred("start_inside")
		else:
			player.global_position = ground_layer.to_global(ground_layer.map_to_local(player_cell)) - off
		player_start_global = player.global_position
	var car := level.get_node_or_null("Car") as Node2D
	if car:
		car.global_position = ground_layer.to_global(ground_layer.map_to_local(car_cell))
		if taxi_frames:
			# Aloitusauto on taksi (keltainen)
			var spr := car.get_node("AnimatedSprite2D") as AnimatedSprite2D
			spr.sprite_frames = taxi_frames
			car.set("is_taxi", true)
			car.set("display_name", "Taksi")
			spr.animation = &"car_down"
	# Ei aloituspistoolia: pistooli ostetaan asekaupasta (kenttään jäänyt solmu poistetaan)
	var pistol := level.get_node_or_null("Pistol") as Node2D
	pistol_start_global = ground_layer.to_global(ground_layer.map_to_local(pistol_cell))
	if pistol:
		pistol.queue_free()
	var cam := level.get_node_or_null("Camera2D") as Camera2D
	if cam and player:
		cam.global_position = player.global_position


## Liikuttaa NPC:tä (A*-reitti) tai autoa (tieverkko) ruudusta ruutuun.
# ----------------------------------------------------------------------------
#  LIIKENNE: KAISTAT, RISTEYKSET JA ESTEET
#  Oikeanpuoleinen liikenne: kumpikin ajosuunta pysyy omalla puolellaan keskiviivaa.
#  Risteykseen ajetaan vain varauksella (ristikkäiset reitit eivät mene päällekkäin),
#  eikä risteykseen ajeta, jos ulosajossa ei ole tilaa (risteystä ei tukita).
#  Esteet (autot, jalankulkijat, pelaaja) kerätään kerran ruudussa ruutukohtaisiin lokeroihin.
# ----------------------------------------------------------------------------
const NO_KEY := Vector2i(-1, -1)
var _rx_of := PackedInt32Array()   # x -> road_x-indeksi (-1 = ei pystytietä)
var _ry_of := PackedInt32Array()   # y -> road_y-indeksi
var _jlocks := {}                  # risteys -> [{car, cells, entry, first, t}]
var _jwait := {}                   # risteys -> {car: [odotus alkoi, tulosuunta, viimeksi nähty]}
var _obs := {}                     # ruutu -> [[solmu, Rect2, nopeus], ...]
var _obs_frame := -1
var _g0 := Vector2.ZERO            # ruudun (0,0) vasen yläkulma maailmassa


func _build_lane_index() -> void:
	_rx_of.resize(map_w)
	_rx_of.fill(-1)
	for i in road_x.size():
		for x in range(road_x[i].x, road_x[i].y):
			_rx_of[x] = i
	_ry_of.resize(map_h)
	_ry_of.fill(-1)
	for i in road_y.size():
		for y in range(road_y[i].x, road_y[i].y):
			_ry_of[y] = i
	_jlocks.clear()
	_jwait.clear()


func is_junction(c: Vector2i) -> bool:
	return _in_bounds(c) and col_road[c.x] == 1 and row_road[c.y] == 1


func junction_key(c: Vector2i) -> Vector2i:
	if not is_junction(c):
		return NO_KEY
	return Vector2i(_rx_of[c.x], _ry_of[c.y])


func _junction_rect(key: Vector2i) -> Rect2i:
	var rx: Vector2i = road_x[key.x]
	var ry: Vector2i = road_y[key.y]
	return Rect2i(rx.x, ry.x, rx.y - rx.x, ry.y - ry.x)


## Tie, jota pitkin ruudussa c ajetaan suuntaan d: (alku, loppu-exclusive), tai NO_KEY.
func traffic_road(c: Vector2i, d: Vector2i) -> Vector2i:
	if not _in_bounds(c):
		return NO_KEY
	if d.y != 0:
		var i := _rx_of[c.x]
		return road_x[i] if i >= 0 else NO_KEY
	var j := _ry_of[c.y]
	return road_y[j] if j >= 0 else NO_KEY


## Tien r ajokaistat suuntaan d (poikittaiskoordinaatit), reunakaista ensin.
## Oikeanpuoleinen liikenne: alas ja vasemmalle ajetaan pienempien koordinaattien puolella.
func traffic_lanes(r: Vector2i, d: Vector2i) -> Array[int]:
	var out: Array[int] = []
	if r == NO_KEY:
		return out
	var c := r.x + (r.y - r.x) / 2   # keskiviiva
	if d == Vector2i.UP or d == Vector2i.RIGHT:
		for k in range(r.y - 1, c, -1):
			out.append(k)
	else:
		for k in range(r.x, c):
			out.append(k)
	return out


## Ruudun kaista (poikittaiskoordinaatti) ajosuunnassa d.
static func lane_coord(c: Vector2i, d: Vector2i) -> int:
	return c.x if d.y != 0 else c.y


static func set_lane(c: Vector2i, d: Vector2i, lane: int) -> Vector2i:
	return Vector2i(lane, c.y) if d.y != 0 else Vector2i(c.x, lane)


## Reitti risteyksen läpi ruudusta cell (risteyksen edessä) suuntaan d.
## Arpoo suoraan / oikealle / vasemmalle. Palauttaa {"cells": [...risteysruudut, ulosajoruutu], "dir": uusi suunta}
## tai {} jos risteyksestä ei pääse mihinkään (kartan reuna).
func traffic_junction_plan(cell: Vector2i, d: Vector2i) -> Dictionary:
	var key := junction_key(cell + d)
	if key == NO_KEY:
		return {}
	var j := _junction_rect(key)
	var right := Vector2i(-d.y, d.x)
	var left := Vector2i(d.y, -d.x)
	var opts: Array = []
	var weights: Array[float] = []
	for e: Vector2i in [d, right, left]:
		var cells := _junction_path(cell, d, e, key, j)
		if cells.is_empty():
			continue
		opts.append([cells, e])
		weights.append(0.55 if e == d else (0.25 if e == right else 0.2))
	if opts.is_empty():
		return {}
	var total := 0.0
	for w in weights:
		total += w
	var pick := rng.randf() * total
	for i in opts.size():
		pick -= weights[i]
		if pick <= 0.0 or i == opts.size() - 1:
			return {"cells": opts[i][0], "dir": opts[i][1]}
	return {}


## Ruudut risteyksen läpi: oikealle käännytään reunakaistalle, vasemmalle sisäkaistalle,
## suoraan ajetaan samalla kaistalla.
func _junction_path(cell: Vector2i, d: Vector2i, e: Vector2i, key: Vector2i, j: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var p := cell + d
	if e != d:
		var cross: Vector2i = road_y[key.y] if e.x != 0 else road_x[key.x]
		var lanes := traffic_lanes(cross, e)
		if lanes.is_empty():
			return out
		var t: int = lanes[0] if e == Vector2i(-d.y, d.x) else lanes[lanes.size() - 1]
		while j.has_point(p) and lane_coord(p, e) != t:
			out.append(p)
			p += d
		if not j.has_point(p):
			out.clear()
			return out
		while j.has_point(p):
			out.append(p)
			p += e
	else:
		while j.has_point(p):
			out.append(p)
			p += d
	if not _in_bounds(p) or not _is_road(p) or is_junction(p):
		out.clear()
		return out
	out.append(p)
	return out


## Yrittää varata risteyksen. cells = auton reitin risteysruudut, entry = tulosuunta.
## Samaa kaistaa perässä tuleva saa ajaa edellisen perässä, mutta ei loputtomasti,
## jos risteävästä suunnasta joku on odottanut kauan.
func traffic_try_enter(car: Object, key: Vector2i, cells: Array[Vector2i], entry: Vector2i) -> bool:
	if cells.is_empty():
		return false
	var now := Time.get_ticks_msec()
	var holders: Array = _jlocks.get(key, [])
	for i in range(holders.size() - 1, -1, -1):
		var h: Dictionary = holders[i]
		var hc = h["car"]
		if not is_instance_valid(hc) or Game.flag(hc, "wrecked") or now - int(h["t"]) > 9000:
			holders.remove_at(i)
	_jlocks[key] = holders
	var waits: Dictionary = _jwait.get(key, {})
	for w in waits.keys():
		if not is_instance_valid(w) or now - int(waits[w][2]) > 600:
			waits.erase(w)
	_jwait[key] = waits
	var since: int = int(waits[car][0]) if waits.has(car) else now
	var ok := true
	var following := false
	for h: Dictionary in holders:
		if h["car"] == car:
			return true
		if h["entry"] == entry and h["first"] == cells[0]:
			following = true
			continue
		for c in cells:
			if h["cells"].has(c):
				ok = false
				break
		if not ok:
			break
	if ok and following:
		for w in waits.keys():
			if w != car and waits[w][1] != entry and now - int(waits[w][0]) > 2500 and int(waits[w][0]) < since:
				ok = false
				break
	if not ok:
		waits[car] = [since, entry, now]
		return false
	waits.erase(car)
	var cs := {}
	for c in cells:
		cs[c] = true
	holders.append({"car": car, "cells": cs, "entry": entry, "first": cells[0], "t": now})
	return true


## Oikealla kaistalla pysyvä reitin jatko (partioautot): {"cells", "faces", "dir"} tai {}.
## Väärältä kaistalta siirrytään ensin vinosti lähimmälle oman ajosuunnan kaistalle,
## risteyksessä käytetään samaa reitinvalintaa kuin liikenteellä, umpikujassa U-käännös.
func lane_route(c: Vector2i, d: Vector2i) -> Dictionary:
	if not _in_bounds(c) or d == Vector2i.ZERO:
		return {}
	if not is_junction(c):
		var lanes := traffic_lanes(traffic_road(c, d), d)
		var cur := lane_coord(c, d)
		if not lanes.is_empty() and not lanes.has(cur):
			var best: int = lanes[0]
			for l: int in lanes:
				if absi(l - cur) < absi(best - cur):
					best = l
			var sgn := signi(best - cur)
			var lat := Vector2i(sgn, 0) if d.y != 0 else Vector2i(0, sgn)
			for p: Vector2i in [c + d + lat, c + lat]:
				if _is_road(p) and not is_junction(p):
					return {"cells": [p], "faces": [d], "dir": d}
	var ahead := c + d
	if not _is_road(ahead) or is_edge(ahead):
		return traffic_uturn(c, d)
	if is_junction(ahead) and not is_junction(c):
		var plan := traffic_junction_plan(c, d)
		if plan.is_empty():
			return traffic_uturn(c, d)
		var faces: Array = []
		for _jc: Vector2i in plan["cells"]:
			faces.append(Vector2i.ZERO)
		return {"cells": (plan["cells"] as Array).duplicate(), "faces": faces, "dir": plan["dir"]}
	return {"cells": [ahead], "faces": [Vector2i.ZERO], "dir": d}


## U-käännös ruudusta c (ajosuunta d) vastakkaisen suunnan kaistalle: {"cells", "faces", "dir"} tai {}.
func traffic_uturn(c: Vector2i, d: Vector2i) -> Dictionary:
	var opp := traffic_lanes(traffic_road(c, d), -d)
	if opp.is_empty():
		return {}
	var now := lane_coord(c, d)
	var tl: int = opp[opp.size() - 1]
	var sgn := signi(tl - now)
	if sgn == 0:
		return {"cells": [c - d], "faces": [-d], "dir": -d} if _is_road(c - d) else {}
	var lat := Vector2i(sgn, 0) if d.y != 0 else Vector2i(0, sgn)
	var cells: Array = []
	var faces: Array = []
	var p := c + d + lat
	if not _is_road(p) or is_junction(p) or is_junction(c + d) or is_edge(p):
		p = c + lat
	if not _is_road(p):
		return {}
	cells.append(p)
	faces.append(lat)
	var guard := 0
	while lane_coord(p, d) != tl and guard < 8:
		guard += 1
		p += lat
		if not _is_road(p):
			return {}
		cells.append(p)
		faces.append(lat)
	faces[faces.size() - 1] = -d
	return {"cells": cells, "faces": faces, "dir": -d}


func traffic_leave(car: Object, key: Vector2i) -> void:
	var holders: Array = _jlocks.get(key, [])
	for i in range(holders.size() - 1, -1, -1):
		if holders[i]["car"] == car:
			holders.remove_at(i)


func _cell_fast(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - _g0.x) / tile), floori((p.y - _g0.y) / tile))


func _obs_add(n: Object, r: Rect2, spd: float) -> void:
	# lokeroon kasvatettuna, jotta reunan yli osuva koetin löytää esteen
	var g := r.grow(6.0)
	var a := _cell_fast(g.position)
	var b := _cell_fast(g.end)
	var e := [n, r, spd]
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var k := Vector2i(x, y)
			if _obs.has(k):
				_obs[k].append(e)
			else:
				_obs[k] = [e]


func _obs_add_sprite(n, wreck: bool = false) -> void:
	if not is_instance_valid(n) or not (n is Node2D) or (Game.flag(n, "dead") and not wreck):
		return
	var spr: Sprite2D = null
	for key in ["visual", "sprite"]:
		var v = n.get(key)
		if v is Sprite2D and is_instance_valid(v):
			spr = v
			break
	if spr == null:
		for ch in n.get_children():
			if ch is Sprite2D:
				spr = ch
				break
	if spr == null or spr.texture == null:
		return
	var sz := spr.texture.get_size()
	var c: Vector2 = (n as Node2D).global_position + spr.offset
	var spd := 0.0
	if Game.flag(n, "moving") and n.get("speed") != null:
		spd = float(n.get("speed"))
	_obs_add(n, Rect2(c - sz * 0.5, sz).grow_individual(-1.0, -3.0, -1.0, -1.0), spd)


## Kerää esteet (kerran ruudussa). Liikenneautot kutsuvat tätä ennen kuin katsovat eteensä.
func traffic_refresh_obstacles() -> void:
	var f := Engine.get_process_frames()
	if f == _obs_frame:
		return
	_obs_frame = f
	_obs.clear()
	_g0 = ground_layer.to_global(ground_layer.map_to_local(Vector2i.ZERO)) - Vector2(tile, tile) * 0.5
	if entities:
		for m in entities.get_children():
			if m is Mover and m.is_car and not m.dead:
				_obs_add(m, m.car_rect(), m.cur_speed)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	for n in get_tree().get_nodes_in_group("shootable"):
		if n == player or not (n is Node2D) or not n.has_method("hit_point"):
			continue
		if Game.flag(n, "is_car") or Game.flag(n, "dead") or not (n as Node2D).is_visible_in_tree():
			continue
		var hp: Vector2 = n.hit_point()
		_obs_add(n, Rect2(hp + Vector2(-4.0, -4.0), Vector2(8.0, 10.0)), 0.0)
	for c in get_tree().get_nodes_in_group("player_vehicles"):
		if is_instance_valid(c) and c.is_inside_tree() and c.has_method("hit_rect"):
			_obs_add(c, c.hit_rect(), (c as CharacterBody2D).velocity.length())
	if player and player.visible:
		var pc: Vector2 = player.body_center() if player.has_method("body_center") else player.global_position
		var pv := (player as CharacterBody2D).velocity.length() if player is CharacterBody2D else 0.0
		_obs_add(player, Rect2(pc + Vector2(-4.0, -4.0), Vector2(8.0, 10.0)), pv)
	var pm := get_tree().get_first_node_in_group("police_manager")
	if pm and "cars" in pm:
		for c in pm.cars:
			_obs_add_sprite(c)
	var pp := get_tree().get_first_node_in_group("police_patrol")
	if pp and "patrols" in pp:
		for c in pp.patrols:
			_obs_add_sprite(c)
	for c in get_tree().get_nodes_in_group("police_wrecks"):
		_obs_add_sprite(c, true)


## Ensimmäinen este, joka osuu laatikkoon (keskipiste p, puolikoko half). [] jos ei mitään.
func traffic_probe(p: Vector2, half: float, me: Object) -> Array:
	var arr = _obs.get(_cell_fast(p))
	if arr == null:
		return []
	var box := Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0)
	for e in arr:
		if e[0] != me and (e[1] as Rect2).intersects(box):
			return e
	return []


## Onko ruudussa c este (muu kuin me), jonka nopeus on alle max_speed?
func traffic_cell_blocked(c: Vector2i, me: Object, max_speed: float = INF) -> bool:
	var arr = _obs.get(c)
	if arr == null:
		return false
	var center := _g0 + (Vector2(c) + Vector2(0.5, 0.5)) * tile
	var box := Rect2(center - Vector2(6.0, 6.0), Vector2(12.0, 12.0))
	for e in arr:
		if e[0] != me and float(e[2]) < max_speed and (e[1] as Rect2).intersects(box):
			return true
	return false


## Uusi ohikulkija (esim. palavasta autosta paennut kuski) ruutuun c.
func spawn_ped_at(c: Vector2i, local_pos: Vector2) -> Node2D:
	if not entities or not _in_bounds(c) or _is_solid(c):
		return null
	var m := _make_ped(c)
	m.position = local_pos
	m.wait = 0.0
	entities.add_child(m)
	m.refresh()
	return m


class Mover extends Node2D:
	const COIN_SCRIPT := preload("res://scripts/world/Coin.gd")
	## Ryöstössä pudotettavien kolikoiden määrä ja yhden kolikon arvo ($) -- säädä näitä
	const ROB_COINS_MIN := 3
	const ROB_COINS_MAX := 7
	const COIN_VALUE_MIN := 5
	const COIN_VALUE_MAX := 15
	const SURRENDER_TIME := 1.3
	const SCREAMS := ["Älä ammu!", "Ota rahat!", "Ei, ei!", "Apua!", "Rauhassa!"]

	var robbed := false
	var city: CityGenerator
	var is_car := false
	var car_color := "green"
	var cell := Vector2i.ZERO
	var dir := Vector2i.DOWN
	var speed := 40.0
	var visual: Sprite2D
	var base_row := 0
	var step := 0
	var anim := 0.0
	var path: Array[Vector2i] = []
	var next_cell := Vector2i.ZERO
	var target := Vector2.ZERO
	var moving := false
	var wait := 0.0
	var dead := false
	var _blocked_t := 0.0
	var _xwalk_wait := 0.0
	var _honked := false
	var _impacts: Node = null

	# --- Todistaja: näki rikoksen ja soittaa poliisille (PoliceManager.commit_crime) ---
	const CALL_TIME := 4.5        ## puhelun kesto sekunteina ennen kuin poliisi saa tiedon
	const CALL_SIGHT := 280.0     ## puhelun lopussa todistajan pitää yhä nähdä pelaaja (px)
	const SCARED_TIME := 12.0     ## vaiennettu todistaja ei soita tähän aikaan
	var calling := false
	var _call_delay := -1.0       # > 0: odottaa ennen puhelua (uhri pakenee ensin)
	var _call_t := 0.0
	var _call_mgr: Node = null
	var _call_id := 0
	var _call_points := 0
	var _call_serious := false
	var _scared_t := 0.0
	var _phone: Node2D = null
	var _phone_fill: ColorRect = null
	## Nippusiteillä sidottu (s jäljellä): ei liiku eikä soita poliisille
	var tied_t := 0.0
	var _tie_mark: Node2D = null

	func is_tied() -> bool:
		return tied_t > 0.0

	## Pelaaja sitoo nippusiteillä (Player2D.try_tie). Puhelu katkeaa.
	func tie_up(secs: float) -> void:
		if dead or is_car:
			return
		calling = false
		_call_delay = -1.0
		_hide_phone()
		tied_t = secs
		moving = false
		path.clear()
		step = 0
		dir = Vector2i.DOWN   # kasvot pelaajaan päin, jotta sidotut ranteet näkyvät
		if visual:
			visual.position.x = 0.0
		refresh()
		_say(["Mmmph!", "Päästä irti!", "Mitä sä teet?!"][randi() % 3])
		if _tie_mark == null:
			_tie_mark = TieMark.new()
			add_child(_tie_mark)

	func _process(delta: float) -> void:
		if is_car:
			_car_process(delta)
			return
		if tied_t > 0.0:
			tied_t -= delta
			if tied_t <= 0.0:
				if is_instance_valid(_tie_mark):
					_tie_mark.queue_free()
				_tie_mark = null
				_scared_t = SCARED_TIME
				_say("Vihdoin irti!")
			return
		if _scared_t > 0.0:
			_scared_t -= delta
		if _call_delay > 0.0:
			_call_delay -= delta
			if _call_delay <= 0.0:
				_begin_call()
		if calling:
			_update_call(delta)
			return
		if wait > 0.0:
			wait -= delta
			return
		if dead:
			return
		if not moving and not _choose_next():
			return
		if not is_car:
			anim += delta
			var st := 1 + (int(anim * 6.0) % 2)
			if st != step:
				step = st
				refresh()
		var to := target - position
		var dist := speed * delta
		if to.length() <= dist:
			position = target
			cell = next_cell
			moving = false
			if not is_car and path.is_empty():
				wait = randf_range(1.0, 4.0)
				step = 0
				refresh()
		else:
			position += to.normalized() * dist

	# ------------------------------------------------------------------
	#  LIIKENNEAUTO: AJO OMALLA KAISTALLA, VÄISTÄMINEN, VAURIOT
	# ------------------------------------------------------------------
	const CAR_FIRE := preload("res://scripts/entities/CarFire.gd")
	const BLOOD := preload("res://scripts/core/Blood.gd")
	const EXPLOSION := preload("res://scripts/core/Explosion.gd")
	# --- SÄÄDÄ NÄITÄ ---
	const ACCEL := 70.0              ## kiihtyvyys (px/s²)
	const BRAKE := 260.0             ## jarrutus (px/s²): tästä lasketaan jarrutusmatka
	const FRONT := 11.0              ## keulan etäisyys auton keskeltä (px)
	const STOP_GAP := 5.0            ## väli edessä olevaan pysähdyttäessä (px)
	const TURN_SPEED := 40.0         ## nopeus käännöksissä ja kaistanvaihdoissa
	const ACQUIRE_DIST := 26.0       ## risteys varataan, kun pysäytyskohtaan on tätä vähemmän (px)
	const LANE_CHANGE_AFTER := 1.0   ## jumissa näin kauan -> vaihdetaan viereiselle kaistalle (leveä tie)
	const OVERTAKE_AFTER := 2.5      ## seisovan esteen takana näin kauan -> ohitetaan vastaantulevien kaistan kautta
	const UTURN_AFTER := 8.0         ## tie ei vapaudu -> käännytään ympäri
	const HONK_AFTER := 1.5          ## pelaaja tiellä -> tööttäys
	const CAR_MAX_HEALTH := 60.0
	const BURN_TIME := 5.0           ## palava auto räjähtää näin monen sekunnin päästä

	var cur_speed := 0.0
	var route: Array[Vector2i] = []
	var route_face: Array[Vector2i] = []   # (0,0) = suunta liikkeestä
	var plan_cell := Vector2i.ZERO         # reitin viimeinen ruutu
	var plan_dir := Vector2i.DOWN          # ajosuunta reitin lopussa
	var j_key := Vector2i(-1, -1)          # varattu risteys
	var _maneuver := 0                     # ohitus/kaistanvaihto/U-käännös kesken (ruutuja jäljellä)
	var _blocker: Array = []
	var _gap := 0.0
	var _far_skip := 0
	var health := CAR_MAX_HEALTH
	var burning := false
	var wrecked := false
	var _burn_t := 0.0
	var _fire = null   # CarFire.gd
	var _by_player := false

	func _car_process(delta: float) -> void:
		if burning:
			_burn_t -= delta
			if _burn_t <= 0.0:
				_explode()
			return
		if wrecked:
			return
		if wait > 0.0:
			wait -= delta
			return
		city.traffic_refresh_obstacles()
		while route.size() < 6:
			if not _extend_route():
				break
		if not moving and not _next_step():
			cur_speed = 0.0
			_blocker = []
			_handle_blocked(delta, true)
			return
		var res := _free_distance()
		_gap = res[0]
		_blocker = res[1]
		var cruise := speed * Game.car_speed_mult()
		if _turn_ahead():
			cruise = minf(cruise, TURN_SPEED)
		var room := maxf(_gap - STOP_GAP, 0.0)
		var want := minf(cruise, sqrt(2.0 * BRAKE * room))
		if want > cur_speed:
			cur_speed = minf(cur_speed + ACCEL * delta, want)
		else:
			cur_speed = want
		if room <= 0.5:
			cur_speed = 0.0
		_handle_blocked(delta, false)
		if not moving:
			return   # väistöliike alkoi: uusi reitti otetaan käyttöön seuraavassa ruudussa
		var dist := minf(cur_speed * delta, room)
		var guard := 0
		while dist > 0.0 and guard < 4:
			guard += 1
			var to := target - position
			var l := to.length()
			if l <= dist:
				position = target
				dist -= l
				_arrive()
				if not _next_step():
					break
			else:
				position += to / l * dist
				dist = 0.0

	func _arrive() -> void:
		cell = next_cell
		moving = false
		if j_key != Vector2i(-1, -1) and not city.is_junction(cell):
			city.traffic_leave(self, j_key)
			j_key = Vector2i(-1, -1)

	## Seuraava ruutu reitiltä. Risteykseen ei ajeta ilman varausta.
	func _next_step() -> bool:
		if route.is_empty():
			return false
		var n: Vector2i = route[0]
		if city.is_junction(n) and not city.is_junction(cell) and j_key != city.junction_key(n):
			var cs: Array[Vector2i] = [cell]
			cs.append_array(route)
			if not _try_junction(1, cs):
				return false
		route.pop_front()
		var f: Vector2i = route_face.pop_front()
		if _maneuver > 0:
			_maneuver -= 1
		next_cell = n
		var dv := n - cell
		if f != Vector2i.ZERO:
			dir = f
		elif dv != Vector2i.ZERO and (dv.x == 0 or dv.y == 0):
			dir = Vector2i(signi(dv.x), signi(dv.y))
		target = city._cell_center(n)
		moving = true
		refresh()
		return true

	## Jatkaa reittiä: suoraan omalla kaistalla, risteyksessä arvottu käännös, kartan reunalla U-käännös.
	func _extend_route() -> bool:
		var c := plan_cell
		var d := plan_dir
		var ahead := c + d
		if not city.is_road(ahead) or city.is_edge(ahead):
			return _append(_uturn_cells(c, d), -d)
		if city.is_junction(ahead) and not city.is_junction(c):
			var plan := city.traffic_junction_plan(c, d)
			if plan.is_empty():
				return _append(_uturn_cells(c, d), -d)
			for jc: Vector2i in plan["cells"]:
				route.append(jc)
				route_face.append(Vector2i.ZERO)
			plan_cell = route[route.size() - 1]
			plan_dir = plan["dir"]
			return true
		route.append(ahead)
		route_face.append(Vector2i.ZERO)
		plan_cell = ahead
		return true

	func _append(cells_faces: Array, new_dir: Vector2i) -> bool:
		if cells_faces.is_empty():
			return false
		var cells: Array = cells_faces[0]
		var faces: Array = cells_faces[1]
		for i in cells.size():
			route.append(cells[i])
			route_face.append(faces[i])
		plan_cell = cells[cells.size() - 1]
		plan_dir = new_dir
		return true

	## U-käännös ruudusta c (ajosuunta d) vastakkaisen suunnan sisäkaistalle. [] jos ei onnistu.
	func _uturn_cells(c: Vector2i, d: Vector2i) -> Array:
		var r := city.traffic_road(c, d)
		var opp := city.traffic_lanes(r, -d)
		if opp.is_empty():
			return []
		var now := CityGenerator.lane_coord(c, d)
		var tl: int = opp[opp.size() - 1]
		var sgn := signi(tl - now)
		if sgn == 0:
			return []
		var lat := Vector2i(sgn, 0) if d.y != 0 else Vector2i(0, sgn)
		var cells: Array[Vector2i] = []
		var faces: Array[Vector2i] = []
		var p := c + d + lat
		if not city.is_road(p) or city.is_junction(p) or city.is_junction(c + d) or city.is_edge(p):
			p = c + lat
		cells.append(p)
		faces.append(lat)
		var guard := 0
		while CityGenerator.lane_coord(p, d) != tl and guard < 8:
			guard += 1
			p += lat
			cells.append(p)
			faces.append(lat)
		faces[faces.size() - 1] = -d
		return [cells, faces]

	## Kuinka pitkälle (px) reitillä on tilaa. Palauttaa [matka, este tai []].
	## Risteyksen kohdalla matka loppuu pysäytyskohtaan, jos risteystä ei saada varattua.
	func _free_distance() -> Array:
		# kaukana kamerasta tarkistetaan harvemmin (kevyempi)
		if _far_skip > 0:
			_far_skip -= 1
			return [_gap - cur_speed * get_process_delta_time(), _blocker]
		var cam := get_viewport().get_camera_2d()
		if cam and cam.get_screen_center_position().distance_squared_to(global_position) > 900.0 * 900.0:
			_far_skip = 2
		var xf := (get_parent() as Node2D).global_transform
		var look := 34.0 + cur_speed * cur_speed / (2.0 * BRAKE) + FRONT
		var pts: Array[Vector2] = [position]
		var cs: Array[Vector2i] = [cell]
		if moving:
			pts.append(target)
			cs.append(next_cell)
		for c in route:
			pts.append(city._cell_center(c))
			cs.append(c)
		var acc := 0.0
		for i in range(pts.size() - 1):
			var cb := cs[i + 1]
			if city.is_junction(cb) and not city.is_junction(cs[i]) and city.junction_key(cb) != j_key:
				if acc > ACQUIRE_DIST or not _try_junction(i + 1, cs):
					return [acc, []]
			var a := pts[i]
			var seg := pts[i + 1] - a
			var l := seg.length()
			if l < 0.01:
				continue
			var u := seg / l
			var t := 0.0
			while t < l:
				var hit := city.traffic_probe(xf * (a + u * (t + FRONT)), 4.0, self)
				if not hit.is_empty():
					return [acc + t, hit]
				t += 4.0
				if acc + t > look:
					return [acc + t, []]
			acc += l
		return [acc, []]

	## Varaa risteyksen, jos reitti sen läpi on vapaa ja ulosajossa on tilaa.
	func _try_junction(idx: int, cs: Array[Vector2i]) -> bool:
		var jcells: Array[Vector2i] = []
		var k := idx
		while k < cs.size() and city.is_junction(cs[k]):
			jcells.append(cs[k])
			k += 1
		if jcells.is_empty() or idx < 1:
			return false
		for c in jcells:
			if city.traffic_cell_blocked(c, self, 15.0):
				return false
		# ei tukita risteystä: ulosajoruudussa (ja sen takana) ei saa seistä mitään
		if k < cs.size() and city.traffic_cell_blocked(cs[k], self, 15.0):
			return false
		if k + 1 < cs.size() and city.traffic_cell_blocked(cs[k + 1], self, 15.0):
			return false
		var key := city.junction_key(cs[idx])
		var entry := cs[idx] - cs[idx - 1]
		if not city.traffic_try_enter(self, key, jcells, entry):
			return false
		j_key = key
		return true

	## Onko lähiruuduissa suunnanmuutos (käännös, kaistanvaihto)? Silloin hiljennetään.
	func _turn_ahead() -> bool:
		var pd := (next_cell - cell) if moving else dir
		var p := next_cell if moving else cell
		for i in mini(2, route.size()):
			var nd := route[i] - p
			if nd != pd:
				return true
			p = route[i]
		return false

	## Jumissa: tööttää pelaajalle, vaihtaa kaistaa, ohittaa seisovan esteen tai kääntyy ympäri.
	func _handle_blocked(delta: float, waiting_junction: bool) -> void:
		var stopped := cur_speed < 4.0 and _gap < 26.0 and not _blocker.is_empty()
		if waiting_junction:
			stopped = true
		if not stopped:
			_blocked_t = 0.0
			_honked = false
			return
		_blocked_t += delta
		var b = _blocker[0] if not _blocker.is_empty() else null
		var b_speed: float = float(_blocker[2]) if not _blocker.is_empty() else 0.0
		var valid: bool = b != null and is_instance_valid(b)
		var is_player: bool = valid and (b.is_in_group("player") or (b.is_in_group("player_vehicles") and Game.flag(b, "is_driving")))
		if is_player and _blocked_t > HONK_AFTER and not _honked:
			_honked = true
			Sfx.play("horn", global_position, -6.0, 0.08)
			_say(["Liiku!", "Pois tieltä!", "Haloo?!", "Ajatko vai et?"][randi() % 4])
		# risteyksen edessä odotetaan vuoroa; vasta kauan tukossa olleesta risteyksestä käännytään pois
		if waiting_junction:
			if _blocked_t > UTURN_AFTER * 2.0 and _maneuver == 0 and j_key == Vector2i(-1, -1):
				var u0 := _uturn_cells(cell, dir)
				if not u0.is_empty() and _lane_clear_for_uturn(u0):
					_begin_maneuver(u0[0], u0[1], -dir)
			return
		if _maneuver > 0 or j_key != Vector2i(-1, -1) or city.is_junction(cell):
			return
		if moving and city.is_junction(next_cell):
			return
		# jonossa seisova liikenneauto: ei ohiteta vastaantulevien kaistan kautta
		var queue: bool = valid and Game.flag(b, "is_car") and not Game.flag(b, "wrecked")
		if _blocked_t > LANE_CHANGE_AFTER and b_speed < 10.0 and _try_lane_change():
			return
		if not queue and _blocked_t > OVERTAKE_AFTER and b_speed < 5.0 and _try_overtake():
			return
		if _blocked_t > UTURN_AFTER * (2.0 if queue else 1.0):
			var u := _uturn_cells(cell, dir)
			if not u.is_empty() and _lane_clear_for_uturn(u):
				_begin_maneuver(u[0], u[1], -dir)

	func _lane_clear_for_uturn(u: Array) -> bool:
		var cells: Array = u[0]
		var last: Vector2i = cells[cells.size() - 1]
		for c in cells:
			if city.traffic_cell_blocked(c, self):
				return false
		for k in range(1, 4):
			if city.traffic_cell_blocked(last + dir * k, self):
				return false
		return true

	## Leveällä tiellä viereiselle kaistalle (sama ajosuunta), jos siellä on tilaa.
	func _try_lane_change() -> bool:
		var d := dir
		var lanes := city.traffic_lanes(city.traffic_road(cell, d), d)
		if lanes.size() < 2:
			return false
		var cur := CityGenerator.lane_coord(cell, d)
		var idx := lanes.find(cur)
		if idx < 0:
			return false
		for k in range(1, 3):
			if not city.is_road(cell + d * k) or city.is_junction(cell + d * k):
				return false
		var opts: Array[int] = []
		if idx + 1 < lanes.size():
			opts.append(lanes[idx + 1])
		if idx - 1 >= 0:
			opts.append(lanes[idx - 1])
		for tl in opts:
			var side := CityGenerator.set_lane(cell, d, tl)
			var ok := true
			for k in range(-2, 3):
				var c := side + d * k
				if not city.is_road(c) or city.traffic_cell_blocked(c, self):
					ok = false
					break
			if ok:
				var cells: Array[Vector2i] = [side + d]
				var faces: Array[Vector2i] = [d]
				_begin_maneuver(cells, faces, d)
				return true
		return false

	## Seisova este (romu, pysäköity auto, poliisi) ohitetaan vastaantulevien kaistan kautta,
	## kun vastaantulevien kaista on vapaa riittävän pitkälle eikä edessä ole risteystä.
	func _try_overtake() -> bool:
		# Ei koskaan ajeta vastaantulevien kaistalle: seisovan esteen takaa vaihdetaan
		# kaistaa (leveä tie) tai lopulta käännytään ympäri.
		if true:
			return false
		var d := dir
		var r := city.traffic_road(cell, d)
		var opp := city.traffic_lanes(r, -d)
		if opp.is_empty():
			return false
		var cur := CityGenerator.lane_coord(cell, d)
		var tl: int = opp[opp.size() - 1]
		var sgn := signi(tl - cur)
		if sgn == 0:
			return false
		var lat := Vector2i(sgn, 0) if d.y != 0 else Vector2i(0, sgn)
		var nlat := absi(tl - cur)
		# esteen pituus omalla kaistalla
		var first := -1
		var last := -1
		for k in range(1, 7):
			var blocked := city.traffic_cell_blocked(cell + d * k, self, 5.0)
			if blocked:
				if first < 0:
					first = k
				last = k
			elif first >= 0:
				break
		if first < 0:
			first = 1
			last = 1
		if last >= 6:
			return false
		var straight := maxi(1, last - nlat + 1)
		var end := 2 * nlat + straight
		for i in range(0, end + 2):
			var c := cell + d * i
			if not city.is_road(c) or city.is_junction(c):
				return false
		# vastaantulevien kaista vapaa ohituksen ajan ja vähän pidemmälle
		for i in range(0, end + 7):
			if city.traffic_cell_blocked(CityGenerator.set_lane(cell + d * i, d, tl), self):
				return false
		var cells: Array[Vector2i] = []
		var faces: Array[Vector2i] = []
		var p := cell
		for i in nlat:
			p += d + lat
			cells.append(p)
		for i in straight:
			p += d
			cells.append(p)
		for i in nlat:
			p += d - lat
			cells.append(p)
		for c in cells:
			if city.traffic_cell_blocked(c, self):
				return false
			faces.append(d)
		_begin_maneuver(cells, faces, d)
		return true

	func _begin_maneuver(cells: Array, faces: Array, new_dir: Vector2i) -> void:
		route.clear()
		route_face.clear()
		for i in cells.size():
			route.append(cells[i])
			route_face.append(faces[i])
		_maneuver = cells.size()
		plan_cell = cells[cells.size() - 1]
		plan_dir = new_dir
		moving = false
		_blocked_t = 0.0
		_honked = false

	## Auton törmäyslaatikko maailmassa (kuva, hieman pienempänä).
	func car_rect() -> Rect2:
		if visual == null or visual.texture == null:
			return Rect2(global_position - Vector2(7.0, 7.0), Vector2(14.0, 14.0))
		var sz := visual.texture.get_size()
		var c := global_position + visual.offset
		return Rect2(c - sz * 0.5, sz).grow_individual(-1.0, -3.0, -1.0, -1.0)

	func hit_rect() -> Rect2:
		return car_rect()

	## Vahinkoa liikenneautolle (kolari, luoti, räjähdys). Kunnon loppuessa auto syttyy palamaan.
	func take_hit(amount: float, by_player: bool = false) -> void:
		if not is_car or amount <= 0.0 or (wrecked and not burning):
			return
		if by_player:
			_by_player = true
		if burning:
			_burn_t -= amount * 0.04
			return
		health = maxf(health - amount, 0.0)
		cur_speed *= 0.3
		visual.modulate = Color.WHITE.lerp(Color(0.55, 0.5, 0.48), 1.0 - health / CAR_MAX_HEALTH)
		if health <= 0.0:
			_ignite()
		elif health < CAR_MAX_HEALTH * 0.5:
			_ensure_fire().set_level(CAR_FIRE.SMOKE)

	func _ensure_fire():
		if _fire == null:
			_fire = CAR_FIRE.new()
			var sz: Vector2 = visual.texture.get_size() if visual and visual.texture else Vector2(16.0, 16.0)
			_fire.half = sz * 0.5 * Vector2(0.7, 0.5)
			_fire.center = visual.offset if visual else Vector2.ZERO
			add_child(_fire)
		return _fire

	func is_burning() -> bool:
		return burning

	func _ignite() -> void:
		burning = true
		wrecked = true
		_burn_t = BURN_TIME
		cur_speed = 0.0
		if j_key != Vector2i(-1, -1):
			city.traffic_leave(self, j_key)
			j_key = Vector2i(-1, -1)
		_ensure_fire().set_level(CAR_FIRE.BURNING)
		Sfx.play("glass_break", global_position, -2.0, 0.05)
		Sfx.play("ignite", global_position, 2.0, 0.08)
		# kuski hyppää ulos ja juoksee pakoon
		var ped := city.spawn_ped_at(cell, position + Vector2(0.0, 2.0))
		if ped:
			ped.speed = 95.0
			ped._say(["Apua, se palaa!", "Mun auto!", "Pois alta!"][randi() % 3])
			ped.create_tween().tween_property(ped, "speed", 40.0, 0.5).set_delay(5.0)

	func _explode() -> void:
		burning = false
		_ensure_fire().set_level(CAR_FIRE.SMOLDER)
		visual.modulate = Color(0.22, 0.19, 0.18)
		var ex := EXPLOSION.new()
		ex.source = self
		ex.by_player = _by_player
		get_parent().add_child(ex)
		ex.global_position = global_position + visual.offset
		var tw := create_tween()
		tw.tween_property(visual, "position:y", -7.0, 0.12).set_ease(Tween.EASE_OUT)
		tw.tween_property(visual, "position:y", 0.0, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)

	func _choose_next() -> bool:
		if is_car:
			next_cell = city.car_next_cell(cell, dir)
		else:
			if path.is_empty():
				path = city.ped_path(cell)
				if path.is_empty():
					wait = randf_range(0.5, 2.0)
					return false
			# Suojatien reunalla odotetaan, jos autoja on tulossa (enintään hetki; autot jarruttavat jalankulkijalle)
			if city.crosswalk_cells.has(path[0]) and not city.crosswalk_cells.has(cell) \
					and _xwalk_wait < 4.0 and city.crosswalk_busy(path[0]):
				_xwalk_wait += 0.35
				wait = 0.35
				step = 0
				refresh()
				return false
			_xwalk_wait = 0.0
			next_cell = path.pop_front()
		var d := next_cell - cell
		if d != Vector2i.ZERO:
			dir = d
		target = city._cell_center(next_cell)
		moving = true
		refresh()
		return true

	## Tie tukossa: auto kääntyy takaisin tulosuuntaansa.
	func _u_turn() -> void:
		_blocked_t = 0.0
		_honked = false
		dir = -dir
		next_cell = cell
		target = city._cell_center(cell)
		moving = true
		refresh()

	func can_be_robbed() -> bool:
		return not dead and not is_car and not robbed

	# ------------------------------------------------------------------
	#  TODISTAJA
	# ------------------------------------------------------------------
	## Voiko tämä ohikulkija todistaa rikoksen (ei jo soita, ei pelästynyt hiljaiseksi)?
	func can_witness() -> bool:
		return not dead and not is_car and not calling and _call_delay <= 0.0 and _scared_t <= 0.0 and tied_t <= 0.0

	func is_calling() -> bool:
		return calling or _call_delay > 0.0

	## PoliceManager pyytää soittamaan. delay = sekunteja ennen kuin puhelin otetaan esiin.
	func start_call(mgr: Node, crime_id: int, points: int, serious: bool, delay: float) -> void:
		_call_mgr = mgr
		_call_id = crime_id
		_call_points = points
		_call_serious = serious
		_call_delay = maxf(delay, 0.01)

	func _begin_call() -> void:
		if dead or not is_inside_tree():
			return
		calling = true
		_call_t = CALL_TIME
		moving = false
		path.clear()
		step = 0
		_face_player()
		_say(["Soitan poliisille!", "Hätänumero... 112!", "Poliisi, tänne!"][randi() % 3])
		Sfx.play("phone", global_position, -6.0, 0.0)
		_show_phone()

	func _update_call(delta: float) -> void:
		_call_t -= delta
		_face_player()
		if _phone_fill:
			_phone_fill.size.x = 14.0 * clampf(1.0 - _call_t / CALL_TIME, 0.0, 1.0)
		if _call_t <= 0.0:
			_finish_call()

	func _finish_call() -> void:
		calling = false
		_hide_phone()
		wait = 1.0
		if not is_instance_valid(_call_mgr):
			return
		var saw: bool = _call_mgr.can_see_player_from(global_position, CALL_SIGHT)
		_call_mgr.witness_report(_call_id, _call_points, _call_serious, saw)
		if not saw:
			_say("Se ehti karata...")

	## Todistaja hiljennettiin (lyönti tai aseella uhkaus): puhelu katkeaa, eikä hän soita hetkeen.
	func _silence() -> void:
		var was := is_calling()
		calling = false
		_call_delay = -1.0
		_scared_t = SCARED_TIME
		_hide_phone()
		if was:
			var hud := get_tree().current_scene.get_node_or_null("Hud")
			if hud and hud.has_method("show_message"):
				hud.show_message("Todistaja vaiennettu – puhelu katkesi.", 2.2)

	func _face_player() -> void:
		var pl := get_tree().get_first_node_in_group("player") as Node2D
		if pl == null:
			return
		var to_p := pl.global_position - global_position
		if absf(to_p.x) > absf(to_p.y):
			dir = Vector2i.RIGHT if to_p.x > 0.0 else Vector2i.LEFT
		else:
			dir = Vector2i.DOWN if to_p.y > 0.0 else Vector2i.UP
		refresh()

	## Puhelin kädessä + edistymispalkki pään päällä.
	func _show_phone() -> void:
		_hide_phone()
		_phone = Node2D.new()
		_phone.z_index = 30
		add_child(_phone)
		var handset := ColorRect.new()
		handset.color = Color(0.12, 0.12, 0.14)
		handset.position = Vector2(3.0, -10.0)
		handset.size = Vector2(3.0, 5.0)
		_phone.add_child(handset)
		var screen := ColorRect.new()
		screen.color = Color(0.5, 0.95, 1.0)
		screen.position = Vector2(3.5, -9.5)
		screen.size = Vector2(2.0, 2.0)
		_phone.add_child(screen)
		var bg := ColorRect.new()
		bg.color = Color(0.0, 0.0, 0.0, 0.7)
		bg.position = Vector2(-8.0, -18.0)
		bg.size = Vector2(16.0, 3.0)
		_phone.add_child(bg)
		_phone_fill = ColorRect.new()
		_phone_fill.color = Color(1.0, 0.3, 0.25)
		_phone_fill.position = Vector2(-7.0, -17.5)
		_phone_fill.size = Vector2(0.0, 2.0)
		_phone.add_child(_phone_fill)
		for c in _phone.get_children():
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _hide_phone() -> void:
		if is_instance_valid(_phone):
			_phone.queue_free()
		_phone = null
		_phone_fill = null

	## Uhri voi itse soittaa poliisille, paitsi jos hänet juuri vaiennettiin.
	func _victim_or_null(silenced: bool) -> Node:
		if silenced:
			return null
		return self

	func _crime(points: int, serious: bool = false, victim: Node = null) -> void:
		get_tree().call_group("police_manager", "commit_crime", points, global_position, victim, serious)

	## Pelaaja uhkaa asetta: NPC pysähtyy kädet ylhäällä, pudottaa kolikoita ja juoksee pakoon.
	func rob(player: Node2D) -> void:
		if not can_be_robbed():
			return
		var was_calling := is_calling()
		if was_calling:
			_silence()   # aseella uhattu todistaja ei enää soita
		robbed = true
		wait = SURRENDER_TIME + 1.0
		moving = false
		path.clear()
		step = 0
		# Käänny pelaajaan päin
		var to_p: Vector2 = player.body_center() - global_position
		if absf(to_p.x) > absf(to_p.y):
			dir = Vector2i.RIGHT if to_p.x > 0.0 else Vector2i.LEFT
		else:
			dir = Vector2i.DOWN if to_p.y > 0.0 else Vector2i.UP
		refresh()
		_say(SCREAMS[randi() % SCREAMS.size()])
		var shake := create_tween().set_loops(6)
		shake.tween_property(visual, "position:x", 0.8, 0.05)
		shake.tween_property(visual, "position:x", -0.8, 0.05)
		# Ryöstö: muut ohikulkijat voivat nähdä sen, ja uhri soittaa paettuaan
		# (paitsi jos hänet jo vaiennettiin)
		_crime(1, false, _victim_or_null(was_calling))

		await get_tree().create_timer(SURRENDER_TIME).timeout
		if dead or not is_inside_tree():
			return
		visual.position.x = 0.0
		_drop_coins()
		# Pakenee hetken lujempaa
		var normal_speed := speed
		speed = 100.0
		wait = 0.0
		await get_tree().create_timer(5.0).timeout
		if is_instance_valid(self) and not dead:
			speed = normal_speed

	func _drop_coins() -> void:
		var n := randi_range(ROB_COINS_MIN, ROB_COINS_MAX)
		for i in n:
			var coin := COIN_SCRIPT.new()
			coin.value = randi_range(COIN_VALUE_MIN, COIN_VALUE_MAX)
			coin.position = position + Vector2(0.0, -4.0)
			get_parent().add_child(coin)
			coin.toss(Vector2.from_angle(randf() * TAU) * randf_range(25.0, 70.0))
		Sfx.play("coin", global_position, -6.0, 0.1, 0.85)

	var shoved := false

	func is_punchable() -> bool:
		return not dead and not is_car

	## Pelaajan nyrkki: ohikulkija huutaa ja juoksee pakoon. Ensimmäinen isku on pahoinpitely (1 tähti).
	func fist_hit(from: Node2D) -> void:
		if not is_punchable():
			return
		var away: Vector2 = (global_position - from.global_position).normalized()
		BLOOD.spray(self, hit_point(), away, 3)
		position += away * 4.0
		var was_calling := is_calling()
		if was_calling:
			_silence()   # lyöty todistaja pudottaa puhelimen ja pakenee
		if shoved:
			return
		shoved = true
		moving = false
		path.clear()
		wait = 0.0
		_say(["Hei, älä lyö!", "Mikä sua vaivaa?!", "Apua, poliisi!"][randi() % 3])
		_crime(1, false, _victim_or_null(was_calling))
		var normal_speed := speed
		speed = 100.0
		await get_tree().create_timer(5.0).timeout
		if is_instance_valid(self) and not dead:
			speed = normal_speed
			shoved = false

	## Puhekupla NPC:n yläpuolelle.
	func _say(text: String) -> void:
		var l := Label.new()
		l.text = text
		l.position = Vector2(-34.0, -28.0)
		l.size = Vector2(68.0, 12.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.z_index = 30
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		add_child(l)
		var tw := create_tween()
		tw.tween_interval(1.2)
		tw.tween_property(l, "modulate:a", 0.0, 0.4)
		tw.tween_callback(l.queue_free)

	## Luodin osumapiste (vartalon keskikohta)
	func hit_point() -> Vector2:
		return global_position + Vector2(0, -4)

	## NPC kaatuu ja katoaa hetken päästä. Pelaajan ampuma NPC aiheuttaa etsintäkuulutuksen.
	func take_damage(_amount: int = 1, source: Node = null) -> void:
		if is_car:
			# luoti osuu liikenneautoon
			take_hit(float(_amount) * 4.0, source != null and source.is_in_group("player"))
			return
		if dead:
			return
		var was_calling := is_calling()
		var bdir: Vector2 = (global_position - (source as Node2D).global_position) if source is Node2D else Vector2.ZERO
		BLOOD.spray(self, hit_point(), bdir, 9, true)
		dead = true
		calling = false
		_call_delay = -1.0
		_hide_phone()
		remove_from_group("shootable")
		set_process(false)
		visual.rotation = deg_to_rad(90.0 if dir.x >= 0 else -90.0)
		if source and source.is_in_group("player"):
			if was_calling:
				var hud := get_tree().current_scene.get_node_or_null("Hud")
				if hud and hud.has_method("show_message"):
					hud.show_message("Todistaja vaiennettu... pysyvästi.", 2.2)
			# Henkirikos: muut ohikulkijat voivat nähdä sen
			_crime(1, true)
		var tw := create_tween()
		tw.tween_interval(5.0)
		tw.tween_property(self, "modulate:a", 0.0, 1.0)
		tw.tween_callback(queue_free)

	func refresh() -> void:
		if is_car:
			var tex := city.car_texture(car_color, dir)
			visual.texture = tex
			# korkeammat kuvat (katto/ohjaamo) nostetaan niin että renkaat pysyvät tiellä
			visual.offset = Vector2(0, -floorf((tex.get_height() - 16) * 0.5))
		else:
			visual.texture = city.npc_tex(base_row, dir, step)


## Nippusiteet sidotun ohikulkijan ranteissa (Mover.tie_up) ja tärinä.
class TieMark extends Node2D:
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var sh := sin(_t * 25.0) * 0.3
		var c := Color(0.97, 0.97, 0.95)
		# Hahmon kuva on nostettu 4 px (Sprite offset), joten ranteet ovat y ≈ -1 ja
		# kädet x ≈ ±3.8. Side kiertää kummankin ranteen ja vetää ne vyötärön eteen.
		var dk := Color(0.55, 0.55, 0.58)
		for sx: float in [-3.8, 3.8]:
			draw_rect(Rect2(Vector2(sx - 0.9 + sh, -1.6), Vector2(1.8, 0.8)), c)
			draw_rect(Rect2(Vector2(sx - 0.9 + sh, -0.8), Vector2(1.8, 0.3)), dk)
		draw_line(Vector2(-3.0 + sh, -1.2), Vector2(3.0 + sh, -1.2), c, 0.7)
		draw_rect(Rect2(Vector2(-0.5 + sh, -1.7), Vector2(1.0, 1.0)), dk)


## Tietyömaat kartan reunoilla (city_generator._build_roadworks). zones = [[alue, kaupunkiin päin]].
class RoadWorks extends Node2D:
	var zones: Array = []
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if fmod(_t, 0.25) < delta:
			queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var blink := fmod(_t, 1.0) < 0.5
		for z: Array in zones:
			var r: Rect2 = z[0]
			var inward: Vector2 = z[1]
			var vertical := absf(inward.y) > 0.5   # pystytie: puomi vaakasuunnassa
			# kaivettu asfaltti ja sorahiekka
			draw_rect(r, Color(0.36, 0.3, 0.24))
			var seed_i := int(r.position.x * 7.0 + r.position.y * 3.0)
			for k in 28:
				var px := r.position.x + fposmod(float(seed_i * 13 + k * 37), r.size.x)
				var py := r.position.y + fposmod(float(seed_i * 7 + k * 23), r.size.y)
				draw_rect(Rect2(px, py, 1.0, 1.0), Color(0.5, 0.44, 0.36) if k % 2 == 0 else Color(0.25, 0.21, 0.17))
			# puomi kaupungin puoleisessa reunassa: punavalkoiset raidat tolpilla
			var inner_edge: Rect2
			if vertical:
				var by := r.end.y - 6.0 if inward.y > 0.0 else r.position.y + 1.0
				inner_edge = Rect2(r.position.x, by, r.size.x, 5.0)
			else:
				var bx := r.end.x - 6.0 if inward.x > 0.0 else r.position.x + 1.0
				inner_edge = Rect2(bx, r.position.y, 5.0, r.size.y)
			draw_rect(inner_edge, Color(0.95, 0.95, 0.95))
			var stripe := 0.0
			var length := inner_edge.size.x if vertical else inner_edge.size.y
			while stripe < length:
				var sr := Rect2(inner_edge.position.x + stripe, inner_edge.position.y, minf(4.0, length - stripe), inner_edge.size.y) if vertical \
					else Rect2(inner_edge.position.x, inner_edge.position.y + stripe, inner_edge.size.x, minf(4.0, length - stripe))
				draw_rect(sr, Color(0.85, 0.12, 0.1))
				stripe += 8.0
			draw_rect(inner_edge, Color(0.2, 0.05, 0.05), false, 1.0)
			# vilkkuvalot puomin päissä ja keskellä
			var lamps: Array[Vector2] = []
			if vertical:
				lamps = [Vector2(inner_edge.position.x + 3.0, inner_edge.position.y - 1.0), Vector2(inner_edge.get_center().x, inner_edge.position.y - 1.0), Vector2(inner_edge.end.x - 3.0, inner_edge.position.y - 1.0)]
			else:
				lamps = [Vector2(inner_edge.get_center().x, inner_edge.position.y + 3.0), Vector2(inner_edge.get_center().x, inner_edge.get_center().y), Vector2(inner_edge.get_center().x, inner_edge.end.y - 3.0)]
			for i in lamps.size():
				var on := blink if i % 2 == 0 else not blink
				draw_circle(lamps[i], 1.6, Color(1.0, 0.75, 0.1) if on else Color(0.5, 0.35, 0.05))
				if on:
					draw_circle(lamps[i], 5.0, Color(1.0, 0.8, 0.2, 0.18))
			# liikennekartiot puomin edessä
			var front := inner_edge.get_center() + inward * 9.0
			var along := Vector2(1.0, 0.0) if vertical else Vector2(0.0, 1.0)
			for k in range(-2, 3):
				var cp := front + along * float(k) * (length / 5.0)
				draw_colored_polygon(PackedVector2Array([cp + Vector2(-2.5, 2.0), cp + Vector2(2.5, 2.0), cp + Vector2(0.0, -5.0)]), Color(1.0, 0.45, 0.05))
				draw_line(cp + Vector2(-1.4, -1.0), cp + Vector2(1.4, -1.0), Color.WHITE, 1.0)
				draw_rect(Rect2(cp + Vector2(-3.0, 1.5), Vector2(6.0, 1.5)), Color(0.15, 0.15, 0.15))
			# kaivuri ja hiekkakasa työmaan puolella
			var mid := r.get_center() - inward * 4.0
			var dig := mid - along * (length * 0.22)
			draw_rect(Rect2(dig + Vector2(-8.0, 2.0), Vector2(16.0, 4.0)), Color(0.12, 0.12, 0.14))       # telat
			draw_rect(Rect2(dig + Vector2(-7.0, -5.0), Vector2(14.0, 7.0)), Color(0.95, 0.72, 0.1))        # runko
			draw_rect(Rect2(dig + Vector2(-6.0, -11.0), Vector2(7.0, 6.0)), Color(0.95, 0.72, 0.1))        # ohjaamo
			draw_rect(Rect2(dig + Vector2(-5.0, -10.0), Vector2(5.0, 3.0)), Color(0.45, 0.65, 0.8))        # ikkuna
			draw_line(dig + Vector2(5.0, -4.0), dig + Vector2(12.0, -11.0), Color(0.85, 0.62, 0.08), 2.0)   # puomi
			draw_line(dig + Vector2(12.0, -11.0), dig + Vector2(16.0, -3.0), Color(0.85, 0.62, 0.08), 2.0)
			draw_colored_polygon(PackedVector2Array([dig + Vector2(14.0, -3.0), dig + Vector2(19.0, -3.0), dig + Vector2(17.0, 1.0)]), Color(0.3, 0.3, 0.32))   # kauha
			var sand := mid + along * (length * 0.22)
			draw_colored_polygon(PackedVector2Array([sand + Vector2(-9.0, 3.0), sand + Vector2(9.0, 3.0), sand + Vector2(3.0, -5.0), sand + Vector2(-3.0, -6.0)]), Color(0.82, 0.68, 0.42))
			draw_line(sand + Vector2(-3.0, -6.0), sand + Vector2(3.0, -5.0), Color(0.92, 0.8, 0.55), 1.0)
			# TIETYÖ-kyltti
			var sp := front + along * (length * 0.5 - 6.0) + inward * 3.0
			var sign_r := Rect2(sp + Vector2(-11.0, -16.0), Vector2(22.0, 9.0))
			draw_line(sp + Vector2(0.0, -7.0), sp + Vector2(0.0, 2.0), Color(0.5, 0.5, 0.55), 1.0)
			draw_rect(sign_r, Color(1.0, 0.82, 0.1))
			draw_rect(sign_r, Color(0.1, 0.1, 0.1), false, 1.0)
			TextFit.draw(self, font, sign_r.position + Vector2(0.0, 7.0), "TIETYÖ", sign_r.size.x, 6, Color(0.1, 0.1, 0.1))
