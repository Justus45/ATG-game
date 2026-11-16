extends RefCounted
## Tarkat (2x) kuvat, jotka piirretään alkuperäisen kokoisina.
## <polku>.png  ->  <polku>_hd.png (tehty _varmuuskopio/gen_world_hd.py:llä)
##
## Palautettu ImageTexture raportoi koon 1x-kuvan mukaan (set_size_override), joten
## osumalaatikot, offsetit ym. pysyvät ennallaan. 1x-kuva tallennetaan metatietoon
## "lo_image" pikselianalyysejä varten (CarFX etsii siitä renkaat).

static var _cache := {}


static func make(hd: Image, lo: Image) -> ImageTexture:
	var t := ImageTexture.create_from_image(hd)
	t.set_size_override(lo.get_size())
	t.set_meta("lo_image", lo)
	return t


static func _rgba(img: Image) -> Image:
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Korvaa tekstuurin HD-versiolla, jos sellainen on. Toimii myös AtlasTexturelle,
## joka kattaa koko kuvan (esim. car.tscn:n animaatioruudut).
static func upgrade(tex: Texture2D) -> Texture2D:
	if tex == null:
		return tex
	var src: Texture2D = tex
	if tex is AtlasTexture:
		var at := tex as AtlasTexture
		if at.atlas == null or at.region.position != Vector2.ZERO or at.region.size != at.atlas.get_size():
			return tex
		src = at.atlas
	var path := src.resource_path
	if path == "" or not path.ends_with(".png") or path.ends_with("_hd.png"):
		return tex
	if _cache.has(path):
		return _cache[path]
	var out: Texture2D = tex
	var hd_path := path.trim_suffix(".png") + "_hd.png"
	if ResourceLoader.exists(hd_path):
		var hd_tex := load(hd_path) as Texture2D
		if hd_tex:
			var hd_img := _rgba(hd_tex.get_image())
			var lo_img := _rgba(src.get_image())
			if hd_img and lo_img:
				out = make(hd_img, lo_img)
	_cache[path] = out
	return out


static func upgrade_frames(frames: SpriteFrames) -> SpriteFrames:
	if frames == null:
		return frames
	var out := frames.duplicate() as SpriteFrames
	for anim in out.get_animation_names():
		for i in out.get_frame_count(anim):
			var t := out.get_frame_texture(anim, i)
			var u := upgrade(t)
			if u != t:
				out.set_frame(anim, i, u, out.get_frame_duration(anim, i))
	return out
