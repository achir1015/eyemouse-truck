class_name Lines
extends RefCounted
## 小柯語音文字（id -> 文字）。all() 會再加上導航、標誌、課程自動產生的句子。
## tools/dump_lines.gd 把 all() 輸出成 JSON，tools/gen_voice.py 依此產生預錄語音。

const L := {
	"title_hello": "歡迎回來！我是小柯，今天想開去哪裡呢？",
	"title_back": "回到主選單了。",
	"update_available": "有新版本可以更新了，在主選單右下角按更新就可以。",
	"drive_hello": "出發囉！記得繫安全帶，看清楚後照鏡再起步。",
	"nav_start": "導航開始，請依照平板上的藍色路線行駛。",
	"nav_reroute": "已經重新規劃路線。",
	"nav_arrive": "已經抵達目的地，辛苦了！",
	"nav_300_arrive": "前方三百公尺抵達目的地。",
	"nav_100_arrive": "目的地就在前方，請準備靠邊停車。",
	"ap_on": "小柯自駕開始，我會遵守號誌和速限，你可以轉頭看看風景。",
	"ap_off": "小柯自駕關閉，請握好方向盤。",
	"lka_on": "車道維持開始，我幫你轉方向盤，你負責油門和煞車。",
	"tip_reverse": "倒車中，請看左右後照鏡，慢慢倒。",
	"v_crash": "小心！發生碰撞了，請放慢速度。",
	"v_belt": "還沒有繫安全帶喔，請按 B 繫上安全帶。",
	"v_speed": "超速了，請注意速限。",
	"v_lights": "天色暗或在隧道裡，請打開大燈。",
	"v_wrong": "逆向了！請回到右邊的車道。",
	"v_offroad": "開出道路了，請回到車道上。",
	"v_red": "闖紅燈了！紅燈要停在停止線前面。",
	"v_stop": "看到停字要完全停車，再看清楚左右。",
	"v_blink": "轉彎前要先打方向燈喔。",
	"v_ambulance": "請讓救護車先過，減速靠右。",
	"ev_wind": "側風很強，請抓穩方向盤，放慢速度。",
	"ev_ambulance": "後方有救護車鳴笛，請減速靠右讓道。",
	"ev_accident": "前方發生事故，請減速，打方向燈換到旁邊車道。",
	"res_0": "完成了，不過分數不太夠，再練習一次會更好。",
	"res_1": "完成了！拿到一顆星。",
	"res_2": "做得很好！拿到兩顆星。",
	"res_3": "太厲害了！三顆星滿分表現！",
	"res_fail": "這次沒有完成，沒關係，我們再試一次。",
	"quiz_q": "這個標誌是什麼意思呢？看著答案就可以選。",
	"quiz_ok": "答對了，好棒！",
	"quiz_no": "答錯了，沒關係，記住它就好。",
	"tut_m1": "你好，我是小柯機器人！這是眼動鼠之寶島卡車，可以用眼睛看著按鈕來開車，帶你環遊台灣。",
	"tut_m2": "自由駕駛：選台北、國道一號、日月潭、高雄、太魯閣、墾丁等地圖，自己決定車子、時間、天氣和目的地。",
	"tut_m3": "駕訓班：從起步、轉彎、紅綠燈，一路練到倒車入庫和上高速公路。",
	"tut_m4": "考驗挑戰：下雨天、夜晚、寒流濃霧、夏天、交通事故、塞車、颱風和救護車，看你能不能平安送達。",
	"tut_m5": "交通標誌：認識台灣常見的交通標誌，還有小測驗。",
	"tut_m6": "設定：可以切換眼控駕駛或鍵盤方向盤，調整音量、停留時間和視線轉頭。",
	"tut_m7": "所有按鈕都一樣：看著它，下方的黃色進度條跑完就會選取。",
	"tut_m8": "接下來我們到小柯駕訓場，實際上車看看駕駛室吧！",
	"tut_d1": "這裡是駕駛室，你坐在左邊的駕駛座，前面是擋風玻璃。",
	"tut_d2": "方向盤後面是儀表：左邊車速、右邊轉速，中間是檔位、油量和方向燈。",
	"tut_d3": "中間這台平板是小柯導航：藍色是路線，上方會告訴你多遠要轉彎，也會用語音提醒。",
	"tut_d4": "左右兩邊是後照鏡。只要看畫面最左邊或最右邊，就會像轉頭一樣看過去；看回中間就轉回來。",
	"tut_d5": "這一排是操作按鈕。眼控模式下，看著油門、煞車、左右按鈕就會持續作用；用鍵盤時是 W、S、A、D。",
	"tut_d6": "按小柯自駕，我就會幫你開車，會看紅綠燈、保持車距、打方向燈。現在示範給你看。",
	"tut_d7": "路邊的交通標誌，小柯會自動辨識，在上方顯示並念給你聽。",
	"tut_d8": "右上角是分數，闖紅燈、超速、逆向、碰撞、沒打方向燈都會扣分。",
	"tut_d9": "右邊是小地圖，也可以看平板導航。音樂按鈕可以換下一首車內音樂。",
	"tut_d10": "想休息時按暫停，可以重新開始、再聽一次教學或回主選單。",
	"tut_d11": "教學結束，祝你一路順風，開車要平安喔！",
}

static var _all := {}


static func all() -> Dictionary:
	if not _all.is_empty():
		return _all
	var d := L.duplicate()
	var dirs := {"left": "左轉", "right": "右轉", "uturn": "迴轉"}
	var dist := {500: "前方五百公尺", 300: "前方三百公尺", 100: "前方一百公尺"}
	for k in dirs:
		for m in dist:
			d["nav_%d_%s" % [m, k]] = "%s%s。" % [dist[m], dirs[k]]
		d["nav_now_" + k] = "請現在%s。" % dirs[k]
	for v in [20, 30, 40, 50, 60, 70, 80, 90, 100, 110]:
		d["sign_speed_%d" % v] = "前方速限%d公里。" % v
	for t in SignArt.INFO:
		if t == "speed":
			continue
		d["sign_" + t] = "前方有%s標誌。" % SignArt.name_of(t)
		d["sign_info_" + t] = SignArt.explain(t)
	d["sign_info_speed"] = SignArt.explain("speed")
	for l in Lessons.SCHOOL + Lessons.CHALLENGES:
		d[l.intro] = str(l.title).trim_prefix(str(l.title).get_slice(" ", 0) + " ") + "。" + str(l.desc)
	_all = d
	return d


static func text(id: String) -> String:
	return str(all().get(id, ""))
