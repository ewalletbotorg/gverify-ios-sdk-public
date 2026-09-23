import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Collects stable device, locale, and screen signals from native APIs.
enum DeviceCollector {
    static func collect(trueDeviceId: String) -> DeviceSignals {
        let tz = TimeZone.current
        let locale = Locale.current
        let info = ProcessInfo.processInfo

        // Memory in GB (rounded), processor count.
        let memoryGB = Double(info.physicalMemory) / 1_073_741_824.0
        let cores = info.activeProcessorCount

        // Preferred languages as BCP-47 tags.
        let languages = Locale.preferredLanguages

        let bcp47: String? = {
            if #available(iOS 16, *) {
                return locale.identifier(.bcp47)
            }
            return locale.identifier.replacingOccurrences(of: "_", with: "-")
        }()

        var device = DeviceSignals()
        device.true_device_id = trueDeviceId
        device.platform = "iOS"
        device.vendor = "Apple"
        device.model = deviceModelIdentifier()
        device.timezone = tz.identifier
        device.timezone_offset = -tz.secondsFromGMT() / 60 // JS getTimezoneOffset() semantics
        device.languages = languages.isEmpty ? nil : languages
        device.locale = bcp47
        device.timezone_country = locale.regionCode
        device.device_memory = (memoryGB * 100).rounded() / 100
        device.hardware_concurrency = cores
        device.touch_support = true

        #if canImport(UIKit)
        device.device_hash = UIDevice.current.identifierForVendor?.uuidString.lowercased()
        let osVersion = UIDevice.current.systemVersion
        let screen = UIScreen.main
        let native = screen.nativeBounds
        var screenSignals = ScreenSignals()
        screenSignals.width = Int(native.width)
        screenSignals.height = Int(native.height)
        screenSignals.pixel_ratio = Double(screen.scale)
        if #available(iOS 10.3, *) {
            screenSignals.refresh_rate = Double(screen.maximumFramesPerSecond)
        }
        screenSignals.is_extended = UIScreen.screens.count > 1
        let pointBounds = screen.bounds
        screenSignals.available_width = Int(pointBounds.width)
        screenSignals.available_height = Int(pointBounds.height)
        device.screen = screenSignals
        device.user_agent_data = UserAgentData(
            platform: "iOS",
            platform_version: osVersion,
            model: deviceModelIdentifier(),
            mobile: true
        )
        #endif

        return device
    }

    /// Hardware model identifier, e.g. "iPhone15,2".
    static func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
    }
}
