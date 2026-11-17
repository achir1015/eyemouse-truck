extends Control
## 語音動態教學：一步一步框出真正的畫面位置，小柯念說明，示範游標移過去，也會實際操作（例如開啟自駕）。
## steps：[{id（語音 id，文字在 Lines）, target: Callable -> Rect2, action: Callable}]

signal done

var steps: Array = []
var i := -1
var rect := Rect2()
var _t := 0.0
var _wait := 0.0
var _cursor := Vector2(-100, -100)
var caption: Label
var font: Font
var next_btn: GazeButton
var skip_btn: GazeButton
var auto_quit := false
var shots := false


func start(list: Array) -> void:
	steps = list
	font = load("res://assets/fonts/ui_font.tres")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 26)
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	caption.add_theme_constant_override("outline_size", 8)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.size = Vector2(900, 120)
	caption.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	next_btn = GazeButton.new("下一步", Color(0.15, 0.55, 0.35))
	next_btn.picked.connect(_next)
	add_child(next_btn)
	skip_btn = GazeButton.new("跳過教學", Color(0.5, 0.25, 0.25))
	skip_btn.picked.connect(finish)
	add_child(skip_btn)
	App.demo = true
	_next()


func _layout() -> void:
	var vs := get_viewport_rect().size
	size = vs
	var below := rect.size == Vector2.ZERO or rect.get_center().y < vs.y * 0.55
	caption.size = Vector2(minf(900.0, vs.x - 60), 130)
	caption.position = Vector2((vs.x - caption.size.x) * 0.5, vs.y * 0.62 if below else vs.y * 0.16)
	if rect.size != Vector2.ZERO and Rect2(caption.position, caption.size).intersects(rect):
		caption.position.y = vs.y * 0.16 if below else vs.y * 0.62
	next_btn.size = Vector2(170, 70)
	skip_btn.size = Vector2(170, 70)
	next_btn.position = Vector2(vs.x * 0.5 + 10, caption.position.y + caption.size.y + 8)
	skip_btn.position = Vector2(vs.x * 0.5 - 180, caption.position.y + caption.size.y + 8)


func _next() -> void:
	i += 1
	if i >= steps.size():
		finish()
		return
	var s: Dictionary = steps[i]
	caption.text = Lines.text(s.id)
	rect = (s.target as Callable).call() if s.has("target") else Rect2()
	if s.has("action"):
		(s.action as Callable).call()
	Snd.say(s.id, true)
	_t = 0.0
	_wait = 0.0
	_layout()
	queue_redraw()


func finish() -> void:
	App.demo = false
	Gaze.bot_point = null
	Snd.stop_speaking()
	done.emit()
	queue_free()


func _process(dt: float) -> void:
	_t += dt
	if steps.is_empty() or i < 0 or i >= steps.size():
		return
	var s: Dictionary = steps[i]
	if s.has("target"):
		rect = (s.target as Callable).call()
	# 示範游標滑向目標
	var goal := rect.get_center() if rect.size != Vector2.ZERO else get_viewport_rect().size * 0.5
	if s.has("gaze"):
		goal = (s.gaze as Callable).call()
		Gaze.bot_point = _cursor
	else:
		Gaze.bot_point = null
	_cursor = goal if _cursor.x < -50 else _cursor.lerp(goal, clampf(dt * 3.0, 0, 1))
	_layout()
	queue_redraw()
	# 念完自動下一步
	if not Snd.is_speaking() and _t > 1.0:
		_wait += dt
		if _wait > (1.2 if not s.has("hold") else float(s.hold)):
			if shots and App.args.has("tut-shots"):
				get_viewport().get_texture().get_image().save_png(App.arg("tut-shots") + "_%02d.png" % i)
			_next()
	elif App.test_mode and _t > 2.5 and not Snd.is_speaking():
		_next()


func _draw() -> void:
	var vs := get_viewport_rect().size
	var dim := Color(0, 0, 0, 0.5)
	if rect.size == Vector2.ZERO:
		draw_rect(Rect2(Vector2.ZERO, vs), dim)
	else:
		var r := rect.grow(8)
		draw_rect(Rect2(0, 0, vs.x, r.position.y), dim)
		draw_rect(Rect2(0, r.end.y, vs.x, vs.y - r.end.y), dim)
		draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), dim)
		draw_rect(Rect2(r.end.x, r.position.y, vs.x - r.end.x, r.size.y), dim)
		var pulse := 3.0 + 2.0 * sin(_t * 6.0)
		draw_rect(r, Color(1, 0.85, 0.2), false, pulse)
	# 字幕底
	draw_rect(Rect2(caption.position - Vector2(16, 8), caption.size + Vector2(32, 16)), Color(0.05, 0.1, 0.2, 0.92))
	draw_rect(Rect2(caption.position - Vector2(16, 8), caption.size + Vector2(32, 16)), Color(0.4, 0.8, 1, 0.7), false, 2)
	# 示範游標（小眼睛）
	if _cursor.x > -50:
		draw_circle(_cursor, 22, Color(1, 1, 1, 0.9))
		draw_circle(_cursor, 11, Color(0.1, 0.35, 0.8))
		draw_circle(_cursor, 5, Color(0, 0, 0))
		draw_arc(_cursor, 28, -PI * 0.5, -PI * 0.5 + TAU * fmod(_t, 1.0), 24, Color(1, 0.85, 0.2), 4)
	# 進度
	var p := "%d / %d" % [i + 1, steps.size()]
	draw_string(font, Vector2(vs.x - 110, vs.y - 20), p, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.8))
