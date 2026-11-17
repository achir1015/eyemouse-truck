extends SceneTree
## 模型預覽：godot --path . -s res://tools/preview_models.gd -- --shot=檔案.png
## 每個模型縮放到 5 m 排一排，從斜上方看；紅色箭頭標示 -Z（遊戲裡的車頭方向）。

func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.6, 0.65, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.7)
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	root.add_child(sun)
	var names := []
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	for f in DirAccess.get_files_at("res://assets/models"):
		if f.ends_with(".glb") and (only == "" or only.split(",").has(f.get_basename())):
			names.append(f.get_basename())
	names.sort()
	var i := 0
	for n in names:
		var m := Models.make(n, 5.0)
		if m == null:
			continue
		var col := i % 5
		var row := i / 5
		m.position = Vector3(col * 8.0, 0, row * 9.0)
		root.add_child(m)
		var bb := Models.aabb_of(m)
		print("%s size=%s" % [n, bb.size])
		var arrow := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, 0.1, 2.5)
		arrow.mesh = bm
		var am := StandardMaterial3D.new()
		am.albedo_color = Color(1, 0, 0)
		arrow.material_override = am
		arrow.position = m.position + Vector3(0, 0.05, -4.0)
		root.add_child(arrow)
		var lab := Label3D.new()
		lab.text = n
		lab.pixel_size = 0.02
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.position = m.position + Vector3(0, 4.5, 0)
		root.add_child(lab)
		i += 1
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(16, 14, 22), Vector3(16, 0, 4))
	cam.current = true
	for k in 10:
		await process_frame
	if names.size() <= 2:
		cam.look_at_from_position(Vector3(5, 4, 7), Vector3(0, 0.8, 0))
		for k in 3:
			await process_frame
	var shot := "user://preview.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.get_slice("=", 1)
	get_root().get_texture().get_image().save_png(shot)
	quit()
