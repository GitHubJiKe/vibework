import SwiftUI
import AppKit

@main
final class VibePilotMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var menuBar: MenuBarController?
    private let model = AppModel.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menuBar = MenuBarController()
        menuBar.setup(with: model)
        self.menuBar = menuBar
        showMainWindow()
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = mainWindow {
            win.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: ContentView().environmentObject(model))
        let win = NSWindow(contentViewController: hosting)
        win.title = "VibePilot"
        win.setContentSize(NSSize(width: 700, height: 620))
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.isReleasedWhenClosed = false
        mainWindow = win
        win.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await AppModel.shared.stop()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }
}
