import SwiftUI

@main
struct SpaceIndicatorApp: App {
    @State private var model: SpaceIndicatorModel

    init() {
        let bundleID = "com.mohandong.SpaceIndicator"
        let othersRunning = {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .contains { $0.processIdentifier != getpid() && !$0.isTerminated }
        }
        // Spin the run loop between polls so terminated instances are noticed.
        if SingleInstance.anotherInstanceRemains(
            wait: { RunLoop.current.run(until: Date(timeIntervalSinceNow: $0)) },
            othersRunning: othersRunning)
        {
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        _model = State(initialValue: SpaceIndicatorModel())
    }

    var body: some Scene {
        MenuBarExtra {
            @Bindable var model = model
            Toggle("Launch at Login", isOn: $model.launchAtLogin)
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: TitleImage.make(model.title))
                .accessibilityLabel(model.title)
        }
        .menuBarExtraStyle(.menu)
    }
}
