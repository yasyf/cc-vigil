import Foundation

public enum ProcArgsParser {
    public static let maxArgc = 4096

    public static func argv(fromProcArgs2 data: Data) -> [String]? {
        let bytes = [UInt8](data)
        guard bytes.count > 4 else { return nil }
        let argc = Int(
            UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        )
        guard argc >= 1, argc <= maxArgc else { return nil }
        guard let execPathEnd = bytes[4...].firstIndex(of: 0) else { return nil }
        var index = execPathEnd
        while index < bytes.count, bytes[index] == 0 {
            index += 1
        }
        var argv: [String] = []
        while argv.count < argc, index < bytes.count {
            guard let end = bytes[index...].firstIndex(of: 0) else { break }
            // swiftlint:disable:next optional_data_string_conversion - deliberate lossy decode of kernel argv bytes
            argv.append(String(decoding: bytes[index ..< end], as: UTF8.self))
            index = end + 1
        }
        guard argv.count == argc else { return nil }
        return argv
    }
}

public enum ClaudeProcessMatcher {
    public static let processName = "claude"

    public static func isClaude(argv: [String]) -> Bool {
        guard let command = argv.first else { return false }
        if basename(command) == processName {
            return true
        }
        guard argv.count >= 2 else { return false }
        let interpreterScript = argv[1]
        return interpreterScript.contains("/") && basename(interpreterScript) == processName
    }

    private static func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
