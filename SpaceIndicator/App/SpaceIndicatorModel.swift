import AppKit
import Observation
import OSLog

@MainActor
@Observable
final class SpaceIndicatorModel {
    private(set) var title = SpaceNumbering.title(for: [])
    /// Whether the LaunchAgent plist exists. Re-read from disk at launch, after every toggle,
    /// and when a menu starts tracking, so a change made outside the app shows on the next open.
    private(set) var launchAtLogin = false

    @ObservationIgnored private var previousApp: NSRunningApplication?
    @ObservationIgnored private let store = LaunchAgentStore.user
    @ObservationIgnored private let logger = Logger(
        subsystem: AppIdentity.bundleID, category: "LaunchAgent")

    private static var resolvedBundlePath: String {
        Bundle.main.bundleURL.resolvingSymlinksInPath().path
    }

    init() {
        refresh()
        reloadLaunchAtLogin()
        // The poll below is the catch-all: macOS posts no notification when Mission Control
        // reorders Spaces or a full-screen Space disappears, and it also covers display changes.
        // This observer only makes the common case, a Space switch, update instantly.
        // Block observers and the timer are retained by their center and run loop for the
        // app's lifetime, so none of them is stored.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadLaunchAtLogin() }
        }
        // Poll one WindowServer query every second. `.common` mode keeps it firing while the
        // menu is open; refresh() only assigns when the title changes.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        // A menu bar app has no windows to focus, but `open` on a running copy activates it
        // and steals focus. Remember the last other frontmost app and give focus back.
        previousApp = NSWorkspace.shared.frontmostApplication
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.frontmostChanged(to: app) }
        }
        do {
            try store.repairIfNeeded(resolvedBundlePath: Self.resolvedBundlePath)
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

    /// The 1 s poll must not re-render the label when nothing changed. @Observable already
    /// skips notifying when an equal value is assigned; the explicit guard states that intent.
    func refresh() {
        let new = SpaceNumbering.title(for: CGS.spaceNumbers())
        if new != title { title = new }
    }

    /// Installs or removes the LaunchAgent, then re-reads the file whether or not that worked.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try store.install(executablePath: LaunchAgent.stableExecutablePath(
                    resolvedBundlePath: Self.resolvedBundlePath))
            } else {
                try store.uninstall()
            }
        } catch {
            logger.error("Toggle failed: \(error.localizedDescription)")
        }
        reloadLaunchAtLogin()
    }

    /// Mirrors the file on disk. Observers are notified only when the value actually changes
    /// (@Observable skips equal assignments), e.g. after a toggle or an outside edit.
    private func reloadLaunchAtLogin() {
        launchAtLogin = store.isInstalled()
    }
}
