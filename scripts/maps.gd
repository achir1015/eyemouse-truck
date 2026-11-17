class_name Maps
extends RefCounted
## 地圖定義：台灣著名景點與市區（原創低多邊形意象，不是真實比例）。

const LIST := [
	{"id": "taipei", "name": "台北市區", "desc": "信義區、總統府、台北101，紅綠燈多、機車多的市區駕駛"},
	{"id": "freeway", "name": "國道一號", "desc": "從物流倉庫上交流道，經過服務區，開到台中物流中心"},
	{"id": "sunmoon", "name": "日月潭環湖", "desc": "環湖公路、碼頭、慈恩塔，彎道多、風景好"},
	{"id": "kaohsiung", "name": "高雄港都", "desc": "85 大樓、愛河、駁二、港區貨櫃場，大卡車的家"},
	{"id": "taroko", "name": "太魯閣峽谷", "desc": "中橫公路峽谷、隧道、峭壁，山路彎多要小心"},
	{"id": "kenting", "name": "墾丁濱海", "desc": "海岸公路、鵝鑾鼻燈塔、墾丁大街夜市"},
	{"id": "school", "name": "小柯駕訓場", "desc": "練習起步、轉彎、紅綠燈、S 彎、倒車入庫、路邊停車"},
]


static func info(id: String) -> Dictionary:
	for m in LIST:
		if m.id == id:
			return m
	return LIST[0]


static func build(id: String) -> Dictionary:
	var m := {}
	match id:
		"freeway": m = _freeway()
		"sunmoon": m = _sunmoon()
		"kaohsiung": m = _kaohsiung()
		"taroko": m = _taroko()
		"kenting": m = _kenting()
		"school": m = _school()
		_: m = _taipei()
	m.id = id
	m.name = info(id).name
	var net: RoadNet = m.net
	net.finalize()
	for p in m.pois:
		if not p.has("node"):
			p.node = net.nearest_node(p.pos)
	if not m.has("signs"):
		m.signs = []
	if not m.has("water"):
		m.water = []
	if not m.has("blocks"):
		m.blocks = []
	if not m.has("landmarks"):
		m.landmarks = []
	if not m.has("parking"):
		m.parking = []
	if not m.has("lights"):
		m.lights = []
		for n in net.nodes.size():
			if net.is_junction(n) and _all_kind(net, n, ["city"]):
				m.lights.append(n)
	if not m.has("stops"):
		m.stops = []
	return m


static func _all_kind(net: RoadNet, n: int, kinds: Array) -> bool:
	for e in net.adj[n]:
		if not kinds.has(net.edges[e].kind):
			return false
	return true


# ---------------------------------------------------------------- 共用
## 方格街道，回傳 ids[i][j]（i=x、j=z）
static func _grid(net: RoadNet, xs: Array, zs: Array, xopts: Callable, zopts: Callable) -> Array:
	var ids := []
	for i in xs.size():
		var col := []
		for j in zs.size():
			col.append(net.add_node(Vector2(xs[i], zs[j])))
		ids.append(col)
	for i in xs.size():          # 南北向（x 固定）
		for j in zs.size() - 1:
			net.add_edge(ids[i][j], ids[i][j + 1], xopts.call(i))
	for j in zs.size():          # 東西向（z 固定）
		for i in xs.size() - 1:
			net.add_edge(ids[i][j], ids[i + 1][j], zopts.call(j))
	return ids


static func _blocks(xs: Array, zs: Array, skip := []) -> Array:
	var out := []
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var c := Vector2((xs[i] + xs[i + 1]) * 0.5, (zs[j] + zs[j + 1]) * 0.5)
			var hit := false
			for s in skip:
				if c.distance_to(s) < 5.0:
					hit = true
			if not hit:
				out.append(Rect2(Vector2(xs[i], zs[j]), Vector2(xs[i + 1] - xs[i], zs[j + 1] - zs[j])))
	return out


static func _chain(net: RoadNet, pts: Array, opts := {}) -> Array:
	var ids := []
	for p in pts:
		ids.append(net.add_node(p))
	net.add_path(ids, opts)
	return ids


static func _sign(edge: int, from_end: bool, t: float, type: String, value := 0) -> Dictionary:
	return {"edge": edge, "rev": from_end, "t": t, "type": type, "value": value}


# ---------------------------------------------------------------- 台北市區
static func _taipei() -> Dictionary:
	var net := RoadNet.new()
	var xs := [-390.0, -260.0, -130.0, 0.0, 130.0, 260.0, 390.0]
	var zs := [-325.0, -195.0, -65.0, 65.0, 195.0, 325.0]
	var xnames := ["中山南路", "新生南路", "復興南路", "敦化南路", "光復南路", "基隆路", "松仁路"]
	var znames := ["市民大道", "忠孝東路", "仁愛路", "信義路", "和平東路", "辛亥路"]
	var ids := _grid(net, xs, zs,
		func(i): return {"name": xnames[i], "lanes": 2 if i in [0, 3, 5] else 1, "limit": 50, "kind": "city", "median": 2.0 if i == 3 else 0.3},
		func(j): return {"name": znames[j], "lanes": 2 if j in [1, 2, 3] else 1, "limit": 50, "kind": "city", "median": 3.0 if j == 2 else 0.3})
	var lm := [
		{"type": "tw101", "pos": Vector2(325, 0), "name": "台北101"},
		{"type": "memorial_hall", "pos": Vector2(195, 130), "name": "國父紀念館"},
		{"type": "presidential", "pos": Vector2(-325, 0), "name": "總統府"},
		{"type": "cks_gate", "pos": Vector2(-325, 130), "name": "自由廣場"},
		{"type": "station", "pos": Vector2(-325, -260), "name": "台北車站"},
		{"type": "park", "pos": Vector2(-65, 260), "name": "大安森林公園"},
		{"type": "warehouse", "pos": Vector2(325, 260), "name": "小柯物流倉庫"},
	]
	var pois := []
	for l in lm:
		pois.append({"name": l.name, "pos": l.pos + Vector2(0, 65)})
	pois.append({"name": "西門町", "pos": Vector2(-260, -195)})
	var skip := []
	for l in lm:
		skip.append(l.pos)
	var signs := []
	# 每條路段放速限與其他標誌
	for e in net.edges.size():
		var d: Dictionary = net.edges[e]
		if e % 3 == 0:
			signs.append(_sign(e, false, 0.35, "speed", d.limit))
		elif e % 7 == 1:
			signs.append(_sign(e, true, 0.4, "no_parking"))
		elif e % 11 == 2:
			signs.append(_sign(e, false, 0.5, "school"))
		elif e % 13 == 4:
			signs.append(_sign(e, true, 0.5, "ped"))
		elif e % 17 == 5:
			signs.append(_sign(e, false, 0.6, "no_uturn"))
		elif e % 19 == 6:
			signs.append(_sign(e, true, 0.6, "no_left"))
	return {"net": net, "pois": pois, "landmarks": lm, "blocks": _blocks(xs, zs, skip),
		"spawn": {"node": ids[6][4], "next": ids[5][4]}, "ground": Color(0.42, 0.44, 0.4), "biome": "city",
		"signs": signs, "sky": "city", "scooters": true, "density": 1.0}


# ---------------------------------------------------------------- 國道一號
static func _freeway() -> Dictionary:
	var net := RoadNet.new()
	# 起點小鎮（南端）
	var txs := [-240.0, -120.0, 0.0]
	var tzs := [0.0, 120.0, 240.0]
	var town := _grid(net, txs, tzs,
		func(_i): return {"lanes": 1, "limit": 40, "kind": "city", "name": "工業區路"},
		func(_j): return {"lanes": 1, "limit": 40, "kind": "city", "name": "倉庫街"})
	# 國道主線，往北（-Z）約 4.5 公里
	var main_ids := []
	var hopts := {"lanes": 3, "lane_w": 3.75, "limit": 100, "kind": "highway", "median": 2.4, "name": "國道一號"}
	for k in 46:
		var z := 60.0 - k * 100.0
		var x := 160.0 + 260.0 * sin(k * 0.16) + 80.0 * sin(k * 0.41)
		main_ids.append(net.add_node(Vector2(x, z)))
	net.add_path(main_ids, hopts)
	# 交流道：小鎮東北角 → 主線第 2 點
	var ramp1 := net.add_node(Vector2(80, -20))
	net.add_edge(town[2][0], ramp1, {"lanes": 1, "limit": 60, "kind": "ramp", "name": "交流道"})
	net.add_edge(ramp1, main_ids[2], {"lanes": 1, "limit": 60, "kind": "ramp", "name": "交流道"})
	# 服務區（主線第 22 點東側）
	var sa: Vector2 = net.nodes[main_ids[22]] + Vector2(150, 0)
	var sa1 := net.add_node(net.nodes[main_ids[21]] + Vector2(70, 0))
	var sa2 := net.add_node(sa + Vector2(0, 60))
	var sa3 := net.add_node(sa + Vector2(0, -60))
	var sa4 := net.add_node(net.nodes[main_ids[23]] + Vector2(70, 0))
	var so := {"lanes": 1, "limit": 30, "kind": "yard", "name": "服務區聯絡道"}
	net.add_edge(main_ids[21], sa1, so)
	net.add_edge(sa1, sa2, so)
	net.add_edge(sa2, sa3, so)
	net.add_edge(sa3, sa4, so)
	net.add_edge(sa4, main_ids[23], so)
	# 終點：台中物流中心（北端）
	var end_p: Vector2 = net.nodes[main_ids[45]]
	var dxs := [end_p.x - 120.0, end_p.x, end_p.x + 120.0]
	var dzs := [end_p.y - 260.0, end_p.y - 140.0]
	var ramp2 := net.add_node(end_p + Vector2(0, -70))
	net.add_edge(main_ids[45], ramp2, {"lanes": 1, "limit": 60, "kind": "ramp", "name": "交流道"})
	var dest := _grid(net, dxs, dzs,
		func(_i): return {"lanes": 1, "limit": 40, "kind": "city", "name": "港埠路"},
		func(_j): return {"lanes": 1, "limit": 40, "kind": "city", "name": "物流大道"})
	net.add_edge(ramp2, dest[1][1], {"lanes": 1, "limit": 50, "kind": "city", "name": "港埠路"})
	var signs := []
	for k in range(3, 45, 4):
		var e := net.edge_between(main_ids[k], main_ids[k + 1])
		signs.append(_sign(e, false, 0.3, "speed", 100 if k % 8 != 3 else 90))
	for k in [8, 30]:
		signs.append(_sign(net.edge_between(main_ids[k], main_ids[k + 1]), false, 0.5, "keep_right"))
	signs.append(_sign(net.edge_between(main_ids[19], main_ids[20]), false, 0.4, "guide", 0))
	signs.append(_sign(net.edge_between(main_ids[42], main_ids[43]), false, 0.4, "guide", 1))
	signs.append(_sign(net.edge_between(main_ids[14], main_ids[15]), false, 0.5, "curve_r"))
	signs.append(_sign(net.edge_between(main_ids[35], main_ids[36]), false, 0.5, "slow"))
	var gantries := []
	for k in [6, 18, 32, 41]:
		gantries.append({"type": "gantry", "pos": (net.nodes[main_ids[k]] + net.nodes[main_ids[k + 1]]) * 0.5,
			"rot": atan2(net.nodes[main_ids[k + 1]].x - net.nodes[main_ids[k]].x, net.nodes[main_ids[k + 1]].y - net.nodes[main_ids[k]].y)})
	var lm := [
		{"type": "warehouse", "pos": Vector2(-180, 180), "name": "林口物流倉庫"},
		{"type": "service_area", "pos": sa + Vector2(45, 0), "name": "泰安服務區"},
		{"type": "warehouse", "pos": Vector2(end_p.x - 60, end_p.y - 200), "name": "台中物流中心"},
	]
	lm.append_array(gantries)
	return {"net": net, "landmarks": lm,
		"pois": [{"name": "林口物流倉庫", "node": town[0][1]}, {"name": "泰安服務區", "node": sa2},
			{"name": "台中物流中心", "node": dest[0][0]}],
		"blocks": _blocks(txs, tzs, [Vector2(-180, 180)]) + _blocks(dxs, dzs, [Vector2(end_p.x - 60, end_p.y - 200)]),
		"spawn": {"node": town[0][1], "next": town[1][1]}, "ground": Color(0.36, 0.5, 0.3), "biome": "rural",
		"signs": signs, "sky": "clear", "mountains": true, "density": 0.8, "trees": true}


# ---------------------------------------------------------------- 日月潭
static func _lake_r(th: float) -> float:
	return 430.0 + 60.0 * sin(3.0 * th) + 32.0 * sin(5.0 * th + 1.0)


static func _sunmoon() -> Dictionary:
	var net := RoadNet.new()
	var ring := []
	var N := 60
	for k in N:
		var th := TAU * k / N
		ring.append(net.add_node(Vector2(cos(th), sin(th)) * _lake_r(th)))
	var opts := {"lanes": 1, "limit": 40, "kind": "rural", "name": "台 21 線環湖公路", "median": 0.3}
	for k in N:
		net.add_edge(ring[k], ring[(k + 1) % N], opts)
	var spur := func(k: int, length: float, name: String) -> int:
		var th := TAU * k / N
		var p: Vector2 = net.nodes[ring[k]]
		var mid := net.add_node(p + Vector2(cos(th), sin(th)) * length * 0.5 + Vector2(-sin(th), cos(th)) * 12.0)
		var end := net.add_node(p + Vector2(cos(th), sin(th)) * length)
		net.add_path([ring[k], mid, end], {"lanes": 1, "limit": 30, "kind": "rural", "name": name})
		return end
	var pagoda: int = spur.call(40, 170.0, "慈恩塔步道口")
	var temple: int = spur.call(8, 120.0, "文武廟聯絡道")
	var center: int = spur.call(25, 140.0, "向山遊客中心")
	# 湖水
	var lake := PackedVector2Array()
	for k in 96:
		var th := TAU * k / 96.0
		lake.append(Vector2(cos(th), sin(th)) * (_lake_r(th) - 22.0))
	var land := func(k: int, d: float) -> Vector2:
		var th := TAU * k / N
		return Vector2(cos(th), sin(th)) * (_lake_r(th) + d)
	var lm := [
		{"type": "pagoda", "pos": land.call(40, 205.0), "name": "慈恩塔"},
		{"type": "temple", "pos": land.call(8, 155.0), "name": "文武廟"},
		{"type": "visitor", "pos": land.call(25, 175.0), "name": "向山遊客中心"},
		{"type": "wharf", "pos": land.call(52, -40.0), "rot": -TAU * 52 / N + PI * 0.5, "name": "水社碼頭"},
		{"type": "wharf", "pos": land.call(17, -40.0), "rot": -TAU * 17 / N + PI * 0.5, "name": "伊達邵碼頭"},
		{"type": "island", "pos": Vector2(60, -40), "name": "拉魯島"},
	]
	var signs := []
	for k in range(1, N, 5):
		var e := net.edge_between(ring[k], ring[(k + 1) % N])
		var types := ["speed", "curve_l", "slow", "curve_r", "rock", "speed", "animal", "no_overtake"]
		var tp: String = types[(k / 5) % types.size()]
		signs.append(_sign(e, k % 2 == 0, 0.5, tp, 40))
	return {"net": net, "landmarks": lm, "water": [lake],
		"pois": [{"name": "水社碼頭", "node": ring[52]}, {"name": "伊達邵碼頭", "node": ring[17]},
			{"name": "慈恩塔", "node": pagoda}, {"name": "文武廟", "node": temple}, {"name": "向山遊客中心", "node": center}],
		"spawn": {"node": ring[52], "next": ring[53]}, "ground": Color(0.3, 0.48, 0.26), "biome": "lake",
		"signs": signs, "sky": "clear", "mountains": true, "density": 0.5, "trees": true}


# ---------------------------------------------------------------- 高雄港都
static func _kaohsiung() -> Dictionary:
	var net := RoadNet.new()
	var xs := [-420.0, -280.0, -140.0, 0.0, 140.0, 280.0]
	var zs := [-280.0, -140.0, 0.0, 140.0, 280.0]
	var xnames := ["臨海路", "七賢路", "河東路", "中山路", "民族路", "博愛路"]
	var znames := ["建國路", "中正路", "五福路", "成功路", "三多路"]
	var ids := _grid(net, xs, zs,
		func(i): return {"name": xnames[i], "lanes": 2 if i in [0, 3] else 1, "limit": 50, "kind": "city"},
		func(j): return {"name": znames[j], "lanes": 2 if j in [1, 2] else 1, "limit": 50, "kind": "city"})
	# 愛河在 x = -210 附近，過河的路段是橋
	for e in net.edges.size():
		var d: Dictionary = net.edges[e]
		var a: Vector2 = net.nodes[d.a]
		var b: Vector2 = net.nodes[d.b]
		if minf(a.x, b.x) < -210.0 and maxf(a.x, b.x) > -210.0:
			d.bridge = true
	# 港區：臨海路往西到貨櫃場
	var y1 := net.add_node(Vector2(-560, 0))
	var y2 := net.add_node(Vector2(-560, -200))
	var y3 := net.add_node(Vector2(-560, 200))
	var yo := {"lanes": 2, "limit": 40, "kind": "yard", "name": "港區道路"}
	net.add_edge(ids[0][2], y1, yo)
	net.add_edge(y1, y2, yo)
	net.add_edge(y1, y3, yo)
	var river := PackedVector2Array([Vector2(-225, -700), Vector2(-195, -700), Vector2(-190, 0), Vector2(-200, 700),
		Vector2(-230, 700), Vector2(-222, 0)])
	var sea := PackedVector2Array([Vector2(-700, -900), Vector2(-640, -900), Vector2(-640, 900), Vector2(-700, 900),
		Vector2(-1600, 900), Vector2(-1600, -900)])
	var lm := [
		{"type": "tower85", "pos": Vector2(210, 70), "name": "85 大樓"},
		{"type": "pier2", "pos": Vector2(-350, 210), "name": "駁二藝術特區"},
		{"type": "cranes", "pos": Vector2(-620, 0), "name": "港區起重機"},
		{"type": "container_yard", "pos": Vector2(-600, -150), "name": "貨櫃場"},
		{"type": "warehouse", "pos": Vector2(210, -210), "name": "小柯物流倉庫"},
		{"type": "park", "pos": Vector2(-70, 210), "name": "中央公園"},
	]
	var skip := [Vector2(210, 70), Vector2(-350, 210), Vector2(210, -210), Vector2(-70, 210)]
	var blocks := []
	for r in _blocks(xs, zs, skip):
		var rr: Rect2 = r
		if rr.position.x < -210.0 and rr.end.x > -210.0:   # 愛河穿過的街廓切成兩半
			blocks.append(Rect2(rr.position, Vector2(-235.0 - rr.position.x, rr.size.y)))
			blocks.append(Rect2(Vector2(-185.0, rr.position.y), Vector2(rr.end.x + 185.0, rr.size.y)))
		else:
			blocks.append(rr)
	var signs := []
	for e in net.edges.size():
		if e % 3 == 0:
			signs.append(_sign(e, false, 0.35, "speed", net.edges[e].limit))
		elif e % 5 == 1:
			signs.append(_sign(e, true, 0.45, "truck_route"))
		elif e % 9 == 2:
			signs.append(_sign(e, false, 0.5, "no_parking"))
		elif e % 11 == 3:
			signs.append(_sign(e, true, 0.5, "ped"))
	return {"net": net, "landmarks": lm, "water": [river, sea], "blocks": blocks,
		"pois": [{"name": "85 大樓", "pos": Vector2(210, 140)}, {"name": "駁二藝術特區", "pos": Vector2(-280, 280)},
			{"name": "港區貨櫃場", "node": y2}, {"name": "小柯物流倉庫", "pos": Vector2(140, -140)},
			{"name": "中央公園", "pos": Vector2(0, 280)}],
		"spawn": {"node": ids[4][1], "next": ids[3][1]}, "ground": Color(0.45, 0.45, 0.42), "biome": "city",
		"signs": signs, "sky": "city", "scooters": true, "density": 0.9}


# ---------------------------------------------------------------- 太魯閣
static func _taroko() -> Dictionary:
	var net := RoadNet.new()
	# 從東邊牌樓往西進峽谷，蜿蜒前進
	var pts := []
	var p := Vector2(900, 0)
	var heading := PI          # 朝 -X
	for k in 70:
		pts.append(p)
		heading += 0.22 * sin(k * 0.37) + 0.12 * sin(k * 0.91 + 0.5)
		heading = clampf(heading, PI * 0.55, PI * 1.45)
		p += Vector2(cos(heading), sin(heading)) * 45.0
	var ids := []
	for q in pts:
		ids.append(net.add_node(q))
	var e_ids := net.add_path(ids, {"lanes": 1, "limit": 40, "kind": "mountain", "name": "台 8 線中橫公路", "median": 0.3})
	# 隧道
	for k in [14, 15, 16, 31, 32, 47, 48, 49, 58]:
		net.edges[e_ids[k]].tunnel = true
	# 牌樓前的小路口（停車場）
	var lot := net.add_node(pts[0] + Vector2(60, 40))
	net.add_edge(ids[0], lot, {"lanes": 1, "limit": 20, "kind": "yard", "name": "遊客中心停車場"})
	var river := PackedVector2Array()
	var river_b := PackedVector2Array()
	for k in pts.size():
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[mini(k + 1, pts.size() - 1)]
		var dir: Vector2 = (b - a).normalized() if k < pts.size() - 1 else (a - pts[k - 1]).normalized()
		var right := Vector2(-dir.y, dir.x)
		river.append(a - right * 22.0)
		river_b.append(a - right * 50.0)
	river_b.reverse()
	var river_poly := river + river_b
	var lm := [
		{"type": "taroko_gate", "pos": pts[0] + Vector2(-25, 0), "rot": PI * 0.5, "name": "太魯閣牌樓"},
		{"type": "shrine", "pos": pts[10] + Vector2(0, -40), "name": "長春祠"},
		{"type": "suspension", "pos": pts[38], "name": "燕子口"},
		{"type": "pagoda", "pos": pts[69] + Vector2(-40, 30), "name": "天祥祥德寺"},
	]
	var signs := []
	var types := ["curve_l", "rock", "speed", "curve_r", "tunnel", "slow", "no_overtake", "rock", "horn"]
	for k in range(2, 68, 4):
		var tp: String = types[(k / 4) % types.size()]
		signs.append(_sign(e_ids[k], false, 0.4, tp, 40))
	for k in [13, 30, 46, 57]:
		signs.append(_sign(e_ids[k], false, 0.3, "tunnel"))
	return {"net": net, "landmarks": lm, "water": [river_poly],
		"pois": [{"name": "太魯閣牌樓", "node": ids[0]}, {"name": "長春祠", "node": ids[10]},
			{"name": "燕子口", "node": ids[38]}, {"name": "天祥", "node": ids[69]}],
		"spawn": {"node": lot, "next": ids[0]}, "ground": Color(0.38, 0.42, 0.33), "biome": "canyon",
		"signs": signs, "sky": "clear", "mountains": true, "canyon": true, "density": 0.35, "trees": true}


# ---------------------------------------------------------------- 墾丁
static func _kenting() -> Dictionary:
	var net := RoadNet.new()
	# 海岸公路（台 26 線）由西往東，再往南到鵝鑾鼻
	var pts := []
	for k in 30:
		var x := -1200.0 + k * 70.0
		var z := 40.0 * sin(k * 0.35) + (0.0 if k < 18 else (k - 18) * 12.0)
		pts.append(Vector2(x, z))
	var coast := _chain(net, pts, {"lanes": 1, "limit": 50, "kind": "rural", "name": "台 26 線屏鵝公路"})
	# 墾丁大街：在中段北側的小方格
	var sx := [-460.0, -360.0, -260.0]
	var sz := [-160.0, -60.0]
	var town := _grid(net, sx, sz,
		func(_i): return {"lanes": 1, "limit": 30, "kind": "city", "name": "墾丁路"},
		func(j): return {"lanes": 1, "limit": 30, "kind": "city", "name": "墾丁大街" if j == 1 else "大灣路"})
	net.add_edge(town[1][1], coast[11], {"lanes": 1, "limit": 30, "kind": "city", "name": "墾丁路"})
	# 往南的燈塔支線
	var tip: Vector2 = pts[29]
	var lt := _chain(net, [tip + Vector2(40, 90), tip + Vector2(30, 190), tip + Vector2(70, 280)],
		{"lanes": 1, "limit": 40, "kind": "rural", "name": "鵝鑾鼻公園路"})
	net.add_edge(coast[29], lt[0], {"lanes": 1, "limit": 40, "kind": "rural", "name": "鵝鑾鼻公園路"})
	var sea := PackedVector2Array([Vector2(-1500, 110), Vector2(-500, 120), Vector2(200, 160), Vector2(500, 200),
		Vector2(560, 500), Vector2(820, 520), Vector2(900, 2000), Vector2(-1500, 2000)])
	var lm := [
		{"type": "lighthouse", "pos": tip + Vector2(110, 320), "name": "鵝鑾鼻燈塔"},
		{"type": "sail_rock", "pos": Vector2(250, 260), "name": "船帆石"},
		{"type": "night_market", "pos": Vector2(-360, -60), "name": "墾丁大街夜市"},
		{"type": "beach", "pos": Vector2(-700, 150), "name": "南灣"},
	]
	var signs := []
	for k in range(1, 28, 3):
		var types := ["speed", "curve_r", "ped", "animal", "slow", "no_parking", "curve_l"]
		signs.append(_sign(net.edge_between(coast[k], coast[k + 1]), k % 2 == 1, 0.5, types[(k / 3) % types.size()], 50))
	return {"net": net, "landmarks": lm, "water": [sea],
		"blocks": [Rect2(-460, -160, 100, 100), Rect2(-360, -160, 100, 100)],
		"pois": [{"name": "墾丁大街", "node": town[1][1]}, {"name": "南灣", "node": coast[7]},
			{"name": "船帆石", "node": coast[21]}, {"name": "鵝鑾鼻燈塔", "node": lt[2]}],
		"spawn": {"node": coast[0], "next": coast[1]}, "ground": Color(0.42, 0.55, 0.3), "biome": "coast",
		"signs": signs, "sky": "clear", "mountains": true, "density": 0.5, "trees": true, "scooters": true}


# ---------------------------------------------------------------- 駕訓場
static func _school() -> Dictionary:
	var net := RoadNet.new()
	var o := {"lanes": 1, "limit": 30, "kind": "city", "name": "練習道", "walk": false}
	# 外圈 4 個角＋中間十字路口（有紅綠燈）
	var c00 := net.add_node(Vector2(-200, -150))
	var c10 := net.add_node(Vector2(0, -150))
	var c20 := net.add_node(Vector2(200, -150))
	var c01 := net.add_node(Vector2(-200, 0))
	var c11 := net.add_node(Vector2(0, 0))
	var c21 := net.add_node(Vector2(200, 0))
	var c02 := net.add_node(Vector2(-200, 150))
	var c12 := net.add_node(Vector2(0, 150))
	var c22 := net.add_node(Vector2(200, 150))
	for pr in [[c00, c10], [c10, c20], [c00, c01], [c20, c21], [c01, c11], [c11, c21], [c10, c11], [c11, c12],
			[c01, c02], [c21, c22], [c12, c22]]:
		net.add_edge(pr[0], pr[1], o)
	# 左下：S 彎（c02 → c12）
	var s_pts := []
	for k in range(1, 12):
		var x := -200.0 + k * 200.0 / 12.0
		s_pts.append(Vector2(x, 150.0 + 28.0 * sin(k * TAU / 12.0)))
	var s_ids := []
	for q in s_pts:
		s_ids.append(net.add_node(q))
	net.add_path([c02] + s_ids + [c12], {"lanes": 1, "limit": 20, "kind": "yard", "name": "S 彎道", "lane_w": 3.6})
	var lm := [
		{"type": "school_bldg", "pos": Vector2(-100, -75), "name": "小柯駕訓班"},
		{"type": "parking_bays", "pos": Vector2(100, -75), "name": "倒車入庫場"},
		{"type": "parking_street", "pos": Vector2(100, 75), "name": "路邊停車場"},
	]
	# 倒車入庫車位：在 c10–c11 道路東側
	var parking := [
		{"kind": "bay", "pos": Vector2(29, -75), "yaw": PI * 0.5, "size": Vector2(4.6, 19.5), "name": "倒車入庫車位"},
		{"kind": "street", "pos": Vector2(100, 6.6), "yaw": PI * 0.5, "size": Vector2(3.0, 22.0), "name": "路邊停車格"},
	]
	var signs := [
		_sign(net.edge_between(c00, c10), false, 0.4, "speed", 30),
		_sign(net.edge_between(c10, c11), false, 0.5, "slow"),
		_sign(net.edge_between(c01, c11), false, 0.5, "stop_ahead"),
		_sign(net.edge_between(c11, c12), false, 0.4, "no_left"),
		_sign(net.edge_between(c20, c21), false, 0.5, "ped"),
		_sign(net.edge_between(c21, c22), false, 0.5, "curve_l"),
	]
	return {"net": net, "landmarks": lm, "parking": parking, "lights": [c11],
		"stops": [{"node": c21, "edge": net.edge_between(c20, c21)}],
		"pois": [{"name": "中央路口", "node": c11}, {"name": "S 彎道", "node": c02}, {"name": "倒車入庫場", "node": c10},
			{"name": "路邊停車場", "node": c21}],
		"spawn": {"node": c00, "next": c10}, "ground": Color(0.4, 0.52, 0.32), "biome": "school",
		"signs": signs, "sky": "clear", "density": 0.15, "trees": true}
