extends CanvasLayer
## Baarin rahapelit: biljardi, tikanheitto ja ventti. Bar.gd kutsuu start(peli).
##  1. valitse panos (HUD-valikko), panos maksetaan heti
##  2. peli pyörii tällä kerroksella, pelaaja on lukossa (menu_locked)
##  3. voitto maksaa panoksen kaksinkertaisena takaisin
## Humala ja krapula tekevät tähtäämisestä vaikeampaa.
##
## Ohjaimet: välilyönti / E = heitä / lyö, 1 = ota kortti, 2 = jää, Esc = luovuta.

const BETS := [10, 25, 50]

var _game := ""
var _bet := 0
var _active := false
var _t := 0.0
var _player: Node
var _board: Board
var _info: Label

# tikat
var _throws: Array = []        # pisteet
var _dart_marks: Array = []    # osumakohdat
var _opp_score := 0
# biljardi
var _shot := 0
var _pots := 0
var _zone := Vector2(0.4, 0.6)
var _marker := 0.0
var _opp_pots := 0
var _last_result := ""
# ventti
var _hand: Array = []
var _dealer: Array = []
var _deck: Array = []
var _cards_done := false
var _end_t := -1.0


func _ready() -> void:
	add_to_group("bar_games")
	layer = 20
	_board = Board.new()
	_board.games = self
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board)
	_board.set_anchors_preset(Control.PRESET_CENTER)
	_board.offset_left = -260.0
	_board.offset_right = 260.0
	_board.offset_top = -210.0
	_board.offset_bottom = 210.0
	_board.hide()
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 18)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 5)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(_info)
	_info.position = Vector2(10, 350)
	_info.size = Vector2(500, 60)


func busy() -> bool:
	return _active


func start(game: String) -> void:
	if _active:
		return
	var hud := get_tree().current_scene.get_node_or_null("Hud")
	if hud == null or not hud.has_method("show_menu"):
		return
	var names := {"pool": "BILJARDI", "darts": "TIKANHEITTO", "cards": "VENTTI"}
	var rules := {
		"pool": "Lyö, kun merkki on vihreällä alueella. 5 lyöntiä,\nupota enemmän kuin vastustaja.",
		"darts": "3 tikkaa. Heitä, kun tähtäin osuu keskelle.\nEnemmän pisteitä kuin vastustajalla voittaa.",
		"cards": "Pääse lähemmäs 21:tä kuin jakaja, mutta älä yli.\n1 = ota kortti, 2 = jää.",
	}
	var opts: Array = []
	for b: int in BETS:
		opts.append("Panos %d $ (voitto %d $)" % [b, b * 2])
	hud.show_menu("%s\n%s" % [names.get(game, game), rules.get(game, "")], opts, _on_bet.bind(game))


func _on_bet(i: int, game: String) -> void:
	if i < 0:
		return
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	var bet: int = BETS[i]
	if _player.money < bet:
		Sfx.play_ui("denied", -6.0)
		Game.msg("Ei rahaa panokseen (%d $ / %d $)." % [_player.money, bet], 2.0)
		return
	_player.add_money(-bet)
	_bet = bet
	_game = game
	_active = true
	_t = 0.0
	_end_t = -1.0
	_player.set("menu_locked", true)
	match game:
		"darts":
			_throws = []
			_dart_marks = []
			_opp_score = randi_range(35, 110)
		"pool":
			_shot = 0
			_pots = 0
			_opp_pots = randi_range(1, 4)
			_new_zone()
		"cards":
			_deck = []
			for v in range(1, 14):
				for k in 4:
					_deck.append(v)
			_deck.shuffle()
			_hand = [_deck.pop_back(), _deck.pop_back()]
			_dealer = [_deck.pop_back()]
			_cards_done = false
	_board.show()
	_update_info()


## Humala ja krapula: 0..1 (vaikeuttaa tähtäystä)
func _shake() -> float:
	if _player == null:
		return 0.0
	return clampf(float(_player.drunk_strength()) + 0.6 * float(_player.get("hangover")), 0.0, 1.3)


func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	if _game == "pool":
		var spd := 0.9 + 0.9 * _shake() + 0.15 * _shot
		_marker = 0.5 + 0.5 * sin(_t * spd * PI)
	if _end_t >= 0.0:
		_end_t -= delta
		if _end_t <= 0.0:
			_close()
	_board.queue_redraw()


func _input(event: InputEvent) -> void:
	if not _active or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	if _end_t >= 0.0:
		return
	var key := (event as InputEventKey).physical_keycode
	if key == KEY_ESCAPE:
		_finish(false, "Luovutit. Panos meni.")
		return
	var action_key := key == KEY_SPACE or key == KEY_E
	match _game:
		"darts":
			if action_key:
				_throw_dart()
		"pool":
			if action_key:
				_pool_shot()
		"cards":
			if key == KEY_1:
				_hand.append(_deck.pop_back())
				Sfx.play_ui("step", -6.0, 1.6)
				if _hand_value(_hand) > 21:
					_finish(false, "Yli 21! Hävisit.")
			elif key == KEY_2:
				_dealer_play()
	_update_info()


# ----------------------------------------------------------------------------
#  TIKAT
# ----------------------------------------------------------------------------
func _crosshair() -> Vector2:
	var r := 30.0 + 70.0 * _shake()
	return Vector2(sin(_t * 2.3) * r, sin(_t * 3.1 + 1.0) * r * 0.9) + Vector2(sin(_t * 7.0), cos(_t * 6.0)) * 6.0 * _shake()


func _throw_dart() -> void:
	var p := _crosshair()
	var d := p.length()
	var pts := 0
	if d < 8.0:
		pts = 50
	elif d < 25.0:
		pts = 25
	elif d < 50.0:
		pts = 15
	elif d < 80.0:
		pts = 5
	_throws.append(pts)
	_dart_marks.append(p)
	Sfx.play_ui("dart", -2.0)
	if _throws.size() >= 3:
		var total := 0
		for v: int in _throws:
			total += v
		if total > _opp_score:
			_finish(true, "Voitit! %d pistettä vs %d." % [total, _opp_score])
		else:
			_finish(false, "Hävisit. %d pistettä vs %d." % [total, _opp_score])


# ----------------------------------------------------------------------------
#  BILJARDI
# ----------------------------------------------------------------------------
func _new_zone() -> void:
	var w := clampf(0.2 - 0.1 * _shake() - 0.01 * _shot, 0.06, 0.25)
	var c := randf_range(0.15 + w, 0.85 - w)
	_zone = Vector2(c - w * 0.5, c + w * 0.5)


func _pool_shot() -> void:
	_shot += 1
	Sfx.play_ui("pool", -2.0)
	if _marker >= _zone.x and _marker <= _zone.y:
		_pots += 1
		_last_result = "Uppos!"
	else:
		_last_result = "Ohi."
	if _shot >= 5:
		if _pots > _opp_pots:
			_finish(true, "Voitit! Upotit %d, vastustaja %d." % [_pots, _opp_pots])
		else:
			_finish(false, "Hävisit. Upotit %d, vastustaja %d." % [_pots, _opp_pots])
		return
	_new_zone()


# ----------------------------------------------------------------------------
#  VENTTI
# ----------------------------------------------------------------------------
func _hand_value(h: Array) -> int:
	var total := 0
	var aces := 0
	for v: int in h:
		if v == 1:
			aces += 1
			total += 11
		else:
			total += mini(v, 10)
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return total


func _card_name(v: int) -> String:
	match v:
		1:
			return "A"
		11:
			return "J"
		12:
			return "Q"
		13:
			return "K"
	return str(v)


func _dealer_play() -> void:
	while _hand_value(_dealer) < 17:
		_dealer.append(_deck.pop_back())
	_cards_done = true
	var me := _hand_value(_hand)
	var them := _hand_value(_dealer)
	if them > 21 or me > them:
		_finish(true, "Voitit! %d vs jakajan %d." % [me, them])
	else:
		_finish(false, "Jakaja voitti: %d vs %d." % [them, me])


# ----------------------------------------------------------------------------
#  LOPETUS
# ----------------------------------------------------------------------------
func _finish(won: bool, text: String) -> void:
	if won:
		_player.add_money(_bet * 2)
		Game.add_rep("regulars", 2)
		_last_result = text + "  +%d $" % (_bet * 2)
	else:
		_last_result = text + "  -%d $" % _bet
	_end_t = 2.2
	_update_info()


func _close() -> void:
	_active = false
	_end_t = -1.0
	_board.hide()
	if _player:
		_player.set("menu_locked", false)
	Game.msg(_last_result, 2.5)


func _update_info() -> void:
	match _game:
		"darts":
			_info.text = "TIKAT  %d/3   Vastustajan pisteet: %d   Panos %d $\nVälilyönti / E = heitä   Esc = luovuta" % [_throws.size(), _opp_score, _bet]
		"pool":
			_info.text = "BILJARDI  lyönti %d/5   upotettu %d   vastustaja %d   Panos %d $\nVälilyönti / E = lyö   %s" % [mini(_shot + 1, 5), _pots, _opp_pots, _bet, _last_result]
		"cards":
			_info.text = "VENTTI  Panos %d $\n1 = ota kortti   2 = jää   Esc = luovuta" % _bet
	if _end_t >= 0.0:
		_info.text = _last_result


func draw_board(c: Control) -> void:
	var font := ThemeDB.fallback_font
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.05, 0.06, 0.1, 0.93))
	c.draw_rect(r, Color(1.0, 0.85, 0.3, 0.8), false, 2.0)
	var mid := Vector2(r.size.x * 0.5, 170.0)
	match _game:
		"darts":
			for ring: Array in [[100.0, Color(0.1, 0.1, 0.1)], [80.0, Color(0.9, 0.85, 0.7)], [50.0, Color(0.15, 0.5, 0.25)],
					[25.0, Color(0.85, 0.85, 0.75)], [8.0, Color(0.8, 0.15, 0.15)]]:
				c.draw_circle(mid, ring[0], ring[1])
			for m: Vector2 in _dart_marks:
				c.draw_circle(mid + m, 3.0, Color(0.2, 0.6, 1.0))
			if _end_t < 0.0:
				var ch := mid + _crosshair()
				c.draw_arc(ch, 7.0, 0.0, TAU, 20, Color(1, 1, 0.3), 2.0)
				c.draw_line(ch - Vector2(10, 0), ch + Vector2(10, 0), Color(1, 1, 0.3), 1.0)
				c.draw_line(ch - Vector2(0, 10), ch + Vector2(0, 10), Color(1, 1, 0.3), 1.0)
		"pool":
			var table := Rect2(mid - Vector2(200, 90), Vector2(400, 180))
			c.draw_rect(table.grow(10.0), Color(0.3, 0.17, 0.08))
			c.draw_rect(table, Color(0.1, 0.45, 0.22))
			for i in 6 - _pots:
				c.draw_circle(table.position + Vector2(280 + (i % 3) * 18, 70 + (i / 3) * 18), 8.0,
					[Color(0.95, 0.85, 0.2), Color(0.8, 0.15, 0.15), Color(0.15, 0.3, 0.8), Color(0.95, 0.5, 0.1), Color(0.5, 0.2, 0.6), Color(0.1, 0.1, 0.1)][i])
			c.draw_circle(table.position + Vector2(90, 90), 8.0, Color.WHITE)
			var bar := Rect2(mid.x - 200, 290, 400, 20)
			c.draw_rect(bar, Color(0.2, 0.2, 0.25))
			c.draw_rect(Rect2(bar.position.x + _zone.x * bar.size.x, bar.position.y, (_zone.y - _zone.x) * bar.size.x, bar.size.y), Color(0.25, 0.85, 0.35))
			c.draw_rect(Rect2(bar.position.x + _marker * bar.size.x - 2.0, bar.position.y - 4.0, 4.0, bar.size.y + 8.0), Color.WHITE)
		"cards":
			_draw_hand(c, font, _dealer, Vector2(60, 60), "Jakaja: %d" % _hand_value(_dealer))
			_draw_hand(c, font, _hand, Vector2(60, 200), "Sinä: %d" % _hand_value(_hand))


func _draw_hand(c: Control, font: Font, h: Array, at: Vector2, title: String) -> void:
	c.draw_string(font, at + Vector2(0, -10), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	for i in h.size():
		var cr := Rect2(at + Vector2(i * 56, 0), Vector2(48, 70))
		c.draw_rect(cr, Color(0.96, 0.96, 0.92))
		c.draw_rect(cr, Color(0.2, 0.2, 0.2), false, 2.0)
		var v: int = h[i]
		c.draw_string(font, cr.position + Vector2(0, 44), _card_name(v), HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 26,
			Color(0.75, 0.1, 0.15) if i % 2 == 0 else Color(0.1, 0.1, 0.15))


class Board extends Control:
	var games: Node

	func _draw() -> void:
		if games:
			games.draw_board(self)
