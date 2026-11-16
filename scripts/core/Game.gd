extends Node
## Pelin pysyvä tila. Autoload "Game" (project.godot -> [autoload]).
##  - kello ja vuorokausi (päivä / ilta / yö), sää (selkeä / sade / lumi)
##  - talous: pankkitili, viikkovuokra, jääkaappi
##  - pelaajan tarpeet: nälkä ja väsymys
##  - rikosrekisteri ja maine (poliisi, baarin kanta-asiakkaat, rikollisporukka)
##  - baarin kieltolista ja "tutut kasvot" (kaunaa kantavat rähinöitsijät)
##  - päätarina (Story.gd): velka Haille, sitten alamaailman tai baarin tie.
##  - tallennus (F5) ja lataus (F9), uusi peli (Shift+F9). Esc: taukovalikko (PauseMenu.gd).
##
## Pelin alussa Game liittää kenttään ajonaikaiset järjestelmät (JobManager,
## Atmosphere, StreetEvents, BarGames) ja lataa tallennuksen, jos sellainen on.

const SAVE_PATH := "user://atg_save.json"

## -- SÄÄDÄ NÄITÄ --
const GAME_MIN_PER_SEC := 2.0        ## pelin minuutteja yhtä oikeaa sekuntia kohden (1 h = 30 s)
const START_HOUR := 9
const RENT := 150                    ## viikkovuokra ($)
const RENT_EVERY_DAYS := 7
const HUNGER_PER_MIN := 100.0 / 1500.0    ## nälkä täyttyy ~25 pelitunnissa
const FATIGUE_PER_MIN := 100.0 / 1900.0   ## väsymys täyttyy ~32 pelitunnissa
const BAR_PRICE := 5000              ## oman baarin hinta (päätavoite)
const OWN_BAR_INCOME := 80           ## oma baari tuottaa päivittäin tilille ($)
const WEEKDAYS := ["Ma", "Ti", "Ke", "To", "Pe", "La", "Su"]
const GRUDGE_NAMES := ["Rami", "Jarkko", "Tero", "Make", "Pertti", "Jone", "Sakke", "Veikko", "Kimmo", "Arto"]

signal hour_changed(hour: int)
signal day_changed(day: int)
signal weather_changed(weather: String)

# --- aika ja sää ---
var day := 1
var minutes := float(START_HOUR * 60)
var weather := "clear"              # "clear", "cloudy", "fog", "rain", "storm", "snow"
var weather_k := 0.0                # 0..1 sään voimakkuus (pehmeä siirtymä)
var _weather_next := 40.0           # pelin minuutteja seuraavaan säänvaihtoon
var _weather_target := "clear"      # sää vaihtuu: vanha hiipuu ensin, sitten uusi voimistuu
var snow_cover := 0.0               # 0..1 maahan kertynyt lumi (sulaa pois sateen loputtua)
var wind := 0.3                     # -1..1 tuulen suunta ja voima (sateen kulma, hiutaleiden ajautuminen)
var _wt := 0.0
var _last_hour := -1

# --- talous ja koti ---
var bank := 0
var rent_due_day := RENT_EVERY_DAYS + 1
var rent_overdue := false
var fridge := 2                     # ruoka-annoksia jääkaapissa

# --- tarpeet ---
var hunger := 10.0                  # 0..100
var fatigue := 5.0                  # 0..100

# --- rikosrekisteri ja maine ---
var record := {"arrests": 0, "fines": 0, "crimes": 0, "jail_seconds": 0}
var rep := {"police": 0, "regulars": 0, "criminals": 0}   # -100..100

# --- baari ---
var bar_ban_until := -1.0           # absoluuttinen pelin minuutti
var bar_strikes := 0
var grudges: Array = []             # [{"name": String, "row": int, "beaten": int}]

# --- aseet ja tavoite ---
var stored_weapon := ""             # putkassa säilytykseen otettu ase
var owns_bar := false
## Vitutus 0..100: nousee liiasta työnteosta ja rikoksista, laskee tupakalla ja unella
var vitutus := 0.0
## Savukkeet taskussa (inventaario, oma paikka aseen vieressä). Askissa 20.
var cigarettes := 0
## Juoksuostosten saalis (tuote-id:t): kulkee mukana, kotona ruoat jääkaappiin ja esineet lattialle
var loot: Array = []
## Kevlarliivin kestävyys (0 = ei liiviä päällä)
var armor := 0.0
## Riisuttu kevlarliivi mukana (kestävyys, 0 = ei riisuttua liiviä). V riisuu / pukee.
var vest_carried := 0.0
## Asekaappi (koti / kartano): säilötyt aseet (WeaponDB-id:t), GunCabinet.gd
var gun_cabinet: Array = []
## Paikalleen kuuluvat esineet (baarin biljardikeppi ja pullo, kotien keittiöveitset):
## tag -> "out" (kädessä tai maassa), "gone" (kaapissa/takavarikossa/säilössä), "broken".
## Puuttuva tag = esine on omalla paikallaan. Estää esineiden monistumisen.
var fixtures: Dictionary = {}
## Nippusiteet (asekauppa): Z sitoo lähellä olevan ohikulkijan tai ryöstössä kaupan myyjän
var zip_ties := 0
const ZIP_TIE_PACK := 5
const ZIP_TIE_PRICE := 30
const ARMOR_MAX := 12.0
const ARMOR_ABSORB := 0.6       ## liivi ottaa tämän osuuden iskusta / luodista
const VEST_PRICE := 250
## Vaatteet (torin vaatekauppias): id -> [nimi, hinta, väri]. Väri a = 0 -> alkuperäinen.
const SHIRTS := {
	"grey": ["Harmaa t-paita", 0, Color(0, 0, 0, 0)],
	"red_hood": ["Punainen huppari", 45, Color(0.72, 0.13, 0.13)],
	"white": ["Valkoinen kauluspaita", 60, Color(0.86, 0.86, 0.83)],
	"leather": ["Musta nahkatakki", 120, Color(0.2, 0.18, 0.19)],
	"track_blue": ["Sininen tuulipuku", 70, Color(0.16, 0.3, 0.68)],
	"yellow": ["Keltainen collegepaita", 40, Color(0.88, 0.72, 0.12)],
	"army": ["Maastotakki", 80, Color(0.33, 0.38, 0.2)],
	"pink": ["Pinkki kauluspaita", 55, Color(0.92, 0.45, 0.62)],
	"dress_tie": ["Valkoinen kauluspaita ja kravatti", 90, Color(0.93, 0.93, 0.95)],
	"suit": ["Puvun takki (kauluspaita ja kravatti alla)", 260, Color(0.13, 0.14, 0.22)],
}
## Paidat, jotka piirretään omalla tyylillään (CharSprites._suit_px) eikä pelkällä värillä
const SHIRT_STYLES := ["dress_tie", "suit"]
## Koko puku kerralla (takki, kauluspaita, kravatti ja puvun housut)
const SUIT_SET_PRICE := 380
## Hatut ja lasit (Vaate-Vuokko): id -> [nimi, hinta, väri]
const HATS := {
	"hat_none": ["Ei hattua", 0, Color(0, 0, 0, 0)],
	"hat_cap": ["Punainen lippis", 25, Color(0.78, 0.12, 0.12)],
	"hat_beanie": ["Sininen pipo tupsulla", 20, Color(0.18, 0.32, 0.7)],
	"hat_fedora": ["Harmaa borsalino", 70, Color(0.36, 0.36, 0.4)],
	"hat_tophat": ["Silinteri", 120, Color(0.1, 0.1, 0.12)],
	"hat_cowboy": ["Cowboyhattu", 85, Color(0.55, 0.36, 0.18)],
}
const GLASSES := {
	"gl_none": ["Ei laseja", 0, Color(0, 0, 0, 0)],
	"gl_sun": ["Mustat aurinkolasit", 40, Color(0.05, 0.05, 0.07)],
	"gl_nerd": ["Paksusankaiset silmälasit", 35, Color(0.08, 0.08, 0.1)],
	"gl_aviator": ["Pilottilasit", 65, Color(0.85, 0.7, 0.3)],
}
const PANTS := {
	"black": ["Mustat housut", 0, Color(0, 0, 0, 0)],
	"jeans": ["Farkut", 50, Color(0.2, 0.31, 0.55)],
	"grey_track": ["Harmaat verkkarit", 30, Color(0.48, 0.48, 0.52)],
	"khaki": ["Khakihousut", 45, Color(0.58, 0.5, 0.34)],
	"red_track": ["Punaiset verkkarit", 35, Color(0.58, 0.1, 0.1)],
	"suit_pants": ["Puvun housut", 110, Color(0.14, 0.15, 0.21)],
}
var outfit := {"shirt": "grey", "pants": "black", "hat": "hat_none", "glasses": "gl_none"}
var clothes_owned: Array = ["grey", "black", "hat_none", "gl_none"]
## Kampaukset (torin kampaamo): id -> [nimi, hinta, hiusten väri]. Piirto: CharSprites.hair_overlay
const HAIRS := {
	"bald": ["Kalju (oma tyyli)", 0, Color(0, 0, 0, 0)],
	"short": ["Lyhyt siili", 25, Color(0.34, 0.21, 0.12)],
	"platinum": ["Platinasiili", 45, Color(0.92, 0.9, 0.82)],
	"banana": ["Banaanikampaus (rasvattu)", 90, Color(0.1, 0.09, 0.13)],
	"mohawk": ["Punainen irokeesi", 70, Color(0.85, 0.12, 0.12)],
	"long": ["Pitkä blondi tukka", 80, Color(0.86, 0.68, 0.34)],
	"afro": ["Afro", 85, Color(0.2, 0.12, 0.08)],
}
var hair := "bald"
var hair_owned: Array = ["bald"]
## Torin Auto-Makelta ostettu klassikko (musta 80-luvun baijerilainen coupe)
var owns_classic := false
const CLASSIC_PRICE := 9500
## Mopo poistettiin pelistä: vanhan tallennuksen mopo hyvitetään tilille
const OLD_MOPED_REFUND := 600
## Torin superauto (Lamborghini-tyylinen Furia V12)
var owns_supercar := false
const SUPERCAR_PRICE := 25000
## Kartano (kiinteistövälitys): ei vuokraa, koti siirtyy kartanoon, Sakke muuttaa vanhaan kämppään
var owns_manor := false
const MANOR_PRICE := 30000
const MANOR_INCOME := 250            ## kartanon sijoitukset ja vuokralaiset tuottavat päivittäin tilille
## Pankkikeikka (Kallen viimeinen keikka): C4-panokset, kommandopipo
var c4 := 0
var has_mask := false
var mask_on := false            ## pipo päässä (keikan ajan), ei tallenneta
var heist_active := false       ## keikka käynnissä: kaupungin poliisi ei reagoi
const C4_PRICE := 500
const MASK_PRICE := 40
## Oman baarin tila: nimi, päivitykset, suosio, kunto... (BarBusiness.gd)
var bar_data: Dictionary = {}
var finished := false
var missions_done := 0
var story: Dictionary = {}          # tarinan tila (Story.gd)
var phone_heard: Array = []         # kuunnellut lankapuhelimen viestit (Home.gd)
## true kun kenttä on palautettu tallennuksesta: alkuintroa ei näytetä
var loaded_from_save := false
## Aloitusvalikko näytetään kerran, kun peli käynnistetään
var _show_main_menu := true

var _attached_scene: Node = null
var _pending_load: Dictionary = {}
var _hud_hint_shown := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Fysiikka samaan tahtiin näytön kanssa: auto, pelaaja ja kamera liikkuvat fysiikka-
	# askelissa, joten 60 Hz fysiikka 144 Hz näytöllä näytti nykivältä ajaessa.
	var hz := roundi(DisplayServer.screen_get_refresh_rate())
	if hz >= 50:
		Engine.physics_ticks_per_second = clampi(hz, 60, 240)
		Engine.max_physics_steps_per_frame = 12
	_add_key("save_game", KEY_F5)
	_add_key("load_game", KEY_F9)
	_add_key("full_map", KEY_M)
	_add_key("debug_weather", KEY_F7)
	_add_key("debug_time", KEY_F8)
	# Tallennusta ei ladata automaattisesti: aloitusvalikko (MainMenu.gd) kysyy jatketaanko vai aloitetaanko uusi


func _add_key(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


# ----------------------------------------------------------------------------
#  PÄÄSILMUKKA
# ----------------------------------------------------------------------------
func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.get_node_or_null("City") == null:
		return
	if scene != _attached_scene:
		_attach(scene)
		return
	_attach_idle_life(delta)
	_update_bgm_auto()
	if get_tree().paused:
		return
	_advance(delta * GAME_MIN_PER_SEC)
	_update_weather(delta)


## Kaupungin taustamusiikki: soi, kun pelaaja kävelee ulkona (ei autossa, ei sisällä, ei jahdissa).
func _update_bgm_auto() -> void:
	var p := player() as Node2D
	var want := ""
	if p and p.visible and not player_indoors():
		var driving := false
		for c in get_tree().get_nodes_in_group("player_vehicles"):
			if flag(c, "is_driving"):
				driving = true
				break
		var pm := get_tree().get_first_node_in_group("police_manager")
		var chased: bool = pm != null and int(pm.get("wanted")) > 0
		if not driving and not chased:
			want = "city"
	Sfx.set_bgm_auto(want)


## Hahmojen elävyys (IdleLife.gd: silmien räpsytys, syvä hengitys paikallaan seistessä).
## Liitetään kerran sekunnissa kaikkiin hahmoihin, joilta se vielä puuttuu.
const IDLE_LIFE := preload("res://scripts/core/IdleLife.gd")
var _life_scan := 0.0

func _attach_idle_life(delta: float) -> void:
	_life_scan -= delta
	if _life_scan > 0.0:
		return
	_life_scan = 1.0
	var nodes: Array = get_tree().get_nodes_in_group("shootable")
	nodes.append_array(get_tree().get_nodes_in_group("player"))
	for n in nodes:
		if not is_instance_valid(n) or not (n is Node2D) or flag(n, "is_car"):
			continue
		if n.has_node("IdleLife"):
			continue
		var spr: Variant = null
		for key in ["animated_sprite", "visual", "sprite"]:
			var v: Variant = n.get(key)
			if v is Sprite2D or v is AnimatedSprite2D:
				spr = v
				break
		if spr == null or n.has_meta("no_idle_life"):
			continue
		# vain hahmot (16x16 hahmokuvat), ei autoja tai muita kuvia
		var tex: Texture2D = null
		if spr is Sprite2D:
			tex = (spr as Sprite2D).texture
		else:
			var a := spr as AnimatedSprite2D
			if a.sprite_frames and a.sprite_frames.has_animation(a.animation):
				tex = a.sprite_frames.get_frame_texture(a.animation, a.frame)
		if tex == null:
			continue
		if tex.get_size() != Vector2(16, 16):
			n.set_meta("no_idle_life", true)
			continue
		var life := IDLE_LIFE.new()
		life.name = "IdleLife"
		life.body = n
		life.sprite = spr
		n.add_child(life)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save_game"):
		if can_save():
			save_game()
			msg("Peli tallennettu (F5). F9 lataa, Shift+F9 aloittaa uuden pelin.", 2.5)
		else:
			msg("Tallennus ei onnistu nyt (jahti, putka tai keikka kesken).", 2.0)
	elif event.is_action_pressed("load_game"):
		if event is InputEventKey and (event as InputEventKey).shift_pressed:
			new_game()
		else:
			load_game()
	elif event.is_action_pressed("debug_weather"):
		# Testinäppäin: seuraava sää heti (selkeä -> pilvinen -> sumu -> sade -> myrsky -> lumi)
		var order := ["clear", "cloudy", "fog", "rain", "storm", "snow"]
		var nxt: String = order[(order.find(_weather_target) + 1) % order.size()]
		_weather_target = nxt
		weather = nxt
		weather_k = 0.0 if nxt == "clear" else 0.6
		_weather_next = randf_range(120.0, 300.0)
		msg("Testi: sää = %s (F7 seuraava)" % weather_name(), 2.0)
	elif event.is_action_pressed("debug_time"):
		# Testinäppäin: kello 2 tuntia eteenpäin
		skip_minutes(120.0, 0.0)
		msg("Testi: kello %s (F8 +2 h)" % clock_text(), 1.5)


## Kenttä latautui: luodaan ajonaikaiset järjestelmät ja palautetaan tallennus.
func _attach(scene: Node) -> void:
	_attached_scene = scene
	var failed: PackedStringArray = []
	for path: String in ["res://scripts/world/JobManager.gd", "res://scripts/world/Story.gd", "res://scripts/world/Atmosphere.gd",
			"res://scripts/core/Impacts.gd",
			"res://scripts/world/StreetEvents.gd", "res://scripts/world/BarGames.gd",
			"res://scripts/ui/CityMap.gd", "res://scripts/ui/PauseMenu.gd"]:
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			push_error("ATG: skriptiä ei voitu ladata: " + path)
			failed.append(path.get_file())
			continue
		var n: Node = script.new()
		n.name = path.get_file().get_basename()
		scene.add_child(n)
	if not failed.is_empty():
		msg("VIRHE: nämä skriptit eivät latautuneet: %s. Katso Godotin Output-paneeli." % ", ".join(failed), 8.0)
		return
	if _show_main_menu:
		_show_main_menu = false
		var mm_script := load("res://scripts/ui/MainMenu.gd") as Script
		if mm_script and mm_script.can_instantiate():
			var mm: Node = mm_script.new()
			mm.name = "MainMenu"
			scene.add_child(mm)
			return
	if not _pending_load.is_empty():
		_apply_save(_pending_load)
		_pending_load = {}
		msg("Tallennus ladattu: päivä %d." % day, 3.0)
	elif not _hud_hint_shown:
		_hud_hint_shown = true   # tarinan alku: Story.gd näyttää Hain viestit


# ----------------------------------------------------------------------------
#  AIKA
# ----------------------------------------------------------------------------
func _advance(game_minutes: float) -> void:
	minutes += game_minutes
	hunger = minf(hunger + HUNGER_PER_MIN * game_minutes, 100.0)
	fatigue = minf(fatigue + FATIGUE_PER_MIN * game_minutes, 100.0)
	while minutes >= 1440.0:
		minutes -= 1440.0
		day += 1
		_on_new_day()
	var h := hour()
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)
	_weather_next -= game_minutes
	if _weather_next <= 0.0:
		_roll_weather()


## Siirtää kelloa eteenpäin (esim. nukkuminen). Tarpeet kasvavat vain osittain.
func skip_minutes(game_minutes: float, needs_scale: float = 0.3) -> void:
	var h0 := hunger
	var f0 := fatigue
	_advance(game_minutes)
	hunger = minf(h0 + (hunger - h0) * needs_scale, 100.0)
	fatigue = f0


func hour() -> int:
	return int(minutes / 60.0) % 24


## Absoluuttinen aika pelin minuutteina (pelin alusta).
func now() -> float:
	return float(day - 1) * 1440.0 + minutes


func clock_text() -> String:
	return "%02d:%02d" % [hour(), int(minutes) % 60]


func weekday() -> String:
	return WEEKDAYS[(day - 1) % 7]


## "päivä", "ilta" tai "yö"
func period() -> String:
	var h := hour()
	if h >= 6 and h < 17:
		return "päivä"
	if h >= 17 and h < 22:
		return "ilta"
	return "yö"


func is_night() -> bool:
	return period() == "yö"


## Pimeys 0..1 (Atmosphere piirtää tämän mukaan).
func darkness() -> float:
	var m := minutes
	# aamu 5-7 vaalenee, ilta 18-21.5 pimenee
	if m < 300.0:
		return 1.0
	if m < 420.0:
		return 1.0 - (m - 300.0) / 120.0
	if m < 1080.0:
		return 0.0
	if m < 1290.0:
		return (m - 1080.0) / 210.0
	return 1.0


## Onko kello välillä [open, close) (tunteina, voi mennä keskiyön yli).
func is_open(open_h: int, close_h: int) -> bool:
	var h := hour()
	if open_h == close_h:
		return true
	if open_h < close_h:
		return h >= open_h and h < close_h
	return h >= open_h or h < close_h


func _on_new_day() -> void:
	day_changed.emit(day)
	if owns_bar:
		var biz := get_tree().get_first_node_in_group("bar_business")
		if biz and biz.has_method("end_of_day"):
			biz.end_of_day()
		else:
			bank += OWN_BAR_INCOME
			msg("Oma baari tuotti %d $ tilillesi." % OWN_BAR_INCOME, 3.0)
	if owns_manor:
		# oma kartano: ei vuokraa, sijoitukset tuottavat ja hovimestari täyttää jääkaapin
		bank += MANOR_INCOME
		fridge = maxi(fridge, 4)
		msg("Hovimestari Hemmo: kartanon tuotto %d $ tilille, jääkaappi täytetty." % MANOR_INCOME, 3.5)
	elif day >= rent_due_day and not rent_overdue:
		_charge_rent()
	elif rent_overdue:
		msg("Vuokra on yhä maksamatta! Koti on lukossa, kunnes maksat (%d $)." % RENT, 3.5)


func _charge_rent() -> void:
	var p := player()
	var wallet: int = p.money if p else 0
	if bank + wallet < RENT:
		rent_overdue = true
		msg("Vuokranantaja vaihtoi lukot: vuokra %d $ maksamatta. Maksa kotisi ovella." % RENT, 4.0)
		return
	var from_bank := mini(bank, RENT)
	bank -= from_bank
	if RENT - from_bank > 0 and p:
		p.add_money(-(RENT - from_bank))
	rent_due_day += RENT_EVERY_DAYS
	msg("Viikkovuokra %d $ maksettu. Seuraava eräpäivä: päivä %d." % [RENT, rent_due_day], 3.0)


## Maksaa myöhässä olevan vuokran lompakosta. Palauttaa true jos onnistui.
func pay_overdue_rent() -> bool:
	var p := player()
	if p == null:
		return false
	var total: int = p.money + bank
	if total < RENT:
		return false
	var from_wallet := mini(p.money, RENT)
	p.add_money(-from_wallet)
	bank -= RENT - from_wallet
	rent_overdue = false
	rent_due_day = day + RENT_EVERY_DAYS
	return true


# ----------------------------------------------------------------------------
#  SÄÄ
# ----------------------------------------------------------------------------
## Sääkone: todennäköisyydet riippuvat nykyisestä säästä (sade tulee pilvisestä,
## ukkonen sateesta, sumu yöllä). Vaihto tapahtuu pehmeästi.
const WEATHER_NEXT := {
	"clear": [["clear", 25], ["cloudy", 35], ["fog", 10], ["rain", 22], ["snow", 8]],
	"cloudy": [["clear", 25], ["cloudy", 20], ["rain", 30], ["snow", 12], ["fog", 8], ["storm", 5]],
	"fog": [["clear", 35], ["cloudy", 40], ["fog", 15], ["rain", 10]],
	"rain": [["cloudy", 35], ["rain", 25], ["storm", 20], ["clear", 15], ["fog", 5]],
	"storm": [["rain", 55], ["cloudy", 30], ["storm", 15]],
	"snow": [["snow", 35], ["cloudy", 40], ["clear", 20], ["fog", 5]],
}


func _roll_weather() -> void:
	_weather_next = randf_range(90.0, 220.0)
	var opts: Array = WEATHER_NEXT.get(_weather_target, WEATHER_NEXT["clear"])
	var total := 0
	for o: Array in opts:
		total += int(o[1])
		if o[0] == "fog" and is_night():
			total += 10
	var r := randi_range(0, total - 1)
	var w := "clear"
	for o: Array in opts:
		var weight := int(o[1]) + (10 if o[0] == "fog" and is_night() else 0)
		if r < weight:
			w = str(o[0])
			break
		r -= weight
	if w == _weather_target:
		return
	_weather_target = w
	# Säänmuutoksista ei näytetä ilmoituksia: sää näkyy kellon vieressä ja ruudulla.


## Pehmeä siirtymä: vanha sää hiipuu (weather_k -> 0), sitten uusi voimistuu (-> 1).
func _update_weather(delta: float) -> void:
	_wt += delta
	if weather != _weather_target:
		weather_k = move_toward(weather_k, 0.0, delta * 0.15)
		if weather_k <= 0.0:
			weather = _weather_target
			weather_changed.emit(weather)
	else:
		weather_k = move_toward(weather_k, 0.0 if weather == "clear" else 1.0, delta * 0.1)
	# tuuli kääntyilee hitaasti, myrskyssä puuskittain
	wind = 0.35 * sin(_wt * 0.05) + 0.25 * sin(_wt * 0.17 + 1.3)
	if weather == "storm":
		wind += 0.4 * sin(_wt * 0.9) * weather_k
	# lumi kertyy maahan ja sulaa hitaasti
	if weather == "snow":
		snow_cover = minf(snow_cover + delta * weather_k / 90.0, 1.0)
	else:
		snow_cover = maxf(snow_cover - delta / (240.0 if weather != "rain" and weather != "storm" else 80.0), 0.0)


## Voimakkuus 0..1 puuskineen (sade ei ole tasaista).
func _gust() -> float:
	return clampf(0.8 + 0.2 * sin(_wt * 0.31) * sin(_wt * 0.13 + 2.0), 0.0, 1.0)


func rain_amount() -> float:
	match weather:
		"rain":
			return weather_k * _gust()
		"storm":
			return weather_k
	return 0.0


func snow_amount() -> float:
	return weather_k * _gust() if weather == "snow" else 0.0


func fog_amount() -> float:
	match weather:
		"fog":
			return weather_k
		"storm":
			return weather_k * 0.3
		"rain":
			return weather_k * 0.15
		"snow":
			return weather_k * 0.25
	return 0.0


## Pilvisyys 0..1: päivälläkin kuva tummuu ja harmaantuu.
func cloud_amount() -> float:
	match weather:
		"cloudy":
			return weather_k * 0.45
		"fog":
			return weather_k * 0.5
		"rain":
			return weather_k * 0.75
		"storm":
			return weather_k
		"snow":
			return weather_k * 0.55
	return 0.0


func weather_name() -> String:
	match weather:
		"cloudy":
			return "pilvistä"
		"fog":
			return "sumua"
		"rain":
			return "sadetta"
		"storm":
			return "ukkosmyrsky"
		"snow":
			return "lumisade"
	return "selkeää"


## Auton huippunopeuden kerroin.
func car_speed_mult() -> float:
	var m := 1.0
	match weather:
		"rain":
			m = lerpf(1.0, 0.88, weather_k)
		"storm":
			m = lerpf(1.0, 0.8, weather_k)
		"snow":
			m = lerpf(1.0, 0.72, weather_k)
		"fog":
			m = lerpf(1.0, 0.92, weather_k)
	return m * lerpf(1.0, 0.85, snow_cover)


## Auton pito 0..1 (pienempi = luistaa enemmän).
func road_grip() -> float:
	var g := 1.0
	match weather:
		"rain":
			g = lerpf(1.0, 0.55, weather_k)
		"storm":
			g = lerpf(1.0, 0.45, weather_k)
		"snow":
			g = lerpf(1.0, 0.3, weather_k)
	return minf(g, lerpf(1.0, 0.4, snow_cover))


## Näkyvyyskerroin poliisille ja todistajille (sää + pimeys).
func visibility() -> float:
	var v := 1.0
	match weather:
		"cloudy":
			v = lerpf(1.0, 0.95, weather_k)
		"rain":
			v = lerpf(1.0, 0.8, weather_k)
		"storm":
			v = lerpf(1.0, 0.62, weather_k)
		"snow":
			v = lerpf(1.0, 0.65, weather_k)
		"fog":
			v = lerpf(1.0, 0.5, weather_k)
	return v * lerpf(1.0, 0.7, darkness())


# ----------------------------------------------------------------------------
#  REKISTERI JA MAINE
# ----------------------------------------------------------------------------
func add_rep(kind: String, amount: int) -> void:
	if not rep.has(kind) or amount == 0:
		return
	rep[kind] = clampi(int(rep[kind]) + amount, -100, 100)


func rep_word(kind: String) -> String:
	var v: int = rep.get(kind, 0)
	if v <= -50:
		return "vihattu"
	if v <= -15:
		return "huono"
	if v < 15:
		return "neutraali"
	if v < 50:
		return "hyvä"
	return "loistava"


## Tuomion kerroin aiempien pidätysten mukaan (toistuvat pidätykset pidentävät).
func sentence_mult() -> float:
	var m := 1.0 + 0.25 * mini(int(record.arrests), 6)
	if int(rep.police) <= -40:
		m += 0.25
	return m


## Kuinka tuttu pelaaja on poliisille (0..5): nopeampi tunnistus ja pidätys.
func recognition() -> int:
	return mini(int(record.arrests), 5)


func note_arrest(jail_seconds: int) -> void:
	record.arrests = int(record.arrests) + 1
	record.jail_seconds = int(record.jail_seconds) + jail_seconds
	add_rep("police", -6)
	add_rep("criminals", 3)


func note_fine() -> void:
	record.fines = int(record.fines) + 1
	add_rep("police", -2)


func note_crime() -> void:
	record.crimes = int(record.crimes) + 1


# ----------------------------------------------------------------------------
#  BAARI
# ----------------------------------------------------------------------------
func bar_banned() -> bool:
	return bar_ban_until > now()


func bar_ban_minutes_left() -> int:
	return maxi(int(ceil(bar_ban_until - now())), 0)


## Portsari heitti ulos. Toisesta kerrasta seuraa kielto.
func bar_strike() -> bool:
	bar_strikes += 1
	add_rep("regulars", -6)
	if bar_strikes >= 2:
		bar_strikes = 0
		bar_ban_until = now() + 300.0   # 5 pelituntia = 2,5 min oikeaa aikaa
		add_rep("regulars", -8)
		return true
	return false


## Rähinöitsijä hävisi pelaajalle: hän muistaa tämän.
func add_grudge(row: int) -> Dictionary:
	for g: Dictionary in grudges:
		if int(g.row) == row:
			g.beaten = int(g.beaten) + 1
			return g
	var g := {"name": GRUDGE_NAMES[randi() % GRUDGE_NAMES.size()], "row": row, "beaten": 1}
	grudges.append(g)
	if grudges.size() > 4:
		grudges.pop_front()
	return g


func remove_grudge(g: Dictionary) -> void:
	for i in range(grudges.size() - 1, -1, -1):
		if grudges[i].get("name", "") == g.get("name", "-") and int(grudges[i].row) == int(g.get("row", -1)):
			grudges.remove_at(i)


func random_grudge() -> Dictionary:
	if grudges.is_empty():
		return {}
	return grudges[randi() % grudges.size()]


# ----------------------------------------------------------------------------
#  TAVOITE
# ----------------------------------------------------------------------------
func buy_bar() -> bool:
	if owns_bar:
		return false
	var p := player()
	if p == null or p.money + bank < BAR_PRICE:
		return false
	_pay_total(BAR_PRICE)
	owns_bar = true
	add_rep("regulars", 30)
	_finish("OMA BAARI!",
		"Ostit kaupungin baarin %d dollarilla.\nPäivä %d. Pidätyksiä %d, sakkoja %d.\n\nBaari tuottaa noin %d $ päivässä alkuun, ja juomat ovat sinulle ilmaisia.\nToimistosta voit päivittää baaria: suosio ja tulot kasvavat.\nVoit jatkaa pelaamista." %
		[BAR_PRICE, day, int(record.arrests), int(record.fines), OWN_BAR_INCOME])
	return true


## Hovimestari Hemmo hakee kadulle jääneet omat autot kartanon luksustalliin
## (pidätys, sammuminen, sairaala). delay = viive ennen viestiä, ettei se peity muiden alle.
func butler_fetch_cars(delay: float = 3.0) -> void:
	if not owns_manor:
		return
	var garage := get_tree().get_first_node_in_group("luxury_garage")
	if garage == null or not garage.has_method("owned_vehicles"):
		return
	var g_origin: Vector2 = garage.get("origin")
	var names: PackedStringArray = []
	for v in garage.call("owned_vehicles"):
		if not is_instance_valid(v) or flag(v, "is_driving") or flag(v, "burning"):
			continue
		if (v as Node2D).global_position.distance_to(g_origin) < 600.0:
			continue   # on jo tallissa
		if garage.call("store", v):
			names.append(str(v.get("display_name")))
	if names.is_empty():
		return
	var text := "Hovimestari Hemmo haki kadulle jääneet autot talliin: %s." % ", ".join(names)
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func() -> void: msg(text, 4.0))
	else:
		msg(text, 4.0)


## Maksaa summan ensin lompakosta, loput pankista.
func _pay_total(amount: int) -> void:
	var p := player()
	var from_wallet := mini(p.money, amount)
	p.add_money(-from_wallet)
	bank -= amount - from_wallet


func _finish(title: String, text: String) -> void:
	finished = true
	Sfx.play_ui("cash", 0.0, 0.8)
	var hud := _hud()
	if hud and hud.has_method("show_ending"):
		hud.show_ending(title, text)
	save_game()


# ----------------------------------------------------------------------------
#  TILANNE (Tab)
# ----------------------------------------------------------------------------
func status_text() -> String:
	var p := player()
	var lines: PackedStringArray = []
	lines.append("PÄIVÄ %d (%s)  %s  –  %s, %s" % [day, weekday(), clock_text(), period(), weather_name()])
	lines.append("")
	lines.append("Lompakko %d $   Pankki %d $" % [p.money if p else 0, bank])
	if owns_manor:
		lines.append("Koti: oma kartano (ei vuokraa)")
	elif rent_overdue:
		lines.append("Vuokra %d $ MYÖHÄSSÄ: koti lukossa" % RENT)
	else:
		lines.append("Vuokra %d $ erääntyy päivänä %d" % [RENT, rent_due_day])
	lines.append("Jääkaapissa %d ruoka-annosta.  Nälkä %d %%   Väsymys %d %%" % [fridge, int(hunger), int(fatigue)])
	var vest_txt := "päällä %d %%" % roundi(armor / ARMOR_MAX * 100.0) if armor > 0.0 else ("mukana (V)" if vest_carried > 0.0 else "ei")
	var cars: PackedStringArray = []
	if owns_classic:
		cars.append("Bemari 635 CSi")
	if owns_supercar:
		cars.append("Furia V12")
	lines.append("VARUSTEET: liivi %s, nippusiteitä %d, asekaapissa %d asetta, savukkeita %d%s" % [
		vest_txt, zip_ties, gun_cabinet.size(), cigarettes, (", autot: " + ", ".join(cars)) if not cars.is_empty() else ""])
	lines.append("")
	lines.append("RIKOSREKISTERI: pidätyksiä %d, sakkoja %d, rikoksia %d, putkassa %d s" %
		[int(record.arrests), int(record.fines), int(record.crimes), int(record.jail_seconds)])
	lines.append("  Tuomiot %d %% pidempiä, poliisi tunnistaa sinut %s" %
		[int(round((sentence_mult() - 1.0) * 100.0)), ["huonosti", "vähän", "kohtalaisesti", "hyvin", "tosi hyvin", "heti"][recognition()]])
	lines.append("MAINE: poliisi %s (%d), kanta-asiakkaat %s (%d), rikollisporukka %s (%d)" %
		[rep_word("police"), int(rep.police), rep_word("regulars"), int(rep.regulars), rep_word("criminals"), int(rep.criminals)])
	if bar_banned():
		lines.append("Baarin kieltolistalla vielä %d min (pelin aikaa)" % bar_ban_minutes_left())
	if not grudges.is_empty():
		var names: PackedStringArray = []
		for g: Dictionary in grudges:
			names.append(str(g.name))
		lines.append("Kaunaa kantavat: " + ", ".join(names))
	lines.append("")
	var jm := get_tree().get_first_node_in_group("job_manager")
	if jm and jm.has_method("status_lines"):
		lines.append_array(jm.status_lines())
	lines.append("")
	var st := get_tree().get_first_node_in_group("story")
	if st and st.has_method("status_lines"):
		lines.append_array(st.status_lines())
	lines.append("")
	lines.append("F5 tallenna   F9 lataa   Shift+F9 uusi peli   Tab sulje")
	return "\n".join(lines)


# ----------------------------------------------------------------------------
#  TALLENNUS
# ----------------------------------------------------------------------------
## Turvallinen totuusarvo-ominaisuuden luku: puuttuva ominaisuus, null tai vapautettu
## olio = false. (Godot 4.7: null == true ja bool(null) kaatavat skriptin.)
static func flag(o: Variant, prop: String) -> bool:
	if not is_instance_valid(o):
		return false
	var v: Variant = o.get(prop)
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return false


func can_save() -> bool:
	var pm := get_tree().get_first_node_in_group("police_manager")
	if pm and (pm.wanted > 0 or pm.jail.serving):
		return false
	var jm := get_tree().get_first_node_in_group("job_manager")
	if jm and jm.has_method("busy") and jm.busy():
		return false
	# Pankkikeikka tai kaupan ryöstö/panttivankitilanne kesken: tallennus rikkoisi tilan
	if heist_active:
		return false
	for r: Node in get_tree().get_nodes_in_group("indoor_room"):
		if flag(r, "robbing") or flag(r, "standoff") or (r.has_method("panic") and r.panic()):
			return false
	return player() != null


func save_game() -> void:
	var p := player()
	var data := {
		"version": 1,
		"day": day, "minutes": minutes, "weather": _weather_target, "snow_cover": snow_cover,
		"bank": bank, "rent_due_day": rent_due_day, "rent_overdue": rent_overdue, "fridge": fridge,
		"hunger": hunger, "fatigue": fatigue,
		"record": record, "rep": rep,
		"bar_ban_until": bar_ban_until, "bar_strikes": bar_strikes, "grudges": grudges,
		"stored_weapon": stored_weapon, "owns_bar": owns_bar, "vitutus": vitutus, "cigarettes": cigarettes, "loot": loot, "armor": armor, "vest_carried": vest_carried, "gun_cabinet": gun_cabinet, "fixtures": fixtures, "zip_ties": zip_ties, "outfit": outfit, "clothes_owned": clothes_owned, "hair": hair, "hair_owned": hair_owned, "owns_classic": owns_classic, "owns_supercar": owns_supercar, "owns_manor": owns_manor, "c4": c4, "has_mask": has_mask, "bar_data": bar_data, "finished": finished,
		"missions_done": missions_done, "story": story, "phone_heard": phone_heard,
	}
	if p:
		data["money"] = p.money
		data["drunk"] = p.drunk
		data["hangover"] = p.hangover
		data["hp"] = p.hp
		data["weapon"] = p.held_weapon.weapon_id if p.has_weapon() else ""
		data["weapon_fixture"] = str(p.held_weapon.fixture) if p.has_weapon() else ""
		data["grenades"] = p.grenades
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


func _read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed
	return {}


func load_game() -> void:
	var data := _read_save()
	if data.is_empty():
		msg("Tallennusta ei löytynyt.", 2.0)
		return
	_stop_audio()
	_pending_load = data
	_attached_scene = null
	get_tree().reload_current_scene()


func new_game() -> void:
	_stop_audio()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_reset_state()
	_pending_load = {}
	_attached_scene = null
	_hud_hint_shown = false
	get_tree().reload_current_scene()


func _stop_audio() -> void:
	Sfx.stop_music()
	Sfx.bgm_override = ""
	Sfx.set_siren(0.0)
	Sfx.set_rain(0.0)


func _reset_state() -> void:
	day = 1
	minutes = float(START_HOUR * 60)
	weather = "clear"
	_weather_target = "clear"
	weather_k = 0.0
	snow_cover = 0.0
	bank = 0
	rent_due_day = RENT_EVERY_DAYS + 1
	rent_overdue = false
	fridge = 2
	hunger = 10.0
	fatigue = 5.0
	record = {"arrests": 0, "fines": 0, "crimes": 0, "jail_seconds": 0}
	rep = {"police": 0, "regulars": 0, "criminals": 0}
	bar_ban_until = -1.0
	bar_strikes = 0
	grudges = []
	stored_weapon = ""
	owns_bar = false
	bar_data = {}
	vitutus = 0.0
	cigarettes = 0
	loot = []
	armor = 0.0
	vest_carried = 0.0
	fixtures = {}
	gun_cabinet = []
	zip_ties = 0
	outfit = {"shirt": "grey", "pants": "black", "hat": "hat_none", "glasses": "gl_none"}
	clothes_owned = ["grey", "black", "hat_none", "gl_none"]
	hair = "bald"
	hair_owned = ["bald"]
	owns_classic = false
	owns_supercar = false
	owns_manor = false
	c4 = 0
	has_mask = false
	mask_on = false
	heist_active = false
	finished = false
	missions_done = 0
	story = {}
	phone_heard = []
	loaded_from_save = false


func _apply_save(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	minutes = float(d.get("minutes", START_HOUR * 60))
	weather = str(d.get("weather", "clear"))
	if not WEATHER_NEXT.has(weather):
		weather = "clear"
	_weather_target = weather
	weather_k = 1.0 if weather != "clear" else 0.0
	snow_cover = float(d.get("snow_cover", 0.0))
	bank = int(d.get("bank", 0))
	rent_due_day = int(d.get("rent_due_day", RENT_EVERY_DAYS + 1))
	rent_overdue = bool(d.get("rent_overdue", false))
	fridge = int(d.get("fridge", 2))
	hunger = float(d.get("hunger", 10.0))
	fatigue = float(d.get("fatigue", 5.0))
	var rec: Variant = d.get("record", {})
	if rec is Dictionary:
		for k: String in record.keys():
			record[k] = int((rec as Dictionary).get(k, record[k]))
	var rp: Variant = d.get("rep", {})
	if rp is Dictionary:
		for k: String in rep.keys():
			rep[k] = int((rp as Dictionary).get(k, rep[k]))
	bar_ban_until = float(d.get("bar_ban_until", -1.0))
	bar_strikes = int(d.get("bar_strikes", 0))
	var gr: Variant = d.get("grudges", [])
	grudges = []
	if gr is Array:
		for g: Variant in gr:
			if g is Dictionary:
				grudges.append({"name": str(g.get("name", "Rami")), "row": int(g.get("row", 0)), "beaten": int(g.get("beaten", 1))})
	stored_weapon = str(d.get("stored_weapon", ""))
	owns_bar = bool(d.get("owns_bar", false))
	vitutus = float(d.get("vitutus", 0.0))
	cigarettes = int(d.get("cigarettes", 0))
	var lt: Variant = d.get("loot", [])
	loot = (lt as Array).duplicate() if lt is Array else []
	armor = clampf(float(d.get("armor", 0.0)), 0.0, ARMOR_MAX)
	vest_carried = clampf(float(d.get("vest_carried", 0.0)), 0.0, ARMOR_MAX)
	zip_ties = maxi(int(d.get("zip_ties", 0)), 0)
	gun_cabinet = []
	var fx: Variant = d.get("fixtures", {})
	fixtures = (fx as Dictionary).duplicate() if fx is Dictionary else {}
	var gc: Variant = d.get("gun_cabinet", [])
	if gc is Array:
		for v: Variant in gc:
			if WeaponDB.DATA.has(str(v)):
				gun_cabinet.append(str(v))
	var of: Variant = d.get("outfit", {})
	outfit = {"shirt": "grey", "pants": "black", "hat": "hat_none", "glasses": "gl_none"}
	if of is Dictionary:
		if SHIRTS.has(str((of as Dictionary).get("shirt", ""))):
			outfit["shirt"] = str((of as Dictionary).get("shirt"))
		if PANTS.has(str((of as Dictionary).get("pants", ""))):
			outfit["pants"] = str((of as Dictionary).get("pants"))
		if HATS.has(str((of as Dictionary).get("hat", ""))):
			outfit["hat"] = str((of as Dictionary).get("hat"))
		if GLASSES.has(str((of as Dictionary).get("glasses", ""))):
			outfit["glasses"] = str((of as Dictionary).get("glasses"))
	var co: Variant = d.get("clothes_owned", [])
	clothes_owned = (co as Array).duplicate() if co is Array else []
	for base: String in ["grey", "black", "hat_none", "gl_none"]:
		if not clothes_owned.has(base):
			clothes_owned.append(base)
	hair = str(d.get("hair", "bald"))
	if not HAIRS.has(hair):
		hair = "bald"
	var ho: Variant = d.get("hair_owned", [])
	hair_owned = (ho as Array).duplicate() if ho is Array else []
	if not hair_owned.has("bald"):
		hair_owned.append("bald")
	if not hair_owned.has(hair):
		hair_owned.append(hair)
	owns_classic = bool(d.get("owns_classic", false))
	if bool(d.get("owns_moped", false)):
		bank += OLD_MOPED_REFUND
		msg("Mopo on poistunut kaupungista – %d $ hyvitettiin tilillesi." % OLD_MOPED_REFUND, 4.0)
	owns_supercar = bool(d.get("owns_supercar", false))
	owns_manor = bool(d.get("owns_manor", false))
	c4 = int(d.get("c4", 0))
	has_mask = bool(d.get("has_mask", false))
	mask_on = false
	heist_active = false
	var bd: Variant = d.get("bar_data", {})
	bar_data = (bd as Dictionary).duplicate(true) if bd is Dictionary else {}
	finished = bool(d.get("finished", false))
	missions_done = int(d.get("missions_done", 0))
	var sd: Variant = d.get("story", {})
	story = (sd as Dictionary).duplicate(true) if sd is Dictionary else {}
	var ph: Variant = d.get("phone_heard", [])
	phone_heard = (ph as Array).duplicate() if ph is Array else []
	# Ladattu peli: intro on jo nähty (myös vanhoissa tallennuksissa ilman tarinaa)
	loaded_from_save = true
	if not story.is_empty():
		story["intro"] = true
	var p := player()
	if p:
		p.money = 0
		p.add_money(int(d.get("money", 0)))
		p.drunk = float(d.get("drunk", 0.0))
		p.hangover = float(d.get("hangover", 0.0))
		p.hp = float(d.get("hp", 12.0))
		p.grenades = 0
		p.add_grenades(int(d.get("grenades", 0)))
		var w := str(d.get("weapon", ""))
		if w != "" and WeaponDB.DATA.has(w):
			p.held_weapon.equip(w)
			p.held_weapon.fixture = str(d.get("weapon_fixture", ""))
		# Aloituspistooli pois maasta, jos pelaajalla on jo ase tai pistooli on
		# asekaapissa/takavarikossa (muuten se monistuisi joka latauksella)
		var pistol := get_tree().current_scene.get_node_or_null("Pistol")
		if pistol:
			var pst := str(fixtures.get("start_pistol", ""))
			if w != "" or pst == "gone":
				pistol.queue_free()
			else:
				fixtures.erase("start_pistol")


# ----------------------------------------------------------------------------
#  APUFUNKTIOT
# ----------------------------------------------------------------------------
func player() -> Node:
	return get_tree().get_first_node_in_group("player")


func _hud() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("Hud") if scene else null


func msg(text: String, seconds: float = 2.5) -> void:
	var hud := _hud()
	if hud and hud.has_method("show_message"):
		hud.show_message(text, seconds)


## Baarin nimi neonkyltissä (BarBusiness.gd vaihtaa sen omistajan toimistosta).
func bar_name() -> String:
	return str(bar_data.get("name", "RAILIN BAARI"))


## Baarin neonvärit (BarBusiness LOOK_OPTIONS "neon"). Käytetään kyltissä, sisällä ja lavalla.
const BAR_NEON_COLORS := {
	"pink": Color(1.0, 0.22, 0.68), "cyan": Color(0.25, 0.95, 1.0), "green": Color(0.35, 1.0, 0.45),
	"red": Color(1.0, 0.2, 0.15), "gold": Color(1.0, 0.8, 0.3), "violet": Color(0.7, 0.4, 1.0),
}

func bar_neon_color() -> Color:
	var lk: Variant = bar_data.get("look", {})
	var id := str((lk as Dictionary).get("neon", "pink")) if lk is Dictionary else "pink"
	return BAR_NEON_COLORS.get(id, BAR_NEON_COLORS["pink"])


## Neonin toinen väri (kaksivärinen kyltti): vastaväri
func bar_neon_color2() -> Color:
	var c := bar_neon_color()
	return Color.from_hsv(fmod(c.h + 0.5, 1.0), clampf(c.s, 0.5, 0.8), 1.0)



# ----------------------------------------------------------------------------
#  VITUTUS JA TUPAKKA
# ----------------------------------------------------------------------------
const VITUTUS_WORK := 9.0       ## valmis keikka / työ
const VITUTUS_FAIL := 6.0       ## epäonnistunut keikka
const VITUTUS_CRIME := 3.5      ## rikos (kerrottuna vakavuudella)
const VITUTUS_ARREST := 15.0
const VITUTUS_SMOKE := 7.0      ## yksi henkonen (savukkeessa n. 5 henkosta)
const VITUTUS_SLEEP := 45.0
const CIG_PACK := 20
const CIG_PRICE := 7

## Muuttaa vitutusta. Rajojen ylityksistä pieni ilmoitus.
func add_vitutus(amount: float) -> void:
	var before := vitutus
	vitutus = clampf(vitutus + amount, 0.0, 100.0)
	if amount > 0.0:
		if before < 50.0 and vitutus >= 50.0:
			msg("Alkaa vituttaa. Tupakka auttaisi (C)." if cigarettes > 0 else "Alkaa vituttaa. Kaupasta saisi tupakkaa.", 2.5)
		elif before < 80.0 and vitutus >= 80.0:
			msg("Vituttaa ihan sikana!", 2.0)
		elif before < 100.0 and vitutus >= 100.0:
			msg("PINNA PALAA! Nyt on pakko saada röökiä.", 2.5)


## Onko pelaaja jossain sisätilassa (koti, baari, asekauppa, putka, kauppa, pankki)?
func player_indoors() -> bool:
	for g in ["home", "bar", "armory", "jail"]:
		var n := get_tree().get_first_node_in_group(g)
		if n and flag(n, "inside"):
			return true
	for n in get_tree().get_nodes_in_group("indoor_room"):
		if flag(n, "inside"):
			return true
	return false


## Saako paikalleen kuuluvan esineen (tag) luoda omalle paikalleen? Ei, jos se on
## pelaajan kädessä, lojuu jossain maassa tai on kaapissa/takavarikossa. Rikottu
## (pullo) palaa paikalleen, samoin hukattu (maassa ollut esine katosi latauksessa).
func fixture_should_spawn(tag: String) -> bool:
	if not fixtures.has(tag):
		return true
	var st := str(fixtures[tag])
	if st == "broken":
		fixtures.erase(tag)
		return true
	if st != "out":
		return false
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("has_weapon") and p.has_weapon() and str(p.held_weapon.fixture) == tag:
		return false
	for n: Node in get_tree().get_nodes_in_group("fixture_pickups"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and str(n.get("fixture")) == tag:
			return false
	fixtures.erase(tag)
	return true
