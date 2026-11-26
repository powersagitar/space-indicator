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
    /// Lives as long as the model, i.e. the app.
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private let logger = Logger(
        subsystem: "com.mohandong.SpaceIndicator", category: "LaunchAgent")

    private static var resolvedBundlePath: String {
        Bundle.main.bundleURL.resolvingSymlinksInPath().path
    }

    init() {
        refresh()
        // The poll below is the catch-all: macOS posts no notification when Mission Control
        // reorders Spaces or a full-screen Space disappears, and it also covers display changes.
        // This observer only makes the common case, a Space switch, update instantly.
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.loginRevision += 1 }
            })
        // Poll one WindowServer query every second. `.common` mode keeps it firing while the
        // menu is open; refresh() only assigns when the title changes.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        // A menu bar app has no windows to focus, but `open` on a running copy activates it
        // and steals focus. Remember the last other frontmost app and give focus back.
        previousApp = NSWorkspace.shared.frontmostApplication
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.frontmostChanged(to: app) }
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

    /// Assigns only on change: @Observable notifies on every set, and the 1 s poll would
    /// otherwise re-render the label every second.
    func refresh() {
        let new = SpaceNumbering.title(for: CGS.spaceNumbers())
        if new != title { title = new }
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
