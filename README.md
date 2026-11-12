# bluetooth_relay_ios: 心電計 → iPhone → PC 中継アプリ(案A)

iPhoneが心電計のBLE通知(0011心電/0012動き/0021)を受け取り、PCへ WebSocket(ws://PC:9750)で
**加工せずに**転送する。PCに繋がらない間はアプリ内にため、PCが `pull` を送ったら全部送る。

## ビルド(Macなし)
GitHub Actions(macOS)でビルドし、署名なしの `BluetoothRelay.ipa` を成果物として取得する。
`.github/workflows/build.yml` → Actions の artifact `BluetoothRelay-ipa`。

## iPhoneへの入れ方
- 自分用: Windowsの Sideloadly(無料のApple IDで署名、7日ごとに入れ直し)。
- 複数のiPhone/期限なし: Apple Developer Program(年額約13,000円)+ TestFlight が必要。

## アプリの画面
- 解析: 心拍数とRiRの時間推移、ΔHR と ΣRiR の散布図、信号品質、状態(安静 / 軽い動き / 運動)
- 接続: 心電計との接続(波形と検出したR波)、PCへの送信、PCへの解析結果の表示
- 設定: グラフの時間範囲と描き方(Canvas / Swift Charts)、起動時に心電計・PCを探すかどうか、解析の設定

## PC側
- 生データを受け取る: `python pc_receiver.py`(`pip install websockets zeroconf`)。ポート9750。
- iPhoneの解析結果を表示する: `python pc_monitor.py`(`pip install websockets zeroconf matplotlib`)。ポート9751。
  iPhoneが計算した心拍数とRiRを、iPhone 1台につき1行で表示する。複数のiPhoneを同時に表示できる。
  PCでは解析しない。通信の形式は `pc_monitor.py` の先頭に書いてある。
- Pythonが無いPCでは: GitHub Actions の「pc-monitor-exe」の成果物 `pc-tools-windows` を落として、`pc_monitor.exe` / `pc_receiver.exe` を開く。初回はWindowsのファイアウォールの確認が出るので「許可」を押す。
- どちらも、動かしている間はアプリの「PCを探す」に出る。出ないときはPCのIPアドレスをアプリに入力する。

## 解析部(Analysis/)
心電図からRiRまでの計算(前処理、R波検出、RRIの補正、RiR・ΣRiR・La)をSwiftに書き写したもの。
元は `kokolog_test` の `realtime/pipeline.py`(逐次処理)と、`20261110_viewer_realtime.py` の解析部。
RiRの計算式(`RiRFilters.swift`)は基準プログラム Uef190901 のまま変えない。

- テスト: `cd Analysis && swift test`(Python版の結果を正解として比べる。心電図とジャイロは計算で作った作り物)
- 状態(安静 / 軽い動き / 運動)の判定は `Activity.swift`。元は `realtime/activity.py`(Python版では「安静」を「静止」と呼ぶ)
- 実測データでの確認(Windows):
  1. `cd Analysis && swift run -c release ecgcheck <入力.ecg> swift.csv`
  2. `kokolog_test` で `python -m realtime.export_beats <入力.ecg> py.csv`
  3. `python -m realtime.export_beats --compare py.csv swift.csv`
- 正解データの作り直し: `python Analysis/tools_make_fixtures.py <kokolog_test のフォルダ>`
- 実測の心電データは、このリポジトリ(公開)に入れないこと。
