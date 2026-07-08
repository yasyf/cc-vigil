import AppKit
import CCVigilAppKit
import SwiftUI

struct InstallerView: View {
    let controller: InstallerController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(24)
        .frame(width: 480, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
        switch controller.state {
        case .idle:
            title("Welcome to cc-vigil")
            Text("""
            cc-vigil keeps this Mac awake while local Claude Code agents are truly \
            working. Setup installs:
            • a background agent that watches session transcripts
            • a privileged helper that manages sleep (admin approval required)
            • Claude Code hooks that nudge re-evaluation
            • the cc-vigil command line tool
            """)
            Button("Install") {
                controller.begin()
            }
            .keyboardShortcut(.defaultAction)
        case .translocated:
            title("Move cc-vigil to Applications")
            Text("""
            macOS is running this copy from a quarantined (translocated) path, so \
            background services cannot be registered. Move CCVigil.app into \
            /Applications, relaunch it, and run setup again.
            """)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        case .registeringServices:
            title("Setting up")
            progress("Registering background services…")
        case .awaitingApproval:
            title("Approval needed")
            progress("Waiting for approval in System Settings → Login Items…")
            Button("Open Login Items") {
                controller.openLoginItemsSettings()
            }
        case .installingHooks:
            title("Setting up")
            progress("Installing Claude Code hooks…")
        case .linkingCLI:
            title("Setting up")
            progress("Linking the cc-vigil CLI…")
        case let .failed(step, message):
            title("Setup failed during \(step.rawValue)")
            Text(message)
                .textSelection(.enabled)
            Button("Retry") {
                controller.retry()
            }
            .keyboardShortcut(.defaultAction)
        case let .done(summary):
            title("cc-vigil is ready")
            Text("""
            Installed:
            • background services (agent + privileged helper)
            • Claude Code hooks running `\(summary.hookCommand)`
            • CLI symlink at \(summary.cliSymlinkPath)
            """)
            .textSelection(.enabled)
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.title2)
            .bold()
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(text)
        }
    }
}
