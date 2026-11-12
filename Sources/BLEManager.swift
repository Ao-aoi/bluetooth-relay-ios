import Foundation
import CoreBluetooth

/// 心電計の通知(心電図・動き・5秒ごと)を購読し、受け取ったバイト列を加工せずに RelayClient へ渡す。
/// 心電図と動きは AnalysisModel にも渡して、アプリの中で解析する。
/// 書き込みは一切しない。
final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var status = "待機中"
    @Published var scanning = false
    @Published var deviceName = ""   // 接続中の心電計の名前
    @Published var serial = ""       // 接続中の心電計の製造番号(0031 の読み出し値から)
    @Published var counts: [UInt8: Int] = [:]

    private let analysis: AnalysisModel
    private let relay: RelayClient
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var wantConnection = false

    private func uuid(_ s: String) -> CBUUID { CBUUID(string: "0e97\(s)-ec52-42ce-9075-c027350fb893") }
    private lazy var svcMain = uuid("0010")   // 0011 ECG, 0012 motion
    private lazy var svcMisc = uuid("0020")   // 0021 (5秒ごと)
    private lazy var svcInfo = uuid("0030")   // 0031 機器情報(読み出しのみ)
    private lazy var chInfo = uuid("0031")
    private lazy var kinds: [CBUUID: UInt8] = [uuid("0011"): 0x01, uuid("0012"): 0x02, uuid("0021"): 0x03]

    init(relay: RelayClient, analysis: AnalysisModel) {
        self.relay = relay
        self.analysis = analysis
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
            peripheral = p; p.delegate = self; wantConnection = true; deviceName = p.name ?? ""
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        guard name.lowercased().hasPrefix("kokolog") else { return }
        central.stopScan()
        peripheral = p
        p.delegate = self
        deviceName = name
        status = "\(name) に接続中..."
        central.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        status = "接続しました。サービスを調べています..."
        serial = ""
        p.discoverServices([svcMain, svcMisc, svcInfo])
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
        for s in p.services ?? [] { p.discoverCharacteristics(Array(kinds.keys) + [chInfo], for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] where kinds[ch.uuid] != nil && ch.properties.contains(.notify) {
            p.setNotifyValue(true, for: ch)   // 通知の購読のみ(書き込みなし)
        }
        for ch in s.characteristics ?? [] where ch.uuid == chInfo && ch.properties.contains(.read) {
            p.readValue(for: ch)              // 機器情報の読み出し(書き込みなし)
        }
        status = "受信中"
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if ch.uuid == chInfo, let data = ch.value {
            // 形式: "FW01.01/製造番号/モード/メモリ/電池"
            let text = String(decoding: data, as: UTF8.self)
            let parts = text.split(separator: "/")
            serial = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)) : text
            return
        }
        guard let kind = kinds[ch.uuid], let data = ch.value else { return }
        counts[kind, default: 0] += 1
        if kind == 0x01 || kind == 0x02 { analysis.receive(kind: kind, data: data) }
        relay.send(kind: kind, packet: data)
    }
}
