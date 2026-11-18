import Foundation
import CryptoKit
import Security

/// PCとの通信の暗号化(TLS)で、相手が本物のPCかを確かめる。
///
/// PCは自分で作った証明書を使うので、iOSの標準の確認(公的な認証局の署名)は通らない。
/// 代わりに、証明書の SHA-256(指紋)をPCごとに覚えておき、次からはそれと一致する相手にだけつなぐ。
/// 初めてのPCでは、確認コード(指紋の先頭8文字)を画面に出し、PCの画面と同じなら覚える。
enum TLSPin {
    private static func key(_ host: String) -> String { "pin.\(host)" }

    static func pinned(_ host: String) -> String? { UserDefaults.standard.string(forKey: key(host)) }

    static func trust(_ host: String, fingerprint: String) { UserDefaults.standard.set(fingerprint, forKey: key(host)) }

    /// 覚えたPCを全部忘れる。
    static func forgetAll() {
        for k in UserDefaults.standard.dictionaryRepresentation().keys where k.hasPrefix("pin.") {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }

    /// 確認コード: 指紋の先頭8文字を XXXX-XXXX の形にしたもの(PC側 relay_tls.code() と同じ)。
    static func code(_ fingerprint: String) -> String {
        let s = Array(fingerprint)
        return String(s[0..<4]) + "-" + String(s[4..<8])
    }

    /// 相手の証明書の指紋。取れなければ nil。
    static func fingerprint(_ trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else { return nil }
        let der = SecCertificateCopyData(leaf) as Data
        return SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined()
    }

    enum Result {
        case ok(URLCredential)
        case unknown(String)     // 初めてのPC。指紋を返すので、利用者に確認してもらう
        case mismatch            // 覚えた指紋と違う(別のPC、またはなりすまし)
    }

    static func check(_ challenge: URLAuthenticationChallenge, host: String) -> Result? {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust, let fp = fingerprint(trust) else { return nil }
        guard let known = pinned(host) else { return .unknown(fp) }
        return known == fp ? .ok(URLCredential(trust: trust)) : .mismatch
    }
}

/// 確認待ちのPC(初めてつなぐPC)。
struct PendingPC: Identifiable, Equatable {
    let host: String
    let fingerprint: String
    var id: String { host + fingerprint }
    var code: String { TLSPin.code(fingerprint) }
}
