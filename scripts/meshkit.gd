class_name MeshKit
extends RefCounted
## 程式產生模型：依材質＋區塊（300 m）合併成少量 ArrayMesh，頂點色上色。

const CHUNK := 300.0

var tools := {}        # "mat|cx|cz" -> SurfaceTool
var mats := {}         # mat 名稱 -> Material
var root: Node3D


func _init(parent: Node3D, materials: Dictionary) -> void:
	root = parent
	mats = materials


func st(mat: String, at: Vector3) -> SurfaceTool:
	var key := "%s|%d|%d" % [mat, floori(at.x / CHUNK), floori(at.z / CHUNK)]
	if not tools.has(key):
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[key] = s
	return tools[key]


func commit() -> void:
	for key in tools:
		var s: SurfaceTool = tools[key]
		if key.begins_with("road|") or key.begins_with("building|"):
			s.generate_tangents()
		var mesh := s.commit()
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var mname: String = key.get_slice("|", 0)
		mi.material_override = mats.get(mname)
		if mname in ["glow", "marking", "water", "glass"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "M_" + key.replace("|", "_")
		root.add_child(mi)
	tools.clear()


# ---------------------------------------------------------------- 基本形狀
static func tri(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, uva := Vector2.ZERO, uvb := Vector2.ZERO, uvc := Vector2.ZERO) -> void:
	# 輸入為「從正面看逆時針」，Godot 正面是順時針，所以輸出 a c b
	var n := (b - a).cross(c - a).normalized()
	s.set_color(col)
	s.set_normal(n)
	s.set_uv(uva)
	s.add_vertex(a)
	s.set_uv(uvc)
	s.add_vertex(c)
	s.set_uv(uvb)
	s.add_vertex(b)


## 四邊形 a b c d（逆時針朝外看：a 左下 b 右下 c 右上 d 左上）
static func quad(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uv0 := Vector2.ZERO, uv1 := Vector2.ONE) -> void:
	tri(s, a, b, c, col, Vector2(uv0.x, uv1.y), uv1, Vector2(uv1.x, uv0.y))
	tri(s, a, c, d, col, Vector2(uv0.x, uv1.y), Vector2(uv1.x, uv0.y), uv0)


## 盒子：xf 為中心座標系，size 全尺寸。uv_scale>0 時牆面 UV 依公尺計（窗戶貼圖）
static func box(s: SurfaceTool, xf: Transform3D, size: Vector3, col: Color, uv_scale := Vector2.ZERO, top_col := Color(0, 0, 0, 0)) -> void:
	var h := size * 0.5
	var p := [
		xf * Vector3(-h.x, -h.y, -h.z), xf * Vector3(h.x, -h.y, -h.z), xf * Vector3(h.x, h.y, -h.z), xf * Vector3(-h.x, h.y, -h.z),
		xf * Vector3(-h.x, -h.y, h.z), xf * Vector3(h.x, -h.y, h.z), xf * Vector3(h.x, h.y, h.z), xf * Vector3(-h.x, h.y, h.z),
	]
	var tc := top_col if top_col.a > 0.0 else col
	var faces := [
		[4, 5, 6, 7, size.x], [1, 0, 3, 2, size.x], [5, 1, 2, 6, size.z], [0, 4, 7, 3, size.z],
	]
	for f in faces:
		var uv1 := Vector2.ONE
		if uv_scale != Vector2.ZERO:
			uv1 = Vector2(maxf(1.0, roundf(f[4] / uv_scale.x)) / 8.0, maxf(1.0, roundf(size.y / uv_scale.y)) / 8.0)
		quad(s, p[f[0]], p[f[1]], p[f[2]], p[f[3]], col, Vector2.ZERO, uv1)
	quad(s, p[7], p[6], p[2], p[3], tc, Vector2(0.002, 0.002), Vector2(0.012, 0.012))   # 頂（貼圖的牆面角落）
	quad(s, p[0], p[1], p[5], p[4], col.darkened(0.3), Vector2(0.002, 0.002), Vector2(0.012, 0.012))


## 圓柱／圓錐（底部中心在 xf.origin，沿 xf 的 Y 軸）
static func cyl(s: SurfaceTool, xf: Transform3D, r0: float, r1: float, h: float, segs: int, col: Color, caps := true) -> void:
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var b0 := xf * Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var b1 := xf * Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var t0 := xf * Vector3(cos(a0) * r1, h, sin(a0) * r1)
		var t1 := xf * Vector3(cos(a1) * r1, h, sin(a1) * r1)
		quad(s, b1, b0, t0, t1, col)
		if caps:
			if r1 > 0.001:
				tri(s, xf * Vector3(0, h, 0), t1, t0, col.lightened(0.05))
			tri(s, xf * Vector3(0, 0, 0), b0, b1, col.darkened(0.2))


static func sphere(s: SurfaceTool, c: Vector3, r: float, col: Color, segs := 8, squash := 1.0) -> void:
	var rings := maxi(3, segs / 2)
	for i in rings:
		var p0 := PI * i / rings - PI * 0.5
		var p1 := PI * (i + 1) / rings - PI * 0.5
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var v := func(p: float, a: float) -> Vector3:
				return c + Vector3(cos(p) * cos(a) * r, sin(p) * r * squash, cos(p) * sin(a) * r)
			quad(s, v.call(p0, a1), v.call(p0, a0), v.call(p1, a0), v.call(p1, a1), col)


## 平面多邊形（水面、草地），y 高度
static func poly(s: SurfaceTool, pts: PackedVector2Array, y: float, col: Color, uv_div := 0.0) -> void:
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		var rev := pts.duplicate()
		rev.reverse()
		idx = Geometry2D.triangulate_polygon(rev)
		pts = rev
	for i in range(0, idx.size(), 3):
		var a := pts[idx[i]]
		var b := pts[idx[i + 1]]
		var c := pts[idx[i + 2]]
		var A := Vector3(a.x, y, a.y)
		var B := Vector3(b.x, y, b.y)
		var C := Vector3(c.x, y, c.y)
		var up := (B - A).cross(C - A).y
		var ua := a / uv_div if uv_div > 0 else Vector2.ZERO
		var ub := b / uv_div if uv_div > 0 else Vector2.ZERO
		var uc := c / uv_div if uv_div > 0 else Vector2.ZERO
		if up >= 0:
			tri(s, A, B, C, col, ua, ub, uc)
		else:
			tri(s, A, C, B, col, ua, uc, ub)


## 平面帶狀（沿 a→b，寬 w，左右偏移 off），用於路面、標線
static func strip(s: SurfaceTool, a: Vector2, b: Vector2, off0: float, off1: float, y: float, col: Color, uv_div := 0.0) -> void:
	var d := (b - a).normalized()
	var r := Vector2(-d.y, d.x)
	var p0 := a + r * off0
	var p1 := b + r * off0
	var p2 := b + r * off1
	var p3 := a + r * off1
	var A := Vector3(p0.x, y, p0.y)
	var B := Vector3(p1.x, y, p1.y)
	var C := Vector3(p2.x, y, p2.y)
	var D := Vector3(p3.x, y, p3.y)
	var u := func(p: Vector2) -> Vector2: return p / uv_div if uv_div > 0 else Vector2.ZERO
	# 朝上
	if (B - A).cross(D - A).y > 0:
		tri(s, A, B, C, col, u.call(p0), u.call(p1), u.call(p2))
		tri(s, A, C, D, col, u.call(p0), u.call(p2), u.call(p3))
	else:
		tri(s, A, C, B, col, u.call(p0), u.call(p2), u.call(p1))
		tri(s, A, D, C, col, u.call(p0), u.call(p3), u.call(p2))


## 直立牆（沿 a→b 的線，從 y0 到 y1），朝 normal_side 那一側
static func wall(s: SurfaceTool, a: Vector2, b: Vector2, y0: float, y1: float, col: Color, face_right := true, uv_scale := Vector2.ZERO) -> void:
	var A := Vector3(a.x, y0, a.y)
	var B := Vector3(b.x, y0, b.y)
	var C := Vector3(b.x, y1, b.y)
	var D := Vector3(a.x, y1, a.y)
	var uv1 := Vector2.ONE
	if uv_scale != Vector2.ZERO:
		uv1 = Vector2(maxf(1.0, roundf(a.distance_to(b) / uv_scale.x)), maxf(1.0, roundf((y1 - y0) / uv_scale.y)))
	if face_right:
		quad(s, A, B, C, D, col, Vector2.ZERO, uv1)
	else:
		quad(s, B, A, D, C, col, Vector2.ZERO, uv1)


static func xf_at(p: Vector3, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), p)
