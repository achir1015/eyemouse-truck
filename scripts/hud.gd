extends CanvasLayer
## 駕駛畫面上層：小柯訊息、分數、標誌識別卡、小地圖、眼控操作列、暫停與成績。

signal menu_requested
signal retry_requested
signal tutorial_requested

var d: Node                       # drive.gd
var root: Control
var msg_box: Control
var msg_label: Label
var msg_t := 0.0
var info_label: Label
var score_label: Label
var sign_card: Control
var sign_t := 0.0
var _sign := {"type": "", "value": 0}
var mini: Control
var bar: Control
var buttons := {}                 # 名稱 -> GazeButton
var pause_panel: Control
var result_panel: Control
var speed_label: Label
var robot: Control
var font: Font
var _talk := 0.0


func setup(drive: Node) -> void:
	d = drive
	font = load("res://assets/fonts/ui_font.tres")
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	d.message.connect(_on_msg)
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _label(sz: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel(col := Color(0.04, 0.07, 0.12, 0.78)) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(14)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _build() -> void:
	# 小柯訊息
	msg_box = _panel()
	root.add_child(msg_box)
	robot = Control.new()
	robot.size = Vector2(64, 64)
	robot.position = Vector2(10, 10)
	robot.draw.connect(_draw_robot)
	robot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msg_box.add_child(robot)
	msg_label = _label(22)
	msg_label.position = Vector2(84, 8)
	msg_label.size = Vector2(440, 70)
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	msg_label.text = "小柯：準備好就出發吧！"
	msg_box.add_child(msg_label)
	# 右上：分數與課程
	score_label = _label(30, Color(1, 0.95, 0.6))
	root.add_child(score_label)
	info_label = _label(18, Color(0.85, 0.92, 1))
	root.add_child(info_label)
	# 標誌識別卡
	sign_card = Control.new()
	sign_card.size = Vector2(250, 190)
	sign_card.draw.connect(_draw_sign_card)
	sign_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sign_card.visible = false
	root.add_child(sign_card)
	# 小地圖
	mini = load("res://scripts/dash.gd").new()
	mini.mode = "mini"
	mini.veh = d.veh
	mini.drive = d
	mini.zoom = 1.3
	mini.size = Vector2(220, 220)
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini.clip_contents = true
	root.add_child(mini)
	speed_label = _label(40)
	root.add_child(speed_label)
	# 操作列
	bar = Control.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	var eye := str(App.settings.control) == "eye"
	var specs := [
		["ap", "小柯自駕", Color(0.1, 0.55, 0.45), func(): d.toggle_ap("full")],
		["lka", "車道維持", Color(0.12, 0.45, 0.6), func(): d.toggle_ap("lka")],
		["bl", "◀ 方向燈", Color(0.55, 0.42, 0.1), func(): d.toggle_blinker(-1)],
		["br", "方向燈 ▶", Color(0.55, 0.42, 0.1), func(): d.toggle_blinker(1)],
		["horn", "喇叭", Color(0.45, 0.3, 0.6), func(): Snd.play("horn_truck" if d.veh.kind == "truck" else "horn_car", 0.8)],
		["gear", "檔位 D/R", Color(0.3, 0.35, 0.45), func(): d.shift_toggle()],
		["light", "大燈", Color(0.3, 0.35, 0.45), func(): d.veh.lights_on = not d.veh.lights_on],
		["wiper", "雨刷", Color(0.3, 0.35, 0.45), func(): d.veh.wipers = (d.veh.wipers + 1) % 3],
		["view", "視角", Color(0.3, 0.35, 0.45), func(): d.cycle_view()],
		["music", "下一首", Color(0.35, 0.3, 0.5), func(): Snd.next_track()],
		["pause", "暫停", Color(0.55, 0.2, 0.2), func(): toggle_pause()],
	]
	for s in specs:
		var b := GazeButton.new(s[1], s[2])
		b.font_size = 18
		b.picked.connect(s[3])
		bar.add_child(b)
		buttons[s[0]] = b
	if eye:
		for s in [["left", "◀ 左", Color(0.2, 0.4, 0.75)], ["brake", "煞車", Color(0.75, 0.2, 0.2)],
				["gas", "油門", Color(0.15, 0.6, 0.3)], ["right", "右 ▶", Color(0.2, 0.4, 0.75)]]:
			var hb := GazeButton.new(s[1], s[2])
			hb.hold = true
			hb.font_size = 30
			bar.add_child(hb)
			buttons[s[0]] = hb


func _layout() -> void:
	var vs := root.get_viewport_rect().size
	msg_box.position = Vector2(14, 14)
	msg_box.size = Vector2(540, 86)
	score_label.position = Vector2(vs.x - 250, 14)
	score_label.size = Vector2(236, 40)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_label.position = Vector2(vs.x - 420, 56)
	info_label.size = Vector2(406, 60)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sign_card.position = Vector2(vs.x * 0.5 - 125, 14)
	mini.position = Vector2(vs.x - 234, 120)
	speed_label.position = Vector2(20, vs.y - 230)
	speed_label.size = Vector2(300, 50)
	var eye := str(App.settings.control) == "eye"
	var names := ["ap", "lka", "bl", "br", "horn", "gear", "light", "wiper", "view", "music", "pause"]
	if eye:
		# 下方大按鈕（持續看著就作用），兩側一排功能鍵
		var bw := minf(220.0, (vs.x - 300) / 4.0)
		var bh := 110.0
		var x0 := (vs.x - bw * 4 - 30) * 0.5
		var i := 0
		for n in ["left", "brake", "gas", "right"]:
			var b: GazeButton = buttons[n]
			b.position = Vector2(x0 + i * (bw + 10), vs.y - bh - 10)
			b.size = Vector2(bw, bh)
			i += 1
		var sw := 120.0
		var sh := minf(64.0, (vs.y - 130) / 6.0)
		for k in names.size():
			var b2: GazeButton = buttons[names[k]]
			var left := k < 6
			var row := k if left else k - 6
			b2.position = Vector2(10 if left else vs.x - sw - 10, vs.y - 130 - (6 - row) * (sh + 6) + 6 if left else 350 + row * (sh + 6))
			b2.size = Vector2(sw, sh)
		mini.position = Vector2(vs.x - 234, 120)
		mini.size = Vector2(220, 220)
	else:
		var bw2 := minf(108.0, (vs.x - 40) / names.size() - 6)
		for k in names.size():
			var b3: GazeButton = buttons[names[k]]
			b3.position = Vector2(14 + k * (bw2 + 6), vs.y - 62)
			b3.size = Vector2(bw2, 54)
	if pause_panel:
		pause_panel.size = vs
	if result_panel:
		result_panel.size = vs


func held() -> Dictionary:
	var out := {}
	for n in ["left", "right", "gas", "brake"]:
		if buttons.has(n):
			out[n] = (buttons[n] as GazeButton).active
	return out


## 視線是否落在操作按鈕上（就不要轉頭）
func gaze_on_ui() -> bool:
	if not Gaze.valid:
		return false
	for n in buttons:
		var b: GazeButton = buttons[n]
		if b.is_visible_in_tree() and b.get_global_rect().grow(20).has_point(Gaze.point):
			return true
	return mini.get_global_rect().has_point(Gaze.point)


func target_rect(name: String) -> Rect2:
	if buttons.has(name):
		return (buttons[name] as Control).get_global_rect()
	match name:
		"msg": return msg_box.get_global_rect()
		"score": return Rect2(score_label.position, Vector2(score_label.size.x, 100))
		"mini": return mini.get_global_rect()
		"sign": return sign_card.get_global_rect()
		"bar":
			var r := Rect2()
			var first := true
			for n in buttons:
				var gr: Rect2 = (buttons[n] as Control).get_global_rect()
				r = gr if first else r.merge(gr)
				first = false
			return r
	# 駕駛室裡的位置（投影到畫面）
	if d.cabin.spots.has(name) and d.view == "cabin":
		var lp: Vector3 = d.cabin.spots[name]
		var gp: Vector3 = d.veh.body.global_transform * lp
		if not d.cam.is_position_behind(gp):
			var sp: Vector2 = d.cam.unproject_position(gp)
			return Rect2(sp - Vector2(110, 70), Vector2(220, 140))
	return Rect2()


func _on_msg(text: String, kind: String) -> void:
	msg_label.text = text
	msg_t = 6.0
	_talk = 1.5
	var col: Color = {"bad": Color(1, 0.55, 0.5), "warn": Color(1, 0.85, 0.4), "ok": Color(0.6, 1, 0.7)}.get(kind, Color.WHITE)
	msg_label.add_theme_color_override("font_color", col)


func show_sign(type: String, value: int) -> void:
	_sign = {"type": type, "value": value}
	sign_t = 4.0
	sign_card.visible = true
	sign_card.queue_redraw()
	_on_msg("小柯看到：" + SignArt.name_of(type, value), "ok")


func _draw_sign_card() -> void:
	sign_card.draw_rect(Rect2(Vector2.ZERO, sign_card.size), Color(0.04, 0.07, 0.12, 0.85))
	sign_card.draw_rect(Rect2(Vector2.ZERO, sign_card.size), Color(0.3, 0.8, 1, 0.8), false, 3)
	SignArt.draw(sign_card, _sign.type, _sign.value, Rect2(75, 10, 100, 100), font)
	var n := SignArt.name_of(_sign.type, _sign.value)
	var w := font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	sign_card.draw_string(font, Vector2((250 - w) * 0.5, 145), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
	var k := "小柯辨識　" + SignArt.kind_of(_sign.type) + "標誌"
	var w2 := font.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	sign_card.draw_string(font, Vector2((250 - w2) * 0.5, 175), k, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.9, 1))


func _draw_robot() -> void:
	# 小柯：圓頭機器人（原創）
	var c := Vector2(32, 34)
	robot.draw_circle(c, 28, Color(0.85, 0.92, 1))
	robot.draw_circle(c, 24, Color(0.15, 0.4, 0.75))
	robot.draw_rect(Rect2(c + Vector2(-18, -10), Vector2(36, 20)), Color(0.05, 0.08, 0.15))
	var blink := fmod(Time.get_ticks_msec() / 1000.0, 4.0) < 0.15
	for x in [-8.0, 8.0]:
		if blink:
			robot.draw_line(c + Vector2(x - 4, 0), c + Vector2(x + 4, 0), Color(0.4, 1, 0.9), 2)
		else:
			robot.draw_circle(c + Vector2(x, 0), 4, Color(0.4, 1, 0.9))
	var mouth := 2.0 + (absf(sin(Time.get_ticks_msec() / 90.0)) * 4.0 if _talk > 0 or Snd.is_speaking() else 0.0)
	robot.draw_rect(Rect2(c + Vector2(-6, 14), Vector2(12, mouth)), Color(0.9, 0.95, 1))
	robot.draw_line(c + Vector2(0, -28), c + Vector2(0, -34), Color(0.85, 0.92, 1), 3)
	robot.draw_circle(c + Vector2(0, -35), 3.5, Color(1, 0.5, 0.3))


func _process(dt: float) -> void:
	if d == null or d.veh == null:
		return
	_talk = maxf(0.0, _talk - dt)
	robot.queue_redraw()
	msg_t -= dt
	msg_box.modulate.a = 1.0 if msg_t > 0 or Snd.is_speaking() else 0.55
	sign_t -= dt
	if sign_t <= 0 and sign_card.visible:
		sign_card.visible = false
	score_label.text = "★ %d 分" % d.score
	var info := ""
	if d.lesson.has("title"):
		info = str(d.lesson.title)
		if d.lesson.has("time_limit"):
			info += "　剩 %d 秒" % maxi(0, int(float(d.lesson.time_limit) - d.elapsed))
	else:
		info = "自由駕駛　" + str(d.world.map.name)
	var ap_mode: String = d.ap.mode
	if ap_mode != "off":
		info += "\n小柯：" + d.ap.status
	info_label.text = info
	mini.queue_redraw()
	mini.visible = d.view != "cabin" or str(App.settings.control) == "eye" or root.get_viewport_rect().size.x > 1100
	speed_label.visible = d.view != "cabin"
	speed_label.text = "%d km/h  %s" % [int(d.veh.kmh()), d.veh.gear]
	(buttons["ap"] as GazeButton).selected = ap_mode == "full"
	(buttons["lka"] as GazeButton).selected = ap_mode == "lka"
	(buttons["bl"] as GazeButton).selected = d.veh.blinker == -1
	(buttons["br"] as GazeButton).selected = d.veh.blinker == 1
	(buttons["light"] as GazeButton).selected = d.veh.lights_on
	(buttons["wiper"] as GazeButton).selected = d.veh.wipers > 0
	(buttons["gear"] as GazeButton).text = "檔位 " + d.veh.gear
	for n in buttons:
		(buttons[n] as GazeButton).queue_redraw()


# ---------------------------------------------------------------- 暫停
func toggle_pause() -> void:
	if result_panel:
		return
	if pause_panel:
		pause_panel.queue_free()
		pause_panel = null
		d.paused = false
		Snd.music.stream_paused = Snd.music_paused
		return
	d.paused = true
	Snd.stop_loops()
	pause_panel = _panel(Color(0, 0, 0, 0.6))
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_panel.size = root.get_viewport_rect().size
	root.add_child(pause_panel)
	var vs := pause_panel.size
	var t := _label(40)
	t.text = "暫停"
	t.position = Vector2(0, vs.y * 0.12)
	t.size = Vector2(vs.x, 60)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_panel.add_child(t)
	var items := [
		["繼續駕駛", Color(0.15, 0.55, 0.35), func(): toggle_pause()],
		["重新開始", Color(0.2, 0.4, 0.7), func(): retry_requested.emit()],
		["語音教學", Color(0.45, 0.35, 0.65), _tut],
		["音量 −", Color(0.3, 0.35, 0.45), func(): _vol(-0.1)],
		["音量 ＋", Color(0.3, 0.35, 0.45), func(): _vol(0.1)],
		["回主選單", Color(0.6, 0.25, 0.2), func(): menu_requested.emit()],
	]
	var bw := 260.0
	var bh := 84.0
	for i in items.size():
		var col := i % 2
		var row := i / 2
		var b := GazeButton.make(pause_panel, items[i][0], Rect2(vs.x * 0.5 - bw - 10 + col * (bw + 20), vs.y * 0.28 + row * (bh + 18), bw, bh), items[i][1], items[i][2])
		b.font_size = 26
	var keys := _label(17, Color(0.8, 0.85, 0.95))
	keys.text = "鍵盤：W/S 油門煞車　A/D 方向　Q/E 方向燈　X 雙黃燈　R 倒車／前進　空白鍵 手煞車　B 安全帶　N 引擎\nL 大燈　K 遠燈　P 雨刷　H 喇叭　T 小柯自駕　Y 車道維持　C 視角　M 下一首　＋/− 定速　按住滑鼠右鍵轉頭"
	keys.position = Vector2(40, vs.y - 110)
	keys.size = Vector2(vs.x - 80, 80)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_panel.add_child(keys)


func _tut() -> void:
	toggle_pause()
	tutorial_requested.emit()


func _vol(dv: float) -> void:
	App.settings.volume = clampf(float(App.settings.volume) + dv, 0.0, 1.0)
	App.save()
	Snd.refresh_music_volume()
	Snd.play("tick")
	_on_msg("音量 %d%%" % int(round(float(App.settings.volume) * 100)), "info")


# ---------------------------------------------------------------- 成績
func show_result(res: Dictionary) -> void:
	if pause_panel:
		pause_panel.queue_free()
		pause_panel = null
	result_panel = _panel(Color(0, 0.02, 0.06, 0.72))
	result_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	result_panel.size = root.get_viewport_rect().size
	root.add_child(result_panel)
	var vs := result_panel.size
	var t := _label(42, Color(1, 0.95, 0.6) if res.ok else Color(1, 0.6, 0.55))
	t.text = "%s　%s" % [res.title, "完成！" if res.ok else "未完成"]
	t.position = Vector2(0, vs.y * 0.08)
	t.size = Vector2(vs.x, 60)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_panel.add_child(t)
	var st := _label(64, Color(1, 0.85, 0.2))
	st.text = "★".repeat(int(res.stars)) + "☆".repeat(3 - int(res.stars))
	st.position = Vector2(0, vs.y * 0.18)
	st.size = Vector2(vs.x, 80)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_panel.add_child(st)
	var body := _label(22)
	var lines := ["%s" % res.why, "分數 %d 分　用時 %d 分 %02d 秒　辨識標誌 %d 個" % [res.score, int(res.time) / 60, int(res.time) % 60, res.signs]]
	if res.violations.is_empty():
		lines.append("沒有任何違規，太棒了！")
	else:
		var cnt := {}
		for v in res.violations:
			cnt[v.text] = cnt.get(v.text, 0) + 1
		var vl := []
		for k in cnt:
			vl.append("%s ×%d" % [k, cnt[k]])
		lines.append("違規：" + "、".join(vl))
	body.text = "\n".join(lines)
	body.position = Vector2(60, vs.y * 0.33)
	body.size = Vector2(vs.x - 120, 160)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	result_panel.add_child(body)
	GazeButton.make(result_panel, "再試一次", Rect2(vs.x * 0.5 - 290, vs.y * 0.66, 270, 96), Color(0.2, 0.45, 0.75), func(): retry_requested.emit()).font_size = 28
	GazeButton.make(result_panel, "回主選單", Rect2(vs.x * 0.5 + 20, vs.y * 0.66, 270, 96), Color(0.15, 0.55, 0.35), func(): menu_requested.emit()).font_size = 28
