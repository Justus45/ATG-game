class_name WeaponDB
extends RefCounted
## Kaikkien aseiden tiedot yhdessä paikassa. Uusi ase = uusi rivi tähän + sprite-arkki
## (7 ruutua à 16 px: poiminta, oikea, vasen, ylös, alas, suuliekki, luoti).

const CELL := 16
## Tarkat asekuvat (<id>_hd.png, _varmuuskopio/gen_weapons_hd.py): 7 ruutua à 48 px,
## piirretään 24x24 kokoisina, jolloin ase on samassa tarkkuudessa kuin hahmot
## ja kahva osuu pelaajan käteen. Puuttuessa käytetään vanhaa 16 px arkkia.
const HD_CELL := 48
const HD_SCALE := 2
## Suun paikka (px) HeldWeapon-solmusta kullekin aseelle ja suunnalle (HD-kuvat)
const HD_MUZZLE := {
	"pistol": {"right": Vector2(10.25, 0.75), "left": Vector2(-4.25, 0.75), "up": Vector2(7.25, -1.25), "down": Vector2(4.75, 6.75)},
	"rifle": {"right": Vector2(12.25, 1.75), "left": Vector2(-6.25, 1.75), "up": Vector2(7.25, -4.25), "down": Vector2(4.25, 9.75)},
	"shotgun": {"right": Vector2(12.75, 1.75), "left": Vector2(-6.75, 1.75), "up": Vector2(7.25, -4.75), "down": Vector2(4.25, 10.25)},
	"knife": {"right": Vector2(12.25, 1.75), "left": Vector2(-6.25, 1.75), "up": Vector2(7.75, -3.25), "down": Vector2(4.25, 8.75)},
	"bottle": {"right": Vector2(12.25, 1.75), "left": Vector2(-6.25, 1.75), "up": Vector2(7.75, -3.25), "down": Vector2(4.25, 8.75)},
	"cue": {"right": Vector2(16.75, 2.25), "left": Vector2(-10.75, 2.25), "up": Vector2(7.25, -8.75), "down": Vector2(4.25, 14.25)},
	"pen": {"right": Vector2(9.25, 1.25), "left": Vector2(-3.25, 1.25), "up": Vector2(7.25, -0.25), "down": Vector2(4.75, 5.75)},
}
## Aseet joita pidetään kahdella kädellä (pelaajan asento 2), muut yhdellä (asento 1)
const TWO_HANDED := ["rifle", "shotgun", "cue"]
static var _hd_cache := {}


## Pelaajan aseasento: 1 = yhden käden ote, 2 = kahden käden ote
static func hold_pose(id: String) -> int:
	return 2 if id in TWO_HANDED else 1

const DATA := {
	"pistol": {
		"name": "Pistooli",
		"price": 120,            # asekaupan hinta (maasta löytyvä/pudotettu pistooli on ilmainen)
		"sheet": "res://assets/sprites/weapons/pistol.png",
		"fire_interval": 0.25,
		"damage": 1,
		"bullet_speed": 450.0,
		"range": 320.0,
		"spread": 0.0,
	},
	"rifle": {
		"name": "Rynnäkkökivääri AK4",
		"price": 300,            # asekaupan hinta
		"sheet": "res://assets/sprites/weapons/rifle.png",
		"fire_interval": 0.09,   # sarjatuli
		"damage": 2,
		"bullet_speed": 620.0,
		"range": 440.0,
		"spread": 0.05,          # radiaaneja, pieni hajonta
	},
	"shotgun": {
		"name": "Haulikko",
		"price": 450,
		"sheet": "res://assets/sprites/weapons/shotgun.png",
		"fire_interval": 0.85,
		"damage": 1,
		"bullet_speed": 420.0,
		"range": 190.0,
		"spread": 0.2,
		"pellets": 6,            # hauleja per laukaus
	},
	# --- Lähiaseet: melee = true. damage = iskun voima, reach = ulottuvuus (px).
	# lethal = tekee oikeaa vahinkoa (veitsi), muuten isku on kuin vahva lyönti.
	"knife": {
		"name": "Veitsi",
		"price": 0,
		"sheet": "res://assets/sprites/weapons/knife.png",
		"fire_interval": 0.4, "damage": 2, "bullet_speed": 0.0, "range": 0.0, "spread": 0.0,
		"melee": true, "reach": 24.0, "lethal": true,
	},
	"bottle": {
		"name": "Pullo",
		"price": 0,
		"sheet": "res://assets/sprites/weapons/bottle.png",
		"fire_interval": 0.5, "damage": 2, "bullet_speed": 0.0, "range": 0.0, "spread": 0.0,
		"melee": true, "reach": 24.0, "durability": 4,
	},
	"cue": {
		"name": "Biljardikeppi",
		"price": 0,
		"sheet": "res://assets/sprites/weapons/cue.png",
		"fire_interval": 0.65, "damage": 2, "bullet_speed": 0.0, "range": 0.0, "spread": 0.0,
		"melee": true, "reach": 36.0, "durability": 12,
	},
	"pen": {
		"name": "Kuulakärkikynä",
		"price": 0,
		"sheet": "res://assets/sprites/weapons/pen.png",
		"fire_interval": 0.25, "damage": 1, "bullet_speed": 0.0, "range": 0.0, "spread": 0.0,
		"melee": true, "reach": 20.0,
	},
}


static func get_data(id: String) -> Dictionary:
	return DATA.get(id, DATA["pistol"])


static func display_name(id: String) -> String:
	return get_data(id).name


static func _hd_image(id: String) -> Image:
	var key := "img_" + id
	if _hd_cache.has(key):
		return _hd_cache[key]
	var img: Image = null
	var path := "res://assets/sprites/weapons/%s_hd.png" % id
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			img = tex.get_image()
			if img and img.is_compressed():
				img.decompress()
			if img:
				img.convert(Image.FORMAT_RGBA8)
	_hd_cache[key] = img
	return img


static func _hd_tex(img: Image) -> ImageTexture:
	var t := ImageTexture.create_from_image(img)
	t.set_size_override(Vector2i(img.get_width() / HD_SCALE, img.get_height() / HD_SCALE))
	return t


## Suun paikka HeldWeapon-solmusta; null jos asetta ei ole HD-taulukossa.
static func muzzle(id: String, facing: String) -> Variant:
	if _hd_image(id) != null and HD_MUZZLE.has(id) and HD_MUZZLE[id].has(facing):
		return HD_MUZZLE[id][facing]
	return null


## Yksittäinen ruutu aseen sprite-arkista (HD: 24x24, vanha: 16x16).
static func cell(id: String, index: int) -> Texture2D:
	var img := _hd_image(id)
	if img != null:
		var key := "%s_%d" % [id, index]
		if not _hd_cache.has(key):
			_hd_cache[key] = _hd_tex(img.get_region(Rect2i(index * HD_CELL, 0, HD_CELL, HD_CELL)))
		return _hd_cache[key]
	var t := AtlasTexture.new()
	t.atlas = load(get_data(id).sheet) as Texture2D
	t.region = Rect2(index * CELL, 0, CELL, CELL)
	return t


## Kuvake poimintaan ja varustepaikkaan.
static func icon(id: String) -> Texture2D:
	var img := _hd_image(id)
	if img == null:
		return cell(id, 0)
	var key := "icon_" + id
	if not _hd_cache.has(key):
		# tiukka neliö aseen ympärille, jotta kuvake täyttää varustepaikan
		var c := img.get_region(Rect2i(0, 0, HD_CELL, HD_CELL))
		var r := c.get_used_rect()
		var s := maxi(r.size.x, r.size.y) + 4
		s += s % 2
		var sq := Image.create(s, s, false, Image.FORMAT_RGBA8)
		sq.blit_rect(c, r, Vector2i((s - r.size.x) / 2, (s - r.size.y) / 2))
		_hd_cache[key] = _hd_tex(sq)
	return _hd_cache[key]
