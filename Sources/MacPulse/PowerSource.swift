import Foundation
import IOKit.ps

/// Reads whether the Mac is currently running on battery. Desktops with no
/// battery always report false (the providing source is "AC Power").
enum PowerSource {
    static var onBattery: Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeRetainedValue() as String?
        else { return false }
        return type == kIOPSBatteryPowerValue
    }
}
