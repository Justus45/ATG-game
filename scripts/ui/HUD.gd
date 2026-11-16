extends CanvasLayer

@onready var instruction_label: Label = $InstructionLabel
@onready var wanted_stars: Control = $WantedStars
@onready var message_label: Label = $MessageLabel

const WeaponSlotScript := preload("res://scripts/ui/WeaponSlot.gd")
const MinimapScript := preload("res://scripts/ui/Minimap.gd")
const MoneyDisplayScript := preload("res://scripts/ui/MoneyDisplay.gd")
const ClockWidgetScript := preload("res://scripts/ui/ClockWidget.gd")
const SpeakerPortraitScript := preload("res://scripts/ui/SpeakerPortrait.gd")
const MessageBubbleScript := preload("res://scripts/ui/MessageBubble.gd")
const DialogueBoxScript := preload("res://scripts/ui/DialogueBox.gd")
const CHAR_SPRITES := preload("res://scripts/core/CharSprites.gd")
## Puhujat: nimi viestin alussa ("Kalle: ...") -> hahmotyypin rivi (characters_hd) tai "police"
const SPEAKERS := {
	"Kalle": 9, "Raili": 15, "Erkki": 6, "Baarimikko": 0, "Portsari": 12, "Välittäjä": 3,
	"Hai": 12, "Vartija": "police", "Lipunmyyjä": 3, "Jarmo": 6, "Kivinen": 6, "Poliisi": "police",
	"Pankkivirkailija": 15, "Myyjä": 0, "Hoitaja": 3,
}
## Valikon otsikon alku -> puhuja
const MENU_SPEAKERS := {
	"KALLE": "Kalle", "BAARIMIKKO": "Baarimikko", "BAARI": "Baarimikko", "RAILI": "Raili",
	"KIINTEISTÖT": "Välittäjä", "PANKKI": "Pankkivirkailija", "KAUPPA": "Myyjä", "SAIRAALA": "Hoitaja",
	"Lukko on vaihdettu": "Kivinen",
}
var _msg_portrait: Control
var _bubble: Control
var _dialog: Control          ## Stardew-tyylinen keskusteluikkuna (DialogueBox.gd)
var _slot_was_visible := true
var _menu_portrait: Control
## Oikea yläkulma ylhäältä alas: kello+sää, etsintätähdet, minikartta (Minimap.TOP_OFFSET), keikka/tarina
const CLOCK_TOP := 14.0
const STARS_TOP := 72.0

var weapon_slot: Control
var money_display: Control
var job_label: Label
var story_label: Label
var drunk_label: Label
var health_bar: Control
var _health_fill: ColorRect
var _message_id := 0
var clock_label: Label
var needs_label: Label
# Valintavalikko (pankki, kauppa, tehtävät...)
var _menu_panel: PanelContainer
var _menu_label: Label
var _menu_cb: Callable
var _menu_count := 0
var _menu_opened_ms := 0
# Tilannepaneeli (Tab) ja loppuruutu
var _status_panel: PanelContainer
var _status_label: Label
var _ending_panel: PanelContainer
var _ending_label: Label

func _ready() -> void:
	# HUD piirretään humalaefektin (DrunkFX, layer 2) päälle, jotta se pysyy terävänä
	layer = 10
	# Piilotetaan teksti alussa
	hide_instruction()
	wanted_stars.hide()
	message_label.hide()
	_layout_center_texts()
	_build_portraits()
	_build_weapon_slot()
	_build_money_display()
	_build_job_label()
	_build_story_label()
	_build_drunk_label()
	_build_health_bar()
	_build_vitutus()
	_build_clock_and_needs()
	_build_menu()
	_build_status()
	_build_ending()
	# 5 tähteä: SWAT neljännellä, armeija viidennellä tasolla
	wanted_stars.max_level = 5
	wanted_stars.offset_left = -200.0
	wanted_stars.offset_top = STARS_TOP
	wanted_stars.offset_bottom = STARS_TOP + 34.0
	var minimap := Control.new()
	minimap.set_script(MinimapScript)
	add_child(minimap)

## Varustepaikka vasempaan alakulmaan (luodaan koodilla).
func _build_weapon_slot() -> void:
	weapon_slot = Control.new()
	weapon_slot.set_script(WeaponSlotScript)
	add_child(weapon_slot)
	weapon_slot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	weapon_slot.offset_left = 20.0
	weapon_slot.offset_right = 240.0
	weapon_slot.offset_top = -138.0
	weapon_slot.offset_bottom = -20.0

## Rahalaskuri vasempaan yläkulmaan (näkyy koko ajan).
func _build_money_display() -> void:
	money_display = Control.new()
	money_display.set_script(MoneyDisplayScript)
	add_child(money_display)
	money_display.set_anchors_preset(Control.PRESET_TOP_LEFT)
	money_display.offset_left = 20.0
	money_display.offset_top = 20.0
	money_display.offset_right = 180.0
	money_display.offset_bottom = 64.0

## Työn tilanne minikartan alle oikeaan reunaan. Tyhjä teksti piilottaa sen.
## Keikka (vihreä) ja tarinan tavoite (keltainen) samassa pinossa minikartan alla,
## jolloin ne eivät voi mennä päällekkäin. Rivimäärä on rajattu, joten pino ei kasva
## viestipaneelin päälle.
const SIDE_W := 340.0          ## oikean reunan tekstipinon leveys
const SIDE_TOP := 246.0        ## minikartan alareuna (110 + 126) + väli

func _build_job_label() -> void:
	var box := VBoxContainer.new()
	box.name = "SideInfo"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -SIDE_W - 20.0
	box.offset_right = -20.0
	box.offset_top = SIDE_TOP
	box.offset_bottom = SIDE_TOP
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	job_label = _side_label(box, 15, Color(0.45, 1.0, 0.55), 2)

## Tarinan tavoite keikkatekstin alle (keltainen).
func _build_story_label() -> void:
	story_label = _side_label(get_node("SideInfo"), 14, Color(1.0, 0.85, 0.35), 3)

func _side_label(parent: Node, font_size: int, color: Color, max_lines: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.max_lines_visible = max_lines
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size = Vector2(SIDE_W, 0.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.hide()
	return l

func set_story_info(text: String) -> void:
	if story_label == null:
		return
	story_label.text = text
	story_label.visible = text != ""

## Viestit ja E-kehotukset alakeskelle, varustepaikan ja kellon yläpuolelle.
## Viesti rivittyy (max 3 riviä) ja kasvaa ylöspäin; kehotus on yksi rivi sen alla.
const MSG_W := 760.0
const PROMPT_BOTTOM := -150.0  ## varustepaikan yläreuna on -138
const MSG_BOTTOM := -194.0

func _layout_center_texts() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.08, 0.72)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8

	message_label.add_theme_stylebox_override("normal", sb)
	message_label.add_theme_font_size_override("font_size", 20)
	message_label.add_theme_color_override("font_outline_color", Color.BLACK)
	message_label.add_theme_constant_override("outline_size", 4)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.max_lines_visible = 3
	message_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	message_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	message_label.offset_left = -MSG_W * 0.5
	message_label.offset_right = MSG_W * 0.5
	message_label.offset_bottom = MSG_BOTTOM
	message_label.offset_top = MSG_BOTTOM - 44.0
	message_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	message_label.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var sb2 := sb.duplicate() as StyleBoxFlat
	sb2.bg_color = Color(0.03, 0.04, 0.08, 0.6)
	sb2.content_margin_top = 4
	sb2.content_margin_bottom = 4
	instruction_label.add_theme_stylebox_override("normal", sb2)
	instruction_label.add_theme_font_size_override("font_size", 18)
	instruction_label.add_theme_color_override("font_outline_color", Color.BLACK)
	instruction_label.add_theme_constant_override("outline_size", 4)
	instruction_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	instruction_label.clip_text = true
	instruction_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	instruction_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	instruction_label.offset_left = -MSG_W * 0.5
	instruction_label.offset_right = MSG_W * 0.5
	instruction_label.offset_bottom = PROMPT_BOTTOM
	instruction_label.offset_top = PROMPT_BOTTOM - 34.0
	instruction_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	instruction_label.grow_horizontal = Control.GROW_DIRECTION_BOTH

## Promillemittari rahalaskurin alle (näkyy vain kun on alkoholia veressä).
func _build_drunk_label() -> void:
	drunk_label = Label.new()
	drunk_label.add_theme_font_size_override("font_size", 18)
	drunk_label.add_theme_color_override("font_outline_color", Color.BLACK)
	drunk_label.add_theme_constant_override("outline_size", 5)
	drunk_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(drunk_label)
	drunk_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	drunk_label.offset_left = 20.0
	drunk_label.offset_top = 164.0   # tarvepalkit ja elämät yläpuolella
	drunk_label.offset_right = 320.0
	drunk_label.offset_bottom = 190.0
	drunk_label.hide()

## Elämäpalkki promillemittarin alle (näkyy vain kun elämiä puuttuu).
func _build_health_bar() -> void:
	health_bar = Control.new()
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(health_bar)
	health_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	health_bar.offset_left = 20.0
	health_bar.offset_top = 146.0   # tarvepalkkien alla (68-140)
	health_bar.offset_right = 180.0
	health_bar.offset_bottom = 158.0
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.65)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.add_child(bg)
	bg.size = Vector2(160.0, 12.0)
	_health_fill = ColorRect.new()
	_health_fill.color = Color(0.85, 0.15, 0.15)
	_health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.add_child(_health_fill)
	_health_fill.position = Vector2(2.0, 2.0)
	_health_fill.size = Vector2(156.0, 8.0)
	health_bar.hide()

## Tarvepalkit (nälkä, väsymys, vitutus) rahojen alle (VitutusMeter.gd).
func _build_vitutus() -> void:
	var m := Control.new()
	m.set_script(preload("res://scripts/ui/VitutusMeter.gd"))
	m.name = "VitutusMeter"
	add_child(m)
	m.set_anchors_preset(Control.PRESET_TOP_LEFT)
	m.offset_left = 20.0
	m.offset_top = 68.0
	m.offset_right = 230.0
	m.offset_bottom = 140.0


## Savukkeiden määrä varustepaikan viereen (WeaponSlot lukee sen myös itse).
func set_cigarettes(_n: int) -> void:
	if weapon_slot:
		weapon_slot.queue_redraw()


## Kello + sää oikeaan alakulmaan, nälkä/väsymys elämäpalkin alle.
func _build_clock_and_needs() -> void:
	# päivä, kello ja sää piirrettynä paneelina minikartan yläpuolelle
	var clock := Control.new()
	clock.set_script(ClockWidgetScript)
	clock.name = "ClockWidget"
	add_child(clock)
	clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	clock.offset_left = -20.0 - ClockWidgetScript.W
	clock.offset_right = -20.0
	clock.offset_top = CLOCK_TOP
	clock.offset_bottom = CLOCK_TOP + ClockWidgetScript.H
	clock.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	needs_label = Label.new()
	needs_label.add_theme_font_size_override("font_size", 16)
	needs_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.35))
	needs_label.add_theme_color_override("font_outline_color", Color.BLACK)
	needs_label.add_theme_constant_override("outline_size", 5)
	needs_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(needs_label)
	needs_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	needs_label.offset_left = 20.0
	needs_label.offset_top = 120.0
	needs_label.offset_right = 420.0
	needs_label.offset_bottom = 142.0
	needs_label.hide()


func _process(_delta: float) -> void:
	if needs_label == null:
		return
	var parts: PackedStringArray = []
	if Game.hunger >= 50.0:
		parts.append("Nälkä %d %%" % int(Game.hunger))
	if Game.fatigue >= 50.0:
		parts.append("Väsymys %d %%" % int(Game.fatigue))
	needs_label.visible = false   # tarpeet näkyvät palkkeina (VitutusMeter.gd)
	if needs_label.visible:
		needs_label.text = "  ·  ".join(parts)
		var worst := maxf(Game.hunger, Game.fatigue)
		needs_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4).lerp(Color(1.0, 0.3, 0.25), clampf((worst - 50.0) / 50.0, 0.0, 1.0)))


func _make_panel(width: float, height: float) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.1, 0.92)
	sb.border_color = Color(1.0, 0.85, 0.3, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	panel.offset_top = -height * 0.5
	panel.offset_bottom = height * 0.5
	panel.hide()
	return panel


func _make_panel_label(panel: PanelContainer, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(l)
	return l


func _build_menu() -> void:
	_menu_panel = _make_panel(560.0, 300.0)
	_menu_label = _make_panel_label(_menu_panel, 20)


func _build_status() -> void:
	_status_panel = _make_panel(900.0, 560.0)
	_status_label = _make_panel_label(_status_panel, 15)


func _build_ending() -> void:
	_ending_panel = _make_panel(760.0, 460.0)
	_ending_label = _make_panel_label(_ending_panel, 18)
	_ending_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


# ----------------------------------------------------------------------------
#  VALINTAVALIKKO
# ----------------------------------------------------------------------------
## Näyttää valikon. options = Array[String]. callback(index) kutsutaan valinnan jälkeen
## (index -1 = peruttu). Pelaaja on lukossa valikon ajan.
func show_menu(title: String, options: Array, callback: Callable) -> void:
	_menu_cb = callback
	_menu_count = mini(options.size(), 9)
	# puhuja otsikon alusta (KALLE, BAARIMIKKO...) -> iso kasvokuva oikealle
	var who := ""
	for key: String in MENU_SPEAKERS:
		if title.begins_with(key):
			who = MENU_SPEAKERS[key]
			break
	var shown := "Jarmo Kivelä" if who == "Jarmo" else who
	_dialog_say_end()
	_bubble.hide_now()
	_menu_portrait.stop()
	_msg_portrait.stop()
	if not _dialog_menu_active():
		_slot_was_visible = weapon_slot.visible
	weapon_slot.visible = false   # laatikko peittää vasemman alakulman
	_dialog.open_menu(shown, _speaker_tex(who) if who != "" else null, title, options.slice(0, _menu_count))
	_menu_opened_ms = Time.get_ticks_msec()
	hide_instruction()
	_lock_player(true)


func menu_open() -> bool:
	return _dialog_menu_active()


func _dialog_menu_active() -> bool:
	return _dialog != null and _dialog.is_menu()


## Repliikki-ikkuna pois ja E-kehote takaisin paikalleen.
func _dialog_say_end() -> void:
	if _dialog and _dialog.is_saying():
		_dialog.close()
	instruction_label.offset_bottom = PROMPT_BOTTOM
	instruction_label.offset_top = PROMPT_BOTTOM - 34.0


func _close_menu(choice: int) -> void:
	_menu_panel.hide()
	_menu_portrait.stop()
	_dialog.close()
	weapon_slot.visible = _slot_was_visible
	_lock_player(false)
	var p := get_tree().get_first_node_in_group("player")
	if p:
		var spot: Variant = p.get("nearby_portal")
		if spot != null and is_instance_valid(spot) and spot.has_method("prompt_text"):
			show_instruction(spot.prompt_text())
	var cb := _menu_cb
	_menu_cb = Callable()
	if cb.is_valid():
		cb.call(choice)


func _lock_player(value: bool) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p:
		p.set("menu_locked", value)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).physical_keycode
	if _ending_panel and _ending_panel.visible:
		if key == KEY_ESCAPE or key == KEY_ENTER or key == KEY_SPACE:
			_ending_panel.hide()
			Sfx.bgm_override = ""
			_lock_player(false)
			get_viewport().set_input_as_handled()
		return
	if _status_panel and _status_panel.visible and key == KEY_ESCAPE:
		_status_panel.hide()
		get_viewport().set_input_as_handled()
		return
	if not menu_open():
		return
	get_viewport().set_input_as_handled()
	if key >= KEY_1 and key <= KEY_9:
		var idx := int(key - KEY_1)
		if idx < _menu_count:
			_close_menu(idx)
	elif key in [KEY_UP, KEY_W]:
		_dialog.move_selection(-1)
	elif key in [KEY_DOWN, KEY_S]:
		_dialog.move_selection(1)
	elif key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		if _dialog.typing():
			_dialog.skip_typing()
		elif _menu_count > 0:
			_close_menu(_dialog.selected())
	elif key == KEY_ESCAPE or (key == KEY_E and Time.get_ticks_msec() - _menu_opened_ms > 250):
		_close_menu(-1)


## Tab: tilannepaneeli päälle/pois.
func toggle_status(text: String) -> void:
	if _status_panel.visible:
		_status_panel.hide()
		return
	_status_label.text = text
	_status_panel.show()


func show_ending(title: String, text: String) -> void:
	var stats := "Rikoksia %d  ·  pidätyksiä %d  ·  sakkoja %d  ·  keikkoja %d" % [
		int(Game.record.get("crimes", 0)), int(Game.record.get("arrests", 0)), int(Game.record.get("fines", 0)), Game.missions_done]
	_ending_label.text = title + "\n\n" + text + "\n\n" + stats + "\n\nKiitos pelaamisesta!  ATG v%s\n\n(Enter jatkaa)" % str(ProjectSettings.get_setting("application/config/version", "1.0"))
	_ending_panel.show()
	Sfx.bgm_override = "cutscene"
	_lock_player(true)


## Päivittää elämäpalkin (piilossa kun elämät ovat täynnä).
func set_health(value: float, max_value: float) -> void:
	if health_bar == null:
		return
	health_bar.visible = value < max_value
	_health_fill.size.x = 156.0 * clampf(value / max_value, 0.0, 1.0)

## Päivittää promillemittarin. stage_name = humalan taso sanoin, hangover = krapula 0..1.
func set_drunk(value: float, stage_name: String, hangover: float = 0.0) -> void:
	if drunk_label == null:
		return
	var hung := hangover > 0.01
	drunk_label.visible = value >= 0.05 or hung
	if value >= 0.05:
		drunk_label.text = "%.2f ‰  %s" % [value, stage_name]
		if hung:
			drunk_label.text += "  ·  krapula"
		var t := clampf(value / 3.0, 0.0, 1.0)
		drunk_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.5).lerp(Color(1.0, 0.35, 0.3), t))
	else:
		drunk_label.text = "Krapula %d %%" % int(ceil(hangover * 100.0))
		drunk_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.55))

func set_job_info(text: String) -> void:
	if job_label == null:
		return
	job_label.text = text
	job_label.visible = text != ""

## Päivittää rahalaskurin.
func set_money(value: int) -> void:
	if money_display:
		money_display.set_money(value)

## Kranaattien määrä varustepaikan vieressä.
func set_grenades(n: int) -> void:
	if weapon_slot:
		weapon_slot.set_grenades(n)

## Päivittää varustepaikan. id = aseen tunnus (WeaponDB), "" = ei asetta.
func set_weapon(id: String) -> void:
	if weapon_slot:
		weapon_slot.set_weapon(id)

func show_instruction(text: String) -> void:
	instruction_label.text = text
	instruction_label.show()

func hide_instruction() -> void:
	instruction_label.hide()

## Etsintäkuulutuksen taso tähtinä (0 = ei näy). 1 tähti = 1 taso.
func set_wanted(level: int) -> void:
	wanted_stars.visible = level > 0
	wanted_stars.level = level
	if level <= 0:
		wanted_stars.searching = false

## true = poliisit ovat menettäneet pelaajan näkyvistä -> tähdet vilkkuvat
func set_searching(value: bool) -> void:
	wanted_stars.searching = value

func show_message(text: String, seconds: float = 3.0) -> void:
	# "Nimi: \"repliikki\"" -> kasvokuva viestin vasemmalle puolelle, teksti ilman nimeä
	# repliikki ('Kalle: "..."') -> keskusteluikkuna kasvokuvineen alareunaan;
	# muu viesti -> ilmoituspaneeli. Valikon aikana kaikki näytetään ilmoituksena.
	var sp := _parse_speaker(text)
	message_label.hide()
	_msg_portrait.stop()
	if not sp.is_empty() and not _dialog_menu_active():
		_bubble.hide_now()
		_dialog.say(str(sp.name), sp.tex, str(sp.text), seconds)
		# E-kehote laatikon yläpuolelle
		var top: float = _dialog.say_top()
		instruction_label.offset_bottom = -top - 8.0
		instruction_label.offset_top = -top - 42.0
	else:
		_dialog_say_end()
		_bubble.show_text(text, "", seconds)
	_message_id += 1
	var id := _message_id
	await get_tree().create_timer(seconds + 0.25).timeout
	if id == _message_id:
		_bubble.hide_now()
		_dialog_say_end()


## Kasvokuvat: viestit (alakeskellä viestin vasemmalla) ja valikot (paneelin vasemmalla).
func _build_portraits() -> void:
	var size := Vector2(SpeakerPortraitScript.SIZE, SpeakerPortraitScript.SIZE + SpeakerPortraitScript.NAME_H)
	_msg_portrait = Control.new()
	_msg_portrait.set_script(SpeakerPortraitScript)
	add_child(_msg_portrait)
	_msg_portrait.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_msg_portrait.offset_right = -MSG_W * 0.5 - 12.0
	_msg_portrait.offset_left = _msg_portrait.offset_right - size.x
	_msg_portrait.offset_bottom = MSG_BOTTOM
	_msg_portrait.offset_top = MSG_BOTTOM - size.y
	# piirretty viestikupla (MessageBubble.gd) korvaa MessageLabelin
	_bubble = Control.new()
	_bubble.set_script(MessageBubbleScript)
	add_child(_bubble)
	_bubble.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bubble.offset_left = -MSG_W * 0.5
	_bubble.offset_right = MSG_W * 0.5
	_bubble.offset_bottom = MSG_BOTTOM
	_bubble.offset_top = MSG_BOTTOM - 130.0
	_dialog = Control.new()
	_dialog.set_script(DialogueBoxScript)
	add_child(_dialog)
	_dialog.chosen.connect(_on_dialog_chosen)
	_menu_portrait = Control.new()
	_menu_portrait.set_script(SpeakerPortraitScript)
	add_child(_menu_portrait)
	_menu_portrait.set_anchors_preset(Control.PRESET_CENTER)


func _on_dialog_chosen(index: int) -> void:
	if _dialog_menu_active() and index < _menu_count:
		_close_menu(index)


func _speaker_tex(name: String) -> Texture2D:
	var v: Variant = SPEAKERS.get(name, null)
	if v == null:
		return null
	if v is String:
		return CHAR_SPRITES.police(1, 0)
	if name == "Kalle":
		return CHAR_SPRITES.kalle(1, 0)
	return CHAR_SPRITES.npc(1, int(v))


## Tunnistaa puhujan: 'Kalle: "..."', 'Kalle tuhahtaa: "..."', 'Puhelin piippaa. Hai: "..."'.
## Palauttaa {name, tex, text} tai tyhjän.
func _parse_speaker(text: String) -> Dictionary:
	var i := text.find(": ")
	if i <= 0 or i > 40:
		return {}
	var prefix := text.substr(0, i)
	var dot := prefix.rfind(". ")
	if dot >= 0:
		prefix = prefix.substr(dot + 2)
	var name := prefix.split(" ")[0]
	if not SPEAKERS.has(name):
		return {}
	var rest := text.substr(i + 2).strip_edges()
	if rest.begins_with("\"") and rest.count("\"") == 2 and rest.ends_with("\""):
		rest = rest.substr(1, rest.length() - 2)
	var shown := name if name != "Jarmo" else "Jarmo Kivelä"
	return {"name": shown, "tex": _speaker_tex(name), "text": rest}
