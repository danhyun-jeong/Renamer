import SwiftUI

@main
struct RenamerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Renamer", systemImage: "rectangle.and.pencil.and.ellipsis") {
            MenuBarContentView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
