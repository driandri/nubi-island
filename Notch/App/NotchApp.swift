import SwiftUI

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                // Every entry point uses the same reusable AppKit settings window.
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { delegate.openSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}
