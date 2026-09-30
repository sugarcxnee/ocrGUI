import SwiftUI
import OCRGUICore

@main
struct OCRGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsPane()
                .environment(appModel)
        }
    }
}

/// SPM 可执行程序默认不抢占前台，这里显式激活，保证菜单栏与键盘焦点正常
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
