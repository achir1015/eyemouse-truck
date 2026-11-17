class_name Models
extends RefCounted
## 載入 TRELLIS 產生的寫實模型（assets/models/*.glb）：自動縮放到指定長度、貼地、置中、轉成車頭朝 -Z。
## 沒有模型檔時回傳 null，呼叫端改用程序化外觀。

## 名稱 -> 模型原本車頭朝向的修正角（弧度；讓車頭朝 -Z）。依 tools/inspect_models 預覽結果設定。
static var YAW := {"sedan": -PI * 0.5, "truck_tractor": PI, "trailer": PI, "car_white": PI, "car_silver": PI, "car_red": PI, "van": PI, "ambulance": PI, "scooter_parked": PI, "taxi": PI, "bus": PI, "scooter": PI}
static var _cache := {}


static func path_of(name: String) -> String:
	for p in ["res://assets/models/%s.glb" % name, "res://assets/models/%s/%s.gltf" % [name, name]]:
		if ResourceLoader.exists(p):
			return p
	return ""


static func has(name: String) -> bool:
	return path_of(name) != ""


static func aabb_of(n: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [n]
	while stack.size() > 0:
		var c: Node = stack.pop_back()
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var mi := c as MeshInstance3D
			var xf := _rel_xf(mi, n)
			var b := xf * mi.mesh.get_aabb()
			out = b if first else out.merge(b)
			first = false
		for ch in c.get_children():
			stack.append(ch)
	return out


static func _rel_xf(node: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## 產生一個實例：length = 沿車身長軸的長度（公尺）；height>0 時改用高度縮放（樹木）
static func make(name: String, length: float, height := 0.0, extra_yaw := 0.0) -> Node3D:
	var path := path_of(name)
	if path == "":
		return null
	var ps: PackedScene = _cache.get(name)
	if ps == null:
		ps = load(path)
		_cache[name] = ps
	var inst: Node3D = ps.instantiate()
	var holder := Node3D.new()
	var pivot := Node3D.new()
	holder.add_child(pivot)
	pivot.add_child(inst)
	pivot.rotation.y = float(YAW.get(name, 0.0)) + extra_yaw
	var bb := aabb_of(holder)
	var s := 1.0
	if height > 0.0:
		s = height / maxf(bb.size.y, 0.001)
	else:
		s = length / maxf(maxf(bb.size.x, bb.size.z), 0.001)
	pivot.scale = Vector3(s, s, s)
	bb = aabb_of(holder)
	pivot.position -= Vector3(bb.get_center().x, bb.position.y, bb.get_center().z)
	for mi in _meshes(holder):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return holder


static func _meshes(n: Node) -> Array:
	var out := []
	var stack: Array = [n]
	while stack.size() > 0:
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			out.append(c)
		for ch in c.get_children():
			stack.append(ch)
	return out


## 車身染色（同一個模型做出不同顏色的車）：把材質複製一份乘上顏色
static func tint(n: Node, col: Color) -> void:
	for mi in _meshes(n):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if mat is StandardMaterial3D:
				var c := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				c.albedo_color = c.albedo_color * Color.WHITE.lerp(col, 0.55).lightened(0.1)
				m.set_surface_override_material(i, c)
