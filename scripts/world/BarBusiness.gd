extends Node
## Oman baarin pyörittäminen (kun Game.owns_bar).
##
##  - Toimisto (sisällä, alaseinän ovi): päivitykset, hinnoittelu, illan tapahtuma,
##    siivous ja huolto, nimen vaihto ja kirjanpito.
##  - SUOSIO 0–100 %: hakeutuu joka päivä kohti tavoitetta, jonka määräävät päivitykset,
##    kanta-asiakkaiden maine, hinnoittelu, baarin kunto ja tapahtumat. Mitä enemmän
##    päivityksiä, sitä suositumpi baari, sitä enemmän asiakkaita ja rahaa.
##  - TILITYS joka aamu (Game._on_new_day -> end_of_day): asiakkaat x keskiostos - kulut
##    pankkitilille. Viikonloppuna ja tapahtumailtoina enemmän väkeä, sateella vähemmän
##    (paitsi katetulla terassilla).
##  - KUNTO kuluu asiakkaista ja tappeluista; huono kunto laskee suosiota.
##  - HENKILÖKUNTA: baarimikot ja tarjoilijat määräävät, montako asiakasta ehditään palvella.
##    Jos väkeä on liian vähän, osa asiakkaista lähtee palvelematta. Ovimies, kokki ja DJ
##    tuovat lisää suosiota / myyntiä. Palkat maksetaan joka päivä.
##  - MAINE (taso 1–10): kertyy palvelluista asiakkaista, omasta tarjoilusta tiskin takana,
##    tapahtumista ja päivityksistä. Jokainen taso tuo lisää asiakkaita ja isommat ostokset.
##
## Tila tallentuu Game.bar_data:han (Game tallentaa sen). Bar.gd luo tämän solmun.

# --- SÄÄDÄ NÄITÄ ---
const BASE_POP := 25.0          ## suosion tavoite ilman päivityksiä
const BASE_CAPACITY := 60.0     ## asiakkaita päivässä täydellä suosiolla ilman päivityksiä
const BASE_SPEND := 7.5         ## asiakkaan keskiostos ($) ilman päivityksiä
const GOODS_COST := 0.35        ## juomien ja ruoan sisäänostohinta (osuus myynnistä)
const UPKEEP := 25              ## kiinteät kulut / päivä ($)
const POP_DRIFT := 0.35         ## kuinka nopeasti suosio hakeutuu tavoitteeseen (osuus / päivä)
const START_POP := 30.0
const DEFAULT_NAME := "RAILIN BAARI"
const NAME_MAX := 16

## Päivitykset. Vaikutus tasoa kohden: pop = suosion tavoite, cap = asiakaskapasiteetti,
## spend = keskiostos ($), wage = palkat / päivä ($).
const UPGRADES := [
	{"id": "decor", "name": "Sisustus", "pop": 9, "cap": 8, "spend": 0.7, "wage": 0, "levels": [
		{"price": 500, "desc": "Pöytäliinat, kynttilät ja seinävalaisimet"},
		{"price": 1400, "desc": "Nahkaloosit, viherkasvit ja LED-valot tiskiin"},
		{"price": 3000, "desc": "Kattokruunu, kultakaiteet ja punainen matto"}]},
	{"id": "sound", "name": "Musiikki", "pop": 8, "cap": 12, "spend": 0.3, "wage": 0, "levels": [
		{"price": 450, "desc": "Isot kaiuttimet"},
		{"price": 1200, "desc": "Valaistu tanssilattia ja liikkuvat spotit"},
		{"price": 2600, "desc": "Diskopallo, laserit ja savukone"}]},
	{"id": "drinks", "name": "Juomavalikoima", "pop": 5, "cap": 0, "spend": 1.6, "wage": 0, "levels": [
		{"price": 350, "desc": "Lonkero ja siideri listalle + kylmäkaappi"},
		{"price": 1000, "desc": "Viski ja Jaloviina, valaistu viskiseinä"},
		{"price": 2200, "desc": "Cocktailbaari: Mojito ja Long Island"}]},
	{"id": "space", "name": "Laajennus", "pop": 8, "cap": 30, "spend": 0.3, "wage": 0, "levels": [
		{"price": 2500, "desc": "Juhlasali, esiintymislava ja LED-tanssilattia"},
		{"price": 4500, "desc": "VIP-lounge samppanjabaareineen"}]},
	{"id": "kitchen", "name": "Keittiö", "pop": 6, "cap": 6, "spend": 2.0, "wage": 20, "levels": [
		{"price": 700, "desc": "Makkaraperunat (myös sinulle)"},
		{"price": 1800, "desc": "Pizzauuni"}]},
	{"id": "terrace", "name": "Terassi", "pop": 7, "cap": 18, "spend": 0.2, "wage": 0, "levels": [
		{"price": 800, "desc": "Terassi asiakkaineen: pöydät, päivänvarjot, valot"},
		{"price": 2000, "desc": "Isompi terassi, katos ja lämmittimet (sade ei haittaa)"}]},
	{"id": "ads", "name": "Mainonta", "pop": 8, "cap": 0, "spend": 0.0, "wage": 0, "levels": [
		{"price": 200, "desc": "Flaijerit kaupungille"},
		{"price": 700, "desc": "Radiomainos"},
		{"price": 1800, "desc": "Somevaikuttaja"}]},
	{"id": "sign", "name": "Neonkyltti", "pop": 6, "cap": 0, "spend": 0.0, "wage": 0, "levels": [
		{"price": 300, "desc": "Kirkkaampi kyltti ja AUKI-valo"},
		{"price": 900, "desc": "Kaksivärinen kyltti ja valonauha"},
		{"price": 1800, "desc": "Jättikyltti ja valonheittimet"}]},
	{"id": "slots", "name": "Pelikoneet", "pop": 4, "cap": 4, "spend": 0.9, "wage": 0, "levels": [
		{"price": 600, "desc": "Pajatso ja raaputusarvat tiskille"},
		{"price": 1500, "desc": "Flipperi ja peliautomaatit nurkkaan"}]},
	{"id": "security", "name": "Turvallisuus", "pop": 4, "cap": 0, "spend": 0.0, "wage": 10, "levels": [
		{"price": 400, "desc": "Valvontakamerat ja hälytysnappi: vähemmän tappeluja"},
		{"price": 1100, "desc": "Turvamies viikonloppuisin ja metallinpaljastin ovelle"}]},
	{"id": "toilets", "name": "Vessat", "pop": 4, "cap": 2, "spend": 0.2, "wage": 0, "levels": [
		{"price": 300, "desc": "Remontoidut vessat ja isot peilit"},
		{"price": 900, "desc": "Luksusvessat: kultahanat ja hajusteet"}]},
	{"id": "sauna", "name": "Baarisauna", "pop": 10, "cap": 15, "spend": 1.5, "wage": 15, "levels": [
		{"price": 3500, "desc": "Saunaosasto takahuoneeseen: löylyt ja kylmät oluet"},
		{"price": 6000, "desc": "Palju katolle ja saunailtoja joka viikonloppu"}]},
]

## Palkattava henkilökunta. wage = palkka / päivä, hire = palkkausmaksu, need = vaadittu päivitys.
## serve = montako asiakasta lisää ehditään palvella päivässä, pop = suosion tavoite,
## spend = keskiostos ($), demand = asiakkaiden kerroin.
const BASE_SERVE := 70          ## Railin vanha baarimikko ja portsari palvelevat ilman lisäväkeä
const HIRES := [
	{"id": "bartender", "name": "Baarimikko", "wage": 50, "hire": 120, "max": 8, "need": "", "serve": 45, "pop": 0.0, "spend": 0.0, "demand": 0.0,
		"desc": "+45 palveltua asiakasta / pv"},
	{"id": "waiter", "name": "Tarjoilija", "wage": 40, "hire": 100, "max": 6, "need": "", "serve": 25, "pop": 1.0, "spend": 0.5, "demand": 0.0,
		"desc": "+25 palveltua, isommat ostokset"},
	{"id": "bouncer", "name": "Ovimies", "wage": 45, "hire": 120, "max": 4, "need": "", "serve": 0, "pop": 3.0, "spend": 0.0, "demand": 0.0,
		"desc": "turvallisuus: +suosio, vähemmän rähinää"},
	{"id": "cook", "name": "Kokki", "wage": 45, "hire": 150, "max": 4, "need": "kitchen", "serve": 0, "pop": 1.5, "spend": 1.0, "demand": 0.0,
		"desc": "keittiö myy enemmän (vaatii Keittiö 1)"},
	{"id": "dj", "name": "DJ", "wage": 70, "hire": 250, "max": 2, "need": "sound", "serve": 0, "pop": 6.0, "spend": 0.0, "demand": 0.08,
		"desc": "+suosio, +8 % asiakkaita (vaatii Musiikki 1)"},
]

## Maine: tarvittavat maine-pisteet tasoille 1..10
const REP_LEVELS := [0, 25, 60, 110, 180, 270, 380, 520, 700, 950]
const REP_DEMAND := 0.07        ## +7 % asiakkaita / maine-taso
const REP_SPEND := 0.04         ## +4 % keskiostos / maine-taso
const REP_POP := 2.0            ## +2 suosion tavoitteeseen / maine-taso

## Hinnoittelu: [nimi, asiakaskerroin, ostoskerroin, suosion tavoite]
const PRICING := [
	["Halpa", 1.2, 0.8, 7.0],
	["Normaali", 1.0, 1.0, 0.0],
	["Premium", 0.85, 1.35, -7.0],
]

## Illan tapahtumat: tilataan toimistosta, toteutuvat seuraavassa tilityksessä.
const EVENTS := {
	"quiz": {"name": "Tietovisa", "cost": 40, "cust": 1.1, "spend": 1.0, "pop": 2.0, "need": ""},
	"karaoke": {"name": "Karaokeilta", "cost": 80, "cust": 1.25, "spend": 1.0, "pop": 3.0, "need": ""},
	"happy": {"name": "Happy hour", "cost": 0, "cust": 1.35, "spend": 0.75, "pop": 2.0, "need": ""},
	"band": {"name": "Livebändi", "cost": 260, "cust": 1.5, "spend": 1.05, "pop": 6.0, "need": "sound"},
}
const EVENT_ORDER := ["quiz", "karaoke", "happy", "band"]
const STAGE_EVENTS := ["band", "karaoke", "quiz"]   ## käyttävät lavaa: vain yksi kerrallaan
const MAX_EVENTS := 2                               ## samana iltana enintään kaksi tapahtumaa

## Baarin ulkoasu (vapaasti valittavissa toimiston tietokoneelta, ilmainen).
## [id, nimi, esikatseluväri]
const LOOK_OPTIONS := {
	"floor": [["wood", "Puulattia", Color(0.30, 0.18, 0.11)], ["dark_wood", "Tumma lakattu puu", Color(0.36, 0.19, 0.09)],
		["checker", "Shakkiruutu", Color(0.55, 0.55, 0.55)], ["marble", "Musta marmori", Color(0.13, 0.11, 0.14)],
		["red_tile", "Punainen laatta", Color(0.55, 0.16, 0.12)], ["concrete", "Betoni", Color(0.46, 0.47, 0.5)],
		["carpet", "Vihreä kokolattiamatto", Color(0.15, 0.33, 0.22)]],
	"wall": [["brick", "Alkuperäinen seinä", Color(0.55, 0.3, 0.22)], ["green", "Vihreä paneeli", Color(0.12, 0.28, 0.2)],
		["burgundy", "Viininpunainen kuvio", Color(0.38, 0.07, 0.11)], ["deco", "Art deco musta-kulta", Color(0.07, 0.06, 0.09)],
		["blue_stripe", "Sininen raita", Color(0.15, 0.25, 0.5)], ["wood", "Puupaneeli", Color(0.42, 0.26, 0.14)]],
	"counter": [["wood", "Puu", Color(0.45, 0.27, 0.14)], ["white_marble", "Valkoinen marmori", Color(0.88, 0.87, 0.86)],
		["black_marble", "Musta marmori", Color(0.12, 0.1, 0.12)], ["copper", "Kupari", Color(0.72, 0.42, 0.25)]],
	"neon": [["pink", "Pinkki", Color(1.0, 0.22, 0.68)], ["cyan", "Syaani", Color(0.25, 0.95, 1.0)],
		["green", "Vihreä", Color(0.35, 1.0, 0.45)], ["red", "Punainen", Color(1.0, 0.2, 0.15)],
		["gold", "Kulta", Color(1.0, 0.8, 0.3)], ["violet", "Violetti", Color(0.7, 0.4, 1.0)]],
}
const LOOK_DEFAULT := {"floor": "wood", "wall": "brick", "counter": "wood", "neon": "pink"}
const LOOK_PRESETS := [
	["Railin alkuperäinen", {"floor": "wood", "wall": "brick", "counter": "wood", "neon": "pink"}],
	["Perinteinen pubi", {"floor": "dark_wood", "wall": "green", "counter": "wood", "neon": "gold"}],
	["Diskoklubi", {"floor": "checker", "wall": "blue_stripe", "counter": "black_marble", "neon": "pink"}],
	["Luksus", {"floor": "marble", "wall": "deco", "counter": "black_marble", "neon": "gold"}],
	["Rock-baari", {"floor": "concrete", "wall": "brick", "counter": "copper", "neon": "red"}],
	["Retro 70-luku", {"floor": "carpet", "wall": "wood", "counter": "wood", "neon": "violet"}],
]

const NAME_IDEAS := ["KULTAINEN KOSSU", "PUB HUMALA", "YÖKYÖPELI", "BAARI NEON", "KRAPULA CLUB",
	"VIIMEINEN TUOPPI", "KOSKEN RANTA", "KULMAKUPPILA"]

var bar: Node = null   # Bar.gd


func _ready() -> void:
	add_to_group("bar_business")
	_data()


# ----------------------------------------------------------------------------
#  TILA
# ----------------------------------------------------------------------------
## Game.bar_data oletusarvoineen (vanhat tallennukset saavat puuttuvat kentät).
func _data() -> Dictionary:
	var d: Dictionary = Game.bar_data
	if not d.has("name"):
		d["name"] = DEFAULT_NAME
	if not d.has("up") or not (d.up is Dictionary):
		d["up"] = {}
	if not d.has("pop"):
		d["pop"] = START_POP
	if not d.has("cond"):
		d["cond"] = 100.0
	if not d.has("price"):
		d["price"] = 1
	if not d.has("events") or not (d.events is Array):
		# vanha yksi tapahtuma -> lista
		var old_ev := str(d.get("event", ""))
		d["events"] = [old_ev] if old_ev != "" else []
	d["event"] = ""
	if not d.has("look") or not (d.look is Dictionary):
		d["look"] = {}
	if not d.has("last"):
		d["last"] = {}
	if not d.has("history"):
		d["history"] = []
	if not d.has("total"):
		d["total"] = 0
	if not d.has("fights"):
		d["fights"] = 0
	if not d.has("staff") or not (d.staff is Dictionary):
		var st := {}
		# vanha "Henkilökunta"-päivitys -> palkattu väki
		var old := int((d.up as Dictionary).get("staff", 0))
		if old >= 1:
			st["bartender"] = 1
		if old >= 2:
			st["bouncer"] = 1
		if old >= 3:
			st["waiter"] = 1
		(d.up as Dictionary).erase("staff")
		d["staff"] = st
	if not d.has("rep_xp"):
		d["rep_xp"] = 0
	if not d.has("served"):
		d["served"] = 0       # pelaajan itse tarjoilemat juomat (tänään)
	if not d.has("tips"):
		d["tips"] = 0         # pelaajan tarjoilusta saamat rahat (tänään)
	if not d.has("unserved"):
		d["unserved"] = 0
	Game.bar_data = d
	return d


func level(id: String) -> int:
	if id.begins_with("h_"):
		return hired(id.substr(2))
	if id == "staff":
		# vanha yhteenveto (rähinäkerroin): ovimiehet painavat eniten
		return mini(hired("bouncer") * 2 + hired("waiter") + mini(hired("bartender"), 1), 3)
	return int((_data().up as Dictionary).get(id, 0))


func levels() -> Dictionary:
	var out := {}
	for u: Dictionary in UPGRADES:
		out[u.id] = level(str(u.id))
	for h: Dictionary in HIRES:
		out["h_" + str(h.id)] = hired(str(h.id))
	return out


func hires_list() -> Array:
	return HIRES


## Palkattujen määrä (oletusväen lisäksi)
func hired(id: String) -> int:
	return int((_data().staff as Dictionary).get(id, 0))


func _hire_def(id: String) -> Dictionary:
	for h: Dictionary in HIRES:
		if str(h.id) == id:
			return h
	return {}


# --- Maine ---
func rep_xp() -> int:
	return int(_data().rep_xp)


func rep_level() -> int:
	var xp := rep_xp()
	var lvl := 1
	for i in REP_LEVELS.size():
		if xp >= int(REP_LEVELS[i]):
			lvl = i + 1
	return lvl


## Seuraavan tason raja (tai -1 maksimitasolla)
func rep_next() -> int:
	var lvl := rep_level()
	return int(REP_LEVELS[lvl]) if lvl < REP_LEVELS.size() else -1


func rep_text() -> String:
	var nxt := rep_next()
	if nxt < 0:
		return "Maine taso %d (huippu)" % rep_level()
	return "Maine taso %d (%d / %d)" % [rep_level(), rep_xp(), nxt]


## Maine-pisteitä. Tason noustessa ilmoitus.
func add_rep_xp(amount: int) -> void:
	if amount == 0 or not Game.owns_bar:
		return
	var before := rep_level()
	Game.bar_data["rep_xp"] = maxi(rep_xp() + amount, 0)
	var after := rep_level()
	if after > before:
		Sfx.play_ui("cash", -2.0, 1.3)
		Game.msg("%s: maine nousi tasolle %d! Enemmän asiakkaita ja isommat ostokset." % [bar_name(), after], 3.5)
		_refresh_bar()


func popularity() -> float:
	return float(_data().pop)


func condition() -> float:
	return float(_data().cond)


func bar_name() -> String:
	return str(_data().name)


## Illan tapahtumat (enintään MAX_EVENTS, lavalle mahtuu yksi esitys kerrallaan)
func events_active() -> Array:
	return (_data().events as Array).duplicate()


func has_event(id: String) -> bool:
	return id in (_data().events as Array)


## Lavan tapahtuma (bändi / karaoke / tietovisa), muuten ensimmäinen tilattu, "" = ei mitään
func event_id() -> String:
	var evs: Array = _data().events
	for e in evs:
		if str(e) in STAGE_EVENTS:
			return str(e)
	return str(evs[0]) if not evs.is_empty() else ""


## Illan tapahtuman nimi ("" = ei tapahtumaa)
func event_name() -> String:
	var names: PackedStringArray = []
	for e in (_data().events as Array):
		if EVENTS.has(str(e)):
			names.append(str((EVENTS[str(e)] as Dictionary).name))
	return " + ".join(names)


# --- Ulkoasu ---
func look(key: String) -> String:
	return str((_data().look as Dictionary).get(key, LOOK_DEFAULT.get(key, "")))


func looks() -> Dictionary:
	var out := {}
	for k: String in LOOK_DEFAULT:
		out[k] = look(k)
	return out


func look_options(key: String) -> Array:
	return LOOK_OPTIONS.get(key, [])


func look_presets() -> Array:
	return LOOK_PRESETS


func set_look(key: String, id: String) -> Array:
	(_data().look as Dictionary)[key] = id
	_refresh_bar()
	return [true, "Ulkoasu päivitetty."]


func apply_preset(i: int) -> Array:
	if i < 0 or i >= LOOK_PRESETS.size():
		return [false, ""]
	var pr: Array = LOOK_PRESETS[i]
	var lk: Dictionary = _data().look
	for k: String in (pr[1] as Dictionary):
		lk[k] = str((pr[1] as Dictionary)[k])
	_refresh_bar()
	return [true, "Tyyli vaihdettu: %s." % pr[0]]


func total_levels() -> int:
	var n := 0
	for u: Dictionary in UPGRADES:
		n += level(str(u.id))
	return n


func max_levels() -> int:
	var n := 0
	for u: Dictionary in UPGRADES:
		n += (u.levels as Array).size()
	return n


func stars_text() -> String:
	var s := clampi(roundi(popularity() / 20.0), 0, 5)
	return "*".repeat(s) + "·".repeat(5 - s)


func popularity_label() -> String:
	var p := popularity()
	if p >= 90.0:
		return "Kaupungin kuumin paikka"
	if p >= 70.0:
		return "Jonoa ovella"
	if p >= 50.0:
		return "Suosittu"
	if p >= 30.0:
		return "Paikallisten kantapaikka"
	if p >= 15.0:
		return "Hiljainen"
	return "Kuollut paikka"


# ----------------------------------------------------------------------------
#  TALOUSMALLI
# ----------------------------------------------------------------------------
func _sum(key: String) -> float:
	var s := 0.0
	for u: Dictionary in UPGRADES:
		s += float(u[key]) * level(str(u.id))
	return s


## Suosion tavoite nykyisillä päivityksillä ja valinnoilla.
func target_popularity() -> float:
	var d := _data()
	var t := BASE_POP + _sum("pop") + _staff_sum("pop") + REP_POP * (rep_level() - 1)
	t += clampf(float(Game.rep.get("regulars", 0)) * 0.12, -8.0, 8.0)
	var pr: Array = PRICING[clampi(int(d.price), 0, 2)]
	var price_pop := float(pr[3])
	if int(d.price) == 2:
		price_pop += level("decor") * 2.5   # hieno sisustus oikeuttaa premium-hinnat
	t += price_pop
	var cond := condition()
	if cond < 70.0:
		t -= (70.0 - cond) * 0.45
	return clampf(t, 0.0, 100.0)


## Palkatun väen vaikutus (kokki vain, jos keittiö on; DJ vain, jos musiikkipäivitys on)
func _staff_sum(key: String) -> float:
	var s := 0.0
	for h: Dictionary in HIRES:
		if str(h.need) != "" and level(str(h.need)) < 1:
			continue
		s += float(h[key]) * hired(str(h.id))
	return s


## Tilojen asiakaskapasiteetti (päivitykset)
## Hinnoittelun ostoskerroin (halpa 0.8, normaali 1, premium 1.35)
func price_mult() -> float:
	var pr: Array = PRICING[clampi(int(_data().price), 0, 2)]
	return float(pr[2])


func capacity() -> float:
	return BASE_CAPACITY + _sum("cap")


## Montako asiakasta henkilökunta ehtii palvella päivässä
func service_capacity() -> float:
	return BASE_SERVE + _staff_sum("serve")


func spend_per_customer() -> float:
	var pr: Array = PRICING[clampi(int(_data().price), 0, 2)]
	return (BASE_SPEND + _sum("spend") + _staff_sum("spend")) * float(pr[2]) * (1.0 + REP_SPEND * (rep_level() - 1))


func wages() -> int:
	var w := 0
	for u: Dictionary in UPGRADES:
		w += int(u.wage) * level(str(u.id))
	for h: Dictionary in HIRES:
		w += int(h.wage) * hired(str(h.id))
	return w


## Arvio tämän päivän tuloksesta (ilman satunnaisuutta). [asiakkaat, myynti, kulut, kysyntä]
## Kysyntä = tulijat; asiakkaat = ne, jotka henkilökunta ehtii palvella.
func forecast(with_event: String = "") -> Array:
	var d := _data()
	var pr: Array = PRICING[clampi(int(d.price), 0, 2)]
	var demand := capacity() * (0.2 + 0.8 * popularity() / 100.0) * float(pr[1]) * _day_factor() * _weather_factor()
	demand *= (1.0 + REP_DEMAND * (rep_level() - 1)) * (1.0 + _staff_sum("demand"))
	var spend := spend_per_customer()
	var ev_cost := 0
	var evs: Array = events_active()
	if with_event != "" and not (with_event in evs):
		evs.append(with_event)
	for ev in evs:
		if EVENTS.has(str(ev)):
			var e: Dictionary = EVENTS[str(ev)]
			demand *= float(e.cust)
			spend *= float(e.spend)
			ev_cost += int(e.cost)
	var cust := minf(demand, service_capacity())
	var sales := cust * spend
	var costs := UPKEEP + wages() + ev_cost + sales * GOODS_COST
	return [cust, sales, costs, demand]


func _day_factor() -> float:
	match Game.weekday():
		"Pe", "La":
			return 1.35
		"Su":
			return 0.85
		"Ma", "Ti":
			return 0.9
	return 1.0


func _weather_factor() -> float:
	var bad := Game.weather in ["rain", "storm", "snow"]
	if not bad:
		return 1.0
	var k := 0.85
	if level("terrace") >= 2:
		k = 1.0
	elif level("terrace") == 1:
		k = 0.8   # avoterassi on sateella tyhjä
	return lerpf(1.0, k, Game.weather_k)


## Aamun tilitys (Game._on_new_day). Rahat pankkiin, suosio ja kunto päivittyvät.
func end_of_day() -> void:
	var d := _data()
	var f := forecast()
	var demand := float(f[3]) * randf_range(0.88, 1.12)
	var cust := minf(demand, service_capacity())
	var unserved := int(round(demand - cust))
	var sales := cust * spend_per_customer()
	var evs: Array = events_active()
	var ev_name := event_name()
	for ev in evs:
		if EVENTS.has(str(ev)):
			sales *= float((EVENTS[str(ev)] as Dictionary).spend)
	var costs := float(UPKEEP + wages()) + sales * GOODS_COST
	var profit := int(round(sales - costs))

	# Suosio: kohti tavoitetta + tapahtuman bonus + satunnaisheilahdus
	var old_pop := popularity()
	var target := target_popularity()
	var drift := POP_DRIFT
	if target < old_pop:
		drift *= lerpf(1.0, 0.4, level("ads") / 3.0)   # mainonta hidastaa hiipumista
	var pop := old_pop + (target - old_pop) * drift + randf_range(-2.0, 2.0)
	for ev in evs:
		if EVENTS.has(str(ev)):
			pop += float((EVENTS[str(ev)] as Dictionary).pop)
	pop -= float(d.fights) * 1.5
	# palvelematta jääneet asiakkaat valittavat kavereilleen
	if unserved > 0:
		pop -= minf(float(unserved) / maxf(demand, 1.0) * 12.0, 6.0)
	d["pop"] = clampf(pop, 0.0, 100.0)
	# Kunto: kuluu asiakkaista ja tappeluista
	d["cond"] = clampf(condition() - 2.0 - cust / 70.0 - float(d.fights) * 3.0, 0.0, 100.0)
	var xp := int(cust / 25.0) + 4 * evs.size() - int(d.fights) * 3
	d["fights"] = 0
	d["events"] = []
	d["unserved"] = unserved
	var served_self := int(d.served)
	var tips := int(d.tips)
	d["served"] = 0
	d["tips"] = 0

	# Rahat: voitto pankkiin, tappio pankista (ja lompakosta)
	if profit >= 0:
		Game.bank += profit
	else:
		var p := Game.player()
		var have := Game.bank + (int(p.money) if p else 0)
		if have >= -profit:
			Game._pay_total(-profit)
		else:
			Game._pay_total(have)
			d["pop"] = maxf(float(d.pop) - 5.0, 0.0)   # tavarantoimittajat suuttuivat
	d["total"] = int(d.total) + profit
	d["last"] = {"day": Game.day - 1, "cust": int(round(cust)), "sales": int(round(sales)),
		"costs": int(round(costs)), "profit": profit, "event": ev_name, "unserved": unserved,
		"served_self": served_self, "tips": tips}
	var hist: Array = d.history
	hist.append(profit)
	while hist.size() > 7:
		hist.pop_front()
	var dp := int(round(float(d.pop) - old_pop))
	var msg := "%s: %d asiakasta%s, myynti %d $, kulut %d $ -> %s %d $. Suosio %d %% (%s%d)." % [
		bar_name(), int(round(cust)), (" (" + ev_name + ")") if ev_name != "" else "",
		int(round(sales)), int(round(costs)), "voitto" if profit >= 0 else "TAPPIO", absi(profit),
		roundi(float(d.pop)), "+" if dp >= 0 else "", dp]
	Game.msg(msg, 5.0)
	if unserved > 5:
		Game.msg("%d asiakasta lähti palvelematta! Palkkaa lisää baarimikkoja tai tarjoilijoita toimistosta." % unserved, 4.0)
	if condition() < 50.0:
		Game.msg("%s on huonossa kunnossa (%d %%). Siivoa ja huolla toimistosta!" % [bar_name(), roundi(condition())], 3.5)
	add_rep_xp(xp)
	_refresh_bar()


## Tappelu omassa baarissa: maine ja kunto kärsivät (näkyy seuraavassa tilityksessä).
func note_fight() -> void:
	if not Game.owns_bar:
		return
	var d := _data()
	d["fights"] = int(d.fights) + 1


## Pelaaja tarjoili itse tiskin takana (BarService.gd): rahat jo lompakossa, kirjataan.
func note_served(money: int, xp: int) -> void:
	var d := _data()
	d["served"] = int(d.served) + 1
	d["tips"] = int(d.tips) + money
	add_rep_xp(xp)


# ----------------------------------------------------------------------------
#  TIETOKONE (BarComputer.gd): toiminnot ilman valikoita. Palauttavat [ok, viesti].
# ----------------------------------------------------------------------------
const ComputerScript := preload("res://scripts/ui/BarComputer.gd")
var _computer: CanvasLayer = null


## Avaa toimiston tietokoneen. app = "" (työpöytä), "books", "upgrades", "staff", "price", "events", "care", "settings"
func open_computer(app: String = "") -> void:
	if not Game.owns_bar:
		Game.msg("Tietokone kysyy salasanaa. Et ole omistaja.", 2.0)
		return
	if is_instance_valid(_computer):
		_computer.open_app(app)
		return
	_computer = ComputerScript.new()
	_computer.biz = self
	_computer.start_app = app
	add_child(_computer)


func upgrades_list() -> Array:
	return UPGRADES


func pricing_list() -> Array:
	return PRICING


func price_index() -> int:
	return clampi(int(_data().price), 0, 2)


## [[id, tiedot], ...] järjestyksessä
func events_list() -> Array:
	var out := []
	for id: String in EVENT_ORDER:
		out.append([id, EVENTS[id]])
	return out


func repair_price() -> int:
	return _repair_price()


func money_total() -> int:
	var p := Game.player()
	return Game.bank + (int(p.money) if p else 0)


func buy_upgrade(i: int) -> Array:
	if i < 0 or i >= UPGRADES.size():
		return [false, ""]
	var u: Dictionary = UPGRADES[i]
	var lv := level(str(u.id))
	var levels_arr: Array = u.levels
	if lv >= levels_arr.size():
		return [false, "%s on jo täysin päivitetty." % u.name]
	var nxt: Dictionary = levels_arr[lv]
	if not _pay(int(nxt.price)):
		return [false, "Rahat eivät riitä (%d $)." % int(nxt.price)]
	var ups: Dictionary = _data().up
	ups[str(u.id)] = lv + 1
	Sfx.play_ui("cash", -2.0, 1.0)
	Game.bar_data["pop"] = minf(popularity() + float(u.pop) * 0.3, 100.0)
	add_rep_xp(4)
	_refresh_bar()
	return [true, "%s: %s. Suosion tavoite nyt %d %%." % [u.name, nxt.desc, roundi(target_popularity())]]


func hire(id: String) -> Array:
	var h := _hire_def(id)
	if h.is_empty():
		return [false, ""]
	if hired(id) >= int(h.max):
		return [false, "%s: paikat täynnä." % h.name]
	if str(h.need) != "" and level(str(h.need)) < 1:
		return [false, "%s tarvitsee ensin päivityksen %s." % [h.name, _upgrade_name(str(h.need))]]
	if not _pay(int(h.hire)):
		return [false, "Rahat eivät riitä (%d $)." % int(h.hire)]
	var st: Dictionary = _data().staff
	st[id] = hired(id) + 1
	Sfx.play_ui("coin", -4.0, 1.1)
	add_rep_xp(1)
	_refresh_bar()
	return [true, "Palkattu: %s (%d $ / pv)." % [str(h.name).to_lower(), int(h.wage)]]


func fire(id: String) -> Array:
	if hired(id) <= 0:
		return [false, "Ei irtisanottavaa."]
	var st: Dictionary = _data().staff
	st[id] = hired(id) - 1
	_refresh_bar()
	return [true, "Irtisanottu: %s." % str(_hire_def(id).get("name", id)).to_lower()]


func set_price(i: int) -> Array:
	Game.bar_data["price"] = clampi(i, 0, 2)
	return [true, "Hinnoittelu: %s." % str((PRICING[clampi(i, 0, 2)] as Array)[0])]


## Voiko tapahtuman tilata nyt? "" = voi, muuten syy.
func event_block_reason(id: String) -> String:
	if not EVENTS.has(id):
		return "?"
	var e: Dictionary = EVENTS[id]
	if has_event(id):
		return "Tilattu"
	if str(e.need) != "" and level(str(e.need)) < 1:
		return "Vaatii %s" % _upgrade_name(str(e.need))
	var evs: Array = _data().events
	if evs.size() >= MAX_EVENTS:
		return "Ilta täynnä (max %d)" % MAX_EVENTS
	if id in STAGE_EVENTS:
		for o in evs:
			if str(o) in STAGE_EVENTS:
				return "Lava varattu: %s" % str((EVENTS[str(o)] as Dictionary).name)
	return ""


func order_event(id: String) -> Array:
	if id == "":
		Game.bar_data["events"] = []
		_refresh_bar()
		return [true, "Illan tapahtumat peruttu (maksuja ei palauteta)."]
	if not EVENTS.has(id):
		return [false, ""]
	var e: Dictionary = EVENTS[id]
	var why := event_block_reason(id)
	if why != "":
		return [false, "%s: %s." % [e.name, why]]
	if int(e.cost) > 0 and not _pay(int(e.cost)):
		return [false, "Rahat eivät riitä (%d $)." % int(e.cost)]
	(_data().events as Array).append(id)
	Sfx.play_ui("cash", -4.0, 1.1)
	_refresh_bar()
	return [true, "%s tilattu tälle illalle! Illan ohjelma: %s." % [e.name, event_name()]]


func cancel_event(id: String) -> Array:
	(_data().events as Array).erase(id)
	_refresh_bar()
	return [true, "%s peruttu (maksua ei palauteta)." % str((EVENTS.get(id, {"name": id}) as Dictionary).name)]


func do_repair() -> Array:
	if condition() >= 99.5:
		return [false, "Paikat kiiltävät jo."]
	var price := _repair_price()
	if not _pay(price):
		return [false, "Rahat eivät riitä (%d $)." % price]
	Game.bar_data["cond"] = 100.0
	Sfx.play_ui("cash", -4.0, 0.9)
	_refresh_bar()
	return [true, "Siivooja ja remonttimies kävivät. Kunto 100 %."]


func rename(n: String) -> Array:
	n = n.strip_edges().to_upper()
	if n == "":
		return [false, "Nimi ei voi olla tyhjä."]
	_set_name(n)
	return [true, "Uusi nimi: %s. Neonkyltti vaihdettu!" % bar_name()]


func name_ideas() -> Array:
	return NAME_IDEAS


# ----------------------------------------------------------------------------
#  TOIMISTO (valikot)
# ----------------------------------------------------------------------------
func open_office() -> void:
	if not Game.owns_bar:
		Game.msg("Toimisto on lukossa. \"Vain henkilökunnalle.\"", 2.0)
		return
	var d := _data()
	var last: Dictionary = d.last
	var last_txt := "Ei vielä tilitystä."
	if not last.is_empty():
		last_txt = "Eilen: %d asiakasta, %s %d $" % [int(last.cust), "voitto" if int(last.profit) >= 0 else "tappio", absi(int(last.profit))]
	var ev_txt: String = event_name() if event_name() != "" else "ei mitään"
	var title := "TOIMISTO – %s\nSuosio %s %d %% (%s)  Kunto %d %%  %s\n%s" % [
		bar_name(), stars_text(), roundi(popularity()), popularity_label(), roundi(condition()), rep_text(), last_txt]
	var opts := [
		"Päivitykset (%d / %d)" % [total_levels(), max_levels()],
		"Henkilökunta (palkat %d $ / pv)" % wages(),
		"Hinnoittelu: %s" % str((PRICING[int(d.price)] as Array)[0]),
		"Illan tapahtuma: %s" % ev_txt,
		("Siivous ja huolto (%d $)" % _repair_price()) if condition() < 99.5 else "Siivous ja huolto (kaikki kunnossa)",
		"Vaihda baarin nimi",
		"Kirjanpito ja ennuste",
	]
	_menu(title, opts, _office_choice)


func _office_choice(i: int) -> void:
	match i:
		0:
			_upgrade_menu()
		1:
			staff_menu()
		2:
			_price_menu()
		3:
			_event_menu()
		4:
			_repair()
		5:
			_name_menu()
		6:
			_show_books()


func _upgrade_menu() -> void:
	var opts := []
	for u: Dictionary in UPGRADES:
		var lv := level(str(u.id))
		var levels_arr: Array = u.levels
		if lv >= levels_arr.size():
			opts.append("%s %d/%d – täynnä" % [u.name, lv, levels_arr.size()])
		else:
			var nxt: Dictionary = levels_arr[lv]
			opts.append("%s %d/%d: %s – %d $" % [u.name, lv + 1, levels_arr.size(), nxt.desc, int(nxt.price)])
	var p := Game.player()
	var money := (int(p.money) if p else 0) + Game.bank
	_menu("PÄIVITYKSET – rahaa %d $\nJokainen päivitys nostaa suosiota ja tuloja." % money, opts, _buy_upgrade)


func _buy_upgrade(i: int) -> void:
	if i < 0 or i >= UPGRADES.size():
		open_office.call_deferred()
		return
	var u: Dictionary = UPGRADES[i]
	var lv := level(str(u.id))
	var levels_arr: Array = u.levels
	if lv >= levels_arr.size():
		Game.msg("%s on jo täysin päivitetty." % u.name, 2.0)
		_upgrade_menu.call_deferred()
		return
	var nxt: Dictionary = levels_arr[lv]
	var price := int(nxt.price)
	if not _pay(price):
		_upgrade_menu.call_deferred()
		return
	var ups: Dictionary = _data().up
	ups[str(u.id)] = lv + 1
	Sfx.play_ui("cash", -2.0, 1.0)
	Game.msg("%s: %s! Suosion tavoite nyt %d %%." % [u.name, nxt.desc, roundi(target_popularity())], 3.5)
	# Pieni välitön piristys: uutuus houkuttelee
	Game.bar_data["pop"] = minf(popularity() + float(u.pop) * 0.3, 100.0)
	add_rep_xp(4)
	_refresh_bar()
	_upgrade_menu.call_deferred()


# ----------------------------------------------------------------------------
#  HENKILÖKUNTA
# ----------------------------------------------------------------------------
func staff_menu() -> void:
	if not Game.owns_bar:
		Game.msg("Henkilökuntataulu: \"Vain omistajalle.\"", 2.0)
		return
	var f := forecast()
	var demand := float(f[3])
	var sc := service_capacity()
	var status := "Henkilökuntaa riittää" if demand <= sc else "VÄKEÄ LIIAN VÄHÄN: ~%d asiakasta jää palvelematta" % roundi(demand - sc)
	var opts := []
	for h: Dictionary in HIRES:
		var n := hired(str(h.id))
		var lock := ""
		if str(h.need) != "" and level(str(h.need)) < 1:
			lock = " [lukossa]"
		if n >= int(h.max):
			opts.append("%s %d/%d – täynnä%s" % [h.name, n, int(h.max), lock])
		else:
			opts.append("Palkkaa %s (%d/%d): %d $ + %d $/pv – %s%s" % [str(h.name).to_lower(), n, int(h.max), int(h.hire), int(h.wage), h.desc, lock])
	opts.append("Irtisano työntekijä...")
	_menu("HENKILÖKUNTA – palkat %d $ / pv\nEhditään palvella %d / pv, tulijoita tänään ~%d\n%s" % [wages(), roundi(sc), roundi(demand), status],
		opts, _staff_choice)


func _staff_choice(i: int) -> void:
	if i < 0:
		open_office.call_deferred()
		return
	if i >= HIRES.size():
		_fire_menu.call_deferred()
		return
	var h: Dictionary = HIRES[i]
	var id := str(h.id)
	if hired(id) >= int(h.max):
		Game.msg("%s: paikat täynnä." % h.name, 2.0)
		staff_menu.call_deferred()
		return
	if str(h.need) != "" and level(str(h.need)) < 1:
		Sfx.play_ui("denied", -4.0)
		Game.msg("%s tarvitsee ensin päivityksen: %s." % [h.name, _upgrade_name(str(h.need))], 2.5)
		staff_menu.call_deferred()
		return
	if not _pay(int(h.hire)):
		staff_menu.call_deferred()
		return
	var st: Dictionary = _data().staff
	st[id] = hired(id) + 1
	Sfx.play_ui("coin", -4.0, 1.1)
	Game.msg("Palkkasit uuden: %s. Palkka %d $ / pv." % [str(h.name).to_lower(), int(h.wage)], 2.5)
	add_rep_xp(1)
	_refresh_bar()
	staff_menu.call_deferred()


func _fire_menu() -> void:
	var opts := []
	var ids := []
	for h: Dictionary in HIRES:
		if hired(str(h.id)) > 0:
			opts.append("Irtisano %s (%d töissä, säästö %d $/pv)" % [str(h.name).to_lower(), hired(str(h.id)), int(h.wage)])
			ids.append(str(h.id))
	if opts.is_empty():
		Game.msg("Ei palkattua väkeä irtisanottavaksi.", 2.0)
		staff_menu.call_deferred()
		return
	_menu("IRTISANO", opts, _fire_choice.bind(ids))


func _fire_choice(i: int, ids: Array) -> void:
	if i >= 0 and i < ids.size():
		var id := str(ids[i])
		var st: Dictionary = _data().staff
		st[id] = maxi(hired(id) - 1, 0)
		Game.msg("Irtisanoit yhden: %s." % str(_hire_def(id).get("name", id)).to_lower(), 2.0)
		_refresh_bar()
	staff_menu.call_deferred()


func _upgrade_name(id: String) -> String:
	for u: Dictionary in UPGRADES:
		if str(u.id) == id:
			return str(u.name) + " 1"
	return id


func _price_menu() -> void:
	var opts := []
	for pr: Array in PRICING:
		var hint := ""
		match str(pr[0]):
			"Halpa":
				hint = "enemmän asiakkaita, pienempi kate"
			"Normaali":
				hint = "tasapainoinen"
			"Premium":
				hint = "vähemmän asiakkaita, iso kate (sopii hienoon sisustukseen)"
		opts.append("%s – %s" % [pr[0], hint])
	_menu("HINNOITTELU", opts, _set_price)


func _set_price(i: int) -> void:
	if i >= 0 and i < PRICING.size():
		Game.bar_data["price"] = i
		Game.msg("Hinnoittelu: %s." % str((PRICING[i] as Array)[0]), 2.0)
	open_office.call_deferred()


func _event_menu() -> void:
	var opts := []
	for id: String in EVENT_ORDER:
		var e: Dictionary = EVENTS[id]
		var f := forecast(id)
		var extra := ""
		if str(e.need) != "" and level(str(e.need)) < 1:
			extra = " (vaatii Musiikki 1)"
		opts.append("%s – %d $, arvio %d asiakasta%s" % [e.name, int(e.cost), roundi(float(f[0])), extra])
	opts.append("Ei tapahtumaa")
	_menu("ILLAN TAPAHTUMA\nToteutuu tänä iltana (tilitys aamulla).", opts, _set_event)


func _set_event(i: int) -> void:
	if i < 0:
		open_office.call_deferred()
		return
	var res: Array = order_event("" if i >= EVENT_ORDER.size() else str(EVENT_ORDER[i]))
	Game.msg(str(res[1]), 2.5)


func _repair_price() -> int:
	return int(ceil((100.0 - condition()) * 5.0))


func _repair() -> void:
	if condition() >= 99.5:
		Game.msg("Paikat kiiltävät jo.", 1.8)
		open_office.call_deferred()
		return
	var price := _repair_price()
	if not _pay(price):
		return
	Game.bar_data["cond"] = 100.0
	Sfx.play_ui("cash", -4.0, 0.9)
	Game.msg("Siivooja ja remonttimies kävivät. Kunto 100 %.", 2.5)
	_refresh_bar()


func _name_menu() -> void:
	var opts := ["Kirjoita oma nimi..."]
	var ideas := NAME_IDEAS.duplicate()
	ideas.shuffle()
	for n in ideas.slice(0, 6):
		opts.append(n)
	_menu("BAARIN NIMI – nyt %s\nNimi näkyy neonkyltissä." % bar_name(), opts, _name_choice.bind(opts))


func _name_choice(i: int, opts: Array) -> void:
	if i == 0:
		_ask_name.call_deferred()
	elif i > 0 and i < opts.size():
		_set_name(str(opts[i]))


func _set_name(n: String) -> void:
	n = n.strip_edges().to_upper()
	if n == "":
		return
	if n.length() > NAME_MAX:
		n = n.substr(0, NAME_MAX)
	Game.bar_data["name"] = n
	Sfx.play_ui("coin", -4.0, 1.2)
	Game.msg("Baarin uusi nimi: %s. Neonkyltti vaihdettu!" % n, 3.0)
	_refresh_bar()


## Oma nimi tekstikentästä. Enter hyväksyy, Esc peruu.
func _ask_name() -> void:
	var p := Game.player()
	if p:
		p.set("menu_locked", true)
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.04, 0.1, 0.95)
	sb.border_color = Color(1.0, 0.25, 0.7)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var lbl := Label.new()
	lbl.text = "Baarin nimi (enintään %d merkkiä)\nEnter = valmis, Esc = peru" % NAME_MAX
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.95))
	box.add_child(lbl)
	var edit := LineEdit.new()
	edit.max_length = NAME_MAX
	edit.text = bar_name()
	edit.custom_minimum_size = Vector2(360, 40)
	edit.add_theme_font_size_override("font_size", 22)
	box.add_child(edit)
	panel.position -= panel.get_combined_minimum_size() * 0.5
	var finish := func(accept: bool) -> void:
		if not is_instance_valid(layer) or layer.is_queued_for_deletion():
			return
		var txt := edit.text
		layer.queue_free()
		if is_instance_valid(p):
			p.set("menu_locked", false)
		if accept:
			_set_name(txt)
	var on_submit := func(_t: String) -> void:
		finish.call(true)
	var on_key := func(ev: InputEvent) -> void:
		if ev is InputEventKey and (ev as InputEventKey).pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
			edit.accept_event()
			finish.call(false)
	edit.text_submitted.connect(on_submit)
	edit.gui_input.connect(on_key)
	edit.grab_focus()
	edit.select_all()


func show_books() -> void:
	open_computer("books")


func _show_books() -> void:
	var d := _data()
	var lines: PackedStringArray = []
	lines.append("%s – KIRJANPITO" % bar_name())
	lines.append("")
	lines.append("Suosio %d %% %s (%s), tavoite %d %%" % [roundi(popularity()), stars_text(), popularity_label(), roundi(target_popularity())])
	lines.append("Kunto %d %%   Hinnoittelu %s   Päivityksiä %d / %d" % [roundi(condition()), str((PRICING[int(d.price)] as Array)[0]), total_levels(), max_levels()])
	lines.append("%s   (+%d %% asiakkaita, +%d %% ostokset)" % [rep_text(), roundi(REP_DEMAND * 100.0 * (rep_level() - 1)), roundi(REP_SPEND * 100.0 * (rep_level() - 1))])
	lines.append("Tilaa %d asiakkaalle / pv,  henkilökunta ehtii palvella %d,  keskiostos %.1f $,  palkat %d $ / pv" % [roundi(capacity()), roundi(service_capacity()), spend_per_customer(), wages()])
	var staff_parts: PackedStringArray = []
	for h: Dictionary in HIRES:
		if hired(str(h.id)) > 0:
			staff_parts.append("%s %d" % [str(h.name).to_lower(), hired(str(h.id))])
	lines.append("Palkattu väki: " + (", ".join(staff_parts) if not staff_parts.is_empty() else "ei ketään (vain Railin vanha baarimikko ja portsari)"))
	var f := forecast()
	lines.append("Ennuste tänään (%s): ~%d tulijaa, palvellaan ~%d, myynti ~%d $, voitto ~%d $" % [Game.weekday(), roundi(float(f[3])), roundi(float(f[0])), roundi(float(f[1])), roundi(float(f[1]) - float(f[2]))])
	lines.append("Tänään itse tarjoiltu: %d juomaa, %d $ lompakkoon" % [int(d.served), int(d.tips)])
	lines.append("")
	var last: Dictionary = d.last
	if not last.is_empty():
		lines.append("Eilen: %d asiakasta%s, myynti %d $, kulut %d $, tulos %d $, palvelematta %d" % [int(last.cust),
			(" (" + str(last.event) + ")") if str(last.get("event", "")) != "" else "", int(last.sales), int(last.costs), int(last.profit), int(last.get("unserved", 0))])
	var hist: Array = d.history
	if not hist.is_empty():
		var parts: PackedStringArray = []
		for h in hist:
			parts.append(("+" if int(h) >= 0 else "") + str(int(h)))
		lines.append("Viimeiset päivät: " + "  ".join(parts) + " $")
	lines.append("Tulos yhteensä omistusaikana: %d $" % int(d.total))
	lines.append("")
	lines.append("Vinkki: viikonloppuna väkeä on eniten. Tapahtumat, päivitykset ja oma tarjoilu tiskin")
	lines.append("takana nostavat suosiota ja mainetta; tappelut ja huono kunto laskevat.   (Esc sulkee)")
	var hud := _hud()
	if hud and hud.has_method("toggle_status"):
		hud.toggle_status("\n".join(lines))


# ----------------------------------------------------------------------------
#  APUFUNKTIOT
# ----------------------------------------------------------------------------
## Maksaa lompakosta ja pankista. Palauttaa false, jos rahat eivät riitä.
func _pay(price: int) -> bool:
	var p := Game.player()
	var have := Game.bank + (int(p.money) if p else 0)
	if have < price:
		Sfx.play_ui("denied", -4.0)
		Game.msg("Rahat eivät riitä (%d $ / %d $)." % [have, price], 2.2)
		return false
	Game._pay_total(price)
	return true


func _refresh_bar() -> void:
	if bar and is_instance_valid(bar) and bar.has_method("refresh_business"):
		bar.refresh_business()


func _hud() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("Hud") if scene else null


func _menu(title: String, options: Array, cb: Callable) -> void:
	var hud := _hud()
	if hud and hud.has_method("show_menu"):
		hud.show_menu(title, options, cb)
