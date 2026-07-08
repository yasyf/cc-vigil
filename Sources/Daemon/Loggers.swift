import os

extension Logger {
    static let daemon = Logger(subsystem: "dev.yasyf.cc-vigil", category: "Daemon")
    static let helperClient = Logger(subsystem: "dev.yasyf.cc-vigil", category: "HelperClient")
    static let monitors = Logger(subsystem: "dev.yasyf.cc-vigil", category: "Monitors")
    static let cli = Logger(subsystem: "dev.yasyf.cc-vigil", category: "CLISocket")
}
