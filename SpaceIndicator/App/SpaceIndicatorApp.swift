import SwiftUI

@main
struct SpaceIndicatorApp: App {
    @State private var model: SpaceIndicatorModel

    init() {
        let othersRunning = {
            NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.bundleID)
                .contains { $0.processIdentifier != getpid() && !$0.isTerminated }
        }
        // Default wait is Thread.sleep: the main run loop has no sources before NSApplication.run,
        // so RunLoop.run(until:) would return at once. Each poll re-queries the running apps.
        if SingleInstance.anotherInstanceRemains(othersRunning: othersRunning) {
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        _model = State(initialValue: SpaceIndicatorModel())
    }

    var body: some Scene {
        MenuBarExtra {
            Toggle("Launch at Login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }))
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            // Plain text so the system styles it like its own menu bar text (weight, size, position).
            // MenuBarExtra ignores font and frame modifiers, so the width follows the digits.
            Text(model.title)
        }
        .menuBarExtraStyle(.menu)
    }
}
