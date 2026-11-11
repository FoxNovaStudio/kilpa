extends RefCounted
## Rata: keskilinja, mittaukset ja 3D-mallit. Pinta (asfaltti / sora / lumi) tulee radan määrittelystä.

const SPACING := 3.0        # mittauspisteiden väli (metriä)

const ASPHALT_PTS := [
	Vector2(0, 0), Vector2(150, 0), Vector2(290, -10), Vector2(380, -80),
	Vector2(390, -190), Vector2(330, -270), Vector2(230, -300), Vector2(150, -250),
	Vector2(110, -170), Vector2(30, -130), Vector2(-60, -170), Vector2(-110, -250),
	Vector2(-200, -300), Vector2(-310, -280), Vector2(-375, -205), Vector2(-380, -115),
	Vector2(-320, -45), Vector2(-220, -20), Vector2(-100, 0),
]
const GRAVEL_PTS := [Vector2(-265, -25), Vector2(-208, -49), Vector2(-157, -72), Vector2(-119, -96), Vector2(-94, -120), Vector2(-78, -144), Vector2(-67, -161), Vector2(-55, -170), Vector2(-42, -168), Vector2(-26, -157), Vector2(-10, -142), Vector2(4, -128), Vector2(14, -115), Vector2(17, -104), Vector2(16, -90), Vector2(14, -74), Vector2(15, -57), Vector2(22, -42), Vector2(37, -33), Vector2(56, -33), Vector2(76, -39), Vector2(94, -47), Vector2(111, -53), Vector2(130, -55), Vector2(156, -55), Vector2(187, -55), Vector2(221, -55), Vector2(251, -52), Vector2(272, -42), Vector2(283, -23), Vector2(286, 3), Vector2(284, 33), Vector2(277, 58), Vector2(263, 74), Vector2(237, 80), Vector2(198, 81), Vector2(151, 82), Vector2(103, 90), Vector2(64, 104), Vector2(37, 124), Vector2(20, 143), Vector2(3, 157), Vector2(-20, 164), Vector2(-51, 163), Vector2(-86, 155), Vector2(-118, 144), Vector2(-140, 132), Vector2(-154, 121), Vector2(-169, 112), Vector2(-193, 104), Vector2(-231, 96), Vector2(-279, 86), Vector2(-323, 71), Vector2(-349, 51), Vector2(-347, 26), Vector2(-316, 0)]
const SNOW_PTS := [Vector2(141, -235), Vector2(277, -220), Vector2(407, -183), Vector2(498, -131), Vector2(528, -75), Vector2(498, -24), Vector2(427, 13), Vector2(350, 38), Vector2(295, 59), Vector2(275, 83), Vector2(283, 119), Vector2(300, 165), Vector2(300, 212), Vector2(270, 247), Vector2(210, 260), Vector2(132, 245), Vector2(56, 206), Vector2(-7, 155), Vector2(-51, 105), Vector2(-83, 68), Vector2(-110, 50), Vector2(-136, 52), Vector2(-162, 67), Vector2(-184, 89), Vector2(-201, 111), Vector2(-213, 127), Vector2(-227, 136), Vector2(-247, 134), Vector2(-274, 121), Vector2(-302, 99), Vector2(-318, 70), Vector2(-312, 40), Vector2(-282, 11), Vector2(-236, -13), Vector2(-189, -33), Vector2(-159, -52), Vector2(-154, -75), Vector2(-169, -102), Vector2(-191, -133), Vector2(-204, -163), Vector2(-198, -186), Vector2(-174, -198), Vector2(-144, -201), Vector2(-119, -199), Vector2(-102, -200), Vector2(-83, -207), Vector2(-45, -220), Vector2(29, -233)]

# grip = pito (1 = asfaltti), top = huippunopeuden kerroin, off = rata-alueen ulkopuolinen hidastus
const TRACKS := [
	{"name": "Kilparata", "info": "Asfaltti · leveä · nopea", "surface": "asphalt", "pts": ASPHALT_PTS,
		"road_half": 8.0, "curb": 1.6, "wall": 14.0, "grip": 1.0, "top": 1.0, "off": 0.6},
	{"name": "Metsärallia", "info": "Sora · kapea · mutkainen · huono pito", "surface": "gravel", "pts": GRAVEL_PTS,
		"road_half": 4.4, "curb": 0.0, "wall": 8.6, "grip": 0.58, "top": 0.8, "off": 0.8},
	{"name": "Talvirallia", "info": "Lumi · liukas · pitkät kaarteet", "surface": "snow", "pts": SNOW_PTS,
		"road_half": 5.4, "curb": 0.0, "wall": 10.5, "grip": 0.4, "top": 0.74, "off": 0.8},
]

var def: Dictionary = {}
var track_name := ""
var surface := "asphalt"
var road_half := 8.0
var curb_w := 1.6
var wall_offset := 14.0
var wall_h := 1.2
var wall_slope := 0.0
var grip := 1.0
var top_k := 1.0
var off_k := 0.6

var pts := PackedVector2Array()
var tangents := PackedVector2Array()
var normals := PackedVector2Array()   # vasen normaali
var dist := PackedFloat32Array()
var curv := PackedFloat32Array()      # etumerkillinen kaarevuus (+ = oikealle)
var n := 0
var length := 0.0
var step := SPACING
var bounds_min := Vector2.ZERO
var bounds_max := Vector2.ZERO


static func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


static func yaw_of(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


func setup(p_def: Dictionary) -> void:
	def = p_def
	track_name = def["name"]
	surface = def["surface"]
	road_half = float(def["road_half"])
	curb_w = float(def["curb"])
	wall_offset = float(def["wall"])
	grip = float(def["grip"])
	top_k = float(def["top"])
	off_k = float(def["off"])
	if surface == "asphalt":
		wall_h = 1.2
		wall_slope = 0.0
	else:
		wall_h = 1.5
		wall_slope = 1.3
	build()


# Ympäristön asetukset (taivas, sumu, valo) pinnan mukaan
func env_params() -> Dictionary:
	match surface:
		"gravel":
			return {"sky_top": Color(0.2, 0.38, 0.7), "sky_hor": Color(0.78, 0.83, 0.86), "fog": Color(0.7, 0.78, 0.78),
				"fog_density": 0.0022, "sun": 1.45, "sun_col": Color(1.0, 0.93, 0.8), "mark": Color(0.17, 0.12, 0.08, 0.5),
				"dust": Color(0.62, 0.52, 0.38)}
		"snow":
			return {"sky_top": Color(0.45, 0.56, 0.72), "sky_hor": Color(0.86, 0.89, 0.93), "fog": Color(0.84, 0.87, 0.92),
				"fog_density": 0.0026, "sun": 1.1, "sun_col": Color(0.95, 0.96, 1.0), "mark": Color(0.5, 0.55, 0.65, 0.55),
				"dust": Color(0.95, 0.97, 1.0)}
	return {"sky_top": Color(0.14, 0.34, 0.76), "sky_hor": Color(0.74, 0.84, 0.94), "fog": Color(0.72, 0.82, 0.92),
		"fog_density": 0.0012, "sun": 1.6, "sun_col": Color(1.0, 0.94, 0.82), "mark": Color(0.01, 0.01, 0.01, 0.5),
		"dust": Color(0.55, 0.43, 0.29)}


func build() -> void:
	var ctrl: Array = def["pts"]
	var dense := PackedVector2Array()
	var c: int = ctrl.size()
	for i in c:
		var p0: Vector2 = ctrl[(i - 1 + c) % c]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[(i + 1) % c]
		var p3: Vector2 = ctrl[(i + 2) % c]
		for k in 40:
			dense.append(_cr(p0, p1, p2, p3, k / 40.0))
	var d := dense.size()
	var cum := PackedFloat32Array()
	cum.resize(d + 1)
	cum[0] = 0.0
	for i in d:
		cum[i + 1] = cum[i] + dense[i].distance_to(dense[(i + 1) % d])
	var total := cum[d]
	n = int(round(total / SPACING))
	step = total / n
	length = total
	pts.resize(n)
	dist.resize(n)
	var j := 0
	for k in n:
		var target := k * step
		while j < d - 1 and cum[j + 1] < target:
			j += 1
		var seg := cum[j + 1] - cum[j]
		var f := 0.0
		if seg > 0.0001:
			f = (target - cum[j]) / seg
		pts[k] = dense[j].lerp(dense[(j + 1) % d], clampf(f, 0.0, 1.0))
		dist[k] = target

	tangents.resize(n)
	normals.resize(n)
	for k in n:
		var t := (pts[(k + 1) % n] - pts[(k - 1 + n) % n]).normalized()
		tangents[k] = t
		normals[k] = Vector2(t.y, -t.x)

	var raw := PackedFloat32Array()
	raw.resize(n)
	for k in n:
		raw[k] = tangents[k].angle_to(tangents[(k + 1) % n]) / step
	curv.resize(n)
	for k in n:
		var sum := 0.0
		for o in range(-3, 4):
			sum += raw[(k + o + n) % n]
		curv[k] = sum / 7.0

	bounds_min = pts[0]
	bounds_max = pts[0]
	for p in pts:
		bounds_min = Vector2(minf(bounds_min.x, p.x), minf(bounds_min.y, p.y))
		bounds_max = Vector2(maxf(bounds_max.x, p.x), maxf(bounds_max.y, p.y))


func nearest(p: Vector2, hint: int = -1) -> int:
	var best := -1
	var bd := 1e20
	if hint >= 0:
		for o in range(-8, 13):
			var i := (hint + o + n) % n
			var dd := p.distance_squared_to(pts[i])
			if dd < bd:
				bd = dd
				best = i
		if bd < 900.0:
			return best
	best = 0
	bd = 1e20
	for i in n:
		var dd := p.distance_squared_to(pts[i])
		if dd < bd:
			bd = dd
			best = i
	return best


func pos_at(s: float) -> Vector2:
	var sf := fposmod(s, length) / step
	var i := int(floor(sf)) % n
	return pts[i].lerp(pts[(i + 1) % n], sf - floor(sf))


func dir_at(s: float) -> Vector2:
	var sf := fposmod(s, length) / step
	var i := int(floor(sf)) % n
	return tangents[i].lerp(tangents[(i + 1) % n], sf - floor(sf)).normalized()


func normal_at(s: float) -> Vector2:
	var t := dir_at(s)
	return Vector2(t.y, -t.x)


# ---------------------------------------------------------------- tekstuurit

func _road_texture() -> ImageTexture:
	var w := 256
	var h := 512
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	if surface == "gravel":
		var base := Color(0.5, 0.41, 0.3)
		var verge := Color(0.2, 0.24, 0.12)
		for y in h:
			for x in w:
				var fx := float(x) / w
				var col := base * (0.88 + rng.randf() * 0.24)
				if absf(fx - 0.3) < 0.07 or absf(fx - 0.7) < 0.07:
					col = col * 0.78
				if absf(fx - 0.5) < 0.05:
					col = col * 1.08
				if rng.randf() < 0.02:
					col = col * (0.7 if rng.randf() < 0.5 else 1.3)
				var e := minf(fx, 1.0 - fx)
				if e < 0.07:
					col = verge.lerp(col, e / 0.07)
				col.a = 1.0
				img.set_pixel(x, y, col)
	elif surface == "snow":
		var base := Color(0.8, 0.84, 0.91)
		var edge := Color(0.96, 0.97, 1.0)
		for y in h:
			for x in w:
				var fx := float(x) / w
				var col := base * (0.96 + rng.randf() * 0.06)
				var rut := minf(absf(fx - 0.3), absf(fx - 0.7))
				if rut < 0.07:
					col = col * (0.72 + rut * 2.0)
				if rng.randf() < 0.01:
					col = col * 0.85
				var e := minf(fx, 1.0 - fx)
				if e < 0.06:
					col = edge.lerp(col, e / 0.06)
				col.a = 1.0
				img.set_pixel(x, y, col)
	else:
		for y in h:
			for x in w:
				var g := 0.16 + rng.randf() * 0.07
				var fx := float(x) / w
				if absf(fx - 0.3) < 0.07 or absf(fx - 0.7) < 0.07:
					g -= 0.035
				if rng.randf() < 0.012:
					g += 0.18
				img.set_pixel(x, y, Color(g, g, g * 1.05))
		var white := Color(0.92, 0.92, 0.9)
		for y in h:
			for x in range(8, 15):
				var c := white if rng.randf() > 0.08 else Color(0.7, 0.7, 0.68)
				img.set_pixel(x, y, c)
				img.set_pixel(w - 1 - x, y, c)
			if (y % 256) < 96:
				for x in range(w / 2 - 2, w / 2 + 2):
					img.set_pixel(x, y, white)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _ground_texture() -> ImageTexture:
	var s := 128
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for y in s:
		for x in s:
			var v := rng.randf()
			var lf := sin(x * 0.19) * sin(y * 0.23) * 0.5 + 0.5
			var c: Color
			if surface == "gravel":
				c = Color(0.1 + v * 0.06 + lf * 0.07, 0.18 + v * 0.1 + lf * 0.05, 0.06 + v * 0.04)
			elif surface == "snow":
				var w := 0.9 + v * 0.06 - lf * 0.03
				c = Color(w, w + 0.02, minf(1.0, w + 0.06))
			else:
				c = Color(0.12 + v * 0.07 + lf * 0.05, 0.28 + v * 0.12 + lf * 0.08, 0.07 + v * 0.05)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _crowd_texture() -> ImageTexture:
	var w := 64
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for y in h:
		for x in w:
			var c := Color.from_hsv(rng.randf(), 0.55 + rng.randf() * 0.3, 0.45 + rng.randf() * 0.5)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _checker_texture() -> ImageTexture:
	var img := Image.create(16, 2, false, Image.FORMAT_RGB8)
	for y in 2:
		for x in 16:
			var c := Color.WHITE if (x + y) % 2 == 0 else Color(0.05, 0.05, 0.05)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- mallit

func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, col: Color, v0: float, v1: float) -> void:
	# a = vasen alku, b = vasen loppu, c = oikea alku, d = oikea loppu
	var verts := [a, b, c, c, b, d]
	var uvs := [Vector2(0, v0), Vector2(0, v1), Vector2(1, v0), Vector2(1, v0), Vector2(0, v1), Vector2(1, v1)]
	if (b - a).cross(c - a).dot(nrm) > 0.0:
		verts = [a, c, b, c, d, b]
		uvs = [Vector2(0, v0), Vector2(1, v0), Vector2(0, v1), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)]
	for i in 6:
		st.set_color(col)
		st.set_normal(nrm)
		st.set_uv(uvs[i])
		st.add_vertex(verts[i])


func _p3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


func _mesh_instance(root: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	root.add_child(mi)
	return mi


func build_visuals(root: Node3D) -> void:
	_build_ground(root)
	_build_road(root)
	_build_curbs_and_walls(root)
	_build_startline(root)
	if surface == "asphalt":
		_build_stands(root)
	if surface == "snow":
		_build_poles(root)
	_build_trees(root)
	_build_mountains(root)


func _build_ground(root: Node3D) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(5000, 5000)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _ground_texture()
	mat.uv1_scale = Vector3(700, 700, 1)
	mat.roughness = 1.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var mi := _mesh_instance(root, pm, mat)
	mi.position = Vector3(0, -0.05, 0)


func _build_road(root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in n:
		var k2 := (k + 1) % n
		var v0 := dist[k] / 16.0
		var v1 := (dist[k] + step) / 16.0
		var a := _p3(pts[k] + normals[k] * road_half, 0.0)
		var b := _p3(pts[k2] + normals[k2] * road_half, 0.0)
		var c := _p3(pts[k] - normals[k] * road_half, 0.0)
		var d := _p3(pts[k2] - normals[k2] * road_half, 0.0)
		_add_quad(st, a, b, c, d, Vector3.UP, Color.WHITE, v0, v1)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _road_texture()
	mat.roughness = 0.62 if surface == "asphalt" else 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mesh_instance(root, st.commit(), mat)


func _build_curbs_and_walls(root: Node3D) -> void:
	var curb := SurfaceTool.new()
	curb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col_a := Color(0.85, 0.1, 0.1)
	var col_b := Color(0.95, 0.95, 0.95)
	var top_col := Color(0.55, 0.55, 0.58)
	var out_col := Color(0.45, 0.45, 0.48)
	if surface == "gravel":
		col_a = Color(0.36, 0.28, 0.2)
		col_b = Color(0.31, 0.25, 0.17)
		top_col = Color(0.18, 0.26, 0.12)
		out_col = Color(0.16, 0.22, 0.1)
	elif surface == "snow":
		col_a = Color(0.93, 0.95, 1.0)
		col_b = Color(0.86, 0.89, 0.96)
		top_col = Color(0.98, 0.99, 1.0)
		out_col = Color(0.9, 0.93, 0.98)
	for k in n:
		var k2 := (k + 1) % n
		var ccol := Color(0.85, 0.1, 0.1) if (k / 2) % 2 == 0 else Color(0.95, 0.95, 0.95)
		var wcol := col_a if (k / 4) % 2 == 0 else col_b
		for side in [1.0, -1.0]:
			var sd: float = side
			if curb_w > 0.0:
				var a := _p3(pts[k] + normals[k] * sd * road_half, 0.03)
				var b := _p3(pts[k2] + normals[k2] * sd * road_half, 0.03)
				var c := _p3(pts[k] + normals[k] * sd * (road_half + curb_w), 0.03)
				var d := _p3(pts[k2] + normals[k2] * sd * (road_half + curb_w), 0.03)
				_add_quad(curb, a, b, c, d, Vector3.UP, ccol, 0.0, 1.0)
			# vallin (tai penkan) sisäpinta
			var w0 := pts[k] + normals[k] * sd * wall_offset
			var w1 := pts[k2] + normals[k2] * sd * wall_offset
			var t0 := pts[k] + normals[k] * sd * (wall_offset + wall_slope)
			var t1 := pts[k2] + normals[k2] * sd * (wall_offset + wall_slope)
			var inward := Vector3(-normals[k].x * sd, 0.0, -normals[k].y * sd)
			var face_n := inward
			if wall_slope > 0.0:
				face_n = Vector3(inward.x * wall_h, wall_slope, inward.z * wall_h).normalized()
			_add_quad(wall, _p3(w0, 0.0), _p3(w1, 0.0), _p3(t0, wall_h), _p3(t1, wall_h), face_n, wcol, 0.0, 1.0)
			# yläpinta ja ulkopinta
			var o0 := pts[k] + normals[k] * sd * (wall_offset + wall_slope + 0.8)
			var o1 := pts[k2] + normals[k2] * sd * (wall_offset + wall_slope + 0.8)
			_add_quad(wall, _p3(t0, wall_h), _p3(t1, wall_h), _p3(o0, wall_h), _p3(o1, wall_h), Vector3.UP, top_col, 0.0, 1.0)
			_add_quad(wall, _p3(o0, wall_h), _p3(o1, wall_h), _p3(o0, 0.0), _p3(o1, 0.0), -inward, out_col, 0.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.75 if surface == "asphalt" else 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if curb_w > 0.0:
		_mesh_instance(root, curb.commit(), mat)
	_mesh_instance(root, wall.commit(), mat)


func _build_startline(root: Node3D) -> void:
	var yaw := yaw_of(tangents[0])
	var pm := PlaneMesh.new()
	pm.size = Vector2(road_half * 2.0, 2.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _checker_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.8
	var line := _mesh_instance(root, pm, mat)
	line.position = _p3(pts[0], 0.04)
	line.rotation.y = yaw

	# Lähtöportaali
	var gantry := Node3D.new()
	gantry.position = _p3(pts[0], 0.0)
	gantry.rotation.y = yaw
	root.add_child(gantry)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.15)
	dark.roughness = 0.6
	var half := road_half + 2.5
	for sx in [-half, half]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 8.0, 0.7)
		post.mesh = bm
		post.material_override = dark
		post.position = Vector3(sx, 4.0, 0)
		gantry.add_child(post)
	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(half * 2.0 + 1.0, 2.0, 0.9)
	beam.mesh = bb
	beam.material_override = dark
	beam.position = Vector3(0, 8.0, 0)
	gantry.add_child(beam)
	var label := Label3D.new()
	label.text = "START / MAALI"
	label.font_size = 64
	label.pixel_size = 0.022 if half > 9.0 else 0.015
	label.modulate = Color(1.0, 0.85, 0.2)
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0)
	label.double_sided = false
	label.position = Vector3(0, 8.0, 0.5)
	gantry.add_child(label)


func _build_poles(root: Node3D) -> void:
	# Oranssit reunatikut lumiradalle, jotta tien reuna erottuu
	var count := 0
	for k in range(0, n, 6):
		count += 2
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.07
	pm.height = 1.8
	pm.radial_segments = 5
	pm.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.05)
	mat.roughness = 0.6
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pm
	mm.instance_count = count
	var i := 0
	for k in range(0, n, 6):
		for sd in [1.0, -1.0]:
			var p: Vector2 = pts[k] + normals[k] * sd * (road_half + 0.9)
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x, 0.9, p.y)))
			i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


func _build_stands(root: Node3D) -> void:
	var crowd := StandardMaterial3D.new()
	crowd.albedo_texture = _crowd_texture()
	crowd.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	crowd.roughness = 1.0
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.55, 0.55, 0.58)
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color(0.8, 0.12, 0.12)
	roof.roughness = 0.5
	var s_mid := -5.0
	var yaw := yaw_of(dir_at(s_mid))
	var base := pos_at(s_mid)
	var nrm := normal_at(s_mid)
	for tier in 4:
		var off := wall_offset + 5.0 + tier * 2.4
		var h := 1.6 + tier * 1.5
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.4, h, 80.0)
		mi.mesh = bm
		mi.material_override = crowd if tier > 0 else concrete
		mi.position = _p3(base + nrm * off, h / 2.0)
		mi.rotation.y = yaw
		root.add_child(mi)
	var canopy := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(13.0, 0.5, 80.0)
	canopy.mesh = cb
	canopy.material_override = roof
	canopy.position = _p3(base + nrm * (wall_offset + 12.0), 11.0)
	canopy.rotation.y = yaw
	root.add_child(canopy)
	for sz in [-38.0, 0.0, 38.0]:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.6, 11.0, 0.6)
		post.mesh = pb
		post.material_override = concrete
		var pp := pos_at(s_mid + sz) + normal_at(s_mid + sz) * (wall_offset + 17.5)
		post.position = _p3(pp, 5.5)
		root.add_child(post)


func _build_trees(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var minp := bounds_min - Vector2(260, 260)
	var maxp := bounds_max + Vector2(260, 260)
	var target := 1400
	var near_frac := 0.0
	var clear := wall_offset + 8.0
	if surface == "gravel":
		target = 2600
		near_frac = 0.85
		clear = wall_offset + 2.0
	elif surface == "snow":
		target = 1900
		near_frac = 0.6
		clear = wall_offset + 3.0
	var clear2 := clear * clear
	var spots: Array = []
	var attempts := 0
	var stand_c := pos_at(-5.0) + normal_at(-5.0) * 30.0
	while spots.size() < target and attempts < target * 4:
		attempts += 1
		var p: Vector2
		if rng.randf() < near_frac:
			var kk := rng.randi() % n
			var sgn := 1.0 if rng.randf() < 0.5 else -1.0
			var off := clear + pow(rng.randf(), 2.0) * 70.0
			p = pts[kk] + normals[kk] * sgn * off
		else:
			p = Vector2(rng.randf_range(minp.x, maxp.x), rng.randf_range(minp.y, maxp.y))
		var ok := true
		var k := 0
		while k < n:
			if p.distance_squared_to(pts[k]) < clear2:
				ok = false
				break
			k += 3
		if ok and surface == "asphalt" and p.distance_to(stand_c) < 55.0:
			ok = false
		if ok:
			spots.append(p)
	var count := spots.size()

	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.0
	cone.height = 6.0
	cone.radial_segments = 7
	cone.rings = 1
	var cone_mat := StandardMaterial3D.new()
	cone_mat.vertex_color_use_as_albedo = true
	cone_mat.roughness = 0.9
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.3
	trunk.bottom_radius = 0.4
	trunk.height = 1.8
	trunk.radial_segments = 5
	trunk.rings = 1
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.32, 0.2, 0.1)

	var mm_leaf := MultiMesh.new()
	mm_leaf.transform_format = MultiMesh.TRANSFORM_3D
	mm_leaf.use_colors = true
	mm_leaf.mesh = cone
	mm_leaf.instance_count = count
	var mm_trunk := MultiMesh.new()
	mm_trunk.transform_format = MultiMesh.TRANSFORM_3D
	mm_trunk.mesh = trunk
	mm_trunk.instance_count = count
	for i in count:
		var p: Vector2 = spots[i]
		var sc := rng.randf_range(0.8, 1.7)
		var col: Color
		if surface == "gravel":
			sc = rng.randf_range(1.0, 2.1)
			col = Color(0.05 + rng.randf() * 0.07, 0.2 + rng.randf() * 0.12, 0.07 + rng.randf() * 0.05)
		elif surface == "snow":
			var w := rng.randf()
			col = Color(0.62 + w * 0.2, 0.76 + w * 0.15, 0.7 + w * 0.2)
		else:
			col = Color(0.08 + rng.randf() * 0.08, 0.3 + rng.randf() * 0.2, 0.1 + rng.randf() * 0.06)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc))
		mm_leaf.set_instance_transform(i, Transform3D(basis, Vector3(p.x, (1.2 + 3.0) * sc, p.y)))
		mm_leaf.set_instance_color(i, col)
		mm_trunk.set_instance_transform(i, Transform3D(basis, Vector3(p.x, 0.9 * sc, p.y)))
	var leaf_node := MultiMeshInstance3D.new()
	leaf_node.multimesh = mm_leaf
	leaf_node.material_override = cone_mat
	leaf_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(leaf_node)
	var trunk_node := MultiMeshInstance3D.new()
	trunk_node.multimesh = mm_trunk
	trunk_node.material_override = trunk_mat
	trunk_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(trunk_node)


func _build_mountains(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var center := (bounds_min + bounds_max) * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.42, 0.5)
	if surface == "gravel":
		mat.albedo_color = Color(0.24, 0.33, 0.3)
	elif surface == "snow":
		mat.albedo_color = Color(0.9, 0.93, 0.98)
	mat.roughness = 1.0
	for i in 30:
		var a := TAU * i / 30.0 + rng.randf() * 0.1
		var r := rng.randf_range(1300.0, 1800.0)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = rng.randf_range(250.0, 420.0)
		cm.height = rng.randf_range(160.0, 330.0)
		cm.radial_segments = 8
		cm.rings = 1
		var mi := _mesh_instance(root, cm, mat)
		mi.position = Vector3(center.x + cos(a) * r, cm.height * 0.5 - 5.0, center.y + sin(a) * r)
		mi.rotation.y = rng.randf() * TAU
