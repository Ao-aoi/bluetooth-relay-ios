# Swiftコードの読み方(Pythonが読める人向け)

このアプリは4つのファイルでできています。上から順に、役割と読み方を書きます。

| ファイル | 役割 | Pythonでいうと |
|---|---|---|
| `Sources/BLEManager.swift` | 心電計からBluetoothでデータを受け取る | `bleak` を使った受信部分(`live_plot.py` など) |
| `Sources/RelayClient.swift` | 受け取ったデータをPCへ送る/ためる | `receiver.py` へ送るクライアント |
| `Sources/ContentView.swift` | 画面(入力欄とボタンと数字) | tkinterの画面 |
| `Sources/BluetoothRelayApp.swift` | アプリの起動と部品のつなぎ | `main()` |

## 1. 文法の対応表

| Swift | 意味 | Python |
|---|---|---|
| `let x = 3` | 変えられない値 | `X = 3` |
| `var x = 3` | 変えられる値 | `x = 3` |
| `func f(a: Int) -> String { }` | 関数。`->` は返す型 | `def f(a): ...` |
| `class A { }` / `struct A { }` | 部品の設計図 | `class A:` |
| `self` | 自分自身 | `self` |
| `if let x = y { }` | yが空(nil)でなければxとして使う | `if y is not None:` |
| `guard 条件 else { return }` | 条件が満たされないとき早めに抜ける | `if not 条件: return` |
| `[UInt8: Int]` | 辞書 | `dict` |
| `Data` | バイト列 | `bytes` |
| `{ [weak self] x in ... }` | 無名関数(あとで呼ばれる) | `lambda x: ...` |
| `?`(例 `String?`) | 空(nil)かもしれない値 | `Optional` / `None` |
| `0x01` | 16進数 | `0x01` |

## 2. ファイルごとの読み方

### BLEManager.swift(Bluetoothの受信)
流れは、`bleak` の受信と同じです。

1. `start()` … 心電計を探し始める(`scanForPeripherals`)。
2. `didDiscover` … 見つかるたびに呼ばれる。名前が `kokolog` で始まる機器だけを選んで接続する。
3. `didConnect` → `didDiscoverServices` → `didDiscoverCharacteristicsFor` … 接続後、サービス(引き出し)を調べ、入れ物(特性)を見つける。
4. `setNotifyValue(true, ...)` … **通知の購読**。これは受信の登録だけで、心電計への書き込みではありません。
5. `didUpdateValueFor` … データが届くたびに呼ばれる(`bleak` の `notify` コールバックと同じ)。ここで `relay.send(...)` を呼び、PCへ渡します。
6. `didDisconnectPeripheral` … 切れたら、`connect` をもう一度呼ぶ。電波が戻れば自動でつながります。

`didXxx` という名前の関数は「〜が起きたときに呼ばれる関数」(コールバック)です。自分で呼ぶのではなく、iPhoneのBluetooth機能が呼んでくれます。

`kinds` は `[UUID: 種類番号]` の辞書です。0011→1(心電)、0012→2(動き)、0021→3(5秒ごと)。

### RelayClient.swift(PCへの送信)
- `connect()` … `ws://PCのIP:9750` へWebSocketで接続。
- `send(kind:packet:)` … 先頭に種類の1バイトを付けてPCへ送る。**つながっていないときは `keep()` で `buffer`(リスト)にためる**。
- `listen()` … PCからのメッセージを待つ。`pull` が来たら `flush()` を呼ぶ。
- `flush()` … ためた分を古い順に1つずつ全部送る。送っている間に新しく届いたものは後ろに並べるので、順番は崩れません。
- `Timer.scheduledTimer(... 3秒 ...)` … 3秒ごとに「切れていたら再接続」を試す。

`@Published var connected` のように `@Published` が付いた変数は、値が変わると画面が自動で更新されます(Pythonにはない仕組みです)。

### ContentView.swift(画面)
`Form { Section { ... } }` が、画面に積まれる部品の並びです。上から順に、PCのIP入力欄、開始ボタン、状態の数字が並びます。`Button("名前") { 押したときの処理 }` と読んでください。

### BluetoothRelayApp.swift(起動)
`@main` が付いた場所からアプリが始まります。`RelayClient` と `BLEManager` を1つずつ作って、画面に渡しています。

## 3. 全体の流れ(1パケットの旅)
心電計が送信 → `didUpdateValueFor`(BLEManager) → `relay.send`(RelayClient) → PCにつながっていれば即送信 / いなければ `buffer` にためる → PCが `pull` を送る → `flush` で全部送る。

## 4. 入れ方(開発者プログラムなし)
- Windowsの **Sideloadly** に、GitHub Actionsで作った `BluetoothRelay.ipa` を渡し、無料のApple IDで署名してiPhoneへ入れます。
- 制限: **7日ごとに入れ直し**が必要です。入れられる台数は、そのApple IDで同時に3アプリまでです。他の人のiPhoneに入れるときは、その人のiPhoneをPCにつないで同じ作業をします。
