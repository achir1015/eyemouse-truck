class_name Lessons
extends RefCounted
## 駕訓班課程與各種考驗。
## goal：reach（抵達目的地）、stop_zone（停進白框）、park（停進車格）
## events：accident（前方事故）、jam（塞車）、ambulance（救護車）、wind（颱風側風）

const SCHOOL := [
	{"id": "l_start", "title": "1 起步與停車", "map": "school", "goal": "stop_zone", "zone_edge": [0, 0.75],
		"desc": "繫安全帶、發動引擎、打 D 檔、放開手煞車，慢慢開到前面的白框停好。", "intro": "lesson_start"},
	{"id": "l_lane", "title": "2 車道與速限", "map": "school", "goal": "reach", "dest": "路邊停車場",
		"desc": "沿著車道開，不要超過速限 30，也不要壓到中線。", "intro": "lesson_lane"},
	{"id": "l_turn", "title": "3 轉彎打方向燈", "map": "school", "goal": "reach", "dest": "S 彎道", "need_blinker": true,
		"desc": "照導航開，每次轉彎前先打方向燈（Q 左、E 右）。", "intro": "lesson_turn"},
	{"id": "l_light", "title": "4 紅綠燈與停止線", "map": "school", "goal": "reach", "dest": "倒車入庫場", "start": [1, 7], "density": 0.3,
		"desc": "通過中央路口：紅燈停在停止線前，綠燈再走。", "intro": "lesson_light"},
	{"id": "l_stop", "title": "5 停車再開", "map": "school", "goal": "reach", "dest": "路邊停車場", "start": [2, 5],
		"desc": "看到紅色八角形「停」字，車子要完全停下來，看清楚再開。", "intro": "lesson_stop"},
	{"id": "l_scurve", "title": "6 S 型彎道", "map": "school", "goal": "reach", "dest": "中央路口", "start": [6, 7],
		"desc": "慢慢通過 S 彎，方向盤要提早轉，車身不要碰到路邊。", "intro": "lesson_scurve"},
	{"id": "l_reverse", "title": "7 倒車入庫", "map": "school", "goal": "park", "park": 0, "start_at": "bay",
		"desc": "打 R 檔倒車，看後照鏡，把車子倒進黃色車格，停好再拉手煞車。", "intro": "lesson_reverse"},
	{"id": "l_parallel", "title": "8 路邊停車", "map": "school", "goal": "park", "park": 1, "start_at": "street",
		"desc": "把車子停進路邊的黃色停車格，車身要和道路平行。", "intro": "lesson_parallel"},
	{"id": "l_highway", "title": "9 高速公路匯入", "map": "freeway", "goal": "reach", "dest": "泰安服務區", "density": 0.6,
		"desc": "從交流道加速匯入國道，保持車距、靠右行駛，開到服務區休息。", "intro": "lesson_highway"},
	{"id": "l_signs", "title": "10 交通標誌辨識", "map": "taipei", "goal": "reach", "dest": "國父紀念館", "need_signs": 5, "density": 0.6,
		"desc": "小柯會幫你辨識路邊的交通標誌，至少看懂 5 個標誌並開到國父紀念館。", "intro": "lesson_signs"},
]

const CHALLENGES := [
	{"id": "c_rain", "title": "雨天送貨", "map": "taipei", "dest": "台北101", "weather": "rain", "goal": "reach",
		"desc": "台北下大雨，路面濕滑、視線不好。打開雨刷，煞車要提早。", "intro": "ch_rain"},
	{"id": "c_night", "title": "夜間行車", "map": "kaohsiung", "dest": "港區貨櫃場", "time": "night", "goal": "reach", "need_lights": true,
		"desc": "晚上把貨送到高雄港。記得開大燈（L），注意路口的機車。", "intro": "ch_night"},
	{"id": "c_highway", "title": "國道長途", "map": "freeway", "dest": "台中物流中心", "goal": "reach", "time_limit": 600, "density": 0.9,
		"desc": "從林口開國道一號到台中物流中心，10 分鐘內送達，不要超速。", "intro": "ch_highway"},
	{"id": "c_cold", "title": "寒流濃霧", "map": "taroko", "dest": "天祥", "weather": "cold", "goal": "reach",
		"desc": "寒流來襲，峽谷起濃霧，路面也比較滑。開霧燈（大燈）、放慢速度。", "intro": "ch_cold"},
	{"id": "c_summer", "title": "夏日正午", "map": "kenting", "dest": "鵝鑾鼻燈塔", "time": "noon", "goal": "reach", "density": 0.7,
		"desc": "墾丁大太陽，遊客和機車很多，開到鵝鑾鼻燈塔，注意行人和機車。", "intro": "ch_summer"},
	{"id": "c_accident", "title": "前方事故", "map": "freeway", "dest": "泰安服務區", "goal": "reach", "events": ["accident"], "density": 0.6,
		"desc": "國道前方發生事故佔用車道。看到三角錐要減速、打方向燈換到旁邊車道。", "intro": "ch_accident"},
	{"id": "c_jam", "title": "上班塞車", "map": "taipei", "dest": "總統府", "goal": "reach", "events": ["jam"], "density": 1.4,
		"desc": "上班時間大塞車，跟車要保持距離，不要按太多喇叭，也不要擦撞。", "intro": "ch_jam"},
	{"id": "c_typhoon", "title": "颱風天", "map": "sunmoon", "dest": "慈恩塔", "weather": "storm", "goal": "reach", "events": ["wind"],
		"desc": "颱風來了，大雨加強風，車子會被側風吹動。雙手穩住方向盤，慢慢開。", "intro": "ch_typhoon"},
	{"id": "c_ambulance", "title": "救護車讓道", "map": "kaohsiung", "dest": "85 大樓", "goal": "reach", "events": ["ambulance"], "density": 0.7,
		"desc": "後面有救護車鳴笛開過來，要減速靠右讓救護車先過。", "intro": "ch_ambulance"},
	{"id": "c_scooter", "title": "機車大軍", "map": "taipei", "dest": "台北車站", "goal": "reach", "density": 1.6, "time": "dusk",
		"desc": "傍晚下班機車特別多，轉彎前看後照鏡，小心內輪差。", "intro": "ch_scooter"},
]


static func find(id: String) -> Dictionary:
	for l in SCHOOL + CHALLENGES:
		if l.id == id:
			return l
	return {}


static func stars_for(score: int) -> int:
	if score >= 90:
		return 3
	if score >= 75:
		return 2
	if score >= 60:
		return 1
	return 0
