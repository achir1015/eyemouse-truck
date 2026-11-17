class_name Traffic
extends Node3D
## 路上其他車輛：小客車、計程車、公車、小貨車、機車。依車道行駛、看紅綠燈、保持車距；
## 也負責特殊狀況（事故路段、塞車、救護車）。

const TYPES := {
	"car": {"len": 4.5, "w": 1.8, "r": 1.0, "vmul": 1.0},
	"taxi": {"len": 4.6, "w": 1.8, "r": 1.0, "vmul": 1.05},
	"bus": {"len": 11.0, "w": 2.5, "r": 1.3, "vmul": 0.85},
	"van": {"len": 6.0, "w": 2.1, "r": 1.15, "vmul": 0.9},
	"scooter": {"len": 1.9, "w": 0.7, "r": 0.5, "vmul": 1.1},
	"ambulance": {"len": 6.0, "w": 2.1, "r": 1.15, "vmul": 1.5},
	"wreck": {"len": 4.5, "w": 1.8, "r": 1.0, "vmul": 0.0},
}

var world: World
var net: RoadNet
var cars: Array = []          # Dictionary
var player: Vehicle
var target_count := 30
var meshes := {}
var rng := RandomNumberGenerator.new()
var obstacles: Array = []     # 事故現場的靜態障礙 {c, r}
var jam_edges := {}           # edge -> 速度上限（km/h）
var siren_car = null
var _respawn_t := 0.0


func setup(w: World, p: Vehicle, density: float) -> void:
	world = w
	net = w.net
	player = p
	rng.seed = 2026
	target_count = int(clampf(40.0 * density, 4.0, 60.0))
	if str(App.settings.quality) == "low":
		target_count = int(target_count * 0.6)
	_build_meshes()
	for i in target_count:
		_spawn_random(true)


# ---------------------------------------------------------------- 模型
func _build_meshes() -> void:
	for t in TYPES:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var W := Color(1, 1, 1)
		var D := Color(0.1, 0.12, 0.15)
		var K := Color(0.06, 0.06, 0.06)
		var X := func(x: float, y: float, z: float) -> Transform3D: return Transform3D(Basis.IDENTITY, Vector3(x, y, z))
		var wheel := func(x: float, z: float, r: float, w: float) -> void:
			MeshKit.cyl(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x - w * 0.5, r, z)), r, r, w, 8, K)
		match t:
			"car", "taxi", "wreck":
				MeshKit.box(st, X.call(0, 0.6, 0), Vector3(1.8, 0.62, 4.4), W)
				MeshKit.box(st, X.call(0, 1.15, 0.2), Vector3(1.6, 0.5, 2.3), D)
				MeshKit.box(st, X.call(0, 1.42, 0.25), Vector3(1.5, 0.06, 1.8), W)
				if t == "taxi":
					MeshKit.box(st, X.call(0, 1.55, 0.3), Vector3(0.5, 0.2, 0.25), Color(1, 1, 0.9))
				for z in [-1.4, 1.4]:
					for x in [-0.8, 0.8]:
						wheel.call(x, z, 0.33, 0.22)
			"bus":
				MeshKit.box(st, X.call(0, 1.75, 0), Vector3(2.5, 2.9, 11.0), W)
				MeshKit.box(st, X.call(0, 2.3, 0), Vector3(2.52, 1.0, 10.4), D)
				MeshKit.box(st, X.call(0, 1.9, -5.51), Vector3(2.3, 1.6, 0.04), D)
				for z in [-3.6, 3.4]:
					for x in [-1.1, 1.1]:
						wheel.call(x, z, 0.5, 0.35)
			"van", "ambulance":
				MeshKit.box(st, X.call(0, 1.3, 0.6), Vector3(2.1, 2.1, 4.6), W)
				MeshKit.box(st, X.call(0, 1.0, -2.25), Vector3(2.0, 1.4, 1.5), W)
				MeshKit.box(st, X.call(0, 1.75, -2.4), Vector3(1.9, 0.6, 1.0), D)
				if t == "ambulance":
					MeshKit.box(st, X.call(0, 1.6, 0.6), Vector3(2.12, 0.3, 4.62), Color(0.9, 0.1, 0.1))
				for z in [-2.2, 1.9]:
					for x in [-0.95, 0.95]:
						wheel.call(x, z, 0.38, 0.25)
			"scooter":
				MeshKit.box(st, X.call(0, 0.45, 0), Vector3(0.5, 0.45, 1.6), W)
				MeshKit.box(st, X.call(0, 0.85, -0.55), Vector3(0.45, 0.6, 0.2), W)
				MeshKit.box(st, X.call(0, 1.2, 0.1), Vector3(0.45, 0.65, 0.35), Color(0.25, 0.3, 0.45))   # 騎士
				MeshKit.sphere(st, Vector3(0, 1.68, 0.05), 0.17, Color(0.9, 0.85, 0.2), 6)               # 安全帽
				wheel.call(0, -0.65, 0.25, 0.12)
				wheel.call(0, 0.65, 0.25, 0.12)
		meshes[t] = st.commit()


const MODEL_FOR := {"taxi": ["taxi", "car_silver"], "bus": ["bus"], "van": ["van"], "scooter": ["scooter"], "ambulance": ["ambulance"],
	"car": ["car_white", "car_silver", "car_red", "sedan"], "wreck": ["car_silver", "car_white"]}


func _car_node(t: String, color: Color) -> Node3D:
	var n := Node3D.new()
	var names: Array = (MODEL_FOR.get(t, []) as Array).filter(func(nm): return Models.has(nm))
	var pick: String = names[rng.randi() % names.size()] if names.size() > 0 else ""
	var model: Node3D = Models.make(pick, TYPES[t].len) if pick != "" else null
	if model:
		n.add_child(model)
		if t == "wreck":
			Models.tint(model, Color(0.55, 0.5, 0.48))
		elif t == "taxi":
			Models.tint(model, Color(1.0, 0.85, 0.15))
			var sign := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(0.55, 0.18, 0.28)
			sign.mesh = sb
			var bb := Models.aabb_of(model)
			sign.position = Vector3(0, bb.end.y + 0.08, 0.2)
			var smat := StandardMaterial3D.new()
			smat.albedo_color = Color(1, 1, 0.92)
			smat.emission_enabled = true
			smat.emission = Color(1, 0.95, 0.7)
			smat.emission_energy_multiplier = 0.6
			sign.material_override = smat
			model.add_child(sign)
		elif pick in ["car_white", "car_silver"]:
			Models.tint(model, color.lightened(0.15))
		add_child(n)
		return n
	if t == "scooter" and Models.has("scooter_parked"):
		var sc := Models.make("scooter_parked", 1.85)
		n.add_child(sc)
		n.add_child(_rider(color))
		add_child(n)
		return n
	if t == "bus":
		n.add_child(_bus(color))
		add_child(n)
		return n
	var mi := MeshInstance3D.new()
	mi.mesh = meshes[t]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = color
	m.roughness = 0.45
	m.metallic = 0.2
	mi.material_override = m
	n.add_child(mi)
	if t != "scooter":
		var tail := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(TYPES[t].w * 0.9, 0.12, 0.05)
		tail.mesh = bm
		tail.position = Vector3(0, 0.75 if t != "bus" else 0.9, TYPES[t].len * 0.5 + 0.02)
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.albedo_color = Color(0.45, 0.03, 0.03)
		tail.material_override = tm
		n.add_child(tail)
		n.set_meta("tail", tm)
	if t == "ambulance":
		var lb := OmniLight3D.new()
		lb.position = Vector3(0, 2.6, 0)
		lb.light_color = Color(1, 0.1, 0.1)
		lb.omni_range = 14.0
		lb.light_energy = 2.0
		n.add_child(lb)
		n.set_meta("siren", lb)
	add_child(n)
	return n


func _pbr(col: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## 騎士（坐在機車上，安全帽、外套、長褲）
func _rider(jacket: Color) -> Node3D:
	var r := Node3D.new()
	var cloth := _pbr(jacket.darkened(0.2), 0.85)
	var pants := _pbr(Color(0.15, 0.17, 0.22), 0.9)
	var skin := _pbr(Color(0.86, 0.68, 0.55), 0.7)
	var helmet := _pbr(Color.from_hsv(randf(), 0.5, 0.9), 0.25, 0.1)
	var torso := CapsuleMesh.new()
	torso.radius = 0.19
	torso.height = 0.62
	_part(r, torso, Vector3(0, 1.12, 0.12), cloth, Vector3(-0.25, 0, 0))
	var head := SphereMesh.new()
	head.radius = 0.15
	head.height = 0.3
	_part(r, head, Vector3(0, 1.52, 0.0), skin)
	var hel := SphereMesh.new()
	hel.radius = 0.17
	hel.height = 0.3
	hel.is_hemisphere = true
	_part(r, hel, Vector3(0, 1.55, 0.0), helmet)
	var visor := BoxMesh.new()
	visor.size = Vector3(0.24, 0.07, 0.04)
	_part(r, visor, Vector3(0, 1.58, -0.16), _pbr(Color(0.05, 0.05, 0.06), 0.1, 0.5))
	var arm := CapsuleMesh.new()
	arm.radius = 0.06
	arm.height = 0.55
	for sx in [-1.0, 1.0]:
		_part(r, arm, Vector3(sx * 0.2, 1.15, -0.2), cloth, Vector3(-1.1, 0, sx * 0.15))
		var thigh := CapsuleMesh.new()
		thigh.radius = 0.085
		thigh.height = 0.5
		_part(r, thigh, Vector3(sx * 0.14, 0.78, -0.08), pants, Vector3(-1.4, 0, 0))
		var shin := CapsuleMesh.new()
		shin.radius = 0.07
		shin.height = 0.45
		_part(r, shin, Vector3(sx * 0.16, 0.5, -0.3), pants, Vector3(-0.2, 0, 0))
	return r


## 市區公車（圓弧車頂、整排反光車窗、輪框、LED 路線牌）
func _bus(paint: Color) -> Node3D:
	var b := Node3D.new()
	var L := 11.0
	var body := _pbr(Color(0.93, 0.93, 0.95), 0.35, 0.2)
	var stripe := _pbr(paint, 0.4, 0.2)
	var glass := _pbr(Color(0.06, 0.08, 0.1), 0.05, 0.6)
	glass.metallic_specular = 0.9
	var lower := BoxMesh.new()
	lower.size = Vector3(2.5, 1.25, L)
	_part(b, lower, Vector3(0, 0.95, 0), body)
	var band := BoxMesh.new()
	band.size = Vector3(2.52, 0.3, L - 0.2)
	_part(b, band, Vector3(0, 0.65, 0), stripe)
	var win := BoxMesh.new()
	win.size = Vector3(2.46, 1.0, L - 0.5)
	_part(b, win, Vector3(0, 2.07, 0.1), glass)
	var front := BoxMesh.new()
	front.size = Vector3(2.3, 1.55, 0.06)
	_part(b, front, Vector3(0, 2.0, -L * 0.5 - 0.01), glass, Vector3(0.08, 0, 0))
	# 圓弧車頂
	var roof := CylinderMesh.new()
	roof.top_radius = 1.25
	roof.bottom_radius = 1.25
	roof.height = L
	roof.radial_segments = 24
	var rn := _part(b, roof, Vector3(0, 2.35, 0), body, Vector3(PI * 0.5, 0, 0))
	rn.scale = Vector3(1.0, 1.0, 0.3)
	# 窗柱
	for k in 7:
		var post := BoxMesh.new()
		post.size = Vector3(2.5, 1.0, 0.12)
		_part(b, post, Vector3(0, 2.07, -L * 0.5 + 1.2 + k * 1.45), body)
	# LED 路線牌
	var led := BoxMesh.new()
	led.size = Vector3(1.8, 0.28, 0.05)
	var lm := _pbr(Color(1, 0.55, 0.1), 0.5)
	lm.emission_enabled = true
	lm.emission = Color(1, 0.5, 0.05)
	lm.emission_energy_multiplier = 1.5
	_part(b, led, Vector3(0, 2.62, -L * 0.5 - 0.04), lm)
	# 輪胎與輪框
	var tire := CylinderMesh.new()
	tire.top_radius = 0.5
	tire.bottom_radius = 0.5
	tire.height = 0.32
	tire.radial_segments = 20
	var rim := CylinderMesh.new()
	rim.top_radius = 0.3
	rim.bottom_radius = 0.3
	rim.height = 0.34
	rim.radial_segments = 16
	for z in [-3.3, 3.2]:
		for sx in [-1.08, 1.08]:
			_part(b, tire, Vector3(sx, 0.5, z), _pbr(Color(0.05, 0.05, 0.05), 0.9), Vector3(0, 0, PI * 0.5))
			_part(b, rim, Vector3(sx, 0.5, z), _pbr(Color(0.7, 0.72, 0.74), 0.3, 0.9), Vector3(0, 0, PI * 0.5))
	# 後窗、尾燈、保險桿
	var rear := BoxMesh.new()
	rear.size = Vector3(2.1, 0.9, 0.06)
	_part(b, rear, Vector3(0, 2.05, L * 0.5 + 0.01), glass)
	var bump := BoxMesh.new()
	bump.size = Vector3(2.5, 0.3, 0.12)
	_part(b, bump, Vector3(0, 0.45, L * 0.5 + 0.03), _pbr(Color(0.15, 0.15, 0.16), 0.6))
	var tlm := _pbr(Color(0.8, 0.05, 0.05), 0.3)
	tlm.emission_enabled = true
	tlm.emission = Color(0.6, 0.02, 0.02)
	for sx in [-1.05, 1.05]:
		var tl := BoxMesh.new()
		tl.size = Vector3(0.22, 0.5, 0.05)
		_part(b, tl, Vector3(sx, 1.1, L * 0.5 + 0.03), tlm)
	var adv := BoxMesh.new()
	adv.size = Vector3(0.03, 0.8, L * 0.55)
	_part(b, adv, Vector3(1.27, 1.0, 0.5), _pbr(paint.lightened(0.2), 0.5))
	# 頭燈
	for sx in [-0.85, 0.85]:
		var hl := BoxMesh.new()
		hl.size = Vector3(0.4, 0.16, 0.04)
		var hm := _pbr(Color(1, 1, 0.95), 0.1)
		hm.emission_enabled = true
		hm.emission = Color(1, 1, 0.9)
		hm.emission_energy_multiplier = 0.4
		_part(b, hl, Vector3(sx, 0.85, -L * 0.5 - 0.02), hm)
	return b


# ---------------------------------------------------------------- 生成
func _pick_type(e: int) -> String:
	var d: Dictionary = net.edges[e]
	var r := rng.randf()
	var scooters: bool = world.map.get("scooters", false)
	if d.kind == "city" and scooters and r < 0.35:
		return "scooter"
	if r < 0.45:
		return "taxi" if d.kind == "city" and rng.randf() < 0.4 else "car"
	if r < 0.8:
		return "car"
	if r < 0.9:
		return "van"
	return "bus" if d.kind in ["city", "highway"] else "car"


func _palette(t: String) -> Color:
	match t:
		"taxi": return Color(1.0, 0.82, 0.1)
		"bus": return [Color(0.2, 0.55, 0.85), Color(0.15, 0.6, 0.35), Color(0.9, 0.5, 0.15)][rng.randi() % 3]
		"ambulance": return Color(1, 1, 1)
		"wreck": return Color(0.55, 0.55, 0.58)
		"scooter": return Color.from_hsv(rng.randf(), 0.6, 0.85)
	var pal := [Color(0.92, 0.92, 0.94), Color(0.1, 0.1, 0.12), Color(0.6, 0.62, 0.66), Color(0.7, 0.12, 0.12),
		Color(0.15, 0.3, 0.6), Color(0.85, 0.85, 0.8), Color(0.3, 0.32, 0.3)]
	return pal[rng.randi() % pal.size()]


func _spawn_random(initial: bool) -> void:
	var pp := player.pos2() if player else Vector2.ZERO
	for attempt in 30:
		var e := rng.randi() % net.edges.size()
		var d: Dictionary = net.edges[e]
		if d.kind in ["yard"] and rng.randf() < 0.8:
			continue
		var from: int = d.a if rng.randf() < 0.5 else d.b
		if not net.can_go(e, from):
			from = d.a
		var t := rng.randf_range(0.15, 0.8)
		var lane := rng.randi() % int(d.lanes)
		var p := net.lane_point(e, from, lane, t)
		var dist := p.distance_to(pp)
		if initial:
			if dist < 25.0 or dist > 380.0:
				continue
		elif dist < 140.0 or dist > 330.0:
			continue
		if _occupied(p, 12.0):
			continue
		add_car(_pick_type(e), e, from, lane, t)
		return


func _occupied(p: Vector2, r: float) -> bool:
	for c in cars:
		if c.pos.distance_to(p) < r:
			return true
	return false


func add_car(t: String, e: int, from: int, lane: int, tt: float, speed_kmh := -1.0) -> Dictionary:
	var d: Dictionary = net.edges[e]
	var spec: Dictionary = TYPES[t]
	var c := {
		"type": t, "e": e, "from": from, "to": net.other(e, from), "lane": lane, "t": tt,
		"speed": 0.0, "vmax": float(d.limit) / 3.6 * spec.vmul * rng.randf_range(0.85, 1.05),
		"len": spec.len, "r": spec.r, "node": _car_node(t, _palette(t)), "turn": null, "next_e": -1,
		"pos": net.lane_point(e, from, lane, tt), "dir": Vector2.ZERO, "wait": 0.0, "stopped_at": -1,
		"fixed": t == "wreck", "brake": false,
	}
	if t == "scooter":
		c.vmax = minf(c.vmax, 55.0 / 3.6)
	if speed_kmh >= 0.0:
		c.speed = speed_kmh / 3.6
	else:
		c.speed = c.vmax * 0.7
	c.next_e = _choose_next(c)
	cars.append(c)
	_place(c)
	return c


func _choose_next(c: Dictionary) -> int:
	var to: int = c.to
	var options := []
	for e in net.adj[to]:
		if e == c.e and net.adj[to].size() > 1:
			continue
		if not net.can_go(e, to):
			continue
		if net.edges[e].kind == "yard" and rng.randf() < 0.85 and net.adj[to].size() > 2:
			continue
		options.append(e)
	if options.is_empty():
		return c.e      # 死路：迴轉
	return options[rng.randi() % options.size()]


# ---------------------------------------------------------------- 每格更新
func step(dt: float) -> void:
	_respawn_t += dt
	var pp := player.pos2()
	var pf := player.fwd2()
	for c in cars.duplicate():
		if c.fixed:
			continue
		_drive(c, dt, pp, pf)
		_place(c)
		if c.pos.distance_to(pp) > 420.0 and c != siren_car:
			_remove(c)
	if _respawn_t > 0.5:
		_respawn_t = 0.0
		var n := 0
		for c in cars:
			if not c.fixed and c != siren_car:
				n += 1
		if n < target_count:
			_spawn_random(false)
	if siren_car != null:
		var lb: OmniLight3D = siren_car.node.get_meta("siren")
		lb.light_color = Color(1, 0.1, 0.1) if fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0 else Color(0.2, 0.3, 1.0)


func _remove(c: Dictionary) -> void:
	c.node.queue_free()
	cars.erase(c)
	if siren_car == c:
		siren_car = null


func _drive(c: Dictionary, dt: float, pp: Vector2, pf: Vector2) -> void:
	var e: int = c.e
	var d: Dictionary = net.edges[e]
	var len: float = d.len
	var vdes: float = c.vmax
	if jam_edges.has(e):
		vdes = minf(vdes, float(jam_edges[e]) / 3.6)
	if c.turn != null:
		vdes = minf(vdes, 7.0 if c.type != "scooter" else 8.0)
	# 前車距離（同一路段、同方向、同車道）
	var gap := 1e9
	for o in cars:
		if o == c:
			continue
		var rel: Vector2 = o.pos - c.pos
		var dist := rel.length()
		if dist > 45.0 or dist < 0.01:
			continue
		var cd: Vector2 = c.dir if c.dir != Vector2.ZERO else Vector2(0, -1)
		var ahead := rel.dot(cd)
		var lat := absf(rel.x * cd.y - rel.y * cd.x)
		if ahead > 0.0 and lat < (1.4 if c.type != "scooter" else 0.9) + (0.6 if o.type != "scooter" else 0.0):
			gap = minf(gap, ahead - (c.len + o.len) * 0.5)
	# 玩家
	var relp: Vector2 = pp - c.pos
	var cdp: Vector2 = c.dir if c.dir != Vector2.ZERO else Vector2(0, -1)
	var aheadp := relp.dot(cdp)
	var latp := absf(relp.x * cdp.y - relp.y * cdp.x)
	if aheadp > 0.0 and aheadp < 45.0 and latp < 2.4:
		gap = minf(gap, aheadp - c.len * 0.5 - (6.0 if player.kind == "truck" else 2.5))
	# 拖車
	if player.has_trailer:
		var ta := player.trailer_axle_2d()
		var relt: Vector2 = ta - c.pos
		var at: float = relt.dot(cdp)
		if at > 0.0 and at < 30.0 and absf(relt.x * cdp.y - relt.y * cdp.x) < 2.6:
			gap = minf(gap, at - c.len * 0.5 - 3.0)
	for ob in obstacles:
		var relo: Vector2 = ob.c - c.pos
		var ao := relo.dot(cdp)
		if ao > 0.0 and ao < 40.0 and absf(relo.x * cdp.y - relo.y * cdp.x) < ob.r + 1.2:
			gap = minf(gap, ao - ob.r - c.len * 0.5)
	if gap < 1e8:
		vdes = minf(vdes, maxf(0.0, (gap - 2.5) / 1.6))
	# 紅綠燈／停止線
	var to: int = c.to
	if c.turn == null:
		var t_in := net.t_in(e, to)
		var stop_t := t_in - 4.5 / len
		var dist_stop: float = (stop_t - c.t) * len
		var st := world.light_state(to, e)
		if st != "" and dist_stop > -0.5 and dist_stop < 50.0:
			if st == "R" or (st == "Y" and dist_stop > c.speed * 1.2):
				vdes = minf(vdes, maxf(0.0, dist_stop - 0.5) / 1.8)
		if c.type == "ambulance":
			vdes = c.vmax
	c.brake = vdes < c.speed - 0.5
	var acc := 2.5 if c.type != "scooter" else 3.5
	if c.type == "bus":
		acc = 1.2
	if c.speed < vdes:
		c.speed = minf(vdes, c.speed + acc * dt)
	else:
		c.speed = maxf(vdes, c.speed - 7.0 * dt)
	if c.node.has_meta("tail"):
		(c.node.get_meta("tail") as StandardMaterial3D).albedo_color = Color(1, 0.1, 0.05) if c.brake or c.speed < 0.3 else Color(0.45, 0.03, 0.03)
	# 前進
	var ds: float = c.speed * dt
	if c.turn != null:
		var tr: Dictionary = c.turn
		tr.s += ds
		var u: float = clampf(tr.s / tr.len, 0.0, 1.0)
		var p0: Vector2 = tr.p0
		var p1: Vector2 = tr.c
		var p2: Vector2 = tr.p1
		var np := p0.lerp(p1, u).lerp(p1.lerp(p2, u), u)
		var nd := (p1 - p0).lerp(p2 - p1, u).normalized()
		c.pos = np
		if nd != Vector2.ZERO:
			c.dir = nd
		if u >= 1.0:
			c.turn = null
			c.e = tr.e
			c.from = tr.from
			c.to = net.other(tr.e, tr.from)
			c.lane = mini(c.lane, int(net.edges[tr.e].lanes) - 1)
			c.t = net.t_out(tr.e, tr.from)
			c.vmax = float(net.edges[tr.e].limit) / 3.6 * TYPES[c.type].vmul * rng.randf_range(0.85, 1.05)
			if c.type == "scooter":
				c.vmax = minf(c.vmax, 55.0 / 3.6)
			c.next_e = _choose_next(c)
		return
	c.t += ds / maxf(len, 0.1)
	var tin := net.t_in(e, to)
	if c.t >= tin:
		# 進入路口：建立轉彎曲線
		var ne: int = c.next_e
		var lane_n := mini(c.lane, int(net.edges[ne].lanes) - 1)
		var p0 := net.lane_point(e, c.from, c.lane, tin)
		var p1 := net.lane_point(ne, to, lane_n, net.t_out(ne, to))
		if ne == e:
			p1 = net.lane_point(e, to, 0, net.t_out(e, to))
		var din := (net.nodes[to] - net.nodes[c.from]).normalized()
		var dout := (net.nodes[net.other(ne, to)] - net.nodes[to]).normalized()
		var ctrl = Geometry2D.line_intersects_line(p0, din, p1, -dout)
		if ctrl == null or (ctrl as Vector2).distance_to(net.nodes[to]) > net.node_r[to] * 2.5 + 5.0:
			ctrl = (p0 + p1) * 0.5 + din * p0.distance_to(p1) * 0.3
		var L := p0.distance_to(ctrl) + (ctrl as Vector2).distance_to(p1)
		c.turn = {"p0": p0, "c": ctrl, "p1": p1, "len": maxf(L, 0.5), "s": 0.0, "e": ne, "from": to}
		return
	c.pos = net.lane_point(e, c.from, c.lane, c.t)
	if c.type == "scooter":
		var r := Vector2(-((net.nodes[to] - net.nodes[c.from]).normalized()).y, ((net.nodes[to] - net.nodes[c.from]).normalized()).x)
		c.pos += r * 1.1
	c.dir = (net.nodes[to] - net.nodes[c.from]).normalized()


func _place(c: Dictionary) -> void:
	var n: Node3D = c.node
	n.position = Vector3(c.pos.x, 0, c.pos.y)
	var dir: Vector2 = c.dir
	if dir == Vector2.ZERO:
		var d: Dictionary = net.edges[c.e]
		dir = (net.nodes[c.to] - net.nodes[c.from]).normalized() if d.len > 0 else Vector2(0, -1)
		c.dir = dir
	n.rotation.y = atan2(-dir.x, -dir.y)


## 玩家碰撞：圓 (p, r) 與所有車輛（車身用 2 個圓）
func push(p: Vector2, r: float) -> Vector2:
	var total := Vector2.ZERO
	for c in cars:
		if c.pos.distance_squared_to(p) > 400.0:
			continue
		var pts := [c.pos]
		if c.len > 3.0:
			var half: float = c.len * 0.3
			pts = [c.pos + c.dir * half, c.pos - c.dir * half]
			if c.len > 8.0:
				pts.append(c.pos)
		for q in pts:
			var d: Vector2 = p - q
			var dl := d.length()
			var rr: float = r + c.r
			if dl < rr and dl > 0.001:
				total += d / dl * (rr - dl)
	for ob in obstacles:
		var d2: Vector2 = p - ob.c
		var dl2 := d2.length()
		if dl2 < r + ob.r and dl2 > 0.001:
			total += d2 / dl2 * (r + ob.r - dl2)
	return total


# ---------------------------------------------------------------- 特殊狀況
## 事故現場：在某路段某車道放兩台事故車＋三角錐
func make_accident(e: int, from: int, t: float, lane := 0) -> void:
	var d: Dictionary = net.edges[e]
	lane = clampi(lane, 0, int(d.lanes) - 1)
	var p := net.lane_point(e, from, lane, t)
	var dir := (net.nodes[net.other(e, from)] - net.nodes[from]).normalized()
	var w1 := add_car("wreck", e, from, lane, t)
	w1.node.rotation.y += 0.5
	var w2 := add_car("wreck", e, from, lane, t + 6.0 / d.len)
	w2.node.rotation.y -= 0.7
	w2.node.get_child(0).material_override.albedo_color = Color(0.7, 0.2, 0.15)
	obstacles.append({"c": p, "r": 2.2})
	obstacles.append({"c": w2.pos, "r": 2.2})
	# 三角錐
	var cone := CylinderMesh.new()
	cone.top_radius = 0.03
	cone.bottom_radius = 0.22
	cone.height = 0.7
	cone.radial_segments = 8
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(1, 0.4, 0.05)
	cm.emission_enabled = true
	cm.emission = Color(0.6, 0.2, 0.0)
	cone.material = cm
	for k in 5:
		var cp := p - dir * (12.0 - k * 2.5) + Vector2(-dir.y, dir.x) * (k * 0.35 - 0.6)
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.position = Vector3(cp.x, 0.35, cp.y)
		add_child(mi)
		obstacles.append({"c": cp, "r": 0.25})
	# 警車閃燈
	var pl := OmniLight3D.new()
	pl.position = Vector3(p.x, 2.5, p.y)
	pl.light_color = Color(0.2, 0.3, 1)
	pl.omni_range = 18.0
	pl.light_energy = 2.0
	add_child(pl)
	pl.set_meta("blink", true)


## 塞車：在路線上的幾個路段密集放車、限速
func make_jam(edge_list: Array, kmh := 12.0) -> void:
	for e in edge_list:
		jam_edges[e] = kmh
		var d: Dictionary = net.edges[e]
		for from in [d.a, d.b]:
			var t := 0.15
			while t < 0.85:
				for lane in int(d.lanes):
					var p := net.lane_point(e, from, lane, t)
					if p.distance_to(player.pos2()) > 25.0 and not _occupied(p, 7.0):
						add_car("car" if rng.randf() < 0.75 else "van", e, from, lane, t, kmh * 0.5)
				t += 9.0 / maxf(d.len, 9.0)


## 救護車：從玩家後方開來（要靠右讓道）
func make_ambulance() -> void:
	var q := net.query(player.pos2())
	if q.edge < 0:
		return
	var d: Dictionary = net.edges[q.edge]
	var from: int = d.a if d.dir.dot(player.fwd2()) >= 0.0 else d.b
	var t: float = clampf(q.t if from == d.a else 1.0 - q.t, 0.0, 1.0) - 60.0 / d.len
	if t < 0.05:
		t = 0.05
	siren_car = add_car("ambulance", q.edge, from, 0, t, 60.0)
	siren_car.vmax = 75.0 / 3.6


func nearest_ahead(p: Vector2, f: Vector2, max_d := 60.0) -> float:
	var best := 1e9
	for c in cars:
		var rel: Vector2 = c.pos - p
		var a := rel.dot(f)
		if a > 0.0 and a < max_d and absf(rel.x * f.y - rel.y * f.x) < 2.0:
			best = minf(best, a)
	for ob in obstacles:
		var rel2: Vector2 = ob.c - p
		var a2 := rel2.dot(f)
		if a2 > 0.0 and a2 < max_d and absf(rel2.x * f.y - rel2.y * f.x) < 1.8 + ob.r:
			best = minf(best, a2)
	return best
