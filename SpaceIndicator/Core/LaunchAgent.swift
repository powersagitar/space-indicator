import Foundation

enum LaunchAgent {
    static let label = AppIdentity.bundleID

    /// Rewrites a Homebrew Cellar path to the stable `opt` path so the agent survives upgrades.
    static func stableAppPath(resolvedBundlePath: String) -> String {
        resolvedBundlePath.replacingOccurrences(
            of: "^(.+)/Cellar/space-indicator/[^/]+/(.+)$",
            with: "$1/opt/space-indicator/$2",
            options: .regularExpression)
    }

    static func isCellarPath(_ resolvedBundlePath: String) -> Bool {
        stableAppPath(resolvedBundlePath: resolvedBundlePath) != resolvedBundlePath
    }

    static func executablePath(appPath: String) -> String {
        appPath + "/Contents/MacOS/Space Indicator"
    }

    static func stableExecutablePath(resolvedBundlePath: String) -> String {
        executablePath(appPath: stableAppPath(resolvedBundlePath: resolvedBundlePath))
    }

    static func plist(executablePath: String) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]
    }
}

struct LaunchAgentStore {
    let directory: URL

    static var user: LaunchAgentStore {
        LaunchAgentStore(
            directory: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents", isDirectory: true))
    }

    var plistURL: URL {
        directory.appendingPathComponent("\(LaunchAgent.label).plist")
    }

    func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func install(executablePath: String) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: LaunchAgent.plist(executablePath: executablePath),
            format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
    }

    func uninstall() throws {
        guard isInstalled() else { return }
        try FileManager.default.removeItem(at: plistURL)
    }

    func installedExecutablePath() -> String? {
        guard let data = try? Data(contentsOf: plistURL),
            let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = object as? [String: Any],
            let args = dict["ProgramArguments"] as? [String]
        else { return nil }
        return args.first
    }

    @discardableResult
    func repairIfNeeded(resolvedBundlePath: String) throws -> Bool {
        guard isInstalled(), LaunchAgent.isCellarPath(resolvedBundlePath) else { return false }
        let desired = LaunchAgent.stableExecutablePath(resolvedBundlePath: resolvedBundlePath)
        guard installedExecutablePath() != desired else { return false }
        try install(executablePath: desired)
        return true
    }
}
