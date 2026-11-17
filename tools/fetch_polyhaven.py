"""下載 Poly Haven（CC0 公眾領域）天空 HDRI 與 PBR 材質貼圖 → assets/sky、assets/tex
用法：python -I tools/fetch_polyhaven.py
"""
import json
import os
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UA = {"User-Agent": "godot-asset-fetch"}
SKIES = {  # 用途: (id, 解析度)
    "day": ("kloofendal_48d_partly_cloudy_puresky", "2k"),
    "noon": ("kloofendal_43d_clear_puresky", "2k"),
    "overcast": ("kloofendal_overcast_puresky", "2k"),
    "misty": ("kloofendal_misty_morning_puresky", "1k"),
    "dusk": ("qwantani_dusk_2_puresky", "2k"),
}
TEX = {  # 用途: id
    "asphalt": "asphalt_02",
    "pavers": "concrete_pavers",
    "grass": "leafy_grass",
    "facade_tile": "rectangular_facade_tiles",
    "plaster": "grey_plaster",
    "cliff": "cliff_side",
    "shutter": "painted_metal_shutter",
    "concrete": "concrete",
    "sand": "coast_sand_rocks_02",
    "leather": "fabric_leather_02",
    "plastic": "leather_white",
}
MAPS = {"diff": "Diffuse", "nor": "nor_gl", "rough": "Rough"}


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120).read()


def save(url, path):
    if os.path.exists(path):
        return
    data = get(url)
    open(path, "wb").write(data)
    print("ok", os.path.basename(path), len(data) // 1024, "KB", flush=True)


def main():
    os.makedirs(os.path.join(ROOT, "assets", "sky"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "assets", "tex"), exist_ok=True)
    credits = []
    for name, (pid, res) in SKIES.items():
        info = json.loads(get("https://api.polyhaven.com/files/" + pid))
        save(info["hdri"][res]["hdr"]["url"], os.path.join(ROOT, "assets", "sky", name + ".hdr"))
        credits.append(pid)
    for name, pid in TEX.items():
        info = json.loads(get("https://api.polyhaven.com/files/" + pid))
        for short, key in MAPS.items():
            if key not in info:
                continue
            save(info[key]["1k"]["jpg"]["url"], os.path.join(ROOT, "assets", "tex", f"{name}_{short}.jpg"))
        credits.append(pid)
    open(os.path.join(ROOT, "assets", "CREDITS-polyhaven.txt"), "w", encoding="utf8").write(
        "天空與材質來自 Poly Haven（https://polyhaven.com），CC0 公眾領域授權：\n" + "\n".join(credits) + "\n")


if __name__ == "__main__":
    main()
