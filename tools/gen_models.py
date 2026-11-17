"""用 NVIDIA Build 的 Microsoft TRELLIS API 產生寫實車輛與街景模型（GLB）。

用法：python -I tools/gen_models.py [名稱 ...] [--force] [--jobs=N]
金鑰：環境變數 NVIDIA_API_KEY，或 E:\\3D金融業遊戲\\nvidia_key.txt（使用者 2026-11-17 同意本專案使用）。
輸出：assets/models/<名稱>.glb；已存在的略過。
"""
import base64
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import requests

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "models")
URL = "https://ai.api.nvidia.com/v1/genai/microsoft/trellis"
KEY_FILE = r"E:\3D金融業遊戲\nvidia_key.txt"

MODELS = {
    "truck_tractor": ("realistic modern semi truck tractor unit, blue cab over engine, no trailer", 101),
    "trailer": ("realistic white box semi trailer, long rectangular cargo container on wheels", 102),
    "sedan": ("realistic black luxury sedan car, glossy paint, detailed wheels", 103),
    "car_white": ("realistic white compact family hatchback car, detailed", 104),
    "car_silver": ("realistic silver family sedan car, detailed wheels and windows", 105),
    "car_red": ("realistic red compact city car, detailed", 106),
    "taxi": ("bright yellow four door sedan car, realistic, glossy paint", 207),
    "bus": ("long white and blue passenger coach vehicle, realistic", 208),
    "van": ("realistic small white delivery van", 109),
    "scooter": ("person wearing helmet riding a small motorbike, realistic", 210),
    "ambulance": ("realistic white ambulance van with red stripes and roof lights", 111),
    "tree_street": ("realistic broad leafy green street tree with thick trunk", 112),
    "tree_palm": ("realistic tall coconut palm tree", 113),
    "water_tank": ("stainless steel rooftop water tank on metal legs", 114),
    "ac_unit": ("outdoor air conditioner condenser unit with fan grille", 115),
    "traffic_light": ("realistic traffic signal pole with long arm and horizontal 3 lamp light", 116),
    "street_lamp": ("realistic modern city street light pole with curved arm, metal", 117),
    "utility_pole": ("realistic concrete electricity utility pole with wires crossarm", 118),
    "guardrail": ("realistic steel highway guardrail section on posts", 119),
    "scooter_parked": ("realistic parked motor scooter, glossy, no rider", 120),
    "bus_stop": ("realistic city bus stop shelter with glass and metal roof", 121),
    "tree_banyan": ("realistic large banyan tree with dense green canopy", 122),
    "shrub": ("realistic green round bush shrub", 123),
    "bench": ("wooden park bench with metal legs", 224),
    "traffic_cone": ("orange road cone", 225),
}


def key() -> str:
    k = os.environ.get("NVIDIA_API_KEY", "").strip()
    if not k and os.path.exists(KEY_FILE):
        k = open(KEY_FILE, encoding="utf-8-sig").read().strip()
    if not k.startswith("nvapi-"):
        sys.exit("找不到 NVIDIA 金鑰")
    return k


def gen(name: str, k: str) -> bool:
    prompt, seed = MODELS[name]
    assert len(prompt) <= 77, (name, len(prompt))
    payload = {"mode": "text", "prompt": prompt, "seed": seed, "output_format": "glb"}
    headers = {"Authorization": "Bearer " + k, "Accept": "application/json", "Content-Type": "application/json"}
    tries = int(os.environ.get("TRELLIS_TRIES", "5"))
    for attempt in range(tries):
        t0 = time.time()
        try:
            r = requests.post(URL, headers=headers, json=payload, timeout=600)
        except requests.RequestException as e:
            print(name, "連線錯誤", e, flush=True)
            time.sleep(10)
            continue
        if r.status_code == 429:
            print(name, "請求太頻繁，等 30 秒", flush=True)
            time.sleep(30)
            continue
        if r.status_code != 200:
            print(name, "HTTP", r.status_code, r.text[:200], flush=True)
            if r.status_code in (401, 403):
                return False
            time.sleep(10 + attempt * 10)
            continue
        art = r.json()["artifacts"][0]
        if art.get("finishReason") != "SUCCESS":
            print(name, "失敗：", art.get("finishReason"), flush=True)
            payload["seed"] += 100
            continue
        data = base64.b64decode(art["base64"])
        with open(os.path.join(OUT, name + ".glb"), "wb") as f:
            f.write(data)
        print(f"{name}.glb  {len(data) // 1024} KB  {time.time() - t0:.0f}s", flush=True)
        return True
    return False


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    force = "--force" in sys.argv
    jobs = 3
    for a in sys.argv:
        if a.startswith("--jobs="):
            jobs = int(a.split("=")[1])
    os.makedirs(OUT, exist_ok=True)
    k = key()
    todo = [n for n in MODELS if (not args or n in args) and (force or not os.path.exists(os.path.join(OUT, n + ".glb")))]
    with ThreadPoolExecutor(jobs) as ex:
        res = dict(zip(todo, ex.map(lambda n: gen(n, k), todo)))
    bad = [n for n, ok in res.items() if not ok]
    print("完成" if not bad else "失敗：" + ", ".join(bad), flush=True)


if __name__ == "__main__":
    main()
