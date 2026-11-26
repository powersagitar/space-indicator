import AppKit

let bundleID = "com.mohandong.SpaceIndicator"
if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .contains(where: { $0.processIdentifier != getpid() })
{
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
