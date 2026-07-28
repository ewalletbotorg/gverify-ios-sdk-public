import Foundation

/// GPS collection mode (mirrors the web SDK's `GpsMode`).
public enum GPSMode: String {
    /// Never touch CoreLocation.
    case off
    /// Use location only if already authorized; never prompt.
    case silent
    /// Prompt for permission if undetermined (default).
    case prompt
    /// Prompt and require a fix; `getSession()` throws `GSError.gpsRequired`
    /// when no coordinates are captured.
    case required
}

/// SDK configuration captured by `GS.configure(...)`.
public struct GSConfig {
    /// Client identifier (used by your backend's API key model; not embedded in
    /// the token — identification happens server-side, exactly like the web SDK).
    public var clientId: String
    /// Optional fresh per-action session id; auto-generated if nil.
    public var sessionId: String?
    public var gps: GPSMode
    public var behavior: Bool
    public var persistence: Bool
    /// Emit an unencrypted sandbox payload (for `gk_test_` keys).
    public var sandbox: Bool
    public var debug: Bool
    /// Max wall-clock time (seconds) collectors may run before sealing.
    public var maxWaitTime: TimeInterval

    public init(
        clientId: String,
        sessionId: String? = nil,
        gps: GPSMode = .prompt,
        behavior: Bool = true,
        persistence: Bool = true,
        sandbox: Bool = false,
        debug: Bool = false,
        maxWaitTime: TimeInterval = 4.0
    ) {
        self.clientId = clientId
        self.sessionId = sessionId
        self.gps = gps
        self.behavior = behavior
        self.persistence = persistence
        self.sandbox = sandbox
        self.debug = debug
        self.maxWaitTime = maxWaitTime
    }
}

/// Errors surfaced by the public API.
public enum GSError: Error {
    /// `getSession()` called before `GS.configure(...)`.
    case notConfigured
    /// `gps: .required` but no coordinates were captured.
    case gpsRequired(permissionState: String?)
    /// Token sealing failed.
    case sealFailed(underlying: Error)
}
