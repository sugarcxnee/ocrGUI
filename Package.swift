// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "OCRGUI",
    platforms: [.macOS(.v14)],
    targets: [
        // 核心逻辑库：模型、引擎、管线、存储（可测试）
        .target(
            name: "OCRGUICore",
            path: "Sources/OCRGUICore"
        ),
        // 应用壳：SwiftUI 界面
        .executableTarget(
            name: "OCRGUI",
            dependencies: ["OCRGUICore"],
            path: "Sources/OCRGUI"
        ),
        .testTarget(
            name: "OCRGUITests",
            dependencies: ["OCRGUICore"],
            path: "Tests/OCRGUITests"
        ),
    ]
)
