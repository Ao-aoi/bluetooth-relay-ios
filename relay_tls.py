"""iPhone と PC の間の通信を暗号化する(TLS)ための、PC側の共通部品。

- 初めて動かしたとき、このPC専用の鍵と証明書を作り、ホームフォルダの .btrelay に保存する。
  (pc_receiver と pc_monitor で同じものを使う。消すと作り直され、確認コードが変わる)
- 証明書から「確認コード」(8文字)を作って表示する。iPhoneアプリは初めてつなぐときにこのコードを出すので、
  PCの画面のコードと同じであることを確かめてから「信頼する」を押す。2回目からは自動でつながる。
- 第三者がPCになりすましても、確認コードが一致しないので、iPhoneはつながらない。
"""
import datetime
import hashlib
import ipaddress
import ssl
from pathlib import Path

DIR = Path.home() / ".btrelay"
CERT = DIR / "cert.pem"
KEY = DIR / "key.pem"


def _make_cert():
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.x509.oid import NameOID

    DIR.mkdir(exist_ok=True)
    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Bluetooth Relay PC")])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (x509.CertificateBuilder()
            .subject_name(name).issuer_name(name)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - datetime.timedelta(days=1))
            .not_valid_after(now + datetime.timedelta(days=3650))
            .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ipaddress.ip_address("127.0.0.1"))]), False)
            .sign(key, hashes.SHA256()))
    KEY.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                      serialization.NoEncryption()))
    try:
        KEY.chmod(0o600)
    except OSError:
        pass
    CERT.write_bytes(cert.public_bytes(serialization.Encoding.PEM))


def fingerprint():
    """証明書(DER)の SHA-256。iPhoneアプリはこの値を覚えて、次から照合する。"""
    der = ssl.PEM_cert_to_DER_cert(CERT.read_text())
    return hashlib.sha256(der).hexdigest().upper()


def code():
    """確認コード。証明書の SHA-256 の先頭8文字を XXXX-XXXX の形にしたもの。"""
    f = fingerprint()
    return f"{f[:4]}-{f[4:8]}"


def server_context():
    """WebSocket の待ち受けに渡す TLS の設定。"""
    if not (CERT.exists() and KEY.exists()):
        _make_cert()
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(CERT, KEY)
    return ctx
