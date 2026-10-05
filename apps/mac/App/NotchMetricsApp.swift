import SwiftUI

@main
struct NotchMetricsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // A plain `Window`, not the `Settings` scene.
        //
        // `Settings` + `SettingsLink` presumes an app menu the user can reach,
        // which an LSUIElement app does not have, and `SettingsLink` cannot be
        // triggered programmatically — so the gear button in the notch, and
        // `notchmetrics://settings`, would both have nothing to call.
        Window("Notch Metrics Settings", id: SettingsWindowID.main) {
            SettingsRootView()
                .environment(delegate.env)
                .frame(minWidth: 760, minHeight: 500)
        }
        .defaultSize(width: 860, height: 580)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .commands {
            // The notch is the app; a "New Window" item makes no sense here.
            CommandGroup(replacing: .newItem) {}
        }
    }
}
