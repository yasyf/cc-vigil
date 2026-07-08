import CCVigilAppKit
import Foundation

enum Uninstaller {
    static func run(registrar: ServiceRegistrar) async -> [String] {
        var lines: [String] = []
        let hooks = await BundledCLI.run(["uninstall-hooks"])
        lines.append(hooks.status == 0 ? hooks.output : "uninstall-hooks failed: \(hooks.output)")
        let unregistered = await Task.detached(priority: .userInitiated) {
            registrar.unregisterAll()
        }.value
        lines.append(contentsOf: unregistered)
        do {
            let removed = try CLISymlinker.removeLinks(
                pointingInto: Bundle.main.bundlePath,
                directories: CLISymlinker.defaultDirectories(
                    home: FileManager.default.homeDirectoryForCurrentUser
                ),
                fileSystem: SystemSymlinkFileSystem()
            )
            lines.append(removed.isEmpty
                ? "no CLI symlink to remove"
                : "removed \(removed.joined(separator: ", "))")
        } catch {
            lines.append("symlink removal failed: \(error)")
        }
        return lines
    }
}
