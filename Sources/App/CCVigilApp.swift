import AppKit
import CCVigilAppKit
import SwiftUI

enum WindowID {
    static let installer = "installer"
}

@main
struct CCVigilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @State private var installer: InstallerController

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        _installer = State(initialValue: InstallerController { model.completeFirstRun() })
        AppDelegate.model = model
        model.start()
    }

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarInserted) {
            VigilMenu(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        Window("cc-vigil Setup", id: WindowID.installer) {
            InstallerView(controller: installer)
        }
        .windowResizability(.contentSize)
        Settings {
            SettingsView(model: model)
        }
    }

    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { !model.config.hideMenuBarExtra },
            set: { model.setHideMenuBarExtra(!$0) }
        )
    }
}

private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: model.status.icon.systemImage)
            .task {
                if !model.firstRunCompleted {
                    openWindow(id: WindowID.installer)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}

/// Relaunching the hidden app is the escape hatch back to the menu bar icon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak static var model: AppModel?

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        Self.model?.setHideMenuBarExtra(false)
        return true
    }
}
