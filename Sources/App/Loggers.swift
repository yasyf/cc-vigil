import os

extension Logger {
    static let app = Logger(subsystem: "dev.yasyf.cc-vigil", category: "App")
    static let installer = Logger(subsystem: "dev.yasyf.cc-vigil", category: "Installer")
}
