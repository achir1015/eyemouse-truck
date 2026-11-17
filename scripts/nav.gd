class_name Nav
extends RefCounted
## 導航：路徑規劃、轉彎提示（語音）、偏離重新規劃、抵達判斷。

signal arrived
signal rerouted

var net: RoadNet
var path: Array = []          # 節點序列
var edges: Array = []         # 路段序列
var idx := 0                  # 目前在第幾段
var dest := -1
var dest_name := ""
var active := false
var remain := 0.0             # 剩餘距離（m）
var next_turn := ""           # left / right / straight / uturn / arrive
var next_dist := 0.0
var next_node := -1
var next_road := ""
var _said := {}               # 已念過的提示
var _off_t := 0.0
var _arrived := false
var log: Array = []           # 測試用：導航語音


func _init(n: RoadNet) -> void:
	net = n


func set_dest(from_pos: Vector2, heading: Vector2, node: int, name: String) -> bool:
	dest = node
	dest_name = name
	_arrived = false
	active = plan(from_pos, heading)
	return active


## 從目前位置規劃：找最近路段，往行駛方向那一端出發
func plan(p: Vector2, heading: Vector2) -> bool:
	var q := net.query(p)
	if q.edge < 0:
		return false
	var d: Dictionary = net.edges[q.edge]
	var forward_b: bool = d.dir.dot(heading) >= 0.0
	var start: int = d.b if forward_b else d.a
	var back: int = d.a if forward_b else d.b
	if start == dest:
		path = [back, dest]
	else:
		var sub := net.find_path(start, dest)
		if sub.is_empty():
			# 往回走試試
			sub = net.find_path(back, dest)
			if sub.is_empty():
				return false
			path = [start] + sub
		else:
			path = [back] + sub
	edges = net.path_edges(path)
	idx = 0
	_said.clear()
	_compute(p)
	return true


func clear() -> void:
	active = false
	path = []
	edges = []
	dest = -1


## 每格更新
func update(p: Vector2, heading: Vector2, dt: float, speed: float) -> void:
	if not active or edges.is_empty():
		return
	# 找目前所在的路段（往前看幾段）
	var best := idx
	var bd := 1e9
	for i in range(idx, mini(idx + 4, edges.size())):
		var e: int = edges[i]
		if e < 0:
			continue
		var dist := _dist_to_edge(p, e)
		if dist < bd - 0.5:
			bd = dist
			best = i
	if best != idx:
		idx = best
	var e_cur: int = edges[idx]
	var hw := net.half_width(e_cur) if e_cur >= 0 else 6.0
	if bd > hw + 18.0:
		_off_t += dt
		if _off_t > 2.0:
			_off_t = 0.0
			if plan(p, heading):
				rerouted.emit()
				_say("nav_reroute")
			return
	else:
		_off_t = 0.0
	_compute(p)
	# 抵達
	if not _arrived and p.distance_to(net.nodes[dest]) < maxf(net.node_r[dest], 8.0) + 14.0 and (idx >= edges.size() - 1):
		_arrived = true
		_say("nav_arrive")
		arrived.emit()
		active = false
		return
	# 語音提示
	if next_turn in ["left", "right", "uturn"]:
		var key := "%d_%s" % [next_node, next_turn]
		for th in [500, 300, 100]:
			if next_dist < th + 15 and next_dist > th - 60 and not _said.has(key + str(th)) and (th == 100 or speed > 8.0 or th == 300):
				_said[key + str(th)] = true
				_say("nav_%d_%s" % [th, next_turn])
				break
		if next_dist < 30 and not _said.has(key + "now"):
			_said[key + "now"] = true
			_say("nav_now_" + next_turn)
	elif next_turn == "arrive":
		var key2 := "arrive%d" % dest
		if next_dist < 320 and next_dist > 150 and not _said.has(key2 + "300"):
			_said[key2 + "300"] = true
			_say("nav_300_arrive")
		elif next_dist < 100 and not _said.has(key2 + "100"):
			_said[key2 + "100"] = true
			_say("nav_100_arrive")


func _say(id: String) -> void:
	log.append(id)
	if bool(App.settings.nav_voice):
		Snd.say(id)


func _dist_to_edge(p: Vector2, e: int) -> float:
	var a: Vector2 = net.nodes[net.edges[e].a]
	var b: Vector2 = net.nodes[net.edges[e].b]
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


## 計算剩餘距離與下一個轉彎
func _compute(p: Vector2) -> void:
	if edges.is_empty():
		return
	var to_node: int = path[idx + 1]
	var dist := p.distance_to(net.nodes[to_node])
	remain = dist
	for i in range(idx + 1, edges.size()):
		remain += net.edges[edges[i]].len
	next_turn = "arrive"
	next_dist = remain
	next_node = dest
	var acc := dist
	for i in range(idx + 1, path.size() - 1):
		var n: int = path[i]
		var ang := net.turn_angle(path[i - 1], n, path[i + 1])
		if net.is_junction(n) or absf(ang) > 100.0:
			if absf(ang) > 150.0:
				next_turn = "uturn"
			elif ang > 32.0:
				next_turn = "right"
			elif ang < -32.0:
				next_turn = "left"
			else:
				next_turn = "straight"
			if next_turn != "straight":
				next_dist = acc
				next_node = n
				next_road = str(net.edges[edges[i]].name)
				return
		acc += net.edges[edges[i]].len
	next_dist = remain
	next_node = dest


## 路徑折線（畫在平板上）
func polyline() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(idx, path.size()):
		out.append(net.nodes[path[i]])
	return out


func eta_min(speed_avg_kmh: float) -> float:
	return remain / 1000.0 / maxf(speed_avg_kmh, 20.0) * 60.0


static func turn_text(t: String) -> String:
	return {"left": "左轉", "right": "右轉", "straight": "直行", "uturn": "迴轉", "arrive": "抵達目的地"}.get(t, "")
