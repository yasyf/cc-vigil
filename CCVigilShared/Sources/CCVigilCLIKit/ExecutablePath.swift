import Darwin
import Foundation

public enum ExecutablePathError: Error, CustomStringConvertible {
    case unresolvable

    public var description: String {
        "cannot resolve the running executable's path"
    }
}

public enum ExecutablePath {
    /// The real on-disk path of the running binary: symlinks resolved so the
    /// installed hook command always points into the app bundle, never at a
    /// symlink that may later dangle.
    public static func resolved() throws -> String {
        var capacity = UInt32(0)
        _NSGetExecutablePath(nil, &capacity)
        var buffer = [CChar](repeating: 0, count: Int(capacity))
        guard _NSGetExecutablePath(&buffer, &capacity) == 0 else {
            throw ExecutablePathError.unresolvable
        }
        let pathBytes = buffer.prefix(while: { $0 != 0 }).map(UInt8.init(bitPattern:))
        // swiftlint:disable:next optional_data_string_conversion - POSIX paths are raw bytes
        return URL(fileURLWithPath: String(decoding: pathBytes, as: UTF8.self))
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}
