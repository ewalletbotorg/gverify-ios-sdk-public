import Foundation

/// Always-on behavioral capture. Native apps don't expose web-style mouse/
/// keystroke dynamics, so this captures privacy-safe session timing only
/// (no input values), matching the web SDK's "timing metadata only" stance.
final class BehaviorCollector {
    static let shared = BehaviorCollector()

    private var sessionStart: Date?
    private let lock = NSLock()

    func start() {
        lock.lock(); defer { lock.unlock() }
        if sessionStart == nil {
            sessionStart = Date()
        }
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        sessionStart = nil
    }

    func snapshot() -> BehaviorSignals {
        lock.lock(); defer { lock.unlock() }
        var signals = BehaviorSignals()
        if let start = sessionStart {
            signals.session_duration_ms = Int(Date().timeIntervalSince(start) * 1000)
        }
        return signals
    }
}
