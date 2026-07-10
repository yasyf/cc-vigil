import CCVigilAppKit
import CCVigilShared
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @State private var confirmingUninstall = false

    var body: some View {
        Form {
            Section("Cutouts") {
                batterySlider
                thermalSlider
                Toggle("Cut out in Low Power Mode", isOn: lowPowerCutout)
            }
            Section("Oracle") {
                activityStepper
            }
            Section("Notifications") {
                Toggle("Notify when agents finish", isOn: notifyOnRelease)
                Toggle("Notify when a cutout drops protection", isOn: notifyOnCutout)
            }
            Section("App") {
                Toggle("Hide menu bar icon", isOn: hideMenuBar)
                Toggle("Launch at login", isOn: launchAtLogin)
                Button("Open Events Log") {
                    model.openEventsLog()
                }
            }
            Section("Maintenance") {
                Button("Repair Background Services") {
                    model.repairServices()
                }
                Button("Uninstall…", role: .destructive) {
                    confirmingUninstall = true
                }
                if let message = model.maintenanceMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear {
            model.refreshLaunchAtLogin()
        }
        .confirmationDialog("Uninstall cc-vigil?", isPresented: $confirmingUninstall) {
            Button("Uninstall", role: .destructive) {
                model.uninstall()
            }
        } message: {
            Text("Removes the Claude Code hooks, background services, and the CLI symlink.")
        }
    }

    private var batterySlider: some View {
        Slider(
            value: Binding(
                get: { Double(model.config.batteryFloorPercent) },
                set: { model.setBatteryFloor(Int($0.rounded())) }
            ),
            in: Double(VigilConfig.batteryFloorPercentRange.lowerBound)
                ... Double(VigilConfig.batteryFloorPercentRange.upperBound),
            step: 1
        ) {
            Text("Battery floor: \(model.config.batteryFloorPercent)%")
        }
    }

    private var thermalSlider: some View {
        Slider(
            value: Binding(
                get: { model.config.thermalCutoutCelsius },
                set: { model.setThermalCutout($0.rounded()) }
            ),
            in: VigilConfig.thermalCutoutCelsiusRange,
            step: 1
        ) {
            Text("Thermal cutout: \(Int(model.config.thermalCutoutCelsius))°C")
        }
    }

    private var activityStepper: some View {
        Stepper(
            value: Binding(
                get: { model.config.activityWindowSeconds / 60 },
                set: { model.setActivityWindow(minutes: $0) }
            ),
            in: 1 ... 120
        ) {
            Text("Activity window: \(model.config.activityWindowSeconds / 60) min")
        }
    }

    private var hideMenuBar: Binding<Bool> {
        Binding(
            get: { model.config.hideMenuBarExtra },
            set: { model.setHideMenuBarExtra($0) }
        )
    }

    private var lowPowerCutout: Binding<Bool> {
        Binding(
            get: { model.config.lowPowerCutout },
            set: { model.setLowPowerCutout($0) }
        )
    }

    private var notifyOnRelease: Binding<Bool> {
        Binding(
            get: { model.config.notifyOnRelease },
            set: { model.setNotifyOnRelease($0) }
        )
    }

    private var notifyOnCutout: Binding<Bool> {
        Binding(
            get: { model.config.notifyOnCutout },
            set: { model.setNotifyOnCutout($0) }
        )
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )
    }
}
