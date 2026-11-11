import Foundation
import CoreBluetooth

/// 心電計の通知(心電図・動き・5秒ごと)を購読し、受け取ったバイト列を加工せずに RelayClient へ渡す。
/// 書き込みは一切しない。
final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var status = "待機中"
    @Published var scanning = false
    @Published var counts: [UInt8: Int] = [:]
    /// 画面表示用: 直近5秒(250Hz×5=1250点)の心電図
    @Published var wave: [Int] = []
    private let waveLength = 1250

    // 解析結果(画面表示用)
    @Published var heartRate: Double? = nil        // 最新の拍の心拍数[bpm]
    @Published var rir: Double? = nil              // 最新のRiR(まだ出ていなければ nil)
    @Published var validSec: Double = 0            // RiRが出るまでに溜まった有効な拍の時間[秒]
    @Published var quality: SignalQuality? = nil   // 信号品質
    @Published var lostPackets = 0                 // 届かなかった心電パケットの数
    let validSpan: Double = 120
    private var session = EcgSession()

    private let relay: RelayClient
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var wantConnection = false

    private func uuid(_ s: String) -> CBUUID { CBUUID(string: "0e97\(s)-ec52-42ce-9075-c027350fb893") }
    private lazy var svcMain = uuid("0010")   // 0011 ECG, 0012 motion
    private lazy var svcMisc = uuid("0020")   // 0021 (5秒ごと)
    private lazy var kinds: [CBUUID: UInt8] = [uuid("0011"): 0x01, uuid("0012"): 0x02, uuid("0021"): 0x03]

    init(relay: RelayClient) {
        self.relay = relay
        super.init()
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "bluetooth-relay"])
    }

    func start() {
        wantConnection = true
        guard central.state == .poweredOn else { status = "Bluetoothをオンにしてください"; return }
        if let p = peripheral { central.connect(p); status = "再接続中..."; scanning = true; return }
        scanning = true
        status = "心電計を探しています..."
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    func stop() {
        wantConnection = false
        scanning = false
        central.stopScan()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        status = "停止中"
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn, wantConnection { start() }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = ps.first {
            peripheral = p; p.delegate = self; wantConnection = true
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        guard name.lowercased().hasPrefix("kokolog") else { return }
        central.stopScan()
        peripheral = p
        p.delegate = self
        status = "\(name) に接続中..."
        central.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        status = "接続しました。サービスを調べています..."
        p.discoverServices([svcMain, svcMisc])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        status = "接続に失敗。再試行します"
        if wantConnection { central.connect(p) }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        status = "切れました。自動で再接続します"
        if wantConnection { central.connect(p) }   // 電波が戻れば自動でつながる(背景でも有効)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics(Array(kinds.keys), for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] where kinds[ch.uuid] != nil && ch.properties.contains(.notify) {
            p.setNotifyValue(true, for: ch)   // 通知の購読のみ(書き込みなし)
        }
        status = "受信中"
    }

    /// 心電パケット1つを解析に渡し、画面用の値を更新する。
    private func analyze(_ pkt: EcgPacket) {
        session.onPacket(pkt)
        let e = session.ecg
        if let last = e.beats.last {
            heartRate = last.hrBpm
            rir = last.rir
        }
        validSec = e.rir.validSec()
        quality = e.quality()
        lostPackets = session.lost
    }

    /// 解析をやり直す(別の人に付け替えたときなど)。
    func resetAnalysis() {
        session = EcgSession()
        heartRate = nil; rir = nil; validSec = 0; quality = nil; lostPackets = 0
        wave = []
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let kind = kinds[ch.uuid], let data = ch.value else { return }
        counts[kind, default: 0] += 1
        if kind == 0x01, let pkt = EcgPacket([UInt8](data)) {
            wave.append(contentsOf: pkt.samples.map { $0 & 0x3FFF })
            if wave.count > waveLength { wave.removeFirst(wave.count - waveLength) }
            analyze(pkt)
        }
        relay.send(kind: kind, packet: data)
    }
}
