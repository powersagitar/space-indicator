import Foundation
import Testing

private let cellar = "/opt/homebrew/Cellar/space-indicator/0.1.0/Space Indicator.app"
private let opt = "/opt/homebrew/opt/space-indicator/Space Indicator.app"
private let derivedData =
    "/Users/me/Library/Developer/Xcode/DerivedData/X/Build/Products/Debug/Space Indicator.app"

private func withStore(_ body: (LaunchAgentStore) throws -> Void) throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    try body(LaunchAgentStore(directory: tmp.appendingPathComponent("LaunchAgents")))
}

@Suite struct LaunchAgentTests {
    @Test func rewritesCellarToOpt() {
        #expect(LaunchAgent.stableAppPath(resolvedBundlePath: cellar) == opt)
        #expect(LaunchAgent.isCellarPath(cellar))
    }

    @Test func rewritesRevisionAndUsrLocal() {
        let input = "/usr/local/Cellar/space-indicator/0.1.0_1/Space Indicator.app"
        #expect(
            LaunchAgent.stableAppPath(resolvedBundlePath: input)
                == "/usr/local/opt/space-indicator/Space Indicator.app")
    }

    @Test func leavesOtherPathsUnchanged() {
        let paths = [
            derivedData,
            "/Applications/Space Indicator.app",
            "/opt/homebrew/Cellar/other/1.0/Space Indicator.app",
            "/opt/homebrew/Cellar/space-indicator/Space Indicator.app",
        ]
        for path in paths {
            #expect(LaunchAgent.stableAppPath(resolvedBundlePath: path) == path)
            #expect(!LaunchAgent.isCellarPath(path))
        }
    }

    @Test func plistContents() {
        let exe = LaunchAgent.executablePath(appPath: opt)
        let dict = LaunchAgent.plist(executablePath: exe)
        #expect(exe == opt + "/Contents/MacOS/Space Indicator")
        #expect(dict["Label"] as? String == "com.mohandong.SpaceIndicator")
        #expect(dict["ProgramArguments"] as? [String] == [exe])
        #expect(dict["RunAtLoad"] as? Bool == true)
        #expect(dict["KeepAlive"] as? Bool == false)
        #expect(dict["ProcessType"] as? String == "Interactive")
        #expect(dict.count == 5)
    }

    @Test func installCreatesMissingDirectory() throws {
        try withStore { store in
            #expect(!FileManager.default.fileExists(atPath: store.directory.path))
            try store.install(executablePath: "/x/y")
            #expect(store.isInstalled())
            #expect(store.installedExecutablePath() == "/x/y")
            let text = try String(contentsOf: store.plistURL, encoding: .utf8)
            #expect(text.hasPrefix("<?xml"))
        }
    }

    @Test func uninstallRemovesAndIsIdempotent() throws {
        try withStore { store in
            try store.install(executablePath: "/x/y")
            try store.uninstall()
            #expect(!store.isInstalled())
            try store.uninstall()
        }
    }

    @Test func repairRewritesStaleCellarPath() throws {
        try withStore { store in
            try store.install(executablePath: "/old/path")
            let r = try store.repairIfNeeded(resolvedBundlePath: cellar)
            #expect(r)
            #expect(store.installedExecutablePath() == opt + "/Contents/MacOS/Space Indicator")
            let again = try store.repairIfNeeded(resolvedBundlePath: cellar)
            #expect(!again)
        }
    }

    @Test func repairOverwritesCorruptPlist() throws {
        try withStore { store in
            try FileManager.default.createDirectory(
                at: store.directory, withIntermediateDirectories: true)
            try "garbage".write(to: store.plistURL, atomically: true, encoding: .utf8)
            #expect(store.isInstalled())
            let r = try store.repairIfNeeded(resolvedBundlePath: cellar)
            #expect(r)
            #expect(store.installedExecutablePath() != nil)
        }
    }

    @Test func repairSkipsNonCellarBuild() throws {
        try withStore { store in
            try store.install(executablePath: "/old/path")
            let r = try store.repairIfNeeded(resolvedBundlePath: derivedData)
            #expect(!r)
            #expect(store.installedExecutablePath() == "/old/path")
        }
    }

    @Test func repairSkipsWhenNotInstalled() throws {
        try withStore { store in
            let r = try store.repairIfNeeded(resolvedBundlePath: cellar)
            #expect(!r)
            #expect(!store.isInstalled())
        }
    }
}
