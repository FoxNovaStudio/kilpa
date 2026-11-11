extends Node3D
## Auto: fysiikka, 3D-malli ja tekoälykuljettaja

const TrackScript = preload("res://track.gd")

const ACCEL := 24.0        # kiihtyvyys (m/s²)
const BRAKE := 36.0        # jarrutus (m/s²)
const REV_ACCEL := 14.0
const REV_MAX := 14.0
const STEER_RATE := 2.6
const MAX_LAT_ACC := 38.0  # pitorajoitus kaarteessa
const CAR_HALF_W := 1.0
const AI_BRAKE := 24.0

var track
var is_player := false
var car_name := ""
var color := Color.RED
var skill := 1.0
var max_speed := 72.0
var corner_acc := 24.0

# Tila
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var yaw := 0.0
var steer := 0.0
var idx := 0
var lap := -1
var max_lap := -1
var lap_start := 0.0
var last_lap := 0.0
var best_lap := INF
var finished := false
var finish_time := 0.0
var finish_pos := 0
var progress := 0.0
var rank := 1
var lap_flag := false

# Ohjaus (pelaaja tai tekoäly)
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0
var in_hbrake := false

# Tekoäly
var lane_cur := 0.0
var line_gain := 1.0
var lane_bias := 0.0
var pace := 1.0

# Tilatiedot äänille ja nollauksille
var slip := 0.0
var impact := 0.0
var on_grass := false
var stuck_t := 0.0
var reset_count := 0
var wall_hits := 0
var last_accel := 0.0

# Mallit
var body: Node3D
var wheel_pivots: Array = []
var wheel_spins: Array = []
var tail_mat: StandardMaterial3D
var roll := 0.0
var pitch := 0.0

# Tehosteet
var smoke: CPUParticles3D
var dust: CPUParticles3D
var sparks: CPUParticles3D
var spark_flag := false
var skid := false
var mark_acc := 1.2
var fx_on := true


func forward() -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


func right() -> Vector2:
	return Vector2(cos(yaw), -sin(yaw))


func speed() -> float:
	return vel.dot(forward())


func setup(p_track, p_color: Color, p_name: String, p_player: bool, p_skill: float) -> void:
	track = p_track
	color = p_color
	car_name = p_name
	is_player = p_player
	skill = p_skill
	if is_player:
		max_speed = 72.0 * track.top_k
	else:
		max_speed = 72.0 * track.top_k * skill
	corner_acc = (19.0 + (skill - 0.8) * 55.0) * track.grip
	_build_model()


func place(s: float, lateral: float) -> void:
	var p: Vector2 = track.pos_at(s) + track.normal_at(s) * lateral
	pos = p
	yaw = TrackScript.yaw_of(track.dir_at(s))
	vel = Vector2.ZERO
	steer = 0.0
	lane_cur = lateral
	idx = track.nearest(pos, -1)
	lap = -1
	max_lap = -1
	lap_start = 0.0
	finished = false
	update_visual(0.0)


func reset_to_track() -> void:
	idx = track.nearest(pos, -1)
	pos = track.pts[idx]
	yaw = TrackScript.yaw_of(track.tangents[idx])
	vel = Vector2.ZERO
	steer = 0.0
	lane_cur = 0.0
	stuck_t = 0.0
	reset_count += 1


# ---------------------------------------------------------------- fysiikka

func step(dt: float, now: float, laps_total: int) -> void:
	var f := forward()
	var sp := vel.dot(f)

	var off: float = (pos - track.pts[idx]).dot(track.normals[idx])
	var aoff := absf(off)
	on_grass = aoff > track.road_half + track.curb_w
	var top := max_speed
	if on_grass:
		top *= track.off_k
	var gk: float = track.grip
	var acc_k := 0.6 + 0.4 * gk
	var brk_k := 0.5 + 0.5 * gk

	# Kaasu ja jarru
	var a := 0.0
	if in_throttle > 0.01:
		if sp < -0.5:
			a = BRAKE * brk_k * in_throttle
		else:
			a = ACCEL * acc_k * in_throttle * clampf(1.0 - maxf(sp, 0.0) / top, 0.0, 1.0)
	if in_brake > 0.01:
		if sp > 0.5:
			a = -BRAKE * brk_k * in_brake
		else:
			a = -REV_ACCEL * in_brake * clampf(1.0 + sp / REV_MAX, 0.0, 1.0)
	if in_throttle <= 0.01 and in_brake <= 0.01:
		a = -signf(sp) * minf(absf(sp) / maxf(dt, 0.001), 3.0 + absf(sp) * 0.05)
	if in_hbrake and absf(sp) > 1.0:
		a -= signf(sp) * 10.0
	if sp > top:
		a -= (sp - top) * 2.5
	last_accel = a

	# Ohjaus
	var target_steer := clampf(in_steer, -1.0, 1.0)
	var rate := 6.0 if absf(target_steer) > absf(steer) else 9.0
	steer = move_toward(steer, target_steer, rate * dt)
	var sfac := 1.0 / (1.0 + absf(sp) / 30.0)
	var yaw_rate := steer * STEER_RATE * sfac * clampf(absf(sp) / 5.0, 0.0, 1.0) * signf(sp)
	if in_hbrake:
		yaw_rate *= 1.4
	var max_rate := MAX_LAT_ACC * gk / maxf(absf(sp), 1.0)
	yaw_rate = clampf(yaw_rate, -max_rate, max_rate)
	yaw -= yaw_rate * dt

	# Sivuttaispito
	var f2 := forward()
	var r2 := right()
	var longv := vel.dot(f2) + a * dt
	var lat := vel.dot(r2)
	var grip := 7.5 * (0.35 + 0.65 * gk)
	if in_hbrake:
		grip = 2.2 * (0.5 + 0.5 * gk)
	if on_grass:
		grip = 4.0 * (0.5 + 0.5 * gk)
	lat *= 1.0 - minf(1.0, grip * dt)
	slip = absf(lat)
	skid = not on_grass and ((slip > (3.5 if gk > 0.9 else 2.2) and absf(sp) > 8.0) or (in_brake > 0.55 and sp > 22.0) or (in_hbrake and absf(sp) > 8.0))
	vel = f2 * longv + r2 * lat
	pos += vel * dt

	# Rata-asema ja kierrokset
	var old_idx := idx
	idx = track.nearest(pos, old_idx)
	var q: int = track.n
	if old_idx > q * 3 / 4 and idx < q / 4:
		lap += 1
		_on_new_lap(now, laps_total)
	elif old_idx < q / 4 and idx > q * 3 / 4:
		lap -= 1

	# Reunavalli
	var nrm: Vector2 = track.normals[idx]
	var off2: float = (pos - track.pts[idx]).dot(nrm)
	var lim: float = track.wall_offset - CAR_HALF_W - 0.2
	if absf(off2) > lim:
		var sgn := signf(off2)
		pos -= nrm * sgn * (absf(off2) - lim)
		var vn: float = vel.dot(nrm) * sgn
		if vn > 0.0:
			vel -= nrm * sgn * vn * 1.25
			vel *= 1.0 - clampf(vn * 0.012, 0.0, 0.3)
			if vn > 2.0:
				wall_hits += 1
				spark_flag = true
			impact = maxf(impact, vn)
		vel *= 0.995

	var t: Vector2 = track.tangents[idx]
	var s_along: float = track.dist[idx] + (pos - track.pts[idx]).dot(t)
	progress = lap * track.length + s_along

	impact = maxf(0.0, impact - dt * 18.0)


func _on_new_lap(now: float, laps_total: int) -> void:
	if lap <= max_lap:
		return
	max_lap = lap
	if lap >= 1:
		last_lap = now - lap_start
		if last_lap < best_lap:
			best_lap = last_lap
		lap_start = now
		lap_flag = true
	if lap >= laps_total and not finished:
		finished = true
		finish_time = now


func assist_steer() -> float:
	# Ohjausapu: pitää auton radan suunnassa nykyisellä sivuttaisasemalla
	var f := forward()
	var sp := vel.dot(f)
	var my_off: float = (pos - track.pts[idx]).dot(track.normals[idx])
	var look: float = 8.0 + maxf(sp, 0.0) * 0.38
	var s_t: float = track.dist[idx] + look
	var tp: Vector2 = track.pos_at(s_t) + track.normal_at(s_t) * clampf(my_off, -track.road_half * 0.56, track.road_half * 0.56)
	return clampf(f.angle_to(tp - pos) * 2.4, -1.0, 1.0)


func bump(strength: float) -> void:
	impact = maxf(impact, strength)


# ---------------------------------------------------------------- tekoäly

func ai_drive(dt: float, cars: Array, speed_cap: float) -> void:
	var f := forward()
	var sp := vel.dot(f)
	var my_off: float = (pos - track.pts[idx]).dot(track.normals[idx])
	var look: float = 8.0 + maxf(sp, 0.0) * 0.38
	var s_here: float = track.dist[idx]

	# Ihanteellinen linja: kaarteen sisäreunaa
	var ci_far: int = (idx + int((look * 2.0) / track.step)) % track.n
	var c_far: float = track.curv[ci_far]
	var lane_lim: float = track.road_half * 0.56
	var dodge_w: float = clampf(track.road_half * 0.45, 2.2, 3.6)
	var lane_goal: float = clampf(-c_far * 260.0, -lane_lim, lane_lim) * line_gain + lane_bias * minf(1.0, track.road_half / 8.0)

	# Väistö ja jonossa ajo
	var block_speed := 1000.0
	for o in cars:
		if o == self:
			continue
		var rel: Vector2 = o.pos - pos
		var ahead := rel.dot(f)
		if ahead > 1.0 and ahead < 18.0:
			var side := rel.dot(right())
			if absf(side) < 3.0:
				var o_off: float = (o.pos - track.pts[o.idx]).dot(track.normals[o.idx])
				var dodge := o_off - dodge_w if my_off <= o_off else o_off + dodge_w
				if absf(dodge) > track.road_half * 0.78:
					dodge = o_off + dodge_w if dodge < 0.0 else o_off - dodge_w
				lane_goal = clampf(dodge, -track.road_half * 0.78, track.road_half * 0.78)
				if ahead < 9.0 and absf(side) < 2.3:
					block_speed = minf(block_speed, maxf(o.speed(), 6.0))
				break
	lane_cur = move_toward(lane_cur, lane_goal, 5.0 * dt)

	# Ohjaus kohdepisteeseen
	var s_t := s_here + look
	var tp: Vector2 = track.pos_at(s_t) + track.normal_at(s_t) * lane_cur
	var local := tp - pos
	var ang := f.angle_to(local)
	in_steer = clampf(ang * 2.4, -1.0, 1.0)

	# Nopeussuunnittelu: jarruta ennen kaarretta
	var target := max_speed * speed_cap
	var brake_dec: float = AI_BRAKE * (0.5 + 0.5 * track.grip)
	var max_d := 30.0 + maxf(sp, 0.0) * 2.2
	var d := 6.0
	while d < max_d:
		var cidx: int = (idx + int(d / track.step)) % track.n
		var c := absf(track.curv[cidx])
		if c > 0.002:
			var v_c: float = maxf(sqrt(corner_acc / c), 9.0 + 5.0 * track.grip)
			var v_allow := sqrt(v_c * v_c + 2.0 * brake_dec * d)
			target = minf(target, v_allow)
		d += 6.0
	target = minf(target, block_speed)

	in_hbrake = false
	if sp < target - 0.5:
		in_throttle = clampf((target - sp) / 5.0, 0.15, 1.0)
		in_brake = 0.0
	elif sp > target + 1.5:
		in_throttle = 0.0
		in_brake = clampf((sp - target) / 6.0, 0.0, 1.0)
	else:
		in_throttle = 0.35
		in_brake = 0.0


# ---------------------------------------------------------------- 3D-malli

func _mat(c: Color, rough: float = 0.5, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(parent: Node3D, size: Vector3, p: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = p
	parent.add_child(mi)
	return mi


func _build_model() -> void:
	body = Node3D.new()
	add_child(body)
	var paint := _mat(color, 0.22, 0.55)
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.8
	paint.clearcoat_roughness = 0.08
	var dark := _mat(Color(0.05, 0.06, 0.08), 0.2, 0.6)
	var trim := _mat(Color(0.1, 0.1, 0.11), 0.7)
	var light_c := color.lightened(0.35)
	var roof := _mat(light_c, 0.3, 0.4)

	_box(body, Vector3(1.9, 0.5, 4.2), Vector3(0, 0.6, 0), paint)
	_box(body, Vector3(1.7, 0.18, 1.5), Vector3(0, 0.92, -1.15), paint)       # konepelti
	_box(body, Vector3(1.6, 0.5, 1.9), Vector3(0, 1.1, 0.35), dark)           # ohjaamo (lasi)
	_box(body, Vector3(1.5, 0.1, 1.5), Vector3(0, 1.38, 0.35), roof)          # katto
	_box(body, Vector3(1.95, 0.1, 0.3), Vector3(0, 0.38, -2.05), trim)        # etuhelma
	_box(body, Vector3(1.95, 0.1, 0.3), Vector3(0, 0.38, 2.05), trim)         # takahelma
	# Siipi
	_box(body, Vector3(1.9, 0.07, 0.55), Vector3(0, 1.28, 1.95), trim)
	_box(body, Vector3(0.08, 0.35, 0.3), Vector3(0.7, 1.08, 1.95), trim)
	_box(body, Vector3(0.08, 0.35, 0.3), Vector3(-0.7, 1.08, 1.95), trim)
	# Valot
	var head := StandardMaterial3D.new()
	head.albedo_color = Color(1.0, 0.95, 0.7)
	head.emission_enabled = true
	head.emission = Color(1.0, 0.95, 0.7)
	head.emission_energy_multiplier = 1.8
	_box(body, Vector3(0.45, 0.16, 0.08), Vector3(0.65, 0.68, -2.12), head)
	_box(body, Vector3(0.45, 0.16, 0.08), Vector3(-0.65, 0.68, -2.12), head)
	tail_mat = StandardMaterial3D.new()
	tail_mat.albedo_color = Color(0.8, 0.0, 0.0)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.05, 0.05)
	tail_mat.emission_energy_multiplier = 0.6
	_box(body, Vector3(0.5, 0.16, 0.08), Vector3(0.6, 0.7, 2.12), tail_mat)
	_box(body, Vector3(0.5, 0.16, 0.08), Vector3(-0.6, 0.7, 2.12), tail_mat)

	# Renkaat
	var tire := _mat(Color(0.04, 0.04, 0.04), 0.9)
	var rim := _mat(Color(0.75, 0.75, 0.8), 0.3, 0.8)
	var wheel_pos := [Vector3(0.98, 0.38, -1.35), Vector3(-0.98, 0.38, -1.35), Vector3(0.98, 0.38, 1.35), Vector3(-0.98, 0.38, 1.35)]
	for i in 4:
		var pivot := Node3D.new()
		pivot.position = wheel_pos[i]
		add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.38
		cm.bottom_radius = 0.38
		cm.height = 0.32
		cm.radial_segments = 14
		cm.rings = 1
		var wm := MeshInstance3D.new()
		wm.mesh = cm
		wm.material_override = tire
		wm.rotation_degrees = Vector3(0, 0, 90)
		spin.add_child(wm)
		_box(spin, Vector3(0.34, 0.08, 0.5), Vector3.ZERO, rim)
		_box(spin, Vector3(0.34, 0.5, 0.08), Vector3.ZERO, rim)
		wheel_pivots.append(pivot)
		wheel_spins.append(spin)

	var env_p: Dictionary = track.env_params()
	smoke = _make_emitter(Color(0.86, 0.86, 0.88), 36, 1.1, 1.6, 0.45, Vector3(0, 0.25, 1.4), Vector3(0, 0.5, 0), true, false)
	dust = _make_emitter(env_p["dust"], 40, 0.9, 2.6, 0.4, Vector3(0, 0.25, 1.3), Vector3(0, -1.0, 0), true, false)
	sparks = _make_emitter(Color(1.0, 0.8, 0.3), 24, 0.35, 7.0, 0.05, Vector3(0, 0.5, 0), Vector3(0, -12.0, 0), false, true)


func _make_emitter(col: Color, amount: int, life: float, vel: float, size: float, pos: Vector3, grav: Vector3, grow: bool, burst: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.direction = Vector3.UP
	p.spread = 70.0 if burst else 35.0
	p.initial_velocity_min = vel * 0.5
	p.initial_velocity_max = vel
	p.gravity = grav
	if burst:
		p.one_shot = true
		p.explosiveness = 1.0
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	sm.material = mat
	p.mesh = sm
	p.color = col
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.55 if grow else 1.0))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = grad
	if grow:
		var cv := Curve.new()
		cv.add_point(Vector2(0.0, 0.6))
		cv.add_point(Vector2(1.0, 2.4))
		p.scale_amount_curve = cv
	p.position = pos
	add_child(p)
	return p


func update_visual(dt: float) -> void:
	position = Vector3(pos.x, 0.0, pos.y)
	rotation.y = yaw
	var sp := vel.dot(forward())
	var target_roll := steer * clampf(absf(sp) / 50.0, 0.0, 1.0) * 0.06
	var target_pitch := clampf(last_accel * 0.0025, -0.06, 0.05)
	var k := 1.0 - exp(-10.0 * dt)
	roll = lerpf(roll, target_roll, k)
	pitch = lerpf(pitch, target_pitch, k)
	body.rotation.z = roll
	body.rotation.x = pitch
	for i in 4:
		wheel_spins[i].rotation.x -= sp * dt / 0.38
	wheel_pivots[0].rotation.y = -steer * 0.45
	wheel_pivots[1].rotation.y = -steer * 0.45
	tail_mat.emission_energy_multiplier = 3.5 if (in_brake > 0.1 and sp > 0.5) else 0.6
	var loose: bool = track.surface != "asphalt"
	smoke.emitting = fx_on and skid and not loose and dt > 0.0
	dust.emitting = fx_on and dt > 0.0 and absf(sp) > 12.0 and (on_grass or (loose and (skid or absf(sp) > 20.0)))
	if spark_flag:
		spark_flag = false
		if fx_on:
			sparks.restart()
			sparks.emitting = true
