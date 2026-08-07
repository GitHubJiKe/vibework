import AppKit

final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private weak var model: AppModel?

    func setup(with model: AppModel) {
        self.model = model
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "app.connected.to.app.below.fill",
                                   accessibilityDescription: "VibePilot")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let model else { return }

        if model.isRunning {
            menu.addItem(disabled("正在推流：\(model.currentAppName ?? "?")"))
            menu.addItem(disabled(model.serverURL))
            if model.appNames.count > 1 {
                menu.addItem(.separator())
                let switchMenu = NSMenu()
                for (i, name) in model.appNames.enumerated() {
                    let action = NSMenuItem(title: name, action: #selector(switchApp(_:)),
                                            keyEquivalent: "")
                    action.target = self
                    action.tag = i
                    action.state = i == model.currentIndex ? .on : .off
                    switchMenu.addItem(action)
                }
                let parent = NSMenuItem(title: "切换应用", action: nil, keyEquivalent: "")
                menu.addItem(parent)
                menu.setSubmenu(switchMenu, for: parent)
            }
            menu.addItem(.separator())
            let stopItem = NSMenuItem(title: "停止推流", action: #selector(stopStreaming),
                                      keyEquivalent: "s")
            stopItem.target = self
            menu.addItem(stopItem)
        } else {
            menu.addItem(disabled("未运行"))
        }

        menu.addItem(.separator())
        let openItem = NSMenuItem(title: "打开主窗口", action: #selector(showMainWindow),
                                  keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 VibePilot", action: #selector(quitApp),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func switchApp(_ sender: NSMenuItem) {
        guard let model else { return }
        Task { await model.switchApp(to: sender.tag) }
    }

    @objc private func stopStreaming() {
        guard let model else { return }
        Task { await model.stop() }
    }

    @objc private func showMainWindow() {
        (NSApp.delegate as? AppDelegate)?.showMainWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
