class_name GazeButton
extends Control
## 眼控按鈕：看著停留（App.settings.dwell 秒）就選取，也可以用滑鼠／手指點。
## hold=true 時是「看著就持續作用」（例如油門、方向），看著時 active=true。

signal picked

var text := ""
var sub := ""                     # 第二行小字
var icon := ""                    # 用文字符號當圖示
var color := Color(0.16, 0.42, 0.78)
var hold := false
var active := false               # hold 模式：目前正在作用
var _touches := {}                # hold 模式：按在這顆鍵上的手指（多指可同時踩油門＋轉向）
var _mouse_down := false
var dwell_scale := 1.0
var enabled := true
var selected := false             # 切換型按鈕的「開」狀態
var font_size := 24
var _dwell := 0.0
var _armed := true                # 選過後要移開視線才能再選
var _hover := false
var _flash := 0.0
var _font: Font


func _init(t := "", c := Color(0.16, 0.42, 0.78)) -> void:
	text = t
	color = c
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	_font = load("res://assets/fonts/ui_font.tres")


func _gui_input(e: InputEvent) -> void:
	if not enabled:
		return
	if (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT) or e is InputEventScreenTouch:
		if hold:
			if e is InputEventScreenTouch:
				if e.pressed:
					_touches[e.index] = true
				else:
					_touches.erase(e.index)
			elif not Gaze.touch_mode:
				_mouse_down = e.pressed
			active = _mouse_down or not _touches.is_empty()
			queue_redraw()
		elif e.pressed:
			_fire()
		accept_event()


func _fire() -> void:
	_flash = 0.35
	_dwell = 0.0
	_armed = false
	Snd.play("select", 0.6)
	picked.emit()
	queue_redraw()


func gaze_inside() -> bool:
	if not Gaze.valid or not is_visible_in_tree():
		return false
	return get_global_rect().has_point(Gaze.point)


func _process(dt: float) -> void:
	_flash = maxf(0.0, _flash - dt)
	var inside := enabled and gaze_inside() and not Gaze.touch_mode
	if inside != _hover:
		_hover = inside
		queue_redraw()
	if hold:
		var g_active := inside and _dwell >= 0.25
		if inside:
			_dwell += dt
		else:
			_dwell = 0.0
		var was := active
		if Gaze.touch_mode:
			active = not _touches.is_empty() or _mouse_down
		elif Gaze.source == "eyemouse" or Gaze.bot_point != null or App.settings.control == "eye":
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				active = g_active
		if was != active:
			queue_redraw()
		return
	if not inside:
		_dwell = 0.0
		_armed = true
		return
	if not _armed:
		return
	_dwell += dt
	queue_redraw()
	if _dwell >= float(App.settings.dwell) * dwell_scale:
		_fire()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var base := color if enabled else Color(0.35, 0.37, 0.4)
	if selected:
		base = base.lightened(0.25)
	if active or _flash > 0.0:
		base = base.lightened(0.35)
	# 立體鍵帽：底部陰影＋上方亮面
	var depth := 6.0
	draw_rect(Rect2(r.position + Vector2(0, depth), r.size - Vector2(0, depth)), base.darkened(0.45))
	var top := Rect2(r.position + Vector2(0, (2.0 if active else 0.0)), r.size - Vector2(0, depth))
	draw_rect(top, base)
	draw_rect(Rect2(top.position, Vector2(top.size.x, top.size.y * 0.45)), Color(1, 1, 1, 0.1))
	if _hover:
		draw_rect(top, Color(1, 0.9, 0.3), false, 4)
	elif selected:
		draw_rect(top, Color(0.5, 1, 0.6), false, 3)
	# 停留進度
	if not hold and _hover and _armed:
		var k := clampf(_dwell / (float(App.settings.dwell) * dwell_scale), 0.0, 1.0)
		draw_rect(Rect2(top.position.x, top.end.y - 7, top.size.x * k, 7), Color(1, 0.9, 0.3))
	if hold and _hover:
		draw_rect(Rect2(top.position.x, top.end.y - 7, top.size.x * clampf(_dwell / 0.25, 0, 1), 7), Color(0.5, 1, 0.6))
	if _font == null:
		return
	var lines := []
	if icon != "":
		lines.append([icon, int(font_size * 1.3)])
	if text != "":
		lines.append([text, font_size])
	if sub != "":
		lines.append([sub, int(font_size * 0.62)])
	var total := 0.0
	for l in lines:
		total += l[1] * 1.15
	var y := top.position.y + (top.size.y - total) * 0.5
	for l in lines:
		var s: String = l[0]
		var fs: int = l[1]
		var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if w > top.size.x - 10 and fs > 12:
			fs = int(fs * (top.size.x - 10) / w)
			w = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, Vector2(top.position.x + (top.size.x - w) * 0.5, y + fs * 0.95), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if enabled else Color(0.75, 0.75, 0.75))
		y += l[1] * 1.15


static func make(parent: Control, t: String, r: Rect2, c := Color(0.16, 0.42, 0.78), cb := Callable()) -> GazeButton:
	var b := GazeButton.new(t, c)
	b.position = r.position
	b.size = r.size
	parent.add_child(b)
	if cb.is_valid():
		b.picked.connect(cb)
	return b
