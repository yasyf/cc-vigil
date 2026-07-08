import CCVigilShared
import Darwin
import Foundation

public enum ProcessFacts {
    public static func bootedAt() -> Date {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boottime, &size, nil, 0) == 0 else {
            fatalError("sysctl kern.boottime failed: errno \(errno)")
        }
        return Date(timeIntervalSince1970: Double(boottime.tv_sec) + Double(boottime.tv_usec) / 1e6)
    }

    public static func processStart(pid: Int32) -> Date? {
        guard let info = processInfo(pid: pid) else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1e6)
    }

    public static func parentPid(of pid: Int32) -> Int32? {
        processInfo(pid: pid)?.kp_eproc.e_ppid
    }

    public static func userPids() -> [Int32] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: getuid())]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let capacity = size / MemoryLayout<kinfo_proc>.stride + 8
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        var bufferSize = capacity * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &buffer, &bufferSize, nil, 0) == 0 else { return [] }
        return buffer.prefix(bufferSize / MemoryLayout<kinfo_proc>.stride).map(\.kp_proc.p_pid)
    }

    public static func argv(pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return ProcArgsParser.argv(fromProcArgs2: Data(buffer.prefix(size)))
    }

    private static func processInfo(pid: Int32) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else {
            return nil
        }
        return info
    }
}
