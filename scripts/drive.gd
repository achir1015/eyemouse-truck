extends Node3D
## 駕駛場景：世界＋車輛＋駕駛室＋車流＋導航＋小柯自駕＋規則評分＋課程。
## 由 main.gd 建立：setup(cfg)。cfg：map、vehicle、time、weather、lesson（id 或空）、dest（POI 名稱）

signal finished(result: Dictionary)
signal message(text: String, kind: String)

var cfg := {}
var lesson := {}
var world: World
var veh: Vehicle
var cabin: Cabin
var traffic: Traffic
var nav: Nav
var ap: Autopilot
var hud: Node
var cam: Camera3D
var head: Node3D
var view := "cabin"            # cabin / chase / top
var look_yaw := 0.0
var look_pitch := 0.0
var _look_target := Vector2.ZERO
var paused := false
var done := false

# 規則與評分
var score := 100
var violations: Array = []     # {kind, text, pts, t}
var _cool := {}
var _speed_t := 0.0
var _wrong_t := 0.0
var _off_t := 0.0
var _dark_t := 0.0
var _belt_warned := false
var _last_blink := {-1: -99.0, 1: -99.0}
var _in_node := -1
var _entry_edge := -1
var _entry_yaw := 0.0
var _min_speed_before := 99.0
var elapsed := 0.0
var limit_now := 0
var limit_sign := 0
var road_name := ""
var cur_edge := -1
var recognized := {}           # sign id -> true
var recog_count := 0
var last_sign := {}            # 最近辨識到的標誌（HUD 卡片）
var _sign_t := 0.0
var wind := 0.0
var _wind_t := 0.0
var _events_done := {}
var _amb_blocked := 0.0
var _park_ok_t := 0.0
var _stop_zone := Vector2.ZERO
var _tip_t := 0.0
var input_lock := false        # 教學示範時鎖住輸入
var demo_inputs = null         # 測試／示範：覆蓋輸入 {steer, throttle, brake}


func setup(c: Dictionary) -> void:
	cfg = c
	if str(c.get("lesson", "")) != "":
		lesson = Lessons.find(str(c.lesson))
	var map_id: String = lesson.get("map", c.get("map", "taipei"))
	var cond := {"time": lesson.get("time", c.get("time", "day")), "weather": lesson.get("weather", c.get("weather", "clear"))}
	world = World.new()
	add_child(world)
	world.setup(map_id, cond)
	# 車輛
	veh = Vehicle.new()
	add_child(veh)
	var kind: String = c.get("vehicle", App.settings.vehicle)
	var sp := _spawn_point()
	veh.setup(kind, world, sp[0], sp[1])
	veh.crashed.connect(_on_crash)
	world.follow = veh
	# 駕駛室
	cabin = Cabin.new()
	veh.body.add_child(cabin)
	cabin.setup(veh, load("res://scripts/dash.gd"))
	cabin.cluster.set("drive", self)
	cabin.tablet.set("drive", self)
	# 頭部／相機
	head = Node3D.new()
	head.position = veh.spec.eye
	veh.body.add_child(head)
	cam = Camera3D.new()
	cam.fov = 74.0
	cam.near = 0.05
	cam.far = 3500.0
	cam.current = true
	head.add_child(cam)
	# 車流
	traffic = Traffic.new()
	add_child(traffic)
	traffic.setup(world, veh, float(lesson.get("density", world.map.get("density", 0.6))) * float(c.get("density_mul", 1.0)))
	veh.traffic_push = traffic.push
	# 導航
	nav = Nav.new(world.net)
	nav.arrived.connect(_on_arrived)
	ap = Autopilot.new(veh, world, nav, traffic)
	var dest_name: String = lesson.get("dest", c.get("dest", ""))
	if dest_name != "":
		set_destination(dest_name)
	if lesson.get("goal", "") == "stop_zone":
		var z: Array = lesson.zone_edge
		var e: int = z[0]
		_stop_zone = world.net.lane_point(e, world.net.edges[e].a, 0, float(z[1]))
		world.show_dest(_stop_zone)
	if lesson.get("goal", "") == "park":
		var pk: Dictionary = world.map.parking[int(lesson.park)]
		world.show_dest(pk.pos)
	# 起始狀態：簡單模式（眼控）自動準備好
	if str(App.settings.control) == "eye" or c.get("ready", false) or App.test_mode:
		_make_ready()
	if world.is_night():
		veh.lights_on = str(App.settings.control) == "eye"
	# 事件
	for ev in lesson.get("events", []):
		if ev == "accident":
			_setup_accident()
		elif ev == "jam":
			_setup_jam()
	# 音樂
	if bool(App.settings.music_on) and not App.test_mode:
		Snd.play_track(int(App.settings.music_track))
	# HUD
	hud = load("res://scripts/hud.gd").new()
	add_child(hud)
	hud.setup(self)
	if str(App.settings.control) == "eye":
		ap.mode = "lka"
	await get_tree().process_frame
	if lesson.has("intro"):
		Snd.say(lesson.intro, true)
		say_msg(lesson.desc, "info")
	else:
		Snd.say("drive_hello", true)


func _make_ready() -> void:
	veh.engine_on = true
	veh.seatbelt = true
	veh.handbrake = false
	veh.gear = "D"


func _spawn_point() -> Array:
	var net := world.net
	if lesson.has("start_at"):
		var pk: Dictionary = world.map.parking[int(lesson.park)]
		var truck: bool = str(cfg.get("vehicle", App.settings.vehicle)) == "truck"
		if lesson.start_at == "bay":
			# 開過車格、停在北邊的車道上，車頭朝北，準備倒車入庫
			return [Vector2(1.9, pk.pos.y - (24.0 if truck else 12.0)), 0.0]
		return [Vector2(pk.pos.x - (28.0 if truck else 20.0), 1.9), -PI * 0.5]
	var a: int = world.map.spawn.node
	var b: int = world.map.spawn.next
	if lesson.has("start"):
		a = lesson.start[0]
		b = lesson.start[1]
	var e := net.edge_between(a, b)
	var p := net.lane_point(e, a, 0, net.t_out(e, a) + 6.0 / maxf(net.edges[e].len, 6.0))
	if net.edges[e].len < 40:
		p = net.lane_point(e, a, 0, 0.5)
	var d := (net.nodes[b] - net.nodes[a]).normalized()
	var yaw := atan2(-d.x, -d.y)
	# 車頭在前：原點是後軸，往後退一點讓車頭不超過起點
	return [p - d * (2.0 if veh == null else 0.0) + d * (6.5 if str(cfg.get("vehicle", App.settings.vehicle)) == "truck" else 4.0), yaw]


func set_destination(name: String) -> bool:
	for p in world.map.pois:
		if p.name == name:
			var ok := nav.set_dest(veh.pos2(), veh.fwd2(), int(p.node), name)
			if ok:
				world.show_dest(world.net.nodes[p.node])
				Snd.say("nav_start")
			return ok
	return false


# ---------------------------------------------------------------- 事件
func _setup_accident() -> void:
	# 在路線前方約 600 m 的國道路段上
	var acc := 0.0
	for i in nav.edges.size():
		var e: int = nav.edges[i]
		acc += world.net.edges[e].len
		if acc > 550.0 and world.net.edges[e].kind == "highway":
			var lanes: int = world.net.edges[e].lanes
			traffic.make_accident(e, nav.path[i], 0.5, lanes - 1)
			return


func _setup_jam() -> void:
	var list := []
	for i in range(1, mini(nav.edges.size(), 6)):
		list.append(nav.edges[i])
	traffic.make_jam(list, 14.0)


# ---------------------------------------------------------------- 輸入
func _key(k: Key) -> bool:
	return Input.is_physical_key_pressed(k)


func _unhandled_input(e: InputEvent) -> void:
	if done:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_ESCAPE: hud.toggle_pause()
			KEY_Q: toggle_blinker(-1)
			KEY_E: toggle_blinker(1)
			KEY_X: toggle_blinker(2)
			KEY_L: veh.lights_on = not veh.lights_on
			KEY_K: veh.high_beam = not veh.high_beam
			KEY_P: veh.wipers = (veh.wipers + 1) % 3
			KEY_B: toggle_belt()
			KEY_N: toggle_engine()
			KEY_SPACE: toggle_handbrake()
			KEY_R: shift_toggle()
			KEY_T: toggle_ap("full")
			KEY_Y: toggle_ap("lka")
			KEY_C: cycle_view()
			KEY_M:
				if e.shift_pressed:
					Snd.toggle_music()
				else:
					Snd.next_track()
			KEY_EQUAL, KEY_KP_ADD: cruise_adjust(10)
			KEY_MINUS, KEY_KP_SUBTRACT: cruise_adjust(-10)
			KEY_F: App.set_fullscreen(not bool(App.settings.fullscreen))
			KEY_1: view = "cabin"
			KEY_2: view = "chase"
			KEY_3: view = "top"
	if e is InputEventKey and e.physical_keycode == KEY_H:
		veh.horn = e.pressed
		if e.pressed and not e.echo:
			Snd.play("horn_truck" if veh.kind == "truck" else "horn_car", 0.8)
	if e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		look_yaw = clampf(look_yaw - e.relative.x * 0.004, -2.4, 2.4)
		look_pitch = clampf(look_pitch - e.relative.y * 0.003, -0.7, 0.5)


func toggle_blinker(side: int) -> void:
	veh.blinker = 0 if veh.blinker == side else side
	Snd.play("blinker", 0.5)


func toggle_belt() -> void:
	veh.seatbelt = not veh.seatbelt
	Snd.play("click")
	if veh.seatbelt:
		say_msg("安全帶繫好了", "ok")


func toggle_engine() -> void:
	veh.engine_on = not veh.engine_on
	Snd.play("door" if veh.engine_on else "click")
	say_msg("引擎發動" if veh.engine_on else "引擎熄火", "info")


func toggle_handbrake() -> void:
	veh.handbrake = not veh.handbrake
	Snd.play("air_brake" if veh.kind == "truck" else "click", 0.6)
	say_msg("手煞車拉起" if veh.handbrake else "手煞車放開", "info")


func shift_toggle() -> void:
	if veh.kmh() > 3.0:
		say_msg("請先停車再換檔", "warn")
		return
	veh.gear = "R" if veh.gear != "R" else "D"
	Snd.play("click")
	say_msg("倒車檔 R" if veh.gear == "R" else "前進檔 D", "info")
	if veh.gear == "R":
		Snd.say("tip_reverse")


func set_gear(g: String) -> void:
	if veh.kmh() > 3.0 and g != veh.gear:
		say_msg("請先停車再換檔", "warn")
		return
	veh.gear = g


func toggle_ap(m: String) -> void:
	if ap.mode == m:
		ap.mode = "off"
		say_msg("小柯自駕關閉，請自己駕駛" if m == "full" else "車道維持關閉", "info")
		Snd.say("ap_off")
		return
	if lesson.get("goal", "") in ["park", "stop_zone"] and m == "full":
		say_msg("這一課要自己練習，小柯不能代開喔", "warn")
		return
	if not nav.active:
		_auto_dest()
	if not veh.engine_on or veh.handbrake or veh.gear != "D":
		_make_ready()
	ap.mode = m
	veh.cruise = -1.0
	say_msg("小柯自駕開始" if m == "full" else "車道維持輔助開始：小柯幫你轉方向盤", "ok")
	Snd.say("ap_on" if m == "full" else "lka_on")


func _auto_dest() -> void:
	# 沒有目的地：挑一個最遠的景點
	var best := ""
	var bd := 0.0
	for p in world.map.pois:
		var d: float = world.net.nodes[p.node].distance_to(veh.pos2())
		if d > bd:
			bd = d
			best = p.name
	if best != "":
		set_destination(best)


func cruise_adjust(dk: float) -> void:
	if veh.cruise < 0:
		veh.cruise = maxf(10.0, roundf(veh.kmh() / 10.0) * 10.0)
	else:
		veh.cruise = clampf(veh.cruise + dk, 10.0, float(veh.spec.vmax))
	say_msg("定速 %d 公里" % int(veh.cruise), "info")


func cruise_off() -> void:
	veh.cruise = -1.0


func cycle_view() -> void:
	view = {"cabin": "chase", "chase": "top", "top": "cabin"}[view]
	Snd.play("click")


func _read_inputs(dt: float) -> void:
	if demo_inputs != null:
		veh.steer_input = float(demo_inputs.get("steer", 0.0))
		veh.throttle = float(demo_inputs.get("throttle", 0.0))
		veh.brake = float(demo_inputs.get("brake", 0.0))
		return
	var steer := 0.0
	var thr := 0.0
	var brk := 0.0
	if not input_lock:
		if _key(KEY_A) or _key(KEY_LEFT):
			steer -= 1.0
		if _key(KEY_D) or _key(KEY_RIGHT):
			steer += 1.0
		if _key(KEY_W) or _key(KEY_UP):
			thr = 1.0
		if _key(KEY_S) or _key(KEY_DOWN):
			brk = 1.0
		# 搖桿／方向盤
		if Input.get_connected_joypads().size() > 0:
			var jx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
			if absf(jx) > 0.08:
				steer = jx
			var rt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
			var lt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
			if rt > 0.05:
				thr = rt
			if lt > 0.05:
				brk = lt
		# 眼控／觸控按鈕
		var hs: Dictionary = hud.held()
		if hs.get("left", false):
			steer -= 1.0
		if hs.get("right", false):
			steer += 1.0
		if hs.get("gas", false):
			thr = 1.0
		if hs.get("brake", false):
			brk = 1.0
	# 鍵盤方向：漸進（避免一按就打死）
	var analog := absf(steer) < 1.0 and absf(steer) > 0.0
	if analog:
		veh.steer_input = steer
	else:
		veh.steer_input = move_toward(veh.steer_input, steer, dt * (2.2 if steer != 0.0 else 3.0))
	if brk > 0.0 and veh.cruise > 0:
		cruise_off()
	veh.throttle = thr
	veh.brake = brk
	# 小柯自駕／車道維持
	if ap.mode != "off":
		var o := ap.drive(dt)
		var manual_steer := absf(steer) > 0.0
		if not manual_steer:
			veh.steer_input = o.steer
		if ap.mode == "full":
			if brk <= 0.0:
				veh.throttle = o.throttle
				veh.brake = o.brake
			veh.blinker = o.blinker if veh.blinker != 2 else 2
		elif ap.mode == "lka" and veh.cruise < 0 and thr == 0.0 and brk == 0.0 and str(App.settings.control) == "eye":
			# 眼控模式：沒踩油門時，小柯幫忙維持速度（遇紅燈、前車會自動煞車）
			veh.throttle = 0.0
			veh.brake = maxf(o.brake, 0.15 if veh.kmh() > ap.target_kmh + 3 else 0.0)
		if ap.mode == "lka" and o.brake > 0.3 and thr == 0.0:
			veh.brake = maxf(veh.brake, o.brake)


# ---------------------------------------------------------------- 每格
func _physics_process(dt: float) -> void:
	if paused or done or veh == null:
		return
	elapsed += dt
	_read_inputs(dt)
	if wind != 0.0:
		veh.yaw += wind * dt / maxf(veh.kmh(), 15.0) * 0.6
	veh.physics(dt)
	traffic.step(dt)
	nav.update(veh.pos2(), veh.fwd2(), dt, absf(veh.speed))
	_rules(dt)
	_signs_scan(dt)
	_events(dt)
	_goal(dt)
	if veh.blinker == -1 or veh.blinker == 1:
		_last_blink[veh.blinker] = elapsed
	# 方向盤回正後自動關方向燈
	if veh.blinker in [-1, 1] and _in_node < 0 and absf(veh.steer) < 0.03 and elapsed - _entry_t_exit < 1.5 and _entry_t_exit > 0:
		veh.blinker = 0
		_entry_t_exit = -1.0


var _entry_t_exit := -1.0


func _process(dt: float) -> void:
	if veh == null:
		return
	_camera(dt)
	cabin.update_cabin(dt, world)
	cabin.visible = view == "cabin"
	_sounds()


func _camera(dt: float) -> void:
	# 視線轉頭：看畫面左右邊緣就轉頭（像轉頭看後照鏡）
	var vs := get_viewport().get_visible_rect().size
	var use_gaze := str(App.settings.look) == "gaze" and Gaze.valid and (Gaze.source == "eyemouse" or str(App.settings.control) == "eye" or Gaze.bot_point != null) and view == "cabin"
	var ty := look_yaw
	var tp := look_pitch
	if use_gaze and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var nx := Gaze.point.x / vs.x * 2.0 - 1.0
		var ny := Gaze.point.y / vs.y * 2.0 - 1.0
		var gain := float(App.settings.look_gain)
		var yaw_t := 0.0
		if absf(nx) > 0.55 and not hud.gaze_on_ui():
			yaw_t = -signf(nx) * pow((absf(nx) - 0.55) / 0.45, 1.2) * deg_to_rad(80.0) * gain
		var pitch_t := 0.0
		if ny > 0.35 and ny < 0.62 and absf(nx) < 0.5 and not hud.gaze_on_ui():
			pitch_t = -deg_to_rad(14.0) * (ny - 0.35) / 0.27
		_look_target = _look_target.lerp(Vector2(yaw_t, pitch_t), clampf(dt * 3.5, 0, 1))
		ty = _look_target.x
		tp = _look_target.y
	elif not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		look_yaw = move_toward(look_yaw, 0.0, dt * 1.2)
		look_pitch = move_toward(look_pitch, 0.0, dt * 0.8)
		ty = look_yaw
		tp = look_pitch
	cam.cull_mask = 0xFFFFF & ~2 if view == "cabin" else 0xFFFFF
	if view == "cabin":
		head.position = veh.spec.eye + Vector3(-0.08 * sin(ty), 0, 0.05 * absf(sin(ty)))
		head.rotation = Vector3(tp - 0.12, ty, 0)
		cam.position = Vector3.ZERO
		cam.rotation = Vector3.ZERO
		cam.fov = 74.0
	else:
		var back := 14.0 if veh.kind == "truck" else 8.0
		var up := 8.5 if veh.kind == "truck" else 3.6
		var target := veh.global_position
		if veh.has_trailer:
			var ta := veh.trailer_axle_2d()
			target = (veh.global_position + Vector3(ta.x, 0, ta.y)) * 0.5
		var f := veh.fwd2()
		var desired: Vector3
		if view == "chase":
			var rot := Vector2(f.x, f.y).rotated(-ty)
			desired = target - Vector3(rot.x, 0, rot.y) * (back + (8.0 if veh.has_trailer else 0.0)) + Vector3(0, up, 0)
		else:
			desired = target + Vector3(0.01, 55.0 if veh.has_trailer else 30.0, 0)
		head.global_position = head.global_position.lerp(desired, clampf(dt * 4.0, 0, 1)) if head.global_position.distance_to(desired) < 60 else desired
		head.look_at(target + Vector3(0, 1.0, 0), Vector3.UP if view == "chase" else Vector3(f.x, 0, f.y))
		cam.position = Vector3.ZERO
		cam.rotation = Vector3.ZERO


func _sounds() -> void:
	if paused or done:
		Snd.stop_loops()
		return
	var eng := "engine_truck" if veh.kind == "truck" else "engine_car"
	if veh.engine_on:
		var base := 650.0 if veh.kind == "truck" else 800.0
		Snd.set_loop(eng, 0.35 + veh.throttle * 0.35, veh.rpm / base * (0.8 if veh.kind == "truck" else 0.7))
	else:
		Snd.set_loop(eng, 0.0)
	Snd.set_loop("road", clampf(veh.kmh() / 90.0, 0.0, 1.0) * 0.45, 0.8 + veh.kmh() / 200.0)
	Snd.set_loop("rain", (0.7 if world.weather == "storm" else 0.45) if world.wet > 0 else 0.0)
	Snd.set_loop("wind", 0.5 if world.weather in ["storm"] else (clampf(veh.kmh() / 120.0, 0, 1) * 0.15))
	Snd.set_loop("city", 0.25 if world.map.biome == "city" else 0.0)


# ---------------------------------------------------------------- 規則
func violate(kind: String, text: String, pts: int, cool := 12.0, voice := "") -> void:
	if done:
		return
	if _cool.get(kind, -999.0) > elapsed - cool:
		return
	_cool[kind] = elapsed
	score = maxi(0, score - pts)
	violations.append({"kind": kind, "text": text, "pts": pts, "t": elapsed})
	say_msg("%s　−%d" % [text, pts], "bad")
	Snd.play("warn", 0.7)
	if voice != "":
		Snd.say(voice, true)


func _on_crash(kmh: float, what: String) -> void:
	Snd.play("crash" if kmh > 12 else "bump", clampf(kmh / 40.0, 0.4, 1.0))
	if kmh > 30:
		violate("crash_big", "嚴重碰撞%s" % what, 20, 3.0, "v_crash")
	else:
		violate("crash", "擦撞%s" % what, 10, 3.0, "v_crash")


func _rules(dt: float) -> void:
	var net := world.net
	var front := veh.front_center()
	var q := net.query(veh.pos2())
	cur_edge = q.edge
	if q.edge >= 0:
		var d: Dictionary = net.edges[q.edge]
		road_name = d.name
		limit_now = d.limit
		if veh.kind == "truck" and d.kind == "highway":
			limit_now = mini(limit_now, 90)
	var kmh := veh.kmh()
	# 安全帶
	if kmh > 5 and not veh.seatbelt and not _belt_warned:
		_belt_warned = true
		violate("belt", "沒有繫安全帶", 10, 999.0, "v_belt")
	# 超速
	if limit_now > 0 and kmh > limit_now + 5:
		_speed_t += dt
		if _speed_t > 3.0:
			violate("speed", "超速（速限 %d）" % limit_now, 5, 15.0, "v_speed")
			_speed_t = 0.0
	else:
		_speed_t = maxf(0.0, _speed_t - dt)
	# 夜間或隧道沒開燈
	var dark: bool = world.is_night() or world.weather in ["fog", "cold"] or (q.edge >= 0 and net.edges[q.edge].tunnel)
	if dark and not veh.lights_on and kmh > 5:
		_dark_t += dt
		if _dark_t > 8.0:
			violate("lights", "沒有開大燈", 5, 60.0, "v_lights")
			_dark_t = 0.0
	else:
		_dark_t = 0.0
	# 逆向
	if q.edge >= 0 and q.node < 0 and kmh > 5:
		var d2: Dictionary = net.edges[q.edge]
		var along: float = d2.dir.dot(veh.fwd2())
		var wrong := false
		if d2.oneway:
			wrong = along < -0.5
		elif d2.kind != "yard":
			var m: float = d2.median * 0.5
			wrong = (along > 0.5 and q.lat < -m - 0.4) or (along < -0.5 and q.lat > m + 0.4)
		_wrong_t = _wrong_t + dt if wrong else maxf(0.0, _wrong_t - dt * 2.0)
		if _wrong_t > 2.5:
			violate("wrong", "逆向行駛", 10, 15.0, "v_wrong")
			_wrong_t = 0.0
	# 開出路面
	if not q.on_road and kmh > 3 and not _in_parking():
		_off_t += dt
		if _off_t > 2.0:
			violate("offroad", "開出道路", 5, 12.0, "v_offroad")
			_off_t = 0.0
	else:
		_off_t = 0.0
	# 路口：闖紅燈、停字、方向燈
	var fq := net.query(front)
	var node := -1
	for n in [net.edges[fq.edge].a, net.edges[fq.edge].b] if fq.edge >= 0 else []:
		if net.is_junction(n) and front.distance_to(net.nodes[n]) < net.node_r[n]:
			node = n
	if _in_node < 0:
		if q.edge >= 0:
			_min_speed_before = minf(_min_speed_before, kmh) if _near_stop_line(q.edge) else 99.0
	if node >= 0 and _in_node < 0:
		_in_node = node
		_entry_edge = q.edge
		_entry_yaw = veh.yaw
		var st := world.light_state(node, q.edge)
		if st == "R" and veh.speed > 0.5:
			violate("red", "闖紅燈", 15, 8.0, "v_red")
		for sp in world.map.stops:
			if sp.node == node and sp.edge == q.edge and _min_speed_before > 3.0:
				violate("stop", "看到停字沒有停車", 10, 8.0, "v_stop")
	elif node < 0 and _in_node >= 0:
		var turn := rad_to_deg(wrapf(veh.yaw - _entry_yaw, -PI, PI))
		if absf(turn) > 45.0 and veh.speed > 0:
			var side := -1 if turn > 0 else 1        # yaw 增加 = 左轉
			if elapsed - float(_last_blink[side]) > 5.0:
				violate("blink", "轉彎沒有打方向燈", 3 if not lesson.get("need_blinker", false) else 8, 4.0, "v_blink")
			_entry_t_exit = elapsed
		_in_node = -1
		_min_speed_before = 99.0
	_tip_t += dt


func _near_stop_line(e: int) -> bool:
	for sp in world.map.stops:
		if sp.edge == e and veh.pos2().distance_to(world.net.nodes[sp.node]) < world.net.node_r[sp.node] + 30.0:
			return true
	return false


func _in_parking() -> bool:
	for pk in world.map.parking:
		if veh.pos2().distance_to(pk.pos) < 40.0:
			return true
	for lm in world.map.landmarks:
		if lm.type in ["service_area", "warehouse", "container_yard"] and veh.pos2().distance_to(lm.pos) < 70.0:
			return true
	return false


# ---------------------------------------------------------------- 小柯標誌識別
func _signs_scan(dt: float) -> void:
	_sign_t = maxf(0.0, _sign_t - dt)
	if not bool(App.settings.assist_signs):
		return
	var p := veh.pos2()
	var f := veh.fwd2()
	for s in world.signs:
		if recognized.has(s.id):
			continue
		var sp := Vector2(s.pos.x, s.pos.z)
		var rel := sp - p
		var dist := rel.length()
		if dist > 75.0 or dist < 6.0:
			continue
		if f.dot(rel / dist) < 0.82 or (s.dir as Vector2).dot(f) < 0.6:
			continue
		recognized[s.id] = true
		recog_count += 1
		last_sign = {"type": s.type, "value": s.value, "t": elapsed}
		if s.type == "speed":
			limit_sign = s.value
			Snd.say("sign_speed_%d" % s.value)
		else:
			Snd.say("sign_" + s.type)
		hud.show_sign(s.type, s.value)
		break


# ---------------------------------------------------------------- 事件
func _events(dt: float) -> void:
	if "wind" in lesson.get("events", []):
		_wind_t += dt
		wind = sin(_wind_t * 0.7) * sin(_wind_t * 0.23) * 0.9
		if absf(wind) > 0.75 and not _events_done.has("wind_say"):
			_events_done["wind_say"] = true
			Snd.say("ev_wind")
	if "ambulance" in lesson.get("events", []):
		if elapsed > 12.0 and not _events_done.has("amb"):
			_events_done["amb"] = true
			traffic.make_ambulance()
			Snd.say("ev_ambulance", true)
			say_msg("後方救護車！請減速靠右讓道", "warn")
		var a = traffic.siren_car
		if a != null:
			var rel: Vector2 = veh.pos2() - a.pos
			var ahead: float = rel.dot(a.dir)
			if ahead > 0 and ahead < 25.0 and a.speed < 5.0 and veh.kmh() > 8:
				_amb_blocked += dt
				if _amb_blocked > 6.0:
					violate("amb", "沒有讓救護車", 10, 20.0, "v_ambulance")
					_amb_blocked = 0.0
			else:
				_amb_blocked = maxf(0.0, _amb_blocked - dt)
	if "accident" in lesson.get("events", []) and not _events_done.has("acc_warn"):
		for ob in traffic.obstacles:
			if veh.pos2().distance_to(ob.c) < 250.0:
				_events_done["acc_warn"] = true
				Snd.say("ev_accident", true)
				say_msg("前方事故！減速、打方向燈換車道", "warn")
				break


# ---------------------------------------------------------------- 目標
func _goal(dt: float) -> void:
	var tl := float(lesson.get("time_limit", 0))
	if tl > 0 and elapsed > tl and not done:
		_finish(false, "超過時間了")
		return
	match lesson.get("goal", ""):
		"stop_zone":
			var d := veh.front_center().distance_to(_stop_zone)
			if d < 4.0 and veh.kmh() < 0.5:
				_park_ok_t += dt
				if _park_ok_t > 1.0:
					_finish(true, "停得很好！")
			else:
				_park_ok_t = 0.0
		"park":
			var pk: Dictionary = world.map.parking[int(lesson.park)]
			var center := veh.pos2().lerp(veh.front_center(), 0.5)
			if veh.has_trailer:
				center = (veh.pos2() + veh.trailer_axle_2d()) * 0.5
			var inside := _footprint_in(pk)
			if inside and veh.kmh() < 0.5:
				_park_ok_t += dt
				if _park_ok_t > 1.0 and (veh.handbrake or veh.gear == "P" or _park_ok_t > 3.0):
					_finish(true, "停進車格了！")
			else:
				_park_ok_t = 0.0
			var _c := center


## 車身四角（含拖車）都在車格內（車格會放寬一點）
func _footprint_in(pk: Dictionary) -> bool:
	var sz: Vector2 = pk.size
	var hx := sz.x * 0.5 + 0.35
	var hz := sz.y * 0.5 + 0.6
	var pts := []
	var hw := float(veh.spec.width) * 0.5
	pts.append(veh.local_to_2d(-hw, float(veh.spec.front)))
	pts.append(veh.local_to_2d(hw, float(veh.spec.front)))
	if veh.has_trailer:
		var tf := Vector2(-sin(veh.trailer_yaw), -cos(veh.trailer_yaw))
		var tr := Vector2(-tf.y, tf.x)
		var rear := veh.kingpin_2d() - tf * (Vehicle.TRAILER_LEN - Vehicle.KINGPIN)
		pts.append(rear - tr * hw)
		pts.append(rear + tr * hw)
	else:
		pts.append(veh.local_to_2d(-hw, float(veh.spec.rear)))
		pts.append(veh.local_to_2d(hw, float(veh.spec.rear)))
	for p in pts:
		var lp: Vector2 = (p - (pk.pos as Vector2)).rotated(float(pk.yaw))
		if absf(lp.x) > hx or absf(lp.y) > hz:
			return false
	return true


func _on_arrived() -> void:
	world.show_dest(null)
	if lesson.get("goal", "") == "reach":
		if lesson.get("need_signs", 0) > recog_count:
			say_msg("抵達了，但只辨識了 %d 個標誌" % recog_count, "warn")
		_finish(true, "抵達 %s" % nav.dest_name)
	else:
		say_msg("抵達 %s！可以在平板選下一個目的地" % nav.dest_name, "ok")
		Snd.play("success", 0.7)


func _finish(ok: bool, why: String) -> void:
	if done:
		return
	if lesson.get("need_signs", 0) > recog_count:
		ok = false
		why += "（標誌辨識不足 %d 個）" % int(lesson.need_signs)
	done = true
	ap.mode = "off"
	veh.throttle = 0.0
	veh.brake = 1.0
	var stars := Lessons.stars_for(score) if ok else 0
	if lesson.has("id"):
		App.record(str(lesson.id), stars, score if ok else 0)
	Snd.play("success" if ok and stars > 0 else "fail")
	Snd.say("res_%d" % stars if ok else "res_fail", true)
	var res := {"ok": ok, "why": why, "score": score, "stars": stars, "violations": violations, "time": elapsed,
		"title": lesson.get("title", "自由駕駛"), "signs": recog_count}
	Snd.stop_loops()
	hud.show_result(res)
	finished.emit(res)


func say_msg(text: String, kind := "info") -> void:
	message.emit(text, kind)


func quit_drive() -> void:
	Snd.stop_loops()
	Snd.stop_speaking()
	paused = true
