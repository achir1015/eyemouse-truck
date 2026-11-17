class_name SignAtlas
extends SubViewport
## 把所有交通標誌畫到一張 1024×1024 貼圖（8×8 格），3D 路牌用 UV 取用。

const CELLS := 8
const PX := 128
const SPEEDS := [20, 30, 40, 50, 60, 70, 80, 90, 100, 110]

var index := {}       # "type:value" -> cell
var canvas: Control


func _init() -> void:
	size = Vector2i(CELLS * PX, CELLS * PX)
	transparent_bg = true
	render_target_update_mode = SubViewport.UPDATE_ONCE
	var k := 0
	for t in SignArt.QUIZ_TYPES:
		if t == "speed":
			for v in SPEEDS:
				index["speed:%d" % v] = k
				k += 1
		elif t == "guide":
			index["guide:0"] = k
			index["guide:1"] = k + 1
			k += 2
		else:
			index[t + ":0"] = k
			k += 1
	canvas = Control.new()
	canvas.size = Vector2(size)
	canvas.draw.connect(_draw_all)
	add_child(canvas)


func _draw_all() -> void:
	var font: Font = load("res://assets/fonts/ui_font.tres")
	for key in index:
		var cell: int = index[key]
		var r := Rect2((cell % CELLS) * PX + 4, (cell / CELLS) * PX + 4, PX - 8, PX - 8)
		SignArt.draw(canvas, key.get_slice(":", 0), int(key.get_slice(":", 1)), r, font)


func cell_of(type: String, value: int) -> int:
	if type == "speed":
		var best := 50
		for v in SPEEDS:
			if absi(v - value) < absi(best - value):
				best = v
		return index.get("speed:%d" % best, 0)
	return index.get("%s:%d" % [type, value], index.get(type + ":0", 0))


func uv_rect(type: String, value: int) -> Rect2:
	var c := cell_of(type, value)
	var u := 1.0 / CELLS
	return Rect2((c % CELLS) * u, (c / CELLS) * u, u, u)
