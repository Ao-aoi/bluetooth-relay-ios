# bluetooth_relay_ios: 心電計 → iPhone → PC 中継アプリ(案A)

iPhoneが心電計のBLE通知(0011心電/0012動き/0021)を受け取り、PCへ WebSocket(ws://PC:9750)で
**加工せずに**転送する。PCに繋がらない間はアプリ内にため、PCが `pull` を送ったら全部送る。

## ビルド(Macなし)
GitHub Actions(macOS)でビルドし、署名なしの `BluetoothRelay.ipa` を成果物として取得する。
`.github/workflows/build.yml` → Actions の artifact `BluetoothRelay-ipa`。

## iPhoneへの入れ方
- 自分用: Windowsの Sideloadly(無料のApple IDで署名、7日ごとに入れ直し)。
- 複数のiPhone/期限なし: Apple Developer Program(年額約13,000円)+ TestFlight が必要。

## PC側
`python pc_receiver.py`(`pip install websockets`)。出たIPをアプリに入力する。

## 解析部(Analysis/)
心電図からRiRまでの計算(前処理、R波検出、RRIの補正、RiR・ΣRiR・La)をSwiftに書き写したもの。
元は `kokolog_test` の `realtime/pipeline.py`(逐次処理)と、`20261110_viewer_realtime.py` の解析部。
RiRの計算式(`RiRFilters.swift`)は基準プログラム Uef190901 のまま変えない。

- テスト: `cd Analysis && swift test`(Python版の結果を正解として比べる。心電図は計算で作った作り物)
- 実測データでの確認(Windows):
  1. `cd Analysis && swift run -c release ecgcheck <入力.ecg> swift.csv`
  2. `kokolog_test` で `python -m realtime.export_beats <入力.ecg> py.csv`
  3. `python -m realtime.export_beats --compare py.csv swift.csv`
- 正解データの作り直し: `python Analysis/tools_make_fixtures.py <kokolog_test のフォルダ>`
- 実測の心電データは、このリポジトリ(公開)に入れないこと。
