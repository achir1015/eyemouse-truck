extends Node
## 全域：版本、設定、進度（駕訓成績）、測試參數。

const APP_VERSION := "1.0.0"
const APP_NAME := "眼動鼠之寶島卡車"
const SHORT_NAME := "眼動卡車"
const CREDIT := "系統開發：吳玉柱 先生 與 Claude AI Opus 5.5"

const DEFAULTS := {
	"volume": 0.8,
	"music_volume": 0.45,
	"voice_on": true,           # 小柯語音（導航、標誌、提示）
	"nav_voice": true,
	"music_on": true,
	"music_track": 0,
	"control": "keyboard",      # keyboard 鍵盤／方向盤、eye 眼控駕駛
	"look": "gaze",             # gaze 視線轉頭（看畫面邊緣就轉頭）、off
	"look_gain": 1.0,
	"dwell": 0.8,               # 選單停留秒數
	"auto_eyemouse": true,
	"units_hint": true,
	"tutorial_done": false,
	"vehicle": "truck",
	"assist_signs": true,       # 小柯標誌識別
	"fullscreen": false,
	"quality": "high",          # high / low
}

var settings := DEFAULTS.duplicate(true)
var progress := {}              # lesson_id -> {"stars": n, "best": score}
var test_mode := false
var args := {}                  # --key=value 測試參數
var demo := false               # 教學／自動示範中


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	test_mode = args.has("test")
	_load()
	if test_mode:
		settings = DEFAULTS.duplicate(true)
		settings.tutorial_done = true
		settings.auto_eyemouse = false
		if args.has("eye"):
			settings.control = "eye"
	if OS.has_feature("web") or is_mobile():
		settings.auto_eyemouse = false
	if is_mobile():
		settings.quality = "low"
		settings.control = "eye"   # 手機沒有鍵盤：用畫面上的油門、煞車、方向鍵開車
		var df := FileAccess.open("user://diag.txt", FileAccess.WRITE)   # 手機除錯用：系統名稱與標籤
		if df:
			df.store_string("%s mobile=%s ios=%s control=%s safe=%s win=%s" % [OS.get_name(), OS.has_feature("mobile"), OS.has_feature("ios"),
				settings.control, DisplayServer.get_display_safe_area(), DisplayServer.window_get_size()])


## 手機／平板（Godot 4.7 的 iOS 不一定有 "mobile" 標籤，所以也看系統名稱）
static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("ios") or OS.has_feature("android") or OS.get_name() in ["iOS", "Android"]


## 手機瀏海／圓角的安全邊界（視窗座標，左上右下）；電腦與網頁都是 0
func safe_margins(vp: Vector2) -> Vector4:
	if not is_mobile():
		return Vector4.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if win.x < 10 or safe.size.x < 10:
		return Vector4.ZERO
	var k := vp / win
	return Vector4(safe.position.x * k.x, safe.position.y * k.y, (win.x - safe.end.x) * k.x, (win.y - safe.end.y) * k.y)


func arg(key: String, def := "") -> String:
	return str(args.get(key, def))


func _load() -> void:
	var f := FileAccess.open("user://settings.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			for k in d:
				if settings.has(k):
					settings[k] = d[k]
	f = FileAccess.open("user://progress.json", FileAccess.READ)
	if f:
		var p = JSON.parse_string(f.get_as_text())
		if typeof(p) == TYPE_DICTIONARY:
			progress = p


func save() -> void:
	if test_mode:
		return
	var f := FileAccess.open("user://settings.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings, "\t"))
	f = FileAccess.open("user://progress.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(progress, "\t"))


func record(lesson_id: String, stars: int, score: int) -> void:
	var old: Dictionary = progress.get(lesson_id, {"stars": 0, "best": 0})
	progress[lesson_id] = {"stars": maxi(int(old.stars), stars), "best": maxi(int(old.best), score)}
	save()


func stars(lesson_id: String) -> int:
	return int(progress.get(lesson_id, {}).get("stars", 0))


func set_fullscreen(on: bool) -> void:
	settings.fullscreen = on
	if OS.has_feature("web") or is_mobile():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_MAXIMIZED)
