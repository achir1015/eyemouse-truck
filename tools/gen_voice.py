"""產生小柯預錄語音（edge-tts 台灣華語 曉臻）→ assets/voice/<id>.ogg
用法：先 godot --headless -s res://tools/dump_lines.gd，再 python -I tools/gen_voice.py [--force]
只重做文字有變動的（assets/voice/manifest.json）。
"""
import asyncio
import json
import os
import subprocess
import sys

import edge_tts

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "voice")
VOICE = ("zh-TW-HsiaoChenNeural", "+2%", "+6Hz")


def clean(t):
    return t.replace("「", "").replace("」", "").replace("（", "，").replace("）", "，").replace("Q", " Q ").replace("km/h", "公里")


async def speak(text, path):
    mp3 = path[:-4] + ".mp3"
    for attempt in range(6):
        try:
            await edge_tts.Communicate(clean(text), VOICE[0], rate=VOICE[1], pitch=VOICE[2]).save(mp3)
            break
        except Exception as e:  # noqa: BLE001
            print("retry", os.path.basename(path), e, flush=True)
            await asyncio.sleep(2 + attempt * 2)
    else:
        raise RuntimeError("語音失敗：" + text)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", mp3, "-ac", "1", "-ar", "24000", "-c:a", "libvorbis", "-q:a", "3", path], check=True)
    os.remove(mp3)


async def main():
    force = "--force" in sys.argv
    lines = json.load(open(os.path.join(ROOT, "tools", "lines.json"), encoding="utf8"))
    os.makedirs(OUT, exist_ok=True)
    mf = os.path.join(OUT, "manifest.json")
    old = json.load(open(mf, encoding="utf8")) if os.path.exists(mf) else {}
    todo = [k for k, t in lines.items() if t and (force or old.get(k) != t or not os.path.exists(os.path.join(OUT, k + ".ogg")))]
    print(f"共 {len(lines)} 句，要產生 {len(todo)}", flush=True)
    sem = asyncio.Semaphore(8)

    async def one(k):
        async with sem:
            await speak(lines[k], os.path.join(OUT, k + ".ogg"))
            old[k] = lines[k]

    await asyncio.gather(*(one(k) for k in todo))
    for k in list(old):
        if k not in lines:
            old.pop(k)
            p = os.path.join(OUT, k + ".ogg")
            if os.path.exists(p):
                os.remove(p)
    json.dump(old, open(mf, "w", encoding="utf8"), ensure_ascii=False, indent=0)
    print("done", flush=True)


if __name__ == "__main__":
    asyncio.run(main())
