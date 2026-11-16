extends Control
## Varustepaikka (inventory slot) ruudun vasemmassa alakulmassa.
## Näyttää kädessä olevan aseen kuvakkeen ja nimen. Tyhjänä paikka on himmeä.

const BOX := Vector2(76.0, 76.0)
const ICON_SIZE := 48.0
const GOLD := Color(0.98, 0.8, 0.15)

var weapon_id := ""
var grenades := 0

var _icon: Texture2D = null
var _style := StyleBoxFlat.new()
var _name_label: Label
var _hint_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(BOX.x, 118.0)

	_style.bg_color = Color(0.08, 0.09, 0.13, 0.8)
	_style.set_border_width_all(3)
	_style.set_corner_radius_all(8)

	_name_label = _make_label(Vector2(0.0, 79.0), 15)
	_hint_label = _make_label(Vector2(0.0, 98.0), 12)
	_hint_label.modulate = Color(1, 1, 1, 0.7)
	set_weapon("")


func _make_label(pos: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(220.0, 20.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l


func set_grenades(n: int) -> void:
	grenades = n
	queue_redraw()


## id = aseen tunnus WeaponDB:ssä, tyhjä merkkijono = ei asetta.
func set_weapon(id: String) -> void:
	weapon_id = id
	if id == "":
		_icon = null
		_name_label.text = "Ei asetta"
		_name_label.modulate = Color(1, 1, 1, 0.55)
		_hint_label.text = ""
	else:
		_icon = WeaponDB.icon(id)
		_name_label.text = WeaponDB.display_name(id)
		_name_label.modulate = Color.WHITE
		_hint_label.text = "[G] pudota   [R] ryöstä"
	queue_redraw()


func _draw() -> void:
	_style.border_color = GOLD if weapon_id != "" else Color(0.45, 0.47, 0.55)
	draw_style_box(_style, Rect2(Vector2.ZERO, BOX))
	if _icon:
		var p := (BOX - Vector2(ICON_SIZE, ICON_SIZE)) * 0.5
		draw_texture_rect(_icon, Rect2(p, Vector2(ICON_SIZE, ICON_SIZE)), false)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(8.0, 17.0), "1", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))
	if grenades > 0:
		_draw_grenades(font)
	var cx := BOX.x + 8.0 + (68.0 if grenades > 0 else 0.0)
	_draw_cigarettes(font, cx)
	var nx := cx + 68.0
	if Game.armor > 0.0 or Game.vest_carried > 0.0:
		_draw_vest(font, nx)
		nx += 68.0
	if Game.zip_ties > 0:
		_draw_ties(font, nx)


var _last_cigs := -1
var _last_armor := -1

func _process(_delta: float) -> void:
	var ar := roundi(Game.armor * 10.0) + roundi(Game.vest_carried * 10.0) * 1000 + Game.zip_ties * 1000000
	if Game.cigarettes != _last_cigs or ar != _last_armor:
		_last_cigs = Game.cigarettes
		_last_armor = ar
		queue_redraw()


## Kevlarliivi omassa paikassaan: kuvake ja kestävyyspalkki.
func _draw_vest(font: Font, x: float) -> void:
	var box := Rect2(x, 16.0, 60.0, 60.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.8)
	sb.border_color = Color(0.55, 0.65, 0.4)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	draw_style_box(sb, box)
	var worn := Game.armor > 0.0
	var k := clampf((Game.armor if worn else Game.vest_carried) / Game.ARMOR_MAX, 0.0, 1.0)
	var t := Rect2(box.position + Vector2(18.0, 8.0), Vector2(24.0, 26.0))
	var vc := Color(0.24, 0.29, 0.18) if worn else Color(0.24, 0.29, 0.18, 0.4)
	draw_rect(t, vc)
	draw_rect(Rect2(t.position.x + 7.0, t.position.y, 10.0, 6.0), Color(0.08, 0.09, 0.13))   # kaula-aukko
	draw_rect(Rect2(t.position.x, t.position.y + 16.0, t.size.x, 3.0), Color(0.1, 0.11, 0.09))
	draw_rect(Rect2(t.position.x + 8.0, t.position.y + 9.0, 8.0, 4.0), Color(0.5, 0.56, 0.38))
	draw_rect(t, Color(0, 0, 0, 0.7), false, 1.0)
	var bar := Rect2(box.position.x + 8.0, box.position.y + 36.0, 44.0, 4.0)
	draw_rect(bar, Color(0.15, 0.15, 0.18))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), Color(0.35, 0.65, 1.0) if k > 0.3 else Color(0.95, 0.4, 0.25))
	draw_rect(bar, Color(1, 1, 1, 0.45), false, 1.0)
	TextFit.draw(self, font, box.position + Vector2(0.0, 49.0), "LIIVI %d %%" % roundi(k * 100.0), box.size.x, 9, Color(1, 1, 1, 0.7))
	TextFit.draw(self, font, box.position + Vector2(0.0, 57.5), "[V] riisu" if worn else "[V] pue", box.size.x, 9, Color(1.0, 0.92, 0.55, 0.9))


## Nippusiteet omassa paikassaan: kuvake, määrä ja näppäin.
func _draw_ties(font: Font, x: float) -> void:
	var box := Rect2(x, 16.0, 60.0, 60.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.8)
	sb.border_color = Color(0.85, 0.85, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	draw_style_box(sb, box)
	var c := box.position + Vector2(18.0, 22.0)
	for k in 3:
		var o := Vector2(k * 3.0, k * 2.0)
		draw_arc(c + o, 8.0, 0.3, TAU - 0.3, 18, Color(0.95, 0.95, 0.92), 2.0)
		draw_rect(Rect2(c + o + Vector2(6.0, -2.0), Vector2(4.0, 4.0)), Color(0.75, 0.75, 0.78))
	draw_string(font, box.position + Vector2(34.0, 30.0), "x%d" % Game.zip_ties, HORIZONTAL_ALIGNMENT_LEFT, 26.0, 13, Color.WHITE)
	TextFit.draw(self, font, box.position + Vector2(0.0, 47.0), "SITEET", box.size.x, 9, Color(1, 1, 1, 0.7))
	TextFit.draw(self, font, box.position + Vector2(0.0, 57.5), "[Z] sido", box.size.x, 9, Color(1.0, 0.92, 0.55, 0.9))


## Tupakka-aski omassa inventaariopaikassaan (aseen ja kranaattien vieressä).
func _draw_cigarettes(font: Font, x: float) -> void:
	var n := Game.cigarettes
	var box := Rect2(x, 16.0, 60.0, 60.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.8)
	sb.border_color = Color(0.85, 0.3, 0.25) if n > 0 else Color(0.45, 0.47, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	draw_style_box(sb, box)
	var a := 1.0 if n > 0 else 0.35
	var pk := Rect2(box.position + Vector2(9.0, 14.0), Vector2(20.0, 28.0))
	# savukkeet sojottavat askista
	for k in 3:
		var cx := pk.position.x + 4.0 + k * 5.0
		draw_rect(Rect2(cx, pk.position.y - 6.0 + (k % 2) * 2.0, 3.0, 8.0), Color(0.96, 0.95, 0.9, a))
		draw_rect(Rect2(cx, pk.position.y - 6.0 + (k % 2) * 2.0, 3.0, 2.5), Color(0.85, 0.55, 0.25, a))
	draw_rect(pk, Color(0.95, 0.95, 0.92, a))
	draw_rect(Rect2(pk.position, Vector2(pk.size.x, 10.0)), Color(0.8, 0.12, 0.12, a))
	draw_rect(Rect2(pk.position + Vector2(0, 18), Vector2(pk.size.x, 6.0)), Color(0.1, 0.1, 0.1, a))
	draw_rect(pk, Color(0, 0, 0, 0.6 * a), false, 1.0)
	draw_string(font, box.position + Vector2(32.0, 38.0), "x%d" % n, HORIZONTAL_ALIGNMENT_LEFT, 28.0, 14, Color(1, 1, 1, maxf(a, 0.6)))
	TextFit.draw(self, font, box.position + Vector2(0.0, 56.0), "[C] sytytä/vedä" if n > 0 else "kaupasta", box.size.x, 10, Color(1, 1, 1, 0.6))


## Kranaatit aseen vieressä: pieni laatikko, kranaattikuva, määrä ja heittonäppäin.
func _draw_grenades(font: Font) -> void:
	var box := Rect2(BOX.x + 8.0, 16.0, 60.0, 60.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.8)
	sb.border_color = Color(0.55, 0.65, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	draw_style_box(sb, box)
	var c := box.position + Vector2(22.0, 30.0)
	draw_circle(c + Vector2(0, 2), 10.0, Color(0.11, 0.1, 0.14))
	draw_circle(c + Vector2(0, 2), 8.0, Color(0.33, 0.4, 0.2))
	draw_circle(c + Vector2(1.5, 4.0), 5.5, Color(0.22, 0.27, 0.13))
	draw_rect(Rect2(c.x - 8.0, c.y + 1.0, 16.0, 2.0), Color(0.22, 0.27, 0.13))
	draw_rect(Rect2(c.x - 4.5, c.y - 5.0, 3.0, 3.0), Color(0.5, 0.58, 0.3))
	draw_rect(Rect2(c.x - 4.0, c.y - 13.0, 8.0, 6.0), Color(0.11, 0.1, 0.14))
	draw_rect(Rect2(c.x - 2.5, c.y - 11.5, 5.0, 3.5), Color(0.62, 0.64, 0.7))
	draw_rect(Rect2(c.x + 3.0, c.y - 12.0, 2.5, 11.0), Color(0.38, 0.4, 0.46))
	draw_string(font, box.position + Vector2(36.0, 40.0), "x%d" % grenades, HORIZONTAL_ALIGNMENT_LEFT, 24.0, 15, Color.WHITE)
	TextFit.draw(self, font, box.position + Vector2(0.0, 56.0), "[Q]", box.size.x, 10, Color(1, 1, 1, 0.6))
