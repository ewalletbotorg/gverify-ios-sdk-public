import Foundation
import CoreLocation

/// Consent-gated GPS collection via CoreLocation. Requests "when in use"
/// authorization when undetermined (unless mode is `.off`/`.silent`), then
/// resolves a single fix under a wall-clock budget. Always fail-soft: on denial
/// or timeout, coordinates are nil and `permission_state` reports why.
///
/// Reliability: once authorized we kick off BOTH a one-shot `requestLocation()`
/// and continuous `startUpdatingLocation()`. The Simulator (and cold starts on
/// device) frequently drop the one-shot fix, so the live stream is the fallback
/// that actually delivers `didUpdateLocations`. Whichever arrives first wins,
/// then we stop updating so we don't keep tracking after the token is sealed.
final class GpsCollector: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<GpsSignals, Never>?
    private var mode: GPSMode = .prompt
    private var finished = false
    private var liveUpdating = false

    /// When `true`, emit `[gs] gps: …` lines via `print` for Xcode console
    /// debugging. Wired from `GSConfig.debug`.
    var debug = false

    /// Resolve a GPS block. `timeout` bounds the entire prompt + fix wait.
    func collect(mode: GPSMode, timeout: TimeInterval) async -> GpsSignals {
        // Reset per-collection state so repeated calls behave correctly.
        self.mode = mode
        self.finished = false
        self.liveUpdating = false
        self.continuation = nil

        if mode == .off {
            return GpsSignals(permission_state: "unavailable")
        }

        let status = currentStatus()
        log("collect mode=\(mode.rawValue) status=\(describe(status)) timeout=\(timeout)")

        // Silent mode never prompts.
        if mode == .silent, status == .notDetermined {
            return GpsSignals(permission_state: "prompt")
        }

        if status == .denied || status == .restricted {
            return GpsSignals(permission_state: "denied")
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<GpsSignals, Never>) in
            self.continuation = cont
            DispatchQueue.main.async {
                self.manager.delegate = self
                self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

                if self.currentStatus() == .notDetermined {
                    self.log("requesting when-in-use authorization")
                    self.manager.requestWhenInUseAuthorization()
                } else {
                    self.startResolving()
                }
            }

            // Cached-location fallback. The Simulator (and device cold starts)
            // frequently never fire `didUpdateLocations`, yet `manager.location`
            // already holds the selected/last coordinate. Poll it a few times
            // across the budget so we don't time out when a fix is sitting right
            // there. The delegate callbacks still win the race when they arrive.
            let pollInterval = max(0.4, min(1.0, timeout / 6))
            for tick in 1...5 {
                let delay = pollInterval * Double(tick)
                guard delay < timeout else { break }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.tryCachedLocation()
                }
            }

            // Hard timeout guard. Make one last cached-location attempt before
            // giving up so a late-but-present coordinate still resolves.
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if self.tryCachedLocation(reason: "timeout-final") { return }
                self.log("timed out waiting for a fix")
                self.finish(GpsSignals(permission_state: "timeout"))
            }
        }
    }

    /// Kick off both a one-shot request and a continuous stream. Whichever
    /// delivers `didUpdateLocations` first resolves the continuation.
    private func startResolving() {
        log("starting requestLocation + startUpdatingLocation")
        manager.requestLocation()
        if !liveUpdating {
            liveUpdating = true
            manager.startUpdatingLocation()
        }
        // Some Simulator configurations already have a coordinate available
        // immediately — grab it without waiting for the first poll tick.
        _ = tryCachedLocation(reason: "immediate")
    }

    /// If `CLLocationManager.location` already holds a usable coordinate,
    /// resolve with it. Returns `true` when it finished the collection.
    @discardableResult
    private func tryCachedLocation(reason: String = "poll") -> Bool {
        guard !finished else { return false }
        guard let loc = manager.location else {
            log("\(reason): manager.location is nil")
            return false
        }
        // Reject obviously invalid coordinates (0,0 / negative accuracy).
        guard CLLocationCoordinate2DIsValid(loc.coordinate),
              loc.horizontalAccuracy >= 0,
              !(loc.coordinate.latitude == 0 && loc.coordinate.longitude == 0) else {
            log("\(reason): manager.location invalid")
            return false
        }
        let age = -loc.timestamp.timeIntervalSinceNow
        log("\(reason): using manager.location fallback lat=\(loc.coordinate.latitude) lon=\(loc.coordinate.longitude) age=\(String(format: "%.1f", age))")
        finish(GpsSignals(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            accuracy_m: loc.horizontalAccuracy,
            permission_state: "granted"
        ))
        return true
    }

    private func currentStatus() -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return manager.authorizationStatus
        }
        return CLLocationManager.authorizationStatus()
    }

    private func finish(_ signals: GpsSignals) {
        guard !finished else { return }
        finished = true
        if liveUpdating {
            liveUpdating = false
            manager.stopUpdatingLocation()
        }
        let cont = continuation
        continuation = nil
        manager.delegate = nil
        log("finish state=\(signals.permission_state ?? "nil") lat=\(signals.latitude.map { String($0) } ?? "nil")")
        cont?.resume(returning: signals)
    }

    // MARK: - CLLocationManagerDelegate

    @available(iOS 14.0, *)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        log("authorization changed → \(describe(manager.authorizationStatus))")
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startResolving()
        case .denied, .restricted:
            finish(GpsSignals(permission_state: "denied"))
        case .notDetermined:
            break
        @unknown default:
            finish(GpsSignals(permission_state: "unavailable"))
        }
    }

    // iOS < 14 authorization callback.
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if #available(iOS 14.0, *) { return } // handled above
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            startResolving()
        case .denied, .restricted:
            finish(GpsSignals(permission_state: "denied"))
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else {
            log("didUpdateLocations with empty array")
            finish(GpsSignals(permission_state: "unavailable"))
            return
        }
        log("got fix lat=\(loc.coordinate.latitude) lon=\(loc.coordinate.longitude) acc=\(loc.horizontalAccuracy)")
        finish(GpsSignals(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            accuracy_m: loc.horizontalAccuracy,
            permission_state: "granted"
        ))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A one-shot `requestLocation()` failure is non-fatal while the live
        // stream may still deliver a fix — let the timeout guard decide unless
        // the stream isn't running.
        log("didFailWithError: \(error.localizedDescription)")
        if !liveUpdating {
            finish(GpsSignals(permission_state: "unavailable"))
        }
    }

    // MARK: - Debug helpers

    private func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        @unknown default: return "unknown"
        }
    }

    private func log(_ message: String) {
        guard debug else { return }
        print("[gs] gps: \(message)")
    }
}
