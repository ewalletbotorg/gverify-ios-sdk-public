import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(DeviceCheck)
import DeviceCheck
#endif

/// Native tamper posture: jailbreak heuristics, emulator/simulator detection,
/// and hardware-attestation availability (DeviceCheck / App Attest). All checks
/// are fail-soft — any failure leaves the corresponding flag nil.
enum TamperCollector {
    static func collect() -> TamperSignals {
        var tamper = TamperSignals(automation_flags: [])
        tamper.is_emulator = isSimulator()
        tamper.is_jailbroken = isJailbroken()
        tamper.remote_desktop_suspected = nil // not detectable on iOS
        tamper.attestation_supported = attestationSupported()
        return tamper
    }

    static func isSimulator() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Heuristic jailbreak detection: suspicious files, a sandbox-write probe,
    /// and a cydia URL-scheme check. Skipped on the simulator.
    static func isJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/usr/bin/ssh"
        ]
        for path in suspiciousPaths where FileManager.default.fileExists(atPath: path) {
            return true
        }

        // Sandbox-write probe: a non-jailbroken app cannot write outside its
        // container.
        let probePath = "/private/jailbreak_probe_\(UUID().uuidString).txt"
        do {
            try "probe".write(toFile: probePath, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: probePath)
            return true
        } catch {
            // expected on a non-jailbroken device
        }

        #if canImport(UIKit)
        if let url = URL(string: "cydia://package/com.example.package"),
           UIApplication.shared.canOpenURL(url) {
            return true
        }
        #endif

        return false
        #endif
    }

    /// Whether hardware attestation is available on this device.
    static func attestationSupported() -> Bool {
        #if canImport(DeviceCheck)
        if #available(iOS 14.0, *) {
            return DCAppAttestService.shared.isSupported
        }
        return DCDevice.current.isSupported
        #else
        return false
        #endif
    }
}
