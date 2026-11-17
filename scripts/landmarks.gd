class_name Landmarks
extends RefCounted
## 台灣景點地標（原創低多邊形意象）。回傳碰撞圓 [{c: Vector2, r: float}]。

const WHITE := Color(0.93, 0.92, 0.88)
const CREAM := Color(0.92, 0.86, 0.7)
const BRICK := Color(0.66, 0.28, 0.2)
const TEMPLE_RED := Color(0.72, 0.12, 0.1)
const ROOF_GOLD := Color(0.95, 0.66, 0.15)
const ROOF_BLUE := Color(0.12, 0.3, 0.62)
const ROOF_GREEN := Color(0.18, 0.5, 0.35)
const CONCRETE := Color(0.62, 0.62, 0.6)
const STEEL := Color(0.45, 0.47, 0.5)


static func v3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


static func label(world: Node3D, text: String, pos: Vector3, size := 0.08, yaw := 0.0, col := Color.WHITE, billboard := true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = load("res://assets/fonts/ui_font.tres")
	l.font_size = 96
	l.outline_size = 18
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.pixel_size = size * 0.6
	l.position = pos
	l.rotation.y = yaw
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.no_depth_test = false
	l.double_sided = true
	world.add_child(l)
	return l


static func build(kit: MeshKit, world: Node3D, lm: Dictionary) -> Array:
	var p: Vector2 = lm.pos
	var rot: float = float(lm.get("rot", 0.0))
	var o := v3(p)
	var S := kit.st("solid", o)
	var G := kit.st("glow", o)
	var GL := kit.st("glass", o)
	var X := MeshKit.xf_at(o, rot)
	var cols := []
	match str(lm.type):
		"tw101":
			MeshKit.box(S, X.translated_local(Vector3(0, 12, 0)), Vector3(70, 24, 60), CONCRETE.lightened(0.1))
			MeshKit.cyl(GL, X.translated_local(Vector3(0, 24, 0)) * Transform3D(Basis(Vector3.UP, PI / 4), Vector3.ZERO), 26, 20, 60, 4, Color(0.25, 0.45, 0.45))
			var y := 84.0
			for k in 8:
				MeshKit.cyl(GL, X.translated_local(Vector3(0, y, 0)) * Transform3D(Basis(Vector3.UP, PI / 4), Vector3.ZERO), 17, 23, 24, 4, Color(0.22, 0.48, 0.5).lightened(k * 0.02))
				MeshKit.cyl(G, X.translated_local(Vector3(0, y + 23.5, 0)) * Transform3D(Basis(Vector3.UP, PI / 4), Vector3.ZERO), 23.2, 23.2, 0.6, 4, Color(0.5, 0.9, 1.0), false)
				y += 24.0
			MeshKit.cyl(GL, X.translated_local(Vector3(0, y, 0)) * Transform3D(Basis(Vector3.UP, PI / 4), Vector3.ZERO), 13, 9, 18, 4, Color(0.25, 0.5, 0.5))
			MeshKit.cyl(S, X.translated_local(Vector3(0, y + 18, 0)), 2.5, 0.4, 55, 8, STEEL)
			cols.append({"c": p, "r": 38.0})
			label(world, lm.name, o + Vector3(0, 30, 38), 0.12)
		"memorial_hall":
			MeshKit.box(S, X.translated_local(Vector3(0, 1, 0)), Vector3(90, 2, 70), CONCRETE.lightened(0.2))
			MeshKit.box(S, X.translated_local(Vector3(0, 9, 0)), Vector3(70, 14, 50), CREAM)
			for k in 14:
				MeshKit.cyl(S, X.translated_local(Vector3(-32 + k * 4.9, 2, 26)), 0.9, 0.9, 14, 8, WHITE)
			MeshKit.box(S, X.translated_local(Vector3(0, 17, 0)), Vector3(78, 3, 58), ROOF_GOLD)
			MeshKit.cyl(S, X.translated_local(Vector3(0, 18.5, 0)) * Transform3D(Basis(Vector3.UP, PI / 4), Vector3.ZERO), 40, 18, 9, 4, ROOF_GOLD.darkened(0.1))
			MeshKit.box(S, X.translated_local(Vector3(0, 30, 0)) * Transform3D(Basis(Vector3.FORWARD, 0.0), Vector3.ZERO), Vector3(12, 8, 10), ROOF_GOLD)
			cols.append({"c": p, "r": 40.0})
			label(world, lm.name, o + Vector3(0, 40, 0), 0.1)
		"presidential":
			MeshKit.box(S, X.translated_local(Vector3(0, 10, 0)), Vector3(110, 20, 22), BRICK)
			for k in 5:
				MeshKit.box(S, X.translated_local(Vector3(0, 3 + k * 4, 11.1)), Vector3(110, 0.6, 0.4), WHITE)
			MeshKit.box(S, X.translated_local(Vector3(-50, 10, 22)), Vector3(12, 20, 30), BRICK)
			MeshKit.box(S, X.translated_local(Vector3(50, 10, 22)), Vector3(12, 20, 30), BRICK)
			MeshKit.box(S, X.translated_local(Vector3(0, 30, 2)), Vector3(14, 60, 14), BRICK)
			MeshKit.box(S, X.translated_local(Vector3(0, 62, 2)), Vector3(10, 6, 10), WHITE)
			MeshKit.cyl(S, X.translated_local(Vector3(0, 65, 2)), 4.5, 1.0, 6, 8, WHITE)
			for k in 4:
				MeshKit.box(S, X.translated_local(Vector3(0, 8 + k * 12, 9.1)), Vector3(14.2, 0.8, 0.4), WHITE)
			cols.append({"c": p, "r": 45.0})
			label(world, lm.name, o + Vector3(0, 75, 0), 0.1)
		"cks_gate":
			MeshKit.box(S, X.translated_local(Vector3(0, 0.3, 0)), Vector3(110, 0.6, 110), Color(0.75, 0.73, 0.7))
			var gx := X.translated_local(Vector3(0, 0, 40))
			for k in 6:
				MeshKit.box(S, gx.translated_local(Vector3(-25 + k * 10, 9, 0)), Vector3(4, 18, 5), WHITE)
			MeshKit.box(S, gx.translated_local(Vector3(0, 19, 0)), Vector3(58, 3, 7), WHITE)
			MeshKit.box(S, gx.translated_local(Vector3(0, 21.5, 0)), Vector3(62, 2, 9), ROOF_BLUE)
			MeshKit.box(S, gx.translated_local(Vector3(0, 23.5, 0)), Vector3(22, 3, 8), ROOF_BLUE)
			var hx := X.translated_local(Vector3(0, 0, -25))
			MeshKit.cyl(S, hx, 30, 26, 8, 8, WHITE)
			MeshKit.cyl(S, hx.translated_local(Vector3(0, 8, 0)), 18, 18, 18, 8, WHITE)
			MeshKit.cyl(S, hx.translated_local(Vector3(0, 26, 0)), 22, 10, 7, 8, ROOF_BLUE)
			MeshKit.cyl(S, hx.translated_local(Vector3(0, 33, 0)), 12, 1, 10, 8, ROOF_BLUE)
			MeshKit.sphere(G, (hx * Vector3(0, 44, 0)), 1.5, Color(1, 0.85, 0.3), 8)
			cols.append({"c": p + Vector2(0, -25).rotated(-rot), "r": 31.0})
			for k in [-25, -5, 15]:
				cols.append({"c": p + Vector2(k, 40), "r": 3.5})
			cols.append({"c": p + Vector2(25, 40), "r": 3.5})
			label(world, lm.name, o + Vector3(0, 28, 44), 0.1)
		"station":
			MeshKit.box(S, X.translated_local(Vector3(0, 10, 0)), Vector3(85, 20, 70), CREAM.darkened(0.05))
			MeshKit.cyl(S, X.translated_local(Vector3(0, 20, 0)) * Transform3D(Basis(Vector3.UP, PI / 4), Vector3.ZERO), 58, 30, 10, 4, Color(0.45, 0.32, 0.2))
			MeshKit.box(G, X.translated_local(Vector3(0, 14, 35.2)), Vector3(40, 3, 0.3), Color(1, 0.9, 0.6))
			cols.append({"c": p, "r": 45.0})
			label(world, lm.name, o + Vector3(0, 34, 0), 0.1)
		"park":
			var pond := PackedVector2Array()
			for k in 16:
				var a := TAU * k / 16.0
				pond.append(p + Vector2(cos(a) * 22, sin(a) * 14) + Vector2(20, -10))
			MeshKit.poly(kit.st("water", o), pond, 0.06, Color(0.25, 0.45, 0.55))
			label(world, lm.name, o + Vector3(0, 12, 0), 0.07)
		"warehouse":
			MeshKit.box(S, X.translated_local(Vector3(0, 7, 0)), Vector3(70, 14, 40), Color(0.78, 0.8, 0.82))
			MeshKit.box(S, X.translated_local(Vector3(0, 11, 20.1)), Vector3(70, 2.2, 0.3), Color(0.1, 0.45, 0.85))
			for k in 6:
				MeshKit.box(S, X.translated_local(Vector3(-28 + k * 11, 2.5, 20.1)), Vector3(6, 5, 0.3), Color(0.35, 0.37, 0.4))
			cols.append({"c": p, "r": 34.0})
			label(world, lm.name, o + Vector3(0, 18, 22), 0.07, 0.0, Color(1, 0.95, 0.6))
		"tower85":
			MeshKit.box(GL, X.translated_local(Vector3(-14, 60, 0)), Vector3(18, 120, 30), Color(0.3, 0.42, 0.5))
			MeshKit.box(GL, X.translated_local(Vector3(14, 60, 0)), Vector3(18, 120, 30), Color(0.3, 0.42, 0.5))
			MeshKit.box(GL, X.translated_local(Vector3(0, 150, 0)), Vector3(46, 60, 30), Color(0.32, 0.44, 0.52))
			MeshKit.box(GL, X.translated_local(Vector3(0, 200, 0)), Vector3(28, 40, 24), Color(0.34, 0.46, 0.54))
			MeshKit.box(GL, X.translated_local(Vector3(0, 235, 0)), Vector3(18, 30, 18), Color(0.36, 0.48, 0.56))
			MeshKit.cyl(S, X.translated_local(Vector3(0, 250, 0)), 2, 0.3, 45, 6, STEEL)
			MeshKit.box(G, X.translated_local(Vector3(0, 249, 0)), Vector3(18.4, 1, 18.4), Color(0.6, 0.85, 1))
			cols.append({"c": p, "r": 30.0})
			label(world, lm.name, o + Vector3(0, 30, 20), 0.1)
		"pier2":
			for k in 4:
				var cx := X.translated_local(Vector3(-36 + k * 24, 0, 0))
				var c: Color = [Color(0.75, 0.35, 0.25), Color(0.85, 0.7, 0.3), Color(0.3, 0.55, 0.7), Color(0.55, 0.6, 0.35)][k]
				MeshKit.box(S, cx.translated_local(Vector3(0, 4, 0)), Vector3(20, 8, 40), c)
				MeshKit.cyl(S, cx.translated_local(Vector3(0, 8, 0)) * Transform3D(Basis(Vector3.UP, PI / 4), Vector3.ZERO), 14.5, 2, 4, 4, Color(0.35, 0.33, 0.33))
			cols.append({"c": p, "r": 40.0})
			label(world, lm.name, o + Vector3(0, 16, 22), 0.08)
		"cranes":
			for k in 4:
				var cx := X.translated_local(Vector3(0, 0, -90 + k * 60))
				var c := Color(0.85, 0.35, 0.15) if k % 2 == 0 else Color(0.2, 0.45, 0.75)
				for lx in [-8.0, 8.0]:
					for lz in [-8.0, 8.0]:
						MeshKit.box(S, cx.translated_local(Vector3(lx, 20, lz)), Vector3(1.6, 40, 1.6), c)
				MeshKit.box(S, cx.translated_local(Vector3(-10, 41, 0)), Vector3(70, 3, 3), c)
				MeshKit.box(S, cx.translated_local(Vector3(0, 46, 0)), Vector3(10, 8, 10), c.darkened(0.2))
				MeshKit.box(G, cx.translated_local(Vector3(-44, 43, 0)), Vector3(1, 1, 1), Color(1, 0.2, 0.1))
		"container_yard":
			var rng := RandomNumberGenerator.new()
			rng.seed = 85
			var pal := [Color(0.75, 0.2, 0.15), Color(0.15, 0.4, 0.7), Color(0.2, 0.55, 0.3), Color(0.85, 0.6, 0.15), Color(0.5, 0.5, 0.55)]
			for r in 6:
				for k in 8:
					var h := rng.randi_range(1, 4)
					for lv in h:
						MeshKit.box(S, X.translated_local(Vector3(-55 + r * 14, 1.3 + lv * 2.6, -40 + k * 6.6)), Vector3(12.2, 2.55, 2.45), pal[rng.randi() % pal.size()])
			cols.append({"c": p, "r": 52.0})
			label(world, lm.name, o + Vector3(0, 16, 0), 0.08)
		"pagoda":
			MeshKit.cyl(S, X, 9, 9, 3, 8, CONCRETE)
			var y := 3.0
			for k in 9:
				var r := 6.5 - k * 0.45
				MeshKit.cyl(S, X.translated_local(Vector3(0, y, 0)), r, r, 3.4, 8, CREAM)
				MeshKit.cyl(S, X.translated_local(Vector3(0, y + 3.4, 0)), r + 2.0, r * 0.9, 0.8, 8, ROOF_GOLD if lm.name.begins_with("慈") else TEMPLE_RED)
				y += 4.2
			MeshKit.cyl(S, X.translated_local(Vector3(0, y, 0)), 1.0, 0.1, 6, 8, ROOF_GOLD)
			cols.append({"c": p, "r": 10.0})
			label(world, lm.name, o + Vector3(0, y + 10, 0), 0.08)
		"temple":
			MeshKit.box(S, X.translated_local(Vector3(0, 1.5, 0)), Vector3(50, 3, 36), CONCRETE)
			MeshKit.box(S, X.translated_local(Vector3(0, 8, 0)), Vector3(40, 10, 26), TEMPLE_RED)
			MeshKit.cyl(S, X.translated_local(Vector3(0, 13, 0)) * Transform3D(Basis(Vector3.UP, PI / 4), Vector3.ZERO), 34, 8, 8, 4, ROOF_GOLD)
			MeshKit.box(S, X.translated_local(Vector3(0, 20, 0)), Vector3(18, 1.2, 3), ROOF_GOLD.darkened(0.15))
			for k in 2:
				MeshKit.cyl(S, X.translated_local(Vector3(-8 + k * 16, 3, 22)), 3.5, 3.5, 2, 8, CONCRETE)
				MeshKit.sphere(S, X * Vector3(-8 + k * 16, 6, 22), 1.6, Color(0.55, 0.52, 0.45), 8)
			cols.append({"c": p, "r": 26.0})
			label(world, lm.name, o + Vector3(0, 28, 0), 0.08)
		"visitor":
			MeshKit.box(S, X.translated_local(Vector3(0, 4, 0)), Vector3(80, 8, 24), CONCRETE.lightened(0.1))
			MeshKit.box(GL, X.translated_local(Vector3(0, 4, 12.1)), Vector3(74, 6, 0.3), Color(0.3, 0.45, 0.55))
			MeshKit.poly(kit.st("water", o), PackedVector2Array([p + Vector2(-38, 16), p + Vector2(38, 16), p + Vector2(38, 30), p + Vector2(-38, 30)]), 0.08, Color(0.3, 0.5, 0.6))
			cols.append({"c": p, "r": 30.0})
			label(world, lm.name, o + Vector3(0, 14, 0), 0.07)
		"wharf":
			MeshKit.box(S, X.translated_local(Vector3(0, 0.6, -20)), Vector3(8, 0.5, 50), Color(0.55, 0.42, 0.3))
			for k in 3:
				var bx := X.translated_local(Vector3(9, 0.4, -10 - k * 12))
				MeshKit.box(S, bx, Vector3(4, 1.4, 10), WHITE)
				MeshKit.box(S, bx.translated_local(Vector3(0, 1.4, 1)), Vector3(3.4, 1.4, 4), Color(0.2, 0.45, 0.7))
			label(world, lm.name, o + Vector3(0, 6, 0), 0.06)
		"island":
			MeshKit.cyl(S, MeshKit.xf_at(o + Vector3(0, -0.5, 0)), 26, 16, 3, 14, Color(0.3, 0.5, 0.25))
			for k in 7:
				var a := TAU * k / 7.0
				var tp := o + Vector3(cos(a) * 10, 2.5, sin(a) * 10)
				MeshKit.cyl(S, MeshKit.xf_at(tp), 0.4, 0.3, 4, 5, Color(0.4, 0.28, 0.18), false)
				MeshKit.sphere(S, tp + Vector3(0, 5, 0), 3.2, Color(0.2, 0.45, 0.2), 6)
			label(world, lm.name, o + Vector3(0, 12, 0), 0.06)
		"taroko_gate":
			for x in [-11.0, -4.0, 4.0, 11.0]:
				MeshKit.box(S, X.translated_local(Vector3(x, 5, 0)), Vector3(1.4, 10, 1.4), TEMPLE_RED)
			MeshKit.box(S, X.translated_local(Vector3(0, 10.5, 0)), Vector3(26, 1.5, 2.5), WHITE)
			MeshKit.box(S, X.translated_local(Vector3(0, 12, 0)), Vector3(28, 1.2, 4), ROOF_GREEN)
			MeshKit.box(S, X.translated_local(Vector3(0, 13.8, 0)), Vector3(10, 1.4, 3.6), ROOF_GREEN)
			MeshKit.box(G, X.translated_local(Vector3(0, 10.5, 1.3)), Vector3(6, 1.0, 0.1), Color(1, 0.85, 0.3))
			for x in [-11.0, -4.0, 4.0, 11.0]:
				cols.append({"c": p + Vector2(x, 0).rotated(-rot), "r": 1.2})
			label(world, lm.name, o + Vector3(0, 17, 0), 0.06)
		"shrine":
			MeshKit.box(S, X.translated_local(Vector3(0, 12, 0)), Vector3(12, 6, 8), TEMPLE_RED)
			MeshKit.cyl(S, X.translated_local(Vector3(0, 15, 0)) * Transform3D(Basis(Vector3.UP, PI / 4), Vector3.ZERO), 11, 2, 3, 4, ROOF_GREEN)
			MeshKit.box(G, X.translated_local(Vector3(9, 8, 0)), Vector3(2, 16, 0.5), Color(0.85, 0.95, 1.0))
			label(world, lm.name, o + Vector3(0, 22, 0), 0.06)
		"suspension":
			MeshKit.box(S, X.translated_local(Vector3(0, 6, -36)), Vector3(2, 0.3, 30), Color(0.5, 0.4, 0.3))
			label(world, lm.name, o + Vector3(0, 10, 0), 0.06)
		"lighthouse":
			MeshKit.box(S, X.translated_local(Vector3(8, 2.5, 0)), Vector3(10, 5, 8), WHITE)
			MeshKit.cyl(S, X, 4.0, 2.8, 22, 8, WHITE)
			MeshKit.cyl(S, X.translated_local(Vector3(0, 22, 0)), 3.6, 3.6, 0.6, 8, Color(0.2, 0.2, 0.2))
			MeshKit.cyl(G, X.translated_local(Vector3(0, 22.6, 0)), 2.2, 2.2, 3, 8, Color(1, 0.95, 0.7), false)
			MeshKit.cyl(S, X.translated_local(Vector3(0, 25.6, 0)), 2.8, 0.4, 2.5, 8, Color(0.15, 0.15, 0.15))
			cols.append({"c": p, "r": 6.0})
			label(world, lm.name, o + Vector3(0, 32, 0), 0.07)
		"sail_rock":
			MeshKit.sphere(S, o + Vector3(0, 6, 0), 12, Color(0.5, 0.45, 0.38), 9, 1.4)
			label(world, lm.name, o + Vector3(0, 26, 0), 0.07)
		"night_market":
			var rng2 := RandomNumberGenerator.new()
			rng2.seed = 7
			var foods := ["雞排", "珍珠奶茶", "烤魷魚", "大腸包小腸", "芒果冰", "臭豆腐", "鹽酥雞", "蚵仔煎"]
			for k in 8:
				for side in [-1.0, 1.0]:
					var sx := X.translated_local(Vector3(-42 + k * 12, 0, side * 9.5))
					var c := Color.from_hsv(rng2.randf(), 0.6, 0.9)
					MeshKit.box(S, sx.translated_local(Vector3(0, 1, 0)), Vector3(3, 2, 1.6), Color(0.6, 0.6, 0.62))
					MeshKit.box(S, sx.translated_local(Vector3(0, 2.6, 0)), Vector3(3.6, 0.2, 2.4), c)
					MeshKit.box(G, sx.translated_local(Vector3(0, 2.4, side * -1.2)), Vector3(3.4, 0.25, 0.1), Color(1, 0.85, 0.5))
					if side > 0 and k % 2 == 0:
						label(world, foods[k], sx * Vector3(0, 3.6, 0), 0.03, 0.0, Color(1, 0.95, 0.6))
		"beach":
			var sand := PackedVector2Array()
			for k in 12:
				var a := PI + PI * k / 11.0
				sand.append(p + Vector2(cos(a) * 160, -sin(a) * 40 + 20))
			MeshKit.poly(kit.st("solid", o), sand, 0.02, Color(0.9, 0.84, 0.62))
			for k in 6:
				var up := o + Vector3(-60 + k * 24, 0, 40)
				MeshKit.cyl(S, MeshKit.xf_at(up), 0.08, 0.08, 2.4, 4, WHITE, false)
				MeshKit.cyl(S, MeshKit.xf_at(up + Vector3(0, 2.2, 0)), 1.8, 0.05, 0.6, 8, Color.from_hsv(k * 0.15, 0.7, 0.95))
			label(world, lm.name, o + Vector3(0, 8, 30), 0.07)
		"service_area":
			MeshKit.box(S, X.translated_local(Vector3(0, 4, 0)), Vector3(30, 8, 60), CREAM)
			MeshKit.box(S, X.translated_local(Vector3(0, 8.4, 0)), Vector3(34, 0.8, 64), ROOF_BLUE)
			MeshKit.box(G, X.translated_local(Vector3(-15.2, 5.5, 0)), Vector3(0.3, 1.6, 20), Color(1, 0.95, 0.75))
			cols.append({"c": p, "r": 18.0})
			cols.append({"c": p + Vector2(0, 20), "r": 16.0})
			cols.append({"c": p + Vector2(0, -20), "r": 16.0})
			label(world, lm.name, o + Vector3(-16, 12, 0), 0.08)
		"gantry":
			var gx2 := X
			for x in [-17.0, 17.0]:
				MeshKit.box(S, gx2.translated_local(Vector3(x, 3.8, 0)), Vector3(0.6, 7.6, 0.6), STEEL)
			MeshKit.box(S, gx2.translated_local(Vector3(0, 7.4, 0)), Vector3(35, 0.9, 1.2), STEEL)
			for x in [-12.0, -6.0, 0.0, 6.0, 12.0]:
				MeshKit.box(S, gx2.translated_local(Vector3(x, 6.6, 0)), Vector3(1.2, 0.6, 0.6), Color(0.2, 0.2, 0.22))
			for x in [-17.0, 17.0]:
				cols.append({"c": p + Vector2(x, 0).rotated(-rot), "r": 0.8})
		"school_bldg":
			MeshKit.box(S, X.translated_local(Vector3(0, 6, 0)), Vector3(50, 12, 18), CREAM)
			MeshKit.box(GL, X.translated_local(Vector3(0, 6, 9.1)), Vector3(46, 8, 0.2), Color(0.3, 0.45, 0.55))
			MeshKit.cyl(S, X.translated_local(Vector3(30, 0, 14)), 0.12, 0.08, 12, 6, WHITE, false)
			cols.append({"c": p, "r": 26.0})
			label(world, lm.name, o + Vector3(0, 15, 10), 0.08, 0.0, Color(1, 0.95, 0.6))
		"parking_bays", "parking_street":
			label(world, lm.name, o + Vector3(0, 6, 0), 0.06)
	return cols
