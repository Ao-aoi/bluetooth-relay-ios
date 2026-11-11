# Swift教材: Bluetooth Relay のコードを読む

対象: Pythonは読めるが、Swiftは初めての人。
進め方: ファイルを1つ開き、この教材の該当する節と見比べながら読む。各節は「何をしているか」「なぜこの書き方か」「他の書き方と、採用しなかった理由」の順に書いてある。

読む順番(依存の少ない順):
1. `Sources/BluetoothRelayApp.swift`(起動)
2. `Sources/WaveView.swift`(波形の描画)
3. `Sources/ContentView.swift`(画面)
4. `Sources/RelayClient.swift`(PCへの送信)
5. `Sources/BLEManager.swift`(Bluetooth受信)
6. `Sources/PCFinder.swift`(PCの自動検出)
7. `Analysis/Sources/EcgCore/Packet.swift`(パケットの解読、Windowsでも動く)

---

## 0. 最低限の文法

| Swift | 意味 | Pythonでは |
|---|---|---|
| `let a = 1` | 再代入できない変数 | (相当なし。定数の慣習 `A = 1`) |
| `var a = 1` | 再代入できる変数 | `a = 1` |
| `var a: Int = 1` | 型を明示 | `a: int = 1`(型ヒント) |
| `func f(x: Int) -> Int { }` | 関数 | `def f(x: int) -> int:` |
| `f(x: 3)` | 呼び出し時も引数名を書く | `f(x=3)` |
| `[Int]` | 整数の配列 | `list[int]` |
| `[String: Int]` | 辞書 | `dict[str, int]` |
| `Int?` | 「整数、または値なし(nil)」 | `Optional[int]` |
| `if let v = x { }` | xがnilでなければvとして使う | `if x is not None: v = x` |
| `guard 条件 else { return }` | 条件を満たさなければ抜ける | `if not 条件: return` |
| `{ x in x * 2 }` | 無名関数(クロージャ) | `lambda x: x * 2` |
| `for i in 0..<50` | 0〜49 | `for i in range(50)` |
| `struct` / `class` | 型の定義 | `class` |

`let` と `var` の使い分けは、Swiftで最初に慣れるところ。変えない値は必ず `let` にする、というのがSwiftの習慣で、コンパイラも「varだけど変えていないのでletにせよ」と警告を出す。

`struct` と `class` の違い: `struct` は代入するとコピーされる(Pythonの数値に近い)。`class` は代入しても同じ物を指す(Pythonのリストやオブジェクトに近い)。このアプリでは、画面の部品(View)とデータの入れ物は `struct`、状態を持ち続ける管理役は `class` にしている。

---

## 1. BluetoothRelayApp.swift(起動)

```swift
@main
struct BluetoothRelayApp: App {
    @StateObject private var relay: RelayClient
    @StateObject private var ble: BLEManager

    init() {
        let r = RelayClient()
        _relay = StateObject(wrappedValue: r)
        _ble = StateObject(wrappedValue: BLEManager(relay: r))
    }
    var body: some Scene {
        WindowGroup { ContentView(relay: relay, ble: ble) }
    }
}
```

**何をしているか**: アプリ起動時に、送信役(`RelayClient`)と受信役(`BLEManager`)を1つずつ作り、画面に渡す。

**なぜこの書き方か**
- `@main` は「ここからプログラムが始まる」という印。Pythonの `if __name__ == "__main__":` に当たる。1つのアプリに1か所だけ(2か所あるとビルドエラー。実際に名前変更のときに起きたエラーがこれ)。
- `@StateObject` は「画面が作り直されても、この物は作り直さずに持ち続ける」という印。SwiftUIは画面を頻繁に作り直すので、これがないと接続が毎回切れてしまう。
- `BLEManager` が受信したデータを `RelayClient` に渡すので、**同じ** `RelayClient` を両方に渡す必要がある。そのため `init()` の中で `r` を1つ作ってから、両方に使っている。
- `_relay = StateObject(wrappedValue: r)` の `_` 付きの名前は、`@StateObject` の中身の入れ物そのものを指す書き方。`@StateObject` は通常 `= RelayClient()` のように宣言と同時に作るが、ここでは「他の物と共有したい」ので、この形になる。

**他の書き方**
- 宣言で直接 `@StateObject var relay = RelayClient()` と書き、`BLEManager` 側で後から `ble.relay = relay` と渡す。→ 渡し忘れると受信データが行き先を失うので、作る時点で必ず渡す今の形にした。
- アプリ全体で1つだけの共有物(シングルトン、`static let shared = RelayClient()`)にする。→ 短く書けるが、どこからでも触れるため、後で処理の流れを追いにくくなる。

---

## 2. WaveView.swift(波形の描画)

```swift
struct WaveView: View {
    let samples: [Int]
    let length: Int
    var body: some View {
        Canvas { ctx, size in
            guard samples.count > 1, let lo = samples.min(), let hi = samples.max() else { return }
            let range = Double(max(hi - lo, 1))
            var path = Path()
            for (i, v) in samples.enumerated() { ... path.addLine(to: CGPoint(x: x, y: y)) }
            ctx.stroke(path, with: .color(.red), lineWidth: 1)
        }
        .frame(height: 160)
    }
}
```

**何をしているか**: 受け取った数値の列を、左から右へ折れ線で描く。

**なぜこの書き方か**
- `struct WaveView: View` は「画面の部品」の宣言。`body` に描く中身を書く。SwiftUIでは画面の部品はすべてこの形。
- `Canvas` は自由に線を描ける描画面。1250点の折れ線を毎回描くので、部品を1250個並べるより、1本の線(`Path`)として描くほうが軽い。
- `guard ... else { return }` で「点が2つ未満」「最小・最大が取れない」ときは何も描かずに抜ける。`samples.min()` は配列が空だと nil を返すので、`let lo = ...` で nil でないことを確かめてから使う。
- `max(hi - lo, 1)` は、全点が同じ値のとき(電極を付けていない等)に0で割らないための保護。
- `y = size.height * (1 - ...)` の `1 -` は、画面の座標が「上が0、下に行くほど大きい」ため。そのままだと波形が上下逆になる。
- `enumerated()` は Python の `enumerate()` と同じ。

**他の書き方**
- Apple の Swift Charts(`Chart { LineMark(...) }`)を使う。→ 軸や目盛りが自動で付くが、1秒に5回1250点を描き直すと重くなりやすい。今は波形が見えれば十分なので `Canvas` にした。軸の目盛りが必要になったら、Charts に替える候補。
- 縦の幅を固定値(例 0〜16383)にする。→ 心電計の値は中心約8192の周りで小さく動くので、固定だと波形がほぼ平らに見える。そのため表示中の最小〜最大に合わせた。欠点は、ノイズで1点だけ大きく外れると、波形全体が縮んで見えること。

---

## 3. ContentView.swift(画面)

**何をしているか**: IP入力欄、ボタン、状態の数字、波形を縦に並べる。

**読み方のポイント**
- `@ObservedObject var relay: RelayClient` は「外から渡された物を見張る」印。`relay` の中の `@Published` の値が変わると、画面が自動で描き直される。Pythonのtkinterでは値を変えるたびに `label.config(text=...)` を自分で呼ぶが、SwiftUIでは不要。
- `@State private var host` は、この画面の中だけで使う変数(入力中のIP)。`TextField(..., text: $host)` の `$` は「値そのものではなく、書き換え口を渡す」という意味で、入力欄に打った文字が `host` に入る。
- `Button("名前") { 押したときの処理 }` は、名前と処理の組。
- `relay.running ? "止める" : "始める"` は三項演算子。Pythonの `"止める" if relay.running else "始める"`。
- `.onAppear { ... }` は画面が出たときに1回、`.onReceive(finder.$found) { ... }` は `finder.found` が変わるたびに呼ばれる。PCが見つかったら入力欄を埋める処理はここにある。
- `UIApplication.shared.isIdleTimerDisabled = true` は画面の自動消灯を止める設定。

**他の書き方**
- `Form` ではなく `VStack`(縦に並べるだけ)で自由に配置する。→ `Form` は iPhone の「設定」アプリと同じ見た目が自動で付き、少ない行で整うので採用した。見た目を作り込むときは `VStack` に替える。

---

## 4. RelayClient.swift(PCへの送信)

**何をしているか**: PCとWebSocketでつなぎ、受け取ったBLEパケットに種類の1バイトを付けて送る。つながっていない間は配列にためる。PCから `pull` が来たら、ためた分を古い順に送る。

**読み方のポイント**
- `final class RelayClient: NSObject, ObservableObject, URLSessionWebSocketDelegate`
  - `final` は「これを継承した子クラスを作らない」という宣言。少し速くなり、意図も明確になる。
  - `NSObject` と `URLSessionWebSocketDelegate` は、iPhoneの通信機能から「接続した」「切れた」の連絡を受け取るために必要な決まり。
  - `ObservableObject` と `@Published` は、画面に状態を自動で反映させるための組。
- `func send(kind: UInt8, packet: Data)`
  - `UInt8` は0〜255の整数(1バイト)、`Data` はバイト列(Pythonの `bytes`)。
  - `var m = Data([kind]); m.append(packet)` は Python の `m = bytes([kind]) + packet`。
- `t.send(.data(m)) { [weak self] err in ... }`
  - 送信は時間がかかるので、終わったときに呼ばれる処理を `{ }` で渡す(コールバック)。
  - `[weak self]` は、「このクラスが消えたら、後から呼ばれた処理の中で使わない」という指定。付けないと、互いに参照し合って、メモリから永遠に消えない状態(循環参照)になることがある。Swiftのコールバックでは、ほぼ決まり文句として付ける。
  - その直後の `guard let self else { return }` で、クラスがまだ生きているかを確かめている。
- `flush()` の中の `func next()` は、関数の中の関数。1つ送り終わったら次を送る、を繰り返す。
  - **なぜ for 文で一気に送らないか**: 一気に送ると、途中で接続が切れたときに、どこまで届いたか分からなくなる。1つずつ「送れたら次」にすれば、失敗したものを配列に戻せる(`buffer.insert(m, at: 0)`)。
- `maxBuffer = 400_000` の `_` は桁区切り(Pythonの `400_000` と同じ)。上限を超えたら古いものから捨てる。
- `Timer.scheduledTimer(withTimeInterval: 3, repeats: true)` は3秒ごとの再接続。

**他の書き方**
- WebSocket ではなく UDP(Pythonの `socket.SOCK_DGRAM`)で送る。→ 遅延は少ないが、届いたかが分からず、ためて再送する処理を自分で作る必要がある。中継の仕様書(`realtime/ネットワーク中継の仕様.md`)がWebSocketを提案していたので、それに合わせた。
- Swift の新しい書き方 `async/await` を使う(`try await task.send(...)`)。→ コールバックの入れ子がなくなり読みやすくなる。今回は、iPhoneのBluetooth機能がコールバック式なので、書き方をそろえるためにコールバックにした。Swiftに慣れたら、`async/await` への書き換えは良い練習になる。
- ためたデータをファイルに保存する。→ アプリが落ちても失われないが、今はメモリ上の配列だけ。長時間の切断に備えるなら、次に足す候補。

---

## 5. BLEManager.swift(Bluetooth受信)

**何をしているか**: 心電計を探して接続し、3つの通知(0011心電・0012動き・0021)を購読して、届いたデータを `RelayClient` に渡す。心電データは、画面用に直近5秒ぶんも保持する。

**読み方のポイント**
- `didXxx` という名前の関数(`didDiscover`、`didConnect` など)は、自分で呼ぶのではなく、iPhoneのBluetooth機能が「〜が起きた」ときに呼ぶ。Pythonの `bleak` でいうと、`start_notify(uuid, callback)` の `callback` に当たるものが、イベントごとに分かれている。この仕組みを「デリゲート」と呼ぶ。
- 処理の順番(上から下へ連鎖する):
  `start()` → 見つかる `didDiscover` → 接続 `didConnect` → サービス発見 `didDiscoverServices` → 特性発見 `didDiscoverCharacteristicsFor` → 購読 `setNotifyValue(true)` → データ到着 `didUpdateValueFor`(以後くり返し)
- `private lazy var svcMain = uuid("0010")` の `lazy` は「最初に使われたときに作る」という指定。`uuid()` は自分のクラスの関数なので、クラスが完成する前には呼べない。`lazy` にすると、完成後の最初の使用時に作られるので呼べる。
- `kinds: [CBUUID: UInt8]` は、特性のUUIDから種類番号(1,2,3)を引く辞書。
- `guard name.lowercased().hasPrefix("kokolog")` は、機器名が `kokolog` で始まるものだけに接続する条件。ここは機器自身の名前との照合なので、アプリ名とは関係なく残している。
- `CBCentralManagerOptionRestoreIdentifierKey` は、iPhoneがアプリを裏で一時停止させた後でも、Bluetoothの接続を引き継ぐための設定。`willRestoreState` がその引き継ぎ処理。
- 切断時 `didDisconnectPeripheral` で、もう一度 `connect` を呼ぶ。iPhoneの `connect` には期限がなく、電波が戻った時点で自動的につながる。

**他の書き方**
- 見つかった機器を一覧にして、利用者に選ばせる。→ 複数の心電計が近くにあるときは必要になる。今は「最初に見つけた1台につなぐ」ので、実験で複数台を使うなら、ここを直す必要がある。
- 購読する特性をすべて自動で購読する。→ 書き込み口(0041)など不要なものまで触る危険がある。そのため、使う3つだけを `kinds` に明示した。

---

## 6. PCFinder.swift(PCの自動検出)

**何をしているか**: 同じWi-Fi内で `pc_receiver.py` が出している「_btrelay._tcp という名前のサービスがここにある」という知らせ(Bonjour)を探し、PCのIPアドレスを取り出す。

**読み方のポイント**
- `NWBrowser` が探す役、`NWConnection` が一度つないでIPを確かめる役。
- `ip.version = .v4` で、`192.168.x.x` 形式(IPv4)のアドレスに限定している。指定しないと、長いIPv6のアドレスが入ることがある。
- `if case .hostPort(let host, _)? = ...` は「値が hostPort という形なら、その中身を host として取り出す」という書き方。Pythonの `match` 文の `case` に近い。
- `%` 以降を切る処理は、アドレスに付くことがある「どのネットワーク経由か」の印(例 `%en0`)を取り除くため。

**他の書き方**
- PCのIPを固定にする(ルーターの設定)。→ 研究室のネットワークを毎回設定できるとは限らないので、自動検出にした。
- QRコードで渡す。→ Bluefy版で使った方法。アプリならカメラ機能が要り、コードが増えるため、Bonjourにした。

---

## 7. Analysis/Sources/EcgCore/Packet.swift(Windowsでも動く解読部分)

```swift
public struct EcgPacket {
    public let seconds: Double
    public let samples: [Int]
    public init?(_ d: [UInt8]) {
        guard d.count >= 104 else { return nil }
        seconds = Double(d[0]) * 3600 + Double(d[1]) * 60 + Double(d[2]) + Double(d[3]) / 256
        samples = (0..<50).map { i in Int(d[4 + 2*i]) | (Int(d[5 + 2*i]) << 8) }
    }
}
```

**読み方のポイント**
- `public` は「このパッケージの外(アプリや確認用プログラム)から使ってよい」という印。付けないと、同じパッケージの中からしか使えない。
- `init?` の `?` は「作るのに失敗することがある」という意味。104バイトに足りないデータなら `nil` を返す。Pythonなら例外を出すか `None` を返すところ。
- `(0..<50).map { i in ... }` は Python の `[... for i in range(50)]`(内包表記)と同じ。
- `Int(d[4 + 2*i]) | (Int(d[5 + 2*i]) << 8)` は、リトルエンディアンの2バイトを1つの整数にする計算。下位バイト + 上位バイト×256 と同じ。Pythonの `int.from_bytes(d[4+2*i:6+2*i], "little")`。

**他の書き方**
- `Data` から `withUnsafeBytes` で `UInt16` の配列として一気に読む。→ 速いが、「unsafe(安全でない)」の名のとおり、範囲外を読む危険がある。1パケット50点なら速さは問題にならないので、読みやすく安全な書き方にした。

---

## 8. 練習課題(コードレビューの準備として)

1. `WaveView` の線の色を青に、高さを200にしてみる(`WaveView.swift`)。
2. `RelayClient` の再接続間隔を3秒から5秒にするには、どの行を変えるか探す。
3. `Packet.swift` に「サンプル値の平均を返す関数」を足し、`Tests` にそのテストを書いて `swift test` で確かめる。
4. `BLEManager` で、心電計が2台あるとき何が起きるかを、コードを読んで説明する。

課題1と2はアプリのビルドが必要、課題3はWindowsだけでできる。
