import AppKit
import SwiftUI

// TODO: SMAppService registration (login item, daemon, helper) lands with the product logic.

@main
struct CCVigilApp: App {
    var body: some Scene {
        MenuBarExtra("cc-vigil", systemImage: "eye") {
            Text("cc-vigil skeleton — idle")
            Divider()
            Button("Quit cc-vigil") { NSApplication.shared.terminate(nil) }
        }
    }
}
