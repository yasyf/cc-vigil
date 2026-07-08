import CCVigilAppKit
import CCVigilShared
import Foundation

enum Uninstaller {
    static func run(registrar: ServiceRegistrar, commands: DaemonCommands) async -> [String] {
        await UninstallSequence.run(UninstallSteps(
            uninstallHooks: {
                let hooks = await BundledCLI.run(["uninstall-hooks"])
                return hooks.status == 0 ? hooks.output : "uninstall-hooks failed: \(hooks.output)"
            },
            clearSleepBlock: {
                if case .ok = try? await commands.roundTrip(.clear) {
                    return true
                }
                return false
            },
            unregisterServices: {
                await Task.detached(priority: .userInitiated) {
                    registrar.unregisterAll()
                }.value
            },
            removeSymlinks: {
                do {
                    let removed = try CLISymlinker.removeLinks(
                        pointingInto: Bundle.main.bundlePath,
                        directories: CLISymlinker.defaultDirectories(
                            home: FileManager.default.homeDirectoryForCurrentUser
                        ),
                        fileSystem: SystemSymlinkFileSystem()
                    )
                    return removed.isEmpty
                        ? "no CLI symlink to remove"
                        : "removed \(removed.joined(separator: ", "))"
                } catch {
                    return "symlink removal failed: \(error)"
                }
            }
        ))
    }
}
