import SwiftUI
import OCRGUICore

/// 主窗口占位（P2 起逐步替换为三栏布局）
struct ContentView: View {
    var body: some View {
        Text("OCR GUI \(OCRGUIInfo.version)")
            .font(.title)
            .padding()
    }
}

/// 设置窗口占位（P3 实现引擎管理）
struct SettingsPane: View {
    var body: some View {
        Form {
            Text("设置（待实现）")
        }
        .frame(width: 420, height: 300)
    }
}
