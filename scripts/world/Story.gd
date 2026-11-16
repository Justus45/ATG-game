extends Node
## Pelin päätarina. Game liittää tämän kenttään (ryhmä "story"); tila on Game.story-
## sanakirjassa, joten se tallentuu ja latautuu Gamen mukana.
##
## 1. VELKA (aina): olet velkaa Hai Haapalalle. Erät maksetaan Kallelle baarin kulmalla.
##    Myöhästyminen = korkoa + perijät (Raipe ja Late) kadulla. Liian myöhään = huono loppu.
## 2. Velan jälkeen pelaaja valitsee tiensä:
##    ALAMAAILMA (Kalle): juoksupojan keikat -> Itäpuiston diilerit -> Sakke kostaa ->
##                        Sakken kerho -> Hai itse.  Loppu: KAUPUNGIN KUNKKU
##    BAARI (Raili):      kanta-asiakkaiden luottamus -> häiriköt ovella -> Jarmo Kivelä
##                        (kaiva likaa TAI pelottele) -> osta baari.  Loppu: BAARIN ISÄNTÄ

const THUG := preload("res://scripts/world/StreetThug.gd")
const JOB_MANAGER := preload("res://scripts/world/JobManager.gd")
const INTRO := preload("res://scripts/ui/Intro.gd")

# --- Velka ---
const DEBT := 4000
const INST1 := 1500                ## ensimmäinen erä
const DUE1 := 7                    ## ensimmäisen erän viimeinen päivä
const DUE2 := 14                   ## koko velan viimeinen päivä
const FINAL := 17                  ## tämän jälkeen Hai menettää kärsivällisyytensä
const LATE_FEE1 := 500
const LATE_FEE2 := 1000
const COLLECT_MIN := 45.0          ## perijöiden tarkistusväli (s), kun velka on myöhässä
const COLLECT_MAX := 90.0
# --- Alamaailma ---
const CRIME_JOBS := 3              ## Kallen keikkoja juoksupoikana
const TERRITORY_INCOME := 60       ## Itäpuiston tuotto / päivä
# --- Baari ---
const REGULARS_NEEDED := 12
const STORY_BAR_PRICE := 2500

const ARRIVE := 36.0
## Kaupan ryöstö: Kalle tarjoaa keikkaa kun jengi arvostaa (rep "criminals")
const ROB_REP := 20
## Pankkikeikka (viimeinen keikka): kauppakeikka tehty + jengin arvostus
const HEIST_REP := 35
const HEIST := preload("res://scripts/world/BankHeist.gd")

## Vaiheiden otsikot ja ohjeet (Tab + HUD)
const STAGES := {
	"debt": ["VELKA HAILLE", ""],
	"choose": ["VALITSE TIESI", "Kalle baarin kulmalla tarjoaa töitä. Raili (baarin omistaja) tarvitsee apua: puhu baarimikolle."],
	"crime1": ["JUOKSUPOIKA", "Tee Kallelle %d keikkaa (%d/%d)."],
	"crime2": ["ITÄPUISTO", "Aja Itäpään diilerit pois Kallen uudelta alueelta (%d jäljellä)."],
	"crime3": ["SAKKE KOSTAA", "Itäpään pojat jahtaavat sinua kaduilla. Kaada heidät (%d jäljellä)."],
	"crime4": ["ITÄPÄÄN KERHO", "Mene Sakken kerholle ja hoida Sakke (%d jäljellä)."],
	"crime5": ["HAI", "Hai haluaa puolet kaikesta. Mene venevajalle ja kerro sille ei (%d jäljellä)."],
	"bar1": ["RAILIN LUOTTAMUS", "Ansaitse kanta-asiakkaiden luottamus: baarimikon keikat, baaripelit, ei tappeluja (%d/%d)."],
	"bar2": ["HÄIRIKÖT", "Joku maksaa häiriköille, jotka pelottavat asiakkaat baarin ovelta. Hoida heidät (%d jäljellä)."],
	"bar3": ["JARMO KIVELÄ", ""],
	"bar4": ["KAUPPA", "Raili myy baarin sinulle. Maksa %d $ kiinteistövälityksessä."],
	"done": ["", ""],
	"dead": ["", ""],
}

var _city: Node
var _player: Node2D
var _marker: Node2D
var _group: Array = []
var _counted := {}
var _collect_t := 30.0
var _respawn_t := 0.0
var _resumed := false
var _last_hud := ""


func _ready() -> void:
	add_to_group("story")
	var scene := get_tree().current_scene
	_city = scene.get_node_or_null("City")
	_player = scene.get_node_or_null("Player")
	_marker = JOB_MANAGER.JobMarker.new()
	_marker.marker_color = Color(1.0, 0.8, 0.2)
	_marker.visible = false
	scene.add_child.call_deferred(_marker)
	Game.day_changed.connect(_on_day)


func _s() -> Dictionary:
	if Game.story.is_empty():
		Game.story = default_state()
	return Game.story


static func default_state() -> Dictionary:
	return {"stage": "debt", "path": "", "start": Game.day, "debt": DEBT, "paid": 0, "pen1": false, "pen2": false,
		"jobs": 0, "left": 0, "loc": [], "territory": false, "jarmo": "", "evidence": false, "intro": false}


func _i(key: String) -> int:
	return int(_s().get(key, 0))


## Eräpäivät suhteessa tarinan alkuun (vanhoissa tallennuksissa tarina alkaa latauspäivästä)
func d1() -> int:
	return int(_s().get("start", 1)) + DUE1 - 1


func d2() -> int:
	return int(_s().get("start", 1)) + DUE2 - 1


func dfin() -> int:
	return int(_s().get("start", 1)) + FINAL - 1


func bar_price() -> int:
	return STORY_BAR_PRICE


func stage() -> String:
	return str(_s().get("stage", "debt"))


# ----------------------------------------------------------------------------
#  KULKU
# ----------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _city == null or _player == null:
		return
	if not _resumed:
		_resumed = true
		_resume()
		return
	var st := stage()
	match st:
		"debt":
			if is_overdue():
				_tick_collectors(delta)
		"bar1":
			if int(Game.rep.regulars) >= REGULARS_NEEDED:
				_set_stage("bar2")
		"bar3":
			if str(_s().jarmo) == "dirt":
				_tick_dirt()
		"crime3":
			_tick_ambush(delta)
	_tick_group_respawn(delta)
	_update_marker()
	_update_hud()


## Uusi peli tai lataus: näytetään alku ja palautetaan vaiheen viholliset.
func _resume() -> void:
	var s := _s()
	if Game.loaded_from_save:
		s["intro"] = true
	if not bool(s.get("intro", false)):
		s["intro"] = true
		_intro()
	_enter_stage(stage(), true)


func _intro() -> void:
	var intro = INTRO.new()
	intro.due1 = d1()
	intro.due2 = d2()
	intro.debt = DEBT
	intro.inst1 = INST1
	get_tree().current_scene.add_child(intro)


func _set_stage(st: String) -> void:
	var s := _s()
	s["stage"] = st
	s["left"] = 0
	s["loc"] = []
	_clear_group()
	_enter_stage(st, false)
	Sfx.play_ui("coin", -4.0, 0.7)


## Vaiheen aloitus (resume = latauksesta, ei repliikkejä).
func _enter_stage(st: String, resume: bool) -> void:
	var s := _s()
	match st:
		"choose":
			if not resume:
				_say_seq(["Kalle: \"No moro. Hai sai fyrkkansa. Se sano et sä oot luotettava jäbä. Harvinaista.\"",
					"Kalle: \"Mul ois sulle duunii. Isompaa. Tuu juttelee, ei täs mitään hätää.\"",
					"Baarimikko kuiskaa: \"Raili, omistaja, haluis puhua sun kanssa. Baari on pulassa.\""])
		"crime1":
			if not resume:
				s["jobs"] = 0
				_say_seq(["Kalle: \"Tervetuloo porukkaan, kundi. Eka sä juokset. Kolme keikkaa, niin nähää ootsä mitään.\""])
		"crime2":
			var loc := _loc_or_new(s, 40.0, 70.0)
			if not resume:
				s["left"] = 3
				_say_seq(["Kalle: \"Kliffaa. Sä saat Itäpuiston. Siel vaan notkuu kolme Itäpään diileriä.\"",
					"Kalle: \"Hoida ne himaan. Puhumalla tai muuten. Lähinnä muuten.\""])
			_spawn_n(int(s.left), loc, "target", ["Diileri Jape", "Diileri Pate", "Diileri Mökä"], [0, 6, 15], 6, 40)
		"crime3":
			if not resume:
				s["left"] = 3
				_collect_t = 20.0
				_say_seq(["Puhelin piippaa. Tuntematon numero: \"Täällä Sakke. Itäpuisto oli meidän. Nähdään kaduilla.\""])
		"crime4":
			var loc := _loc_or_new(s, 50.0, 80.0)
			if not resume:
				s["left"] = 3
				_say_seq(["Kalle: \"Sakken pojat on hoideltu. Nyt itte Sakke. Sen kerho on merkattu karttaan.\"",
					"Kalle: \"Ja hei. Älä listi sitä. Ruumiit on huonoo bisnestä, kytät hiffaa heti.\""])
			_spawn_boss(loc, "Sakke", 15, 14, ["Portsari Iso-Ville", "Portsari Pikku-Ville"], 7)
		"crime5":
			var loc := _loc_or_new(s, 55.0, 90.0)
			if not resume:
				s["left"] = 3
				_say_seq(["Puhelin piippaa. Hai: \"Kuulin Sakkesta. Hienoa. Mä otan puolet Itäpuistosta.\"",
					"Kalle: \"Puolet? Ei käy. Nyt on sun vuoro, jäbä. Hai on venevajallaan. Raipe ja Late on sen kaa.\""])
			_spawn_boss(loc, "Hai Haapala", 12, 16, ["Raipe", "Late"], 7)
		"bar1":
			if not resume:
				_say_seq(["Raili: \"Mä oon pyörittäny tätä baaria kakskyt vuotta. Nyt mulla on velkaa ja Jarmo Kivelä hengittää niskaan.\"",
					"Raili: \"Jos haluat auttaa, ansaitse ensin porukan luottamus. Kanta-asiakkaat on mun perhe. Kummallinen perhe.\""])
		"bar2":
			var loc := _bar_front()
			s["loc"] = [loc.x, loc.y]
			if not resume:
				s["left"] = 3
				_say_seq(["Raili: \"Porukka tykkää susta! Mut nyt ovella on kolme häirikköä, jotka pelottaa asiakkaat.\"",
					"Raili: \"Joku maksaa niille. Hoida ne, mut älä hajota mun ikkunoita.\""])
			_spawn_n(int(s.left), loc, "target", ["Häirikkö Toni", "Häirikkö Joni", "Häirikkö Roni"], [3, 9, 0], 6, 15)
		"bar3":
			if not resume:
				s["jarmo"] = ""
				_say_seq(["Häirikön taskusta löytyi käyntikortti: JARMO KIVELÄ, RAVINTOLAKETJU KIVELÄ OY.",
					"Raili: \"Tiesin! Jarmo haluu tästä mun baarista kolmannen Kivelä-pubin. Puhu mulle, keksitään miten hänet hoidetaan.\""])
			elif str(s.jarmo) == "scare":
				_spawn_boss(_loc_or_new(s, 40.0, 70.0), "Jarmo Kivelä", 6, 4, ["Jarmon gorilla"], 10)
			elif str(s.jarmo) == "dirt":
				_loc_or_new(s, 40.0, 70.0)
		"bar4":
			if not resume:
				_say_seq(["Raili: \"Jarmo luopui. Ja tiedätkö mitä? Mä oon väsyny. Mä myyn baarin sulle. Ystävähintaan.\"",
					"Raili: \"%d $. Hoida paperit kiinteistövälityksessä. Mä jään kanta-asiakkaaksi.\"" % STORY_BAR_PRICE])


# ----------------------------------------------------------------------------
#  VELKA
# ----------------------------------------------------------------------------
func debt_left() -> int:
	return maxi(_i("debt") - _i("paid"), 0)


## Paljonko pitää olla maksettu nyt (eräpäivien mukaan).
func due_now() -> int:
	if Game.day <= d1():
		return INST1
	return _i("debt")


func is_overdue() -> bool:
	if stage() != "debt":
		return false
	if Game.day > d1() and _i("paid") < INST1:
		return true
	return Game.day > d2() and debt_left() > 0


func _on_day(d: int) -> void:
	var s := _s()
	match stage():
		"debt":
			if d == d1() - 2 or d == d2() - 2:
				Game.msg("Hai: \"Kaks päivää erään. Mä vaan muistutan. Ystävällisesti. Vielä.\"", 4.0)
			if d > d1() and _i("paid") < INST1 and not bool(s.pen1):
				s["pen1"] = true
				s["debt"] = _i("debt") + LATE_FEE1
				Game.msg("Hai: \"Eka erä myöhässä. Korkoa %d $. Raipe ja Late tulee tervehtimään.\"" % LATE_FEE1, 5.0)
			if d > d2() and debt_left() > 0 and not bool(s.pen2):
				s["pen2"] = true
				s["debt"] = _i("debt") + LATE_FEE2
				Game.msg("Hai: \"Mun kärsivällisyys loppuu päivänä %d. Korkoa %d $. Älä pakota mua.\"" % [dfin(), LATE_FEE2], 5.0)
			if d > dfin() and debt_left() > 0:
				_bad_ending()
		"crime3", "crime4", "crime5", "done":
			if bool(s.get("territory", false)) and stage() != "dead":
				Game.bank += TERRITORY_INCOME
				Game.msg("Itäpuisto tuotti %d $ tilillesi." % TERRITORY_INCOME, 3.0)


func pay(amount: int) -> void:
	var p := _player
	amount = mini(amount, mini(int(p.money), debt_left()))
	if amount <= 0:
		Sfx.play_ui("denied", -6.0)
		Game.msg("Kalle: \"Tyhjil taskuil ei makseta velkoi. Käy pankissa nostaa massit.\"", 3.0)
		return
	p.add_money(-amount)
	_s()["paid"] = _i("paid") + amount
	Sfx.play_ui("cash", -4.0)
	if debt_left() <= 0:
		Game.msg("Kalle laskee setelit. \"Hai on tyytyväinen. Velka on kuitattu, kundi.\"", 3.5)
		_clear_group()
		_set_stage("choose")
	elif _i("paid") >= INST1 and _i("paid") - amount < INST1:
		Game.msg("Kalle: \"Eka erä hoidettu. Loput %d $ päivään %d mennes, muuten tulee noutaja.\"" % [debt_left(), d2()], 3.5)
	else:
		Game.msg("Maksoit %d $. Velkaa jäljellä %d $." % [amount, debt_left()], 3.0)


## Perijät kadulla, kun velka on myöhässä.
func _tick_collectors(delta: float) -> void:
	if _alive_count() > 0:
		return
	_collect_t -= delta
	if _collect_t > 0.0:
		return
	_collect_t = randf_range(COLLECT_MIN, COLLECT_MAX)
	if not _player_on_street() or randf() > 0.6:
		return
	var names := ["Raipe", "Late"]
	var n := 1 if randf() < 0.5 else 2
	for i in n:
		var p := _near_player_point(9.0, 13.0)
		if p == Vector2.INF:
			return
		var t = _spawn_thug(p, "grudge", names[i], [9, 0][i], 6, randi_range(5, 20))
		t.say("%s: Hai lähetti terveisiä!" % names[i], 2.5)
		t.defeated.connect(_on_collector_down)
		t.killed.connect(_on_collector_down)
		_group.append(t)
	Game.msg("Perijät tuli hakemaan Hain rahoja! Maksa velka Kallelle, niin ne lopettaa.", 3.5)


func _on_collector_down(thug: Node) -> void:
	if is_instance_valid(thug):
		thug.call("say", "Hai kuulee tästä...", 2.0)


func _bad_ending() -> void:
	_s()["stage"] = "dead"
	_clear_group()
	Game._finish("HAIN SYÖTTI",
		"Raipe ja Late veivät sinut \"kalaan\" Hain venevajalle.\nSelvisi, kuka oli syötti.\n\nPäivä %d. Velkaa jäi %d $.\n\nShift+F9 aloittaa uuden pelin." % [Game.day, debt_left()])


# ----------------------------------------------------------------------------
#  ALAMAAILMA
# ----------------------------------------------------------------------------
## JobManager kutsuu, kun keikka onnistuu.
func on_job_done(_type: String, crime: bool) -> void:
	if stage() == "crime1" and crime:
		_s()["jobs"] = _i("jobs") + 1
		if _i("jobs") >= CRIME_JOBS:
			_set_stage("crime2")
		else:
			Game.msg("Kalle: \"Ei paha, jäbä. Viel %d keikkaa.\"" % (CRIME_JOBS - _i("jobs")), 3.0)


## Sakken pojat hyökkäävät kadulla kunnes kaikki on kaadettu.
func _tick_ambush(delta: float) -> void:
	if _i("left") <= 0 or _alive_count() > 0:
		return
	_collect_t -= delta
	if _collect_t > 0.0:
		return
	_collect_t = randf_range(25.0, 50.0)
	if not _player_on_street():
		return
	var names := ["Itäpään Kride", "Itäpään Masa", "Itäpään Tuukka"]
	for i in _i("left"):
		var p := _near_player_point(9.0, 14.0)
		if p == Vector2.INF:
			return
		var t = _spawn_thug(p, "grudge", names[i % names.size()], [6, 15, 3][i % 3], 6, randi_range(15, 40))
		t.say("Terveisiä Sakelta!", 2.5)
		_track(t)
	Game.msg("Sakken pojat hyökkäsivät!", 2.5)


# ----------------------------------------------------------------------------
#  BAARI
# ----------------------------------------------------------------------------
func _jarmo_choice(i: int) -> void:
	if stage() != "bar3":
		return
	var s := _s()
	if i == 0:
		s["jarmo"] = "dirt"
		s["evidence"] = false
		_loc_or_new(s, 40.0, 70.0)
		_say_seq(["Raili: \"Jarmon toimisto on merkitty karttaan. Sen kirjanpito on kuulemma luovaa.\"",
			"Raili: \"Tuo se mulle, niin Jarmo perääntyy. Kukaan ei halua verottajaa kylään.\""])
	elif i == 1:
		s["jarmo"] = "scare"
		_spawn_boss(_loc_or_new(s, 40.0, 70.0), "Jarmo Kivelä", 6, 4, ["Jarmon gorilla"], 10)
		_say_seq(["Raili: \"Pelottele? No... Jarmo on toimistollaan. Sen gorilla on iso, mutta tyhmä.\"",
			"Raili: \"Älä tapa ketään. Mä en halua baariin huonoa mainetta. Siis huonompaa.\""])


func _tick_dirt() -> void:
	var s := _s()
	var target: Vector2 = _bar_front() if bool(s.get("evidence", false)) else _loc()
	if _here().distance_to(target) > ARRIVE + 6.0:
		return
	if not bool(s.get("evidence", false)):
		s["evidence"] = true
		Sfx.play_ui("coin", -6.0, 1.2)
		Game.msg("Löysit Jarmon \"luovan\" kirjanpidon. Vie se Railille baariin.", 3.5)
	else:
		Game.add_rep("regulars", 5)
		Game.msg("Raili selaa papereita ja virnistää. \"Jarmo saa kirjeen. Ja verottaja kopion.\"", 3.5)
		_set_stage("bar4")


func bar_for_sale() -> bool:
	return stage() == "bar4"


## Kiinteistövälitys kutsuu. Palauttaa true, jos kauppa onnistui.
func try_buy_bar() -> bool:
	if stage() != "bar4":
		return false
	if int(_player.money) + Game.bank < STORY_BAR_PRICE:
		return false
	Game._pay_total(STORY_BAR_PRICE)
	Game.owns_bar = true
	Game.add_rep("regulars", 30)
	_s()["stage"] = "done"
	Game._finish("BAARIN ISÄNTÄ",
		"Raili ojensi avaimet ja tilasi heti kaljan. \"Talo tarjoaa?\"\nJarmo Kivelä avasi kolmannen pubinsa naapurikaupunkiin. Se meni konkurssiin.\n\nPäivä %d. Pidätyksiä %d, sakkoja %d.\nBaari tuottaa noin %d $ päivässä alkuun ja juomat ovat sinulle ilmaisia.\nPäivitä baaria toimistosta, niin suosio ja tulot kasvavat. Voit jatkaa pelaamista." %
		[Game.day, int(Game.record.arrests), int(Game.record.fines), Game.OWN_BAR_INCOME])
	return true


# ----------------------------------------------------------------------------
#  VALIKOT (Bar.gd kutsuu)
# ----------------------------------------------------------------------------
func kalle_menu(bar: Node) -> void:
	var st := stage()
	var opts: Array = []
	var acts: Array = []
	if st == "debt":
		var next_due := maxi(INST1 - _i("paid"), 0) if Game.day <= d1() else debt_left()
		if next_due > 0 and next_due < debt_left():
			opts.append("Maksa erä Haille (%d $)" % next_due)
			acts.append(func() -> void: pay(next_due))
		opts.append("Maksa Haille kaikki mitä lompakossa on (velkaa %d $)" % debt_left())
		acts.append(func() -> void: pay(int(_player.money)))
	elif st == "choose":
		opts.append("Liity Kallen porukkaan (alamaailman tie)")
		acts.append(func() -> void: _choose("crime"))
	elif str(_s().path) == "crime" and st != "done":
		opts.append("Kysy Kallelta, mitä seuraavaksi")
		acts.append(func() -> void: Game.msg("Kalle: \"%s\"" % objective_text(), 4.0))
	var rob := str(_s().get("rob", ""))
	if rob == "" and int(Game.rep.criminals) >= ROB_REP:
		opts.append("Kalle: \"Mul ois sulle isompi keikka...\"")
		acts.append(_offer_rob)
	elif rob == "active":
		opts.append("Kysy kaupan keikasta")
		acts.append(func() -> void: Game.msg("Kalle: \"Kulman kauppa, kundi. Ampuva rauta esiin kassalla ja anna myyjän täyttää pussi. Siinä menee hetki, älä hätäile – mut ku se myyjä painaa nappia, kytät tulee.\"", 5.0))
	var heist := str(_s().get("heist", ""))
	# Pankkikeikka on Kallen viimeinen keikka: vasta kun tarina on viety loppuun
	# (velka maksettu, Kallen keikat/Hai hoidettu tai baari ostettu) ja kaupan keikka tehty.
	if heist == "" and rob == "done" and st == "done" and int(Game.rep.criminals) >= HEIST_REP:
		opts.append("Kalle: \"Nyt puhutaan isosta keikasta...\"")
		acts.append(_offer_heist)
	elif heist == "prep":
		opts.append("PANKKIKEIKKA: valmistelut ja lähtö")
		acts.append(_heist_menu)
	opts.append("Pimeät keikat...")
	acts.append(func() -> void: _job_menu("kalle_menu", bar))
	_menu("KALLE", opts, acts)


# ----------------------------------------------------------------------------
#  PANKKIKEIKKA (Kallen viimeinen keikka, BankHeist.gd)
# ----------------------------------------------------------------------------
func heist_prep() -> bool:
	return str(_s().get("heist", "")) == "prep"


func _offer_heist() -> void:
	_menu("KALLE – VIIMEINEN KEIKKA\n\"Pankki, kundi. Holvi täynnä hiluja. Mä ajan, Pera, Tuukka ja Jarno tulee mukaan – ja sä.\nTarviit C4:n holvin oveen, AK4:n, kevlarin ja kommandopipon. Erkki hoitaa kamat.\"",
		["\"Mä oon mukana.\"", "\"Liian kuuma keikka mulle.\""],
		[_accept_heist, func() -> void: Game.msg("Kalle: \"Mieti sitä. Tällasta tilaisuutta ei tuu kahta kertaa.\"", 3.0)])


func _accept_heist() -> void:
	_s()["heist"] = "prep"
	Sfx.play_ui("clink", -6.0)
	Game.msg("Kalle: \"Siistii! Hanki kamat Erkiltä asekaupasta ja tuu sit puhuu mulle. Lähdetään heti ku oot valmis.\"", 5.0)


func _heist_checklist() -> Array:
	var hw: Variant = _player.get("held_weapon") if _player else null
	var rifle: bool = hw != null and Game.flag(hw, "equipped") and str(hw.get("weapon_id")) == "rifle"
	return [
		["C4-räjähde (Erkki, asekauppa)", Game.c4 > 0],
		["AK4-rynnäkkökivääri kädessä (asekauppa)", rifle],
		["Kevlarliivi päällä (asekauppa)", Game.armor > 0.0],
		["Kommandopipo (Erkki, asekauppa)", Game.has_mask],
	]


func _heist_menu() -> void:
	var lines := PackedStringArray()
	var all_ok := true
	for it: Array in _heist_checklist():
		lines.append("%s  %s" % ["[OK]" if bool(it[1]) else "[  ]", str(it[0])])
		if not bool(it[1]):
			all_ok = false
	var title := "KALLE – PANKKIKEIKAN VALMISTELUT\n" + "\n".join(lines)
	if all_ok:
		_menu(title, ["LÄHDETÄÄN KEIKALLE!", "Ei vielä"], [_start_heist, func() -> void: pass])
	else:
		_menu(title, ["Selvä, hankin loput kamat."],
			[func() -> void: Game.msg("Kalle: \"Ilman kamoja ei lähetä. Erkki on asekaupalla.\"", 3.0)])


func _start_heist() -> void:
	var pm := get_tree().get_first_node_in_group("police_manager")
	if pm and int(pm.get("wanted")) > 0:
		Game.msg("Kalle: \"Kytät on sun perässä! Karista ne ensin, ei me lähetä mihinkään.\"", 3.5)
		return
	var bank: Node2D = null
	for b in get_tree().get_nodes_in_group("bank"):
		if b.get("interior") != null:
			bank = b
			break
	if bank == null:
		Game.msg("Kalle: \"Pankkia ei löydy kartalta... outoo.\"", 3.0)
		return
	var h := HEIST.new()
	get_tree().current_scene.add_child(h)
	h.start(bank, _player)


## BankHeist kutsuu keikan onnistuttua.
func on_heist_done() -> void:
	_s()["heist"] = "done"


# ----------------------------------------------------------------------------
#  KAUPAN KEIKKA (Kalle)
# ----------------------------------------------------------------------------
func rob_unlocked() -> bool:
	return str(_s().get("rob", "")) != ""


func _offer_rob() -> void:
	_menu("KALLE – KAUPAN KEIKKA\n\"Jengi puhuu susta, kundi. Kulman kaupan kassa on illalla täynnä hiluja.\nOta ampuva rauta, mee tiskille ja tyhjennä se. Myyjä on jänishousu.\"",
		["\"Mä hoidan sen.\"", "\"Ei nyt, Kalle.\""],
		[_accept_rob, func() -> void: Game.msg("Kalle: \"No, mieti sitä. Tarjous ei oo ikuinen, kundi.\"", 3.0)])


func _accept_rob() -> void:
	_s()["rob"] = "active"
	Sfx.play_ui("clink", -6.0)
	Game.msg("Kalle: \"Siistii. Pistooli saa Erkiltä asekaupasta. Ja muista: ku myyjä painaa nappia, kytät tulee. Älä jää nuohoomaan.\"", 5.0)


## ServiceInterior kutsuu, kun kassa on tyhjennetty.
func on_shop_robbed(_cash: int) -> void:
	if str(_s().get("rob", "")) != "active":
		return
	_s()["rob"] = "done"
	Game.add_rep("criminals", 10)
	get_tree().create_timer(4.0).timeout.connect(_kalle_rob_text)


func _kalle_rob_text() -> void:
	Game.msg("Kalle tekstaa: \"Kova keikka, kundi! Hilut on sun. Jengi arvostaa – kauppaan voi palata huomenna uudestaan.\"", 4.5)


func bartender_menu() -> void:
	var st := stage()
	var opts: Array = []
	var acts: Array = []
	if st == "choose":
		opts.append("Puhu Railille, baarin omistajalle (baarin tie)")
		acts.append(func() -> void: _choose("bar"))
	elif st == "bar3" and str(_s().jarmo) == "":
		opts.append("Raili: miten Jarmo hoidetaan?")
		acts.append(_ask_jarmo)
	elif str(_s().path) == "bar" and st != "done":
		opts.append("Kysy Raililta neuvoa")
		acts.append(func() -> void: Game.msg("Raili: \"%s\"" % objective_text(), 4.0))
	opts.append("Baarimikon tehtävät...")
	acts.append(func() -> void: _job_menu("bartender_menu", null))
	_menu("BAARI", opts, acts)


func _ask_jarmo() -> void:
	_menu("RAILI – JARMO KIVELÄ", ["Kaiva likaa: hae Jarmon kirjanpito toimistolta", "Pelottele: käy Jarmon ja sen gorillan luona"],
		[_jarmo_choice.bind(0), _jarmo_choice.bind(1)])


func _choose(path: String) -> void:
	if stage() != "choose":
		return
	_s()["path"] = path
	if path == "crime":
		_set_stage("crime1")
	else:
		Game.msg("Kalle tuhahtaa: \"Raili? Kahvinkeittoo ja tiskaamist. No, sun elämä, kundi.\"", 3.0)
		_set_stage("bar1")


func _job_menu(fn: String, arg: Variant) -> void:
	var jm := get_tree().get_first_node_in_group("job_manager")
	if jm == null:
		return
	if arg == null:
		jm.call(fn)
	else:
		jm.call(fn, arg)


func _menu(title: String, opts: Array, acts: Array) -> void:
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud == null or not hud.has_method("show_menu"):
		return
	var cb := func(i: int) -> void:
		if i >= 0 and i < acts.size():
			(acts[i] as Callable).call()
	hud.show_menu(title, opts, cb)


# ----------------------------------------------------------------------------
#  TILANNE
# ----------------------------------------------------------------------------
func objective_text() -> String:
	var s := _s()
	var st := stage()
	match st:
		"debt":
			if Game.day <= d1() and _i("paid") < INST1:
				return "Maksa Haille %d $ päivään %d mennessä (Kalle baarin kulmalla). Velkaa yhteensä %d $." % [INST1 - _i("paid"), d1(), debt_left()]
			if Game.day <= d2():
				return "Maksa loput %d $ päivään %d mennessä (Kalle baarin kulmalla)." % [debt_left(), d2()]
			return "MYÖHÄSSÄ! Maksa %d $ viimeistään päivänä %d tai Hai menettää hermonsa." % [debt_left(), dfin()]
		"crime1":
			return str(STAGES.crime1[1]) % [CRIME_JOBS, _i("jobs"), CRIME_JOBS]
		"crime2", "crime3", "crime4", "crime5", "bar2":
			return str(STAGES[st][1]) % _i("left")
		"bar1":
			return str(STAGES.bar1[1]) % [int(Game.rep.regulars), REGULARS_NEEDED]
		"bar3":
			match str(s.jarmo):
				"":
					return "Puhu Railille (baarimikko): miten Jarmo Kivelä hoidetaan?"
				"dirt":
					return "Vie Jarmon kirjanpito Railille baariin." if bool(s.get("evidence", false)) else "Hae Jarmon kirjanpito sen toimistolta (merkki kartalla)."
				_:
					return "Pelottele Jarmo ja sen gorilla pois (%d jäljellä)." % _i("left")
		"bar4":
			return str(STAGES.bar4[1]) % STORY_BAR_PRICE
		"choose":
			return str(STAGES.choose[1])
	return ""


func status_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	var st := stage()
	if st == "done":
		out.append("TARINA: suoritettu – " + ("kaupunki on sinun." if str(_s().path) == "crime" else "baari on sinun."))
		return out
	if st == "dead":
		out.append("TARINA: päättyi Hain venevajalle. Shift+F9 aloittaa uuden pelin.")
		return out
	out.append("TARINA – %s:" % str(STAGES.get(st, ["", ""])[0]))
	out.append("  " + objective_text())
	if st == "debt":
		out.append("  Maksettu %d / %d $." % [_i("paid"), _i("debt")])
	if bool(_s().get("territory", false)):
		out.append("  Itäpuisto tuottaa %d $ päivässä." % TERRITORY_INCOME)
	return out


func _update_hud() -> void:
	var st := stage()
	var text := ""
	if st != "done" and st != "dead":
		text = "%s: %s" % [str(STAGES.get(st, ["", ""])[0]), objective_text()]
	if text == _last_hud:
		return
	_last_hud = text
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud and hud.has_method("set_story_info"):
		hud.set_story_info(text)


func _update_marker() -> void:
	if _marker == null or not _marker.is_inside_tree():
		return
	var st := stage()
	var s := _s()
	var pos := Vector2.INF
	var alive := _first_alive()
	if alive:
		pos = alive.global_position
	elif st in ["crime2", "crime4", "crime5", "bar2"] or (st == "bar3" and str(s.jarmo) != ""):
		pos = _bar_front() if (st == "bar3" and bool(s.get("evidence", false))) else _loc()
	elif st == "debt" or st == "choose" or st == "crime1":
		pos = Vector2.INF   # Kalle/baari näkyvät kartalla muutenkin
	elif st == "bar4":
		var r := get_tree().get_first_node_in_group("realtor")
		if r:
			pos = r.door_px + Vector2(0, 28)
	_marker.visible = pos != Vector2.INF
	if _marker.visible:
		_marker.global_position = pos


# ----------------------------------------------------------------------------
#  VIHOLLISRYHMÄT
# ----------------------------------------------------------------------------
func _spawn_thug(world_pos: Vector2, mode: String, name: String, row: int, hp: int, cash: int):
	var t = THUG.new()
	t.city = _city
	t.mode = mode
	t.base_row = row
	t.cash = cash
	t.display_name = name
	t.position = _city.entities.to_local(world_pos)
	_city.entities.add_child(t)
	t.hp = hp
	return t


func _spawn_n(n: int, center: Vector2, mode: String, names: Array, rows: Array, hp: int, cash: int) -> void:
	var start := 3 - n
	for i in n:
		var k := start + i
		var p := _walk_point_near(center, 1.0, 4.0)
		var t = _spawn_thug(p, mode, str(names[k % names.size()]), int(rows[k % rows.size()]), hp, cash)
		_track(t)


## Pomo + vartijat. Kaikki pitää kaataa (left = 1 + vartijat).
func _spawn_boss(center: Vector2, boss: String, row: int, boss_hp: int, guards: Array, guard_hp: int) -> void:
	var total := 1 + guards.size()
	var left := _i("left")
	if left <= 0:
		left = total
		_s()["left"] = total
	# latauksessa: ensin pomo, sitten jäljellä olevat vartijat
	var t = _spawn_thug(center, "target", boss, row, boss_hp, 80)
	_track(t)
	for i in mini(left - 1, guards.size()):
		var g = _spawn_thug(_walk_point_near(center, 1.0, 3.0), "target", str(guards[i]), [9, 0, 6][i % 3], guard_hp, 20)
		_track(g)


func _track(t: Node) -> void:
	_group.append(t)
	t.defeated.connect(_on_out)
	t.killed.connect(_on_out)


func _on_out(thug: Node) -> void:
	var id := thug.get_instance_id()
	if _counted.has(id):
		return
	_counted[id] = true
	var s := _s()
	if int(s.get("left", 0)) <= 0:
		return
	s["left"] = int(s.left) - 1
	if int(s.left) > 0:
		Game.msg("%s kaatui. Jäljellä %d." % [str(thug.get("display_name")), int(s.left)], 2.5)
		return
	_group_done()


func _group_done() -> void:
	match stage():
		"crime2":
			_s()["territory"] = true
			Game.add_rep("criminals", 8)
			Game.msg("Itäpuisto on nyt Kallen ja sinun. Se tuottaa %d $ päivässä." % TERRITORY_INCOME, 4.0)
			_set_stage("crime3")
		"crime3":
			Game.add_rep("criminals", 6)
			_set_stage("crime4")
		"crime4":
			Game.add_rep("criminals", 10)
			_player.add_money(300)
			Game.msg("Sakke makaa maassa. \"Okei okei! Itäpää on teidän!\" (+300 $)", 4.0)
			_set_stage("crime5")
		"crime5":
			_crime_ending()
		"bar2":
			Game.add_rep("regulars", 6)
			_set_stage("bar3")
		"bar3":
			Game.add_rep("regulars", 4)
			Game.msg("Jarmo Kivelä: \"Hyvä on, hyvä on! Pidä se rähjäinen baarisi!\"", 3.5)
			_set_stage("bar4")


func _crime_ending() -> void:
	_s()["stage"] = "done"
	_clear_group()
	Game.add_rep("criminals", 30)
	Game._finish("KAUPUNGIN KUNKKU",
		"Hai Haapala lähti \"eläkkeelle\" Espanjaan. Raipe ja Late tekee nyt töitä sulle.\nKalle sai Itäpuiston, sinä kaiken muun.\n\nPäivä %d. Pidätyksiä %d, sakkoja %d.\nItäpuisto tuottaa %d $ päivässä. Baarin voi nyt ostaa päämajaksi kiinteistövälityksestä (%d $). Voit jatkaa pelaamista." %
		[Game.day, int(Game.record.arrests), int(Game.record.fines), TERRITORY_INCOME, Game.BAR_PRICE])


func _alive_count() -> int:
	var n := 0
	for t in _group:
		if is_instance_valid(t) and t.get("state") != THUG.S.DEAD and t.get("state") != THUG.S.DOWN:
			n += 1
	return n


func _first_alive() -> Node2D:
	for t in _group:
		if is_instance_valid(t) and t.get("state") != THUG.S.DEAD and t.get("state") != THUG.S.DOWN:
			return t
	return null


func _clear_group() -> void:
	for t in _group:
		if is_instance_valid(t):
			t.call("_despawn")
	_group.clear()
	_counted.clear()


## Paikallaan odottavat ryhmät palautetaan, jos ne katosivat (esim. karkasivat).
func _tick_group_respawn(delta: float) -> void:
	var st := stage()
	if not st in ["crime2", "crime4", "crime5", "bar2"] and not (st == "bar3" and str(_s().jarmo) == "scare"):
		return
	if _i("left") <= 0 or _alive_count() > 0:
		_respawn_t = 0.0
		return
	_respawn_t += delta
	if _respawn_t < 8.0 or _here().distance_to(_loc()) < 500.0:
		return
	_respawn_t = 0.0
	_group.clear()
	_enter_stage(st, true)


# ----------------------------------------------------------------------------
#  APUFUNKTIOT
# ----------------------------------------------------------------------------
func _say_seq(lines: Array) -> void:
	for i in lines.size():
		get_tree().create_timer(i * 3.8).timeout.connect(Game.msg.bind(str(lines[i]), 3.8))


func _loc() -> Vector2:
	var l: Array = _s().get("loc", [])
	if l.size() < 2:
		return _bar_front()
	return Vector2(float(l[0]), float(l[1]))


func _loc_or_new(s: Dictionary, min_tiles: float, max_tiles: float) -> Vector2:
	var l: Array = s.get("loc", [])
	if l.size() >= 2:
		return Vector2(float(l[0]), float(l[1]))
	var bar := get_tree().get_first_node_in_group("bar")
	var from: Vector2 = bar.door_px if bar else _player.global_position
	var p := _walk_point_near(from, min_tiles, max_tiles)
	s["loc"] = [p.x, p.y]
	return p


func _bar_front() -> Vector2:
	var bar := get_tree().get_first_node_in_group("bar")
	if bar:
		return bar.door_px + Vector2(0.0, 40.0)
	return _player.global_position


func _walk_point_near(from: Vector2, min_tiles: float, max_tiles: float) -> Vector2:
	var fc: Vector2i = _city.world_to_cell(from)
	for attempt in 300:
		var off := Vector2.from_angle(randf() * TAU) * randf_range(min_tiles, max_tiles)
		var c := fc + Vector2i(off.round())
		if _city.is_walkable(c) and not _city.is_road(c):
			return _city.cell_to_world(c)
	for attempt in 300:
		var off := Vector2.from_angle(randf() * TAU) * randf_range(min_tiles, max_tiles)
		var c := fc + Vector2i(off.round())
		if _city.is_walkable(c):
			return _city.cell_to_world(c)
	return from


func _near_player_point(min_tiles: float, max_tiles: float) -> Vector2:
	var pc: Vector2i = _city.world_to_cell(_player.body_center())
	for i in 40:
		var off := Vector2.from_angle(randf() * TAU) * randf_range(min_tiles, max_tiles)
		var c := pc + Vector2i(off.round())
		if _city.is_walkable(c):
			return _city.cell_to_world(c)
	return Vector2.INF


func _here() -> Vector2:
	for car in get_tree().get_nodes_in_group("player_vehicles"):
		if "is_driving" in car and car.is_driving:
			return (car as Node2D).global_position
	return _player.body_center()


## Pelaaja kävelee kadulla (ei autossa, sisällä, putkassa eikä jahdissa).
func _player_on_street() -> bool:
	if not _player.visible or not _player.is_physics_processing():
		return false
	if _player.get("police_locked") or _player.get("menu_locked"):
		return false
	if Game.player_indoors():
		return false
	var pm := get_tree().get_first_node_in_group("police_manager")
	if pm and pm.wanted > 0:
		return false
	return true
