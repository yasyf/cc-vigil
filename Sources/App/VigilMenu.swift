import AppKit
import CCVigilAppKit
import SwiftUI

private let holdChoices: [(title: String, seconds: Int)] = [
    ("For 30 Minutes", 1800),
    ("For 2 Hours", 7200),
    ("For 8 Hours", 28800),
]

struct VigilMenu: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Text(model.headline)
            ForEach(model.status.sessionLines, id: \.self) { line in
                Text(line)
            }
            if let error = model.commandError {
                Text("error: \(error)")
            }
            if let lines = model.awaySummary?.lines, !lines.isEmpty {
                Divider()
                Text("while you were away")
                ForEach(lines, id: \.self) { line in
                    Text(line)
                }
            }
            Divider()
            Button(model.pauseMenuTitle) {
                model.togglePause()
            }
            .disabled(!model.status.canSendCommands)
            holdMenu
            Divider()
            if !model.firstRunCompleted {
                Button("Finish Setup…") {
                    openWindow(id: WindowID.installer)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            SettingsLink {
                Text("Settings…")
            }
            Button("Quit cc-vigil") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear {
            model.menuOpened()
        }
    }

    private var holdMenu: some View {
        Menu("Keep Awake") {
            ForEach(holdChoices, id: \.seconds) { choice in
                Button(choice.title) {
                    model.hold(seconds: choice.seconds)
                }
            }
            if !model.status.activeHolds.isEmpty {
                Divider()
                ForEach(model.status.activeHolds, id: \.key) { hold in
                    Button("Release \(hold.key)") {
                        model.releaseHold(key: hold.key)
                    }
                }
            }
        }
        .disabled(!model.status.canSendCommands)
    }
}
