extends Node3D
## Kilpa-ajo: pääohjelma (maailma, syötteet, kisan kulku, kamera, ääni)

const TrackScript = preload("res://track.gd")
const CarScript = preload("res://car.gd")
const HudScript = preload("res://hud.gd")

const S_MENU := 0
const S_COUNTDOWN := 1
const S_RACE := 2
const S_RESULTS := 3
const DIFF_NAMES := ["Helppo", "Normaali", "Kova"]
const DIFF_SKILL := [0.82, 0.91, 0.99]
const AI_NAMES := ["Aaro", "Liisa", "Eero", "Sofia", "Veeti", "Oona", "Juho"]
const AI_COLORS := [Color(0.15, 0.4, 0.95), Color(0.95, 0.8, 0.1), Color(0.2, 0.75, 0.3), Color(0.95, 0.5, 0.1), Color(0.65, 0.25, 0.85), Color(0.1, 0.75, 0.8), Color(0.95, 0.4, 0.6)]
const PLAYER_COLOR := Color(0.9, 0.1, 0.12)

const DEFAULTS := {
	"sens": 1.0, "deadzone": 0.15, "assist": 0, "laps": 3, "ai": 5, "rubber": 1,
	"cam": 0, "fov": 70, "shake": 1, "volume": 80, "units": 0, "minimap": 1, "quality": 1,
}
const SETTING_ROWS := [
	{"key": "sens", "name": "Ohjauksen herkkyys", "type": "num", "min": 0.5, "max": 2.0, "step": 0.1, "fmt": "%.1f x"},
	{"key": "deadzone", "name": "Tatin kuollut alue", "type": "num", "min": 0.05, "max": 0.4, "step": 0.05, "fmt": "%d %%", "mult": 100.0, "int": true},
	{"key": "assist", "name": "Ohjausapu", "type": "choice", "choices": ["Pois", "Matala", "Korkea"]},
	{"key": "laps", "name": "Kierrosten määrä", "type": "num", "min": 1, "max": 10, "step": 1, "fmt": "%d", "int": true},
	{"key": "ai", "name": "Vastustajien määrä", "type": "num", "min": 0, "max": 7, "step": 1, "fmt": "%d", "int": true},
	{"key": "rubber", "name": "Vastustajien tasoitus", "type": "choice", "choices": ["Pois", "Päällä"]},
	{"key": "cam", "name": "Kamera", "type": "choice", "choices": ["Takaa", "Kauempaa", "Ohjaamosta"]},
	{"key": "fov", "name": "Näkökenttä", "type": "num", "min": 55, "max": 95, "step": 5, "fmt": "%d°", "int": true},
	{"key": "quality", "name": "Grafiikka", "type": "choice", "choices": ["Matala", "Korkea"]},
	{"key": "shake", "name": "Kameran tärinä", "type": "choice", "choices": ["Pois", "Päällä"]},
	{"key": "volume", "name": "Äänenvoimakkuus", "type": "num", "min": 0, "max": 100, "step": 10, "fmt": "%d %%", "int": true},
	{"key": "units", "name": "Nopeusyksikkö", "type": "choice", "choices": ["km/h", "mph"]},
	{"key": "minimap", "name": "Minikartta", "type": "choice", "choices": ["Pois", "Päällä"]},
	{"key": "_reset", "name": "Palauta oletusasetukset", "type": "action"},
	{"key": "_close", "name": "Takaisin", "type": "action"},
]
const SAVE_PATH := "user://kilpa_ajo.cfg"

var track
var cars: Array = []
var player
var state := S_MENU
var paused := false
var difficulty := 1
var race_time := 0.0
var count_t := 0.0
var go_t := 0.0
var finish_count := 0
var wrong_way := false
var lap_msg := ""
var lap_msg_t := 0.0
var best_laps := {}
var settings: Dictionary = DEFAULTS.duplicate()
var settings_open := false
var help_open := false
var env: Environment
var sun: DirectionalLight3D
var marks_mm: MultiMesh
var mark_i := 0
const MAX_MARKS := 2400
var set_sel := 0
var menu_sel := 0
var hold_t := 0.0
var rep_t := 0.0

var cam: Camera3D
var cam_yaw := 0.0
var cam_mode := 0
var menu_angle := 0.0
var hud
var testing := false
var auto_player := false

# Ääni
var audio_player: AudioStreamPlayer
var audio_pb: AudioStreamGeneratorPlayback
var phase := 0.0
var lp_engine := 0.0
var lp_noise := 0.0
var noise_rng := RandomNumberGenerator.new()
var snd_throttle := 0.0
var snd_speed := 0.0


func _ready() -> void:
	_setup_inputs()
	_setup_world()
	track = TrackScript.new()
	track.build()
	track.build_visuals(self)
	_setup_marks()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.game = self
	layer.add_child(hud)
	hud.build_map(track)

	_load_save()
	_setup_audio()
	_apply_settings()
	_spawn_cars()

	if "--autotest" in OS.get_cmdline_user_args():
		testing = true
		auto_player = true
		_run_autotest()
		get_tree().quit()


# ---------------------------------------------------------------- asetukset

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _jbtn(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e


func _jaxis(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	return e


func _action(name: String, events: Array, deadzone: float = 0.2) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, deadzone)
	for e in events:
		InputMap.action_add_event(name, e)


func _setup_inputs() -> void:
	_action("accel", [_key(KEY_W), _key(KEY_UP), _jbtn(JOY_BUTTON_A), _jaxis(JOY_AXIS_TRIGGER_RIGHT, 1.0)], 0.1)
	_action("brake", [_key(KEY_S), _key(KEY_DOWN), _jbtn(JOY_BUTTON_B), _jaxis(JOY_AXIS_TRIGGER_LEFT, 1.0)], 0.1)
	_action("steer_left", [_key(KEY_A), _key(KEY_LEFT), _jbtn(JOY_BUTTON_DPAD_LEFT), _jaxis(JOY_AXIS_LEFT_X, -1.0)], 0.15)
	_action("steer_right", [_key(KEY_D), _key(KEY_RIGHT), _jbtn(JOY_BUTTON_DPAD_RIGHT), _jaxis(JOY_AXIS_LEFT_X, 1.0)], 0.15)
	_action("handbrake", [_key(KEY_SPACE), _jbtn(JOY_BUTTON_RIGHT_SHOULDER), _jbtn(JOY_BUTTON_LEFT_SHOULDER)])
	_action("menu_up", [_key(KEY_UP), _key(KEY_W), _jbtn(JOY_BUTTON_DPAD_UP), _jaxis(JOY_AXIS_LEFT_Y, -1.0)], 0.5)
	_action("menu_down", [_key(KEY_DOWN), _key(KEY_S), _jbtn(JOY_BUTTON_DPAD_DOWN), _jaxis(JOY_AXIS_LEFT_Y, 1.0)], 0.5)
	_action("camera", [_key(KEY_C), _jbtn(JOY_BUTTON_Y)])
	_action("reset", [_key(KEY_R), _jbtn(JOY_BUTTON_X)])
	_action("pause", [_key(KEY_ESCAPE), _key(KEY_P), _jbtn(JOY_BUTTON_START)])
	_action("confirm", [_key(KEY_ENTER), _key(KEY_KP_ENTER), _jbtn(JOY_BUTTON_A)])
	_action("back", [_key(KEY_BACKSPACE), _jbtn(JOY_BUTTON_BACK)])
	_action("fullscreen", [_key(KEY_F11)])


func _setup_world() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.14, 0.34, 0.76)
	sm.sky_horizon_color = Color(0.74, 0.84, 0.94)
	sm.ground_horizon_color = Color(0.74, 0.84, 0.94)
	sm.sky_curve = 0.12
	sm.sun_angle_max = 30.0
	sm.ground_bottom_color = Color(0.3, 0.38, 0.3)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.82, 0.92)
	env.fog_density = 0.0012
	env.fog_sun_scatter = 0.3
	env.tonemap_white = 5.0
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -40, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.shadow_blur = 1.6
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)

	cam = Camera3D.new()
	cam.fov = 72.0
	cam.near = 0.3
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()


func _setup_audio() -> void:
	noise_rng.seed = 5
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.15
	audio_player = AudioStreamPlayer.new()
	audio_player.stream = gen
	add_child(audio_player)
	audio_player.play()
	var pb := audio_player.get_stream_playback()
	if pb is AudioStreamGeneratorPlayback:
		audio_pb = pb


func _load_save() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	difficulty = int(cf.get_value("game", "difficulty", 1))
	for k in DEFAULTS.keys():
		var def_v = DEFAULTS[k]
		var v = cf.get_value("settings", k, def_v)
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			settings[k] = v
	for d in 3:
		var v: float = float(cf.get_value("best", str(d), INF))
		if v < INF:
			best_laps[d] = v


func _save() -> void:
	if testing:
		return
	var cf := ConfigFile.new()
	cf.set_value("game", "difficulty", difficulty)
	for k in settings.keys():
		cf.set_value("settings", k, settings[k])
	for d in best_laps.keys():
		cf.set_value("best", str(d), best_laps[d])
	cf.save(SAVE_PATH)


# ---------------------------------------------------------------- renkaiden jäljet

func _setup_marks() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.01, 1.1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.01, 0.01, 0.01, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = mat
	marks_mm = MultiMesh.new()
	marks_mm.transform_format = MultiMesh.TRANSFORM_3D
	marks_mm.mesh = bm
	marks_mm.instance_count = MAX_MARKS
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = marks_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_clear_marks()


func _clear_marks() -> void:
	if marks_mm == null:
		return
	var away := Transform3D(Basis(), Vector3(0, -100, 0))
	for i in MAX_MARKS:
		marks_mm.set_instance_transform(i, away)
	mark_i = 0


func _emit_marks_for(c, dt: float) -> void:
	if not c.skid:
		c.mark_acc = 1.2
		return
	c.mark_acc += c.vel.length() * dt
	if c.mark_acc < 0.6:
		return
	c.mark_acc = 0.0
	var heading: float = c.yaw
	if c.vel.length() > 3.0:
		heading = atan2(-c.vel.x, -c.vel.y)
	var basis := Basis(Vector3.UP, heading)
	var f: Vector2 = c.forward()
	var r: Vector2 = c.right()
	for side in [-0.98, 0.98]:
		var p: Vector2 = c.pos + r * side - f * 1.35
		marks_mm.set_instance_transform(mark_i, Transform3D(basis, Vector3(p.x, 0.045, p.y)))
		mark_i = (mark_i + 1) % MAX_MARKS


# ---------------------------------------------------------------- asetukset (valikko)

func laps_total() -> int:
	return roundi(float(settings["laps"]))


func setting_text(row: Dictionary) -> String:
	var v = settings[row["key"]]
	if row["type"] == "num":
		var val := float(v) * float(row.get("mult", 1.0))
		if row.get("int", false):
			return String(row["fmt"]) % int(roundf(val))
		return String(row["fmt"]) % val
	if row["type"] == "choice":
		return String(row["choices"][int(v)])
	return ""


func _adjust_setting(row: Dictionary, dir: int) -> void:
	var key: String = row["key"]
	if row["type"] == "num":
		var step: float = float(row["step"])
		var nv := clampf(snappedf(float(settings[key]) + dir * step, step), float(row["min"]), float(row["max"]))
		settings[key] = nv
	elif row["type"] == "choice":
		var n: int = row["choices"].size()
		settings[key] = (int(settings[key]) + dir + n) % n
	_apply_settings()


func _apply_settings() -> void:
	var dz := float(settings["deadzone"])
	InputMap.action_set_deadzone("steer_left", dz)
	InputMap.action_set_deadzone("steer_right", dz)
	cam_mode = int(settings["cam"])
	var hq := int(settings["quality"]) == 1
	if sun != null:
		sun.shadow_enabled = hq
	if env != null:
		env.glow_enabled = hq
		env.adjustment_enabled = hq
	get_viewport().msaa_3d = Viewport.MSAA_4X if hq else Viewport.MSAA_DISABLED
	for c in cars:
		c.fx_on = hq
	if audio_player != null:
		var vol := float(settings["volume"]) / 100.0
		audio_player.volume_db = linear_to_db(vol) if vol > 0.001 else -80.0


func _open_settings() -> void:
	settings_open = true
	set_sel = 0
	hold_t = 0.0


func _close_settings() -> void:
	settings_open = false
	_apply_settings()
	_save()
	if state == S_MENU:
		_spawn_cars()


func _handle_settings_input(dt: float) -> void:
	var n := SETTING_ROWS.size()
	if Input.is_action_just_pressed("menu_down"):
		set_sel = (set_sel + 1) % n
	if Input.is_action_just_pressed("menu_up"):
		set_sel = (set_sel + n - 1) % n
	var row: Dictionary = SETTING_ROWS[set_sel]

	var dir := 0
	if Input.is_action_just_pressed("steer_left"):
		dir = -1
		hold_t = 0.0
		rep_t = 0.0
	elif Input.is_action_just_pressed("steer_right"):
		dir = 1
		hold_t = 0.0
		rep_t = 0.0
	elif Input.is_action_pressed("steer_left") or Input.is_action_pressed("steer_right"):
		hold_t += dt
		if hold_t > 0.4:
			rep_t -= dt
			if rep_t <= 0.0:
				dir = -1 if Input.is_action_pressed("steer_left") else 1
				rep_t = 0.07
	else:
		hold_t = 0.0
	if dir != 0 and row["type"] != "action":
		_adjust_setting(row, dir)

	if Input.is_action_just_pressed("confirm") and row["type"] == "action":
		if row["key"] == "_reset":
			settings = DEFAULTS.duplicate()
			_apply_settings()
		else:
			_close_settings()
			return
	if Input.is_action_just_pressed("back") or Input.is_action_just_pressed("pause"):
		_close_settings()


# ---------------------------------------------------------------- kisan kulku

func _spawn_cars() -> void:
	for c in cars:
		c.queue_free()
	cars.clear()
	_clear_marks()
	var base: float = DIFF_SKILL[difficulty]
	var ai_count := clampi(roundi(float(settings["ai"])), 0, AI_NAMES.size())
	var player_slot := mini(3, ai_count)
	var ai_i := 0
	for slot in ai_count + 1:
		var c = CarScript.new()
		add_child(c)
		if slot == player_slot:
			c.setup(track, PLAYER_COLOR, "Sinä", true, 1.0)
			player = c
		else:
			var sk: float = base - ai_i * 0.012 + noise_rng.randf_range(-0.01, 0.01)
			c.setup(track, AI_COLORS[ai_i], AI_NAMES[ai_i], false, sk)
			c.line_gain = noise_rng.randf_range(0.7, 1.1)
			c.lane_bias = noise_rng.randf_range(-1.5, 1.5)
			ai_i += 1
		var row := slot / 2
		var col := slot % 2
		c.place(-10.0 - row * 10.0, 3.2 if col == 0 else -3.2)
		c.fx_on = int(settings["quality"]) == 1
		cars.append(c)
	_compute_ranks()
	wrong_way = false
	lap_msg_t = 0.0
	go_t = 0.0


func _start_race() -> void:
	_spawn_cars()
	state = S_COUNTDOWN
	count_t = 0.0
	race_time = 0.0
	finish_count = 0
	paused = false
	_save()


func _to_menu() -> void:
	_spawn_cars()
	state = S_MENU
	paused = false


func _compute_ranks() -> void:
	var arr: Array = cars.duplicate()
	arr.sort_custom(func(a, b):
		if a.finished != b.finished:
			return a.finished
		if a.finished:
			return a.finish_pos < b.finish_pos
		return a.progress > b.progress)
	for i in arr.size():
		arr[i].rank = i + 1


func _read_player_input() -> void:
	player.in_throttle = Input.get_action_strength("accel")
	player.in_brake = Input.get_action_strength("brake")
	var raw := Input.get_axis("steer_left", "steer_right")
	var st := signf(raw) * pow(absf(raw), 1.0 / float(settings["sens"]))
	var assist_k: float = [0.0, 0.35, 0.7][int(settings["assist"])]
	if assist_k > 0.0 and player.speed() > 3.0 and player.forward().dot(track.tangents[player.idx]) > 0.2:
		st = lerpf(st, player.assist_steer(), assist_k * (1.0 - absf(st)))
	player.in_steer = clampf(st, -1.0, 1.0)
	player.in_hbrake = Input.is_action_pressed("handbrake")


func _sim_step(dt: float) -> void:
	if state == S_COUNTDOWN:
		count_t += dt
		if count_t >= 3.0:
			state = S_RACE
			go_t = 1.2
			race_time = 0.0
		return

	if state != S_RACE and state != S_RESULTS:
		return

	race_time += dt
	go_t = maxf(0.0, go_t - dt)
	lap_msg_t = maxf(0.0, lap_msg_t - dt)

	for c in cars:
		var pace_mul := 1.0
		if not c.is_player and int(settings["rubber"]) == 1:
			var gap: float = player.progress - c.progress
			pace_mul = 1.0 + clampf(gap / 300.0, -1.0, 1.0) * 0.04
		if c.is_player and not c.finished and not auto_player:
			_read_player_input()
		else:
			var cap := pace_mul
			if c.finished:
				cap = 0.5
			c.ai_drive(dt, cars, cap)
		c.step(dt, race_time, laps_total())
		_emit_marks_for(c, dt)

	_collide_cars()

	for c in cars:
		# Jumissa olevat autot takaisin radalle
		if absf(c.speed()) < 2.0 and race_time > 3.0 and not c.finished:
			c.stuck_t += dt
		else:
			c.stuck_t = 0.0
		var limit := 6.0 if c.is_player and not auto_player else 2.5
		if c.stuck_t > limit:
			c.reset_to_track()

		if c.lap_flag:
			c.lap_flag = false
			if c.is_player:
				lap_msg = "Kierros %d: %s" % [c.lap, hud._fmt_time(c.last_lap)]
				lap_msg_t = 3.0
				var rec: float = best_laps.get(difficulty, INF)
				if c.last_lap < rec:
					best_laps[difficulty] = c.last_lap
					lap_msg += "   (uusi ennätys!)"
					_save()
		if c.finished and c.finish_pos == 0:
			finish_count += 1
			c.finish_pos = finish_count
			if c.is_player:
				state = S_RESULTS

	_compute_ranks()

	var tg: Vector2 = track.tangents[player.idx]
	wrong_way = player.speed() > 6.0 and player.forward().dot(tg) < -0.3


func _collide_cars() -> void:
	var radius := 1.25
	var min_d := radius * 2.0
	for i in cars.size():
		for j in range(i + 1, cars.size()):
			var a = cars[i]
			var b = cars[j]
			if a.pos.distance_squared_to(b.pos) > 25.0:
				continue
			var fa: Vector2 = a.forward()
			var fb: Vector2 = b.forward()
			for oa in [-1.3, 1.3]:
				for ob in [-1.3, 1.3]:
					var pa: Vector2 = a.pos + fa * oa
					var pb: Vector2 = b.pos + fb * ob
					var d := pa - pb
					var dist := d.length()
					if dist < min_d and dist > 0.001:
						var nrm := d / dist
						var overlap := min_d - dist
						a.pos += nrm * overlap * 0.5
						b.pos -= nrm * overlap * 0.5
						var rv: float = (a.vel - b.vel).dot(nrm)
						if rv < 0.0:
							var imp: float = -(1.0 + 0.25) * rv * 0.5
							a.vel += nrm * imp
							b.vel -= nrm * imp
							a.bump(-rv)
							b.bump(-rv)


# ---------------------------------------------------------------- silmukka

func _process(delta: float) -> void:
	if testing:
		return
	var dt := minf(delta, 0.1)

	_handle_ui_input(dt)

	if state == S_MENU:
		menu_angle += dt * 0.25
	elif not paused:
		var remaining := dt
		while remaining > 0.0:
			var h := minf(remaining, 1.0 / 90.0)
			_sim_step(h)
			remaining -= h
	for c in cars:
		c.update_visual(dt if not paused else 0.0)

	_update_camera(dt)
	_update_audio()
	hud.queue_redraw()


func _handle_ui_input(dt: float) -> void:
	if Input.is_action_just_pressed("fullscreen"):
		var m := DisplayServer.window_get_mode()
		if m == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	if help_open:
		if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("back") or Input.is_action_just_pressed("pause"):
			help_open = false
		return
	if settings_open:
		_handle_settings_input(dt)
		return

	match state:
		S_MENU:
			if Input.is_action_just_pressed("menu_down"):
				menu_sel = (menu_sel + 1) % 4
			if Input.is_action_just_pressed("menu_up"):
				menu_sel = (menu_sel + 3) % 4
			if Input.is_action_just_pressed("steer_left"):
				difficulty = (difficulty + 2) % 3
				_spawn_cars()
				_save()
			if Input.is_action_just_pressed("steer_right"):
				difficulty = (difficulty + 1) % 3
				_spawn_cars()
				_save()
			if Input.is_action_just_pressed("confirm"):
				if menu_sel == 2:
					_open_settings()
				elif menu_sel == 3:
					help_open = true
				else:
					_start_race()
			elif Input.is_action_just_pressed("pause"):
				_start_race()
		S_COUNTDOWN, S_RACE:
			if Input.is_action_just_pressed("pause"):
				paused = not paused
			if paused:
				if Input.is_action_just_pressed("confirm"):
					_open_settings()
				elif Input.is_action_just_pressed("back"):
					_to_menu()
			else:
				if Input.is_action_just_pressed("back"):
					_start_race()
				if Input.is_action_just_pressed("camera"):
					cam_mode = (cam_mode + 1) % 3
					settings["cam"] = cam_mode
				if Input.is_action_just_pressed("reset") and state == S_RACE:
					player.reset_to_track()
		S_RESULTS:
			if Input.is_action_just_pressed("confirm"):
				_start_race()
			if Input.is_action_just_pressed("back"):
				_to_menu()
			if Input.is_action_just_pressed("camera"):
				cam_mode = (cam_mode + 1) % 3
				settings["cam"] = cam_mode


func _update_camera(dt: float) -> void:
	if state == S_MENU:
		var gs := -22.0
		var g: Vector2 = track.pos_at(gs)
		var d: Vector2 = track.dir_at(gs)
		var r: Vector2 = -track.normal_at(gs)
		var a := 0.9 + sin(menu_angle * 0.8) * 0.55
		var c2: Vector2 = g + d * (cos(a) * 17.0) + r * (sin(a) * 17.0)
		cam.global_position = Vector3(c2.x, 3.4, c2.y)
		cam.look_at(Vector3(g.x, 0.9, g.y))
		cam.fov = 62.0
		player.visible = true
		return

	var pc: Vector3 = Vector3(player.pos.x, 0.0, player.pos.y)
	var sp: float = player.speed()
	cam_yaw = lerp_angle(cam_yaw, player.yaw, 1.0 - exp(-6.0 * dt))
	if cam_mode == 2 and state != S_RESULTS:
		var fwd := Vector3(-sin(player.yaw), 0.0, -cos(player.yaw))
		cam.global_position = pc + Vector3.UP * 1.05 + fwd * 0.2
		cam.look_at(cam.global_position + fwd * 10.0 + Vector3.DOWN * 0.1)
		cam.fov = float(settings["fov"]) + 10.0 + clampf(sp, 0.0, 72.0) * 0.2
		player.visible = false
		return
	player.visible = true
	var dist := 9.0
	var height := 3.6
	if cam_mode == 1:
		dist = 14.0
		height = 5.6
	dist += clampf(sp, 0.0, 72.0) * 0.035
	var f3 := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	cam.global_position = pc - f3 * dist + Vector3.UP * height
	cam.look_at(pc + Vector3.UP * 1.2 + f3 * 5.0)
	cam.fov = lerpf(cam.fov, float(settings["fov"]) + clampf(absf(sp), 0.0, 72.0) * 0.35, 1.0 - exp(-4.0 * dt))
	if player.impact > 3.0 and int(settings["shake"]) == 1:
		cam.global_position += Vector3(noise_rng.randf_range(-1, 1), noise_rng.randf_range(-1, 1), noise_rng.randf_range(-1, 1)) * minf(player.impact * 0.01, 0.25)


# ---------------------------------------------------------------- ääni

func _update_audio() -> void:
	if audio_pb == null:
		return
	var avail := audio_pb.get_frames_available()
	if avail <= 0:
		return
	var running := state != S_MENU and not paused
	var sp_target: float = absf(player.speed()) if running else 0.0
	var th_target: float = player.in_throttle if running else 0.0
	snd_speed = lerpf(snd_speed, sp_target, 0.2)
	snd_throttle = lerpf(snd_throttle, th_target, 0.2)
	var gear := mini(int(snd_speed / 16.0), 4)
	var frac := fmod(snd_speed, 16.0) / 16.0
	if gear == 4:
		frac = clampf((snd_speed - 64.0) / 16.0, 0.0, 1.0)
	var freq := 48.0 + frac * 100.0 + gear * 14.0 + snd_throttle * 12.0
	var vol := 0.10 + 0.10 * snd_throttle
	var screech: float = clampf((player.slip - 4.0) / 10.0, 0.0, 1.0) if running else 0.0
	if player.on_grass and running:
		screech = maxf(screech, clampf(snd_speed / 60.0, 0.0, 0.6))
	var imp: float = clampf(player.impact / 15.0, 0.0, 1.0) if running else 0.0

	var buf := PackedVector2Array()
	buf.resize(avail)
	var inc := freq / 22050.0
	for i in avail:
		phase += inc
		if phase >= 1.0:
			phase -= 1.0
		var saw := phase * 2.0 - 1.0
		var s := saw * 0.35 + sin(phase * TAU * 2.0) * 0.3 + (1.0 if phase < 0.3 else -1.0) * 0.1
		lp_engine += (s - lp_engine) * 0.3
		var nz := noise_rng.randf() * 2.0 - 1.0
		lp_noise += (nz - lp_noise) * 0.5
		var hiss := (nz - lp_noise) * screech * 0.25
		var thud := lp_noise * imp * 0.8
		var v := lp_engine * vol + hiss + thud
		buf[i] = Vector2(v, v)
	audio_pb.push_buffer(buf)


# ---------------------------------------------------------------- automaattitesti

func _run_autotest() -> void:
	print("Radan pituus: %.0f m, pisteitä: %d" % [track.length, track.n])
	var maxc := 0.0
	for c in track.curv:
		maxc = maxf(maxc, absf(c))
	print("Suurin kaarevuus: %.4f (pienin säde %.1f m)" % [maxc, 1.0 / maxc])
	var min_sep := 1e9
	for i in range(0, track.n, 4):
		for j in range(i + 30, track.n, 4):
			if j - i > track.n - 30:
				continue
			min_sep = minf(min_sep, track.pts[i].distance_to(track.pts[j]))
	print("Radan osien pienin etäisyys toisistaan: %.1f m (vallien välissä tarvitaan > 28)" % min_sep)

	_start_race()
	var t := 0.0
	var dt := 1.0 / 60.0
	var maxspeed := 0.0
	var steps := 0
	while steps < 60 * 400:
		_sim_step(dt)
		steps += 1
		for c in cars:
			maxspeed = maxf(maxspeed, c.vel.length())
		var all_done := true
		for c in cars:
			if not c.finished:
				all_done = false
		if all_done:
			break
	print("Simulaatio kesti %.1f s, suurin nopeus %.1f m/s (%.0f km/h)" % [steps * dt, maxspeed, maxspeed * 3.6])
	var arr: Array = cars.duplicate()
	arr.sort_custom(func(a, b): return a.finish_pos < b.finish_pos if (a.finished and b.finished) else a.finished)
	for c in arr:
		print("%d. %-6s  aika %s  paras kierros %.2f  palautuksia %d  seinäosumia %d" % [c.finish_pos, c.car_name, hud._fmt_time(c.finish_time) if c.finished else "kesken", c.best_lap, c.reset_count, c.wall_hits])

