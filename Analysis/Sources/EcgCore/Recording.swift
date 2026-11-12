import Foundation

/// 受信したパケットの記録ファイル。1件 = [種類 1バイト][長さ 1バイト][BLEパケット]。
/// 種類は中継と同じ(0x01=心電, 0x02=動き)。アプリを途中で終了されても、それまでに書いた分は残る。
public enum Recording {
    public static func encode(kind: UInt8, _ d: [UInt8]) -> [UInt8] {
        guard d.count <= 255 else { return [] }
        return [kind, UInt8(d.count)] + d
    }

    /// 記録を読み出す。末尾が途中で切れている件は捨てる。
    public static func decode(_ b: [UInt8]) -> [(kind: UInt8, packet: [UInt8])] {
        var out = [(kind: UInt8, packet: [UInt8])]()
        var i = 0
        while i + 2 <= b.count {
            let n = Int(b[i + 1])
            if i + 2 + n > b.count { break }
            out.append((b[i], Array(b[(i + 2)..<(i + 2 + n)])))
            i += 2 + n
        }
        return out
    }

    /// 記録を最初から流し直して、解析を受信時と同じ状態にする。
    /// progress には 0〜1 の進み具合を渡す(呼ぶ間隔はおよそ1%ごと)。
    public static func replay(_ b: [UInt8], into s: EcgSession, progress: ((Double) -> Void)? = nil) {
        let recs = decode(b)
        let step = max(1, recs.count / 100)
        for (i, r) in recs.enumerated() {
            if r.kind == 0x01, let p = EcgPacket(r.packet) { s.onPacket(p) }
            else if r.kind == 0x02, let p = GyroPacket(r.packet) { s.onGyro(p) }
            if i % step == 0 { progress?(Double(i) / Double(recs.count)) }
        }
    }
}
