"""中継アプリ(ios_relay)からのデータをPCで受け取り、生のまま保存する簡易受け口。
使い方: pip install websockets zeroconf ; python pc_receiver.py
iPhoneアプリにこのPCのIPアドレスを入れて「PCへの送信を始める」を押す。
形式: 1バイトの種類(0x01=心電,0x02=動き,0x03=5秒ごと) + BLEパケット(realtime/ネットワーク中継の仕様.md)"""
import asyncio, socket, time, json
import websockets

OUT = open(time.strftime("relay_%Y%m%d_%H%M%S.jsonl"), "a", encoding="utf-8")

def local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1)); return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()

async def handler(ws):
    print("iPhone接続")
    n = 0
    async for msg in ws:
        if isinstance(msg, str):
            print("iPhone:", msg)
            if "buffered=" in msg and not msg.endswith("=0"):
                await ws.send("pull")   # ためてあるデータを全部送らせる
            continue
        OUT.write(json.dumps({"t": time.time(), "kind": msg[0], "hex": msg[1:].hex()}) + "\n")
        n += 1
        if n % 100 == 0:
            OUT.flush(); print("受信", n)
        # TODO: NetworkSource へ (kind, msg[1:]) を渡す
    OUT.flush(); print("iPhone切断")

async def main():
    ip = local_ip()
    zc = None
    try:  # iPhoneアプリが自動でこのPCを見つけられるように知らせる(Bonjour)
        from zeroconf import ServiceInfo
        from zeroconf.asyncio import AsyncZeroconf
        zc = AsyncZeroconf()
        await zc.async_register_service(ServiceInfo(
            "_btrelay._tcp.local.", f"{socket.gethostname()}._btrelay._tcp.local.",
            addresses=[socket.inet_aton(ip)], port=9750))
    except ImportError:
        print("(自動検出には pip install zeroconf が必要です。IPの手入力は使えます)")
    async with websockets.serve(handler, "0.0.0.0", 9750):
        print("待機中。PCのIP:", ip)
        try:
            await asyncio.Future()
        finally:
            if zc:
                await zc.async_close()

asyncio.run(main())
