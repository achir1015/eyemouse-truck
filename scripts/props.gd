class_name Props
extends RefCounted
## 街景真實物件：路燈、路邊停放的機車、消防栓、公車亭、電線桿＋電線、灌木、大石頭。
## 有寫實模型（TRELLIS／Poly Haven）就用模型，沒有的用曲面程序化造型（金屬材質、平滑圓管）。


static func metal_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.metallic = 0.75
	m.roughness = 0.38
	return m


## 圓管沿 3D 折線（平滑彎曲），段數 seg
static func tube(s: SurfaceTool, pts: Array, r0: float, r1: float, col: Color, seg := 12) -> void:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var ra := lerpf(r0, r1, float(i) / (pts.size() - 1))
		var rb := lerpf(r0, r1, float(i + 1) / (pts.size() - 1))
		var up := (b - a).normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var basis := Basis(side, up, side.cross(up).normalized())
		MeshKit.cyl(s, Transform3D(basis, a), ra, rb, a.distance_to(b), seg, col, i == pts.size() - 2)


## 路燈：彎曲燈臂（toward = 朝路中央的方向）
static func lamp(s_metal: SurfaceTool, s_glow: SurfaceTool, p: Vector2, toward: Vector2) -> void:
	var base := Vector3(p.x, 0, p.y)
	var t3 := Vector3(toward.x, 0, toward.y)
	var pts := [base, base + Vector3(0, 6.5, 0), base + Vector3(0, 7.6, 0) + t3 * 0.25, base + Vector3(0, 8.1, 0) + t3 * 0.9,
		base + Vector3(0, 8.2, 0) + t3 * 1.8]
	tube(s_metal, pts, 0.11, 0.05, Color(0.62, 0.64, 0.66), 12)
	MeshKit.cyl(s_metal, MeshKit.xf_at(base), 0.2, 0.15, 0.6, 12, Color(0.5, 0.52, 0.54))
	var head: Vector3 = pts[4] + t3 * 0.35
	var yaw := atan2(toward.x, toward.y)
	MeshKit.sphere(s_metal, head + Vector3(0, 0.05, 0), 0.32, Color(0.55, 0.57, 0.6), 12, 0.35)
	MeshKit.cyl(s_glow, MeshKit.xf_at(head - Vector3(0, 0.07, 0), yaw), 0.24, 0.24, 0.03, 12, Color(1.0, 0.95, 0.82), false)


## 電線桿（水泥）＋橫擔
static func utility_pole(s: SurfaceTool, p: Vector2, along: Vector2) -> Array:
	var base := Vector3(p.x, 0, p.y)
	MeshKit.cyl(s, MeshKit.xf_at(base), 0.2, 0.13, 10.5, 12, Color(0.72, 0.71, 0.68), true)
	var yaw := atan2(along.x, along.y) + PI * 0.5
	MeshKit.box(s, MeshKit.xf_at(base + Vector3(0, 9.6, 0), yaw), Vector3(0.12, 0.12, 2.2), Color(0.35, 0.33, 0.3))
	var r := Vector3(-along.y, 0, along.x)
	var tips := []
	for k in [-0.95, 0.0, 0.95]:
		var tp: Vector3 = base + Vector3(0, 9.75, 0) + r * float(k)
		MeshKit.cyl(s, MeshKit.xf_at(tp - Vector3(0, 0.1, 0)), 0.05, 0.05, 0.16, 6, Color(0.85, 0.85, 0.82))
		tips.append(tp)
	# 變壓器桶（台灣電線桿常見）
	if hash(p) % 4 == 0:
		MeshKit.cyl(s, MeshKit.xf_at(base + Vector3(0, 7.2, 0) - r * 0.4), 0.32, 0.32, 1.1, 12, Color(0.55, 0.58, 0.55))
	return tips


## 兩點之間下垂的電線
static func wire(s: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var pts := []
	for k in 9:
		var t := k / 8.0
		var q := a.lerp(b, t)
		q.y -= sin(t * PI) * a.distance_to(b) * 0.035
		pts.append(q)
	tube(s, pts, 0.015, 0.015, Color(0.08, 0.08, 0.08), 4)


static func place(w: World) -> void:
	var net := w.net
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var low := str(App.settings.quality) == "low"
	var metal := metal_mat()
	var sm := SurfaceTool.new()
	sm.begin(Mesh.PRIMITIVE_TRIANGLES)
	var scooters := []
	var hydrants := []
	var stops := []
	var benches := []
	var shrubs := []
	var boulders := []
	for e in net.edges.size():
		var d: Dictionary = net.edges[e]
		var a: Vector2 = net.nodes[d.a]
		var dir: Vector2 = d.dir
		var r := Vector2(-dir.y, dir.x)
		var hw := net.half_width(e)
		var near := func(p: Vector2, extra: float) -> bool:
			for n in [d.a, d.b]:
				if p.distance_to(net.nodes[n]) < net.node_r[n] + extra:
					return true
			return false
		if d.walk:
			# 路邊機車（台灣騎樓前一整排）
			var t := rng.randf_range(20, 50)
			while t < d.len - 20:
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var n := rng.randi_range(4, 8)
				for k in n:
					var p: Vector2 = a + dir * (t + k * 0.85) + r * side * (hw + 2.9)
					if near.call(p, 6.0):
						continue
					var yaw := atan2(r.x * side, r.y * side) + rng.randf_range(-0.12, 0.12)
					scooters.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.15, p.y)))
				t += rng.randf_range(45, 90)
			# 消防栓
			var th := rng.randf_range(30, 90)
			while th < d.len - 15:
				var ph: Vector2 = a + dir * th + r * (hw + 0.6) * (1.0 if int(th) % 2 == 0 else -1.0)
				if not near.call(ph, 4.0):
					hydrants.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(ph.x, 0.15, ph.y)))
				th += 140.0
			# 公車亭（主要道路）
			if d.lanes >= 2 and d.len > 100:
				var ps: Vector2 = a + dir * d.len * 0.5 + r * (hw + 2.2)
				stops.append(Transform3D(Basis(Vector3.UP, atan2(-r.x, -r.y)), Vector3(ps.x, 0.15, ps.y)))
				var pb: Vector2 = ps + dir * 4.0
				benches.append(Transform3D(Basis(Vector3.UP, atan2(-r.x, -r.y)), Vector3(pb.x, 0.15, pb.y)))
			# 中央分隔島灌木
			if d.median > 0.8:
				var tm := 6.0
				while tm < d.len - 6:
					var pm: Vector2 = a + dir * tm
					if not near.call(pm, 2.0):
						shrubs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(pm.x, 0.18, pm.y)))
					tm += 5.0
		elif d.kind in ["rural", "mountain"] and not d.tunnel and not low:
			# 鄉間電線桿與電線（靠右側）
			var side2 := 1.0 if not w.map.get("canyon", false) else -1.0
			var prev: Array = []
			var tp := 6.0
			while tp < d.len:
				var pp: Vector2 = a + dir * tp + r * side2 * (hw + 2.4)
				if w.in_water(pp) or w.hit_any(pp, 1.0):
					prev = []
				else:
					var tips := utility_pole(sm, pp, dir)
					if prev.size() == 3:
						for k in 3:
							wire(sm, prev[k], tips[k])
					prev = tips
				tp += 42.0
		if d.kind == "mountain" or (w.map.biome == "coast" and d.kind == "rural"):
			var tb := rng.randf_range(10, 40)
			while tb < d.len:
				var pb2: Vector2 = a + dir * tb - r * (hw + rng.randf_range(4, 16))
				boulders.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.6, 2.2)), Vector3(pb2.x, -0.3, pb2.y)))
				tb += rng.randf_range(25, 60)
	var mi := MeshInstance3D.new()
	mi.mesh = sm.commit()
	mi.material_override = w.mats["solid"]
	w.add_child(mi)
	w._scatter("scooter_parked", scooters, 1.85)
	w._scatter("ph_hydrant", hydrants, 0.0, 0.8)
	w._scatter("bus_stop", stops, 4.5)
	w._scatter("bench", benches, 1.8)
	w._scatter("shrub", shrubs, 0.0, 1.1)
	w._scatter("ph_boulder", boulders, 0.0, 1.6)
	for c in scooters:
		pass
