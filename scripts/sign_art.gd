class_name SignArt
extends RefCounted
## 交通標誌圖樣（依台灣標誌樣式原創繪製）：給 3D 路牌貼圖、儀表板識別卡、標誌學習共用。

const RED := Color(0.85, 0.1, 0.12)
const BLUE := Color(0.07, 0.3, 0.72)
const GREEN := Color(0.0, 0.45, 0.25)
const BLK := Color(0.08, 0.08, 0.08)
const WHT := Color(1, 1, 1)

## type -> [名稱, 說明（小柯會念）, 類別]
const INFO := {
	"speed": ["最高速限", "最高速限標誌：圓形紅框，數字是這段路最快可以開的時速，不可以超過。", "禁制"],
	"stop": ["停車再開", "紅色八角形「停」：車子要完全停下來，看清楚左右來車再開。", "禁制"],
	"no_entry": ["禁止進入", "紅底白槓：這個方向禁止車輛進入，通常是單行道的出口。", "禁制"],
	"no_parking": ["禁止停車", "藍底紅框一條斜線：這裡不可以停車，但可以臨時停車上下客。", "禁制"],
	"no_left": ["禁止左轉", "紅框圓形、左轉箭頭加斜線：這個路口不可以左轉。", "禁制"],
	"no_uturn": ["禁止迴轉", "紅框圓形、迴轉箭頭加斜線：這裡不可以迴轉。", "禁制"],
	"no_overtake": ["禁止超車", "紅框圓形兩台車：這段路不可以超車，山路彎道常見。", "禁制"],
	"keep_right": ["靠右行駛", "藍色圓形白色箭頭：遵行方向，請靠右邊行駛。", "指示"],
	"truck_route": ["大貨車專用道", "藍色方牌卡車圖：大貨車請走這條路線。", "指示"],
	"guide": ["指路標誌", "綠色方牌：告訴你前方出口或地名的方向與距離。", "指示"],
	"slow": ["慢", "倒三角形「慢」：前方路況要注意，請減速慢行。", "禁制"],
	"school": ["當心兒童", "三角形警告：前面有學校或兒童，請放慢、注意小朋友。", "警告"],
	"ped": ["當心行人", "三角形警告：前面有行人穿越道，請禮讓行人。", "警告"],
	"curve_l": ["左彎", "三角形警告：前方道路向左彎，請提早減速。", "警告"],
	"curve_r": ["右彎", "三角形警告：前方道路向右彎，請提早減速。", "警告"],
	"rock": ["注意落石", "三角形警告：山壁可能掉落石頭，請注意上方與路面，不要停留。", "警告"],
	"animal": ["當心動物", "三角形警告：可能有野生動物穿越道路，請減速。", "警告"],
	"tunnel": ["隧道", "三角形警告：前方有隧道，請開大燈、保持車距。", "警告"],
	"horn": ["鳴喇叭", "三角形警告：前方彎道視線不好，可以按喇叭提醒對向來車。", "警告"],
	"stop_ahead": ["注意號誌", "三角形警告：前方有紅綠燈，請準備停車。", "警告"],
	"rail": ["注意火車", "三角形警告：前方有平交道，要停看聽。", "警告"],
}

const QUIZ_TYPES := ["speed", "stop", "no_entry", "no_parking", "no_left", "no_uturn", "no_overtake", "keep_right",
	"truck_route", "slow", "school", "ped", "curve_l", "curve_r", "rock", "animal", "tunnel", "horn", "stop_ahead", "rail", "guide"]


static func name_of(type: String, value := 0) -> String:
	var n: String = INFO.get(type, [type])[0]
	if type == "speed" and value > 0:
		return "速限 %d" % value
	return n


static func explain(type: String) -> String:
	return INFO.get(type, ["", ""])[1]


static func kind_of(type: String) -> String:
	return INFO.get(type, ["", "", ""])[2]


static func _circle(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c, r, col)


static func _tri(ci: CanvasItem, c: Vector2, r: float, down := false) -> void:
	var pts := PackedVector2Array()
	for k in 3:
		var a := -PI * 0.5 + k * TAU / 3.0 + (PI if down else 0.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(pts, RED)
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(c + (p - c) * 0.72)
	ci.draw_colored_polygon(inner, WHT)


static func _text(ci: CanvasItem, font: Font, c: Vector2, s: String, size: int, col: Color) -> void:
	if font == null:
		return
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(font, c + Vector2(-w * 0.5, size * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func _arrow(ci: CanvasItem, c: Vector2, s: float, dir: String, col: Color) -> void:
	var w := s * 0.16
	match dir:
		"left":
			ci.draw_line(c + Vector2(s * 0.3, s * 0.45), c + Vector2(s * 0.3, -s * 0.05), col, w)
			ci.draw_line(c + Vector2(s * 0.3, -s * 0.05), c + Vector2(-s * 0.15, -s * 0.05), col, w)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.45, -s * 0.05), c + Vector2(-s * 0.1, -s * 0.3),
				c + Vector2(-s * 0.1, s * 0.2)]), col)
		"uturn":
			ci.draw_line(c + Vector2(s * 0.25, s * 0.45), c + Vector2(s * 0.25, -s * 0.1), col, w)
			ci.draw_arc(c + Vector2(0, -s * 0.1), s * 0.25, PI, TAU, 16, col, w)
			ci.draw_line(c + Vector2(-s * 0.25, -s * 0.1), c + Vector2(-s * 0.25, s * 0.1), col, w)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.45, s * 0.08), c + Vector2(-s * 0.05, s * 0.08),
				c + Vector2(-s * 0.25, s * 0.4)]), col)
		"down_right":
			ci.draw_line(c + Vector2(-s * 0.3, -s * 0.3), c + Vector2(s * 0.15, s * 0.15), col, w * 1.3)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.38, s * 0.38), c + Vector2(s * 0.38, -s * 0.05),
				c + Vector2(-s * 0.05, s * 0.38)]), col)


static func _slash(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_line(c + Vector2(-r, -r) * 0.68, c + Vector2(r, r) * 0.68, RED, r * 0.16)


static func _car(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_rect(Rect2(c + Vector2(-s * 0.5, -s * 0.1), Vector2(s, s * 0.35)), col)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.28, -s * 0.36), Vector2(s * 0.56, s * 0.3)), col)
	ci.draw_circle(c + Vector2(-s * 0.28, s * 0.27), s * 0.12, col)
	ci.draw_circle(c + Vector2(s * 0.28, s * 0.27), s * 0.12, col)


static func _truck(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_rect(Rect2(c + Vector2(-s * 0.6, -s * 0.35), Vector2(s * 0.8, s * 0.55)), col)
	ci.draw_rect(Rect2(c + Vector2(s * 0.24, -s * 0.15), Vector2(s * 0.36, s * 0.35)), col)
	for x in [-0.42, -0.1, 0.42]:
		ci.draw_circle(c + Vector2(s * x, s * 0.27), s * 0.11, col)


## 在 rect 內畫標誌
static func draw(ci: CanvasItem, type: String, value: int, rect: Rect2, font: Font) -> void:
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.47
	match type:
		"speed":
			_circle(ci, c, r, RED)
			_circle(ci, c, r * 0.78, WHT)
			_text(ci, font, c, str(value), int(r * (0.95 if value < 100 else 0.8)), BLK)
		"stop":
			var pts := PackedVector2Array()
			for k in 8:
				var a := PI / 8.0 + k * TAU / 8.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			ci.draw_colored_polygon(pts, RED)
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), WHT, r * 0.06)
			_text(ci, font, c, "停", int(r * 1.1), WHT)
		"no_entry":
			_circle(ci, c, r, RED)
			ci.draw_rect(Rect2(c - Vector2(r * 0.7, r * 0.17), Vector2(r * 1.4, r * 0.34)), WHT)
		"no_parking":
			_circle(ci, c, r, RED)
			_circle(ci, c, r * 0.78, BLUE)
			ci.draw_line(c + Vector2(-r, -r) * 0.55, c + Vector2(r, r) * 0.55, RED, r * 0.16)
		"no_left", "no_uturn":
			_circle(ci, c, r, RED)
			_circle(ci, c, r * 0.78, WHT)
			_arrow(ci, c, r * 1.2, "left" if type == "no_left" else "uturn", BLK)
			_slash(ci, c, r)
		"no_overtake":
			_circle(ci, c, r, RED)
			_circle(ci, c, r * 0.78, WHT)
			_car(ci, c + Vector2(-r * 0.3, 0), r * 0.5, RED)
			_car(ci, c + Vector2(r * 0.3, 0), r * 0.5, BLK)
		"keep_right":
			_circle(ci, c, r, BLUE)
			_arrow(ci, c, r * 1.3, "down_right", WHT)
		"truck_route":
			ci.draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), BLUE)
			_truck(ci, c, r * 1.1, WHT)
		"guide":
			ci.draw_rect(Rect2(c - Vector2(r, r * 0.75), Vector2(r * 2, r * 1.5)), GREEN)
			ci.draw_rect(Rect2(c - Vector2(r * 0.92, r * 0.67), Vector2(r * 1.84, r * 1.34)), WHT, false, r * 0.04)
			_text(ci, font, c + Vector2(0, -r * 0.25), "出口" if value == 0 else "台中", int(r * 0.42), WHT)
			_text(ci, font, c + Vector2(0, r * 0.3), "服務區 2 km" if value == 0 else "1 km", int(r * 0.3), WHT)
		"slow":
			_tri(ci, c + Vector2(0, -r * 0.08), r * 1.05, true)
			_text(ci, font, c + Vector2(0, -r * 0.2), "慢", int(r * 0.7), BLK)
		_:
			# 三角形警告標誌
			var tc := c + Vector2(0, r * 0.12)
			_tri(ci, tc, r * 1.08)
			var s := r * 0.62
			var ic := tc + Vector2(0, r * 0.12)
			match type:
				"school":
					ci.draw_circle(ic + Vector2(-s * 0.25, -s * 0.38), s * 0.12, BLK)
					ci.draw_circle(ic + Vector2(s * 0.2, -s * 0.28), s * 0.1, BLK)
					ci.draw_line(ic + Vector2(-s * 0.25, -s * 0.25), ic + Vector2(-s * 0.3, s * 0.2), BLK, s * 0.13)
					ci.draw_line(ic + Vector2(s * 0.2, -s * 0.16), ic + Vector2(s * 0.22, s * 0.2), BLK, s * 0.11)
					ci.draw_line(ic + Vector2(-s * 0.3, s * 0.2), ic + Vector2(-s * 0.45, s * 0.45), BLK, s * 0.1)
					ci.draw_line(ic + Vector2(-s * 0.3, s * 0.2), ic + Vector2(-s * 0.12, s * 0.45), BLK, s * 0.1)
					ci.draw_line(ic + Vector2(s * 0.22, s * 0.2), ic + Vector2(s * 0.35, s * 0.45), BLK, s * 0.09)
				"ped":
					ci.draw_circle(ic + Vector2(0, -s * 0.4), s * 0.12, BLK)
					ci.draw_line(ic + Vector2(0, -s * 0.27), ic + Vector2(-s * 0.05, s * 0.12), BLK, s * 0.14)
					ci.draw_line(ic + Vector2(-s * 0.05, s * 0.12), ic + Vector2(-s * 0.25, s * 0.45), BLK, s * 0.11)
					ci.draw_line(ic + Vector2(-s * 0.05, s * 0.12), ic + Vector2(s * 0.2, s * 0.45), BLK, s * 0.11)
					ci.draw_line(ic + Vector2(-s * 0.02, -s * 0.15), ic + Vector2(s * 0.25, s * 0.0), BLK, s * 0.09)
				"curve_l", "curve_r":
					var sg := -1.0 if type == "curve_l" else 1.0
					var pts2 := PackedVector2Array()
					for k in 12:
						var t := k / 11.0
						pts2.append(ic + Vector2(sg * s * 0.35 * sin(t * PI * 0.5) - sg * s * 0.1, s * 0.45 - t * s * 0.8))
					ci.draw_polyline(pts2, BLK, s * 0.14)
					var tip := pts2[11]
					ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(sg * s * 0.18, -s * 0.05), tip + Vector2(-sg * s * 0.12, -s * 0.12),
						tip + Vector2(0, s * 0.15)]), BLK)
				"rock":
					ci.draw_colored_polygon(PackedVector2Array([ic + Vector2(-s * 0.5, -s * 0.5), ic + Vector2(-s * 0.15, -s * 0.5),
						ic + Vector2(-s * 0.15, s * 0.45), ic + Vector2(-s * 0.5, s * 0.45)]), BLK)
					ci.draw_circle(ic + Vector2(s * 0.1, -s * 0.2), s * 0.11, BLK)
					ci.draw_circle(ic + Vector2(s * 0.3, s * 0.1), s * 0.09, BLK)
					ci.draw_circle(ic + Vector2(s * 0.1, s * 0.35), s * 0.13, BLK)
				"animal":
					ci.draw_rect(Rect2(ic + Vector2(-s * 0.35, -s * 0.1), Vector2(s * 0.6, s * 0.25)), BLK)
					ci.draw_line(ic + Vector2(s * 0.2, -s * 0.05), ic + Vector2(s * 0.38, -s * 0.38), BLK, s * 0.12)
					ci.draw_line(ic + Vector2(s * 0.38, -s * 0.38), ic + Vector2(s * 0.3, -s * 0.55), BLK, s * 0.06)
					ci.draw_line(ic + Vector2(s * 0.38, -s * 0.38), ic + Vector2(s * 0.5, -s * 0.52), BLK, s * 0.06)
					for x in [-0.3, -0.15, 0.1, 0.2]:
						ci.draw_line(ic + Vector2(s * x, s * 0.12), ic + Vector2(s * x, s * 0.45), BLK, s * 0.07)
				"tunnel":
					ci.draw_arc(ic + Vector2(0, s * 0.25), s * 0.4, PI, TAU, 18, BLK, s * 0.16)
					ci.draw_line(ic + Vector2(-s * 0.4, s * 0.25), ic + Vector2(-s * 0.4, s * 0.45), BLK, s * 0.16)
					ci.draw_line(ic + Vector2(s * 0.4, s * 0.25), ic + Vector2(s * 0.4, s * 0.45), BLK, s * 0.16)
				"horn":
					ci.draw_colored_polygon(PackedVector2Array([ic + Vector2(-s * 0.4, -s * 0.12), ic + Vector2(-s * 0.15, -s * 0.12),
						ic + Vector2(s * 0.25, -s * 0.38), ic + Vector2(s * 0.25, s * 0.38), ic + Vector2(-s * 0.15, s * 0.12),
						ic + Vector2(-s * 0.4, s * 0.12)]), BLK)
					ci.draw_arc(ic + Vector2(s * 0.25, 0), s * 0.2, -0.8, 0.8, 8, BLK, s * 0.06)
				"stop_ahead":
					ci.draw_rect(Rect2(ic + Vector2(-s * 0.17, -s * 0.5), Vector2(s * 0.34, s * 0.95)), BLK)
					ci.draw_circle(ic + Vector2(0, -s * 0.3), s * 0.1, RED)
					ci.draw_circle(ic + Vector2(0, -s * 0.03), s * 0.1, Color(1, 0.75, 0.1))
					ci.draw_circle(ic + Vector2(0, s * 0.24), s * 0.1, Color(0.1, 0.8, 0.3))
				"rail":
					ci.draw_line(ic + Vector2(-s * 0.4, -s * 0.4), ic + Vector2(s * 0.4, s * 0.4), BLK, s * 0.14)
					ci.draw_line(ic + Vector2(s * 0.4, -s * 0.4), ic + Vector2(-s * 0.4, s * 0.4), BLK, s * 0.14)
				_:
					_text(ci, font, ic, "!", int(s), BLK)
