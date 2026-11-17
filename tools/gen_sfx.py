"""產生音效（全部原創合成）→ assets/sfx/*.wav
用法：python -I tools/gen_sfx.py
循環音（engine_truck、engine_car、rain、wind、city、road）會設好 loop 點（Godot 匯入時用 .import 設定）。
"""
import os
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sfx")
SR = 22050
rng = np.random.default_rng(7)


def save(name, x, loop=False):
    x = np.asarray(x, dtype=np.float64)
    if loop:
        # 頭尾交叉淡化，循環時不會有爆音
        n = int(SR * 0.08)
        head = x[:n].copy()
        x = x[n:]
        x[-n:] = x[-n:] * np.linspace(1, 0, n) + head * np.linspace(0, 1, n)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * 0.85
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def t(sec):
    return np.arange(int(SR * sec)) / SR


def env(n, a=0.005, r=0.1):
    e = np.ones(n)
    na, nr = int(SR * a), int(SR * r)
    if na:
        e[:na] = np.linspace(0, 1, na)
    if nr:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def lowpass(x, k):
    ker = np.ones(k) / k
    return np.convolve(x, ker, mode="same")


def noise(sec):
    return rng.uniform(-1, 1, int(SR * sec))


def engine(base, harmonics, sec=2.0, rough=0.25):
    tt = t(sec)
    x = np.zeros_like(tt)
    # 基頻取整數倍，循環時相位連續
    f0 = round(base * sec) / sec
    for i, a in enumerate(harmonics, 1):
        x += a * np.sin(2 * np.pi * f0 * i * tt + i)
    # 汽缸點火的脈動
    fire = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * f0 * 2 * tt))
    x = x * (0.7 + 0.3 * lowpass(fire, 20))
    x += rough * lowpass(noise(sec), 6)
    return lowpass(x, 3)


def main():
    os.makedirs(OUT, exist_ok=True)
    save("engine_truck", engine(32, [1, 0.8, 0.6, 0.35, 0.25, 0.15], rough=0.35), loop=True)
    save("engine_car", engine(46, [1, 0.5, 0.35, 0.2, 0.1], rough=0.15), loop=True)
    save("rain", lowpass(noise(3.0), 2) * 0.6 + lowpass(noise(3.0), 9) * 0.4, loop=True)
    w = lowpass(noise(3.0), 40)
    save("wind", w * (0.6 + 0.4 * np.sin(2 * np.pi * t(3.0) / 3.0)), loop=True)
    city = lowpass(noise(4.0), 25) * 0.5
    for k in range(5):  # 遠方的機車聲
        st = rng.integers(0, int(SR * 3))
        n = int(SR * 0.8)
        tt = t(0.8)
        city[st:st + n] += 0.15 * np.sin(2 * np.pi * (90 + 30 * tt) * tt) * env(n, 0.3, 0.4)
    save("city", city, loop=True)
    save("road", lowpass(noise(2.0), 14), loop=True)
    # 單次音效
    tt = t(0.06)
    save("click", np.sin(2 * np.pi * 1800 * tt) * np.exp(-tt * 80))
    tt = t(0.18)
    save("select", (np.sin(2 * np.pi * 880 * tt) + 0.6 * np.sin(2 * np.pi * 1320 * tt)) * np.exp(-tt * 18))
    tt = t(0.05)
    save("tick", np.sin(2 * np.pi * 2400 * tt) * np.exp(-tt * 120))
    tt = t(0.9)
    save("chime", (np.sin(2 * np.pi * 784 * tt) * (tt < 0.45) + np.sin(2 * np.pi * 1046 * tt) * (tt >= 0.3)) * np.exp(-tt * 3))
    tt = t(0.9)
    horn = sum(np.sign(np.sin(2 * np.pi * f * tt)) * a for f, a in [(210, 1), (265, 0.8), (315, 0.5)])
    save("horn_truck", lowpass(horn, 8) * env(len(tt), 0.02, 0.08))
    tt = t(0.6)
    horn2 = sum(np.sign(np.sin(2 * np.pi * f * tt)) * a for f, a in [(420, 1), (500, 0.8)])
    save("horn_car", lowpass(horn2, 6) * env(len(tt), 0.01, 0.06))
    tt = t(0.12)
    blink = np.sin(2 * np.pi * 1200 * tt) * np.exp(-tt * 70) + 0.4 * lowpass(noise(0.12), 2) * np.exp(-tt * 90)
    save("blinker", np.concatenate([blink, np.zeros(int(SR * 0.28)), blink * 0.8]))
    n = noise(1.2)
    tt = t(1.2)
    save("crash", (lowpass(n, 3) * np.exp(-tt * 4) + 0.6 * np.sin(2 * np.pi * 70 * tt) * np.exp(-tt * 8)
                   + 0.3 * np.sin(2 * np.pi * 1700 * tt) * np.exp(-tt * 6) * (n > 0.6)))
    tt = t(0.3)
    save("bump", np.sin(2 * np.pi * 80 * tt) * np.exp(-tt * 18) + 0.3 * lowpass(noise(0.3), 5) * np.exp(-tt * 25))
    tt = t(1.0)
    save("air_brake", lowpass(noise(1.0), 1) * env(len(tt), 0.01, 0.6) * np.exp(-tt * 2))
    tt = t(0.5)
    save("wiper", lowpass(noise(0.5), 30) * np.sin(np.pi * tt / 0.5))
    tt = t(0.5)
    save("warn", (np.sin(2 * np.pi * 660 * tt) * (tt < 0.22) + np.sin(2 * np.pi * 520 * tt) * (tt >= 0.25)) * 0.8)
    tt = t(1.0)
    notes = [523, 659, 784, 1046]
    s = np.zeros_like(tt)
    for i, f in enumerate(notes):
        m = (tt >= i * 0.12)
        s += m * np.sin(2 * np.pi * f * tt) * np.exp(-(tt - i * 0.12).clip(0) * 4)
    save("success", s)
    s2 = np.zeros_like(tt)
    for i, f in enumerate([392, 330, 262]):
        m = (tt >= i * 0.18)
        s2 += m * np.sin(2 * np.pi * f * tt) * np.exp(-(tt - i * 0.18).clip(0) * 4)
    save("fail", s2)
    tt = t(0.35)
    save("door", lowpass(noise(0.35), 10) * np.exp(-tt * 14) + np.sin(2 * np.pi * 60 * tt) * np.exp(-tt * 20))
    print("sfx ok")


if __name__ == "__main__":
    main()
