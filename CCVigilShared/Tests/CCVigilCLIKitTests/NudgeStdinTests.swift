import CCVigilCLIKit
import Foundation
import Testing

private func stdin(bytes: Int) throws -> FileHandle {
    let pipe = Pipe()
    try pipe.fileHandleForWriting.write(contentsOf: Data(repeating: 0x61, count: bytes))
    try pipe.fileHandleForWriting.close()
    return pipe.fileHandleForReading
}

@Test(arguments: [0, 1, 16])
func readsStdinUpToTheLimit(bytes: Int) throws {
    let data = try NudgeStdin.read(from: stdin(bytes: bytes), limit: 16)
    #expect(data == Data(repeating: 0x61, count: bytes))
}

@Test(arguments: [17, 64, 4096])
func rejectsStdinAboveTheLimit(bytes: Int) throws {
    let handle = try stdin(bytes: bytes)
    #expect(throws: NudgeStdinError.oversized(limit: 16)) {
        try NudgeStdin.read(from: handle, limit: 16)
    }
}
