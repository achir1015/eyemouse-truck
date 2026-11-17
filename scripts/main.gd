extends Node
## 主程式：選單 → 駕駛。所有選單按鈕都能用眼睛停留選取。

var ui: CanvasLayer
var screen: Control
var drive: Node3D
var font: Font
var cfg := {"map": "taipei", "vehicle": "truck", "time": "day", "weather": "clear", "dest": ""}
var last_cfg := {}
var bg: Control
var status_label: Label
var _quiz := {}
var tut: Control


func _ready() -> void:
	font = load("res://assets/fonts/ui_font.tres")
	RenderingServer.set_default_clear_color(Color(0.07, 0.11, 0.2))
	cfg.vehicle = App.settings.vehicle
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	get_viewport().size_changed.connect(func(): if screen and screen.has_meta("rebuild"): (screen.get_meta("rebuild") as Callable).call())
	if bool(App.settings.fullscreen):
		App.set_fullscreen(true)
	if App.test_mode:
		_run_test()
		return
	show_title()
	if not bool(App.settings.tutorial_done):
		await get_tree().create_timer(0.8).timeout
		_menu_tutorial()
	else:
		Snd.say("title_hello")
	Updater.checked.connect(_on_update_checked)
	Updater.check()


# ---------------------------------------------------------------- 共用
func _clear() -> Control:
	if screen:
		screen.queue_free()
	if tut:
		tut.queue_free()
		tut = null
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := App.safe_margins(get_viewport().get_visible_rect().size)
	screen.offset_left = m.x
	screen.offset_top = m.y
	screen.offset_right = -m.z
	screen.offset_bottom = -m.w
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(screen)
	bg = Control.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = -m.x
	bg.offset_top = -m.y
	bg.offset_right = m.z
	bg.offset_bottom = m.w
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.draw.connect(_draw_bg)
	screen.add_child(bg)
	return screen


func _vs() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var m := App.safe_margins(vp)
	return vp - Vector2(m.x + m.z, m.y + m.w)


func _draw_bg() -> void:
	var vs := bg.size
	for k in 24:
		var t := k / 23.0
		bg.draw_rect(Rect2(0, vs.y * t, vs.x, vs.y / 23.0 + 1), Color(0.05, 0.09, 0.18).lerp(Color(0.12, 0.28, 0.42), t))
	# 遠山與道路剪影
	var pts := PackedVector2Array([Vector2(0, vs.y)])
	for k in 13:
		pts.append(Vector2(vs.x * k / 12.0, vs.y * (0.72 - 0.08 * sin(k * 1.3) - 0.05 * sin(k * 2.7))))
	pts.append(Vector2(vs.x, vs.y))
	bg.draw_colored_polygon(pts, Color(0.06, 0.16, 0.2))
	bg.draw_colored_polygon(PackedVector2Array([Vector2(vs.x * 0.47, vs.y * 0.74), Vector2(vs.x * 0.53, vs.y * 0.74), Vector2(vs.x * 0.75, vs.y), Vector2(vs.x * 0.25, vs.y)]), Color(0.16, 0.17, 0.2))
	for k in 6:
		var y0 := vs.y * (0.76 + k * 0.045)
		bg.draw_rect(Rect2(vs.x * 0.5 - 2 - k, y0, 4 + k * 2, vs.y * 0.02), Color(0.95, 0.8, 0.2, 0.8))


func _title(text: String, sub := "") -> void:
	var vs := _vs()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 8)
	l.position = Vector2(0, 18)
	l.size = Vector2(vs.x, 56)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen.add_child(l)
	if sub != "":
		var s := Label.new()
		s.text = sub
		s.add_theme_font_size_override("font_size", 20)
		s.add_theme_color_override("font_color", Color(0.8, 0.9, 1))
		s.position = Vector2(20, 74)
		s.size = Vector2(vs.x - 40, 30)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		screen.add_child(s)


func _btn(text: String, r: Rect2, col: Color, cb: Callable, sub := "", fs := 24) -> GazeButton:
	var b := GazeButton.make(screen, text, r, col, cb)
	b.sub = sub
	b.font_size = fs
	return b


## 依格狀排列按鈕
func _grid(items: Array, top: float, cols: int, h: float, w_max := 300.0, gap := 14.0) -> Array:
	var vs := _vs()
	var w := minf(w_max, (vs.x - 60 - gap * (cols - 1)) / cols)
	var total_w := w * cols + gap * (cols - 1)
	var x0 := (vs.x - total_w) * 0.5
	var out := []
	for i in items.size():
		var it: Array = items[i]
		var r := Rect2(x0 + (i % cols) * (w + gap), top + (i / cols) * (h + gap), w, h)
		out.append(_btn(it[0], r, it[1], it[2], it[3] if it.size() > 3 else "", it[4] if it.size() > 4 else 24))
	return out


func _back(cb := Callable(self, "show_title")) -> void:
	_btn("◀ 返回", Rect2(16, 16, 150, 64), Color(0.35, 0.38, 0.45), cb)


# ---------------------------------------------------------------- 標題
func show_title() -> void:
	_stop_drive()
	_clear()
	screen.set_meta("rebuild", Callable(self, "show_title"))
	var vs := _vs()
	var icon := TextureRect.new()
	icon.texture = load("res://icon.svg")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(vs.x * 0.5 - 300, 18)
	icon.size = Vector2(96, 96)
	screen.add_child(icon)
	var l := Label.new()
	l.text = App.APP_NAME
	l.add_theme_font_size_override("font_size", 46)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 10)
	l.position = Vector2(vs.x * 0.5 - 190, 22)
	l.size = Vector2(560, 60)
	screen.add_child(l)
	var s := Label.new()
	s.text = "用眼睛開卡車環遊台灣　v" + App.APP_VERSION
	s.add_theme_font_size_override("font_size", 20)
	s.add_theme_color_override("font_color", Color(0.75, 0.88, 1))
	s.position = Vector2(vs.x * 0.5 - 188, 80)
	s.size = Vector2(560, 30)
	screen.add_child(s)
	var items := [
		["自由駕駛", Color(0.15, 0.5, 0.8), show_free, "台灣景點、市區任你開"],
		["駕訓班", Color(0.15, 0.55, 0.35), show_lessons, "起步、轉彎、倒車入庫"],
		["考驗挑戰", Color(0.7, 0.35, 0.15), show_challenges, "雨天、夜晚、事故、塞車"],
		["交通標誌", Color(0.6, 0.45, 0.1), show_signs, "認識標誌與小測驗"],
		["語音教學", Color(0.45, 0.3, 0.65), _menu_tutorial, "小柯一步一步教你"],
		["設定", Color(0.3, 0.35, 0.45), show_settings, "眼控、音量、畫質"],
		["檢查更新", Color(0.25, 0.4, 0.5), show_update, ""],
		["關於", Color(0.3, 0.3, 0.38), show_about, ""],
		["離開", Color(0.55, 0.22, 0.22), _quit, ""],
	]
	if OS.has_feature("web"):
		items.pop_back()   # 瀏覽器裡不能關閉程式
	var btns := _grid(items, 140, 3, 108, 330)
	for b in btns:
		b.set_meta("menu", b.text)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 17)
	status_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	status_label.position = Vector2(20, vs.y - 34)
	status_label.size = Vector2(vs.x - 40, 26)
	status_label.text = Gaze.status_text() + "　｜　" + App.CREDIT
	screen.add_child(status_label)
	if Updater.has_update:
		_btn("有新版 %s，按這裡更新" % Updater.latest, Rect2(vs.x - 380, vs.y - 100, 360, 56), Color(0.8, 0.45, 0.1), show_update)


func _quit() -> void:
	App.save()
	Gaze.shutdown()
	get_tree().quit()


func _menu_btn(name: String) -> Rect2:
	if screen == null:
		return Rect2()
	for c in screen.get_children():
		if c is GazeButton and c.text == name:
			return c.get_global_rect()
	return Rect2()


# ---------------------------------------------------------------- 自由駕駛設定
func show_free() -> void:
	_clear()
	screen.set_meta("rebuild", Callable(self, "show_free"))
	_title("自由駕駛", "選地圖、車子、時間與天氣，再選目的地（也可以不選）")
	_back()
	var vs := _vs()
	var y := 112.0
	var maps := []
	for m in Maps.LIST:
		maps.append([m.name, Color(0.15, 0.45, 0.75) if cfg.map != m.id else Color(0.2, 0.65, 0.4), _set_cfg.bind("map", m.id), "", 22])
	var mb := _grid(maps, y, 7, 70, 170, 8)
	for i in mb.size():
		mb[i].selected = Maps.LIST[i].id == cfg.map
	y += 82
	var desc := Label.new()
	desc.text = Maps.info(cfg.map).desc
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", Color(0.85, 0.92, 1))
	desc.position = Vector2(20, y)
	desc.size = Vector2(vs.x - 40, 26)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen.add_child(desc)
	y += 34
	var row := []
	for v in [["truck", "聯結車"], ["car", "豪華房車"]]:
		row.append([v[1], Color(0.35, 0.3, 0.55), _set_cfg.bind("vehicle", v[0]), "", 22])
	for t in [["day", "白天"], ["noon", "正午"], ["dusk", "黃昏"], ["night", "夜晚"]]:
		row.append([t[1], Color(0.45, 0.35, 0.15), _set_cfg.bind("time", t[0]), "", 22])
	var rb := _grid(row, y, 6, 62, 170, 8)
	rb[0].selected = cfg.vehicle == "truck"
	rb[1].selected = cfg.vehicle == "car"
	for i in 4:
		rb[2 + i].selected = cfg.time == ["day", "noon", "dusk", "night"][i]
	y += 72
	var wx := []
	var wlist := [["clear", "晴天"], ["cloudy", "陰天"], ["rain", "下雨"], ["fog", "濃霧"], ["cold", "寒流"], ["storm", "颱風"]]
	for w in wlist:
		wx.append([w[1], Color(0.2, 0.4, 0.55), _set_cfg.bind("weather", w[0]), "", 22])
	var wb := _grid(wx, y, 6, 62, 170, 8)
	for i in wlist.size():
		wb[i].selected = cfg.weather == wlist[i][0]
	y += 74
	var lab := Label.new()
	lab.text = "目的地（小柯導航）："
	lab.add_theme_font_size_override("font_size", 20)
	lab.position = Vector2(20, y)
	lab.size = Vector2(vs.x - 40, 28)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen.add_child(lab)
	y += 32
	var pois := [["不設定", Color(0.3, 0.33, 0.4), _set_cfg.bind("dest", ""), "", 20]]
	for p in _map_pois(cfg.map):
		pois.append([p, Color(0.5, 0.25, 0.4), _set_cfg.bind("dest", p), "", 20])
	var pb := _grid(pois, y, mini(pois.size(), 6), 56, 190, 8)
	for b in pb:
		b.selected = (b.text == cfg.dest) or (b.text == "不設定" and cfg.dest == "")
	_btn("出發！", Rect2(vs.x * 0.5 - 170, vs.y - 104, 340, 88), Color(0.12, 0.6, 0.3), func(): start_drive(cfg.duplicate()), "", 32)


func _map_pois(map_id: String) -> Array:
	var m := Maps.build(map_id)
	var out := []
	for p in m.pois:
		out.append(p.name)
	return out


func _set_cfg(key: String, val: String) -> void:
	cfg[key] = val
	if key == "map":
		cfg.dest = ""
	if key == "vehicle":
		App.settings.vehicle = val
		App.save()
	show_free()


# ---------------------------------------------------------------- 駕訓班、考驗
func show_lessons() -> void:
	_clear()
	screen.set_meta("rebuild", Callable(self, "show_lessons"))
	_title("小柯駕訓班", "從起步練到上高速公路；★ 是你的最好成績")
	_back()
	var items := []
	for l in Lessons.SCHOOL:
		var st := App.stars(l.id)
		items.append([l.title, Color(0.15, 0.5, 0.35), func(): start_drive({"lesson": l.id, "vehicle": cfg.vehicle}), "★".repeat(st) + "☆".repeat(3 - st), 22])
	_grid(items, 116, 5, 96, 230, 10)
	_vehicle_switch()


func show_challenges() -> void:
	_clear()
	screen.set_meta("rebuild", Callable(self, "show_challenges"))
	_title("考驗挑戰", "下雨、夜晚、寒流、夏天、事故、塞車、颱風……你能平安送達嗎？")
	_back()
	var items := []
	for l in Lessons.CHALLENGES:
		var st := App.stars(l.id)
		items.append([l.title, Color(0.65, 0.33, 0.15), func(): start_drive({"lesson": l.id, "vehicle": cfg.vehicle}), Maps.info(l.map).name + "　" + "★".repeat(st) + "☆".repeat(3 - st), 22])
	_grid(items, 116, 5, 96, 230, 10)
	_vehicle_switch()


func _vehicle_switch() -> void:
	var vs := _vs()
	var b1 := _btn("開聯結車", Rect2(vs.x * 0.5 - 260, vs.y - 100, 250, 76), Color(0.35, 0.3, 0.55), func(): _veh("truck"))
	var b2 := _btn("開豪華房車", Rect2(vs.x * 0.5 + 10, vs.y - 100, 250, 76), Color(0.35, 0.3, 0.55), func(): _veh("car"))
	b1.selected = cfg.vehicle == "truck"
	b2.selected = cfg.vehicle == "car"


func _veh(v: String) -> void:
	cfg.vehicle = v
	App.settings.vehicle = v
	App.save()
	var cb: Callable = screen.get_meta("rebuild")
	cb.call()


# ---------------------------------------------------------------- 交通標誌
func show_signs() -> void:
	_clear()
	screen.set_meta("rebuild", Callable(self, "show_signs"))
	_title("交通標誌", "看著標誌停留，小柯會說明；認識之後來做小測驗")
	_back()
	var vs := _vs()
	var types: Array = SignArt.QUIZ_TYPES
	var cols := 7
	var w := minf(160.0, (vs.x - 80) / cols)
	var h := w * 0.95
	var x0 := (vs.x - w * cols - 8 * (cols - 1)) * 0.5
	for i in types.size():
		var t: String = types[i]
		var r := Rect2(x0 + (i % cols) * (w + 8), 112 + (i / cols) * (h + 8), w, h)
		var b := _btn("", r, Color(0.92, 0.92, 0.95), func(): _explain(t))
		var art := Control.new()
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.size = r.size
		art.draw.connect(func():
			SignArt.draw(art, t, 50, Rect2(r.size.x * 0.2, 6, r.size.x * 0.6, r.size.y * 0.62), font)
			var n := SignArt.name_of(t)
			var fw := font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			art.draw_string(font, Vector2((r.size.x - fw) * 0.5, r.size.y * 0.86), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.1, 0.1, 0.12)))
		b.add_child(art)
	_btn("標誌小測驗", Rect2(vs.x * 0.5 - 160, vs.y - 96, 320, 80), Color(0.6, 0.45, 0.1), show_quiz, "", 28)


func _explain(t: String) -> void:
	Snd.say("sign_info_" + t, true)
	if status_label == null or not is_instance_valid(status_label):
		status_label = Label.new()
		status_label.add_theme_font_size_override("font_size", 20)
		status_label.position = Vector2(20, _vs().y - 150)
		status_label.size = Vector2(_vs().x - 40, 50)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		screen.add_child(status_label)
	status_label.text = SignArt.explain(t)


func show_quiz() -> void:
	_clear()
	screen.set_meta("rebuild", Callable(self, "show_quiz"))
	_back(show_signs)
	var vs := _vs()
	var types: Array = SignArt.QUIZ_TYPES.duplicate()
	types.shuffle()
	var answer: String = types[0]
	var opts := [answer, types[1], types[2], types[3]]
	opts.shuffle()
	_quiz = {"answer": answer, "n": int(_quiz.get("n", 0)) + 1, "ok": int(_quiz.get("ok", 0))}
	_title("標誌小測驗　第 %d 題" % _quiz.n, "答對 %d 題　這個標誌是什麼意思？" % _quiz.ok)
	var art := Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = Vector2(vs.x * 0.5 - 110, 112)
	art.size = Vector2(220, 220)
	art.draw.connect(func(): SignArt.draw(art, answer, 60, Rect2(Vector2.ZERO, art.size), font))
	screen.add_child(art)
	var items := []
	for o in opts:
		items.append([SignArt.name_of(o), Color(0.2, 0.42, 0.7), _answer.bind(o), "", 26])
	_grid(items, 350, 2, 96, 380, 16)
	Snd.say("quiz_q", true)


func _answer(o: String) -> void:
	var ok: bool = o == _quiz.answer
	if ok:
		_quiz.ok = int(_quiz.ok) + 1
		Snd.play("success", 0.6)
		Snd.say("quiz_ok", true)
	else:
		Snd.play("fail", 0.6)
		Snd.say("quiz_no", true)
	var vs := _vs()
	var l := Label.new()
	l.text = ("答對了！" if ok else "答錯了，正確是「%s」。" % SignArt.name_of(_quiz.answer)) + SignArt.explain(_quiz.answer)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.6, 1, 0.7) if ok else Color(1, 0.7, 0.6))
	l.position = Vector2(30, vs.y - 190)
	l.size = Vector2(vs.x - 60, 70)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	screen.add_child(l)
	for c in screen.get_children():
		if c is GazeButton and c.text != "◀ 返回":
			c.enabled = false
	_btn("下一題", Rect2(vs.x * 0.5 - 140, vs.y - 104, 280, 84), Color(0.15, 0.55, 0.35), show_quiz, "", 28)


# ---------------------------------------------------------------- 設定
func show_settings() -> void:
	_clear()
	screen.set_meta("rebuild", Callable(self, "show_settings"))
	_title("設定")
	_back()
	var s := App.settings
	var items := [
		["操作：" + ("眼控駕駛" if s.control == "eye" else "鍵盤／方向盤"), Color(0.2, 0.45, 0.7), func(): _setv("control", "keyboard" if s.control == "eye" else "eye"), "眼控＝看著按鈕開車，小柯幫忙維持車道"],
		["視線轉頭：" + ("開" if s.look == "gaze" else "關"), Color(0.2, 0.45, 0.7), func(): _setv("look", "off" if s.look == "gaze" else "gaze"), "看畫面左右邊緣就轉頭看後照鏡"],
		["轉頭靈敏度 %.1f" % float(s.look_gain), Color(0.2, 0.45, 0.7), func(): _setv("look_gain", 0.6 if float(s.look_gain) >= 1.4 else float(s.look_gain) + 0.2), "按一下調整"],
		["停留時間 %.1f 秒" % float(s.dwell), Color(0.3, 0.4, 0.5), func(): _setv("dwell", 0.5 if float(s.dwell) >= 1.6 else float(s.dwell) + 0.2), "看著按鈕多久算選取"],
		["音量 %d%%" % int(float(s.volume) * 100), Color(0.3, 0.4, 0.5), func(): _setv("volume", 0.2 if float(s.volume) >= 1.0 else float(s.volume) + 0.2), "按一下調整"],
		["音樂音量 %d%%" % int(float(s.music_volume) * 100), Color(0.3, 0.4, 0.5), func(): _setv("music_volume", 0.0 if float(s.music_volume) >= 0.9 else float(s.music_volume) + 0.15), ""],
		["車內音樂：" + ("開" if s.music_on else "關"), Color(0.35, 0.3, 0.55), func(): _setv("music_on", not s.music_on), "%d 首" % Snd.tracks.size()],
		["小柯語音：" + ("開" if s.voice_on else "關"), Color(0.35, 0.3, 0.55), func(): _setv("voice_on", not s.voice_on), "導航與提示"],
		["標誌識別：" + ("開" if s.assist_signs else "關"), Color(0.35, 0.3, 0.55), func(): _setv("assist_signs", not s.assist_signs), ""],
		["畫質：" + ("高" if s.quality == "high" else "省電"), Color(0.3, 0.4, 0.5), func(): _setv("quality", "low" if s.quality == "high" else "high"), "電腦較慢請選省電"],
		["全螢幕：" + ("開" if s.fullscreen else "關"), Color(0.3, 0.4, 0.5), func(): App.set_fullscreen(not s.fullscreen); App.save(); show_settings(), "F 鍵也可以切換"],
		["自動開眼動鼠：" + ("開" if s.auto_eyemouse else "關"), Color(0.3, 0.4, 0.5), func(): _setv("auto_eyemouse", not s.auto_eyemouse), ""],
	]
	_grid(items, 100, 3, 90, 360, 12)
	var vs := _vs()
	var l := Label.new()
	l.text = Gaze.status_text()
	l.add_theme_font_size_override("font_size", 18)
	l.position = Vector2(20, vs.y - 40)
	l.size = Vector2(vs.x - 40, 26)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen.add_child(l)


func _setv(k: String, v) -> void:
	App.settings[k] = v
	App.save()
	Snd.refresh_music_volume()
	show_settings()


# ---------------------------------------------------------------- 更新、關於
func show_update() -> void:
	_clear()
	_title("檢查更新", "目前版本 " + App.APP_VERSION + "（" + Updater.platform_name() + "）")
	_back()
	var vs := _vs()
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 24)
	l.position = Vector2(40, 150)
	l.size = Vector2(vs.x - 80, 160)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.text = "正在檢查…"
	screen.add_child(l)
	screen.set_meta("label", l)
	var on_checked := func(has: bool, latest: String, notes: String):
		if not is_instance_valid(l):
			return
		if has:
			l.text = "有新版 %s！\n%s" % [latest, notes]
			_btn("立即更新", Rect2(vs.x * 0.5 - 160, 340, 320, 90), Color(0.8, 0.45, 0.1), func(): l.text = "準備更新…"; Updater.apply_update(), "", 30)
		else:
			l.text = "已經是最新版 %s 了。" % App.APP_VERSION
	Updater.checked.connect(on_checked, CONNECT_ONE_SHOT)
	Updater.failed.connect(func(m): if is_instance_valid(l): l.text = m, CONNECT_ONE_SHOT)
	Updater.progress.connect(func(r, t): if is_instance_valid(l): l.text = "%s（%d%%）" % [t, int(r * 100)])
	Updater.check()


func _on_update_checked(has: bool, latest: String, _notes: String) -> void:
	if has and screen and screen.has_meta("rebuild") and (screen.get_meta("rebuild") as Callable).get_method() == "show_title":
		show_title()
		Snd.say("update_available")


func show_about() -> void:
	_clear()
	_title("關於", App.APP_NAME + "　v" + App.APP_VERSION)
	_back()
	var vs := _vs()
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 21)
	l.position = Vector2(60, 120)
	l.size = Vector2(vs.x - 120, vs.y - 160)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.text = "\n".join([
		"給喜歡開車、也給手不方便的朋友：用眼動鼠看著按鈕就能開車，轉頭看後照鏡只要看畫面邊緣。",
		"地圖：台北市區、國道一號、日月潭、高雄港都、太魯閣、墾丁、小柯駕訓場（原創低多邊形意象）。",
		"駕駛室：左駕儀表板、導航平板、左右後照鏡；小柯機器人會辨識交通標誌、語音導航，也可以 AI 自駕。",
		"車內音樂 %d 首皆為原創合成。字型：Noto Sans TC（SIL OFL）。" % Snd.tracks.size(),
		"眼動鼠：" + Gaze.status_text(),
		"",
		App.CREDIT,
	])
	screen.add_child(l)


# ---------------------------------------------------------------- 駕駛
func start_drive(c: Dictionary) -> void:
	last_cfg = c.duplicate()
	_clear()
	screen.visible = false
	_stop_drive()
	drive = load("res://scripts/drive.gd").new()
	add_child(drive)
	drive.setup(c)
	drive.hud.menu_requested.connect(func(): show_title(); Snd.say("title_back"))
	drive.hud.retry_requested.connect(func(): start_drive(last_cfg))
	drive.hud.tutorial_requested.connect(func(): _drive_tutorial())
	if c.get("tutorial", false):
		await get_tree().create_timer(1.0).timeout
		_drive_tutorial()


func _stop_drive() -> void:
	if drive:
		drive.quit_drive()
		drive.queue_free()
		drive = null
	Snd.stop_music()
	Snd.stop_loops()


# ---------------------------------------------------------------- 語音教學
func _menu_tutorial() -> void:
	show_title()
	tut = load("res://scripts/tutorial.gd").new()
	ui.add_child(tut)
	tut.done.connect(func():
		App.settings.tutorial_done = true
		App.save()
		tut = null)
	tut.start([
		{"id": "tut_m1"},
		{"id": "tut_m2", "target": func(): return _menu_btn("自由駕駛")},
		{"id": "tut_m3", "target": func(): return _menu_btn("駕訓班")},
		{"id": "tut_m4", "target": func(): return _menu_btn("考驗挑戰")},
		{"id": "tut_m5", "target": func(): return _menu_btn("交通標誌")},
		{"id": "tut_m6", "target": func(): return _menu_btn("設定")},
		{"id": "tut_m7", "target": func(): return _menu_btn("語音教學"), "action": func(): pass},
		{"id": "tut_m8", "action": func(): _start_tutorial_drive()},
	])


func _start_tutorial_drive() -> void:
	await get_tree().create_timer(3.5).timeout
	if tut:
		tut.queue_free()
		tut = null
	start_drive({"map": "school", "vehicle": cfg.vehicle, "ready": true, "tutorial": true, "dest": "倒車入庫場"})


func _drive_tutorial() -> void:
	if drive == null:
		return
	var d := drive
	var t: Control = load("res://scripts/tutorial.gd").new()
	d.hud.root.add_child(t)
	t.shots = true
	var r := func(n: String) -> Rect2: return d.hud.target_rect(n)
	t.start([
		{"id": "tut_d1", "action": func(): d.view = "cabin"},
		{"id": "tut_d2", "target": r.bind("cluster")},
		{"id": "tut_d3", "target": r.bind("tablet")},
		{"id": "tut_d4", "target": r.bind("mirror_l"), "gaze": func(): return Vector2(30, _vs().y * 0.42)},
		{"id": "tut_d5", "target": r.bind("bar")},
		{"id": "tut_d6", "target": r.bind("ap"), "action": func(): if d.ap.mode != "full": d.toggle_ap("full")},
		{"id": "tut_d7", "target": r.bind("sign"), "action": func(): d.hud.show_sign("speed", 30)},
		{"id": "tut_d8", "target": r.bind("score")},
		{"id": "tut_d9", "target": r.bind("mini")},
		{"id": "tut_d10", "target": r.bind("pause")},
		{"id": "tut_d11"},
	])
	if App.args.has("quit-after-tutorial"):
		t.done.connect(func(): get_tree().quit())


# ---------------------------------------------------------------- 測試
func _run_test() -> void:
	var scr := App.arg("screen", "selftest")
	await get_tree().process_frame
	match scr:
		"title": show_title()
		"free": show_free()
		"lessons": show_lessons()
		"challenges": show_challenges()
		"signs": show_signs()
		"quiz": show_quiz()
		"settings": show_settings()
		"about": show_about()
		"drive":
			var c := {"map": App.arg("map", "taipei"), "vehicle": App.arg("vehicle", "truck"), "time": App.arg("time", "day"),
				"weather": App.arg("weather", "clear"), "dest": App.arg("dest", ""), "lesson": App.arg("lesson", ""), "ready": true}
			start_drive(c)
			if App.args.has("spawn"):
				await get_tree().process_frame
				var tr: Traffic = drive.traffic
				var q: Dictionary = drive.world.net.query(drive.veh.pos2())
				var ed: Dictionary = drive.world.net.edges[q.edge]
				var from: int = ed.a if ed.dir.dot(drive.veh.fwd2()) >= 0.0 else ed.b
				var t0: float = (q.t if from == ed.a else 1.0 - q.t)
				var k := 0
				for typ in App.arg("spawn").split(","):
					var sc_car := tr.add_car(typ, q.edge, from, 0 if k % 2 == 0 else mini(1, int(ed.lanes) - 1), clampf(t0 + (22.0 + k * 9.0) / ed.len, 0.0, 0.95), 0.0)
					sc_car.vmax = 0.0
					k += 1
			if App.args.has("ap"):
				await get_tree().process_frame
				drive.toggle_ap("full")
			if App.args.has("view"):
				drive.view = App.arg("view")
			if App.args.has("drive-secs"):
				var secs := float(App.arg("drive-secs"))
				var t0 := Time.get_ticks_msec()
				var last_log := 0.0
				while (Time.get_ticks_msec() - t0) / 1000.0 < secs and not drive.done:
					await get_tree().process_frame
					var el := (Time.get_ticks_msec() - t0) / 1000.0
					if el - last_log > 10.0:
						last_log = el
						print("T=%d pos=%s kmh=%.0f ap=%s remain=%.0f" % [int(el), drive.veh.pos2().round(), drive.veh.kmh(), drive.ap.status, drive.nav.remain])
				print("DRIVE_RESULT pos=%s kmh=%.1f score=%d done=%s viol=%s remain=%.0f signs=%d navlog=%s ap=%s" % [drive.veh.pos2(), drive.veh.kmh(), drive.score, drive.done,
					str(drive.violations.map(func(v): return v.text)), drive.nav.remain, drive.recog_count, str(drive.nav.log), drive.ap.status])
		"tutorial":
			start_drive({"map": "school", "vehicle": App.arg("vehicle", "truck"), "ready": true, "dest": "倒車入庫場"})
			await get_tree().create_timer(1.0).timeout
			_drive_tutorial()
			return
		"selftest":
			await _selftest()
			return
	if App.args.has("shot"):
		var wait := float(App.arg("wait", "1.5"))
		await get_tree().create_timer(wait).timeout
		get_viewport().get_texture().get_image().save_png(App.arg("shot"))
		print("SHOT ", App.arg("shot"))
		get_tree().quit()


func _selftest() -> void:
	var out := []
	var ok_all := true
	var check := func(name: String, ok: bool, detail := "") -> void:
		out.append("%s %s %s" % ["OK " if ok else "FAIL", name, detail])
	for m in Maps.LIST:
		var md := Maps.build(m.id)
		var net: RoadNet = md.net
		var reach := true
		for p in md.pois:
			if net.find_path(md.spawn.node, p.node).is_empty():
				reach = false
		check.call("地圖 " + m.name, net.nodes.size() > 4 and reach, "節點 %d 路段 %d 景點 %d" % [net.nodes.size(), net.edges.size(), md.pois.size()])
	for t in Snd.tracks.size():
		pass
	check.call("車內音樂", Snd.tracks.size() >= 20, "%d 首" % Snd.tracks.size())
	var missing := 0
	for id in Lines.all():
		if not ResourceLoader.exists("res://assets/voice/%s.ogg" % id):
			missing += 1
	check.call("小柯語音", missing == 0, "%d 句，缺 %d" % [Lines.all().size(), missing])
	check.call("課程", Lessons.SCHOOL.size() == 10 and Lessons.CHALLENGES.size() == 10)
	for line in out:
		if line.begins_with("FAIL"):
			ok_all = false
		print(line)
	print("SELFTEST ", "PASS" if ok_all else "FAIL")
	if App.args.has("out"):
		var f := FileAccess.open(App.arg("out"), FileAccess.WRITE)
		f.store_string("\n".join(out) + "\nSELFTEST " + ("PASS" if ok_all else "FAIL") + "\n")
	get_tree().quit()
