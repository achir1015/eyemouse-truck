extends SceneTree
## 把高面數的照片掃描樹（Poly Haven glTF，專案外）烘焙成透明背景的正面／側面照片貼圖（impostor）。
## 用法：godot --path . -s res://tools/bake_impostor.gd -- --src=<gltf 絕對路徑> --name=tree_a
## 輸出：assets/tex/<name>_0.png、<name>_1.png（2 個角度）＋ <name>.json（寬高比、高度）

func _init() -> void:
	var src := ""
	var name := "tree"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--src="):
			src = a.substr(6)
		elif a.begins_with("--name="):
			name = a.substr(7)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(src, state) != OK:
		push_error("讀不到 " + src)
		quit(1)
		return
	var scene: Node3D = doc.generate_scene(state)
	var vp := SubViewport.new()
	vp.size = Vector2i(1024, 1024)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	get_root().add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.8)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	vp.add_child(scene)
	var bb := Models.aabb_of(scene)
	var size := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(bb.size.y, maxf(bb.size.x, bb.size.z)) * 1.02
	cam.far = size * 4.0
	vp.add_child(cam)
	cam.current = true
	var c := bb.get_center()
	var meta := {"height_units": bb.size.y, "width_units": maxf(bb.size.x, bb.size.z), "views": 2}
	for k in 2:
		var ang := k * PI * 0.5
		var dir := Vector3(sin(ang), 0, cos(ang))
		cam.look_at_from_position(c + dir * size * 2.0, c, Vector3.UP)
		for f in 4:
			await process_frame
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		# 只留下樹的範圍（裁掉透明邊）
		var used := img.get_used_rect()
		img = img.get_region(used)
		meta["aspect_%d" % k] = float(used.size.x) / float(used.size.y)
		meta["top_%d" % k] = used.position.y
		img.save_png("res://assets/tex/%s_%d.png" % [name, k])
	var f := FileAccess.open("res://assets/tex/%s.json" % name, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	print("baked ", name, " ", meta)
	quit()
