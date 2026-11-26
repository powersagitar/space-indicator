import AppKit
import Observation
import OSLog

@MainActor
@Observable
final class SpaceIndicatorModel {
    private(set) var title = SpaceNumbering.title(for: [])
    /// Bumped after every toggle and when a menu starts tracking, to invalidate views reading `launchAtLogin`.
    private var loginRevision = 0

    @ObservationIgnored private var previousApp: NSRunningApplication?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let logger = Logger(
        subsystem: "com.mohandong.SpaceIndicator", category: "LaunchAgent")

    private static var resolvedBundlePath: String {
        Bundle.main.bundleURL.resolvingSymlinksInPath().path
    }

    init() {
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
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.loginRevision += 1
                    self?.refresh()
                }
            })
        // A Space's position can change without a Space switch (reordering in Mission Control,
        // or an app quitting removes its full-screen Space), so also refresh on app activation,
        // app termination and menu open. No polling.
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        // A menu bar app has no windows to focus, but `open` on a running copy activates it
        // and steals focus. Remember the last other frontmost app and give focus back.
        previousApp = NSWorkspace.shared.frontmostApplication
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    self?.refresh()
                    self?.frontmostChanged(to: app)
                }
            })
        do {
            _ = try LaunchAgentStore.user.repairIfNeeded(
                resolvedBundlePath: Self.resolvedBundlePath)
        } catch {
            logger.error("Repair failed: \(error.localizedDescription)")
        }
    }

    /// Always hands focus back when this app is activated. Fine while the app has no windows
    /// or alerts (by design); any added later would have focus taken away from them by this.
    private func frontmostChanged(to app: NSRunningApplication?) {
        guard let app else { return }
        if app.processIdentifier == getpid() {
            previousApp?.activate()
        } else {
            previousApp = app
        }
    }

    func refresh() {
        title = SpaceNumbering.title(for: CGS.spaceNumbers())
    }

    /// Reads the LaunchAgent file on each evaluation; `loginRevision` is what triggers re-evaluation.
    var launchAtLogin: Bool {
        get {
            _ = loginRevision
            return LaunchAgentStore.user.isInstalled()
        }
        set {
            let store = LaunchAgentStore.user
            do {
                if newValue {
                    let app = LaunchAgent.stableAppPath(resolvedBundlePath: Self.resolvedBundlePath)
                    try store.install(executablePath: LaunchAgent.executablePath(appPath: app))
                } else {
                    try store.uninstall()
                }
            } catch {
                logger.error("Toggle failed: \(error.localizedDescription)")
            }
            loginRevision += 1
        }
    }
}
