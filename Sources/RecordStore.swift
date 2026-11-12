import Foundation

/// 記録ファイル1つ。
struct RecordFile: Identifiable, Hashable {
    let url: URL
    let start: Date          // 記録を始めた時刻(ファイル名から)
    let modified: Date       // 最後に書き込んだ時刻
    let bytes: Int
    var id: URL { url }
    /// おおよその記録時間[秒]。心電(107バイト)と動き(43バイト)が1秒に5個ずつ届く前提。
    var approxSeconds: Double { Double(bytes) / 750.0 }
}

/// 記録ファイルの置き場所(アプリの「書類」フォルダの recordings)。
/// ファイルAppの「このiPhone内 > Bluetooth Relay」からも見える。
enum RecordStore {
    static var folder: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static let nameFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()

    static func newURL() -> URL {
        folder.appendingPathComponent("rec_\(nameFormat.string(from: Date())).bin")
    }

    /// 新しい順。
    static func list() -> [RecordFile] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return urls.filter { $0.pathExtension == "bin" }.compactMap { u in
            let v = try? u.resourceValues(forKeys: Set(keys))
            let stem = u.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "rec_", with: "")
            guard let start = nameFormat.date(from: stem) else { return nil }
            return RecordFile(url: u, start: start, modified: v?.contentModificationDate ?? start, bytes: v?.fileSize ?? 0)
        }.sorted { $0.start > $1.start }
    }
}

/// 受信したパケットを記録ファイルに書き足す。書いた分は、アプリを終了されても残る。
final class Recorder {
    private(set) var url: URL? = nil
    private var handle: FileHandle? = nil

    /// 既存のファイルに続けて書く。
    func resume(_ u: URL) {
        close()
        guard let h = try? FileHandle(forWritingTo: u) else { return }
        h.seekToEndOfFile()
        url = u; handle = h
    }

    func write(kind: UInt8, _ d: Data) {
        if handle == nil {
            let u = RecordStore.newURL()
            FileManager.default.createFile(atPath: u.path, contents: nil)
            url = u
            handle = try? FileHandle(forWritingTo: u)
        }
        handle?.write(Data(Recording.encode(kind: kind, [UInt8](d))))
    }

    /// 今のファイルを閉じる。次に書くときは新しいファイルになる。
    func close() {
        try? handle?.close()
        handle = nil
        url = nil
    }
}
