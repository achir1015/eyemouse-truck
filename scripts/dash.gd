extends Control
## 儀表（mode=cluster）與導航平板（mode=tablet）的 2D 畫面，貼在駕駛室的螢幕上；HUD 小地圖也共用（mode=mini）。

var mode := "cluster"
var veh: Vehicle
var drive: Node            # drive.gd
var font: Font
var zoom := 1.6            # 平板：每公尺幾像素


func _ready() -> void:
	font = load("res://assets/fonts/ui_font.tres")
	size = get_parent().size if get_parent() is SubViewport else size
	if get_parent() is SubViewport:
		size = Vector2((get_parent() as SubViewport).size)


func _draw() -> void:
	if veh == null:
		return
	match mode:
		"cluster": _cluster()
		"tablet": _tablet(Rect2(Vector2.ZERO, size), true)
		"mini": _tablet(Rect2(Vector2.ZERO, size), false)


func _txt(p: Vector2, s: String, sz: int, col := Color.WHITE, center := true) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(font, p - Vector2(w * 0.5 if center else 0.0, -sz * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _gauge(c: Vector2, r: float, val: float, vmax: float, step: float, label: String, unit: String, redline := -1.0) -> void:
	draw_circle(c, r + 6, Color(0.05, 0.06, 0.08))
	draw_arc(c, r + 4, 0, TAU, 48, Color(0.25, 0.3, 0.38), 3)
	var a0 := deg_to_rad(135)
	var a1 := deg_to_rad(405)
	var k := 0.0
	while k <= vmax + 0.01:
		var a := lerpf(a0, a1, k / vmax)
		var big := fmod(k, step * 2.0) < 0.01
		var col := Color(1, 0.3, 0.25) if redline > 0 and k >= redline else Color(0.85, 0.9, 1)
		draw_line(c + Vector2(cos(a), sin(a)) * (r - (14 if big else 7)), c + Vector2(cos(a), sin(a)) * r, col, 3 if big else 1.5)
		if big:
			var v := k if vmax < 100 or vmax > 1000 else k
			_txt(c + Vector2(cos(a), sin(a)) * (r - 30), str(int(v / (1000.0 if vmax > 1000 else 1.0))), 15, Color(0.85, 0.9, 1))
		k += step
	var av := lerpf(a0, a1, clampf(val / vmax, 0.0, 1.05))
	draw_line(c, c + Vector2(cos(av), sin(av)) * (r - 8), Color(1, 0.35, 0.2), 4)
	draw_circle(c, 9, Color(0.75, 0.75, 0.78))
	_txt(c + Vector2(0, r * 0.45), label, 16, Color(0.7, 0.75, 0.85))
	_txt(c + Vector2(0, r * 0.68), unit, 12, Color(0.55, 0.6, 0.7))


func _cluster() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.035))
	var T := veh.kind == "truck"
	var night := veh.lights_on
	var on := veh.engine_on
	_gauge(Vector2(150, 132), 104, veh.kmh(), 120.0 if T else 220.0, 10.0, "車速", "km/h")
	_gauge(Vector2(490, 132), 104, veh.rpm, 2500.0 if T else 7000.0, 250.0 if T else 500.0, "轉速", "x1000 rpm", 2100.0 if T else 6000.0)
	# 中央資訊
	var cx := 320.0
	draw_rect(Rect2(cx - 62, 22, 124, 212), Color(0.04, 0.05, 0.07))
	_txt(Vector2(cx, 60), "%d" % int(round(veh.kmh())), 46, Color.WHITE)
	var g := veh.gear
	if g == "D" and on:
		g = "D%d" % veh.gear_no
	_txt(Vector2(cx, 112), g, 30, Color(0.4, 1, 0.6) if veh.gear == "D" else Color(1, 0.85, 0.3))
	# 油量
	draw_rect(Rect2(cx - 50, 140, 100, 10), Color(0.2, 0.2, 0.22))
	draw_rect(Rect2(cx - 50, 140, 100 * veh.fuel, 10), Color(0.3, 0.85, 0.4) if veh.fuel > 0.2 else Color(1, 0.4, 0.2))
	_txt(Vector2(cx, 162), "油量", 13, Color(0.7, 0.75, 0.85))
	_txt(Vector2(cx, 185), "%.1f km" % (veh.odometer / 1000.0), 15, Color(0.75, 0.8, 0.9))
	if veh.cruise > 0:
		_txt(Vector2(cx, 210), "定速 %d" % int(veh.cruise), 15, Color(0.4, 0.9, 1))
	# 指示燈列
	var blink := veh.blink_phase()
	if (veh.blinker == -1 or veh.blinker == 2) and blink:
		draw_colored_polygon(PackedVector2Array([Vector2(250, 22), Vector2(270, 10), Vector2(270, 34)]), Color(0.2, 1, 0.3))
	if (veh.blinker == 1 or veh.blinker == 2) and blink:
		draw_colored_polygon(PackedVector2Array([Vector2(390, 22), Vector2(370, 10), Vector2(370, 34)]), Color(0.2, 1, 0.3))
	var icons := []
	if veh.handbrake:
		icons.append(["(P)", Color(1, 0.25, 0.2)])
	if not veh.seatbelt:
		icons.append(["安全帶", Color(1, 0.25, 0.2)])
	if night:
		icons.append(["大燈" if not veh.high_beam else "遠燈", Color(0.3, 0.7, 1) if veh.high_beam else Color(0.3, 1, 0.4)])
	if not on:
		icons.append(["引擎", Color(1, 0.7, 0.2)])
	if veh.fuel < 0.15:
		icons.append(["加油", Color(1, 0.7, 0.2)])
	for i in icons.size():
		_txt(Vector2(30 + i * 62, 246), icons[i][0], 15, icons[i][1], false)
	# 小柯辨識到的速限
	if drive and drive.get("limit_sign") > 0:
		var lr := Rect2(560, 196, 56, 56)
		SignArt.draw(self, "speed", drive.limit_sign, lr, font)


func _tablet(r: Rect2, full: bool) -> void:
	draw_rect(r, Color(0.09, 0.11, 0.14))
	if drive == null or drive.world == null:
		return
	var world: World = drive.world
	var net := world.net
	var nav: Nav = drive.nav
	var center := r.get_center() + Vector2(0, r.size.y * (0.22 if full else 0.18))
	var p := veh.pos2()
	var f := veh.fwd2()
	var ang := atan2(f.x, -f.y)    # 讓車頭朝上
	var z := zoom * (1.0 if full else 0.8)
	if veh.kmh() > 60:
		z *= 0.7
	var xf := func(q: Vector2) -> Vector2:
		return center + (q - p).rotated(-ang) * z
	var view := r.grow(40)
	# 水域
	for poly in world.map.water:
		var pts := PackedVector2Array()
		for q in poly:
			pts.append(xf.call(q))
		if pts.size() >= 3 and Geometry2D.triangulate_polygon(pts).size() > 0:
			draw_colored_polygon(pts, Color(0.12, 0.25, 0.38))
	# 道路
	var reach := maxf(r.size.x, r.size.y) / z
	for e in net.edges.size():
		var d: Dictionary = net.edges[e]
		var a: Vector2 = net.nodes[d.a]
		var b: Vector2 = net.nodes[d.b]
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) > reach:
			continue
		var w := maxf(2.0, net.half_width(e) * 2.0 * z * 0.7)
		var col := Color(0.42, 0.45, 0.5) if d.kind != "highway" else Color(0.75, 0.6, 0.3)
		draw_line(xf.call(a), xf.call(b), col, w)
	# 路線
	if nav and nav.active:
		var pl := nav.polyline()
		var pts2 := PackedVector2Array([xf.call(p)])
		for i in range(1, pl.size()):
			pts2.append(xf.call(pl[i]))
		if pts2.size() >= 2:
			draw_polyline(pts2, Color(0.15, 0.75, 1.0), 7 if full else 5)
		var dp: Vector2 = xf.call(net.nodes[nav.dest])
		if view.has_point(dp):
			draw_circle(dp, 10, Color(1, 0.3, 0.3))
			draw_circle(dp, 4, Color.WHITE)
	# 其他車
	if drive.traffic and full:
		for c in drive.traffic.cars:
			var cp: Vector2 = xf.call(c.pos)
			if r.has_point(cp):
				draw_circle(cp, 3, Color(0.9, 0.9, 0.9, 0.7) if c.type != "ambulance" else Color(1, 0.2, 0.2))
	# 自己（箭頭）
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -14), center + Vector2(10, 10), center + Vector2(0, 5), center + Vector2(-10, 10)]), Color(1, 0.85, 0.2))
	if not full:
		draw_rect(r, Color(0.3, 0.6, 1.0, 0.6), false, 2)
		return
	# 上方：下一個動作
	draw_rect(Rect2(0, 0, r.size.x, 92), Color(0.05, 0.3, 0.5, 0.92))
	if nav and nav.active:
		_turn_icon(Vector2(56, 46), nav.next_turn)
		var dist_s := ("%d 公尺" % int(roundf(nav.next_dist / 10.0) * 10.0)) if nav.next_dist < 1000 else ("%.1f 公里" % (nav.next_dist / 1000.0))
		_txt(Vector2(110, 32), dist_s, 30, Color.WHITE, false)
		var road := nav.next_road if nav.next_turn != "arrive" else nav.dest_name
		_txt(Vector2(110, 70), Nav.turn_text(nav.next_turn) + ("　" + road if road != "" else ""), 22, Color(0.85, 0.95, 1), false)
		draw_rect(Rect2(0, r.size.y - 44, r.size.x, 44), Color(0.04, 0.06, 0.08, 0.9))
		_txt(Vector2(14, r.size.y - 22), "目的地：%s　剩 %.1f km　約 %d 分" % [nav.dest_name, nav.remain / 1000.0, int(ceil(nav.eta_min(maxf(veh.kmh(), 30.0))))], 18, Color.WHITE, false)
	else:
		_txt(Vector2(r.size.x * 0.5, 46), "小柯導航：請選擇目的地", 26, Color.WHITE)
		draw_rect(Rect2(0, r.size.y - 44, r.size.x, 44), Color(0.04, 0.06, 0.08, 0.9))
		_txt(Vector2(14, r.size.y - 22), "目前道路：" + str(drive.road_name), 18, Color.WHITE, false)
	# 右側：速限與音樂
	if drive.get("limit_now") > 0:
		SignArt.draw(self, "speed", drive.limit_now, Rect2(r.size.x - 86, 104, 72, 72), font)
	if Snd.music.playing:
		_txt(Vector2(r.size.x - 14 - font.get_string_size("♪ " + Snd.track_title(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, r.size.y - 64), "♪ " + Snd.track_title(), 16, Color(0.8, 0.9, 1), false)


func _turn_icon(c: Vector2, t: String) -> void:
	var col := Color.WHITE
	match t:
		"left", "right":
			var s := -1.0 if t == "left" else 1.0
			draw_line(c + Vector2(0, 30), c + Vector2(0, -2), col, 9)
			draw_line(c + Vector2(0, -2), c + Vector2(s * 18, -2), col, 9)
			draw_colored_polygon(PackedVector2Array([c + Vector2(s * 34, -2), c + Vector2(s * 16, -18), c + Vector2(s * 16, 14)]), col)
		"uturn":
			draw_line(c + Vector2(12, 30), c + Vector2(12, -6), col, 8)
			draw_arc(c + Vector2(0, -6), 12, PI, TAU, 12, col, 8)
			draw_line(c + Vector2(-12, -6), c + Vector2(-12, 12), col, 8)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-26, 10), c + Vector2(2, 10), c + Vector2(-12, 30)]), col)
		"arrive":
			draw_line(c + Vector2(-10, 30), c + Vector2(-10, -28), col, 5)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -28), c + Vector2(24, -18), c + Vector2(-8, -6)]), Color(1, 0.35, 0.3))
		_:
			draw_line(c + Vector2(0, 30), c + Vector2(0, -14), col, 9)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -32), c + Vector2(-16, -12), c + Vector2(16, -12)]), col)
