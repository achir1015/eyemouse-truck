class_name RoadNet
extends RefCounted
## 道路網：節點（XZ 平面座標）＋路段。靠右行駛（台灣），車道從中線往右數。
## 座標：Vector2(x, z)，Godot 世界 Y 朝上，車頭朝 -Z。

const CELL := 40.0

var nodes: Array[Vector2] = []
var edges: Array[Dictionary] = []
var adj: Array = []                 # 節點 -> [edge id]
var node_r: Array[float] = []       # 路口鋪面半徑
var node_light: Array = []          # 節點 -> 紅綠燈資料（Dictionary）或 null
var node_stop: Array = []           # 節點 -> 停車再開（停字）方向 Array[edge]
var _grid := {}


func add_node(p: Vector2) -> int:
	nodes.append(p)
	adj.append([])
	node_r.append(0.0)
	node_light.append(null)
	node_stop.append([])
	return nodes.size() - 1


## opts：lanes（單向車道數）、lane_w、limit（km/h）、kind（city/highway/mountain/rural/yard）、name、median（中央分隔寬）、oneway
func add_edge(a: int, b: int, opts := {}) -> int:
	var e := {
		"a": a, "b": b,
		"lanes": int(opts.get("lanes", 1)),
		"lane_w": float(opts.get("lane_w", 3.5)),
		"limit": int(opts.get("limit", 50)),
		"kind": str(opts.get("kind", "city")),
		"name": str(opts.get("name", "")),
		"median": float(opts.get("median", 0.3)),
		"oneway": bool(opts.get("oneway", false)),
		"walk": bool(opts.get("walk", str(opts.get("kind", "city")) == "city")),
		"tunnel": bool(opts.get("tunnel", false)),
		"bridge": bool(opts.get("bridge", false)),
	}
	e.len = nodes[a].distance_to(nodes[b])
	e.dir = (nodes[b] - nodes[a]).normalized()
	edges.append(e)
	var id := edges.size() - 1
	adj[a].append(id)
	adj[b].append(id)
	return id


## 連成一條線（多點），回傳 edge id 陣列
func add_path(ids: Array, opts := {}) -> Array:
	var out := []
	for i in ids.size() - 1:
		out.append(add_edge(ids[i], ids[i + 1], opts))
	return out


func half_width(e: int) -> float:
	var d: Dictionary = edges[e]
	if d.oneway:
		return d.lanes * d.lane_w * 0.5 + 0.6
	return d.lanes * d.lane_w + d.median * 0.5 + 0.6


func other(e: int, n: int) -> int:
	return edges[e].b if edges[e].a == n else edges[e].a


func degree(n: int) -> int:
	return adj[n].size()


func is_junction(n: int) -> bool:
	return adj[n].size() >= 3


## 建立索引、路口半徑。所有路段加完後呼叫。
func finalize() -> void:
	for n in nodes.size():
		var r := 0.0
		for e in adj[n]:
			r = maxf(r, half_width(e))
		if is_junction(n):
			r += 1.5
		node_r[n] = r
	_grid.clear()
	for e in edges.size():
		var a: Vector2 = nodes[edges[e].a]
		var b: Vector2 = nodes[edges[e].b]
		var hw := half_width(e) + 4.0
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(hw, hw)
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(hw, hw)
		for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
			for cz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
				var k := Vector2i(cx, cz)
				if not _grid.has(k):
					_grid[k] = []
				_grid[k].append(e)


func edges_near(p: Vector2) -> Array:
	return _grid.get(Vector2i(floori(p.x / CELL), floori(p.y / CELL)), [])


## 查詢某點最近的路段：{edge, t(0..1), along(m), lat(+在 a→b 右側), dist, on_road, node(在路口內的節點或 -1)}
func query(p: Vector2) -> Dictionary:
	var best := {"edge": -1, "dist": 1e9, "on_road": false, "node": -1, "t": 0.0, "lat": 0.0, "along": 0.0}
	for e in edges_near(p):
		var d: Dictionary = edges[e]
		var a: Vector2 = nodes[d.a]
		var rel := p - a
		var along := clampf(rel.dot(d.dir), 0.0, d.len)
		var foot: Vector2 = a + d.dir * along
		var dist := p.distance_to(foot)
		if dist < best.dist:
			var right := Vector2(-d.dir.y, d.dir.x)
			best = {"edge": e, "dist": dist, "t": along / maxf(d.len, 0.01), "along": along,
				"lat": rel.dot(right), "on_road": dist <= half_width(e), "node": -1}
	if best.edge >= 0:
		for n in [edges[best.edge].a, edges[best.edge].b]:
			if p.distance_to(nodes[n]) <= node_r[n]:
				best.on_road = true
				if is_junction(n):
					best.node = n
	return best


## 車道中心點：沿 from 節點出發方向，第 lane 條車道（0 = 最內側），t = 0..1
func lane_point(e: int, from: int, lane: int, t: float) -> Vector2:
	var d: Dictionary = edges[e]
	var a: Vector2 = nodes[from]
	var b: Vector2 = nodes[other(e, from)]
	var dir := (b - a).normalized()
	var right := Vector2(-dir.y, dir.x)
	var off: float
	if d.oneway:
		off = (lane + 0.5 - d.lanes * 0.5) * d.lane_w
	else:
		off = d.median * 0.5 + (lane + 0.5) * d.lane_w
	return a.lerp(b, t) + right * off


## 這條路段從 from 出發可不可以走（單行道）
func can_go(e: int, from: int) -> bool:
	return not edges[e].oneway or edges[e].a == from


## 從路口 from 沿路段 e 出發時，離開路口的 t（避開路口鋪面）
func t_out(e: int, from: int) -> float:
	return clampf(node_r[from] / maxf(edges[e].len, 0.1), 0.0, 0.45)


func t_in(e: int, to: int) -> float:
	return 1.0 - clampf(node_r[to] / maxf(edges[e].len, 0.1), 0.0, 0.45)


## A* 找路徑（節點序列）
func find_path(start: int, goal: int, avoid_first_edge := -1) -> Array:
	if start == goal:
		return [start]
	var open := {start: true}
	var came := {}
	var g := {start: 0.0}
	var f := {start: nodes[start].distance_to(nodes[goal])}
	var guard := 0
	while open.size() > 0 and guard < 20000:
		guard += 1
		var cur := -1
		var cf := 1e18
		for k in open:
			if f[k] < cf:
				cf = f[k]
				cur = k
		if cur == goal:
			var path := [cur]
			while came.has(cur):
				cur = came[cur]
				path.push_front(cur)
			return path
		open.erase(cur)
		for e in adj[cur]:
			if not can_go(e, cur):
				continue
			if cur == start and e == avoid_first_edge:
				continue
			var nb := other(e, cur)
			var cost: float = edges[e].len / maxf(float(edges[e].limit), 20.0) * 50.0 + edges[e].len * 0.3
			var ng: float = g[cur] + cost
			if not g.has(nb) or ng < g[nb]:
				g[nb] = ng
				came[nb] = cur
				f[nb] = ng + nodes[nb].distance_to(nodes[goal]) * 0.3
				open[nb] = true
	return []


func edge_between(a: int, b: int) -> int:
	for e in adj[a]:
		if other(e, a) == b:
			return e
	return -1


## 節點序列 → 路段序列
func path_edges(path: Array) -> Array:
	var out := []
	for i in path.size() - 1:
		out.append(edge_between(path[i], path[i + 1]))
	return out


func nearest_node(p: Vector2, junction_only := false) -> int:
	var best := -1
	var bd := 1e18
	for n in nodes.size():
		if junction_only and not is_junction(n):
			continue
		var d := p.distance_squared_to(nodes[n])
		if d < bd:
			bd = d
			best = n
	return best


## 轉彎方向：從 a→n 進入、n→b 離開。回傳角度（度，+右轉 −左轉）
func turn_angle(a: int, n: int, b: int) -> float:
	var d1 := (nodes[n] - nodes[a]).normalized()
	var d2 := (nodes[b] - nodes[n]).normalized()
	var cross := d1.x * d2.y - d1.y * d2.x
	return rad_to_deg(atan2(cross, d1.dot(d2)))


func bounds() -> Rect2:
	var r := Rect2(nodes[0], Vector2.ZERO)
	for p in nodes:
		r = r.expand(p)
	return r
