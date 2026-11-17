#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""眼動鼠之歐卡 2 — 車內音樂（電台）產生器

以 numpy 加法／FM 合成器即時「作曲＋演奏＋混音」出 20 首原創器樂曲，
全部由固定亂數種子決定，重跑會得到完全相同的檔案。

輸出：assets/music/track01.ogg … track20.ogg 與 assets/music/tracks.json

用法：
    python -I tools/gen_music.py            # 全部 20 首
    python -I tools/gen_music.py --only 5   # 只重做第 5 首
    python -I tools/gen_music.py --verify   # 解碼檢查已產生的檔案
"""
import argparse
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from scipy.ndimage import maximum_filter1d, minimum_filter1d, uniform_filter1d
from scipy.signal import butter, lfilter, oaconvolve, sosfilt

SR = 32000
TAIL = 3.5                     # 曲末殘響秒數
VORBIS_Q = "0"                 # ffmpeg libvorbis -q:a
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "music")

MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]
HARM_MINOR = [0, 2, 3, 5, 7, 8, 11]
DORIAN = [0, 2, 3, 5, 7, 9, 10]
MIXO = [0, 2, 4, 5, 7, 9, 10]
PENTA_MAJ = [0, 2, 4, 7, 9]
BLUES = [0, 3, 5, 6, 7, 10]

QUAL = {
    "maj": [0, 4, 7], "min": [0, 3, 7], "dim": [0, 3, 6], "aug": [0, 4, 8],
    "7": [0, 4, 7, 10], "maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10],
    "m7b5": [0, 3, 6, 10], "sus4": [0, 5, 7], "sus2": [0, 2, 7],
    "add9": [0, 4, 7, 14], "madd9": [0, 3, 7, 14], "9": [0, 4, 7, 10, 14],
    "maj9": [0, 4, 7, 11, 14], "m9": [0, 3, 7, 10, 14], "6": [0, 4, 7, 9],
}


# ════════════════════════════════════════════════════════════ 合成器
def _t(n):
    return np.arange(n, dtype=np.float64) / SR


def env_ar(n, n_on, att, rel):
    e = np.ones(n)
    na = min(n, max(1, int(att * SR)))
    e[:na] = np.linspace(0.0, 1.0, na)
    if n_on < n:
        k = np.arange(n - n_on) / SR
        e[n_on:] *= np.exp(-k * 5.0 / max(rel, 1e-3))
    return e


def partials(freq, n, ratios, amps, decays=None, vib=None, glide=None, poff=0.7):
    t = _t(n)
    if glide is not None:
        gs, gt = glide
        fi = freq * 2.0 ** (gs * np.exp(-t / gt) / 12.0)
        base = 2 * np.pi * np.cumsum(fi) / SR
    else:
        base = 2 * np.pi * freq * t
    if vib is not None:
        r, d, dl = vib
        c = 2.0 ** (d / 12.0) - 1.0
        ramp = np.clip((t - dl) / 0.35, 0.0, 1.0)
        base = base + ramp * (freq * c / r) * (1.0 - np.cos(2 * np.pi * r * t))
    out = np.zeros(n)
    for i, (ra, a) in enumerate(zip(ratios, amps)):
        if a == 0 or freq * ra > 0.45 * SR:
            continue
        x = np.sin(base * ra + poff * i)
        if decays is not None and decays[i] > 0:
            x *= np.exp(-decays[i] * t)
        out += a * x
    return out


def _nn(dur, rel):
    return int((dur + rel) * SR), int(dur * SR)


def i_piano(f, dur):
    n, on = _nn(dur, 0.3)
    B = 0.00025 * (f / 262.0)
    ks = np.arange(1, 13)
    ratios = ks * np.sqrt(1 + B * ks * ks)
    amps = [1, .6, .35, .25, .15, .1, .07, .05, .035, .025, .02, .015]
    base = 0.8 * (f / 262.0) ** 0.55 + 0.25
    dec = [base * (1 + 0.45 * i) for i in range(12)]
    x = partials(f, n, ratios, amps, dec) + 0.5 * partials(f * 1.0009, n, ratios[:6], amps[:6], dec[:6], poff=1.9)
    return x * env_ar(n, on, 0.002, 0.3)


def i_epiano(f, dur):
    n, on = _nn(dur, 0.35)
    t = _t(n)
    idx = 1.8 * np.exp(-t * 5) + 0.25
    w = 2 * np.pi * f * t
    x = np.sin(w + idx * np.sin(w)) * np.exp(-t * (0.6 + f / 1200.0))
    if f * 5 < 14000:
        x += 0.12 * np.sin(w * 5.0) * np.exp(-t * 15)
    x *= 1 + 0.12 * np.sin(2 * np.pi * 4.5 * t)
    return x * env_ar(n, on, 0.002, 0.35)


def _simple(f, dur, rel, att, ratios, amps, dec=None, vib=None, glide=None):
    n, on = _nn(dur, rel)
    return partials(f, n, ratios, amps, dec, vib, glide) * env_ar(n, on, att, rel)


def i_bass_finger(f, dur):
    return _simple(f, dur, .07, .008, range(1, 7), [1, .5, .3, .18, .1, .06], [.9, 2, 3.5, 5, 7, 9])


def i_bass_upright(f, dur):
    return _simple(f, dur, .1, .012, range(1, 6), [1, .45, .2, .1, .05], [1.6, 3, 5, 7, 9])


def i_bass_slap(f, dur):
    return _simple(f, dur, .06, .002, range(1, 11), [1, .7, .6, .5, .4, .3, .25, .2, .15, .1],
                   [1.2, 3, 5, 7, 9, 11, 13, 15, 17, 19])


def i_bass_synth(f, dur):
    ks = list(range(1, 17))
    x = _simple(f, dur, .06, .004, ks, [1.0 / k for k in ks], [.3 + 1.6 * k for k in ks])
    n, on = _nn(dur, .06)
    return x + 0.5 * np.sin(2 * np.pi * f * _t(n)) * env_ar(n, on, .004, .06)


def i_bass_sub(f, dur):
    return _simple(f, dur, .08, .01, [1, 2, 3], [1, .25, .08])


def i_bass_tri(f, dur):
    ks = [1, 3, 5, 7, 9, 11, 13]
    return _simple(f, dur, .03, .003, ks, [1.0 / k ** 2 for k in ks])


def _saws(f, n, cents, nh, roll):
    ks = list(range(1, nh + 1))
    amps = [np.exp(-k / roll) / k for k in ks]
    return sum(partials(f * 2 ** (c / 1200.0), n, ks, amps, poff=0.7 + j) for j, c in enumerate(cents)) / len(cents)


def i_pad(f, dur):
    n, on = _nn(dur, 1.2)
    return _saws(f, n, (-8, 0, 8), 10, 5.0) * env_ar(n, on, 0.6, 1.2)


def i_pad_warm(f, dur):
    n, on = _nn(dur, 1.5)
    x = partials(f, n, [1, 2, 3, 4], [1, .3, .15, .08]) + 0.7 * partials(f * 1.004, n, [1, 2, 3], [1, .3, .1], poff=2.1)
    return x * env_ar(n, on, 1.0, 1.5)


def i_strings(f, dur):
    n, on = _nn(dur, 0.6)
    ks = list(range(1, 13))
    amps = [np.exp(-k / 7.0) / k for k in ks]
    x = (partials(f * 2 ** (-6 / 1200.0), n, ks, amps, vib=(5.3, .12, .15))
         + partials(f * 2 ** (6 / 1200.0), n, ks, amps, vib=(5.0, .12, .2), poff=1.7))
    return x * env_ar(n, on, 0.25, 0.6)


def i_brass(f, dur):
    ks = list(range(1, 13))
    return _simple(f, dur, .15, .05, ks, [np.exp(-k / 8.0) / k ** .9 for k in ks], vib=(5, .08, .3))


def i_pluck(f, dur):
    ks = list(range(1, 13))
    return _simple(f, dur, .2, .002, ks, [1.0 / k for k in ks], [2.5 + 2.2 * k for k in ks])


def i_harp(f, dur):
    return _simple(f, dur, .4, .002, range(1, 6), [1, .4, .2, .1, .05], [1.2 + .8 * k for k in range(1, 6)])


def i_guitar(f, dur):
    ks = np.arange(1, 11)
    amps = [abs(np.sin(np.pi * k * 0.18)) / k ** .6 for k in ks]
    return _simple(f, dur, .1, .002, ks * np.sqrt(1 + 0.0001 * ks * ks), amps, [1.2 + 1.1 * k for k in ks])


def i_nylon(f, dur):
    return _simple(f, dur, .15, .003, range(1, 8), [1, .55, .3, .2, .1, .06, .04], [1.4 + .9 * k for k in range(1, 8)])


def i_organ(f, dur):
    n, on = _nn(dur, .08)
    x = partials(f, n, [.5, 1, 2, 3, 4, 6, 8], [.5, 1, .7, .4, .3, .15, .1])
    x *= 1 + 0.1 * np.sin(2 * np.pi * 6.5 * _t(n))
    return x * env_ar(n, on, .008, .08)


def i_lead_saw(f, dur):
    n, on = _nn(dur, .12)
    ks = list(range(1, 19))
    amps = [np.exp(-k / 9.0) / k for k in ks]
    x = (partials(f * 2 ** (-5 / 1200), n, ks, amps, vib=(5.6, .18, .22))
         + partials(f * 2 ** (5 / 1200), n, ks, amps, vib=(5.6, .18, .22), poff=2.3))
    return x * env_ar(n, on, .012, .12)


def i_lead_square(f, dur):
    ks = list(range(1, 18, 2))
    return _simple(f, dur, .1, .01, ks, [np.exp(-k / 12.0) / k for k in ks], vib=(5.5, .15, .25))


def i_chip_square(f, dur):
    ks = list(range(1, 31, 2))
    return _simple(f, dur, .02, .002, ks, [1.0 / k for k in ks])


def i_chip_pulse(f, dur):
    ks = list(range(1, 31))
    return _simple(f, dur, .02, .002, ks, [abs(np.sin(np.pi * k * .25)) / k for k in ks])


def i_flute(f, dur):
    n, on = _nn(dur, .12)
    x = partials(f, n, [1, 2, 3, 4], [1, .22, .1, .04], vib=(5, .2, .15))
    r = np.random.default_rng(int(f * 10))
    br = sosfilt(butter(2, [min(f * 0.8, 9000), min(f * 3, 14000)], "bandpass", fs=SR, output="sos"), r.standard_normal(n))
    x += 0.25 * br / (np.std(br) + 1e-9) * 0.12
    return x * env_ar(n, on, .07, .12)


def i_sax(f, dur):
    ks = list(range(1, 13))
    amps = [1, .85, .7, .55, .42, .32, .24, .18, .13, .09, .06, .04]
    return _simple(f, dur, .1, .035, ks, amps, vib=(5.2, .2, .2))


def i_bell(f, dur):
    n, on = _nn(dur, .6)
    x = partials(f, n, [1, 2.0, 2.76, 5.4, 8.93], [1, .35, .45, .2, .1], [1.0, 1.8, 2.5, 4, 6])
    return x * env_ar(n, on, .001, .6)


def i_marimba(f, dur):
    return _simple(f, dur, .2, .001, [1, 3.93, 9.9], [1, .25, .08], [4, 12, 25])


def i_steel(f, dur):
    return _simple(f, dur, .25, .03, range(1, 9), [1, .5, .3, .2, .12, .08, .05, .03],
                   vib=(5, .12, .3), glide=(-0.8, .06))


def i_guzheng(f, dur):
    ks = list(range(1, 11))
    return _simple(f, dur, .3, .002, ks, [1, .7, .5, .35, .25, .18, .12, .08, .05, .03],
                   [.9 + .7 * k for k in ks], vib=(6, .3, .35))


def i_clav(f, dur):
    ks = list(range(1, 21))
    return _simple(f, dur, .03, .001, ks, [abs(np.sin(np.pi * k * .2)) / k for k in ks], [5 + 1.5 * k for k in ks])


def i_timpani(f, dur):
    n, on = _nn(dur, 1.0)
    x = partials(f, n, [1, 1.5, 1.98, 2.44], [1, .5, .35, .2], [2.5, 3.5, 4.5, 5.5])
    r = np.random.default_rng(int(f))
    th = sosfilt(butter(2, 400, "lowpass", fs=SR, output="sos"), r.standard_normal(n)) * np.exp(-_t(n) * 30)
    return (x + 0.6 * th / (np.max(np.abs(th)) + 1e-9)) * env_ar(n, on, .003, 1.0)


INSTR = {k[2:]: v for k, v in globals().items() if k.startswith("i_")}


class Synth:
    def __init__(self):
        self.cache = {}

    def note(self, inst, midi, dur):
        d = max(0.04, round(dur * 50) / 50.0)
        key = (inst, int(midi), d)
        x = self.cache.get(key)
        if x is None:
            f = 440.0 * 2 ** ((int(midi) - 69) / 12.0)
            x = INSTR[inst](f, d)
            x = (x / max(1e-9, np.max(np.abs(x)))).astype(np.float32)
            self.cache[key] = x
        return x


# ════════════════════════════════════════════════════════════ 鼓組
def make_kit(kind, seed):
    r = np.random.default_rng(seed)
    FT = {"hp": "highpass", "lp": "lowpass", "bp": "bandpass"}

    def nz(n):
        return r.standard_normal(n)

    def flt(x, k, f, order=2):
        return sosfilt(butter(order, f, FT[k], fs=SR, output="sos"), x)

    def ex(n, rate):
        return np.exp(-_t(n) * rate)

    def sh(n, hold):            # 晶片風取樣保持雜訊
        return np.repeat(r.standard_normal(n // hold + 1), hold)[:n]

    kit = {}
    n = int(.55 * SR); t = _t(n)
    if kind == "electronic":
        f = 44 + 120 * np.exp(-t * 20); a = np.exp(-t * 4.0)
    elif kind == "lofi":
        f = 48 + 75 * np.exp(-t * 26); a = np.exp(-t * 8)
    elif kind == "chip":
        f = 40 + 180 * np.exp(-t * 35); a = np.exp(-t * 10)
    else:
        f = 52 + 95 * np.exp(-t * 32); a = np.exp(-t * 7)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * a
    if kind == "chip":
        x = np.sign(x) * a * 0.7
    nc = int(.006 * SR)
    x[:nc] += flt(nz(nc), "hp", 1500) * ex(nc, 600) * 0.25
    kit["K"] = x

    n = int(.35 * SR); t = _t(n)
    body = np.sin(2 * np.pi * 185 * t + 0.6 * np.exp(-t * 40)) * np.exp(-t * 22)
    if kind == "chip":
        noise = sh(n, 6) * np.exp(-t * 14); body *= 0.4
    else:
        noise = flt(nz(n), "bp", [1200, 9000]) * np.exp(-t * (9 if kind == "electronic" else 17))
        if kind == "lofi":
            noise = flt(noise, "lp", 4500)
    noise /= np.max(np.abs(noise))
    kit["S"] = 0.55 * body + noise

    n = int(.4 * SR); t = _t(n)
    cp = np.zeros(n)
    for o in (0, .011, .022):
        s = int(o * SR)
        cp[s:] += np.exp(-_t(n - s) * 120)
    cp += 0.5 * np.exp(-t * 14)
    kit["CP"] = flt(nz(n) * cp, "bp", [900, 5000])

    for name, ln, rate in (("H", .12, 55), ("O", .5, 7)):
        n = int(ln * SR)
        src = sh(n, 2) if kind == "chip" else flt(nz(n), "hp", 7000)
        kit[name] = src * ex(n, rate)
    n = int(1.2 * SR); t = _t(n)
    kit["R"] = flt(nz(n), "hp", 5000) * np.exp(-t * 3) * 0.5 + sum(
        a * np.sin(2 * np.pi * fr * t) for fr, a in ((3150, .2), (4870, .15), (5900, .1))) * np.exp(-t * 4)
    n = int(2.0 * SR)
    kit["CR"] = flt(flt(nz(n), "hp", 4000), "lp", 12000) * ex(n, 2.2)
    n = int(.08 * SR); t = _t(n)
    kit["RS"] = (np.sin(2 * np.pi * 1700 * t) * np.exp(-t * 90) + 0.6 * np.sin(2 * np.pi * 450 * t) * np.exp(-t * 60)
                 + 0.5 * flt(nz(n), "bp", [2000, 6000]) * np.exp(-t * 80))
    n = int(.1 * SR); t = _t(n)
    kit["SH"] = flt(nz(n), "hp", 6000) * np.minimum(1, t / .01) * np.exp(-t * 35)
    n = int(.3 * SR); t = _t(n)
    kit["BR"] = flt(nz(n), "bp", [1000, 6000]) * np.minimum(1, t / .015) * np.exp(-t * 12)
    for name, fr in (("CG", 330), ("CL", 220)):
        n = int(.35 * SR); t = _t(n)
        ph = 2 * np.pi * np.cumsum(fr * (1 + 0.3 * np.exp(-t * 40))) / SR
        kit[name] = np.sin(ph) * np.exp(-t * 13) + 0.3 * flt(nz(n), "bp", [1500, 5000]) * np.exp(-t * 90)
    n = int(.3 * SR); t = _t(n)
    kit["CB"] = flt(np.sign(np.sin(2 * np.pi * 540 * t)) + np.sign(np.sin(2 * np.pi * 800 * t)), "bp", [500, 4000]) * np.exp(-t * 12)
    for name, fr in (("T1", 220), ("T2", 165), ("T3", 120)):
        n = int(.45 * SR); t = _t(n)
        ph = 2 * np.pi * np.cumsum(fr * (1 + 0.4 * np.exp(-t * 25))) / SR
        y = np.sin(ph) * np.exp(-t * 7)
        if kind == "chip":
            y = np.sign(y) * np.exp(-t * 9) * 0.6
        kit[name] = y + 0.15 * flt(nz(n), "lp", 3000) * np.exp(-t * 30)
    for k in kit:
        kit[k] = (kit[k] / np.max(np.abs(kit[k]))).astype(np.float32)
    return kit


DGAIN = {"K": 1.0, "S": .75, "CP": .6, "H": .3, "O": .28, "R": .26, "CR": .36, "RS": .45, "SH": .22,
         "BR": .5, "CG": .45, "CL": .45, "CB": .2, "T1": .6, "T2": .6, "T3": .65}
DPAN = {"H": .25, "O": .25, "R": -.3, "CR": -.2, "SH": .35, "CG": -.3, "CL": .3, "CB": .2,
        "T1": .3, "T2": 0.0, "T3": -.3, "RS": -.05}
DREV = {"K": .03, "S": .22, "CP": .25, "H": .05, "O": .1, "R": .15, "CR": .2, "RS": .2, "SH": .1,
        "BR": .2, "CG": .2, "CL": .2, "CB": .15, "T1": .2, "T2": .2, "T3": .2}
VCH = {".": 0, "g": .3, "o": .55, "x": .8, "X": 1.0}

DP = {
    "pop": dict(main=dict(K="X.....x.X.......", S="....X.......X...", H="x.o.x.o.x.o.x.o."),
                chorus=dict(K="X.....x.X.x.....", H="x.x.x.x.x.x.x.x.", O="..............o.")),
    "rock": dict(main=dict(K="X......xX.x.....", S="....X.......X...", H="X.x.X.x.X.x.X.x."),
                 chorus=dict(H="", R="X.x.X.x.X.x.X.x.", K="X.....xxX.x...x.")),
    "lofi": dict(main=dict(K="X......x..X.....", S="....X.......X..g", H="x.g.x.gxx.g.x.g.")),
    "smooth": dict(main=dict(K="X.....x...x.....", RS="....x.......x...", H="xgxgxgxgxgxgxgxg"),
                   chorus=dict(RS="", S="....x.......x...")),
    "synthwave": dict(main=dict(K="X...X...X...X...", S="....X.......X...", H="..x...x...x...x."),
                      chorus=dict(H="x.x.x.x.x.x.x.x.", O="..o...o...o...o.")),
    "folk": dict(main=dict(K="X.......X.......", RS="....o.......o...", SH="xgogxgogxgogxgog"),
                 chorus=dict(RS="", S="....x.......x...", K="X.....x.X.......")),
    "bossa": dict(main=dict(K="o..xo..xo..xo..x", RS="x..x..x...x..x..", H="gogogogogogogogo"),
                  chorus=dict(SH="xgxgxgxgxgxgxgxg")),
    "funk": dict(main=dict(K="X.x.......x..x..", S="....X..g.g..X..g", H="XxoxXxoxXxoxXxox"),
                 chorus=dict(O="......o.......o.")),
    "onedrop": dict(main=dict(K="........X.......", RS="........X.......", H="x.x.x.x.x.x.x.x."),
                    chorus=dict(RS="", S="........X.......", SH="..x...x...x...x.")),
    "train": dict(main=dict(K="X.......X.......", BR="gogoXogogogoXogo"),
                  chorus=dict(BR="", S="....X.......X...", H="x.x.x.x.x.x.x.x.")),
    "house": dict(main=dict(K="X...X...X...X...", CP="....X.......X...", O="..o...o...o...o.", SH="gggggggggggggggg"),
                  chorus=dict(H="xgxgxgxgxgxgxgxg"),
                  bridge=dict(CP="....x.......x...", O="..o...o...o...o.", SH="gggggggggggggggg")),
    "shuffle": dict(main=dict(K="X.......X.......", S="....X.......X...", R="x.x.x.x.x.x.x.x."),
                    chorus=dict(R="X.x.X.x.X.x.X.x.", K="X.....x.X.......")),
    "chip": dict(main=dict(K="X.......X.x.....", S="....X.......X...", H="x.x.x.x.x.x.x.x."),
                 chorus=dict(H="xgxgxgxgxgxgxgxg")),
    "latin": dict(main=dict(K="...x.......x....", CB="x.o.x.o.x.o.x.o.", CG="..x.g.x...x.g.x.", CL="......x.......xx",
                            RS="....x...x.......x.....x.....x...", SH="xgxgxgxgxgxgxgxg"),
                  chorus=dict(K="X..x....X..x....", O="..............o.")),
}
HALFTIME = dict(K="X.........x.....", S="........X.......", H="x...x...x...x...")
INTRO_PIECES = ("H", "SH", "R", "RS", "CB", "O", "BR")
ENERGY = {"intro": .7, "verse": .85, "pre": .9, "chorus": 1.0, "inter": .85, "bridge": .82, "solo": 1.0, "outro": .85}

FILLS = {
    "snare": [(8, "K", .8), (12, "S", .5), (13, "S", .65), (14, "S", .8), (15, "S", 1.0)],
    "tom": [(8, "T1", .8), (10, "T1", .75), (11, "T2", .8), (12, "T2", .85), (13, "T3", .85), (14, "T3", .9), (15, "S", 1.0)],
    "mix": [(8, "S", .6), (10, "S", .7), (11, "T1", .75), (12, "T2", .8), (14, "T3", .9), (15, "T3", .95)],
}


# ════════════════════════════════════════════════════════════ 和聲
def parse_chord(tok, scale, sev):
    q = None
    if ":" in tok:
        tok, q = tok.split(":")
    if tok.startswith("b"):
        root = (MAJOR[int(tok[1:]) - 1] - 1) % 12
        ivs = QUAL[q or ("maj7" if sev else "maj")]
    else:
        d = int(tok) - 1
        root = scale[d]
        if q:
            ivs = QUAL[q]
        else:
            ivs = []
            for i in range(4 if sev else 3):
                j = d + 2 * i
                ivs.append(scale[j % 7] + 12 * (j // 7) - root)
    return root, list(ivs)


def mk_chord(key, tr, root, ivs):
    pc = (key + tr + root) % 12
    return {"root": pc, "ivs": ivs, "pcs": {(pc + iv) % 12 for iv in ivs}}


def voice(ch, center):
    lo = center - 6
    out = set()
    for iv in ch["ivs"]:
        if len(ch["ivs"]) > 4 and iv == 7:
            continue
        pc = (ch["root"] + iv) % 12
        out.add(lo + (pc - lo) % 12)
    return sorted(out)


def broot(ch, lo):
    return lo + (ch["root"] - lo) % 12


# ════════════════════════════════════════════════════════════ 伴奏型
def comp_events(pat, chords, bar_i, center, rng):
    """回傳 [(拍位置, 拍長, [midi...], 力度, 撥弦錯開秒數)]"""
    ev = []

    def at(p):
        for c0, cl, ch in chords:
            if c0 - 1e-6 <= p < c0 + cl - 1e-6:
                return ch, c0, cl
        c0, cl, ch = chords[-1]
        return ch, c0, cl

    def hits(lst, top=None):
        for p, d, v in lst:
            ch, c0, cl = at(p)
            vo = voice(ch, center)
            if top:
                vo = vo[-top:]
            ev.append((p, min(d, c0 + cl - p), vo, v, 0.0))
        for c0, cl, ch in chords:          # 換和弦處一定要有一下
            if not any(abs(e[0] - c0) < 0.3 for e in ev):
                ev.append((c0, min(0.9, cl), voice(ch, center), .75, 0.0))

    if pat == "sustain":
        for c0, cl, ch in chords:
            ev.append((c0, cl, voice(ch, center), .75, 0.0))
    elif pat == "pop":
        hits([(0, 1.4, .9), (1.5, .9, .7), (2.5, 1.4, .8), (3.5, .45, .65)])
    elif pat == "block":
        hits([(0, .9, .9), (1, .9, .7), (2, .9, .8), (3, .9, .7)])
    elif pat == "syncop":
        hits([(0, .9, .9), (1.5, .4, .7), (2, .4, .6), (2.5, 1.2, .85), (3.5, .4, .7)])
    elif pat == "jazzcomp":
        tpl = [[(0, 1.4, .8), (2.5, 1.2, .7)], [(.5, .9, .75), (2, 1.5, .8)],
               [(0, .4, .8), (1.5, 1.0, .7), (3, .8, .7)], [(1, .9, .7), (2.5, 1.4, .8)]]
        hits(tpl[int(rng.integers(len(tpl)))])
    elif pat == "funk16":
        hits([(0, .2, 1), (.75, .15, .6), (1.5, .2, .8), (2, .15, .5), (2.25, .2, .8), (3, .2, .9), (3.5, .15, .6), (3.75, .15, .7)], top=3)
    elif pat == "stab":
        hits([(0, .4, .95), (2.5, .3, .8), (3, .6, .9)])
    elif pat == "stab_off":
        hits([(.5, .35, .9), (1.5, .3, .8), (2.5, .35, .9), (3.5, .3, .8)])
    elif pat == "skank":
        hits([(1, .22, .9), (3, .22, .9)], top=3)
    elif pat == "bubble":
        hits([(.5, .25, .6), (1.5, .25, .55), (2.5, .25, .6), (3.5, .25, .55)], top=3)
    elif pat == "chick":
        hits([(1, .35, .8), (3, .35, .8)])
    elif pat == "shuffle":
        hits([(0, 1.3, .8), (1.5, .35, .6), (2, 1.3, .8), (3.5, .35, .6)])
    elif pat == "bossa":
        if bar_i % 2 == 0:
            hits([(0, 1.3, .85), (1.5, .9, .7), (3, .9, .75)])
        else:
            hits([(.5, 1.2, .75), (2, 1.3, .8), (3.5, .45, .65)])
    elif pat == "strum":
        pos = [(0, 1, .95), (1, -1, .7), (1.5, 1, .55), (2.5, -1, .6), (3, 1, .8), (3.5, -1, .55)]
        for i, (p, dr, v) in enumerate(pos):
            ch, c0, cl = at(p)
            vo = [broot(ch, center - 18)] + voice(ch, center) + [voice(ch, center)[0] + 12]
            if dr < 0:
                vo = vo[-4:][::-1]
            nxt = pos[i + 1][0] if i + 1 < len(pos) else 4.0
            ev.append((p, min(nxt - p, c0 + cl - p) * 1.1, vo, v, 0.011))
    elif pat == "fingerpick":
        for i in range(8):
            p = i * .5
            ch, c0, cl = at(p)
            vo = voice(ch, center)
            b = broot(ch, center - 18)
            seq = [b, vo[min(2, len(vo) - 1)], vo[1], vo[-1], b + 7, vo[min(2, len(vo) - 1)], vo[1], vo[-1]]
            ev.append((p, min(1.5, c0 + cl - p + .5), [seq[i]], .8 if i % 4 == 0 else .62, 0.0))
    elif pat in ("arp8", "arp16", "harp", "chiparp"):
        step = .5 if pat in ("arp8", "harp") else .25
        nstep = int(4 / step)
        for i in range(nstep):
            p = i * step
            ch, c0, cl = at(p)
            vo = voice(ch, center)
            if pat == "harp":
                seq = vo + [x + 12 for x in vo]
            elif pat == "chiparp":
                seq = vo[:3]
            else:
                s0 = vo + [vo[0] + 12]
                seq = s0 + s0[-2:0:-1]
            k = int(round((p - c0) / step))
            d = step * (3.0 if pat in ("arp8", "harp") else 1.1)
            ev.append((p, d, [seq[k % len(seq)]], .8 if i % (nstep // 4) == 0 else .65, 0.0))
    elif pat == "ballad":
        for c0, cl, ch in chords:
            b = broot(ch, center - 24)
            ev.append((c0, cl, [b, b + 12], .7, 0.0))
            vo = voice(ch, center) + [voice(ch, center)[0] + 12]
            k = 0
            p = c0 + .5
            while p < c0 + cl - 1e-6:
                ev.append((p, min(2.0, c0 + cl - p + .3), [vo[[0, 1, 2, 3, 2, 1, 0][k % 7] % len(vo)]], .6, 0.0))
                k += 1
                p += .5
    elif pat == "alberti":
        for i in range(8):
            p = i * .5
            ch, c0, cl = at(p)
            vo = voice(ch, center - 5)[:3]
            seq = [vo[0], vo[-1], vo[1], vo[-1]]
            ev.append((p, .65, [seq[i % 4]], .75 if i % 4 == 0 else .55, 0.0))
    elif pat == "montuno":
        for p, kind in ((0, "o"), (.5, "c"), (1.5, "c"), (2, "o"), (2.5, "c"), (3.5, "c")):
            ch, c0, cl = at(p)
            vo = voice(ch, center)
            notes = [vo[0], vo[0] + 12] if kind == "o" else vo[1:] + [vo[0] + 12]
            ev.append((p, .35, notes, .8 if kind == "o" else .65, 0.0))
    else:
        raise ValueError(pat)
    return ev


def bass_events(pat, chords, nxt_root, lo, rng):
    ev = []
    for ci, (c0, cl, ch) in enumerate(chords):
        r = broot(ch, lo)
        f5 = r + 7 if r + 7 <= lo + 14 else r - 5
        th = r + (3 if 3 in ch["ivs"] else 4)
        nr = broot(chords[ci + 1][2], lo) if ci + 1 < len(chords) else (nxt_root if nxt_root is not None else r)

        def T(lst):
            for p, d, m, v in lst:
                if p < cl - 1e-6:
                    ev.append((c0 + p, min(d, cl - p), m, v))

        if pat == "sustain":
            T([(0, cl * .95, r, .9)])
        elif pat == "root4":
            T([(i, .9, r, .9 if i % 2 == 0 else .75) for i in range(4)])
        elif pat == "root8":
            lst = [(i * .5, .45, r, .9 if i % 2 == 0 else .7) for i in range(8)]
            if cl >= 4:
                lst[-1] = (3.5, .45, f5, .7)
            T(lst)
        elif pat == "pop":
            T([(0, 1.4, r, .95), (1.5, .4, r, .7), (2, .9, r, .85), (3, .4, f5, .75), (3.5, .4, r + 12, .7)] if cl >= 4
              else [(0, 1.4, r, .95), (1.5, .4, r + 12, .7)])
        elif pat == "walking":
            ap = nr - 1 if rng.random() < .5 else nr + 1
            if cl >= 4:
                T([(0, .9, r, .9), (1, .9, th if rng.random() < .5 else f5, .75), (2, .9, f5, .8), (3, .9, ap, .75)])
            else:
                T([(0, .9, r, .9), (1, .9, ap, .75)])
        elif pat == "rootfifth":
            T([(0, .9, r, .9), (2, .9, r - 5 if r - 5 >= lo - 5 else f5, .8)] + ([(3.5, .4, f5, .55)] if rng.random() < .3 else []))
        elif pat == "funk":
            T([(0, .3, r, 1), (.75, .2, r + 12, .6), (1.5, .25, r, .8), (1.75, .15, r, .4),
               (2.5, .25, r + 12, .75), (3, .2, f5, .8), (3.5, .25, r, .7)])
        elif pat == "reggae":
            T([(0, .9, r, .9), (1.5, .4, f5, .7), (2, .9, r, .8), (3.25, .3, th, .6), (3.5, .4, f5, .7)])
        elif pat == "bossa":
            T([(0, 1.4, r, .9), (1.5, .5, r, .6), (2, 1.4, f5, .85), (3.5, .5, f5, .6)])
        elif pat == "house":
            T([(p, .4, r, .9) for p in (.5, 1.5, 2.5, 3.5)])
        elif pat == "synth8":
            T([(i * .5, .42, r + (12 if i in (2, 6) else 0), .9 if i % 2 == 0 else .75) for i in range(8)])
        elif pat == "shuffle":
            semis = [0, 4, 7, 9, 10, 9, 7, 4]
            T([(i * .5, .45, r + semis[i], .9 if i % 2 == 0 else .7) for i in range(8)])
        elif pat == "tumbao":
            T([(1.5, 1.4, r, .9), (3, .9, f5, .85)] if cl >= 4 else [(0, 1.4, r, .85)])
        elif pat == "chip":
            T([(i * .5, .4, r + (12 if i % 2 else 0), .85) for i in range(8)])
        elif pat == "orch":
            T([(0, 1.9, r, .85), (2, 1.9, r, .75)] if cl >= 4 else [(0, cl * .95, r, .85)])
        elif pat == "lofi":
            T([(0, 1.8, r, .9), (2.5, 1.2, f5, .75)] if cl >= 4 else [(0, cl * .9, r, .9)])
        else:
            raise ValueError(pat)
    return ev


# ════════════════════════════════════════════════════════════ 旋律
SEQ = [0, 2, 0, -1, 1, 3, 0, -2]


class Mel:
    def __init__(self, scale, key):
        self.sc = scale
        self.n = len(scale)
        self.key = key
        self.root = 60 + (key if key < 6 else key - 12)

    def semi(self, d):
        return self.sc[d % self.n] + 12 * (d // self.n)

    def near(self, s):
        return min(range(-2 * self.n, 4 * self.n), key=lambda d: abs(self.semi(d) - s))

    def pc(self, d, tr):
        return (self.key + tr + self.semi(d)) % 12

    def snap(self, d, tr, ch, pref=0):
        order = [0, 1, -1, 2, -2] if pref >= 0 else [0, -1, 1, -2, 2]
        for o in order:
            if self.pc(d + o, tr) in ch["pcs"]:
                return d + o
        return d

    def snap_cad(self, d, tr, ch):
        good = {ch["root"], (ch["root"] + ch["ivs"][1]) % 12}
        for o in (0, -1, 1, -2, 2, -3, 3):
            if self.pc(d + o, tr) in good:
                return d + o
        return self.snap(d, tr, ch)


def gen_motif(rng, grid, bars, dens, rise=0):
    slots = grid * bars
    beat = grid // 4
    ons = []
    for s in range(slots):
        p = s % grid
        if s >= slots - beat:
            continue
        if p == 0:
            w = .9
        elif p % beat == 0:
            w = .62
        elif grid == 16 and p % (beat // 2) == 0:
            w = .4
        else:
            w = .38 if grid == 8 else .2
        if s >= grid:
            w *= .8
        if rng.random() < min(.97, w * dens):
            ons.append(s)
    if not ons or ons[0] > beat:
        ons = [0] + ons
    while len(ons) < 3:
        ons = sorted(set(ons + [int(rng.integers(0, slots - beat))]))
    choices = [-3, -2, -1, 0, 1, 2, 3, 4]
    probs = [.06, .14, .24, .08, .24, .14, .06, .04]
    steps = [0] + [int(rng.choice(choices, p=probs)) + (rise if rng.random() < .5 else 0) for _ in ons[1:]]
    return dict(grid=grid, bars=bars, ons=ons, steps=steps, seed=int(rng.integers(1 << 30)))


def realize(mel, motif, bar0, nbars, chord_at, tr_at, base_semi, rng, variant=0, cad=True, lo=-3, hi=20):
    g = motif["grid"]; mb = motif["bars"]; sb = 4.0 / g
    steps = list(motif["steps"]); ons = motif["ons"]
    if variant:
        r2 = np.random.default_rng(motif["seed"] + variant)
        for _ in range(1 + variant % 2):
            if len(steps) > 1:
                i = int(r2.integers(1, len(steps)))
                steps[i] += int(r2.choice([-1, 1]))
    out = []
    reps = max(1, nbars // mb)
    for r in range(reps):
        sbeat = (bar0 + r * mb) * 4
        tr = tr_at(sbeat)
        last = cad and r == reps - 1
        use = [s for s in ons if s < g * (mb - 1)] if last else list(ons)
        if not use:
            use = [0]
        deg = mel.near(base_semi) + SEQ[r % len(SEQ)]
        st = 0
        for i, s in enumerate(use):
            b = sbeat + s * sb
            ch = chord_at(b)
            if i > 0:
                st = steps[i]
                deg += st
                if not (lo <= mel.semi(deg) <= hi):
                    deg -= 2 * st
                while mel.semi(deg) > hi:
                    deg -= 1
                while mel.semi(deg) < lo:
                    deg += 1
            nxt = use[i + 1] if i + 1 < len(use) else (g * (mb - 1) if last else g * mb - g // 4)
            dur = max(1, nxt - s) * sb
            if s % (g // 2) == 0 or dur >= 1.0:
                deg = mel.snap(deg, tr, ch, st)
            dur = min(max(dur * .9, sb * .6), 2.5)
            vel = .78 + .14 * (s % g == 0) + .06 * (s % (g // 4) == 0) + rng.normal(0, .035)
            out.append((b, dur, deg, vel, tr))
        if last:
            b = sbeat + g * (mb - 1) * sb
            ch = chord_at(b)
            deg = mel.snap_cad(deg, tr, ch)
            out.append((b, 3.2, deg, .85, tr))
    return out


# ════════════════════════════════════════════════════════════ 曲式
def build_sections(bpm, target=208.0):
    bar = 240.0 / bpm
    B = round(target / bar)
    L = 16 if B >= 96 else 8
    outro = 8 if L == 16 else 4
    total = 4 + 5 * L + 8 + outro
    opts = [("pre2", 4), ("solo", 8), ("pre1", 4), ("inter", 4), ("chorus3", L), ("verse3", L), ("intro_ext", 4)]
    on = set()
    for name, ln in opts:
        if total + ln <= B + 3:
            on.add(name)
            total += ln
    seq = [("intro", 8 if "intro_ext" in on else 4), ("verse", L)]
    if "pre1" in on:
        seq.append(("pre", 4))
    seq.append(("chorus", L))
    if "inter" in on:
        seq.append(("inter", 4))
    seq.append(("verse", L))
    if "pre2" in on:
        seq.append(("pre", 4))
    seq += [("chorus", L), ("bridge", 8)]
    if "solo" in on:
        seq.append(("solo", 8))
    if "verse3" in on:
        seq.append(("verse", L))
    seq.append(("chorus", L))
    if "chorus3" in on:
        seq.append(("chorus", L))
    seq.append(("outro", outro))
    out = []
    b = 0
    for name, ln in seq:
        out.append(dict(name=name, bars=ln, bar0=b))
        b += ln
    return out


# ════════════════════════════════════════════════════════════ 20 首曲風
def S(**kw):
    base = dict(scale=MAJOR, mel=MAJOR, sev=False, swing=0.0, swing_unit=8, turn="5", final="1",
                pad=None, comp=[], bass=None, drums=None, arp=None, timpani=False, modulate=0, solo_inst=None,
                fx={})
    base.update(kw)
    fx = dict(t60=1.8, wet=.25, lp=None, crackle=0, rain=0, sc=0.0, lufs=-14.0)
    fx.update(base["fx"])
    base["fx"] = fx
    for k in ("lead", "lead2"):
        d = dict(gain=.38, oct=0, grid=8, dens=.8, rev=.3, dly=.12, pan=.05)
        d.update(base.get(k) or {})
        base[k] = d
    for c in base["comp"]:
        c.setdefault("pan", 0.0); c.setdefault("rev", .3); c.setdefault("dly", 0.0)
        c.setdefault("secs", None); c.setdefault("duck", False)
    if base["pad"]:
        base["pad"].setdefault("rev", .5); base["pad"].setdefault("duck", False); base["pad"].setdefault("center", 60)
    if base["bass"]:
        base["bass"].setdefault("lo", 33); base["bass"].setdefault("duck", False)
    return base


STYLES = [
    S(title="信義路霓虹巡航", style="City Pop 城市流行", bpm=108, key=5,
      prog=dict(verse=["4:maj7", "3:m7", "6:m7", "2:m7", "4:maj7", "3:m7", ["2:m7", "5:7"], "1:maj7"],
                chorus=["4:maj7", "5:7", "3:m7", "6:m7", "2:m7", "5:7", "1:maj7", ["4:maj7", "5:7"]],
                bridge=["b6:maj7", "b7:7", "1:maj7", "6:m7", "b6:maj7", "b7:7", "4:maj7", "5:sus4"],
                pre=["2:m7", "3:m7", "4:maj7", "5:sus4"]),
      turn="5:7", final="1:maj9",
      pad=dict(inst="strings", gain=.12, center=62),
      comp=[dict(inst="epiano", pat="syncop", gain=.32, center=64, pan=-.3),
            dict(inst="guitar", pat="funk16", gain=.14, center=69, pan=.4, rev=.2, secs=["chorus", "solo", "inter"])],
      bass=dict(inst="bass_slap", pat="pop", gain=.55),
      drums=dict(kit="acoustic", pat="pop", gain=.8),
      lead=dict(inst="brass", gain=.4, grid=16, dens=.8), lead2=dict(inst="bell", gain=.25, oct=12),
      solo_inst="sax", modulate=1, fx=dict(t60=1.8, wet=.28)),
    S(title="永康街午後咖啡", style="Lo-fi 輕鬆節拍", bpm=78, key=2, swing=.55, swing_unit=16,
      prog=dict(verse=["2:m9", "5:9", "1:maj9", "6:m7"],
                chorus=["4:maj7", "3:m7", "2:m9", "5:9", "4:maj7", "3:m7", "6:m9", ["2:m7", "5:7"]],
                bridge=["b6:maj7", "b7:9", "1:maj7", "1:maj7"], pre=["4:maj7", "5:sus4"]),
      turn=None, final="1:maj9",
      pad=dict(inst="pad_warm", gain=.12),
      comp=[dict(inst="epiano", pat="jazzcomp", gain=.34, center=62, pan=-.2, rev=.35)],
      bass=dict(inst="bass_upright", pat="lofi", gain=.6),
      drums=dict(kit="lofi", pat="lofi", gain=.8),
      lead=dict(inst="flute", gain=.32, grid=16, dens=.55, dly=.15), lead2=dict(inst="bell", gain=.22, oct=12),
      solo_inst="epiano", fx=dict(t60=1.5, wet=.25, lp=4500, crackle=1)),
    S(title="北海岸逆風而行", style="抒情搖滾 Soft Rock", bpm=116, key=7,
      prog=dict(verse=["1", "5", "6", "4"], chorus=["4", "1", "5", "6", "4", "1", "5", "5"],
                bridge=["6", "4", "1", "5", "2", "4", "5:sus4", "5"], pre=["2", "4", "5:sus4", "5"]),
      pad=dict(inst="organ", gain=.07),
      comp=[dict(inst="guitar", pat="strum", gain=.3, center=62, pan=-.35, rev=.25),
            dict(inst="piano", pat="block", gain=.18, center=67, pan=.3, secs=["chorus", "solo", "bridge"])],
      bass=dict(inst="bass_finger", pat="root8", gain=.6),
      drums=dict(kit="acoustic", pat="rock", gain=.85),
      lead=dict(inst="lead_saw", gain=.36, dens=.9, dly=.15), lead2=dict(inst="piano", gain=.3, oct=12),
      solo_inst="lead_saw", modulate=2, fx=dict(t60=1.6, wet=.22)),
    S(title="淡水河畔晚霞", style="柔順爵士 Smooth Jazz", bpm=94, key=10,
      prog=dict(verse=["1:maj9", "6:m9", "2:m9", "5:9"],
                chorus=["4:maj9", "3:m7", "6:m9", "2:m9", "5:9", "1:maj9", "4:maj9", ["2:m7", "5:9"]],
                bridge=["b3:maj7", "b6:maj7", "2:m7", "5:7"], pre=["2:m9", "3:m7", "4:maj9", "5:9"]),
      turn="5:9", final="1:maj9",
      pad=dict(inst="strings", gain=.1),
      comp=[dict(inst="epiano", pat="jazzcomp", gain=.32, center=63, pan=-.25)],
      bass=dict(inst="bass_finger", pat="pop", gain=.55),
      drums=dict(kit="acoustic", pat="smooth", gain=.7),
      lead=dict(inst="sax", gain=.42, grid=16, dens=.7), lead2=dict(inst="epiano", gain=.28, oct=12),
      solo_inst="sax", fx=dict(t60=2.0, wet=.28)),
    S(title="國道一號午夜", style="合成器浪潮 夜駛 Synthwave", bpm=102, key=9, scale=MINOR, mel=MINOR,
      prog=dict(verse=["1", "6", "3", "7"], chorus=["6", "7", "1", "1", "4", "6", "7", "7"],
                bridge=["4", "5", "6", "7"], pre=["4", "6", "7", "7"]),
      turn="7",
      pad=dict(inst="pad", gain=.2, duck=True),
      comp=[dict(inst="pluck", pat="arp16", gain=.17, center=69, pan=.3, dly=.25)],
      bass=dict(inst="bass_synth", pat="synth8", gain=.5, duck=True),
      drums=dict(kit="electronic", pat="synthwave", gain=.85),
      lead=dict(inst="lead_saw", gain=.35, dens=.8, dly=.25), lead2=dict(inst="bell", gain=.25, oct=12),
      solo_inst="lead_square", fx=dict(t60=2.6, wet=.3, sc=.45)),
    S(title="花東縱谷微風", style="木吉他民謠 Acoustic Folk", bpm=92, key=2,
      prog=dict(verse=["1", "4", "1", "5", "6", "4", "1", "5"], chorus=["4", "5", "3", "6", "2", "5", "1", "1"],
                bridge=["6", "5", "4", "1", "6", "5", "4", "5"], pre=["4", "5"]),
      pad=dict(inst="strings", gain=.08),
      comp=[dict(inst="guitar", pat="fingerpick", gain=.3, center=60, pan=-.3, rev=.25),
            dict(inst="nylon", pat="strum", gain=.18, center=64, pan=.35, secs=["chorus", "solo", "inter"])],
      bass=dict(inst="bass_upright", pat="rootfifth", gain=.5),
      drums=dict(kit="acoustic", pat="folk", gain=.7),
      lead=dict(inst="flute", gain=.38, dens=.8), lead2=dict(inst="guitar", gain=.25, oct=12),
      solo_inst="flute", fx=dict(t60=1.6, wet=.22)),
    S(title="墾丁海岸線", style="巴薩諾瓦 Bossa Nova", bpm=132, key=0,
      prog=dict(verse=["1:maj7", "6:m7", "2:m9", "5:9", "3:m7", "6:7", "2:m7", ["5:7", "b2:7"]],
                chorus=["4:maj7", "b7:9", "3:m7", "6:7", "2:m7", "5:7", "1:maj7", "1:maj7"],
                bridge=["2:m7", "5:7", "1:maj7", "4:maj7", "7:m7b5", "3:7", "6:m7", ["2:m7", "5:7"]],
                pre=["2:m7", "5:7"]),
      turn="5:7", final="1:maj9",
      pad=dict(inst="strings", gain=.07),
      comp=[dict(inst="nylon", pat="bossa", gain=.32, center=60, pan=-.25, rev=.25)],
      bass=dict(inst="bass_upright", pat="bossa", gain=.55),
      drums=dict(kit="acoustic", pat="bossa", gain=.6),
      lead=dict(inst="flute", gain=.38, dens=.7), lead2=dict(inst="epiano", gain=.28),
      solo_inst="sax", fx=dict(t60=1.6, wet=.22)),
    S(title="西門町週末放克", style="放克 Funk", bpm=112, key=4, scale=DORIAN, mel=DORIAN,
      prog=dict(verse=["1:m7", "1:m7", "4:9", "4:9"],
                chorus=["3:maj7", "4:9", "2:m7", "1:m7", "3:maj7", "4:9", "5:m7", "4:9"],
                bridge=["7:maj7", "3:maj7", "4:9", ["5:m7", "4:9"]], pre=["2:m7", "3:maj7", "4:9", "4:9"]),
      turn="4:9", final="1:m9",
      comp=[dict(inst="clav", pat="funk16", gain=.26, center=64, pan=-.3, rev=.15),
            dict(inst="brass", pat="stab", gain=.22, center=67, pan=.3, secs=["chorus", "solo", "inter"])],
      bass=dict(inst="bass_slap", pat="funk", gain=.6),
      drums=dict(kit="acoustic", pat="funk", gain=.85),
      lead=dict(inst="lead_square", gain=.34, grid=16, dens=.9, dly=.1), lead2=dict(inst="epiano", gain=.28, oct=12),
      solo_inst="lead_saw", fx=dict(t60=1.2, wet=.18)),
    S(title="合歡山雲海", style="山嵐氛圍 Ambient", bpm=70, key=5,
      prog=dict(verse=["1:add9", "1:add9", "4:maj7", "4:maj7", "6:m7", "6:m7", "5:sus4", "5:sus4"],
                chorus=["4:maj7", "5:sus2", "6:m7", "3:m7", "4:maj7", "1:add9", "2:m7", "5:sus4"],
                bridge=["b7:maj", "b7:maj", "4:maj7", "4:maj7", "b6:maj7", "b6:maj7", "5:sus4", "5:sus4"],
                pre=["2:m7", "5:sus4"]),
      turn=None, final="1:add9",
      pad=dict(inst="pad_warm", gain=.3, rev=.7),
      comp=[dict(inst="harp", pat="harp", gain=.14, center=67, pan=.3, rev=.6, secs=["chorus", "solo", "bridge"])],
      bass=dict(inst="bass_sub", pat="sustain", gain=.35),
      lead=dict(inst="bell", gain=.32, dens=.45, dly=.3, rev=.6), lead2=dict(inst="flute", gain=.25),
      solo_inst="flute", fx=dict(t60=4.5, wet=.4, lufs=-16.0)),
    S(title="蘇花公路晴天", style="公路流行 Upbeat Pop", bpm=126, key=9,
      prog=dict(verse=["6", "4", "1", "5"], chorus=["1", "5", "6", "3", "4", "1", "4", "5"],
                bridge=["2", "4", "6", "5"], pre=["4", "5", "4", "5"]),
      pad=dict(inst="pad", gain=.1),
      comp=[dict(inst="piano", pat="pop", gain=.3, center=64, pan=-.25),
            dict(inst="pluck", pat="arp8", gain=.16, center=72, pan=.35, dly=.2, secs=["chorus", "solo", "inter"])],
      bass=dict(inst="bass_finger", pat="root8", gain=.55),
      drums=dict(kit="acoustic", pat="pop", gain=.85),
      lead=dict(inst="lead_square", gain=.36, dens=.9), lead2=dict(inst="bell", gain=.25, oct=12),
      solo_inst="lead_saw", modulate=1, fx=dict(t60=1.6, wet=.22)),
    S(title="九份雨巷", style="雨天鋼琴 Rainy Piano", bpm=74, key=0, scale=MINOR, mel=MINOR,
      prog=dict(verse=["1", "4", "7", "3", "6", "2:m7b5", "5:7", "1"], chorus=["6", "7", "3", "6", "4", "5:7", "1", "1"],
                bridge=["4", "5", "3", "6", "4", "5", "5:7", "5:7"], pre=["4", "5:7"]),
      turn="5:7",
      pad=dict(inst="strings", gain=.1),
      comp=[dict(inst="piano", pat="ballad", gain=.4, center=60, pan=-.1, rev=.35)],
      lead=dict(inst="piano", gain=.4, oct=12, grid=16, dens=.55, pan=.1, dly=.0), lead2=dict(inst="strings", gain=.22),
      solo_inst="piano", fx=dict(t60=2.4, wet=.3, rain=1, lufs=-16.0)),
    S(title="稻浪田埂", style="台灣民謠風 五聲音階", bpm=88, key=7, mel=PENTA_MAJ,
      prog=dict(verse=["1", "6", "1", "5", "4", "1", "2", "5"], chorus=["4", "1", "6", "3", "4", "5", "1", "1"],
                bridge=["6", "3", "4", "1", "6", "3", "2", "5"], pre=["4", "5"]),
      pad=dict(inst="strings", gain=.1),
      comp=[dict(inst="guzheng", pat="arp8", gain=.26, center=67, pan=-.3, rev=.35)],
      bass=dict(inst="bass_upright", pat="sustain", gain=.45),
      drums=dict(kit="acoustic", pat="folk", gain=.55),
      lead=dict(inst="flute", gain=.4, dens=.75), lead2=dict(inst="guzheng", gain=.3, oct=12),
      solo_inst="guzheng", fx=dict(t60=2.0, wet=.28)),
    S(title="綠島海風", style="雷鬼 Reggae", bpm=76, key=3, swing=.3, swing_unit=16,
      prog=dict(verse=["1", "4", "1", "5"], chorus=["4", "5", "1", "6", "4", "5", "1", "1"],
                bridge=["2", "5", "1", "6"], pre=["4", "5"]),
      comp=[dict(inst="guitar", pat="skank", gain=.3, center=67, pan=-.35, rev=.25),
            dict(inst="organ", pat="bubble", gain=.16, center=62, pan=.35)],
      bass=dict(inst="bass_sub", pat="reggae", gain=.7),
      drums=dict(kit="acoustic", pat="onedrop", gain=.8),
      lead=dict(inst="lead_square", gain=.3, grid=16, dens=.6, dly=.35), lead2=dict(inst="bell", gain=.22, oct=12),
      solo_inst="organ", fx=dict(t60=1.8, wet=.25)),
    S(title="台九線牛仔晨光", style="鄉村 Country", bpm=120, key=7,
      prog=dict(verse=["1", "1", "4", "1", "1", "1", "5", "5"], chorus=["4", "1", "5", "1", "4", "1", "5", "1"],
                bridge=["6", "6", "4", "4", "2", "2", "5", "5"], pre=["4", "5"]),
      comp=[dict(inst="guitar", pat="strum", gain=.28, center=62, pan=-.3),
            dict(inst="piano", pat="chick", gain=.18, center=67, pan=.3)],
      bass=dict(inst="bass_finger", pat="rootfifth", gain=.55),
      drums=dict(kit="acoustic", pat="train", gain=.75),
      lead=dict(inst="steel", gain=.38, dens=.85), lead2=dict(inst="pluck", gain=.25, oct=12),
      solo_inst="steel", fx=dict(t60=1.4, wet=.2)),
    S(title="港都夜行", style="電子浩室 House", bpm=122, key=5, scale=MINOR, mel=MINOR,
      prog=dict(verse=["1:m7", "6:maj7", "7", "4:m7"],
                chorus=["6:maj7", "7", "1:m7", "1:m7", "6:maj7", "7", "3:maj7", "5:m7"],
                bridge=["4:m7", "5:m7", "6:maj7", "7"], pre=["4:m7", "5:m7", "6:maj7", "7"]),
      turn="7", final="1:m9",
      pad=dict(inst="pad", gain=.18, duck=True),
      comp=[dict(inst="piano", pat="stab_off", gain=.26, center=64, pan=-.2, duck=True)],
      bass=dict(inst="bass_synth", pat="house", gain=.5, duck=True),
      drums=dict(kit="electronic", pat="house", gain=.9),
      lead=dict(inst="pluck", gain=.34, grid=16, dens=.8, dly=.3), lead2=dict(inst="bell", gain=.22, oct=12),
      solo_inst="lead_saw", fx=dict(t60=2.0, wet=.25, sc=.55)),
    S(title="台南老街藍調", style="藍調搖擺 Blues Shuffle", bpm=96, key=9, scale=MIXO, mel=BLUES, swing=1.0,
      prog=dict(verse=["1:7", "4:7", "1:7", "1:7", "4:7", "4:7", "1:7", "5:7"],
                chorus=["4:7", "4:7", "1:7", "1:7", "5:7", "4:7", "1:7", "5:7"],
                bridge=["4:9", "4:9", "1:9", "1:9", "2:m7", "5:7", "1:7", "5:7"], pre=["4:7", "5:7"]),
      turn=None, final="1:9",
      comp=[dict(inst="organ", pat="shuffle", gain=.24, center=62, pan=-.3),
            dict(inst="piano", pat="block", gain=.14, center=70, pan=.3, secs=["chorus", "solo"])],
      bass=dict(inst="bass_finger", pat="shuffle", gain=.55),
      drums=dict(kit="acoustic", pat="shuffle", gain=.8),
      lead=dict(inst="lead_saw", gain=.38, dens=.8), lead2=dict(inst="organ", gain=.25),
      solo_inst="sax", fx=dict(t60=1.5, wet=.2)),
    S(title="阿里山日出", style="管弦日出 Orchestral", bpm=84, key=2,
      prog=dict(verse=["1", "3", "4", "1", "6", "4", "2", "5"], chorus=["4", "5", "6", "1", "4", "5", "1", "1"],
                bridge=["6", "3", "4", "1", "2", "6", "4", "5"], pre=["4", "5"]),
      pad=dict(inst="strings", gain=.22),
      comp=[dict(inst="harp", pat="harp", gain=.18, center=64, pan=.35, rev=.45),
            dict(inst="brass", pat="sustain", gain=.16, center=57, pan=-.3, secs=["chorus", "solo", "outro"])],
      bass=dict(inst="strings", pat="orch", gain=.4, lo=36),
      timpani=True,
      lead=dict(inst="strings", gain=.42, oct=12, dens=.6), lead2=dict(inst="flute", gain=.3, oct=12),
      solo_inst="brass", fx=dict(t60=2.8, wet=.35, lufs=-15.0)),
    S(title="夜市彈珠台", style="復古晶片 Chiptune", bpm=140, key=0,
      prog=dict(verse=["1", "6", "4", "5"], chorus=["4", "5", "3", "6", "2", "5", "1", "5"],
                bridge=["b6", "b7", "1", "1"], pre=["4", "5"]),
      comp=[dict(inst="chip_pulse", pat="chiparp", gain=.18, center=67, pan=-.2, rev=.1)],
      bass=dict(inst="bass_tri", pat="chip", gain=.55),
      drums=dict(kit="chip", pat="chip", gain=.7),
      lead=dict(inst="chip_square", gain=.34, grid=16, dens=.85, rev=.1, dly=.1),
      lead2=dict(inst="chip_pulse", gain=.25, oct=12, rev=.1),
      solo_inst="chip_pulse", fx=dict(t60=.8, wet=.1)),
    S(title="澎湖跨海大橋", style="拉丁 Latin", bpm=104, key=7, scale=MINOR, mel=HARM_MINOR,
      prog=dict(verse=["1:m7", "4:m7", "5:7", "1:m7"],
                chorus=["6:maj7", "2:m7b5", "5:7", "1:m7", "4:m7", "7:7", "3:maj7", "5:7"],
                bridge=["4:m7", "7:7", "3:maj7", "6:maj7", "2:m7b5", "5:7", "1:m7", "5:7"], pre=["4:m7", "5:7"]),
      turn="5:7", final="1:m9",
      comp=[dict(inst="piano", pat="montuno", gain=.3, center=64, pan=-.25),
            dict(inst="brass", pat="stab", gain=.2, center=67, pan=.3, secs=["chorus", "solo", "inter"])],
      bass=dict(inst="bass_upright", pat="tumbao", gain=.55),
      drums=dict(kit="acoustic", pat="latin", gain=.75),
      lead=dict(inst="brass", gain=.38, dens=.8), lead2=dict(inst="marimba", gain=.3, oct=12),
      solo_inst="flute", fx=dict(t60=1.5, wet=.2)),
    S(title="日月潭晨光", style="寧靜古典 Calm Classical", bpm=72, key=8,
      prog=dict(verse=["1", "4", "2", "5", "1", "6", "4", "5"], chorus=["4", "5", "3", "6", "2", "5:7", "1", "1"],
                bridge=["6", "3", "4", "1", "2", "5", "1", "5"], pre=["4", "5"]),
      pad=dict(inst="strings", gain=.14),
      comp=[dict(inst="piano", pat="alberti", gain=.3, center=60, pan=-.15, rev=.35)],
      bass=dict(inst="strings", pat="orch", gain=.3, lo=36),
      lead=dict(inst="piano", gain=.4, oct=12, dens=.6, dly=.0), lead2=dict(inst="strings", gain=.3, oct=12),
      solo_inst="flute", fx=dict(t60=2.4, wet=.3, lufs=-16.0)),
]


# ════════════════════════════════════════════════════════════ 混音
def pan_g(p):
    a = (p + 1) * np.pi / 4
    return np.cos(a) * 1.41421356, np.sin(a) * 1.41421356


class Mixer:
    def __init__(self, n):
        self.n = n
        self.main = np.zeros((2, n), np.float32)
        self.duck = np.zeros((2, n), np.float32)
        self.rev = np.zeros(n, np.float32)
        self.dly = np.zeros(n, np.float32)

    def put(self, x, t0, gain, pan=0.0, rev=0.0, dly=0.0, duck=False):
        s = int(round(t0 * SR))
        if s >= self.n or gain <= 0:
            return
        if s < 0:
            x = x[-s:]
            s = 0
        e = min(self.n, s + len(x))
        x = x[:e - s] * np.float32(gain)
        gl, gr = pan_g(pan)
        b = self.duck if duck else self.main
        b[0, s:e] += x * np.float32(gl)
        b[1, s:e] += x * np.float32(gr)
        if rev:
            self.rev[s:e] += x * np.float32(rev)
        if dly:
            self.dly[s:e] += x * np.float32(dly)


def reverb_ir(t60, seed):
    r = np.random.default_rng(seed)
    n = int(t60 * SR)
    t = _t(n)
    irs = []
    for _ in range(2):
        x = r.standard_normal(n) * np.exp(-6.9 * t / t60)
        x = sosfilt(butter(1, 5500, "lowpass", fs=SR, output="sos"), x)
        x = np.concatenate([np.zeros(int(.02 * SR)), x])
        irs.append((x / np.sqrt(np.sum(x ** 2))).astype(np.float32))
    return irs


def kweight(x):
    fc, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    A = 10 ** (G / 40); w0 = 2 * np.pi * fc / SR; al = np.sin(w0) / (2 * Q); c = np.cos(w0)
    b = [A * ((A + 1) + (A - 1) * c + 2 * np.sqrt(A) * al), -2 * A * ((A - 1) + (A + 1) * c),
         A * ((A + 1) + (A - 1) * c - 2 * np.sqrt(A) * al)]
    a = [(A + 1) - (A - 1) * c + 2 * np.sqrt(A) * al, 2 * ((A - 1) - (A + 1) * c),
         (A + 1) - (A - 1) * c - 2 * np.sqrt(A) * al]
    y = lfilter(b, a, x, axis=-1)
    fc, Q = 38.13547087602444, 0.5003270373238773
    w0 = 2 * np.pi * fc / SR; al = np.sin(w0) / (2 * Q); c = np.cos(w0)
    return lfilter([(1 + c) / 2, -(1 + c), (1 + c) / 2], [1 + al, -2 * c, 1 - al], y, axis=-1)


def lufs(x):
    y = kweight(np.asarray(x, np.float64))
    blk, hop = int(.4 * SR), int(.1 * SR)
    z = 0
    for ch in y:
        c = np.concatenate([[0.0], np.cumsum(ch * ch)])
        st = np.arange(0, len(ch) - blk, hop)
        z = z + (c[st + blk] - c[st]) / blk
    l = -0.691 + 10 * np.log10(z + 1e-12)
    g = z[l > -70]
    if len(g) == 0:
        return -99.0
    lr = -0.691 + 10 * np.log10(np.mean(g)) - 10
    g2 = z[(l > -70) & (l > lr)]
    return float(-0.691 + 10 * np.log10(np.mean(g2)))


def limiter(x, ceil):
    a = np.max(np.abs(x), axis=0)
    w = int(.004 * SR)
    pk = maximum_filter1d(a, 2 * w + 1)
    g = np.minimum(1.0, ceil / np.maximum(pk, 1e-9))
    g = minimum_filter1d(g, 2 * w + 1)
    g = uniform_filter1d(g, 2 * w + 1)
    return np.clip(x * g, -ceil, ceil)


# ════════════════════════════════════════════════════════════ 作曲＋演奏
def render(idx):
    t_start = time.time()
    st = STYLES[idx - 1]
    rng = np.random.default_rng(7919 * idx + 17)
    bpm = st["bpm"]; spb = 60.0 / bpm; key = st["key"]
    swing, su = st["swing"], st["swing_unit"]

    def bt(b):
        if swing <= 0:
            return b * spb
        q = 1.0 if su == 8 else 0.5
        n = np.floor(b / q); f = b / q - n
        d = swing / 6.0
        f2 = f * (0.5 + d) / 0.5 if f < 0.5 else 0.5 + d + (f - 0.5) * (0.5 - d) / 0.5
        return (n + f2) * q * spb

    secs = build_sections(bpm)
    total_bars = secs[-1]["bar0"] + secs[-1]["bars"]
    end_t = bt(total_bars * 4)
    N = int((end_t + TAIL) * SR)
    mix = Mixer(N)
    syn = Synth()

    # 轉調：最後一段副歌與尾奏
    last_ch = max(i for i, s in enumerate(secs) if s["name"] == "chorus")
    tr_bar = []
    for i, s in enumerate(secs):
        tr = st["modulate"] if (st["modulate"] and i >= last_ch) else 0
        tr_bar += [tr] * s["bars"]

    # ── 和弦時間軸
    bars = []
    for si, s in enumerate(secs):
        nm = s["name"]; nxt = secs[si + 1]["name"] if si + 1 < len(secs) else None
        pk = {"intro": "verse", "verse": "verse", "pre": "pre", "chorus": "chorus", "inter": "chorus",
              "bridge": "bridge", "solo": "chorus", "outro": "chorus"}[nm]
        prog = st["prog"].get(pk) or ["4", "5"]
        for b in range(s["bars"]):
            tok = prog[b % len(prog)]
            if b == s["bars"] - 1 and nxt == "chorus" and st["turn"] and nm in ("verse", "pre", "bridge", "solo"):
                tok = st["turn"]
            if b == s["bars"] - 1 and nm == "outro":
                tok = st["final"]
            toks = tok if isinstance(tok, list) else [tok]
            ln = 4.0 / len(toks)
            tr = tr_bar[s["bar0"] + b]
            bars.append([(i * ln, ln, mk_chord(key, tr, *parse_chord(t, st["scale"], st["sev"]))) for i, t in enumerate(toks)])

    def chord_at(beat):
        bi = min(len(bars) - 1, max(0, int(beat // 4)))
        p = beat - bi * 4
        for c0, cl, ch in bars[bi]:
            if c0 - 1e-6 <= p < c0 + cl - 1e-6:
                return ch
        return bars[bi][-1][2]

    def tr_at(beat):
        return tr_bar[min(len(tr_bar) - 1, int(beat // 4))]

    def jit():
        return float(np.clip(rng.normal(0, .003), -.008, .008)) if st["drums"] is None or st["drums"]["kit"] != "chip" else 0.0

    def play(inst, beat, dur_b, midi, gain, pan=0.0, rev=0.0, dly=0.0, duck=False, t_off=0.0):
        t0 = bt(beat)
        ds = bt(beat + dur_b) - t0
        mix.put(syn.note(inst, midi, ds), t0 + t_off + jit(), gain, pan, rev, dly, duck)

    kit = make_kit(st["drums"]["kit"], 1000 + idx) if st["drums"] else None
    dp = DP[st["drums"]["pat"]] if st["drums"] else None
    kicks = []

    def hit(piece, beat, vel):
        if kit is None or piece not in kit:
            return
        t0 = bt(beat) + (0 if st["drums"]["kit"] == "chip" else float(np.clip(rng.normal(0, .002), -.005, .005)))
        mix.put(kit[piece], t0, st["drums"]["gain"] * DGAIN[piece] * vel * (1 + rng.normal(0, .05)),
                DPAN.get(piece, 0.0), DREV[piece] * (2.0 if (piece == "S" and st["drums"]["kit"] == "electronic") else 1.0))
        if piece == "K":
            kicks.append(t0)

    # ── 動機
    lg = st["lead"]["grid"]; ld = st["lead"]["dens"]
    motifs = {
        "verse": gen_motif(rng, lg, 2, .75 * ld),
        "chorus": gen_motif(rng, lg, 2, 1.0 * ld),
        "bridge": gen_motif(rng, lg, 2, .7 * ld),
        "pre": gen_motif(rng, lg, 2, .8 * ld, rise=1),
    }
    mel = Mel(st["mel"], key)
    occ = {}
    final_ch_idx = last_ch

    for si, s in enumerate(secs):
        nm, nb, b0 = s["name"], s["bars"], s["bar0"]
        nxt = secs[si + 1]["name"] if si + 1 < len(secs) else None
        E = ENERGY[nm]
        for bi in range(nb):
            gb = b0 + bi
            chords = bars[gb]
            beat0 = gb * 4
            last_outro = nm == "outro" and bi == nb - 1
            # 鋪底
            pd = st["pad"]
            if pd:
                pg = pd["gain"] * {"intro": 1.1, "bridge": 1.15, "outro": 1.1}.get(nm, 1.0)
                for c0, cl, ch in chords:
                    vo = voice(ch, pd["center"])
                    for k, m in enumerate(vo):
                        pn = -.5 + k / max(1, len(vo) - 1)
                        play(pd["inst"], beat0 + c0, cl * (2.0 if last_outro else 1.0), m, pg / np.sqrt(len(vo)),
                             pn, pd["rev"], duck=pd["duck"])
            # 伴奏
            for li, c in enumerate(st["comp"]):
                if c["secs"] and nm not in c["secs"]:
                    continue
                if nm == "intro" and li > 0:
                    continue
                pat = "sustain" if last_outro else c["pat"]
                for p, d, notes, v, stg in comp_events(pat, chords, gb, c["center"], rng):
                    if last_outro:
                        d = 6.0
                    g = c["gain"] * v * E / np.sqrt(max(1, len(notes)))
                    for k, m in enumerate(notes):
                        play(c["inst"], beat0 + p, d, m, g, c["pan"], c["rev"], c["dly"], c["duck"], t_off=k * stg)
            # 低音
            bs = st["bass"]
            if bs and not (nm == "intro" and bi < nb // 2):
                nb_root = None
                if gb + 1 < len(bars):
                    nb_root = broot(bars[gb + 1][0][2], bs["lo"])
                pat = "sustain" if last_outro else bs["pat"]
                if nm == "bridge" and pat in ("root8", "synth8", "chip", "funk"):
                    pat = "root4"
                for p, d, m, v in bass_events(pat, chords, nb_root, bs["lo"], rng):
                    if last_outro:
                        d = 5.0
                    play(bs["inst"], beat0 + p, d, m, bs["gain"] * v * (0.9 + 0.1 * E), 0.0, .05, duck=bs["duck"])
            # 定音鼓（管弦）
            if st["timpani"]:
                r = broot(chords[0][2], 38)
                if nm in ("chorus", "solo") or (nm == "outro" and bi == nb - 1):
                    play("timpani", beat0, 2.0, r, .55, -.1, .3)
                    if nm != "outro":
                        play("timpani", beat0 + 2, 1.5, r, .35, -.1, .3)
                if bi == nb - 1 and nxt in ("chorus", "solo"):
                    for k in range(8):
                        play("timpani", beat0 + 2 + k * .25, .3, r, .15 + .05 * k, -.1, .3)
            # 鼓
            if dp:
                patd = dict(dp["main"])
                if nm in ("chorus", "solo"):
                    patd.update(dp.get("chorus", {}))
                elif nm == "bridge":
                    patd = dict(dp.get("bridge", HALFTIME))
                vs = E
                if nm == "intro":
                    if bi < nb // 2:
                        patd = {}
                    else:
                        patd = {k: v for k, v in patd.items() if k in INTRO_PIECES}
                        vs *= .8
                elif nm == "outro":
                    if bi >= nb // 2:
                        patd = {k: v for k, v in patd.items() if k in INTRO_PIECES}
                    if last_outro:
                        patd = {}
                        hit("K", beat0, 1.0); hit("CR", beat0, .9)
                fill = None
                if bi == nb - 1 and nxt is not None and nm != "intro" or (nm == "intro" and bi == nb - 1):
                    if nm == "pre":
                        fill = "roll"
                    else:
                        fill = ["snare", "tom", "mix"][int(rng.integers(3))]
                for piece, sstr in patd.items():
                    if not sstr:
                        continue
                    L = len(sstr) // 16
                    off = (bi % L) * 16
                    for i in range(16):
                        v = VCH.get(sstr[off + i], 0)
                        if not v:
                            continue
                        if fill and i >= (0 if fill == "roll" else 8) and piece in ("S", "K", "H", "RS", "BR", "CP"):
                            if not (fill == "roll" and piece in ("K", "H")):
                                continue
                        hit(piece, beat0 + i * .25, v * vs)
                if fill == "roll":
                    for i in range(16):
                        if i < 8 and i % 2:
                            continue
                        hit("S", beat0 + i * .25, .3 + .7 * i / 15)
                elif fill:
                    for i, pc, v in FILLS[fill]:
                        hit(pc if "T" not in pc or "T1" in kit else "S", beat0 + i * .25, v)
                if bi == 0 and nm in ("chorus", "solo", "inter", "outro") and si > 0:
                    hit("CR", beat0, .9)

        # ── 旋律
        ld_ = st["lead"]; l2 = st["lead2"]
        evs = []
        if nm in ("verse", "chorus", "bridge", "pre"):
            o = occ.get(nm, 0); occ[nm] = o + 1
            base = {"verse": 7, "chorus": 12, "bridge": 9, "pre": 9}[nm]
            src = ld_ if nm != "bridge" else l2
            for half in range(max(1, nb // 8)):
                ln = min(8, nb)
                ev = realize(mel, motifs[nm], b0 + half * 8, ln, chord_at, tr_at, base, rng,
                             variant=o + half, cad=(nm != "pre"))
                evs.append((src, ev, 1.0))
                if nm == "chorus" and si == final_ch_idx or (nm == "chorus" and si > final_ch_idx):
                    evs.append((dict(ld_, gain=ld_["gain"] * .55, pan=-.25), [(b, d, dg - 2, v, t) for b, d, dg, v, t in ev], 1.0))
        elif nm == "solo":
            inst = st["solo_inst"] or ld_["inst"]
            so = dict(ld_, inst=inst)
            for k in range(nb // 2):
                m = gen_motif(rng, ld_["grid"], 2, 1.25 * ld_["dens"])
                ev = realize(mel, m, b0 + k * 2, 2, chord_at, tr_at, 7 + 2 * (k % 3), rng, cad=(k == nb // 2 - 1))
                evs.append((so, ev, 1.0))
        elif nm in ("intro", "inter"):
            start = b0 + (nb - 4 if nb > 4 else 0)
            ev = realize(mel, motifs["chorus"], start, min(4, nb), chord_at, tr_at, 12, rng, variant=0)
            evs.append((l2, ev, .75))
        elif nm == "outro" and nb > 1:
            ln = max(2, (nb // 2) // 2 * 2)
            ev = realize(mel, motifs["chorus"], b0, ln, chord_at, tr_at, 12, rng, variant=3)
            evs.append((ld_, ev, .8))
        for spec, ev, gm in evs:
            for b, d, dg, v, t in ev:
                midi = mel.root + t + mel.semi(dg) + spec["oct"]
                play(spec["inst"], b, d, midi, spec["gain"] * v * gm, spec["pan"], spec["rev"], spec["dly"])

    # ════ 母帶處理
    fx = st["fx"]
    out = mix.main.astype(np.float64)
    if fx["sc"] > 0 and kicks:
        sc = np.zeros(N)
        ii = np.clip((np.array(kicks) * SR).astype(int), 0, N - 1)
        sc[ii] = 1.0
        kern = np.exp(-_t(int(.3 * SR)) / .09)
        kern[:160] *= np.linspace(0, 1, 160)
        env = oaconvolve(sc, kern)[:N]
        out += mix.duck * (1 - fx["sc"] * np.clip(env, 0, 1))
    else:
        out += mix.duck
    irs = reverb_ir(fx["t60"], 50 + idx)
    for c in range(2):
        out[c] += fx["wet"] * oaconvolve(mix.rev, irs[c])[:N]
    if np.any(mix.dly):
        d = int(.75 * spb * SR)
        dl = sosfilt(butter(2, 4000, "lowpass", fs=SR, output="sos"), mix.dly)
        for k in range(1, 6):
            s = d * k
            if s >= N:
                break
            out[(k - 1) % 2, s:] += (.42 ** (k - 1)) * .6 * dl[:N - s]
    out = sosfilt(butter(2, 30, "highpass", fs=SR, output="sos"), out, axis=-1)
    if fx["lp"]:
        out = sosfilt(butter(2, fx["lp"], "lowpass", fs=SR, output="sos"), out, axis=-1)
    music_rms = np.sqrt(np.mean(out ** 2)) + 1e-9
    nr = np.random.default_rng(900 + idx)
    if fx["crackle"]:
        cr = np.zeros((2, N))
        cnt = int(N / SR * 5)
        pos = nr.integers(0, N, cnt)
        amp = nr.exponential(1.0, cnt) * nr.choice([-1, 1], cnt)
        cr[0, pos] = amp; cr[1, pos] = amp * .8
        cr = sosfilt(butter(2, 1500, "highpass", fs=SR, output="sos"), cr, axis=-1)
        cr += 0.02 * sosfilt(butter(2, 5000, "lowpass", fs=SR, output="sos"), nr.standard_normal((2, N)), axis=-1)
        out += cr / (np.sqrt(np.mean(cr ** 2)) + 1e-9) * music_rms * 0.06
    if fx["rain"]:
        rn = sosfilt(butter(2, [700, 7000], "bandpass", fs=SR, output="sos"), nr.standard_normal((2, N)), axis=-1)
        tt = _t(N)
        rn *= 0.7 + 0.3 * np.sin(2 * np.pi * .07 * tt) * np.sin(2 * np.pi * .023 * tt + 1)
        drops = np.zeros((2, N))
        cnt = int(N / SR * 14)
        drops[nr.integers(0, 2, cnt), nr.integers(0, N, cnt)] = nr.exponential(1.0, cnt)
        dk = np.sin(2 * np.pi * 3200 * _t(400)) * np.exp(-_t(400) * 300)
        drops = np.stack([oaconvolve(drops[c], dk)[:N] for c in range(2)])
        rn = rn / (np.sqrt(np.mean(rn ** 2)) + 1e-9) + 0.6 * drops / (np.sqrt(np.mean(drops ** 2)) + 1e-9)
        out += rn * music_rms * 0.1

    # 淡入／淡出
    fi = int(.02 * SR)
    out[:, :fi] *= np.linspace(0, 1, fi)
    o = secs[-1]
    f0 = int((bt(o["bar0"] * 4) + 0.3 * (bt((o["bar0"] + o["bars"]) * 4) - bt(o["bar0"] * 4))) * SR)
    fl = N - f0
    out[:, f0:] *= np.cos(np.linspace(0, np.pi / 2, fl)) ** 1.5

    # 響度標準化 + 限幅；Vorbis 編碼後波形會稍微過衝，所以編完解碼回來量峰值，
    # 超過 -1 dBFS 就把限幅門檻再壓低重做。
    pre = out
    target = fx["lufs"]
    path = os.path.join(OUT_DIR, "track%02d.ogg" % idx)
    ceil_db = -2.0
    for _attempt in range(5):
        ceil = 10 ** (ceil_db / 20)
        out = pre
        for _ in range(3):
            L = lufs(out)
            out = limiter(out * 10 ** ((target - L) / 20), ceil)
        L = lufs(out)
        inter = np.ascontiguousarray(out.T.astype("<f4"))
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2",
                        "-i", "pipe:0", "-c:a", "libvorbis", "-q:a", VORBIS_Q, "-fflags", "+bitexact", "-flags:a", "+bitexact",
                        "-metadata", "title=" + st["title"], "-metadata", "genre=" + st["style"], path],
                       input=inter.tobytes(), check=True)
        enc_pk = 20 * np.log10(np.max(np.abs(decode(path))) + 1e-12)
        if enc_pk <= -1.1:
            break
        ceil_db -= enc_pk + 1.3
    meta = dict(file="track%02d.ogg" % idx, title=st["title"], style=st["style"], seconds=round(N / SR, 2))
    info = dict(idx=idx, bpm=bpm, bars=total_bars, lufs=round(L, 2),
                peak_db=round(enc_pk, 2),
                size=os.path.getsize(path), secs=round(time.time() - t_start, 1),
                form=" ".join("%s%d" % (s["name"][:2], s["bars"]) for s in secs))
    return meta, info


# ════════════════════════════════════════════════════════════ 驗證
def decode(path):
    p = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", "2",
                        "-ar", str(SR), "pipe:1"], capture_output=True, check=True)
    return np.frombuffer(p.stdout, "<f4").reshape(-1, 2).T.astype(np.float64)


def verify():
    with open(os.path.join(OUT_DIR, "tracks.json"), encoding="utf-8") as f:
        tracks = json.load(f)
    total = 0
    bad = 0
    print("%-12s %7s %8s %8s %8s %8s %6s  %s" % ("file", "KB", "ffprobe", "peakdB", "rmsdB", "LUFS", "silent", "title"))
    for tk in tracks:
        path = os.path.join(OUT_DIR, tk["file"])
        sz = os.path.getsize(path); total += sz
        dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of",
                                    "default=nw=1:nk=1", path], capture_output=True, text=True).stdout.strip())
        x = decode(path)
        pk = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
        rms = 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)
        # 每 5 秒一窗（不含最後 15 秒淡出）找靜音
        w = 5 * SR
        body = x[:, :max(w, x.shape[1] - 15 * SR)]
        nwin = body.shape[1] // w
        wr = [20 * np.log10(np.sqrt(np.mean(body[:, i * w:(i + 1) * w] ** 2)) + 1e-12) for i in range(nwin)]
        silent = sum(1 for v in wr if v < -45)
        clip = int(np.sum(np.abs(x) >= 0.999))
        ok = pk <= -0.9 and silent == 0 and clip == 0 and 190 <= dur <= 230
        bad += not ok
        print("%-12s %7d %8.1f %8.2f %8.2f %8.2f %6d  %s %s%s" % (tk["file"], sz // 1024, dur, pk, rms, lufs(x),
                                                                 silent, tk["title"], tk["style"], "" if ok else "  <-- 檢查"))
    print("合計 %.2f MB，%d 首，異常 %d 首" % (total / 1048576, len(tracks), bad))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", type=int, default=0)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--verify", action="store_true")
    a = ap.parse_args()
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    if a.verify:
        verify()
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    t0 = time.time()
    ids = [a.only] if a.only else list(range(1, len(STYLES) + 1))
    jpath = os.path.join(OUT_DIR, "tracks.json")
    metas = {}
    if os.path.exists(jpath):
        with open(jpath, encoding="utf-8") as f:
            for m in json.load(f):
                metas[m["file"]] = m
    if len(ids) == 1 or a.jobs <= 1:
        results = [render(i) for i in ids]
    else:
        with ProcessPoolExecutor(max_workers=a.jobs) as ex:
            results = list(ex.map(render, ids))
    for meta, info in results:
        metas[meta["file"]] = meta
        print("%02d %-10s %5.1fs  %3dbpm %3d小節  LUFS %6.2f  峰值 %5.2f dB  %5d KB  耗時 %5.1fs  [%s]" % (
            info["idx"], meta["title"], meta["seconds"], info["bpm"], info["bars"], info["lufs"], info["peak_db"],
            info["size"] // 1024, info["secs"], info["form"]))
    with open(jpath, "w", encoding="utf-8") as f:
        json.dump([metas[k] for k in sorted(metas)], f, ensure_ascii=False, indent=1)
    print("完成，總耗時 %.1f 秒" % (time.time() - t0))


if __name__ == "__main__":
    main()
