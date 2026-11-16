extends Control
## Puhujan kasvokuva viestin tai valikon vieressä: hahmon HD-kuva suurennettuna,
## suu liikkuu puheen tahdissa ja silmät räpsyvät. Nimi kuvan alla. Piirretään (_draw).
## HUD luo kaksi: viesteille ja valikoille.

const SIZE := 84.0                       ## kuvan sivu (px); kokonaiskorkeus SIZE + NAME_H
const NAME_H := 18.0
const SRC := Rect2(2.5, 1.0, 11.0, 11.0) ## pää ja hartiat 16x16-kuvasta
const MOUTH := Vector2(7.75, 7.05)       ## suun keskikohta 16x16-kuvassa (edestä)
const EYES := [Rect2(5.4, 4.9, 1.6, 1.1), Rect2(9.0, 4.9, 1.6, 1.1)]
const GOLD := Color(1.0, 0.82, 0.3)

var _tex: Texture2D
var _name := ""
var _talk := 0.0
var _t := 0.0
var _skin := Color(0.96, 0.74, 0.57)
var _blink_t := 2.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hide()


## tex = hahmon edestä-kuva (CharSprites), talk_seconds = kuinka kauan suu liikkuu.
func speak(speaker: String, tex: Texture2D, talk_seconds: float) -> void:
	_name = speaker
	_tex = tex
	_talk = talk_seconds
	_t = 0.0
	_skin = _sample_skin(tex)
	show()
	queue_redraw()


func stop() -> void:
	hide()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_talk = maxf(_talk - delta, 0.0)
	_blink_t -= delta
	if _blink_t < -0.12:
		_blink_t = randf_range(2.2, 4.5)
	queue_redraw()


## Ihonväri posken kohdalta (HD-kuva 32x32: piste 12,13).
func _sample_skin(tex: Texture2D) -> Color:
	if tex == null:
		return _skin
	var img := tex.get_image()
	if img == null or img.is_empty():
		return _skin
	if img.is_compressed():
		img.decompress()
	var p := Vector2i(int(12.0 * img.get_width() / 32.0), int(13.0 * img.get_height() / 32.0))
	return img.get_pixelv(p)


func _to_dest(src: Vector2, area: Rect2) -> Vector2:
	return area.position + (src - SRC.position) / SRC.size * area.size


func _draw() -> void:
	var frame := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.27, 0.38, 0.95)
	sb.border_color = GOLD if _talk > 0.0 else Color(0.85, 0.82, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	draw_style_box(sb, frame)
	var area := frame.grow(-4.0)
	if _tex:
		# pieni nyökkäys puhuessa
		var bob := Vector2(0.0, sin(_t * 9.0) * 1.0 if _talk > 0.0 else 0.0)
		var a2 := Rect2(area.position + bob, area.size)
		draw_texture_rect_region(_tex, a2, SRC)
		var px := a2.size.x / SRC.size.x      ## yksi 16-kuvan pikseli ruudulla
		# silmien räpsäys: iho silmien päälle
		if _blink_t < 0.0:
			for e: Rect2 in EYES:
				draw_rect(Rect2(_to_dest(e.position, a2), e.size * px), _skin)
		# suu: avautuu ja sulkeutuu puheen tahdissa
		if _talk > 0.0:
			var open := absf(sin(_t * 13.0)) * (0.6 + 0.4 * absf(sin(_t * 3.7)))
			if open > 0.2:
				var c := _to_dest(MOUTH, a2)
				var w := 1.9 * px
				var h := maxf(open * 1.3, 0.35) * px
				draw_rect(Rect2(c.x - w * 0.5, c.y - px * 0.3, w, px * 0.6), _skin.darkened(0.15))
				draw_rect(Rect2(c.x - w * 0.4, c.y - px * 0.2, w * 0.8, h), Color(0.35, 0.08, 0.1))
				if open > 0.6:
					draw_rect(Rect2(c.x - w * 0.3, c.y - px * 0.2, w * 0.6, px * 0.35), Color(0.95, 0.93, 0.88))
	# nimilappu
	var nl := Rect2(0.0, SIZE + 3.0, SIZE, NAME_H - 2.0)
	var ns := StyleBoxFlat.new()
	ns.bg_color = Color(0.04, 0.04, 0.07, 0.85)
	ns.set_corner_radius_all(5)
	draw_style_box(ns, nl)
	var font := ThemeDB.fallback_font
	var fs := 12
	while fs > 8 and font.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > SIZE - 6.0:
		fs -= 1
	TextFit.draw(self, font, Vector2(0.0, nl.position.y + 12.0), _name, SIZE, fs, GOLD)
