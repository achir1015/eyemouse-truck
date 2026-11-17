class_name World
extends Node3D
## 建立 3D 世界：地面、道路、標線、建築、樹、山、峽谷、隧道、紅綠燈、交通標誌、天氣與時間。

const GREEN_T := 16.0
const YELLOW_T := 3.0
const ALLRED_T := 2.0

var map: Dictionary
var net: RoadNet
var kit: MeshKit
var mats := {}
var colliders: Array = []          # {c: Vector2, r: float} 或 {rect: Rect2}
var _cgrid := {}
var signs: Array = []              # {pos: Vector3, dir: Vector2, type, value, id}
var lights := {}                   # node -> {"group": {edge: 0/1}, "offset": float, "lamps": {edge: [R, Y, G]}}
var atlas: SignAtlas
var env: Environment
var sun: DirectionalLight3D
var clock := 0.0
var time_of_day := "day"
var weather := "clear"
var wet := 0.0
var rain: CPUParticles3D
var follow: Node3D                 # 跟隨的玩家（雨滴）
var dest_marker: Node3D
var lamp_mats := {}
var street_lamps: Array = []
var rng := RandomNumberGenerator.new()
var low := false


func setup(map_id: String, cond := {}) -> void:
	low = str(App.settings.quality) == "low"
	rng.seed = hash(map_id)
	map = Maps.build(map_id)
	net = map.net
	_make_materials()
	atlas = SignAtlas.new()
	add_child(atlas)
	mats["sign"].albedo_texture = atlas.get_texture()
	kit = MeshKit.new(self, mats)
	_env()
	_ground()
	_water()
	_roads()
	_markings()
	_sidewalks_and_lamps()
	_highway_parts()
	_buildings()
	_scatter("water_tank", _tanks, 0.0, 3.2)
	_scatter("ph_aircon" if Models.has("ph_aircon") else "ac_unit", _acs, 0.95)
	for lm in map.landmarks:
		for c in Landmarks.build(kit, self, lm):
			_add_col(c)
	_parking()
	_canyon()
	_mountains()
	_trees()
	_place_lamps()
	Props.place(self)
	_traffic_lights()
	_signs()
	kit.commit()
	_dest_marker()
	set_conditions(str(cond.get("time", "day")), str(cond.get("weather", "clear")))


# ---------------------------------------------------------------- 材質
func _noise_tex(base: Color, amount: float, sz := 128) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = 11
	for y in sz:
		for x in sz:
			var n := r.randf_range(-amount, amount)
			img.set_pixel(x, y, Color(base.r + n, base.g + n, base.b + n))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _window_tex(lit: bool) -> ImageTexture:
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = 5 if lit else 3
	img.fill(Color(0, 0, 0) if lit else Color(0.92, 0.92, 0.9))
	for cy in 8:
		for cx in 8:
			var rect := Rect2i(cx * 32 + 6, cy * 32 + 8, 20, 16)
			if lit:
				if r.randf() < 0.42:
					img.fill_rect(rect, Color.from_hsv(r.randf_range(0.08, 0.15), r.randf_range(0.3, 0.6), r.randf_range(0.7, 1.0)))
			else:
				var g := r.randf_range(0.22, 0.38)
				img.fill_rect(rect, Color(g, g + 0.04, g + 0.1))
				img.fill_rect(Rect2i(cx * 32 + 6, cy * 32 + 24, 20, 2), Color(0.7, 0.7, 0.7))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _mat(col := Color.WHITE, rough := 0.85, vc := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.vertex_color_use_as_albedo = vc
	m.vertex_color_is_srgb = true
	return m


func _tex(name: String) -> Texture2D:
	var p := "res://assets/tex/%s.jpg" % name
	return load(p) if ResourceLoader.exists(p) else null


func _tri(prefix: String, scale: float, mix := 1.0, avg := 0.45) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/triplanar.gdshader")
	m.set_shader_parameter("tex_albedo", _tex(prefix + "_diff"))
	m.set_shader_parameter("tex_rough", _tex(prefix + "_rough"))
	m.set_shader_parameter("tex_normal", _tex(prefix + "_nor"))
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("tex_mix", mix)
	m.set_shader_parameter("tex_avg", avg)
	return m


func _make_materials() -> void:
	var asphalt := _mat(Color.WHITE, 1.0)
	asphalt.albedo_texture = _tex("asphalt_diff")
	asphalt.normal_enabled = true
	asphalt.normal_texture = _tex("asphalt_nor")
	asphalt.roughness_texture = _tex("asphalt_rough")
	asphalt.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	asphalt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mats["road"] = asphalt
	var mk := _mat(Color(0.92, 0.9, 0.86), 0.8)
	mats["marking"] = mk
	mats["solid"] = _tri("concrete", 0.35, 0.35, 0.5)
	mats["metal"] = Props.metal_mat()
	mats["pavers"] = _tri("pavers", 0.5, 1.0, 0.42)
	mats["rock"] = _tri("cliff", 0.06, 1.0, 0.4)
	var glass := _mat(Color.WHITE, 0.08)
	glass.metallic = 0.7
	mats["glass"] = glass
	var glow := _mat()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mats["glow"] = glow
	var water := _mat(Color.WHITE, 0.05)
	water.metallic = 0.0
	water.metallic_specular = 0.9
	water.normal_enabled = true
	water.normal_texture = _tex("asphalt_nor")
	water.normal_scale = 0.15
	water.uv1_triplanar = true
	water.uv1_scale = Vector3(0.05, 0.05, 0.05)
	mats["water"] = water
	var gname := "concrete" if map.biome == "city" else ("sand" if map.biome == "coast" else "grass")
	mats["ground"] = _tri(gname, 0.25 if gname == "grass" else 0.3, 1.0, 0.4 if gname != "concrete" else 0.75)
	var bld := ShaderMaterial.new()
	bld.shader = load("res://shaders/facade.gdshader")
	bld.set_shader_parameter("tex_wall", _tex("facade_tile_diff"))
	bld.set_shader_parameter("tex_wall_n", _tex("facade_tile_nor"))
	bld.set_shader_parameter("tex_wall2", _tex("plaster_diff"))
	mats["building"] = bld
	var sign := StandardMaterial3D.new()
	sign.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	sign.alpha_scissor_threshold = 0.5
	sign.roughness = 0.35
	sign.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["sign"] = sign
	for c in ["R", "Y", "G"]:
		var m := StandardMaterial3D.new()
		m.albedo_color = {"R": Color(1, 0.12, 0.08), "Y": Color(1, 0.75, 0.1), "G": Color(0.1, 1, 0.45)}[c]
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 4.0
		lamp_mats[c] = m


# ---------------------------------------------------------------- 環境
var hi_fx := false


func _env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	hi_fx = RenderingServer.get_current_rendering_method() == "forward_plus" and not low
	if hi_fx:
		env.ssao_enabled = true
		env.ssao_radius = 1.6
		env.ssao_intensity = 2.2
		env.ssil_enabled = true
		env.glow_enabled = true
		env.glow_intensity = 0.4
		env.glow_bloom = 0.04
		env.glow_hdr_threshold = 1.2
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_blur = 1.5
	add_child(sun)


func _sky_for(tod: String, wx: String) -> String:
	if wx in ["rain", "storm", "cloudy"]:
		return "overcast"
	if wx in ["fog", "cold"]:
		return "misty"
	if tod == "dusk":
		return "dusk"
	if tod == "noon":
		return "noon"
	return "day"


func set_conditions(tod: String, wx: String) -> void:
	time_of_day = tod
	weather = wx
	var night := tod == "night"
	var dusk := tod == "dusk"
	var noon := tod == "noon"
	var path := "res://assets/sky/%s.hdr" % _sky_for(tod, wx)
	if not night and ResourceLoader.exists(path):
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = load(path)
		env.sky.sky_material = pm
	else:
		var psm := ProceduralSkyMaterial.new()
		psm.sky_top_color = Color(0.01, 0.02, 0.05)
		psm.sky_horizon_color = Color(0.06, 0.08, 0.14)
		psm.ground_horizon_color = psm.sky_horizon_color
		psm.ground_bottom_color = Color(0.02, 0.02, 0.02)
		psm.sky_energy_multiplier = 0.6
		env.sky.sky_material = psm
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(40), 0)
	if noon:
		sun.rotation = Vector3(deg_to_rad(-78), deg_to_rad(20), 0)
	if dusk:
		sun.rotation = Vector3(deg_to_rad(-9), deg_to_rad(-70), 0)
	sun.light_energy = 1.35 if noon else (0.08 if night else (0.75 if dusk else 1.15))
	sun.light_color = Color(1, 0.96, 0.9) if not dusk else Color(1, 0.62, 0.38)
	if night:
		sun.light_color = Color(0.55, 0.65, 1.0)
		sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-30), 0)
	env.ambient_light_energy = 1.0 if not night else 0.35
	env.ambient_light_sky_contribution = 1.0
	env.tonemap_exposure = 0.95 if not night else 1.3
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.ssr_enabled = false
	wet = 0.0
	var overcast := wx in ["rain", "storm", "fog", "cold", "cloudy"]
	if overcast:
		sun.light_energy *= 0.35
		sun.shadow_opacity = 0.5
	else:
		sun.shadow_opacity = 1.0
	if wx in ["rain", "storm"]:
		wet = 1.0
		env.fog_enabled = true
		env.fog_light_color = Color(0.6, 0.63, 0.66) if not night else Color(0.04, 0.05, 0.06)
		env.fog_density = 0.004 if wx == "rain" else 0.008
		env.fog_sky_affect = 0.4
		if hi_fx:
			env.ssr_enabled = true
			env.ssr_max_steps = 48
	if wx in ["fog", "cold"]:
		env.fog_enabled = true
		env.fog_light_color = Color(0.78, 0.8, 0.84) if not night else Color(0.08, 0.09, 0.11)
		env.fog_density = 0.016 if wx == "fog" else 0.009
		env.fog_sky_affect = 0.7
		if hi_fx:
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.01
			env.volumetric_fog_albedo = Color(0.85, 0.87, 0.9)
	if not env.fog_enabled and not night:
		env.fog_enabled = true
		env.fog_light_color = Color(0.72, 0.78, 0.86) if not dusk else Color(0.9, 0.65, 0.5)
		env.fog_density = 0.0005
		env.fog_sky_affect = 0.0
		env.fog_aerial_perspective = 0.35
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08 if noon else 1.0
	env.adjustment_contrast = 1.05
	var road: StandardMaterial3D = mats["road"]
	road.roughness = 1.0 - wet * 0.55
	road.albedo_color = Color(1, 1, 1).darkened(wet * 0.35)
	for k in ["ground", "pavers", "solid", "rock"]:
		(mats[k] as ShaderMaterial).set_shader_parameter("wet", wet)
	var bld: ShaderMaterial = mats["building"]
	bld.set_shader_parameter("night", 1.0 if night else (0.5 if dusk else 0.0))
	bld.set_shader_parameter("wet", wet)
	_setup_rain(wx in ["rain", "storm"], wx == "storm")


func _setup_rain(on: bool, heavy: bool) -> void:
	if rain:
		rain.queue_free()
		rain = null
	if not on:
		return
	rain = CPUParticles3D.new()
	rain.amount = 1400 if heavy else 800
	if low:
		rain.amount /= 2
	rain.lifetime = 0.9
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(30, 1, 30)
	rain.direction = Vector3(0.25 if heavy else 0.05, -1, 0)
	rain.spread = 3.0
	rain.gravity = Vector3(0, -30, 0)
	rain.initial_velocity_min = 22.0
	rain.initial_velocity_max = 28.0
	var qm := QuadMesh.new()
	qm.size = Vector2(0.02, 0.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.8, 0.85, 0.95, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	qm.material = m
	rain.mesh = qm
	rain.local_coords = false
	add_child(rain)


func is_night() -> bool:
	return time_of_day == "night"


# ---------------------------------------------------------------- 地面與水
func _ground() -> void:
	var b := net.bounds().grow(2600)
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col: Color = Color(0.85, 0.85, 0.82) if map.biome in ["city", "coast"] else Color(0.34, 0.5, 0.22)
	MeshKit.poly(s, PackedVector2Array([b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y)]), -0.04, col, 6.0)
	var mi := MeshInstance3D.new()
	mi.mesh = s.commit()
	mi.material_override = mats["ground"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _water() -> void:
	for poly in map.water:
		var c := Vector2.ZERO
		for p in poly:
			c += p
		c /= poly.size()
		MeshKit.poly(kit.st("water", Vector3(c.x, 0, c.y)), poly, -0.015, Color(0.16, 0.36, 0.48) if map.biome != "coast" else Color(0.1, 0.42, 0.55))


func in_water(p: Vector2) -> bool:
	for poly in map.water:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false


# ---------------------------------------------------------------- 道路
func _road_col(e: int) -> Color:
	match str(net.edges[e].kind):
		"highway": return Color(0.95, 0.95, 0.97)
		"yard": return Color(1.05, 1.05, 1.05)
		_: return Color(1, 1, 1)


func _roads() -> void:
	for e in net.edges.size():
		var d: Dictionary = net.edges[e]
		var a: Vector2 = net.nodes[d.a]
		var b: Vector2 = net.nodes[d.b]
		var hw := net.half_width(e)
		var mid := (a + b) * 0.5
		var s := kit.st("road", Vector3(mid.x, 0, mid.y))
		MeshKit.strip(s, a, b, -hw, hw, 0.0, _road_col(e), 5.0)
		if d.bridge:
			var S := kit.st("solid", Vector3(mid.x, 0, mid.y))
			for side in [-1.0, 1.0]:
				var off: float = side * (hw + 0.2)
				var dir: Vector2 = d.dir
				var r := Vector2(-dir.y, dir.x)
				var pa: Vector2 = a + r * off
				var pb: Vector2 = b + r * off
				MeshKit.wall(S, pa, pb, 0.0, 1.1, Color(0.8, 0.8, 0.82), side > 0)
				MeshKit.wall(S, pa, pb, 0.0, 1.1, Color(0.8, 0.8, 0.82), side < 0)
			MeshKit.strip(S, a, b, -hw - 0.4, hw + 0.4, -0.6, Color(0.5, 0.5, 0.5))
	for n in net.nodes.size():
		var r: float = net.node_r[n]
		if r <= 0.0:
			continue
		var c: Vector2 = net.nodes[n]
		var pts := PackedVector2Array()
		var segs := 20 if net.is_junction(n) else 14
		for k in segs:
			var a := TAU * k / segs
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		MeshKit.poly(kit.st("road", Vector3(c.x, 0, c.y)), pts, 0.004, Color(1, 1, 1), 5.0)


## 一段標線（沿 a→b，側向偏移 off、寬 w），dashed 時畫虛線
func _line(a: Vector2, b: Vector2, off: float, w: float, col: Color, dashed := false) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var dir := (b - a) / len
	var mid := (a + b) * 0.5
	var s := kit.st("marking", Vector3(mid.x, 0, mid.y))
	if not dashed:
		MeshKit.strip(s, a, b, off - w * 0.5, off + w * 0.5, 0.02, col)
		return
	var t := 1.0
	while t < len - 1.0:
		var t2 := minf(t + 4.0, len - 1.0)
		MeshKit.strip(s, a + dir * t, a + dir * t2, off - w * 0.5, off + w * 0.5, 0.02, col)
		t += 10.0


func _markings() -> void:
	var white := Color(0.95, 0.95, 0.95)
	var yellow := Color(0.98, 0.78, 0.15)
	for e in net.edges.size():
		var d: Dictionary = net.edges[e]
		if d.kind == "yard" and d.name != "S 彎道":
			continue
		var a0: Vector2 = net.nodes[d.a]
		var b0: Vector2 = net.nodes[d.b]
		var dir: Vector2 = d.dir
		var ta: float = net.node_r[d.a] if net.is_junction(d.a) else 0.0
		var tb: float = net.node_r[d.b] if net.is_junction(d.b) else 0.0
		if d.len - ta - tb < 2.0:
			continue
		var a: Vector2 = a0 + dir * ta
		var b: Vector2 = b0 - dir * tb
		var hw := net.half_width(e) - 0.6
		var lw: float = d.lane_w
		# 路緣白線
		_line(a, b, hw - 0.15, 0.15, white)
		_line(a, b, -hw + 0.15, 0.15, white)
		if d.oneway:
			for k in range(1, d.lanes):
				_line(a, b, (k - d.lanes * 0.5) * lw, 0.12, white, true)
			continue
		var m: float = d.median * 0.5
		if d.kind != "highway":
			if m > 0.8:
				_median(a, b, m - 0.3, d.kind)
			else:
				_line(a, b, -0.12, 0.1, yellow)
				_line(a, b, 0.12, 0.1, yellow)
		for k in range(1, d.lanes):
			_line(a, b, m + k * lw, 0.12, white, true)
			_line(a, b, -(m + k * lw), 0.12, white, true)
		# 路口前停止線＋行人穿越道
		for end in [[d.a, -1.0], [d.b, 1.0]]:
			var n: int = end[0]
			if not net.is_junction(n) or d.kind != "city":
				continue
			var forward: Vector2 = dir * end[1]       # 朝向路口的方向
			var p_edge: Vector2 = net.nodes[n] - forward * net.node_r[n]
			var s := kit.st("marking", Vector3(p_edge.x, 0, p_edge.y))
			var rr := Vector2(-forward.y, forward.x)
			# 斑馬線（橫跨整條路）
			if d.walk:
				for k in range(0, int(hw * 2.0 / 1.0)):
					var o := -hw + 0.5 + k * 1.0
					if k % 2 == 0:
						var c0 := p_edge - forward * 0.5 + rr * o
						MeshKit.strip(s, c0, c0 - forward * 3.0, -0.25, 0.25, 0.021, white)
			# 停止線（只畫進路口那一側＝右側車道）
			var sl := p_edge - forward * (4.0 if d.walk else 1.0)
			MeshKit.strip(s, sl - rr * m, sl + rr * hw, 0.0, 0.4, 0.022, white)


func _median(a: Vector2, b: Vector2, half: float, kind: String) -> void:
	var mid := (a + b) * 0.5
	var S := kit.st("solid", Vector3(mid.x, 0, mid.y))
	MeshKit.strip(S, a, b, -half, half, 0.18, Color(0.35, 0.55, 0.3) if kind == "city" else Color(0.7, 0.7, 0.7))
	var dir := (b - a).normalized()
	var r := Vector2(-dir.y, dir.x)
	MeshKit.wall(S, a + r * half, b + r * half, 0.0, 0.18, Color(0.75, 0.75, 0.72), true)
	MeshKit.wall(S, a - r * half, b - r * half, 0.0, 0.18, Color(0.75, 0.75, 0.72), false)
	# 中央分隔島的小樹
	var len := a.distance_to(b)
	var t := 8.0
	while t < len - 6.0:
		var p := a + dir * t
		MeshKit.cyl(S, MeshKit.xf_at(Vector3(p.x, 0.18, p.y)), 0.12, 0.1, 2.2, 5, Color(0.4, 0.3, 0.2), false)
		MeshKit.sphere(S, Vector3(p.x, 3.0, p.y), 1.2, Color(0.22, 0.48, 0.22), 6)
		t += 14.0
	_add_line_col(a, b, half)


func _add_line_col(a: Vector2, b: Vector2, r: float) -> void:
	var len := a.distance_to(b)
	var n := maxi(1, int(len / (r * 1.5 + 1.0)))
	for k in n + 1:
		_add_col({"c": a.lerp(b, float(k) / n), "r": r})


# ---------------------------------------------------------------- 人行道與路燈
func _sidewalks_and_lamps() -> void:
	for e in net.edges.size():
		var d: Dictionary = net.edges[e]
		var a0: Vector2 = net.nodes[d.a]
		var b0: Vector2 = net.nodes[d.b]
		var dir: Vector2 = d.dir
		var hw := net.half_width(e)
		var lamp_every := 0.0
		if d.walk:
			var ta: float = net.node_r[d.a] + (0.0 if net.is_junction(d.a) else -hw)
			var tb: float = net.node_r[d.b] + (0.0 if net.is_junction(d.b) else -hw)
			ta = maxf(ta, 0.0)
			tb = maxf(tb, 0.0)
			if d.len - ta - tb > 1.0:
				var a: Vector2 = a0 + dir * ta
				var b: Vector2 = b0 - dir * tb
				var mid := (a + b) * 0.5
				var S := kit.st("pavers", Vector3(mid.x, 0, mid.y))
				for side in [-1.0, 1.0]:
					var o0: float = side * hw
					var o1: float = side * (hw + 3.5)
					MeshKit.strip(S, a, b, minf(o0, o1), maxf(o0, o1), 0.15, Color(0.85, 0.8, 0.75))
					var r := Vector2(-dir.y, dir.x)
					MeshKit.wall(S, a + r * o0, b + r * o0, 0.0, 0.15, Color(0.6, 0.6, 0.6), side < 0)
			lamp_every = 40.0
		elif d.kind in ["highway", "ramp"]:
			lamp_every = 0.0
		if lamp_every > 0.0 and not low:
			var t := 12.0
			var side := 1.0
			while t < d.len - 10.0:
				var r := Vector2(-dir.y, dir.x)
				var p: Vector2 = a0 + dir * t + r * side * (hw + 0.6)
				_lamp(p, -r * side)
				side = -side
				t += lamp_every * 0.5


var _lamp_list: Array = []


func _lamp(p: Vector2, toward: Vector2) -> void:
	_lamp_list.append([p, toward])
	street_lamps.append(Vector3(p.x + toward.x * 2.1, 7.6, p.y + toward.y * 2.1))


func _place_lamps() -> void:
	if Models.has("street_lamp"):
		var xf := []
		for l in _lamp_list:
			var t: Vector2 = l[1]
			xf.append(Transform3D(Basis(Vector3.UP, atan2(-t.x, -t.y) + float(Models.YAW.get("street_lamp_arm", 0.0))), Vector3(l[0].x, 0.15, l[0].y)))
		_scatter("street_lamp", xf, 0.0, 8.5)
		return
	for l in _lamp_list:
		var p: Vector2 = l[0]
		Props.lamp(kit.st("metal", Vector3(p.x, 0, p.y)), kit.st("glow", Vector3(p.x, 0, p.y)), p, l[1])


# ---------------------------------------------------------------- 國道：中央護欄、路側護欄
func _highway_parts() -> void:
	for e in net.edges.size():
		var d: Dictionary = net.edges[e]
		if not d.kind in ["highway", "mountain", "ramp"] or d.tunnel:
			continue
		var a: Vector2 = net.nodes[d.a]
		var b: Vector2 = net.nodes[d.b]
		var dir: Vector2 = d.dir
		var r := Vector2(-dir.y, dir.x)
		var hw := net.half_width(e)
		var mid := (a + b) * 0.5
		var S := kit.st("solid", Vector3(mid.x, 0, mid.y))
		var ta: float = net.node_r[d.a] if net.is_junction(d.a) else 0.0
		var tb: float = net.node_r[d.b] if net.is_junction(d.b) else 0.0
		var aa: Vector2 = a + dir * ta
		var bb: Vector2 = b - dir * tb
		if d.kind == "highway":
			# 紐澤西護欄
			MeshKit.wall(S, aa + r * 0.3, bb + r * 0.3, 0.0, 0.85, Color(0.78, 0.78, 0.75), true)
			MeshKit.wall(S, aa - r * 0.3, bb - r * 0.3, 0.0, 0.85, Color(0.78, 0.78, 0.75), false)
			MeshKit.strip(S, aa, bb, -0.3, 0.3, 0.85, Color(0.7, 0.7, 0.68))
			# 中央的路燈
			if not low:
				var t := 30.0
				while t < d.len:
					var p: Vector2 = a + dir * t
					MeshKit.cyl(S, MeshKit.xf_at(Vector3(p.x, 0.85, p.y)), 0.12, 0.1, 10.0, 5, Color(0.55, 0.56, 0.58), false)
					for sd in [-1.0, 1.0]:
						var h: Vector2 = p + r * sd * 2.2
						MeshKit.box(kit.st("glow", Vector3(h.x, 0, h.y)), MeshKit.xf_at(Vector3(h.x, 10.6, h.y), atan2(r.x, r.y)), Vector3(0.4, 0.15, 4.4), Color(1, 0.9, 0.7))
					t += 80.0
		if true:
			for sd in [-1.0, 1.0]:
				if d.kind == "mountain" and sd > 0 and map.get("canyon", false):
					continue
				var o: float = sd * (hw + 0.3)
				var pa: Vector2 = aa + r * o
				var pb: Vector2 = bb + r * o
				# W 型鋼板護欄（鍍鋅）：三段折面＋圓柱立柱
				var M := kit.st("metal", Vector3(mid.x, 0, mid.y))
				var inw: Vector2 = -r * sd       # 朝路面
				var gc := Color(0.72, 0.74, 0.76)
				var prof := [[0.0, 0.48], [0.07, 0.55], [0.0, 0.64], [0.07, 0.72], [0.0, 0.8]]
				for k in prof.size() - 1:
					var o0: Vector2 = inw * float(prof[k][0])
					var o1: Vector2 = inw * float(prof[k + 1][0])
					var A := Vector3(pa.x + o0.x, prof[k][1], pa.y + o0.y)
					var B := Vector3(pb.x + o0.x, prof[k][1], pb.y + o0.y)
					var C := Vector3(pb.x + o1.x, prof[k + 1][1], pb.y + o1.y)
					var D := Vector3(pa.x + o1.x, prof[k + 1][1], pa.y + o1.y)
					MeshKit.quad(M, A, B, C, D, gc)
					MeshKit.quad(M, B, A, D, C, gc.darkened(0.2))
				var t2 := 0.0
				while t2 < pa.distance_to(pb):
					var q: Vector2 = pa + dir * t2 - inw * 0.12
					MeshKit.cyl(M, MeshKit.xf_at(Vector3(q.x, 0, q.y)), 0.07, 0.07, 0.78, 10, Color(0.62, 0.64, 0.66))
					t2 += 4.0


# ---------------------------------------------------------------- 建築
const SHOPS := ["便利商店", "藥局", "早餐店", "牛肉麵", "珍珠奶茶", "機車行", "銀行", "診所", "書局", "眼鏡行",
	"滷肉飯", "水果行", "五金行", "補習班", "火鍋", "咖啡", "麵包店", "電器行", "小吃", "旅館"]


var _tanks: Array = []
var _acs: Array = []


func _scatter(name: String, xforms: Array, length: float, height := 0.0) -> void:
	if xforms.is_empty():
		return
	var holder := Models.make(name, length, height)
	if holder == null:
		return
	for mi in Models._meshes(holder):
		var m := mi as MeshInstance3D
		var base := Models._rel_xf(m, holder)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m.mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, (xforms[i] as Transform3D) * base)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if m.get_active_material(0):
			mmi.material_override = m.get_active_material(0)
		mmi.visibility_range_end = 450.0
		add_child(mmi)
	holder.free()


func _buildings() -> void:
	var tall: bool = map.id in ["taipei", "kaohsiung"]
	var shop_labels := 0
	var max_labels := 30 if low else 70
	var tints := [Color(0.92, 0.88, 0.8), Color(0.8, 0.82, 0.85), Color(0.9, 0.8, 0.78), Color(0.78, 0.84, 0.88),
		Color(0.96, 0.95, 0.92), Color(0.85, 0.86, 0.8), Color(0.75, 0.72, 0.7)]
	for blk in map.blocks:
		var rect: Rect2 = blk
		var inner := rect.grow(-13.0)
		if inner.size.x < 12 or inner.size.y < 12:
			continue
		var sides := [
			[inner.position, Vector2(1, 0), inner.size.x, Vector2(0, 1)],
			[Vector2(inner.end.x, inner.position.y), Vector2(0, 1), inner.size.y, Vector2(-1, 0)],
			[inner.end, Vector2(-1, 0), inner.size.x, Vector2(0, -1)],
			[Vector2(inner.position.x, inner.end.y), Vector2(0, -1), inner.size.y, Vector2(1, 0)],
		]
		for sd in sides:
			var start: Vector2 = sd[0]
			var along: Vector2 = sd[1]
			var length: float = sd[2]
			var inward: Vector2 = sd[3]
			var t := 0.0
			while t < length - 6.0:
				var w := minf(rng.randf_range(10.0, 24.0), length - t)
				var dep := minf(rng.randf_range(12.0, 20.0), minf(inner.size.x, inner.size.y) * 0.5)
				var h := rng.randf_range(9.0, 24.0)
				if tall:
					h = rng.randf_range(12.0, 45.0)
					if rng.randf() < 0.1:
						h = rng.randf_range(60.0, 130.0)
				var c2: Vector2 = start + along * (t + w * 0.5) + inward * (dep * 0.5)
				var yaw := atan2(inward.x, inward.y)     # 讓盒子的 +Z 朝內，-Z 朝街道
				var tint: Color = tints[rng.randi() % tints.size()]
				if h >= 60.0:
					tint = Color(0.75, 0.8, 0.85, 0.3)
				var S := kit.st("building", Vector3(c2.x, 0, c2.y))
				var xf := MeshKit.xf_at(Vector3(c2.x, h * 0.5, c2.y), yaw)
				MeshKit.box(S, xf, Vector3(w - 0.4, h, dep), tint, Vector2(4.0, 3.2), tint.darkened(0.25))
				var bb := Rect2(c2 - Vector2(w, dep) * 0.5, Vector2(w, dep)) if absf(along.x) > 0.5 else Rect2(c2 - Vector2(dep, w) * 0.5, Vector2(dep, w))
				_add_col({"rect": bb.grow(-0.2)})
				# 陽台（台灣公寓）與騎樓柱
				var fr: Vector2 = c2 - inward * (dep * 0.5)
				var SB := kit.st("solid", Vector3(fr.x, 0, fr.y))
				if h < 45.0 and rng.randf() < 0.55:
					var nfl := int(h / 3.2)
					for fl in range(2, nfl):
						var bp: Vector2 = fr - inward * 0.55
						MeshKit.box(SB, MeshKit.xf_at(Vector3(bp.x, fl * 3.2 - 0.05, bp.y), yaw), Vector3(w - 1.4, 0.14, 1.1), tint.darkened(0.15))
						var rp: Vector2 = fr - inward * 1.05
						MeshKit.box(SB, MeshKit.xf_at(Vector3(rp.x, fl * 3.2 + 0.5, rp.y), yaw), Vector3(w - 1.4, 0.9, 0.06), Color(0.32, 0.33, 0.34) if rng.randf() < 0.5 else tint.darkened(0.25))
				if h < 50.0:
					var nc := maxi(2, int(w / 4.0))
					for k in nc + 1:
						var cp: Vector2 = fr - inward * 0.25 + along * (-w * 0.5 + 0.4 + k * (w - 0.8) / nc)
						MeshKit.box(SB, MeshKit.xf_at(Vector3(cp.x, 1.8, cp.y), yaw), Vector3(0.45, 3.6, 0.45), tint.darkened(0.1))
				# 屋頂水塔、外牆冷氣機（台灣街景）
				if h < 50.0 and rng.randf() < 0.6:
					_tanks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(c2.x + rng.randf_range(-w, w) * 0.25, h, c2.y + rng.randf_range(-dep, dep) * 0.25)))
				if h < 60.0:
					var nf := int(h / 3.2)
					for k in mini(nf, 6):
						if rng.randf() < 0.45:
							var fl := rng.randi_range(1, maxi(1, nf - 1))
							var ap: Vector2 = c2 - inward * (dep * 0.5 + 0.35) + along * rng.randf_range(-w * 0.4, w * 0.4)
							_acs.append(Transform3D(Basis(Vector3.UP, yaw + PI), Vector3(ap.x, fl * 3.2 + 0.6, ap.y)))
				# 騎樓與招牌（朝街道那一面）
				var front: Vector2 = c2 - inward * (dep * 0.5)
				var SS := kit.st("solid", Vector3(front.x, 0, front.y))
				MeshKit.box(SS, MeshKit.xf_at(Vector3(front.x, 3.6, front.y) - Vector3(inward.x, 0, inward.y) * 0.3, yaw), Vector3(w - 0.6, 0.5, 0.6), tint.darkened(0.35))
				if h < 50.0 and rng.randf() < 0.75:
					var sc := Color.from_hsv(rng.randf(), rng.randf_range(0.35, 0.6), rng.randf_range(0.7, 0.9))
					var sp: Vector2 = front + along * (w * 0.5 - 1.2) - inward * 0.9
					var sh := minf(h - 5.0, rng.randf_range(4.0, 9.0))
					var SG := kit.st("metal", Vector3(sp.x, 0, sp.y))
					MeshKit.box(SG, MeshKit.xf_at(Vector3(sp.x, 4.5 + sh * 0.5, sp.y), yaw + PI * 0.5), Vector3(1.5, sh, 0.28), sc)
					MeshKit.box(SG, MeshKit.xf_at(Vector3(sp.x, 4.5 + sh * 0.5, sp.y), yaw + PI * 0.5), Vector3(1.62, sh + 0.12, 0.2), Color(0.25, 0.25, 0.27))
				if shop_labels < max_labels and rng.randf() < 0.35:
					shop_labels += 1
					var lp: Vector2 = front - inward * 0.62
					var l := Landmarks.label(self, SHOPS[rng.randi() % SHOPS.size()], Vector3(lp.x, 4.6, lp.y), 0.018, yaw + PI, Color(1, 1, 0.9), false)
					l.outline_size = 8
				t += w


# ---------------------------------------------------------------- 停車格（駕訓場）
func _parking() -> void:
	for pk in map.parking:
		var c: Vector2 = pk.pos
		var sz: Vector2 = pk.size
		var yaw: float = pk.yaw
		var s := kit.st("marking", Vector3(c.x, 0, c.y))
		var hx := sz.x * 0.5
		var hz := sz.y * 0.5
		var corners := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]
		var pts := []
		for q in corners:
			pts.append(c + (q as Vector2).rotated(-yaw))
		if pk.kind == "bay":
			# 停車場地面
			MeshKit.poly(kit.st("road", Vector3(c.x, 0, c.y)), PackedVector2Array([pts[0] + (pts[0] - c) * 0.6, pts[1] + (pts[1] - c) * 0.6,
				pts[2] + (pts[2] - c) * 0.6, pts[3] + (pts[3] - c) * 0.6]), 0.003, Color(1, 1, 1), 8.0)
		var col := Color(1, 0.85, 0.2)
		for k in 4:
			if pk.kind == "bay" and k == 0:
				continue   # 入口那一邊不畫
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[(k + 1) % 4]
			MeshKit.strip(s, a, b, -0.1, 0.1, 0.025, col)


# ---------------------------------------------------------------- 峽谷、隧道
func _canyon() -> void:
	if not map.get("canyon", false):
		return
	var chain := []
	for e in net.edges.size():
		if net.edges[e].kind == "mountain":
			chain.append(e)
	if chain.is_empty():
		return
	var pts: Array = [net.nodes[net.edges[chain[0]].a]]
	for e in chain:
		pts.append(net.nodes[net.edges[e].b])
	var hw := net.half_width(chain[0])
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.02
	# 斷面：右側（靠路的山壁）與左側（河對岸）[側向偏移, 高度]
	var right_prof := [[hw + 1.5, 0.0], [hw + 4.0, 28.0], [hw + 14.0, 85.0], [hw + 60.0, 130.0], [hw + 160.0, 160.0]]
	var left_prof := [[-48.0, -0.5], [-54.0, 40.0], [-70.0, 95.0], [-120.0, 135.0], [-220.0, 160.0]]
	var rows := []
	for k in pts.size():
		var a: Vector2 = pts[maxi(k - 1, 0)]
		var b: Vector2 = pts[mini(k + 1, pts.size() - 1)]
		var dir := (b - a).normalized()
		var r := Vector2(-dir.y, dir.x)
		var p: Vector2 = pts[k]
		var row := []
		for prof in [left_prof, right_prof]:
			var side := []
			for q in prof:
				var n := noise.get_noise_2d(p.x + q[0], p.y) * 0.35 + 1.0
				var off: float = q[0]
				var h: float = q[1] * n if q[1] > 1.0 else q[1]
				var pp: Vector2 = p + r * off
				side.append(Vector3(pp.x, h, pp.y))
			row.append(side)
		rows.append(row)
	var rock := Color(0.56, 0.54, 0.5)
	for k in pts.size() - 1:
		var mid: Vector2 = (pts[k] + pts[k + 1]) * 0.5
		var S := kit.st("rock", Vector3(mid.x, 0, mid.y))
		for sd in 2:
			var A: Array = rows[k][sd]
			var B: Array = rows[k + 1][sd]
			for j in A.size() - 1:
				var shade := 0.12 * sin(k * 1.7 + j) + (0.08 if j == 0 else 0.0)
				var c := rock.darkened(clampf(shade + 0.05, 0.0, 0.4)) if j < 3 else Color(0.28, 0.42, 0.25)
				if sd == 1:
					MeshKit.quad(S, A[j], B[j], B[j + 1], A[j + 1], c)
				else:
					MeshKit.quad(S, B[j], A[j], A[j + 1], B[j + 1], c)
		# 河岸
		MeshKit.strip(S, pts[k], pts[k + 1], -hw - 0.2, -48.0, -0.03, Color(0.52, 0.5, 0.44))
	for e in chain:
		var d: Dictionary = net.edges[e]
		var a: Vector2 = net.nodes[d.a]
		var b: Vector2 = net.nodes[d.b]
		var dir: Vector2 = d.dir
		var r := Vector2(-dir.y, dir.x)
		_add_line_col(a + r * (hw + 2.6), b + r * (hw + 2.6), 1.2)
		if not d.tunnel:
			continue
		var mid := (a + b) * 0.5
		var T := kit.st("solid", Vector3(mid.x, 0, mid.y))
		var aa: Vector2 = a - dir * 0.5
		var bb: Vector2 = b + dir * 0.5
		MeshKit.wall(T, aa - r * (hw + 0.3), bb - r * (hw + 0.3), 0.0, 6.0, Color(0.5, 0.5, 0.48), true)
		MeshKit.wall(T, aa + r * (hw + 0.3), bb + r * (hw + 0.3), 0.0, 6.0, Color(0.5, 0.5, 0.48), false)
		var r3 := Vector3(r.x, 0, r.y) * (hw + 0.4)
		MeshKit.quad(T, Vector3(aa.x, 5.98, aa.y) + r3, Vector3(aa.x, 5.98, aa.y) - r3, Vector3(bb.x, 5.98, bb.y) - r3, Vector3(bb.x, 5.98, bb.y) + r3, Color(0.32, 0.32, 0.32))
		MeshKit.box(T, MeshKit.xf_at(Vector3(mid.x, 6.0 + 9.0, mid.y), atan2(dir.x, dir.y)), Vector3(hw * 2 + 10.0, 18.0, d.len + 1.0), rock)
		var t := 3.0
		while t < d.len:
			var p: Vector2 = a + dir * t
			MeshKit.box(kit.st("glow", Vector3(p.x, 0, p.y)), MeshKit.xf_at(Vector3(p.x, 5.9, p.y), atan2(dir.x, dir.y)), Vector3(0.3, 0.1, 2.0), Color(1, 0.85, 0.55))
			t += 8.0
		_add_line_col(aa - r * (hw + 0.8), bb - r * (hw + 0.8), 0.6)


# ---------------------------------------------------------------- 遠山
func _mountains() -> void:
	if not map.get("mountains", false) and map.biome != "city":
		return
	var b := net.bounds()
	var c := b.get_center()
	var r0 := b.size.length() * 0.5 + 350.0
	var r1 := r0 + 1500.0
	var noise := FastNoiseLite.new()
	noise.seed = hash(map.id)
	noise.frequency = 0.004
	var S := SurfaceTool.new()
	S.begin(Mesh.PRIMITIVE_TRIANGLES)
	var A := 72
	var R := 6
	var city: bool = map.biome == "city"
	var pt := func(i: int, j: int) -> Vector3:
		var a := TAU * i / A
		var f := float(j) / R
		var rad := lerpf(r0, r1, f)
		var p := c + Vector2(cos(a), sin(a)) * rad
		var h := sin(f * PI) * (420.0 if not city else 260.0) * (0.45 + 0.8 * (noise.get_noise_2d(p.x, p.y) * 0.5 + 0.5))
		if j == 0 or j == R:
			h = -2.0
		return Vector3(p.x, h, p.y)
	for i in A:
		for j in R:
			var p00: Vector3 = pt.call(i, j)
			var p10: Vector3 = pt.call(i + 1, j)
			var p01: Vector3 = pt.call(i, j + 1)
			var p11: Vector3 = pt.call(i + 1, j + 1)
			var col := Color(0.16, 0.3, 0.14).lerp(Color(0.3, 0.36, 0.3), clampf(p00.y / 400.0, 0.0, 1.0))
			MeshKit.quad(S, p00, p10, p11, p01, col)
	S.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = S.commit()
	var m := _tri("grass", 0.012, 0.8, 0.4)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------- 樹
func _clear_spot(p: Vector2, margin: float) -> bool:
	var q := net.query(p)
	if q.edge >= 0 and q.dist < net.half_width(q.edge) + margin:
		return false
	for n in net.nodes.size():
		if p.distance_to(net.nodes[n]) < net.node_r[n] + margin:
			return false
	if in_water(p):
		return false
	return not hit_any(p, 1.5)


func _trees() -> void:
	var pos := []
	var palm: bool = map.biome == "coast"
	if map.get("trees", false):
		for e in net.edges.size():
			var d: Dictionary = net.edges[e]
			if d.kind in ["city"] or d.tunnel:
				continue
			var a: Vector2 = net.nodes[d.a]
			var dir: Vector2 = d.dir
			var r := Vector2(-dir.y, dir.x)
			var hw := net.half_width(e)
			var t := rng.randf_range(0, 10)
			var step := 14.0 if not low else 26.0
			while t < d.len:
				for side in [-1.0, 1.0]:
					if map.get("canyon", false) and side > 0:
						continue
					var off: float = hw + rng.randf_range(4.0, 40.0 if not map.get("canyon", false) else 14.0)
					var p: Vector2 = a + dir * t + r * side * off
					if _clear_spot(p, 3.0):
						pos.append(p)
				t += step * rng.randf_range(0.6, 1.4)
	# 市區人行道行道樹
	for e in net.edges.size():
		var d: Dictionary = net.edges[e]
		if not d.walk:
			continue
		var hw := net.half_width(e)
		var r := Vector2(-d.dir.y, d.dir.x)
		var t := 14.0
		while t < d.len - 14.0:
			for side in [-1.0, 1.0]:
				var p: Vector2 = net.nodes[d.a] + d.dir * (t + side * 4.0) + r * side * (hw + 2.4)
				var near_node := false
				for n in [d.a, d.b]:
					if p.distance_to(net.nodes[n]) < net.node_r[n] + 8.0:
						near_node = true
				if not near_node:
					pos.append(p)
			t += 22.0
	for lm in map.landmarks:
		if lm.type == "park":
			for k in (40 if not low else 20):
				var p: Vector2 = lm.pos + Vector2(rng.randf_range(-50, 50), rng.randf_range(-48, 48))
				if _clear_spot(p, 3.0) and not Geometry2D.is_point_in_circle(p, lm.pos + Vector2(20, -10), 24.0):
					pos.append(p)
	if pos.is_empty():
		return
	if palm and _model_trees(pos, "tree_palm"):
		return
	if _impostor_trees(pos):
		return
	if _model_trees(pos, "tree_street"):
		return
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.28
	trunk.height = 3.0 if not palm else 7.0
	trunk.radial_segments = 5
	trunk.rings = 1
	var crown: Mesh
	if palm:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.2
		cm.bottom_radius = 3.0
		cm.height = 1.0
		cm.radial_segments = 7
		crown = cm
	else:
		var sm := SphereMesh.new()
		sm.radius = 2.4
		sm.height = 4.4
		sm.radial_segments = 7
		sm.rings = 4
		crown = sm
	var tm := _mat(Color(0.42, 0.3, 0.2), 1.0, false)
	trunk.material = tm
	var cmat := _mat(Color.WHITE, 1.0, true)
	crown.surface_set_material(0, cmat)
	var mm_t := MultiMesh.new()
	mm_t.transform_format = MultiMesh.TRANSFORM_3D
	mm_t.mesh = trunk
	mm_t.instance_count = pos.size()
	var mm_c := MultiMesh.new()
	mm_c.transform_format = MultiMesh.TRANSFORM_3D
	mm_c.use_colors = true
	mm_c.mesh = crown
	mm_c.instance_count = pos.size()
	for i in pos.size():
		var p: Vector2 = pos[i]
		var s := rng.randf_range(0.8, 1.5)
		var th: float = trunk.height
		mm_t.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(p.x, th * 0.5 * s, p.y)))
		mm_c.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, (th + (1.6 if not palm else 0.3)) * s, p.y)))
		mm_c.set_instance_color(i, Color.from_hsv(rng.randf_range(0.24, 0.33), rng.randf_range(0.45, 0.7), rng.randf_range(0.32, 0.55)))
		_add_col({"c": p, "r": 0.5 * s})
	for mm in [mm_t, mm_c]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if low else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)


## 照片樹（Poly Haven 掃描樹烘焙成的照片貼圖），十字交叉面片＋透明裁切
func _impostor_trees(pos: Array) -> bool:
	var kinds := []
	for nm in ["tree_a", "tree_b"]:
		var tp := "res://assets/tex/%s_0.png" % nm
		if ResourceLoader.exists(tp):
			var meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tex/%s.json" % nm))
			kinds.append([nm, float(meta.get("aspect_0", 1.0)) if typeof(meta) == TYPE_DICTIONARY else 1.0])
	if kinds.is_empty():
		return false
	var groups := {}
	for p in pos:
		var k: int = rng.randi() % kinds.size()
		if not groups.has(k):
			groups[k] = []
		groups[k].append(p)
	for k in groups:
		var nm: String = kinds[k][0]
		var aspect: float = kinds[k][1]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var h := 1.0
		var w := aspect
		for ang in [0.0, PI * 0.5]:
			var ax := Vector3(cos(ang), 0, sin(ang)) * w * 0.5
			MeshKit.quad(st, -ax, ax, ax + Vector3(0, h, 0), -ax + Vector3(0, h, 0), Color.WHITE)
		var mesh := st.commit()
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/tex/%s_0.png" % nm)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.45
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.95
		m.backlight_enabled = true
		m.backlight = Color(0.35, 0.4, 0.25)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var list: Array = groups[k]
		mm.instance_count = list.size()
		for i in list.size():
			var p: Vector2 = list[i]
			var th := rng.randf_range(6.5, 10.0)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(th, th, th)), Vector3(p.x, -0.05, p.y)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = m
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = 900.0
		add_child(mmi)
	for p in pos:
		_add_col({"c": p, "r": 0.45})
	return true


## 寫實樹（TRELLIS 模型）用 MultiMesh 大量擺放；沒有模型回傳 false
func _model_trees(pos: Array, name: String) -> bool:
	var holder := Models.make(name, 0.0, 9.0 if name == "tree_street" else 11.0)
	if holder == null:
		return false
	for mi in Models._meshes(holder):
		var m := mi as MeshInstance3D
		var base := Models._rel_xf(m, holder)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m.mesh
		mm.instance_count = pos.size()
		for i in pos.size():
			var p: Vector2 = pos[i]
			var sc := rng.randf_range(0.75, 1.3)
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(p.x, 0, p.y))
			mm.set_instance_transform(i, xf * base)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if m.mesh.get_surface_count() > 0 and m.get_active_material(0):
			mmi.material_override = m.get_active_material(0)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = 700.0
		add_child(mmi)
	for p in pos:
		_add_col({"c": p, "r": 0.5})
	holder.free()
	return true


# ---------------------------------------------------------------- 碰撞
func _add_col(c: Dictionary) -> void:
	colliders.append(c)
	var idx := colliders.size() - 1
	var lo: Vector2
	var hi: Vector2
	if c.has("rect"):
		lo = c.rect.position
		hi = c.rect.end
	else:
		lo = c.c - Vector2(c.r, c.r)
		hi = c.c + Vector2(c.r, c.r)
	for cx in range(floori(lo.x / 20.0), floori(hi.x / 20.0) + 1):
		for cz in range(floori(lo.y / 20.0), floori(hi.y / 20.0) + 1):
			var k := Vector2i(cx, cz)
			if not _cgrid.has(k):
				_cgrid[k] = []
			_cgrid[k].append(idx)


## 圓（p, r）跟靜態物體的碰撞：回傳推出向量（沒有碰到 = ZERO）
func push_out(p: Vector2, r: float) -> Vector2:
	var total := Vector2.ZERO
	var k := Vector2i(floori(p.x / 20.0), floori(p.y / 20.0))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for idx in _cgrid.get(k + Vector2i(dx, dz), []):
				var c: Dictionary = colliders[idx]
				if c.has("rect"):
					var rc: Rect2 = c.rect
					var q := Vector2(clampf(p.x, rc.position.x, rc.end.x), clampf(p.y, rc.position.y, rc.end.y))
					var d := p - q
					var dl := d.length()
					if dl < r:
						if dl < 0.001:
							# 中心在矩形內：往最近的邊推
							var dl_ := [p.x - rc.position.x, rc.end.x - p.x, p.y - rc.position.y, rc.end.y - p.y]
							var m: float = dl_.min()
							var i := dl_.find(m)
							total += [Vector2(-(m + r), 0), Vector2(m + r, 0), Vector2(0, -(m + r)), Vector2(0, m + r)][i]
						else:
							total += d / dl * (r - dl)
				else:
					var d2: Vector2 = p - c.c
					var dl2 := d2.length()
					var rr: float = r + c.r
					if dl2 < rr and dl2 > 0.001:
						total += d2 / dl2 * (rr - dl2)
	return total


func hit_any(p: Vector2, r: float) -> bool:
	return push_out(p, r) != Vector2.ZERO


# ---------------------------------------------------------------- 紅綠燈
func _traffic_lights() -> void:
	for n in map.lights:
		var groups := {}
		var lamps := {}
		var c: Vector2 = net.nodes[n]
		var first_dir := Vector2.ZERO
		for e in net.adj[n]:
			var o := net.other(e, n)
			var away: Vector2 = (net.nodes[o] - c).normalized()     # 從路口往外
			if first_dir == Vector2.ZERO:
				first_dir = away
			groups[e] = 0 if absf(away.dot(first_dir)) > 0.7 else 1
			# 號誌桿：在進入路口車流的右側（從外往路口看的右邊）
			var toward := -away
			var right := Vector2(-toward.y, toward.x)
			var hw := net.half_width(e)
			var base: Vector2 = c + away * (net.node_r[n] + 0.5) + right * (hw + 1.0)
			var S := kit.st("metal", Vector3(base.x, 0, base.y))
			var arm_len := hw * 0.95
			var b3 := Vector3(base.x, 0, base.y)
			var r3 := Vector3(right.x, 0, right.y)
			# 鍍鋅鋼管：直桿往上，彎進橫臂（平滑曲線）
			Props.tube(S, [b3, b3 + Vector3(0, 5.6, 0), b3 + Vector3(0, 6.15, 0) - r3 * 0.25, b3 + Vector3(0, 6.35, 0) - r3 * 0.8,
				b3 + Vector3(0, 6.45, 0) - r3 * arm_len], 0.15, 0.07, Color(0.66, 0.68, 0.7), 14)
			MeshKit.cyl(S, MeshKit.xf_at(b3), 0.26, 0.2, 0.5, 14, Color(0.5, 0.52, 0.54))
			var yaw := atan2(toward.x, toward.y)
			var head: Vector2 = base - right * (arm_len * 0.72)
			var hp := Vector3(head.x, 5.95, head.y)
			var t3 := Vector3(toward.x, 0, toward.y)
			MeshKit.box(S, MeshKit.xf_at(hp + Vector3(0, 0.33, 0), yaw), Vector3(0.08, 0.3, 0.08), Color(0.3, 0.3, 0.3))
			# 燈箱：黑色外殼＋每顆燈的遮光罩（台灣常見橫式，紅黃綠由左到右）
			var HB := kit.st("solid", Vector3(base.x, 0, base.y))
			MeshKit.box(HB, MeshKit.xf_at(hp, yaw), Vector3(1.42, 0.46, 0.32), Color(0.07, 0.07, 0.075))
			var trio := []
			for k in 3:
				var lp := hp + r3 * ((k - 1) * 0.45) - t3 * 0.17
				var axis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)
				MeshKit.cyl(HB, Transform3D(axis, lp), 0.17, 0.17, 0.02, 16, Color(0.12, 0.12, 0.12))
				# 遮光罩（上半圓筒）
				for q in 8:
					var a0 := PI * q / 8.0
					var a1 := PI * (q + 1) / 8.0
					var c0 := lp + r3 * cos(a0) * 0.2 + Vector3(0, sin(a0) * 0.2, 0)
					var c1 := lp + r3 * cos(a1) * 0.2 + Vector3(0, sin(a1) * 0.2, 0)
					MeshKit.quad(HB, c1, c0, c0 - t3 * 0.22, c1 - t3 * 0.22, Color(0.06, 0.06, 0.065))
					MeshKit.quad(HB, c0, c1, c1 - t3 * 0.22, c0 - t3 * 0.22, Color(0.06, 0.06, 0.065))
				var mi := MeshInstance3D.new()
				var sm := CylinderMesh.new()
				sm.top_radius = 0.16
				sm.bottom_radius = 0.16
				sm.height = 0.03
				sm.radial_segments = 20
				mi.mesh = sm
				mi.rotation = Vector3(PI * 0.5, yaw, 0)
				mi.rotation_order = EULER_ORDER_YXZ
				mi.position = lp - t3 * 0.02
				mi.material_override = lamp_mats[["R", "Y", "G"][k]]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visible = false
				add_child(mi)
				trio.append(mi)
			lamps[e] = trio
		lights[n] = {"group": groups, "offset": rng.randf_range(0, 40), "lamps": lamps}


## 某路口、從路段 e 進入時的燈號 "G" / "Y" / "R"（沒有紅綠燈回傳 ""）
func light_state(n: int, e: int) -> String:
	if not lights.has(n):
		return ""
	var L: Dictionary = lights[n]
	var g: int = L.group.get(e, 0)
	var cycle := (GREEN_T + YELLOW_T + ALLRED_T) * 2.0
	var t := fmod(clock + L.offset, cycle)
	var half := GREEN_T + YELLOW_T + ALLRED_T
	var local := t - (0.0 if g == 0 else half)
	if local < 0:
		local += cycle
	if local < GREEN_T:
		return "G"
	if local < GREEN_T + YELLOW_T:
		return "Y"
	return "R"


## 剩餘秒數（倒數計時器）
func light_remain(n: int, e: int) -> float:
	if not lights.has(n):
		return 0.0
	var L: Dictionary = lights[n]
	var g: int = L.group.get(e, 0)
	var cycle := (GREEN_T + YELLOW_T + ALLRED_T) * 2.0
	var half := GREEN_T + YELLOW_T + ALLRED_T
	var local := fmod(clock + L.offset, cycle) - (0.0 if g == 0 else half)
	if local < 0:
		local += cycle
	if local < GREEN_T:
		return GREEN_T - local
	if local < GREEN_T + YELLOW_T:
		return GREEN_T + YELLOW_T - local
	return cycle - local


func _update_lights() -> void:
	for n in lights:
		var L: Dictionary = lights[n]
		for e in L.lamps:
			var st := light_state(n, e)
			var trio: Array = L.lamps[e]
			trio[0].visible = st == "R"
			trio[1].visible = st == "Y"
			trio[2].visible = st == "G"


# ---------------------------------------------------------------- 交通標誌
func _signs() -> void:
	var all: Array = map.signs.duplicate()
	for st in map.stops:
		all.append({"edge": st.edge, "rev": net.edges[st.edge].a == st.node, "t": 0.85, "type": "stop", "value": 0})
	var sid := 0
	var quads := SurfaceTool.new()
	quads.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sp in all:
		var e: int = sp.edge
		if e < 0:
			continue
		var d: Dictionary = net.edges[e]
		var from: int = d.b if sp.rev else d.a
		var to: int = net.other(e, from)
		var dir: Vector2 = (net.nodes[to] - net.nodes[from]).normalized()
		var right := Vector2(-dir.y, dir.x)
		var t: float = sp.t
		var hw := net.half_width(e)
		var off: float = hw + (4.2 if d.walk else 1.4)
		var p: Vector2 = net.nodes[from].lerp(net.nodes[to], t) + right * off
		var big: bool = d.kind == "highway"
		var size := 1.0 if not big else 1.9
		var pole_h := 2.4 if not big else 3.6
		var S := kit.st("solid", Vector3(p.x, 0, p.y))
		MeshKit.cyl(S, MeshKit.xf_at(Vector3(p.x, 0, p.y)), 0.05, 0.05, pole_h + size * 0.5, 5, Color(0.6, 0.6, 0.62), false)
		var yaw := atan2(dir.x, dir.y)     # 盒子 -Z 朝向來車
		var center := Vector3(p.x, pole_h + size * 0.5, p.y)
		MeshKit.box(S, MeshKit.xf_at(center + Vector3(dir.x, 0, dir.y) * 0.04, yaw), Vector3(size * 0.96, size * 0.96, 0.03), Color(0.55, 0.56, 0.58))
		# 標誌面（朝向來車＝-dir 方向看過來）
		var uv := atlas.uv_rect(str(sp.type), int(sp.get("value", 0)))
		var rr := Vector3(right.x, 0, right.y)
		var front := center - Vector3(dir.x, 0, dir.y) * 0.03
		var hs := size * 0.5
		# 從來車看：駕駛的右手邊就是 right
		var A := front - rr * hs + Vector3(0, -hs, 0)
		var B := front + rr * hs + Vector3(0, -hs, 0)
		var C := front + rr * hs + Vector3(0, hs, 0)
		var D := front - rr * hs + Vector3(0, hs, 0)
		MeshKit.quad(quads, A, B, C, D, Color.WHITE, uv.position, uv.end)
		signs.append({"id": sid, "pos": center, "dir": dir, "type": str(sp.type), "value": int(sp.get("value", 0)), "edge": e})
		sid += 1
	var mi := MeshInstance3D.new()
	mi.mesh = quads.commit()
	mi.material_override = mats["sign"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------- 目的地標記
func _dest_marker() -> void:
	dest_marker = Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.0
	cm.bottom_radius = 2.0
	cm.height = 60.0
	cm.radial_segments = 16
	cm.cap_top = false
	cm.cap_bottom = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.2, 1.0, 0.6, 0.28)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.material = m
	mi.mesh = cm
	mi.position.y = 30.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dest_marker.add_child(mi)
	dest_marker.visible = false
	add_child(dest_marker)


func show_dest(p) -> void:
	if p == null:
		dest_marker.visible = false
	else:
		dest_marker.visible = true
		dest_marker.position = Vector3(p.x, 0, p.y)


func _process(delta: float) -> void:
	clock += delta
	_update_lights()
	if rain and follow:
		rain.global_position = follow.global_position + Vector3(0, 14, 0)
