extends Node
## Humalan ruutuefektit. Player2D luo tämän itselleen lapseksi (nimi "DrunkFX").
##  - ruudun vääristymä, kaksoiskuva, värivirhe, sumeus, reunojen tummuus ja
##    silmäluomien lurppuminen voimistuvat Player2D.drunk_strength() mukana
##  - fade_to() pimentää ruudun kokonaan (sammuminen)
##
## Efektikerros on HUD:n (layer 10) alapuolella, joten HUD pysyy terävänä.

const SHADER_CODE := """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float level : hint_range(0.0, 1.0) = 0.0;
uniform float t = 0.0;
uniform float blink : hint_range(0.0, 1.0) = 0.0;
uniform float hang : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float k = level;
	vec2 uv = SCREEN_UV;

	// aaltoileva vääristymä
	uv.x += sin(uv.y * 16.0 + t * 1.7) * 0.006 * k;
	uv.y += cos(uv.x * 12.0 + t * 1.3) * 0.006 * k;

	// kaksoiskuva + sumeus
	vec2 off = vec2(sin(t * 0.8), cos(t * 0.6)) * 0.014 * k;
	float lod = k * 2.2;
	vec3 base = textureLod(screen_tex, uv, lod).rgb;
	vec3 g1 = textureLod(screen_tex, uv + off, lod).rgb;
	vec3 g2 = textureLod(screen_tex, uv - off, lod).rgb;
	vec3 col = mix(base, 0.5 * (g1 + g2), 0.55 * k);

	// värivirhe
	col.r = mix(col.r, textureLod(screen_tex, uv + off * 0.6, lod).r, 0.6 * k);
	col.b = mix(col.b, textureLod(screen_tex, uv - off * 0.6, lod).b, 0.6 * k);

	// lämmin sävy
	col *= mix(vec3(1.0), vec3(1.06, 0.97, 0.9), k);

	// reunojen tummuus
	float d = length(SCREEN_UV - vec2(0.5));
	col *= 1.0 - smoothstep(0.3, 0.85, d) * 0.6 * k;

	// krapula: haalea, harmaa kuva ja jyskyttävä päänsärky reunoilla
	float gray = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(gray) * vec3(0.98, 1.0, 0.92), 0.4 * hang);
	float throb = 0.5 + 0.5 * sin(t * 2.6);
	col *= 1.0 - smoothstep(0.25, 0.8, d) * (0.18 + 0.22 * throb) * hang;

	// silmäluomet (ylä- ja alareunasta keskelle)
	float lid = abs(SCREEN_UV.y - 0.5) * 2.0;
	col *= 1.0 - smoothstep(1.0 - blink, 1.0 - blink + 0.2, lid);

	COLOR = vec4(col, 1.0);
}
"""

var _k := 0.0      # pehmennetty humalan voimakkuus 0..1
var _h := 0.0      # pehmennetty krapula 0..1
var _t := 0.0
var _rect: ColorRect
var _mat: ShaderMaterial
var _black: ColorRect


func _ready() -> void:
	# Humalaefekti
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	layer.add_child(_rect)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.visible = false

	# Täysi pimennys (HUD:n päällä, asekaupan/baarin oven häivytyksen alla)
	var black_layer := CanvasLayer.new()
	black_layer.layer = 60
	add_child(black_layer)
	_black = ColorRect.new()
	_black.color = Color(0.0, 0.0, 0.0, 0.0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black_layer.add_child(_black)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	var p := get_parent()
	var target := 0.0
	if p and p.has_method("drunk_strength"):
		target = p.drunk_strength()
	_k = lerpf(_k, target, clampf(delta * 1.5, 0.0, 1.0))
	var hang_target := 0.0
	if p and "hangover" in p:
		hang_target = p.hangover
	_h = lerpf(_h, hang_target, clampf(delta * 1.5, 0.0, 1.0))
	_rect.visible = _k > 0.015 or _h > 0.015
	if not _rect.visible:
		return
	_t += delta
	# Silmät lurpahtavat kiinni silloin tällöin, kun on tosi kännissä
	var blink := pow(maxf(sin(_t * 0.5 + sin(_t * 0.13) * 2.0), 0.0), 14.0)
	blink *= smoothstep(0.55, 1.0, _k) * 0.95
	_mat.set_shader_parameter("level", _k)
	_mat.set_shader_parameter("t", _t)
	_mat.set_shader_parameter("blink", blink)
	_mat.set_shader_parameter("hang", _h)


## Pimentää ruudun (alpha 1) tai palauttaa sen (alpha 0) annetussa ajassa.
func fade_to(alpha: float, seconds: float) -> void:
	var tw := create_tween()
	tw.tween_property(_black, "color:a", alpha, seconds)
	await tw.finished
