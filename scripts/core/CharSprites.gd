extends RefCounted
## Yksityiskohtaiset hahmokuvat (32x32 px / ruutu), jotka piirretään pelissä
## 16x16-kokoisina (ImageTexture.set_size_override). Näin hahmoissa on
## kaksinkertainen tarkkuus, mutta mittasuhteet, offsetit ja osumalaatikot
## pysyvät täsmälleen ennallaan.
##
## Kuvat tuottaa _varmuuskopio/gen_characters_hd.py.
## Sarakkeet: 0 vasen, 1 alas, 2 ylös, 3 oikea. Rivit: tyyppi * 3 + askel.

const NPC_SHEET: Texture2D = preload("res://assets/sprites/player/characters_hd.png")
const POLICE_SHEET: Texture2D = preload("res://assets/sprites/police/police_officer_hd.png")
## Pelaajan aseasennot: rivit 0-2 yksi käsi, 3-5 kaksi kättä (sarakkeet kuten yllä)
const ARMED_PATH := "res://assets/sprites/player/player_armed_hd.png"
## Pelaajan hahmon ensimmäinen rivi characters.png:ssä
const PLAYER_ROW := 12
const SRC := 32
const DST := 16

static var _cache := {}
static var _imgs := {}


static func frame(sheet: Texture2D, col: int, row: int) -> Texture2D:
	var key := Vector3i(sheet.get_instance_id(), col, row)
	if _cache.has(key):
		return _cache[key]
	var img: Image = _imgs.get(sheet.get_instance_id())
	if img == null:
		img = sheet.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		_imgs[sheet.get_instance_id()] = img
	var sub := img.get_region(Rect2i(col * SRC, row * SRC, SRC, SRC))
	var t := ImageTexture.create_from_image(sub)
	t.set_size_override(Vector2i(DST, DST))
	t.set_meta("cs_col", col)   # 2 = selin: ei silmiä (räpsytys ohitetaan)
	_cache[key] = t
	return t


# ----------------------------------------------------------------------------
#  BAARIN HENKILÖKUNTA (staff_hd.png, _varmuuskopio/gen_staff_hd.py)
# ----------------------------------------------------------------------------
## Asut: 0 tarjoilija (valkoinen paita, musta liivi, rusetti), 1 ovimies (musta), 2 kokki (valkoinen)
## Hahmotyypit 0-2 (samat kasvot kuin NPC-tyypeillä 0-2). Rivit: (asu*3 + tyyppi)*3 + askel.
const STAFF_PATH := "res://assets/sprites/player/staff_hd.png"
const WAITER := 0
const BOUNCER := 1
const CHEF := 2
static var _staff_sheet: Texture2D = null


static func staff(outfit: int, kind: int, col: int, step: int = 0) -> Texture2D:
	if _staff_sheet == null and ResourceLoader.exists(STAFF_PATH):
		_staff_sheet = load(STAFF_PATH) as Texture2D
	if _staff_sheet == null:
		return npc(col, kind * 3 + step)   # kuvaa ei vielä tuotu: tavallinen NPC
	return frame(_staff_sheet, col, (outfit * 3 + kind) * 3 + step)


# ----------------------------------------------------------------------------
#  SILMIEN RÄPSYTYS JA ÄÄRIVIIVA (IdleLife.gd, baarin piirrot)
# ----------------------------------------------------------------------------
static var _blink_cache := {}
static var _mask_cache := {}


## Sama kuva silmät kiinni (null, jos silmiä ei löydy, esim. selkä tai kypärä).
static func blink(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var id := tex.get_instance_id()
	if _blink_cache.has(id):
		return _blink_cache[id]
	var out: Texture2D = null
	if not (tex.has_meta("cs_col") and int(tex.get_meta("cs_col")) == 2):
		var img := tex.get_image()
		if img:
			img = img.duplicate() as Image
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			if _close_eyes(img):
				var t := ImageTexture.create_from_image(img)
				t.set_size_override(Vector2i(tex.get_size()))
				out = t
	_blink_cache[id] = out
	return out


## Hahmon siluetti valkoisena (ääriviivaa varten: piirretään 1 px siirroilla sävytettynä).
static func mask(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var id := tex.get_instance_id()
	if _mask_cache.has(id):
		return _mask_cache[id]
	var out: Texture2D = null
	var img := tex.get_image()
	if img:
		img = img.duplicate() as Image
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var a := img.get_pixel(x, y).a
				img.set_pixel(x, y, Color(1, 1, 1, 1.0 if a > 0.5 else 0.0))
		var t := ImageTexture.create_from_image(img)
		t.set_size_override(Vector2i(tex.get_size()))
		out = t
	_mask_cache[id] = out
	return out


static func _skin(c: Color) -> bool:
	if c.a < 0.5:
		return false
	var r := c.r8
	var g := c.g8
	var b := c.b8
	return (r > 190 and g > 110 and r > b + 45) or (r >= 100 and r <= 175 and g >= 55 and g <= 115 and b >= 30 and b <= 80 and r > g and g > b)


static func _lum(c: Color) -> float:
	return 0.3 * c.r8 + 0.59 * c.g8 + 0.11 * c.b8


## Etsii pupillit (tumma piste, alla ihoa, yllä värikäs iiris / valkuainen) ja piirtää
## silmäluomen: yläpuoli iholla, pupillin rivi tummalla viivalla.
static func _close_eyes(img: Image) -> bool:
	if img.get_height() != 32:
		return false
	var pupils: Array[Vector2i] = []
	for y in range(7, 16):
		for x in range(1, img.get_width() - 1):
			var c := img.get_pixel(x, y)
			if c.a < 0.5 or absi(c.r8 - 26) + absi(c.g8 - 22) + absi(c.b8 - 34) > 28:
				continue
			var below := img.get_pixel(x, y + 1)
			var above := img.get_pixel(x, y - 1)
			if not _skin(below):
				continue
			if above.a < 0.5 or _skin(above) or _lum(above) < 62.0:
				continue
			pupils.append(Vector2i(x, y))
	if pupils.is_empty():
		return false
	for p in pupils:
		var skin := img.get_pixel(p.x, p.y + 1)
		var lid := Color(skin.r * 0.45, skin.g * 0.4, skin.b * 0.4, 1.0)
		for xx in range(p.x - 1, p.x + 2):
			var a := img.get_pixel(xx, p.y - 1)
			if a.a > 0.5 and (not _skin(a) or _lum(a) > _lum(skin) + 15.0):
				img.set_pixel(xx, p.y - 1, skin)
		for xx in range(p.x - 1, p.x + 2):
			if img.get_pixel(xx, p.y).a > 0.5:
				img.set_pixel(xx, p.y, lid)
	return true


## Jalankulkijat, baarin asiakkaat, katujengit ja pelaaja (characters.png:n järjestys)
static func npc(col: int, row: int) -> Texture2D:
	return frame(NPC_SHEET, col, row)


static func police(col: int, row: int) -> Texture2D:
	return frame(POLICE_SHEET, col, row)


## Pelaajan animaatiot aseasennossa (pose 1 tai 2). frames = Player.tscn:n alkuperäiset ruudut.
static func armed_frames(frames: SpriteFrames, pose: int) -> SpriteFrames:
	var out := frames.duplicate() as SpriteFrames
	if not ResourceLoader.exists(ARMED_PATH):
		return upgrade_frames(frames)
	var sheet := load(ARMED_PATH) as Texture2D
	for anim in out.get_animation_names():
		for i in out.get_frame_count(anim):
			var t := out.get_frame_texture(anim, i)
			if t is AtlasTexture:
				var r: Rect2 = (t as AtlasTexture).region
				var col := int(round(r.position.x / 17.0))
				var row := int(round(r.position.y / 17.0))
				var tex: Texture2D
				if row >= PLAYER_ROW and row < PLAYER_ROW + 3:
					tex = frame(sheet, col, (pose - 1) * 3 + row - PLAYER_ROW)
				else:
					tex = npc(col, row)
				out.set_frame(anim, i, tex, out.get_frame_duration(anim, i))
	return out


# ----------------------------------------------------------------------------
#  PELAAJAN ULKOASU: vaatteiden värit ja kevlarliivi
#  Lähtökuva on aina alkuperäinen (harmaa paita, mustat housut), joten paita, housut
#  ja liivi tunnistetaan sen väreistä luotettavasti ja väritetään sävyt säilyttäen.
# ----------------------------------------------------------------------------
static var _look_cache := {}
const VEST_BASE := Color(0.2, 0.24, 0.15)
const VEST_STRAP := Color(0.09, 0.1, 0.08)
const SHIRT_REF := 142.0     ## alkuperäisen paidan keskisävyn kirkkaus (0-255)
const PANTS_REF := 46.0      ## housujen keskisävy


## Alkuperäisen paidan harmaa (sinertävä, vähän kylläinen) – ei ihoa, housuja eikä ääriviivaa.
static func _shirt(c: Color) -> bool:
	var l := _lum(c)
	var br := c.b8 - c.r8
	return l > 75.0 and l < 215.0 and br >= 6 and br <= 32 and absi(c.g8 - c.r8) <= 12


## Alkuperäiset tummat housut (vyötärö mukaan, solki ja kengät eivät).
static func _pants(c: Color) -> bool:
	var l := _lum(c)
	var br := c.b8 - c.r8
	return l > 28.0 and l < 85.0 and br >= 4 and br <= 20 and absi(c.g8 - c.r8) <= 6


static func _tint(target: Color, c: Color, ref: float) -> Color:
	var k := clampf(_lum(c) / ref, 0.55, 1.55)
	return Color(minf(target.r * k, 1.0), minf(target.g * k, 1.0), minf(target.b * k, 1.0), 1.0)


## Hahmokuva annetuilla vaatteilla (a = 0: alkuperäinen väri) ja liivillä. Välimuistissa.
static func outfit(tex: Texture2D, shirt: Color, pants: Color, vest: bool, mask: bool = false, style: String = "") -> Texture2D:
	if tex == null:
		return tex
	var key := "%d|%s|%s|%d|%d|%s" % [tex.get_instance_id(), shirt.to_html(), pants.to_html(), int(vest), int(mask), style]
	if _look_cache.has(key):
		return _look_cache[key]
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var sc := float(h) / 32.0
	var col := int(tex.get_meta("cs_col", 1))
	# liivi: edestä ja takaa vain vartalo (hihat näkyvät), sivulta koko torso
	var vx0 := 0
	var vx1 := w - 1
	if col == 1 or col == 2:
		vx0 = int(10.0 * sc)
		vx1 = int(21.0 * sc)
	var vy0 := int(17.0 * sc)
	var vy1 := int(24.0 * sc)
	for y in range(int(16.0 * sc), int(29.0 * sc)):
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			if y <= vy1 and _shirt(c):
				if vest and y >= vy0 and x >= vx0 and x <= vx1:
					var v := _tint(VEST_BASE, c, SHIRT_REF)
					if y == vy1 - int(2.0 * sc) or y == vy0 + int(1.0 * sc):
						v = VEST_STRAP   # tarranauhat / olkahihnat
					img.set_pixel(x, y, v)
				elif style == "suit" or style == "dress_tie":
					img.set_pixel(x, y, _suit_px(style, col, float(x) / sc, float(y) / sc, c))
				elif shirt.a > 0.0:
					img.set_pixel(x, y, _tint(shirt, c, SHIRT_REF))
			elif y >= int(25.0 * sc) and pants.a > 0.0 and _pants(c):
				img.set_pixel(x, y, _tint(pants, c, PANTS_REF))
	if mask:
		_balaclava(img, col, sc)
	var out := ImageTexture.create_from_image(img)
	out.set_size_override(Vector2i(tex.get_size()))
	if tex.has_meta("cs_col"):
		out.set_meta("cs_col", tex.get_meta("cs_col"))
	_look_cache[key] = out
	return out


## Kommandopipo: pään iho mustaksi neulokseksi, silmäaukko jää (edestä ja sivulta).
const KNIT := Color(0.14, 0.14, 0.16)

static func _balaclava(img: Image, col: int, sc: float) -> void:
	var w := img.get_width()
	var s0 := int(8.0 * sc)
	var s1 := int(11.0 * sc)
	for y in range(int(2.0 * sc), int(17.0 * sc)):
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < 0.5 or not _skin(c):
				continue
			if y >= s0 and y <= s1:
				if col == 1 and x >= int(10.0 * sc) and x <= int(21.0 * sc):
					continue
				if col == 0 and x >= int(8.0 * sc) and x <= int(16.0 * sc):
					continue
				if col == 3 and x >= int(15.0 * sc) and x <= int(23.0 * sc):
					continue
			var l := _lum(c)
			var k := 0.45 if l < 120.0 else clampf(l / 180.0, 0.5, 1.4)
			var v := Color(KNIT.r * k, KNIT.g * k, KNIT.b * k, 1.0)
			if int(y / sc) % 3 == 0:
				v = v.darkened(0.2)   # neulosraidat
			img.set_pixel(x, y, v)


## Pelaajan animaatiot uusilla vaatteilla / liivillä / pipolla.
static func outfit_frames(frames: SpriteFrames, shirt: Color, pants: Color, vest: bool, mask: bool = false, style: String = "") -> SpriteFrames:
	var out := frames.duplicate() as SpriteFrames
	for anim in out.get_animation_names():
		for i in out.get_frame_count(anim):
			out.set_frame(anim, i, outfit(out.get_frame_texture(anim, i), shirt, pants, vest, mask, style), out.get_frame_duration(anim, i))
	return out


## Puku ("suit": takki, valkoinen kauluspaita ja kravatti) tai pelkkä kauluspaita kravatilla
## ("dress_tie"). gx, gy = paikka 32 px ruudukossa, c = alkuperäisen paidan sävy.
const SUIT_JACKET := Color(0.13, 0.14, 0.22)
const SUIT_SHIRT := Color(0.93, 0.93, 0.95)
const SUIT_TIE := Color(0.62, 0.08, 0.12)

static func _suit_px(style: String, col: int, gx: float, gy: float, c: Color) -> Color:
	var white := _tint(SUIT_SHIRT, c, SHIRT_REF)
	var jacket := _tint(SUIT_JACKET, c, SHIRT_REF)
	var x := int(gx)
	var y := int(gy)
	if col == 1:
		# kravatti keskellä, solmu ylhäällä
		if (x == 15 or x == 16) and y >= 18 and y <= 23:
			return SUIT_TIE.lightened(0.2) if y == 18 else SUIT_TIE
		if style == "dress_tie":
			return white
		# kauluspaidan V-aukko takin rinnuksissa
		var half := 3.0 - float(y - 17) * 0.75
		return white if absf(gx + 0.5 - 16.0) <= half else jacket
	if style == "dress_tie":
		return white
	if col == 2:
		return white if y <= 17 else jacket   # kauluksen reuna niskassa
	# sivukuva: kaulus ja paidan etureuna kasvojen puolella
	if y <= 18 and ((col == 0 and x <= 13) or (col == 3 and x >= 18)):
		return white
	return jacket


## Vaihtaa AnimatedSprite2D:n vanhat 16 px characters.png-ruudut (1 px väli)
## vastaaviin tarkkoihin kuviin.
static func upgrade_frames(frames: SpriteFrames) -> SpriteFrames:
	var out := frames.duplicate() as SpriteFrames
	for anim in out.get_animation_names():
		for i in out.get_frame_count(anim):
			var t := out.get_frame_texture(anim, i)
			if t is AtlasTexture:
				var r: Rect2 = (t as AtlasTexture).region
				var col := int(round(r.position.x / 17.0))
				var row := int(round(r.position.y / 17.0))
				out.set_frame(anim, i, npc(col, row), out.get_frame_duration(anim, i))
	return out


## Istuva hahmo: vain yläruumis (pää ja torso), jalat rajattu pois (terassin tuolit, pöydät).
static var _seat_cache := {}

static func seated(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var id := tex.get_instance_id()
	if _seat_cache.has(id):
		return _seat_cache[id]
	var out: Texture2D = null
	var img := tex.get_image()
	if img and img.get_height() == 32:
		img = img.duplicate() as Image
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var sub := img.get_region(Rect2i(0, 0, 32, 23))
		var t := ImageTexture.create_from_image(sub)
		t.set_size_override(Vector2i(16, 12))
		if tex.has_meta("cs_col"):
			t.set_meta("cs_col", tex.get_meta("cs_col"))
		out = t
	_seat_cache[id] = out
	return out



# ----------------------------------------------------------------------------
#  KALLE (kalle_hd.png, _varmuuskopio/gen_kalle_hd.py): skinhead nahkatakissa, tatuoinnit
# ----------------------------------------------------------------------------
const KALLE_PATH := "res://assets/sprites/player/kalle_hd.png"
static var _kalle_sheet: Texture2D = null

static func kalle(col: int, step: int = 0) -> Texture2D:
	if _kalle_sheet == null and ResourceLoader.exists(KALLE_PATH):
		_kalle_sheet = load(KALLE_PATH) as Texture2D
	if _kalle_sheet == null:
		return npc(col, 9 + step)   # kuvaa ei vielä tuotu
	return frame(_kalle_sheet, col, step)


# ----------------------------------------------------------------------------
#  KARTANON JUHLAVIERAAT: naishahmo (tyyppi 1) bikineissä, eri hiusten- ja bikinien väreillä
# ----------------------------------------------------------------------------
static var _lady_cache := {}
const SKIN_TONE := Color(0.965, 0.737, 0.569)


static func lady(col: int, step: int, hair: Color, dress: Color) -> Texture2D:
	var key := "%d|%d|%s|%s" % [col, step, hair.to_html(), dress.to_html()]
	if _lady_cache.has(key):
		return _lady_cache[key]
	var base := npc(col, 3 + step)
	if base == null:
		return null
	var img := base.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var sc := float(img.get_height()) / 32.0
	for y in img.get_height():
		var ry := float(y) / sc
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var h := c.h * 360.0
			if ry < 20.0 and c.s >= 0.55 and ((h >= 5.0 and h <= 40.0) or c.v < 0.4):
				img.set_pixel(x, y, _tint(hair, c, 150.0))   # hiukset
			elif ry >= 17.0 and ry < 29.0:
				# bikinit: paita ja farkut iholle, yläosa ja alaosa uimapuvun värillä
				var red := c.s > 0.45 and (h >= 345.0 or h <= 10.0) and c.v > 0.45
				var jeans := h >= 220.0 and h <= 245.0 and c.s > 0.3 and c.v > 0.45
				var belt := int(ry) == 25 and absi(c.r8 - c.g8) < 12 and absi(c.g8 - c.b8) < 20 and c.v > 0.2
				var outl := c.r8 == 37 and c.g8 == 36 and c.b8 == 66
				if red or jeans or belt or outl:
					var top := ry >= 19.0 and ry < 21.0
					var bottom := ry >= 25.0 and ry < 27.0
					var ref := 107.0 if red else 94.0
					if outl and not (top or bottom):
						img.set_pixel(x, y, Color8(105, 60, 53))
					elif top or bottom:
						img.set_pixel(x, y, _tint(dress, c, ref))
					else:
						img.set_pixel(x, y, _tint(SKIN_TONE, c, ref))
	var t := ImageTexture.create_from_image(img)
	t.set_size_override(Vector2i(base.get_size()))
	t.set_meta("cs_col", col)
	_lady_cache[key] = t
	return t


# ----------------------------------------------------------------------------
#  KAMPAUKSET (torin kampaamo, Game.HAIRS): piirretään pelaajan pään päälle omana
#  kuvanaan (Player2D.HairView). Pään muoto luetaan animaatioruudusta, joten kampaus
#  seuraa kävelyä ja suuntaa. Kuvassa on HAIR_PAD rivin verran tilaa pään yläpuolella.
# ----------------------------------------------------------------------------
const HAIR_PAD := 12
static var _hair_cache := {}


static func hair_overlay(tex: Texture2D, col: int, style: String, hc: Color) -> Texture2D:
	if tex == null or style == "" or style == "bald":
		return null
	var key := "%d|%d|%s|%s" % [tex.get_instance_id(), col, style, hc.to_html()]
	if _hair_cache.has(key):
		return _hair_cache[key]
	var src := tex.get_image()
	if src == null:
		return null
	if src.is_compressed():
		src = src.duplicate() as Image
		src.decompress()
	if src.get_format() != Image.FORMAT_RGBA8:
		src = src.duplicate() as Image
		src.convert(Image.FORMAT_RGBA8)
	var sc := float(src.get_height()) / 32.0
	# pään rivikohtaiset reunat (rivit 0..16)
	var xmin: Array[int] = []
	var xmax: Array[int] = []
	var top := -1
	for y in 17:
		var a := -1
		var b := -1
		for x in 32:
			var p := src.get_pixel(mini(int(x * sc), src.get_width() - 1), mini(int(y * sc), src.get_height() - 1))
			if p.a > 0.5:
				if a < 0:
					a = x
				b = x
		xmin.append(a)
		xmax.append(b)
		if a >= 0 and top < 0:
			top = y
	if top < 0:
		_hair_cache[key] = null
		return null
	var t := top
	var fy := mini(t + 5, 16)
	var cx := (xmin[fy] + xmax[fy]) * 0.5
	var fmin := 99
	var fmax := -1
	for y in range(t + 3, mini(t + 7, 17)):
		if xmin[y] >= 0:
			fmin = mini(fmin, xmin[y])
			fmax = maxi(fmax, xmax[y])
	var front := col == 1
	var back := col == 2
	var side := not front and not back
	var f := -1.0 if col == 0 else 1.0     # sivukuvassa kasvojen suunta
	var hair := {}
	for y in range(-HAIR_PAD, 32):
		for x in 32:
			var in_head := y >= 0 and y <= 16 and xmin[y] >= 0 and x >= xmin[y] and x <= xmax[y]
			var behind := (float(x) - cx) * f < -1.0     # sivukuvassa takaraivon puoli
			var short := false
			if in_head:
				short = y <= t + 3 \
					or (back and y <= t + 9 and x >= fmin and x <= fmax) \
					or (side and behind and y <= t + 8) \
					or (front and y <= t + 5 and (x <= xmin[y] + 1 or x >= xmax[y] - 1))
			elif y == t - 1 and x > xmin[t] and x < xmax[t]:
				short = true
			var on := false
			match style:
				"short", "platinum":
					on = short
				"banana":
					on = short
					var e := 0.0
					if front:
						e = pow((x - cx) / 7.5, 2.0) + pow((y - (t - 1.5)) / 4.0, 2.0)
						on = on or (e <= 1.0 and y <= t + 2)
					elif back:
						e = pow((x - cx) / 7.5, 2.0) + pow((y - t) / 3.5, 2.0)
						on = on or e <= 1.0
					else:
						e = pow((x - (cx + f * 3.5)) / 8.5, 2.0) + pow((y - (t - 2.5)) / 4.5, 2.0)
						var tip := pow((x - (cx + f * 10.0)) / 2.4, 2.0) + pow((y - (t + 0.5)) / 1.8, 2.0)
						on = on or (e <= 1.0 and y <= t + 2) or tip <= 1.0
				"mohawk":
					if front or back:
						on = absf(x - cx) <= 1.5 and y >= t - 6 and y <= t + 4
					else:
						var spike := 5 + (1 if x % 3 == 0 else 0)
						on = x >= xmin[t + 1] and x <= xmax[t + 1] and y >= t - spike and y <= t + 1
				"long":
					on = short
					if front:
						on = on or (y >= t + 3 and y <= 20 and ((x >= fmin - 1 and x <= fmin + 1) or (x >= fmax - 1 and x <= fmax + 1)))
					elif back:
						on = on or (y >= t and y <= 20 and x >= fmin and x <= fmax and (y <= 16 or (x > fmin and x < fmax)))
					else:
						on = on or (y >= t and y <= 20 and behind and x >= fmin - 1 and x <= fmax + 1 \
							and (y <= 16 or absf(float(x) - (cx - f * 4.0)) <= 3.5))
				"afro":
					var d := Vector2(x - cx, y - (t + 6.0)).length()
					on = d <= 10.5 and y <= t + 11
					if on and in_head and y >= t + 5:
						if front and x >= xmin[y] + 2 and x <= xmax[y] - 2:
							on = false
						elif side and (float(x) - cx) * f >= -1.0:
							on = false
			if on:
				hair[Vector2i(x, y)] = true
	var out := Image.create(32, 32 + HAIR_PAD, false, Image.FORMAT_RGBA8)
	var light := hc.lightened(0.35)
	var dark := hc.darkened(0.3)
	var line := hc.darkened(0.7)
	for k: Vector2i in hair:
		var x := k.x
		var y := k.y
		var c := hc
		if not hair.has(Vector2i(x, y - 1)):
			c = light
		elif not hair.has(Vector2i(x, y + 1)) or not hair.has(Vector2i(x + 1, y)):
			c = dark
		# rasvatun banaanin kampausraidat ja kiilto
		if style == "banana" and y < t and (x + y) % 4 == 0:
			c = light.lightened(0.2)
		if style == "afro" and (x * 7 + y * 3) % 5 == 0:
			c = dark
		var edge := false
		for dv: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := k + dv
			var n_head := n.y >= 0 and n.y <= 16 and xmin[n.y] >= 0 and n.x >= xmin[n.y] and n.x <= xmax[n.y]
			if not hair.has(n) and not n_head:
				edge = true
		if edge:
			c = line
		var oy := y + HAIR_PAD
		if x >= 0 and x < 32 and oy >= 0 and oy < 32 + HAIR_PAD:
			out.set_pixel(x, oy, c)
	var res := ImageTexture.create_from_image(out)
	_hair_cache[key] = res
	return res


# ----------------------------------------------------------------------------
#  HATUT JA LASIT (Vaate-Vuokko, Game.HATS / Game.GLASSES): piirretään kampauksen päälle
#  samaan tapaan (Player2D.HairView). Pään muoto ja silmät luetaan animaatioruudusta.
# ----------------------------------------------------------------------------
static var _acc_cache := {}


static func accessory_overlay(tex: Texture2D, col: int, hat: String, hat_c: Color, glasses: String, gl_c: Color) -> Texture2D:
	if tex == null or ((hat == "" or hat == "hat_none") and (glasses == "" or glasses == "gl_none")):
		return null
	var key := "%d|%d|%s|%s|%s|%s" % [tex.get_instance_id(), col, hat, hat_c.to_html(), glasses, gl_c.to_html()]
	if _acc_cache.has(key):
		return _acc_cache[key]
	var src := tex.get_image()
	if src == null:
		return null
	if src.is_compressed():
		src = src.duplicate() as Image
		src.decompress()
	if src.get_format() != Image.FORMAT_RGBA8:
		src = src.duplicate() as Image
		src.convert(Image.FORMAT_RGBA8)
	var sc := float(src.get_height()) / 32.0
	var px := func(x: int, y: int) -> Color:
		return src.get_pixel(clampi(int(x * sc), 0, src.get_width() - 1), clampi(int(y * sc), 0, src.get_height() - 1))
	var xmin: Array[int] = []
	var xmax: Array[int] = []
	var t := -1
	for y in 17:
		var a := -1
		var b := -1
		for x in 32:
			if (px.call(x, y) as Color).a > 0.5:
				if a < 0:
					a = x
				b = x
		xmin.append(a)
		xmax.append(b)
		if a >= 0 and t < 0:
			t = y
	if t < 0:
		_acc_cache[key] = null
		return null
	var fy := mini(t + 5, 16)
	var cx := (xmin[fy] + xmax[fy]) * 0.5
	var hl := xmin[mini(t + 3, 16)]
	var hr := xmax[mini(t + 3, 16)]
	var f := -1 if col == 0 else 1
	var side := col == 0 or col == 3
	var out := Image.create(32, 32 + HAIR_PAD, false, Image.FORMAT_RGBA8)
	var put := func(x: int, y: int, c: Color) -> void:
		var oy := y + HAIR_PAD
		if x >= 0 and x < 32 and oy >= 0 and oy < 32 + HAIR_PAD:
			out.set_pixel(x, oy, c)
	# --- LASIT (piirretään ensin, hattu tulee päälle) ---
	if glasses != "" and glasses != "gl_none" and col != 2:
		var ey0 := t + 6
		var ey1 := t + 7
		var eyes: Array[int] = []
		for y in range(ey0, ey1 + 1):
			if y > 16 or xmin[y] < 0:
				continue
			for x in range(xmin[y] + 1, xmax[y]):
				var c: Color = px.call(x, y)
				if c.a > 0.5 and (c.r + c.g + c.b) / 3.0 < 0.45:
					eyes.append(x)
		var lenses: Array = []   # [x0, x1]
		if col == 1:
			var lx := []
			var rx := []
			for x in eyes:
				if float(x) < cx:
					lx.append(x)
				else:
					rx.append(x)
			if lx.is_empty():
				lx = [int(cx) - 4, int(cx) - 3]
			if rx.is_empty():
				rx = [int(cx) + 3, int(cx) + 4]
			lenses = [[int(lx.min()) - 1, int(lx.max()) + 1], [int(rx.min()) - 1, int(rx.max()) + 1]]
		else:
			if eyes.is_empty():
				eyes = [int(cx) + f * 3]
			lenses = [[int(eyes.min()) - 1, int(eyes.max()) + 1]]
		var frame := gl_c.darkened(0.2) if glasses != "gl_aviator" else Color(0.85, 0.7, 0.3)
		for L: Array in lenses:
			for x in range(int(L[0]), int(L[1]) + 1):
				for y in range(ey0 - 1, ey1 + 2):
					var edge: bool = x == int(L[0]) or x == int(L[1]) or y == ey0 - 1 or y == ey1 + 1
					match glasses:
						"gl_sun":
							put.call(x, y, Color(0.05, 0.05, 0.07) if not (x == int(L[0]) + 1 and y == ey0) else Color(0.45, 0.5, 0.6))
						"gl_nerd":
							if edge:
								put.call(x, y, frame)
						"gl_aviator":
							if edge and y != ey1 + 1:
								put.call(x, y, frame)
							elif not edge or y == ey1 + 1:
								if not (y == ey1 + 1 and (x == int(L[0]) or x == int(L[1]))):
									put.call(x, y, Color(0.25, 0.16, 0.08) if y <= ey0 else Color(0.4, 0.25, 0.12))
						_:
							if edge:
								put.call(x, y, frame)
		# silta ja sangat
		if col == 1 and lenses.size() == 2:
			for x in range(int(lenses[0][1]) + 1, int(lenses[1][0])):
				put.call(x, ey0, frame)
		elif side:
			var back_x := int(cx) - f * 2
			var x0 := int(lenses[0][0]) if f > 0 else int(lenses[0][1])
			var step := -f
			var x := x0
			var guard := 0
			while x != back_x and guard < 14:
				put.call(x, ey0, frame)
				x += step
				guard += 1
	# --- HATUT ---
	if hat != "" and hat != "hat_none":
		var hc := hat_c
		var hd := hat_c.darkened(0.35)
		var hlt := hat_c.lightened(0.25)
		var line := hat_c.darkened(0.7)
		var cells := {}
		var add := func(x: int, y: int, c: Color) -> void:
			cells[Vector2i(x, y)] = c
		var in_head := func(x: int, y: int) -> bool:
			return y >= 0 and y <= 16 and xmin[y] >= 0 and x >= xmin[y] and x <= xmax[y]
		match hat:
			"hat_cap", "hat_beanie":
				var low := t + 3 if hat == "hat_cap" else t + 4
				for y in range(t - 1, low + 1):
					for x in range(hl - 1, hr + 2):
						if in_head.call(x, y) or (y == t - 1 and x > xmin[t] and x < xmax[t]):
							add.call(x, y, hlt if y <= t else hc)
				if hat == "hat_cap":
					if col == 1:
						for x in range(hl, hr + 1):
							add.call(x, t + 4, hd)
					elif side:
						var fx := hr if f > 0 else hl
						for k in range(0, 6):
							add.call(fx + f * k, t + 3, hd)
							add.call(fx + f * k, t + 4, hd)
					add.call(int(cx), t - 1, hd)   # nappi
				else:
					for x in range(hl - 1, hr + 2):
						if in_head.call(x, low - 1) or in_head.call(x, low):
							add.call(x, low - 1, hd)   # käänne
					for dy in range(-2, 1):
						for dx in range(-1, 2):
							if absi(dx) + absi(dy + 1) <= 1:
								add.call(int(cx) + dx, t - 2 + dy, Color(0.95, 0.95, 0.95))   # tupsu
			"hat_fedora", "hat_tophat", "hat_cowboy":
				var crown_top := t - 3 if hat != "hat_tophat" else t - 8
				var cw := 6 if hat != "hat_tophat" else 5
				var ccx := int(cx) if not side else int(cx) - f
				for y in range(crown_top, t + 3):
					for x in range(ccx - cw, ccx + cw + 1):
						var c := hc
						if y == crown_top:
							c = hlt
							if hat == "hat_cowboy" and absi(x - ccx) <= 1:
								continue   # painauma
						if y >= t + 1 and y <= t + 2 and hat != "hat_cowboy":
							c = Color(0.08, 0.08, 0.1) if hat != "hat_tophat" else Color(0.55, 0.1, 0.12)   # nauha
						add.call(x, y, c)
				var bw := 3 if hat == "hat_fedora" else (2 if hat == "hat_tophat" else 5)
				for x in range(hl - bw, hr + bw + 1):
					add.call(x, t + 3, hd)
				if hat == "hat_cowboy":
					for k in [0, 1]:
						add.call(hl - bw + k, t + 2, hd)
						add.call(hr + bw - k, t + 2, hd)
				else:
					for x in range(hl - bw + 1, hr + bw):
						add.call(x, t + 4, hd.darkened(0.2))
		# ääriviiva hatun reunoille (ei pään päälle)
		for k: Vector2i in cells:
			var c: Color = cells[k]
			var edge := false
			for dv: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
				var n: Vector2i = k + dv
				if not cells.has(n) and not in_head.call(n.x, n.y):
					edge = true
			put.call(k.x, k.y, line if edge else c)
	var res := ImageTexture.create_from_image(out)
	_acc_cache[key] = res
	return res
