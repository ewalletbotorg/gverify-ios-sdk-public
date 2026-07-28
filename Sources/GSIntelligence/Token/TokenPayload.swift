import Foundation

/// Encodable mirror of the web SDK's `Signals` envelope
/// (`packages/gs-web-sdk/src/types.ts`). Field names are snake_case so the
/// sealed JSON matches the shape `fraud-check` / `_shared/device-signals.ts`
/// already decrypt and consume — no backend change is required.
///
/// All fields are optional and omitted when nil (fail-soft). Native-only
/// signals fill existing tamper/device/network slots where they exist; signals
/// with no current backend slot are additive and ignored until mapped.

// MARK: - Device

struct ScreenSignals: Encodable {
    var width: Int?
    var height: Int?
    var color_depth: Int?
    var pixel_ratio: Double?
    var refresh_rate: Double?
    var is_extended: Bool?
    var available_width: Int?
    var available_height: Int?
    var orientation_type: String?
    var orientation_angle: Int?
}

/// High-entropy "UA-Client-Hints" analog. `platform_version` is surfaced by the
/// backend mapper as `device_info.os_version`, so populating it lets
/// `device.os_version` rules resolve identically to the web path.
struct UserAgentData: Encodable {
    var platform: String?
    var platform_version: String?
    var model: String?
    var mobile: Bool?
}

struct DeviceSignals: Encodable {
    /// IDFV (identifierForVendor) — stable per vendor, resets on full uninstall.
    var device_hash: String?
    /// Keychain-persisted UUID — survives reinstall; primary `deviceFingerprint`.
    var true_device_id: String?
    var browser_hash: String?
    var platform: String?
    var vendor: String?
    var model: String?
    var timezone: String?
    var timezone_offset: Int?
    var languages: [String]?
    var locale: String?
    var timezone_country: String?
    var device_memory: Double?
    var hardware_concurrency: Int?
    var touch_support: Bool?
    var screen: ScreenSignals?
    var user_agent_data: UserAgentData?
    /// Set after tamper collection (matches web's spoofing_hash merge).
    var spoofing_hash: String?
}

// MARK: - Browser (no native analog; sent null for parity)

struct BrowserSignals: Encodable {
    var user_agent: String?
    var browser_name: String?
    var browser_version: String?
    var spoofing_detected: Bool?
}

// MARK: - Tamper / environment posture

struct TamperSignals: Encodable {
    var is_emulator: Bool?
    /// Native addition: jailbreak heuristics.
    var is_jailbroken: Bool?
    /// HC136 — external/mirrored display present (existing backend slot).
    var screen_mirrored: Bool?
    /// HC138 — screen recording/capture active (additive).
    var screen_captured: Bool?
    /// HC139 — an active phone call during the transaction (additive).
    var in_call: Bool?
    /// HC137 — not detectable on iOS; always null here.
    var remote_desktop_suspected: Bool?
    /// DeviceCheck / App Attest availability (hardware attestation support).
    var attestation_supported: Bool?
    var automation_flags: [String]
}

// MARK: - GPS

public struct GpsSignals: Encodable {
    public var latitude: Double?
    public var longitude: Double?
    public var accuracy_m: Double?
    /// "granted" | "denied" | "prompt" | "unavailable" | "timeout"
    public var permission_state: String?

    public init(
        latitude: Double? = nil,
        longitude: Double? = nil,
        accuracy_m: Double? = nil,
        permission_state: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy_m = accuracy_m
        self.permission_state = permission_state
    }
}

// MARK: - Network

struct NetworkSignals: Encodable {
    var effective_type: String?
    /// HC134 — VPN tunnel interface detected (additive).
    var vpn_active: Bool?
    /// HC134 — system HTTP/HTTPS proxy configured (additive).
    var proxy_active: Bool?
    var is_expensive: Bool?
    var is_constrained: Bool?
}

// MARK: - Storage

struct StorageSignals: Encodable {
    var persistent_id_present: Bool?
}

// MARK: - Behavior

struct BehaviorSignals: Encodable {
    var session_duration_ms: Int?
    var risk_score: Double?
}

// MARK: - Email hint

struct EmailSignals: Encodable {
    var address: String?
}

// MARK: - Envelope

struct Signals: Encodable {
    var device: DeviceSignals
    var browser: BrowserSignals
    var tamper: TamperSignals
    var gps: GpsSignals
    var network: NetworkSignals
    var storage: StorageSignals
    var behavior: BehaviorSignals
    var email: EmailSignals
}

/// Top-level sealed payload. Shape matches the web SDK's `TokenPayload`
/// (`v`, `sid`, `iat`, `exp`, `nonce`, `collected_at`, `signals`). `iat`/`exp`
/// are epoch milliseconds; TTL is 5 minutes (mirrors `_shared/device-token.ts`).
struct TokenPayload: Encodable {
    let v: Int
    let sid: String
    let iat: Int64
    let exp: Int64
    let nonce: String
    let collected_at: Int64
    let signals: Signals
}
