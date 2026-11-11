// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Analysis",
    targets: [
        // 解析の計算部分(iPhoneアプリとWindowsで共通に使う)
        .target(name: "EcgCore"),
        // Windowsで動かす確認用プログラム
        .executableTarget(name: "ecgcheck", dependencies: ["EcgCore"]),
        .testTarget(name: "EcgCoreTests", dependencies: ["EcgCore"]),
    ]
)
