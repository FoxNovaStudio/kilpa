extends RefCounted
## Rata: keskilinja, mittaukset ja 3D-mallit (tie, reunakivet, vallit, puut, katsomo)

const ROAD_HALF := 8.0      # tien puolileveys (metriä)
const CURB_W := 1.6         # reunakiven leveys
const WALL_OFFSET := 14.0   # reunavallin etäisyys keskilinjasta
const WALL_H := 1.2
const SPACING := 3.0        # mittauspisteiden väli (metriä)

# Radan ohjauspisteet (x, z). Rata kulkee vastapäivään, lähtöviiva on ensimmäisessä pisteessä.
const CONTROL = [
	Vector2(0, 0), Vector2(150, 0), Vector2(290, -10), Vector2(380, -80),
	Vector2(390, -190), Vector2(330, -270), Vector2(230, -300), Vector2(150, -250),
	Vector2(110, -170), Vector2(30, -130), Vector2(-60, -170), Vector2(-110, -250),
	Vector2(-200, -300), Vector2(-310, -280), Vector2(-375, -205), Vector2(-380, -115),
	Vector2(-320, -45), Vector2(-220, -20), Vector2(-100, 0),
]

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


func build() -> void:
	var dense := PackedVector2Array()
	var c: int = CONTROL.size()
	for i in c:
		var p0: Vector2 = CONTROL[(i - 1 + c) % c]
		var p1: Vector2 = CONTROL[i]
		var p2: Vector2 = CONTROL[(i + 1) % c]
		var p3: Vector2 = CONTROL[(i + 2) % c]
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
	var w := 128
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in h:
		for x in w:
			var g := 0.19 + rng.randf() * 0.06
			img.set_pixel(x, y, Color(g, g, g * 1.04))
	var white := Color(0.92, 0.92, 0.9)
	for y in h:
		for x in range(4, 8):
			img.set_pixel(x, y, white)
			img.set_pixel(w - 1 - x, y, white)
		if (y % 128) < 48:
			for x in range(w / 2 - 1, w / 2 + 1):
				img.set_pixel(x, y, white)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _grass_texture() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for y in s:
		for x in s:
			var v := rng.randf()
			var c := Color(0.16 + v * 0.06, 0.36 + v * 0.1, 0.12 + v * 0.05)
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
	_build_stands(root)
	_build_trees(root)
	_build_mountains(root)


func _build_ground(root: Node3D) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(5000, 5000)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _grass_texture()
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
		var a := _p3(pts[k] + normals[k] * ROAD_HALF, 0.0)
		var b := _p3(pts[k2] + normals[k2] * ROAD_HALF, 0.0)
		var c := _p3(pts[k] - normals[k] * ROAD_HALF, 0.0)
		var d := _p3(pts[k2] - normals[k2] * ROAD_HALF, 0.0)
		_add_quad(st, a, b, c, d, Vector3.UP, Color.WHITE, v0, v1)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _road_texture()
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mesh_instance(root, st.commit(), mat)


func _build_curbs_and_walls(root: Node3D) -> void:
	var curb := SurfaceTool.new()
	curb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var red := Color(0.85, 0.1, 0.1)
	var white := Color(0.95, 0.95, 0.95)
	for k in n:
		var k2 := (k + 1) % n
		var col := red if (k / 2) % 2 == 0 else white
		var wcol := red if (k / 4) % 2 == 0 else white
		for side in [1.0, -1.0]:
			var sd: float = side
			# reunakivi
			var a := _p3(pts[k] + normals[k] * sd * ROAD_HALF, 0.03)
			var b := _p3(pts[k2] + normals[k2] * sd * ROAD_HALF, 0.03)
			var c := _p3(pts[k] + normals[k] * sd * (ROAD_HALF + CURB_W), 0.03)
			var d := _p3(pts[k2] + normals[k2] * sd * (ROAD_HALF + CURB_W), 0.03)
			_add_quad(curb, a, b, c, d, Vector3.UP, col, 0.0, 1.0)
			# vallin pysty seinä
			var w0 := pts[k] + normals[k] * sd * WALL_OFFSET
			var w1 := pts[k2] + normals[k2] * sd * WALL_OFFSET
			var inward := Vector3(-normals[k].x * sd, 0.0, -normals[k].y * sd)
			_add_quad(wall, _p3(w0, 0.0), _p3(w1, 0.0), _p3(w0, WALL_H), _p3(w1, WALL_H), inward, wcol, 0.0, 1.0)
			# vallin yläpinta
			var o0 := pts[k] + normals[k] * sd * (WALL_OFFSET + 0.7)
			var o1 := pts[k2] + normals[k2] * sd * (WALL_OFFSET + 0.7)
			_add_quad(wall, _p3(w0, WALL_H), _p3(w1, WALL_H), _p3(o0, WALL_H), _p3(o1, WALL_H), Vector3.UP, Color(0.55, 0.55, 0.58), 0.0, 1.0)
			_add_quad(wall, _p3(o0, WALL_H), _p3(o1, WALL_H), _p3(o0, 0.0), _p3(o1, 0.0), -inward, Color(0.45, 0.45, 0.48), 0.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.75
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_instance(root, curb.commit(), mat)
	_mesh_instance(root, wall.commit(), mat)


func _build_startline(root: Node3D) -> void:
	var yaw := yaw_of(tangents[0])
	var pm := PlaneMesh.new()
	pm.size = Vector2(ROAD_HALF * 2.0, 2.4)
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
	for sx in [-11.0, 11.0]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 8.0, 0.7)
		post.mesh = bm
		post.material_override = dark
		post.position = Vector3(sx, 4.0, 0)
		gantry.add_child(post)
	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(23.0, 2.0, 0.9)
	beam.mesh = bb
	beam.material_override = dark
	beam.position = Vector3(0, 8.0, 0)
	gantry.add_child(beam)
	var label := Label3D.new()
	label.text = "START / MAALI"
	label.font_size = 64
	label.pixel_size = 0.022
	label.modulate = Color(1.0, 0.85, 0.2)
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0)
	label.double_sided = false
	label.position = Vector3(0, 8.0, 0.5)
	gantry.add_child(label)


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
		var off := WALL_OFFSET + 5.0 + tier * 2.4
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
	canopy.position = _p3(base + nrm * (WALL_OFFSET + 12.0), 11.0)
	canopy.rotation.y = yaw
	root.add_child(canopy)
	for sz in [-38.0, 0.0, 38.0]:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.6, 11.0, 0.6)
		post.mesh = pb
		post.material_override = concrete
		var pp := pos_at(s_mid + sz) + normal_at(s_mid + sz) * (WALL_OFFSET + 17.5)
		post.position = _p3(pp, 5.5)
		root.add_child(post)


func _build_trees(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var minp := bounds_min - Vector2(260, 260)
	var maxp := bounds_max + Vector2(260, 260)
	var clear := WALL_OFFSET + 8.0
	var clear2 := clear * clear
	var spots: Array = []
	for t in 3000:
		var p := Vector2(rng.randf_range(minp.x, maxp.x), rng.randf_range(minp.y, maxp.y))
		var ok := true
		var k := 0
		while k < n:
			if p.distance_squared_to(pts[k]) < clear2:
				ok = false
				break
			k += 2
		# katsomon alue vapaaksi
		if ok and p.distance_to(pos_at(-5.0) + normal_at(-5.0) * 30.0) < 55.0:
			ok = false
		if ok:
			spots.append(p)
		if spots.size() >= 1400:
			break
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
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc))
		mm_leaf.set_instance_transform(i, Transform3D(basis, Vector3(p.x, (1.2 + 3.0) * sc, p.y)))
		mm_leaf.set_instance_color(i, Color(0.08 + rng.randf() * 0.08, 0.3 + rng.randf() * 0.2, 0.1 + rng.randf() * 0.06))
		mm_trunk.set_instance_transform(i, Transform3D(basis, Vector3(p.x, 0.9 * sc, p.y)))
	var leaf_node := MultiMeshInstance3D.new()
	leaf_node.multimesh = mm_leaf
	leaf_node.material_override = cone_mat
	root.add_child(leaf_node)
	var trunk_node := MultiMeshInstance3D.new()
	trunk_node.multimesh = mm_trunk
	trunk_node.material_override = trunk_mat
	root.add_child(trunk_node)


func _build_mountains(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var center := (bounds_min + bounds_max) * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.42, 0.5)
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
