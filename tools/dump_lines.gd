extends SceneTree
## 輸出所有語音文字：godot --headless -s res://tools/dump_lines.gd → tools/lines.json

func _init() -> void:
	var f := FileAccess.open("res://tools/lines.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(Lines.all(), "\t"))
	f.close()
	print("lines ", Lines.all().size())
	quit()
