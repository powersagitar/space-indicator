import AppKit
import Observation
import OSLog

@MainActor
@Observable
final class SpaceIndicatorModel {
    private(set) var title = SpaceNumbering.title(for: nil)
    /// Bumped after every toggle so views re-read the file-backed state.
    private var loginRevision = 0

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
        do {
            _ = try LaunchAgentStore.user.repairIfNeeded(
                resolvedBundlePath: Self.resolvedBundlePath)
        } catch {
            logger.error("Repair failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refresh() {
        title = SpaceNumbering.title(for: CGS.activeSpaceNumber())
    }

    /// Reads the real file every time; `loginRevision` keeps the read tracked.
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
                logger.error("Toggle failed: \(error.localizedDescription, privacy: .public)")
            }
            loginRevision += 1
        }
    }
}
