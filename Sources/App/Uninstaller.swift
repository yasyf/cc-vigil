import CCVigilAppKit
import CCVigilCLIKit
import CCVigilShared
import CCVigilTransport
import Foundation

enum Uninstaller {
    static func run(registrar: ServiceRegistrar, commands: DaemonCommands) async -> [String] {
        await UninstallSequence.run(UninstallSteps(
            uninstallHooks: {
                let hooks = await BundledCLI.run(["uninstall-hooks"])
                return hooks.status == 0 ? hooks.output : "uninstall-hooks failed: \(hooks.output)"
            },
            clearSleepBlock: {
                await ConfirmedClear(
                    attemptClear: {
                        do {
                            if case .ok = try await commands.roundTrip(.clear) {
                                return .confirmed
                            }
                            return .wedged
                        } catch let error as DaemonClientError {
                            if case .timedOut = error {
                                return .timedOut
                            }
                            return .unreachable
                        } catch {
                            return .unreachable
                        }
                    },
                    pollBlockCleared: {
                        guard case let .status(report) = try? await commands.roundTrip(.status) else {
                            return false
                        }
                        return !report.blockApplied
                    }
                ).run()
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
