# kokolog_relay_ios: kokolog → iPhone → PC 中継アプリ(案A)

iPhoneがkokologのBLE通知(0011心電/0012動き/0021)を受け取り、PCへ WebSocket(ws://PC:9750)で
**加工せずに**転送する。PCに繋がらない間はアプリ内にため、PCが `pull` を送ったら全部送る。

## ビルド(Macなし)
GitHub Actions(macOS)でビルドし、署名なしの `KokologRelay.ipa` を成果物として取得する。
`.github/workflows/build.yml` → Actions の artifact `KokologRelay-ipa`。

## iPhoneへの入れ方
- 自分用: Windowsの Sideloadly(無料のApple IDで署名、7日ごとに入れ直し)。
- 複数のiPhone/期限なし: Apple Developer Program(年額約13,000円)+ TestFlight が必要。

## PC側
`python pc_receiver.py`(`pip install websockets`)。出たIPをアプリに入力する。
