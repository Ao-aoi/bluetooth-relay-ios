"""iPhoneアプリの解析結果(心拍数・RiR)をPCのウィンドウに表示する。複数のiPhoneを同時に表示できる。
PCでは解析しない。iPhoneが計算した値をそのまま描く。

使い方:
    pip install websockets zeroconf matplotlib
    python pc_monitor.py            (表示する時間を変えるとき: python pc_monitor.py --minutes 30)
iPhoneアプリの「接続」タブでこのPCを選び、「PCに解析結果を表示」を始める。

通信: WebSocket、ポート9751。iPhoneは1秒に1回、JSONの文字メッセージを1つ送る。
    name      iPhoneの名前
    elapsed   測定開始からの経過秒
    hr, rir   最新の心拍数[bpm]とRiR(まだ無ければ null)
    validSec, validSpan   RiRが出るまでに溜まった秒数と、必要な秒数
    quality   信号品質 0=良好 / 1=注意 / 2=不良(まだ無ければ null)
    state     安静 / 軽い動き / 運動 / 不明
    from      beats の先頭が何拍目か。PCは、持っている拍のうち from 以降をこの beats で置き換える
    beats     [経過秒, 心拍数, RiRまたはnull] の並び
"""
import argparse
import asyncio
import json
import socket
import threading
import time

PORT = 9751
QUALITY = {0: ("良好", "green"), 1: ("注意", "darkorange"), 2: ("不良", "red")}
STATE_COLORS = {"安静": "green", "軽い動き": "darkorange", "運動": "red"}


class Phone:
    """iPhone 1台ぶんの受信内容。"""

    def __init__(self, name):
        self.name = name
        self.base = 0            # beats[0] が何拍目か
        self.beats = []          # [経過秒, 心拍数, RiRまたはNone]
        self.last = {}           # 最後に受け取ったメッセージ(beats を除く)
        self.connected = True
        self.received = time.time()

    def update(self, msg):
        new = msg.pop("beats", [])
        i = int(msg.get("from", 0)) - self.base
        if 0 <= i <= len(self.beats):
            self.beats[i:] = new
        else:                    # つながり直した後など、手元の拍と続かないとき
            self.base = int(msg.get("from", 0))
            self.beats = list(new)
        self.last = msg
        self.received = time.time()


class Monitor:
    """受信した内容を iPhone の名前ごとに持つ。受信は別スレッド、描画はメインスレッド。"""

    def __init__(self):
        self.phones = {}
        self.lock = threading.Lock()

    def on_message(self, text):
        msg = json.loads(text)
        name = str(msg.get("name") or "iPhone")
        with self.lock:
            p = self.phones.get(name)
            if p is None:
                p = self.phones[name] = Phone(name)
            p.connected = True
            p.update(msg)
        return name

    def on_close(self, name):
        with self.lock:
            if name in self.phones:
                self.phones[name].connected = False

    def snapshot(self):
        with self.lock:
            return [(p.name, list(p.beats), dict(p.last), p.connected) for p in self.phones.values()]


def local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


async def serve(monitor, port, ready=None):
    import websockets

    async def handler(ws):
        name = None
        try:
            async for text in ws:
                if isinstance(text, str):
                    name = monitor.on_message(text)
        except websockets.ConnectionClosed:
            pass
        finally:
            if name:
                monitor.on_close(name)

    zc = None
    try:  # iPhoneアプリの「PCを探す」に出るようにする(Bonjour)
        from zeroconf import ServiceInfo
        from zeroconf.asyncio import AsyncZeroconf
        zc = AsyncZeroconf()
        await zc.async_register_service(ServiceInfo(
            "_btrelay._tcp.local.", f"{socket.gethostname()} monitor._btrelay._tcp.local.",
            addresses=[socket.inet_aton(local_ip())], port=port))
    except Exception as e:  # zeroconf が無い、ネットワークが無い、など
        print("PCを探す機能は使えません(IPアドレスの手入力は使えます):", e)
    async with websockets.serve(handler, "0.0.0.0", port):
        if ready:
            ready.set()
        try:
            await asyncio.Future()
        finally:
            if zc:
                await zc.async_close()


def draw(fig, phones, minutes):
    """ウィンドウ全体を描き直す。iPhone 1台につき1行(左から 数値 / 心拍数 / RiR)。"""
    fig.clf()
    if not phones:
        fig.text(0.5, 0.5, "iPhoneからの接続を待っています", ha="center", va="center", fontsize=16)
        return
    gs = fig.add_gridspec(len(phones), 3, width_ratios=[1.1, 3, 3], hspace=0.45, wspace=0.22,
                          left=0.03, right=0.98, top=0.93, bottom=0.10)
    for row, (name, beats, last, connected) in enumerate(phones):
        ax_t = fig.add_subplot(gs[row, 0]); ax_t.axis("off")
        ax_hr = fig.add_subplot(gs[row, 1])
        ax_rir = fig.add_subplot(gs[row, 2], sharex=ax_hr)
        end = max(float(last.get("elapsed") or 0.0) / 60.0, minutes)
        start = end - minutes
        t = [b[0] / 60.0 for b in beats]
        ax_hr.plot(t, [b[1] for b in beats], color="red", lw=1.0)
        ax_rir.plot(t, [float("nan") if b[2] is None else b[2] for b in beats], color="blue", lw=1.0)
        ax_hr.set_xlim(start, end)
        shown = [b[1] for b in beats if b[0] / 60.0 >= start]
        ax_hr.set_ylim(min([50] + shown) - 5, max([120] + shown) + 5)
        ax_rir.set_ylim(0, 1)
        ax_hr.set_ylabel("心拍数 [bpm]"); ax_rir.set_ylabel("RiR")
        for ax in (ax_hr, ax_rir):
            ax.grid(alpha=0.3)
            if row == len(phones) - 1:
                ax.set_xlabel("時間 [分]")

        hr, rir, q = last.get("hr"), last.get("rir"), last.get("quality")
        if rir is not None:
            rir_text = f"{rir:.3f}"
        elif hr is None:
            rir_text = "--"
        else:
            rir_text = f"準備中 {min(last.get('validSec', 0), last.get('validSpan', 0)):.0f}/{last.get('validSpan', 0):.0f}秒"
        gray = "gray"
        ax_t.text(0, 0.95, name, fontsize=14, fontweight="bold", va="top", color="black" if connected else gray)
        ax_t.text(0, 0.72, "--" if hr is None else f"{hr:.0f} bpm", fontsize=20, va="top",
                  color="red" if connected else gray)
        ax_t.text(0, 0.48, "RiR " + rir_text, fontsize=13, va="top", color="blue" if connected else gray)
        qt, qc = QUALITY.get(q, ("--", gray))
        ax_t.text(0, 0.28, "信号品質: " + qt, fontsize=11, va="top", color=qc if connected else gray)
        state = str(last.get("state", "不明"))
        ax_t.text(0, 0.12, state, fontsize=11, va="top", color=STATE_COLORS.get(state, gray) if connected else gray)
        if not connected:
            ax_t.text(0, -0.04, "切断", fontsize=11, va="top", color=gray)


def main():
    ap = argparse.ArgumentParser(description="iPhoneアプリの解析結果をPCに表示する")
    ap.add_argument("--minutes", type=float, default=10.0, help="グラフに表示する時間[分](既定10)")
    ap.add_argument("--port", type=int, default=PORT)
    args = ap.parse_args()

    import matplotlib
    import matplotlib.pyplot as plt
    matplotlib.rcParams["font.family"] = ["Yu Gothic", "Meiryo", "MS Gothic", "Hiragino Sans", "IPAGothic", "sans-serif"]

    monitor = Monitor()
    threading.Thread(target=lambda: asyncio.run(serve(monitor, args.port)), daemon=True).start()
    print(f"待機中。このPCのIPアドレス: {local_ip()}  ポート: {args.port}")

    fig = plt.figure("解析結果の表示", figsize=(12, 4))
    seen = 0

    def tick():
        nonlocal seen
        phones = monitor.snapshot()
        if len(phones) != seen:                    # 台数が変わったらウィンドウの高さを合わせる
            seen = len(phones)
            fig.set_size_inches(12, max(4, 3.2 * seen), forward=True)
        draw(fig, phones, args.minutes)
        fig.canvas.draw_idle()

    timer = fig.canvas.new_timer(interval=1000)
    timer.add_callback(tick)
    timer.start()
    tick()
    plt.show()


if __name__ == "__main__":
    main()
