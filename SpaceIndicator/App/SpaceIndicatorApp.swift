import SwiftUI

@main
struct SpaceIndicatorApp: App {
    @State private var model: SpaceIndicatorModel

    init() {
        let bundleID = "com.mohandong.SpaceIndicator"
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { $0.processIdentifier != getpid() })
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
