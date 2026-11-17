class_name Autopilot
extends RefCounted
## 小柯 AI 自駕：沿導航路線的車道行駛（純追蹤轉向），依速限、彎道、紅綠燈、停字、前車、目的地調整速度。
## mode：off / lka（只幫忙轉向＝車道維持）/ full（全自動）

var veh: Vehicle
var world: World
var nav: Nav
var traffic: Traffic
var mode := "off"
var status := ""              # 目前在做什麼（顯示給使用者）
var target_kmh := 0.0
var line := PackedVector2Array()
var _stop_wait := {}          # 停字：已停過的節點
var _stop_t := 0.0


func _init(v: Vehicle, w: World, n: Nav, t: Traffic) -> void:
	veh = v
	world = w
	nav = n
	traffic = t


func _lane_for(i: int) -> int:
	var e: int = nav.edges[i]
	var lanes: int = world.net.edges[e].lanes
	if lanes <= 1:
		return 0
	# 這段路結束時要轉哪邊
	if i + 2 < nav.path.size():
		var ang := world.net.turn_angle(nav.path[i], nav.path[i + 1], nav.path[i + 2])
		if ang < -32.0:
			return 0
		if ang > 32.0:
			return lanes - 1
	return lanes - 1 if veh.kind == "truck" else mini(1, lanes - 1)


## 產生前方車道中心線（約 max_len 公尺）
func build_line(max_len := 150.0) -> PackedVector2Array:
	var net := world.net
	var out := PackedVector2Array()
	if nav.edges.is_empty():
		return out
	var total := 0.0
	var p0 := veh.pos2()
	for i in range(nav.idx, nav.edges.size()):
		var e: int = nav.edges[i]
		var from: int = nav.path[i]
		var to: int = nav.path[i + 1]
		var lane := _lane_for(i)
		var len: float = net.edges[e].len
		var t0 := net.t_out(e, from) if i > nav.idx else 0.0
		var t1 := net.t_in(e, to) if i < nav.edges.size() - 1 else 1.0
		if i == nav.idx:
			# 從車子目前投影位置開始
			var a: Vector2 = net.nodes[from]
			var b: Vector2 = net.nodes[to]
			var proj := clampf((p0 - a).dot((b - a).normalized()) / maxf(len, 0.1), 0.0, 1.0)
			t0 = clampf(proj, 0.0, t1)
		var steps := maxi(1, int((t1 - t0) * len / 4.0))
		for k in steps + 1:
			var t := lerpf(t0, t1, float(k) / steps)
			var p := net.lane_point(e, from, lane, t)
			if out.size() > 0:
				total += out[out.size() - 1].distance_to(p)
			out.append(p)
		if total > max_len or i >= nav.edges.size() - 1:
			break
		# 路口轉彎曲線
		var ne: int = nav.edges[i + 1]
		var nlane := _lane_for(i + 1)
		var pa := net.lane_point(e, from, lane, t1)
		var pb := net.lane_point(ne, to, nlane, net.t_out(ne, to))
		var din := (net.nodes[to] - net.nodes[from]).normalized()
		var dout := (net.nodes[nav.path[i + 2]] - net.nodes[to]).normalized()
		var c = Geometry2D.line_intersects_line(pa, din, pb, -dout)
		if c == null or (c as Vector2).distance_to(net.nodes[to]) > net.node_r[to] * 2.5 + 5.0:
			c = (pa + pb) * 0.5
		for k in range(1, 9):
			var u := k / 8.0
			var q: Vector2 = pa.lerp(c, u).lerp((c as Vector2).lerp(pb, u), u)
			total += out[out.size() - 1].distance_to(q)
			out.append(q)
	return out


func _lookahead(pts: PackedVector2Array, from: Vector2, ld: float) -> Vector2:
	# 找最近點，再往前 ld 公尺
	var best := 0
	var bd := 1e18
	for i in pts.size():
		var d := pts[i].distance_squared_to(from)
		if d < bd:
			bd = d
			best = i
	var acc := 0.0
	for i in range(best, pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		if acc + seg >= ld:
			return pts[i].lerp(pts[i + 1], (ld - acc) / maxf(seg, 0.01))
		acc += seg
	return pts[pts.size() - 1] if pts.size() > 0 else from + veh.fwd2() * ld


## 回傳 {steer, throttle, brake, blinker}
func drive(dt: float) -> Dictionary:
	var out := {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "blinker": 0}
	if not nav.active or nav.edges.is_empty():
		status = "沒有目的地，小柯先停車"
		out.brake = 1.0
		return out
	line = build_line()
	if line.size() < 2:
		out.brake = 1.0
		return out
	var v := veh.speed
	# --- 轉向（純追蹤）
	var ld := clampf(5.0 + absf(v) * 0.75, 7.0, 28.0)
	var target := _lookahead(line, veh.pos2(), ld)
	var to_t := target - veh.pos2()
	var f := veh.fwd2()
	var alpha := atan2(f.x * to_t.y - f.y * to_t.x, f.dot(to_t))      # 正 = 目標在右邊
	var delta := atan(2.0 * float(veh.spec.wb) * sin(alpha) / maxf(to_t.length(), 1.0))
	var max_st: float = veh.spec.steer * clampf(1.0 - absf(v) / 38.0 * 0.65, 0.3, 1.0)
	out.steer = clampf(delta / max_st, -1.0, 1.0)
	# --- 速度規劃
	var net := world.net
	var e_cur: int = nav.edges[nav.idx]
	var limit: float = net.edges[e_cur].limit
	var vt := limit * (0.92 if veh.kind == "truck" else 0.97) / 3.6
	status = "沿車道行駛"
	# 彎道：看前方折線曲率
	var dist := 0.0
	for i in range(1, line.size() - 1):
		var a := line[i - 1]
		var b := line[i]
		var c := line[i + 1]
		dist += a.distance_to(b)
		if dist > 80.0:
			break
		var d1 := (b - a).normalized()
		var d2 := (c - b).normalized()
		var turn := absf(d1.angle_to(d2))
		var seg := maxf(b.distance_to(c), 0.5)
		if turn > 0.01:
			var R := seg / turn
			var a_lat := 1.6 if veh.kind == "truck" else 2.6
			var vc := sqrt(a_lat * R)
			var allowed := sqrt(vc * vc + 2.0 * 1.4 * maxf(dist - 4.0, 0.0))
			if allowed < vt:
				vt = allowed
				status = "前方彎道，減速"
	# 紅綠燈、停字
	var acc_d := veh.pos2().distance_to(net.nodes[nav.path[nav.idx + 1]])
	for i in range(nav.idx, mini(nav.idx + 3, nav.edges.size())):
		var n: int = nav.path[i + 1]
		var e: int = nav.edges[i]
		if i > nav.idx:
			acc_d += net.edges[e].len
		if acc_d > 90.0:
			break
		var stop_d := acc_d - net.node_r[n] - (4.5 if net.edges[e].walk else 1.5) - absf(float(veh.spec.front)) * 0.0 - (5.3 if veh.kind == "truck" else 3.7)
		var st := world.light_state(n, e)
		if st == "R" or (st == "Y" and stop_d > absf(v) * 1.5):
			var allowed2 := sqrt(2.0 * 2.0 * maxf(stop_d - 0.5, 0.0))
			if stop_d < -4.6:
				continue      # 車頭已經進入路口，繼續通過
			if allowed2 < vt:
				vt = allowed2 if stop_d > 0.8 else 0.0
				status = "紅燈，停在停止線前" if st == "R" else "黃燈，準備停車"
		for sp in world.map.stops:
			if sp.node == n and sp.edge == e and not _stop_wait.has(n):
				var allowed3 := sqrt(2.0 * 2.0 * maxf(stop_d - 0.5, 0.0))
				if allowed3 < vt:
					vt = allowed3 if stop_d > 0.8 else 0.0
					status = "看到「停」，完全停車再開"
				if stop_d < 1.5 and absf(v) < 0.3:
					_stop_t += dt
					if _stop_t > 1.5:
						_stop_wait[n] = true
						_stop_t = 0.0
	# 前車
	var gap := traffic.nearest_ahead(veh.front_center(), f, 70.0)
	if gap < 1e8:
		var allowed4 := maxf(0.0, (gap - 5.0) / 1.7)
		if allowed4 < vt:
			vt = allowed4
			status = "保持安全距離"
	# 目的地
	if nav.next_turn == "arrive":
		var allowed5 := sqrt(2.0 * 1.2 * maxf(nav.remain - 12.0, 0.0))
		if allowed5 < vt:
			vt = allowed5
			status = "快到目的地了"
	# 轉彎方向燈
	if nav.next_turn in ["left", "right"] and nav.next_dist < 80.0:
		out.blinker = -1 if nav.next_turn == "left" else 1
		if nav.next_dist < 40.0 and status == "沿車道行駛":
			status = "打方向燈，準備" + Nav.turn_text(nav.next_turn)
	target_kmh = vt * 3.6
	var err := vt - v
	if vt < 0.3 and v < 1.0:
		out.brake = 1.0
	elif err > 0.0:
		out.throttle = clampf(err * 0.45 + 0.1, 0.0, 1.0)
	else:
		out.brake = clampf(-err * 0.35, 0.0, 1.0)
	return out
