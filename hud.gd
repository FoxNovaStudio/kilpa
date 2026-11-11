extends Control
## Käyttöliittymä: nopeus, sijoitus, kierrokset, minikartta, valikot

var game            # viittaus pääpeliin (main.gd)
var map_pts := PackedVector2Array()
var map_scale := 1.0
var map_origin := Vector2.ZERO
const MAP_W := 240.0
const MAP_H := 150.0

var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func build_map(track) -> void:
	var bmin: Vector2 = track.bounds_min
	var bmax: Vector2 = track.bounds_max
	var size := bmax - bmin
	map_scale = minf(MAP_W / size.x, MAP_H / size.y)
	var used := size * map_scale
	map_origin = Vector2(1280.0 - 24.0 - MAP_W + (MAP_W - used.x) * 0.5, 24.0 + (MAP_H - used.y) * 0.5)
	map_pts.clear()
	for p in track.pts:
		map_pts.append((p - bmin) * map_scale + map_origin)
	map_pts.append(map_pts[0])


func _fmt_time(t: float) -> String:
	if t == INF or t < 0.0:
		return "--:--.--"
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%02d:%05.2f" % [m, s]


func _txt(s: String, x: float, y: float, size: int, col: Color = Color.WHITE, align: String = "l") -> void:
	var w := 1200.0
	var px := x
	var al := HORIZONTAL_ALIGNMENT_LEFT
	if align == "c":
		px = x - w * 0.5
		al = HORIZONTAL_ALIGNMENT_CENTER
	elif align == "r":
		px = x - w
		al = HORIZONTAL_ALIGNMENT_RIGHT
	draw_string_outline(font, Vector2(px, y), s, al, w, size, maxi(2, size / 8), Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(px, y), s, al, w, size, col)


func _panel(r: Rect2, col: Color = Color(0, 0, 0, 0.55)) -> void:
	draw_rect(r, col)


func _draw() -> void:
	if game == null:
		return
	match game.state:
		game.S_MENU:
			_draw_menu()
		_:
			_draw_race()
	if game.paused and game.state != game.S_MENU:
		_draw_pause()
	if game.settings_open:
		_draw_settings()
	if game.help_open:
		_draw_help()


func _draw_menu() -> void:
	_panel(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.3))
	_txt("KILPA-AJO", 640, 175, 110, Color(1.0, 0.85, 0.2), "c")
	_txt("%d kierrosta  ·  %d autoa" % [game.laps_total(), game.cars.size()], 640, 228, 28, Color(0.9, 0.95, 1.0), "c")

	var diff: String = game.DIFF_NAMES[game.difficulty]
	var tdef: Dictionary = game.track.def
	var items := ["Aloita kisa", "Rata:  <  " + String(tdef["name"]) + "  >", "Vaikeustaso:  <  " + diff + "  >", "Asetukset", "Ohjaus"]
	for i in items.size():
		var y := 308.0 + i * 52.0
		var sel: bool = game.menu_sel == i
		if sel:
			draw_rect(Rect2(380, y - 38, 520, 50), Color(1, 1, 1, 0.2))
		_txt(items[i], 640, y, 34, Color(1.0, 0.95, 0.5) if sel else Color.WHITE, "c")

	_txt(String(tdef["info"]) + "  ·  " + str(int(round(game.track.length))) + " m", 640, 590, 22, Color(0.85, 0.92, 1.0), "c")
	var best: float = game.best_laps.get(game.best_key(), INF)
	_txt("Paras kierrosaikasi: " + _fmt_time(best), 640, 620, 24, Color(0.7, 0.9, 0.7), "c")
	_panel(Rect2(190, 648, 900, 44))
	_txt("ylös / alas = valitse     vasen / oikea = vaihda     A / Enter = vahvista     Start = aloita heti", 640, 678, 20, Color(1.0, 0.95, 0.6), "c")


func _draw_help() -> void:
	_panel(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.6))
	_panel(Rect2(140, 24, 1000, 676), Color(0.05, 0.07, 0.1, 1.0))
	_txt("OHJAUS", 640, 90, 56, Color(1.0, 0.85, 0.2), "c")
	var head := Color(0.6, 0.85, 1.0)
	_txt("Toiminto", 180, 150, 26, head)
	_txt("Ohjain", 530, 150, 26, head)
	_txt("Näppäimistö", 830, 150, 26, head)
	draw_rect(Rect2(170, 160, 940, 2), Color(1, 1, 1, 0.25))
	var rows := [
		["Kaasu", "RT tai A", "W tai nuoli ylös"],
		["Jarru ja peruutus", "LT tai B", "S tai nuoli alas"],
		["Ohjaus", "Vasen tatti / ristiohjain", "A ja D / nuolet"],
		["Käsijarru", "LB tai RB", "Välilyönti"],
		["Vaihda kameraa", "Y", "C"],
		["Palauta auto radalle", "X", "R"],
		["Tauko", "Start", "Esc tai P"],
		["Aloita kisa alusta", "Back", "Backspace"],
		["Koko ruutu", "-", "F11"],
		["Valikoissa: vahvista", "A", "Enter"],
		["Valikoissa: takaisin", "Back tai Start", "Backspace tai Esc"],
	]
	for i in rows.size():
		var y := 202.0 + i * 38.0
		if i % 2 == 0:
			draw_rect(Rect2(170, y - 27, 940, 36), Color(1, 1, 1, 0.05))
		_txt(rows[i][0], 180, y, 24)
		_txt(rows[i][1], 530, y, 24, Color(1.0, 0.95, 0.6))
		_txt(rows[i][2], 830, y, 24, Color(1.0, 0.95, 0.6))
	_txt("Napit on nimetty Xbox-ohjaimen mukaan. Logitech-ohjaimessa käytä X-tilaa (kytkin pohjassa).", 640, 644, 20, Color(0.75, 0.8, 0.9), "c")
	_txt("Nintendo-ohjaimessa A ja B ovat toisin päin. Kohdat tulevat silti samoille paikoille.", 640, 670, 20, Color(0.75, 0.8, 0.9), "c")
	_txt("A / Enter = sulje", 640, 694, 20, Color.WHITE, "c")


func _draw_race() -> void:
	var p = game.player
	var mph: bool = int(game.settings["units"]) == 1
	var kmh := int(p.vel.length() * (2.23694 if mph else 3.6))

	# Sijoitus
	_panel(Rect2(20, 20, 190, 92))
	_txt(str(p.rank), 36, 98, 84, Color(1.0, 0.85, 0.2))
	_txt("/ " + str(game.cars.size()), 108, 98, 40, Color(0.85, 0.9, 1.0))

	# Kierros ja ajat
	_panel(Rect2(490, 20, 300, 106))
	var lap_show: int = clampi(p.lap + 1, 1, game.laps_total())
	_txt("KIERROS %d / %d" % [lap_show, game.laps_total()], 640, 54, 30, Color.WHITE, "c")
	var shown_time: float = p.finish_time if p.finished else game.race_time
	_txt(_fmt_time(shown_time), 640, 90, 36, Color(1.0, 0.95, 0.6), "c")
	_txt("Paras: " + _fmt_time(p.best_lap), 640, 118, 20, Color(0.7, 0.95, 0.7), "c")

	# Minikartta
	if int(game.settings["minimap"]) == 1:
		_panel(Rect2(1280 - 24 - MAP_W - 10, 14, MAP_W + 20, MAP_H + 20))
		draw_polyline(map_pts, Color(0.75, 0.78, 0.85), 5.0, true)
		draw_polyline(map_pts, Color(0.18, 0.2, 0.25), 2.5, true)
		for c in game.cars:
			if c == p:
				continue
			draw_circle(_map_pos(c.pos), 4.0, c.color)
		draw_circle(_map_pos(p.pos), 6.5, Color.WHITE)
		draw_circle(_map_pos(p.pos), 4.5, p.color)

	# Nopeusmittari
	_panel(Rect2(1280 - 330, 720 - 140, 310, 120))
	_txt(str(kmh), 1280 - 150, 720 - 56, 88, Color.WHITE, "r")
	_txt("mph" if mph else "km/h", 1280 - 40, 720 - 62, 28, Color(0.8, 0.85, 0.95), "r")
	var frac := clampf(p.vel.length() / (72.0 * game.track.top_k), 0.0, 1.0)
	var bar := Rect2(1280 - 316, 720 - 40, 282, 14)
	draw_rect(bar, Color(0.1, 0.1, 0.12, 0.9))
	var col := Color(0.3, 0.9, 0.4).lerp(Color(1.0, 0.25, 0.2), frac)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), col)

	# Kierrosviesti
	if game.lap_msg_t > 0.0 and game.state != game.S_RESULTS:
		_txt(game.lap_msg, 640, 190, 34, Color(0.6, 1.0, 0.7), "c")

	# Väärä suunta ja jumi
	if game.state == game.S_RACE and game.wrong_way:
		_txt("VÄÄRÄÄN SUUNTAAN!", 640, 270, 56, Color(1.0, 0.3, 0.25), "c")
	if game.state == game.S_RACE and p.stuck_t > 2.5:
		_txt("Paina X / R palauttaaksesi auton radalle", 640, 330, 26, Color(1.0, 0.9, 0.5), "c")

	# Lähtölaskenta
	if game.state == game.S_COUNTDOWN:
		var t: float = game.count_t
		if t < 3.0:
			var n := 3 - int(t)
			var frac_t := t - floorf(t)
			_txt(str(n), 640, 300, int(150.0 - frac_t * 40.0), Color(1.0, 0.85, 0.2, 1.0 - frac_t * 0.5), "c")
	elif game.go_t > 0.0:
		_txt("LÄHTÖ!", 640, 300, 140, Color(0.4, 1.0, 0.5, clampf(game.go_t * 1.5, 0.0, 1.0)), "c")

	if game.state == game.S_RESULTS:
		_draw_results()


func _map_pos(p: Vector2) -> Vector2:
	var bmin: Vector2 = game.track.bounds_min
	return (p - bmin) * map_scale + map_origin


func _draw_results() -> void:
	var p = game.player
	_panel(Rect2(340, 130, 600, 470), Color(0, 0, 0, 0.78))
	var place: int = p.finish_pos
	var head := "MAALI!"
	var hc := Color(1.0, 0.85, 0.2)
	if place == 1:
		head = "VOITTO!"
	elif place <= 3:
		head = "PALKINTOSIJA!"
	_txt(head, 640, 195, 64, hc, "c")
	_txt("Sijoituksesi: %d. / %d" % [place, game.cars.size()], 640, 235, 30, Color.WHITE, "c")

	var arr: Array = game.cars.duplicate()
	arr.sort_custom(func(a, b):
		if a.finished != b.finished:
			return a.finished
		if a.finished:
			return a.finish_pos < b.finish_pos
		return a.progress > b.progress)
	var y := 285.0
	var i := 1
	for c in arr:
		var rowcol := Color(1.0, 0.95, 0.55) if c == p else Color(0.9, 0.92, 1.0)
		draw_rect(Rect2(380, y - 22, 14, 14), c.color)
		_txt("%d." % i, 410, y, 24, rowcol)
		_txt(c.car_name, 460, y, 24, rowcol)
		var tt := _fmt_time(c.finish_time) if c.finished else "ajossa..."
		_txt(tt, 900, y, 24, rowcol, "r")
		y += 34.0
		i += 1
	_txt("Paras kierroksesi: " + _fmt_time(p.best_lap), 640, 520, 24, Color(0.7, 1.0, 0.7), "c")
	_txt("A / Enter = uusi kisa      Back / Backspace = valikko", 640, 570, 22, Color(0.9, 0.95, 1.0), "c")


func _draw_pause() -> void:
	_panel(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.55))
	_txt("TAUKO", 640, 290, 100, Color.WHITE, "c")
	_txt("Start / Esc = jatka", 640, 360, 30, Color(0.9, 0.95, 1.0), "c")
	_txt("A / Enter = asetukset", 640, 400, 30, Color(0.9, 0.95, 1.0), "c")
	_txt("Back / Backspace = päävalikkoon", 640, 440, 30, Color(0.9, 0.95, 1.0), "c")


func _draw_settings() -> void:
	_panel(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.6))
	_panel(Rect2(240, 24, 800, 676), Color(0.05, 0.07, 0.1, 1.0))
	_txt("ASETUKSET", 640, 84, 52, Color(1.0, 0.85, 0.2), "c")
	var rows: Array = game.SETTING_ROWS
	for i in rows.size():
		var row: Dictionary = rows[i]
		var y := 134.0 + i * 36.0
		var sel: bool = game.set_sel == i
		if sel:
			draw_rect(Rect2(260, y - 27, 760, 35), Color(1, 1, 1, 0.16))
		var col := Color(1.0, 0.95, 0.5) if sel else Color.WHITE
		if row["type"] == "action":
			_txt(row["name"], 640, y, 26, col, "c")
			continue
		_txt(row["name"], 280, y, 26, col)
		var val: String = game.setting_text(row)
		if sel:
			val = "<  " + val + "  >"
		_txt(val, 1000, y, 26, col, "r")
		if row["type"] == "num":
			var frac := (float(game.settings[row["key"]]) - float(row["min"])) / (float(row["max"]) - float(row["min"]))
			var bar := Rect2(590, y - 14, 150, 8)
			draw_rect(bar, Color(0.2, 0.22, 0.28))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(frac, 0.0, 1.0), bar.size.y)), Color(0.4, 0.8, 1.0) if sel else Color(0.45, 0.55, 0.65))
	_txt("Kierrokset ja vastustajat tulevat voimaan seuraavassa kisassa.", 640, 664, 19, Color(0.7, 0.75, 0.85), "c")
	_txt("ylös / alas = valitse     vasen / oikea = muuta     Back / Esc = takaisin", 640, 688, 19, Color(0.9, 0.95, 1.0), "c")
