import Foundation

/// GS Intelligence — native iOS SDK.
///
/// Two-step integration:
/// ```swift
/// GS.configure(clientId: "YOUR_CLIENT_ID")          // once, at app start
/// let session = try await GS.getSession()           // per protected action
/// // send `session` to YOUR backend → forwards to /fraud-check
/// ```
///
/// `getSession()` collects native device, network, GPS, behavior, tamper, and
/// device-environment signals in parallel under a wall-clock budget, then seals
/// them into a compact JWE that `fraud-check` decrypts with the existing private
/// key — the token format is identical to the web SDK's, so no backend change
/// is required.
public enum GS {
    private static let stateLock = NSLock()
    private static var config: GSConfig?
    private static var lastGps: GpsSignals?

    /// 5-minute token TTL — must mirror `_shared/device-token.ts`.
    private static let ttlMillis: Int64 = 5 * 60 * 1000
    private static let gpsPromptTimeout: TimeInterval = 15.0

    // MARK: - Public API

    /// Configure the SDK once (typically in `application(_:didFinishLaunching…)`).
    public static func configure(
        clientId: String,
        gps: GPSMode = .prompt,
        behavior: Bool = true,
        persistence: Bool = true,
        sandbox: Bool = false,
        debug: Bool = false,
        sessionId: String? = nil,
        maxWaitTime: TimeInterval = 4.0
    ) {
        let cfg = GSConfig(
            clientId: clientId,
            sessionId: sessionId,
            gps: gps,
            behavior: behavior,
            persistence: persistence,
            sandbox: sandbox,
            debug: debug,
            maxWaitTime: maxWaitTime
        )
        configure(cfg)
    }

    /// Configure with a fully-built `GSConfig`.
    public static func configure(_ cfg: GSConfig) {
        stateLock.lock()
        config = cfg
        stateLock.unlock()

        if cfg.behavior {
            BehaviorCollector.shared.start()
        } else {
            BehaviorCollector.shared.stop()
        }
        log("configured: client=\(cfg.clientId) gps=\(cfg.gps.rawValue) sandbox=\(cfg.sandbox)")
    }

    /// Build a fresh, single-use session token. Generate one per protected
    /// user-action (login, checkout, signup). Tokens are one-time and expire in
    /// 5 minutes.
    public static func getSession() async throws -> String {
        guard let cfg = currentConfig() else { throw GSError.notConfigured }

        let iat = epochMillis()
        let signals = await collectSignals(cfg)

        if cfg.gps == .required, signals.gps.latitude == nil || signals.gps.longitude == nil {
            throw GSError.gpsRequired(permissionState: signals.gps.permission_state)
        }

        let payload = TokenPayload(
            v: 1,
            sid: cfg.sessionId ?? GSRandom.uuid(),
            iat: iat,
            exp: iat + ttlMillis,
            nonce: GSRandom.randomHex(16),
            collected_at: iat,
            signals: signals
        )

        if cfg.sandbox {
            log("sandbox mode — returning unencrypted payload")
            do {
                return try sandboxToken(payload)
            } catch {
                throw GSError.sealFailed(underlying: error)
            }
        }

        do {
            return try sealJwe(payload, kid: GSKeys.activeKid)
        } catch {
            throw GSError.sealFailed(underlying: error)
        }
    }

    /// The persistent device identity, without building a full token.
    public static func getDeviceId() -> String {
        let persist = currentConfig()?.persistence ?? true
        return Persistence.trueDeviceId(persist: persist).id
    }

    /// The last GPS block captured by `getSession()` — useful for diagnostics.
    public static func getLastGps() -> GpsSignals? {
        stateLock.lock(); defer { stateLock.unlock() }
        return lastGps
    }

    // MARK: - Orchestration

    private static func collectSignals(_ cfg: GSConfig) async -> Signals {
        let budget = cfg.maxWaitTime
        let persisted = Persistence.trueDeviceId(persist: cfg.persistence)

        let gpsBudget: TimeInterval = (cfg.gps == .prompt || cfg.gps == .required)
            ? max(budget, gpsPromptTimeout)
            : min(budget, 3.0)

        // Run independent collectors concurrently under their own budgets.
        async let deviceTask = withTimeout(budget, fallback: DeviceSignals()) {
            DeviceCollector.collect(trueDeviceId: persisted.id)
        }
        async let networkTask = withTimeout(min(budget, 2.5), fallback: NetworkSignals()) {
            NetworkCollector.collect(timeout: min(budget, 2.5))
        }
        async let tamperTask = withTimeout(budget, fallback: TamperSignals(automation_flags: [])) {
            TamperCollector.collect()
        }
        async let environmentTask = withTimeout(budget, fallback: EnvironmentCollector.Result()) {
            await MainActor.run { EnvironmentCollector.collect() }
        }
        async let gpsTask: GpsSignals = withTimeout(gpsBudget + 0.25, fallback: GpsSignals(permission_state: "timeout")) {
            let collector = GpsCollector()
            collector.debug = cfg.debug
            return await collector.collect(mode: cfg.gps, timeout: gpsBudget)
        }

        var device = await deviceTask
        let network = await networkTask
        var tamper = await tamperTask
        let environment = await environmentTask
        let gps = await gpsTask

        // Merge environment posture into the tamper block (where backend slots
        // exist) so HC136/HC138/HC139 resolve from a single security envelope.
        tamper.screen_mirrored = environment.externalDisplay   // HC136
        tamper.screen_captured = environment.screenCaptured    // HC138
        tamper.in_call = environment.inCall                    // HC139

        // Spoofing posture summary hash (mirrors the web SDK's spoofing_hash).
        device.spoofing_hash = spoofingHash(tamper)

        let storage = StorageSignals(persistent_id_present: persisted.present)
        let behavior = cfg.behavior ? BehaviorCollector.shared.snapshot() : BehaviorSignals()

        let signals = Signals(
            device: device,
            browser: BrowserSignals(),
            tamper: tamper,
            gps: gps,
            network: network,
            storage: storage,
            behavior: behavior,
            email: EmailSignals()
        )

        stateLock.lock()
        lastGps = gps
        stateLock.unlock()

        return signals
    }

    /// Compact, stable hash of the tamper posture.
    private static func spoofingHash(_ tamper: TamperSignals) -> String {
        let parts = [
            tamper.is_emulator.map { String($0) } ?? "-",
            tamper.is_jailbroken.map { String($0) } ?? "-",
            tamper.screen_mirrored.map { String($0) } ?? "-",
            tamper.screen_captured.map { String($0) } ?? "-",
            tamper.in_call.map { String($0) } ?? "-",
            tamper.attestation_supported.map { String($0) } ?? "-"
        ].joined(separator: "|")
        return String(GSRandom.sha256Hex(parts).prefix(32))
    }

    // MARK: - Helpers

    private static func currentConfig() -> GSConfig? {
        stateLock.lock(); defer { stateLock.unlock() }
        return config
    }

    private static func log(_ message: String) {
        guard currentConfig()?.debug == true else { return }
        print("[gs] \(message)")
    }
}
