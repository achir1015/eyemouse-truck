class_name Cabin
extends Node3D
## 駕駛室內裝（左駕）：儀表板、方向盤、儀表（SubViewport）、導航平板（SubViewport）、左右後照鏡（即時畫面）。

var veh: Vehicle
var wheel: Node3D
var cluster_vp: SubViewport
var tablet_vp: SubViewport
var cluster: Control
var tablet: Control
var mirror_cams: Array = []
var mirror_vps: Array = []
var wiper_l: Node3D
var wiper_r: Node3D
var _wiper_t := 0.0
var rain_glass: MeshInstance3D
var tablet_quad: MeshInstance3D
var cluster_quad: MeshInstance3D
var mirror_quads: Array = []
var _frame := 0
## 介面熱點（供教學指出位置）：名稱 -> 本地座標
var spots := {}


func setup(v: Vehicle, dash_script: Script) -> void:
	veh = v
	var T := v.kind == "truck"
	var eye: Vector3 = v.spec.eye
	# 尺寸參數
	var ws_z := -5.2 if T else -2.32          # 擋風玻璃底部 z
	var dash_y := 2.1 if T else 0.95          # 儀表板上緣
	var half_w := 1.22 if T else 0.78
	var roof_y := 3.3 if T else 1.42
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := Color(0.13, 0.13, 0.15)
	var trim := Color(0.22, 0.22, 0.25)
	var X := func(x: float, y: float, z: float, rx := 0.0) -> Transform3D:
		return Transform3D(Basis(Vector3.RIGHT, rx), Vector3(x, y, z))
	var soft := SurfaceTool.new()      # 曲面（平滑法線）：儀表板、A 柱、車門、車頂
	soft.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 儀表板：側面輪廓（z, y）沿 x 方向擠出，前低後高、圓角
	var dz := ws_z
	var dk := 1.0 if T else 0.62
	var dash_prof := [Vector2(dz - 0.06, dash_y - 0.04), Vector2(dz + 0.2 * dk, dash_y + 0.01), Vector2(dz + 0.45 * dk, dash_y - 0.01),
		Vector2(dz + 0.6 * dk, dash_y - 0.07), Vector2(dz + 0.68 * dk, dash_y - 0.18), Vector2(dz + 0.7 * dk, dash_y - 0.34),
		Vector2(dz + 0.66 * dk, dash_y - 0.55), Vector2(dz + 0.62 * dk, dash_y - 0.95)]
	_sweep(soft, dash_prof, -half_w, half_w, dark, 18)
	# 儀表罩（駕駛前方隆起）
	var hk := 1.0 if T else 0.55
	var hood_prof := [Vector2(dz + 0.18 * hk, dash_y + 0.0), Vector2(dz + 0.28 * hk, dash_y + 0.13 * hk), Vector2(dz + 0.45 * hk, dash_y + 0.19 * hk),
		Vector2(dz + 0.62 * hk, dash_y + 0.2 * hk), Vector2(dz + 0.7 * hk, dash_y + 0.17 * hk)]
	var hw2 := 0.36 if T else 0.22
	_sweep(soft, hood_prof, eye.x - hw2, eye.x + hw2, dark.darkened(0.15), 10, true)
	# 中控台（往駕駛傾斜）
	var cs_prof := [Vector2(dz + 0.62 * dk, dash_y - 0.2), Vector2(dz + 0.82 * dk, dash_y - 0.45), Vector2(dz + 0.95 * dk, dash_y - 0.9), Vector2(dz + 1.0 * dk, dash_y - 1.3)]
	_sweep(soft, cs_prof, 0.05 if T else -0.15, 0.45 if T else 0.15, dark.lightened(0.04), 4, true)
	# A 柱（圓管，下粗上細）
	for sx in [-1.0, 1.0]:
		var bot := Vector3(sx * (half_w - 0.02), dash_y - 0.05, ws_z - 0.02)
		var top := Vector3(sx * (half_w - 0.08), roof_y, ws_z + (0.55 if T else 0.75))
		var up := (top - bot).normalized()
		var side := up.cross(Vector3.RIGHT).normalized()
		var basis := Basis(up.cross(side).normalized(), up, side)
		MeshKit.cyl(soft, Transform3D(basis, bot), 0.085, 0.06, bot.distance_to(top), 12, dark, false)
		# 車門內板＋扶手
		var door_prof := [Vector2(sx * (half_w + 0.03), dash_y + 0.05), Vector2(sx * (half_w - 0.02), dash_y + 0.0),
			Vector2(sx * (half_w - 0.06), dash_y - 0.18), Vector2(sx * (half_w - 0.04), dash_y - 0.3), Vector2(sx * (half_w + 0.02), dash_y - 1.0)]
		_sweep_z(soft, door_prof, eye.z - 0.9, eye.z + 1.0, Color(0.2, 0.19, 0.19), 6)
		# B 柱
		MeshKit.cyl(soft, X.call(sx * (half_w - 0.02), dash_y, eye.z + (0.85 if T else 0.6)), 0.07, 0.06, roof_y - dash_y, 10, dark, false)
	# 車頂內襯（微微拱起）
	var top_z := ws_z + (0.55 if T else 0.75)
	var back_z := eye.z + (1.2 if T else 0.9)
	var roof_prof := []
	for k in 9:
		var x := lerpf(-half_w, half_w, k / 8.0)
		roof_prof.append(Vector2(x, roof_y + 0.06 * (1.0 - pow(x / half_w, 2.0))))
	_sweep_z(soft, roof_prof, top_z - 0.05, back_z, Color(0.36, 0.35, 0.34), 8, true)
	# 遮陽板（圓角）
	MeshKit.box(soft, X.call(eye.x, roof_y - 0.06, top_z + 0.18, 0.25), Vector3(0.62, 0.035, 0.3), Color(0.32, 0.31, 0.3))
	if T:
		MeshKit.box(soft, X.call(0, (dash_y + roof_y) * 0.5 - 0.3, eye.z + 1.15), Vector3(half_w * 2, roof_y - dash_y + 1.0, 0.1), Color(0.24, 0.24, 0.25))
	soft.index()
	soft.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = soft.commit()
	mi.material_override = _leather()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	# 儀表板上的出風口、按鍵
	for k in 4:
		var vx := -half_w + 0.25 + k * (half_w * 2 - 0.5) / 3.0
		if absf(vx - eye.x) < hw2 + 0.05:
			continue
		MeshKit.box(st, X.call(vx, dash_y - 0.16, dz + 0.69, -0.2), Vector3(0.2, 0.07, 0.02), Color(0.05, 0.05, 0.06))
	for k in 6:
		MeshKit.box(st, X.call((0.12 if T else -0.08) + (k % 3) * 0.08, dash_y - 0.42 - (k / 3) * 0.06, dz + 0.86, -0.5), Vector3(0.06, 0.035, 0.015), Color(0.3, 0.3, 0.33))
	var mi2 := MeshInstance3D.new()
	mi2.mesh = st.commit()
	var m2 := StandardMaterial3D.new()
	m2.vertex_color_use_as_albedo = true
	m2.vertex_color_is_srgb = true
	m2.roughness = 0.5
	mi2.material_override = m2
	add_child(mi2)
	# 方向盤：皮革握把＋三輻＋中央氣囊
	wheel = Node3D.new()
	wheel.position = Vector3(eye.x, dash_y - (0.02 if T else 0.12), ws_z + (0.66 if T else 0.5))
	wheel.rotation.x = deg_to_rad(-38 if T else -22)
	add_child(wheel)
	var R := 0.225 if T else 0.18
	var tor := TorusMesh.new()
	tor.inner_radius = R - 0.018
	tor.outer_radius = R + 0.018
	tor.rings = 48
	tor.ring_segments = 12
	var wm := MeshInstance3D.new()
	wm.mesh = tor
	wm.rotation.x = PI * 0.5
	wm.material_override = _leather(Color(0.06, 0.06, 0.065))
	wheel.add_child(wm)
	for a in [0.0, PI, -PI * 0.5]:
		var sp := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(R - 0.06, 0.03 if a != -PI * 0.5 else 0.04, 0.015)
		sp.mesh = bm
		sp.rotation.z = a
		sp.position = Vector3(cos(a), sin(a), 0) * (R * 0.5 + 0.02) + Vector3(0, 0, 0.01)
		sp.material_override = _flat(Color(0.12, 0.12, 0.13))
		wheel.add_child(sp)
	var hub := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.075
	cm.bottom_radius = 0.085
	cm.height = 0.06
	cm.radial_segments = 24
	hub.mesh = cm
	hub.rotation.x = PI * 0.5
	hub.position.z = 0.02
	hub.material_override = _leather(Color(0.07, 0.07, 0.075))
	wheel.add_child(hub)
	var logo := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.022
	lm.bottom_radius = 0.022
	lm.height = 0.005
	logo.mesh = lm
	logo.rotation.x = PI * 0.5
	logo.position.z = 0.052
	var lmat := _flat(Color(0.75, 0.77, 0.8))
	lmat.metallic = 0.9
	lmat.roughness = 0.25
	logo.material_override = lmat
	wheel.add_child(logo)
	var col := MeshInstance3D.new()
	var colm := CylinderMesh.new()
	colm.top_radius = 0.045
	colm.bottom_radius = 0.06
	colm.height = 0.35
	col.mesh = colm
	col.rotation.x = -PI * 0.5
	col.position.z = -0.18
	col.material_override = _flat(Color(0.08, 0.08, 0.09))
	wheel.add_child(col)
	# 儀表（方向盤後方）
	cluster_vp = _vp(Vector2i(640, 256))
	cluster = dash_script.new()
	cluster.set("mode", "cluster")
	cluster.set("veh", v)
	cluster_vp.add_child(cluster)
	cluster_quad = _screen(cluster_vp, Vector2(0.56, 0.224) if T else Vector2(0.4, 0.16),
		Vector3(eye.x, dash_y + (0.05 if T else 0.02), ws_z + (0.6 if T else 0.36)), 18.0)
	spots["cluster"] = cluster_quad.position
	# 導航平板（中間）
	tablet_vp = _vp(Vector2i(720, 480))
	tablet = dash_script.new()
	tablet.set("mode", "tablet")
	tablet.set("veh", v)
	tablet_vp.add_child(tablet)
	tablet_quad = _screen(tablet_vp, Vector2(0.39, 0.26) if T else Vector2(0.3, 0.2),
		Vector3(0.12 if T else 0.02, dash_y + (0.24 if T else 0.12), ws_z + (0.4 if T else 0.28)), 22.0, -0.3)
	spots["tablet"] = tablet_quad.position
	# 支架
	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.05, 0.2, 0.05)
	arm.mesh = am
	arm.position = tablet_quad.position + Vector3(0, -0.18, 0.04)
	arm.material_override = _flat(dark)
	add_child(arm)
	# 後照鏡（左右，車外）
	for sx in [-1.0, 1.0]:
		var vp := _vp(Vector2i(220, 360))
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var cam := Camera3D.new()
		cam.fov = 38.0
		cam.far = 600.0
		cam.current = true
		vp.add_child(cam)
		mirror_cams.append(cam)
		mirror_vps.append(vp)
		var mp := Vector3(sx * (half_w + (0.42 if T else 0.2)), dash_y + (0.55 if T else 0.08), ws_z + (0.2 if T else 0.3))
		var housing := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(0.3 if T else 0.22, 0.52 if T else 0.15, 0.08)
		housing.mesh = hb
		housing.position = mp + Vector3(0, 0, -0.05)
		housing.rotation.y = sx * -0.35
		housing.material_override = _flat(Color(0.1, 0.1, 0.12))
		add_child(housing)
		var q := _screen(vp, Vector2(0.26 if T else 0.19, 0.46 if T else 0.12), mp, 0.0, sx * -0.35, true)
		mirror_quads.append(q)
		spots["mirror_l" if sx < 0 else "mirror_r"] = mp
		cam.set_meta("local", mp)
		cam.set_meta("side", sx)
	# 雨刷
	wiper_l = _wiper(Vector3(-0.6 if T else -0.42, dash_y - 0.05, ws_z - 0.08), T)
	wiper_r = _wiper(Vector3(0.42 if T else 0.22, dash_y - 0.05, ws_z - 0.08), T)
	# 擋風玻璃上的雨滴
	rain_glass = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(half_w * 2, (roof_y - dash_y) * 1.05)
	rain_glass.mesh = qm
	rain_glass.position = Vector3(0, (dash_y + roof_y) * 0.5, ws_z + (0.25 if T else 0.35))
	rain_glass.rotation.x = deg_to_rad(-10 if T else -35)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://scripts/rain_glass.gdshader")
	rain_glass.material_override = sm
	rain_glass.visible = false
	rain_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain_glass)



func _leather(tint := Color(0.11, 0.11, 0.12)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	if ResourceLoader.exists("res://assets/tex/leather_diff.jpg"):
		m.normal_enabled = true
		m.normal_texture = load("res://assets/tex/leather_nor.jpg")
		m.normal_scale = 0.6
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(3, 3, 3)
	if tint != Color(0.11, 0.11, 0.12):
		m.vertex_color_use_as_albedo = false
		m.albedo_color = tint
	m.roughness = 0.78
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## 側面輪廓（z, y）沿 x 擠出
func _sweep(s: SurfaceTool, prof: Array, x0: float, x1: float, col: Color, _segs := 1, caps := false) -> void:
	for i in prof.size() - 1:
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		MeshKit.quad(s, Vector3(x0, p0.y, p0.x), Vector3(x1, p0.y, p0.x), Vector3(x1, p1.y, p1.x), Vector3(x0, p1.y, p1.x), col)
	if caps:
		for x in [x0, x1]:
			var c: Vector2 = prof[0].lerp(prof[prof.size() - 1], 0.5)
			for i in prof.size() - 1:
				MeshKit.tri(s, Vector3(x, c.y, c.x), Vector3(x, prof[i].y, prof[i].x), Vector3(x, prof[i + 1].y, prof[i + 1].x), col)


## 正面輪廓（x, y）沿 z 擠出
func _sweep_z(s: SurfaceTool, prof: Array, z0: float, z1: float, col: Color, _segs := 1, _caps := false) -> void:
	for i in prof.size() - 1:
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		MeshKit.quad(s, Vector3(p0.x, p0.y, z0), Vector3(p0.x, p0.y, z1), Vector3(p1.x, p1.y, z1), Vector3(p1.x, p1.y, z0), col)

func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	return m


func _vp(sz: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = sz
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	add_child(vp)
	return vp


## 把 SubViewport 貼在一片四邊形上（recline：上緣往前倒的角度；mirror=true 時左右翻轉）
func _screen(vp: SubViewport, sz: Vector2, pos: Vector3, recline_deg: float, yaw := 0.0, mirror := false) -> MeshInstance3D:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = sz
	q.mesh = qm
	q.position = pos
	q.rotation = Vector3(-deg_to_rad(recline_deg), yaw, 0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = vp.get_texture()
	if mirror:
		m.uv1_scale = Vector3(-1, 1, 1)
		m.uv1_offset = Vector3(1, 0, 0)
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(q)
	return q


func _wiper(base: Vector3, T: bool) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = base
	pivot.rotation.x = deg_to_rad(-10 if T else -35)
	add_child(pivot)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.85 if T else 0.6, 0.02)
	blade.mesh = bm
	blade.position = Vector3(0, bm.size.y * 0.5, 0)
	blade.material_override = _flat(Color(0.05, 0.05, 0.05))
	pivot.add_child(blade)
	pivot.rotation.z = 1.52
	return pivot


func update_cabin(dt: float, world: World) -> void:
	wheel.rotation.z = veh.steer * (9.0 if veh.kind == "truck" else 7.0)
	# 雨刷
	if veh.wipers > 0:
		_wiper_t += dt * (1.6 if veh.wipers == 1 else 3.0)
		var a := 1.52 - (0.5 - 0.5 * cos(_wiper_t * PI)) * 2.4
		wiper_l.rotation.z = a
		wiper_r.rotation.z = a
	else:
		wiper_l.rotation.z = move_toward(wiper_l.rotation.z, 1.52, dt * 3.0)
		wiper_r.rotation.z = wiper_l.rotation.z
	var raining := world != null and world.wet > 0.0
	rain_glass.visible = raining
	if raining:
		var sm: ShaderMaterial = rain_glass.material_override
		sm.set_shader_parameter("wiper", wiper_l.rotation.z)
		sm.set_shader_parameter("intensity", 1.0 if world.weather == "storm" else 0.6)
	# 後照鏡相機：位置跟著車，朝後看
	_frame += 1
	for i in mirror_cams.size():
		var cam: Camera3D = mirror_cams[i]
		var lp: Vector3 = cam.get_meta("local")
		var sx: float = cam.get_meta("side")
		var gp := veh.body.global_transform * lp
		cam.global_position = gp
		var back := veh.body.global_transform.basis * Vector3(sx * 0.1, -0.06, 1.0)
		cam.look_at(gp + back, Vector3.UP)
		if str(App.settings.quality) == "low":
			mirror_vps[i].render_target_update_mode = SubViewport.UPDATE_ONCE if (_frame + i) % 3 == 0 else SubViewport.UPDATE_DISABLED
	cluster.queue_redraw()
	tablet.queue_redraw()


func set_world(w: World) -> void:
	for vp in mirror_vps:
		(vp as SubViewport).world_3d = get_viewport().world_3d
	var _w := w
