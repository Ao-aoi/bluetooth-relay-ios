"""テスト用の基準データを作る(Python版の解析結果を、Swift版と比べるための正解にする)。
使い方: python tools_make_fixtures.py <kokolog_test のフォルダ>
心電図は計算で作った作り物(実測データではない)。"""
import sys
from pathlib import Path
import numpy as np

kt = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(kt))
from realtime.pipeline import RealtimeECG, RealtimeRiR  # noqa: E402
from scipy.signal import find_peaks, sosfiltfilt, butter  # noqa: E402

out = Path(__file__).resolve().parent / "Tests" / "EcgCoreTests" / "Fixtures"
out.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(20261111)
fs = 250
dur = 600
n = fs * dur
t = np.arange(n) / fs

# 拍の時刻: 心拍数 70→125→85 bpm、呼吸などによるゆらぎ(0.1 / 0.25 / 0.6 Hz)を重ねる
beats = []
tb = 0.5
while tb < dur - 1:
    beats.append(tb)
    hr = 70 + 55 * np.exp(-((tb - 330) / 110) ** 2) + 15 * (tb > 450) * (1 - np.exp(-(tb - 450) / 40))
    rr = 60 / hr
    rr *= 1 + 0.04 * np.sin(2 * np.pi * 0.1 * tb) + 0.03 * np.sin(2 * np.pi * 0.25 * tb) \
        + (0.012 + 0.02 * np.exp(-((tb - 330) / 80) ** 2)) * np.sin(2 * np.pi * 0.6 * tb)
    tb += rr + rng.normal(0, 0.002)
x = np.zeros(n)
for b in beats:
    a = 550 * (1 + 0.1 * np.sin(b / 7))
    x += a * np.exp(-0.5 * ((t - b) / 0.011) ** 2)              # R波
    x -= 0.18 * a * np.exp(-0.5 * ((t - b - 0.03) / 0.012) ** 2)  # S波
    x += 0.22 * a * np.exp(-0.5 * ((t - b - 0.25) / 0.045) ** 2)  # T波
x += 120 * np.sin(2 * np.pi * 0.2 * t) + 25 * np.sin(2 * np.pi * 50 * t) + rng.normal(0, 12, n)
# 体動を模した雑音(300〜308秒)と、とがった雑音
seg = (t > 300) & (t < 308)
x[seg] += rng.normal(0, 90, seg.sum())
for s in (302.13, 303.4, 305.77, 306.2, 410.31, 411.02):
    x += 500 * np.exp(-0.5 * ((t - s) / 0.008) ** 2)
adc = np.clip(np.round(x + 8192), 0, 16383).astype("<u2")
adc[int(200.0 * fs):int(200.3 * fs)] = 0          # 記録値が下限に張り付く区間
adc[int(201.5 * fs):int(201.6 * fs)] = 16383      # 上限に張り付く区間
adc.tofile(out / "synthetic.ecg")

# 受信の欠落: (何パケット目の前で, 欠けたサンプル数)
GAPS = {1200: 400, 1800: 50}
e = RealtimeECG()
for i in range(n // 50):
    if i in GAPS:
        e.gap(GAPS[i])
    e.push(adc[i * 50:(i + 1) * 50])

def f(v):
    return "" if v is None or (isinstance(v, float) and np.isnan(v)) else repr(float(v))

with open(out / "expected_beats.csv", "w", encoding="utf-8", newline="\n") as fp:
    fp.write("time_s,sample_index,RRI_ms,HR_bpm,RiR,sumrir_per_span,La\n")
    for b in e.beats:
        fp.write(",".join([f(b["time_s"]), str(b["sample_index"]), f(b["RRI_ms"]), f(b["HR_bpm"]),
                           f(b["RiR"]), f(b["sumrir_per_span"]), f(b["La"])]) + "\n")

q = e.quality()
with open(out / "quality_case.txt", "w", encoding="utf-8", newline="\n") as fp:
    fp.write(" ".join([repr(q["mains"]), repr(q["noise"]), repr(q["qrs"]), repr(q["rail"]), str(q["level"])]) + "\n")

# 部品ごとの確認用: 帯域通過フィルタとピーク検出
sig = (adc[2500:3500].astype(float) - 8192)
sos = butter(3, [5 / 125, 25 / 125], btype="band", output="sos")
y = sosfiltfilt(sos, sig)
med = np.median(y); mad = np.median(np.abs(y - med))
pk, _ = find_peaks(y, distance=65, prominence=mad * 4)
with open(out / "filter_case.txt", "w", encoding="utf-8", newline="\n") as fp:
    fp.write(" ".join(repr(float(v)) for v in sig) + "\n")
    fp.write(" ".join(repr(float(v)) for v in y) + "\n")
    fp.write(" ".join(str(int(p)) for p in pk) + "\n")

# RiRの計算だけの確認用: 0.6Hzのゆらぎが大きいRRI系列(RiRが0.3を超え、Laが動く)
rr_rng = np.random.default_rng(7)
r = RealtimeRiR()
tt = 0.0
with open(out / "rir_case.csv", "w", encoding="utf-8", newline="\n") as fp:
    fp.write("time_s,RRI_ms,RiR,sumrir,La\n")
    for i in range(1500):
        rri = 480 + 30 * np.sin(2 * np.pi * 0.6 * tt) + 6 * np.sin(2 * np.pi * 0.1 * tt) + rr_rng.normal(0, 2)
        rri = float(round(rri * 4) / 4)
        tt += rri / 1000
        if i == 700:
            tt += 3.0            # 拍が届かない区間(欠測の経路を通す)
        o = r.beat(tt, rri)
        fp.write(",".join([repr(tt), repr(rri)] + ([f(o["RiR"]), f(o["sumrir"]), f(o["La"])] if o else ["", "", ""])) + "\n")
print("RiRだけの確認: 最後のLa", o["La"], "RiR", o["RiR"], "再シード", r.reseeds)

valid = [b for b in e.beats if not np.isnan(b["RiR"])]
print("拍", len(e.beats), "RiRあり", len(valid), "①で除外", e.n_dropped_clip, "欠落", e.n_gaps,
      "候補", len(e.cand), "②後", len(e.kept), "再シード", e.rir.reseeds)
print("RiR 最小/最大", min(b["RiR"] for b in valid), max(b["RiR"] for b in valid))
