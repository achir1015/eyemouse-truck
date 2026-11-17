class_name Vehicle
extends Node3D
## 玩家車輛：簡化單車模型（後軸為原點，車頭朝 -Z），卡車有半拖車鉸接。左駕（駕駛座在左邊）。

signal crashed(kmh: float, what: String)

const SPECS := {
	"truck": {"name": "小柯物流聯結車", "wb": 3.9, "steer": 0.62, "vmax": 100.0, "acc": 1.9, "brk": 6.0, "lat": 4.2,
		"eye": Vector3(-0.62, 2.62, -3.8), "front": -5.3, "rear": 1.2, "width": 2.5, "rate": 1.2},
	"car": {"name": "小柯豪華房車", "wb": 2.85, "steer": 0.6, "vmax": 170.0, "acc": 3.8, "brk": 8.5, "lat": 7.5,
		"eye": Vector3(-0.38, 1.17, -1.3), "front": -3.75, "rear": 1.05, "width": 1.85, "rate": 2.2},
}
const TRAILER_LEN := 13.6
const KINGPIN := 1.2          # 牽引銷到拖車前緣
const TRAILER_AXLE := 10.6    # 牽引銷到拖車軸

var kind := "truck"
var spec: Dictionary
var world: World
var speed := 0.0              # m/s，負 = 倒車
var yaw := 0.0
var steer := 0.0              # rad，正 = 左
var steer_input := 0.0        # -1 左 … +1 右
var throttle := 0.0
var brake := 0.0
var gear := "P"               # P R N D
var engine_on := false
var handbrake := true
var seatbelt := false
var rpm := 0.0
var gear_no := 1
var blinker := 0              # -1 左、1 右、2 雙黃燈
var lights_on := false
var high_beam := false
var wipers := 0
var horn := false
var fuel := 0.92
var odometer := 0.0
var trailer_yaw := 0.0
var has_trailer := true
var trailer: Node3D
var body: Node3D
var cruise := -1.0            # 定速（km/h），-1 關
var lat_acc := 0.0
var _hit_cool := 0.0
var _brake_glow: Array = []
var _blink_l: Array = []
var _blink_r: Array = []
var _head: Array = []
var _blink_t := 0.0
var traffic_push: Callable     # (Vector2, r) -> Vector2


func setup(k: String, w: World, pos: Vector2, heading_yaw: float) -> void:
	kind = k
	spec = SPECS[k]
	world = w
	has_trailer = k == "truck"
	position = Vector3(pos.x, 0, pos.y)
	yaw = heading_yaw
	trailer_yaw = heading_yaw
	rotation.y = yaw
	_build()


func pos2() -> Vector2:
	return Vector2(position.x, position.z)


func fwd2() -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


func kmh() -> float:
	return absf(speed) * 3.6


## 世界座標：車上某點（本地 x 右、z 往後）
func local_to_2d(lx: float, lz: float) -> Vector2:
	var f := fwd2()
	var r := Vector2(-f.y, f.x)
	return pos2() + r * lx - f * lz


func front_center() -> Vector2:
	return local_to_2d(0, spec.front)


func kingpin_2d() -> Vector2:
	return local_to_2d(0, -0.4)


func trailer_axle_2d() -> Vector2:
	var tf := Vector2(-sin(trailer_yaw), -cos(trailer_yaw))
	return kingpin_2d() - tf * TRAILER_AXLE


## 碰撞圓：[[中心 Vector2, 半徑]]
func circles() -> Array:
	var out := []
	if kind == "truck":
		out.append([local_to_2d(0, -4.0), 1.3])
		out.append([local_to_2d(0, -1.4), 1.3])
		if has_trailer:
			var tf := Vector2(-sin(trailer_yaw), -cos(trailer_yaw))
			var kp := kingpin_2d()
			for k in 5:
				out.append([kp - tf * (1.2 + k * 2.75), 1.3])
	else:
		for z in [0.4, -1.4, -3.0]:
			out.append([local_to_2d(0, z), 0.95])
	return out


# ---------------------------------------------------------------- 物理
func physics(dt: float) -> void:
	var grip := 1.0
	if world:
		grip = 1.0 - world.wet * 0.3
		if world.weather == "cold":
			grip = 0.85
	var v := speed
	var vmax: float = spec.vmax / 3.6
	# 定速：自動油門
	if cruise > 0.0 and gear == "D" and brake < 0.05:
		var target := cruise / 3.6
		throttle = clampf((target - v) * 0.8, 0.0, 1.0)
		if v > target + 1.5:
			brake = maxf(brake, clampf((v - target) * 0.15, 0.0, 0.4))
	# 轉向：高速時可轉角度變小
	var max_st: float = spec.steer * clampf(1.0 - absf(v) / 38.0 * 0.65, 0.3, 1.0)
	var target_steer := -steer_input * max_st
	steer = move_toward(steer, target_steer, float(spec.rate) * dt)
	# 推力
	var a := 0.0
	if engine_on and not handbrake:
		if gear == "D":
			a += float(spec.acc) * throttle * clampf(1.0 - maxf(v, 0.0) / vmax, 0.0, 1.0) * (1.0 if v >= -0.5 else 0.0)
		elif gear == "R":
			a -= float(spec.acc) * 0.6 * throttle * clampf(1.0 - absf(minf(v, 0.0)) / 5.0, 0.0, 1.0) * (1.0 if v <= 0.5 else 0.0)
	# 阻力
	var drag := 0.18 + 0.0009 * v * v * (2.0 if kind == "truck" else 1.0)
	if engine_on and throttle < 0.05 and gear in ["D", "R"]:
		drag += 0.35   # 引擎煞車
	var dec := drag + float(spec.brk) * brake * (0.6 + 0.4 * grip)
	if handbrake or gear == "P":
		dec += 9.0
	# 速度更新
	v += a * dt
	if absf(v) > 0.0:
		var dv := dec * dt
		if absf(v) <= dv:
			v = 0.0
		else:
			v -= signf(v) * dv
	# 怠速爬行（D 檔放開煞車會慢慢前進）
	if engine_on and not handbrake and gear == "D" and brake < 0.05 and throttle < 0.05 and v < 1.4 and v >= 0.0:
		v = move_toward(v, 1.4, 0.6 * dt)
	speed = v
	# 轉向造成的偏航，受抓地力限制（打滑時轉不過去）
	var yr := v / float(spec.wb) * tan(steer)
	var lim := float(spec.lat) * grip / maxf(absf(v), 0.5)
	yr = clampf(yr, -lim, lim)
	lat_acc = yr * v
	yaw += yr * dt
	var f := fwd2()
	var np := pos2() + f * v * dt
	position = Vector3(np.x, 0, np.y)
	odometer += absf(v) * dt
	fuel = maxf(0.0, fuel - absf(v) * dt * (0.000004 if kind == "car" else 0.000008))
	# 拖車
	if has_trailer:
		trailer_yaw += v / TRAILER_AXLE * sin(yaw - trailer_yaw) * dt
		var diff := wrapf(yaw - trailer_yaw, -PI, PI)
		if absf(diff) > 1.35:      # 折刀角度限制
			trailer_yaw = yaw - signf(diff) * 1.35
	_collide(dt)
	_engine_state()
	rotation.y = yaw
	_update_visual(dt)


func _collide(dt: float) -> void:
	_hit_cool = maxf(0.0, _hit_cool - dt)
	if world == null:
		return
	var total := Vector2.ZERO
	var what := ""
	var cs := circles()
	for i in cs.size():
		var c: Vector2 = cs[i][0]
		var r: float = cs[i][1]
		var p := world.push_out(c, r)
		if p != Vector2.ZERO:
			what = "障礙物"
		if traffic_push.is_valid():
			var tp: Vector2 = traffic_push.call(c, r)
			if tp != Vector2.ZERO:
				what = "其他車輛"
				p += tp
		if i >= 2 and kind == "truck":
			p *= 0.5     # 拖車撞到：推力一半傳回車頭
		total += p
	# 國道、山路的護欄：不能開出路面
	var q := world.net.query(pos2())
	if q.edge >= 0 and q.node < 0:
		var d: Dictionary = world.net.edges[q.edge]
		if d.kind in ["highway", "mountain", "ramp"]:
			var hw := world.net.half_width(q.edge) - float(spec.width) * 0.5 - 0.1
			var right := Vector2(-d.dir.y, d.dir.x)
			var nearest_node := minf(pos2().distance_to(world.net.nodes[d.a]) - world.net.node_r[d.a], pos2().distance_to(world.net.nodes[d.b]) - world.net.node_r[d.b])
			if absf(q.lat) > hw and nearest_node > 2.0:
				total += -right * signf(q.lat) * (absf(q.lat) - hw)
				what = "護欄"
			if d.kind == "highway":
				var med: float = d.median * 0.5 + float(spec.width) * 0.5
				if absf(q.lat) < med:
					total += right * signf(q.lat if absf(q.lat) > 0.01 else 1.0) * (med - absf(q.lat))
					what = "中央護欄"
	if total == Vector2.ZERO:
		return
	total = total.limit_length(1.5)
	var np := pos2() + total
	position = Vector3(np.x, 0, np.y)
	var n := total.normalized()
	var vel := fwd2() * speed
	var into := -vel.dot(n)
	if into > 2.0 and _hit_cool <= 0.0:
		_hit_cool = 1.5
		crashed.emit(into * 3.6, what)
		speed *= 0.25
	elif into > 0.0:
		speed *= 0.92
		if what in ["護欄", "中央護欄"] and kmh() > 15 and _hit_cool <= 0.0:
			_hit_cool = 2.0
			crashed.emit(minf(kmh(), 25.0), what)


func _engine_state() -> void:
	var v := kmh()
	if not engine_on:
		rpm = move_toward(rpm, 0.0, 60.0)
		gear_no = 0
		return
	if kind == "truck":
		gear_no = clampi(int(v / 9.0) + 1, 1, 12)
		var frac := (v - (gear_no - 1) * 9.0) / 9.0
		rpm = 650.0 + clampf(frac, 0.0, 1.0) * 1300.0 + throttle * 120.0
		if gear in ["N", "P"]:
			rpm = 650.0 + throttle * 1200.0
	else:
		gear_no = clampi(int(v / 32.0) + 1, 1, 6)
		var frac2 := (v - (gear_no - 1) * 32.0) / 32.0
		rpm = 800.0 + clampf(frac2, 0.0, 1.0) * 4200.0 + throttle * 300.0
		if gear in ["N", "P"]:
			rpm = 800.0 + throttle * 4000.0
	if gear == "R":
		gear_no = -1


# ---------------------------------------------------------------- 外觀
func _mat(col: Color, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.5
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _vc_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.45
	m.metallic = 0.15
	return m


func _glow_box(parent: Node3D, pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mat(col, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _build() -> void:
	body = Node3D.new()
	add_child(body)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wheel := Color(0.08, 0.08, 0.09)
	var X := func(x: float, y: float, z: float) -> Transform3D: return Transform3D(Basis.IDENTITY, Vector3(x, y, z))
	var wheel_xf := func(x: float, z: float, r: float) -> Transform3D:
		return Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x, r, z))
	if kind == "truck":
		var cab := Color(0.12, 0.38, 0.78)
		MeshKit.box(st, X.call(0, 0.85, -2.2), Vector3(1.0, 0.35, 6.0), Color(0.15, 0.15, 0.16))       # 底盤
		MeshKit.box(st, X.call(0, 1.95, -4.05), Vector3(2.5, 2.3, 2.4), cab)                           # 駕駛室
		MeshKit.box(st, X.call(0, 3.35, -4.15), Vector3(2.45, 0.5, 2.2), cab.lightened(0.15))          # 車頂
		MeshKit.box(st, X.call(0, 0.75, -5.3), Vector3(2.5, 0.5, 0.2), Color(0.75, 0.75, 0.78))        # 保險桿
		MeshKit.box(st, X.call(0, 1.55, -5.27), Vector3(1.8, 0.9, 0.06), Color(0.25, 0.25, 0.27))      # 水箱罩
		MeshKit.box(st, X.call(0, 1.05, -0.4), Vector3(2.0, 0.15, 1.6), Color(0.25, 0.25, 0.25))       # 鞍座
		for z in [-3.9, 0.0, 1.3]:
			for x in [-1.05, 1.05]:
				MeshKit.cyl(st, wheel_xf.call(x - 0.25, z, 0.52) * Transform3D(Basis.IDENTITY, Vector3.ZERO), 0.52, 0.52, 0.5, 12, wheel)
		# 半拖車（另一個節點，依拖車角度轉動）
		trailer = Node3D.new()
		trailer.top_level = true
		add_child(trailer)
		var ts := SurfaceTool.new()
		ts.begin(Mesh.PRIMITIVE_TRIANGLES)
		MeshKit.box(ts, X.call(0, 2.45, TRAILER_LEN * 0.5 - KINGPIN), Vector3(2.55, 2.9, TRAILER_LEN), Color(0.93, 0.93, 0.95))
		MeshKit.box(ts, X.call(0, 0.95, TRAILER_LEN * 0.5 - KINGPIN), Vector3(2.2, 0.3, TRAILER_LEN - 0.4), Color(0.2, 0.2, 0.22))
		MeshKit.box(ts, X.call(0, 2.45, TRAILER_LEN * 0.5 - KINGPIN), Vector3(2.57, 0.5, TRAILER_LEN - 1.0), Color(0.1, 0.45, 0.85))
		for z in [TRAILER_AXLE - 1.3, TRAILER_AXLE, TRAILER_AXLE + 1.3]:
			for x in [-1.0, 1.0]:
				MeshKit.cyl(ts, wheel_xf.call(x - 0.25, z, 0.52), 0.52, 0.52, 0.5, 12, wheel)
		var tm := Models.make("trailer", TRAILER_LEN)
		if tm:
			tm.position.z = TRAILER_LEN * 0.5 - KINGPIN
			trailer.add_child(tm)
		else:
			var tmi := MeshInstance3D.new()
			tmi.mesh = ts.commit()
			tmi.material_override = _vc_mat()
			trailer.add_child(tmi)
		for sd in [-1.0, 1.0]:
			var l := Landmarks.label(trailer, "小柯物流", Vector3(sd * 1.3, 3.2, 5.0), 0.022, sd * PI * 0.5, Color(0.1, 0.35, 0.8), false)
			l.outline_modulate = Color(1, 1, 1, 0.9)
			l.outline_size = 10
		var rear := TRAILER_LEN - KINGPIN + 0.01
		_brake_glow.append(_glow_box(trailer, Vector3(-0.95, 1.1, rear), Vector3(0.4, 0.2, 0.05), Color(0.35, 0.02, 0.02)))
		_brake_glow.append(_glow_box(trailer, Vector3(0.95, 1.1, rear), Vector3(0.4, 0.2, 0.05), Color(0.35, 0.02, 0.02)))
		_blink_l.append(_glow_box(trailer, Vector3(-1.2, 1.1, rear), Vector3(0.12, 0.2, 0.05), Color(1, 0.6, 0.1)))
		_blink_r.append(_glow_box(trailer, Vector3(1.2, 1.1, rear), Vector3(0.12, 0.2, 0.05), Color(1, 0.6, 0.1)))
		_blink_l.append(_glow_box(body, Vector3(-1.26, 1.2, -5.2), Vector3(0.05, 0.15, 0.25), Color(1, 0.6, 0.1)))
		_blink_r.append(_glow_box(body, Vector3(1.26, 1.2, -5.2), Vector3(0.05, 0.15, 0.25), Color(1, 0.6, 0.1)))
		for x in [-0.95, 0.95]:
			_head.append(_glow_box(body, Vector3(x, 1.05, -5.36), Vector3(0.45, 0.22, 0.05), Color(0.9, 0.9, 0.85)))
	else:
		var paint := Color(0.08, 0.1, 0.14)
		MeshKit.box(st, X.call(0, 0.62, -1.35), Vector3(1.85, 0.6, 4.75), paint)
		MeshKit.box(st, X.call(0, 1.12, -1.15), Vector3(1.6, 0.5, 2.5), Color(0.12, 0.16, 0.22))
		MeshKit.box(st, X.call(0, 1.39, -1.05), Vector3(1.5, 0.06, 1.9), paint)
		MeshKit.box(st, X.call(0, 0.55, -3.72), Vector3(1.8, 0.25, 0.08), Color(0.65, 0.65, 0.68))
		for z in [0.0, -2.85]:
			for x in [-0.82, 0.82]:
				MeshKit.cyl(st, wheel_xf.call(x - 0.11, z, 0.34), 0.34, 0.34, 0.22, 12, wheel)
		_brake_glow.append(_glow_box(body, Vector3(-0.7, 0.8, 1.02), Vector3(0.4, 0.12, 0.05), Color(0.35, 0.02, 0.02)))
		_brake_glow.append(_glow_box(body, Vector3(0.7, 0.8, 1.02), Vector3(0.4, 0.12, 0.05), Color(0.35, 0.02, 0.02)))
		_blink_l.append(_glow_box(body, Vector3(-0.92, 0.75, -3.6), Vector3(0.05, 0.1, 0.2), Color(1, 0.6, 0.1)))
		_blink_r.append(_glow_box(body, Vector3(0.92, 0.75, -3.6), Vector3(0.05, 0.1, 0.2), Color(1, 0.6, 0.1)))
		_blink_l.append(_glow_box(body, Vector3(-0.92, 0.8, 1.0), Vector3(0.05, 0.1, 0.1), Color(1, 0.6, 0.1)))
		_blink_r.append(_glow_box(body, Vector3(0.92, 0.8, 1.0), Vector3(0.05, 0.1, 0.1), Color(1, 0.6, 0.1)))
		for x in [-0.65, 0.65]:
			_head.append(_glow_box(body, Vector3(x, 0.72, -3.76), Vector3(0.4, 0.12, 0.05), Color(0.9, 0.9, 0.85)))
	# 寫實模型（TRELLIS）；沒有就用程序化車殼
	var model := Models.make("truck_tractor" if kind == "truck" else "sedan", 6.4 if kind == "truck" else 4.85)
	if model:
		model.position.z = (float(spec.front) + (0.9 if kind == "truck" else float(spec.rear))) * 0.5
		body.add_child(model)
		_set_layer(model, 2)          # 車殼外觀：駕駛室視角不畫（只給後照鏡與車外視角）
		# 寫實模型本身就有車燈：拿掉車頭的程序化燈塊（拖車的保留）
		for arr in [_brake_glow, _blink_l, _blink_r, _head]:
			for g in arr.duplicate():
				if g is MeshInstance3D and g.get_parent() == body:
					arr.erase(g)
					g.queue_free()
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _vc_mat()
		mi.layers = 2
		body.add_child(mi)
	# 大燈（夜間）
	for x in ([-0.8, 0.8] if kind == "truck" else [-0.6, 0.6]):
		var sl := SpotLight3D.new()
		sl.position = Vector3(x, 1.1 if kind == "truck" else 0.7, float(spec.front) - 0.1)
		sl.rotation = Vector3(deg_to_rad(-6), 0, 0)
		sl.spot_range = 70.0
		sl.spot_angle = 32.0
		sl.light_energy = 3.0
		sl.light_color = Color(1, 0.96, 0.88)
		sl.visible = false
		sl.name = "Headlight"
		body.add_child(sl)
		_head.append(sl)


func _update_visual(dt: float) -> void:
	if trailer:
		var kp := kingpin_2d()
		trailer.global_position = Vector3(kp.x, 0, kp.y)
		trailer.global_rotation = Vector3(0, trailer_yaw, 0)
	_blink_t += dt
	var on := fmod(_blink_t, 0.8) < 0.4
	for b in _blink_l:
		b.visible = on and (blinker == -1 or blinker == 2)
	for b in _blink_r:
		b.visible = on and (blinker == 1 or blinker == 2)
	var braking := brake > 0.1 or (absf(speed) < 0.2 and engine_on and gear in ["D", "R"])
	for b in _brake_glow:
		(b.material_override as StandardMaterial3D).albedo_color = Color(1, 0.08, 0.05) if braking else (Color(0.55, 0.03, 0.03) if lights_on else Color(0.3, 0.02, 0.02))
	for h in _head:
		if h is SpotLight3D:
			h.visible = lights_on
			(h as SpotLight3D).spot_range = 110.0 if high_beam else 70.0
		else:
			(h.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 0.92) if lights_on else Color(0.75, 0.75, 0.72)


func _set_layer(n: Node, layer: int) -> void:
	for c in Models._meshes(n):
		(c as MeshInstance3D).layers = layer


func blink_phase() -> bool:
	return fmod(_blink_t, 0.8) < 0.4
