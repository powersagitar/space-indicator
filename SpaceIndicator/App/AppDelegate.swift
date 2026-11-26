import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let loginItem = NSMenuItem(
        title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let logger = Logger(subsystem: "com.mohandong.SpaceIndicator", category: "LaunchAgent")
    private var observers: [NSObjectProtocol] = []

    private static var resolvedBundlePath: String {
        Bundle.main.bundleURL.resolvingSymlinksInPath().path
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize, weight: .regular)

        loginItem.target = self
        let quit = NSMenuItem(
            title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(quit)
        item.menu = menu

        refresh()

        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })

        do {
            _ = try LaunchAgentStore.user.repairIfNeeded(
                resolvedBundlePath: Self.resolvedBundlePath)
        } catch {
            logger.error("Repair failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refresh() {
        statusItem?.button?.title = SpaceNumbering.title(for: CGS.activeSpaceNumber())
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        loginItem.state = LaunchAgentStore.user.isInstalled() ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        let store = LaunchAgentStore.user
        do {
            if store.isInstalled() {
                try store.uninstall()
            } else {
                let app = LaunchAgent.stableAppPath(resolvedBundlePath: Self.resolvedBundlePath)
                try store.install(executablePath: LaunchAgent.executablePath(appPath: app))
            }
        } catch {
            logger.error("Toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
