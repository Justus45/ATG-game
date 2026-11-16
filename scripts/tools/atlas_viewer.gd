extends Node2D
## Apuscripti: näyttää atlaksen ruudukolla ja (sarake,rivi)-numeroilla.
## Käyttö: uusi scene -> Node2D + tämä scripti + Camera2D (zoomaa/siirrä).
## Aseta texture = tilemap_packed.png ja aja scene. Lue koordinaatit
## ja päivitä ne city_generator.gd:n const-arvoihin.

@export var texture: Texture2D
@export var tile := 16
@export var sep := 1
@export var zoom := 3.0


func _draw() -> void:
	if texture == null:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(zoom, zoom))
	draw_texture(texture, Vector2.ZERO)
	var stride := tile + sep
	var font := ThemeDB.fallback_font
	var cols := (texture.get_width() + sep) / stride
	var rows := (texture.get_height() + sep) / stride
	for y in rows:
		for x in cols:
			var p := Vector2(x * stride, y * stride)
			draw_rect(Rect2(p, Vector2(tile, tile)), Color(1, 0, 0, 0.6), false, 0.5)
			draw_string(font, p + Vector2(1, 7), "%d,%d" % [x, y],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Color.YELLOW)


func _process(_delta: float) -> void:
	# Camera2D-liike nuolinäppäimillä
	var cam := get_viewport().get_camera_2d()
	if cam:
		cam.position += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * 10.0
