import CCVigilAppKit
import Foundation
import ServiceManagement

/// The SMAppService edge: registration, status, and login-item control for
/// the bundled LaunchAgent, LaunchDaemon, and the app itself.
struct ServiceRegistrar {
    func register(_ service: ManagedService) -> RegistrationOutcome {
        let appService = Self.appService(service)
        do {
            try appService.register()
            return .registered
        } catch {
            return Self.classify(error, status: appService.status)
        }
    }

    func reregister(_ service: ManagedService) -> RegistrationOutcome {
        let appService = Self.appService(service)
        try? appService.unregister()
        do {
            try appService.register()
            return .registered
        } catch {
            return Self.classify(error, status: appService.status)
        }
    }

    func statuses() -> [ManagedService: ServiceStatus] {
        Dictionary(uniqueKeysWithValues: ManagedService.allCases.map {
            ($0, Self.status(of: Self.appService($0)))
        })
    }

    func repair() -> [String] {
        ManagedService.allCases.map { service in
            switch reregister(service) {
            case .registered: "\(service.rawValue): registered"
            case .notPermitted: "\(service.rawValue): not permitted"
            case let .failed(message): "\(service.rawValue): \(message)"
            }
        }
    }

    func unregisterAll() -> [String] {
        var lines: [String] = []
        for service in ManagedService.allCases {
            do {
                try Self.appService(service).unregister()
                lines.append("unregistered \(service.rawValue)")
            } catch {
                lines.append("\(service.rawValue): \(error.localizedDescription)")
            }
        }
        if SMAppService.mainApp.status == .enabled {
            do {
                try SMAppService.mainApp.unregister()
                lines.append("removed the login item")
            } catch {
                lines.append("login item: \(error.localizedDescription)")
            }
        }
        return lines
    }

    var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func appService(_ service: ManagedService) -> SMAppService {
        switch service {
        case .daemonAgent: SMAppService.agent(plistName: service.rawValue)
        case .helperDaemon: SMAppService.daemon(plistName: service.rawValue)
        }
    }

    private static func classify(_ error: Error, status: SMAppService.Status) -> RegistrationOutcome {
        if status == .enabled || status == .requiresApproval {
            return .registered
        }
        let nsError = error as NSError
        let permissionCode = nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EPERM)
        let permissionText = nsError.localizedDescription
            .localizedCaseInsensitiveContains("operation not permitted")
        if permissionCode || permissionText {
            return .notPermitted
        }
        return .failed(nsError.localizedDescription)
    }

    private static func status(of appService: SMAppService) -> ServiceStatus {
        switch appService.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .notRegistered: .notRegistered
        @unknown default: .notRegistered
        }
    }
}
