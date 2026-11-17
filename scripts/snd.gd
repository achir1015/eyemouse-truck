extends Node
## 聲音：音效、小柯語音（預錄 edge-tts，沒有就用電腦語音）、車內音樂（20 首）、引擎與環境音。

signal speaking_changed(on: bool)
signal track_changed(index: int, title: String)

const SFX := ["click", "select", "tick", "chime", "horn_truck", "horn_car", "blinker", "crash", "air_brake",
	"wiper", "warn", "success", "fail", "door", "bump"]
const LOOPS := ["engine_truck", "engine_car", "rain", "wind", "city", "road"]

var voice := AudioStreamPlayer.new()
var music := AudioStreamPlayer.new()
var pool: Array = []
var streams := {}
var loops := {}                     # name -> AudioStreamPlayer
var tracks: Array = []              # [{file,title,style,seconds}]
var track_index := 0
var _speaking := false
var _tts_voice := ""
var _queue: Array = []              # 等待播放的語音 id
var last_spoken := ""               # 測試用
var spoken_log: Array = []          # 測試用：念過的 id
var music_paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(voice)
	add_child(music)
	voice.finished.connect(_next)
	music.finished.connect(func(): next_track())
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	for s in SFX:
		var path := "res://assets/sfx/%s.wav" % s
		if ResourceLoader.exists(path):
			streams[s] = load(path)
	for s in LOOPS:
		var path := "res://assets/sfx/%s.wav" % s
		var ap := AudioStreamPlayer.new()
		add_child(ap)
		if ResourceLoader.exists(path):
			var st: AudioStreamWAV = load(path)
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_begin = 0
			st.loop_end = int(st.get_length() * st.mix_rate) - 1
			ap.stream = st
		ap.volume_db = -80.0
		loops[s] = ap
	var f := FileAccess.open("res://assets/music/tracks.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_ARRAY:
			tracks = d
	_pick_tts_voice()


func _pick_tts_voice() -> void:
	var best := ""
	for v in DisplayServer.tts_get_voices():
		var lang := str(v.get("language", ""))
		if lang.begins_with("zh") and (lang.contains("TW") or lang.contains("Hant")):
			best = str(v.id)
			break
		if lang.begins_with("zh") and best == "":
			best = str(v.id)
	_tts_voice = best


func vol() -> float:
	return clampf(float(App.settings.volume), 0.0, 1.0)


func play(name: String, v := 1.0, pitch := 1.0) -> void:
	if not streams.has(name) or vol() <= 0.001:
		return
	for p in pool:
		var ap := p as AudioStreamPlayer
		if not ap.playing:
			ap.stream = streams[name]
			ap.volume_db = linear_to_db(maxf(vol() * v, 0.001))
			ap.pitch_scale = pitch
			ap.play()
			return


# ---------------------------------------------------------------- 環境／引擎循環音
func set_loop(name: String, level: float, pitch := 1.0) -> void:
	var ap: AudioStreamPlayer = loops.get(name)
	if ap == null or ap.stream == null:
		return
	level = clampf(level, 0.0, 1.5) * vol()
	if level < 0.005:
		if ap.playing:
			ap.stop()
		return
	ap.volume_db = linear_to_db(level)
	ap.pitch_scale = clampf(pitch, 0.3, 3.5)
	if not ap.playing:
		ap.play()


func stop_loops() -> void:
	for k in loops:
		(loops[k] as AudioStreamPlayer).stop()


# ---------------------------------------------------------------- 小柯語音
func voice_path(id: String) -> String:
	return "res://assets/voice/%s.ogg" % id


## 念一句（id 對應 Lines.L），interrupt=false 時排隊
func say(id: String, interrupt := false) -> void:
	if not bool(App.settings.voice_on) and not id.begins_with("tut_"):
		return
	spoken_log.append(id)
	if spoken_log.size() > 200:
		spoken_log.pop_front()
	if interrupt:
		stop_speaking()
	if voice.playing or (_speaking and DisplayServer.tts_is_speaking()):
		if not _queue.has(id) and _queue.size() < 4:
			_queue.append(id)
		return
	_say_now(id)


func _say_now(id: String) -> void:
	last_spoken = id
	var path := voice_path(id)
	if ResourceLoader.exists(path):
		voice.stream = load(path)
		voice.volume_db = linear_to_db(maxf(vol(), 0.001))
		voice.play()
		_set_speaking(true)
		_duck(true)
	else:
		_tts(Lines.text(id))


func say_text(text: String) -> void:
	stop_speaking()
	_tts(text)


func _tts(text: String) -> void:
	if text == "":
		return
	if _tts_voice == "":
		_pick_tts_voice()
	if _tts_voice == "":
		var all := DisplayServer.tts_get_voices()
		if all.is_empty():
			return
		_tts_voice = str(all[0].id)
	DisplayServer.tts_speak(text.replace("\n", "，"), _tts_voice, int(vol() * 100), 1.0, 1.05, 0, true)
	_set_speaking(true)
	_duck(true)


func _next() -> void:
	if _queue.size() > 0:
		_say_now(_queue.pop_front())
	else:
		_set_speaking(false)
		_duck(false)


func stop_speaking() -> void:
	_queue.clear()
	voice.stop()
	if DisplayServer.tts_is_speaking():
		DisplayServer.tts_stop()
	_set_speaking(false)
	_duck(false)


func is_speaking() -> bool:
	return voice.playing or (_speaking and DisplayServer.tts_is_speaking())


func _set_speaking(v: bool) -> void:
	if v != _speaking:
		_speaking = v
		speaking_changed.emit(v)


# ---------------------------------------------------------------- 車內音樂
func music_vol() -> float:
	return clampf(float(App.settings.music_volume), 0.0, 1.0) * vol()


func _duck(on: bool) -> void:
	if music.playing:
		music.volume_db = linear_to_db(maxf(music_vol() * (0.35 if on else 1.0), 0.0005))


func play_track(i: int) -> void:
	if tracks.is_empty():
		return
	track_index = posmod(i, tracks.size())
	App.settings.music_track = track_index
	var t: Dictionary = tracks[track_index]
	var path := "res://assets/music/" + str(t.file)
	if not ResourceLoader.exists(path):
		return
	var st: AudioStream = load(path)
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = false
	music.stream = st
	music.volume_db = linear_to_db(maxf(music_vol(), 0.0005))
	music.play()
	music_paused = false
	track_changed.emit(track_index, str(t.title))


func next_track() -> void:
	play_track(track_index + 1)


func prev_track() -> void:
	play_track(track_index - 1)


func toggle_music() -> void:
	if music.playing:
		music.stream_paused = not music.stream_paused
		music_paused = music.stream_paused
	else:
		play_track(track_index)


func stop_music() -> void:
	music.stop()


func track_title() -> String:
	if tracks.is_empty():
		return "（沒有音樂）"
	return str(tracks[track_index].title)


func refresh_music_volume() -> void:
	_duck(is_speaking())


func _process(_dt: float) -> void:
	if _speaking and not voice.playing and not DisplayServer.tts_is_speaking():
		_next()
