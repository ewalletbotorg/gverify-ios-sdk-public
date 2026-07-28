import XCTest
import CryptoKit
@testable import GSIntelligence

final class GSIntelligenceTests: XCTestCase {

    private func samplePayload() -> TokenPayload {
        var device = DeviceSignals()
        device.true_device_id = "11111111-2222-3333-4444-555555555555"
        device.platform = "iOS"
        device.model = "iPhone15,2"

        var tamper = TamperSignals(automation_flags: [])
        tamper.is_emulator = false
        tamper.is_jailbroken = false
        tamper.screen_mirrored = true   // HC136
        tamper.screen_captured = false  // HC138
        tamper.in_call = true           // HC139

        var network = NetworkSignals()
        network.effective_type = "wifi"
        network.vpn_active = true       // HC134
        network.proxy_active = false

        let gps = GpsSignals(latitude: 37.33, longitude: -122.03, accuracy_m: 65, permission_state: "granted")

        let signals = Signals(
            device: device,
            browser: BrowserSignals(),
            tamper: tamper,
            gps: gps,
            network: network,
            storage: StorageSignals(persistent_id_present: true),
            behavior: BehaviorSignals(session_duration_ms: 1200, risk_score: nil),
            email: EmailSignals()
        )

        let iat: Int64 = 1_700_000_000_000
        return TokenPayload(
            v: 1,
            sid: "abc",
            iat: iat,
            exp: iat + 5 * 60 * 1000,
            nonce: "deadbeef",
            collected_at: iat,
            signals: signals
        )
    }

    // MARK: - base64url

    func testBase64UrlRoundTrip() {
        let raw = Data([0xfb, 0xff, 0x00, 0x10, 0x3e, 0x3f])
        let encoded = base64url(raw)
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertEqual(base64urlDecode(encoded), raw)
    }

    // MARK: - JWE structure

    func testSealJweProducesFiveCompactParts() throws {
        let token = try sealJwe(samplePayload())
        let parts = token.split(separator: ".")
        XCTAssertEqual(parts.count, 5, "compact JWE must have 5 segments")
        XCTAssertTrue(parts.allSatisfy { !$0.isEmpty })
    }

    func testJweHeaderMatchesWebFormat() throws {
        let token = try sealJwe(samplePayload())
        let encodedHeader = String(token.split(separator: ".")[0])
        let headerData = try XCTUnwrap(base64urlDecode(encodedHeader))
        let header = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: headerData) as? [String: String]
        )
        XCTAssertEqual(header["alg"], "RSA-OAEP-256")
        XCTAssertEqual(header["enc"], "A256GCM")
        XCTAssertEqual(header["kid"], "v1")
        XCTAssertEqual(header["typ"], "GSDS")
    }

    func testJweIvIsTwelveBytes() throws {
        let token = try sealJwe(samplePayload())
        let ivSegment = String(token.split(separator: ".")[2])
        let iv = try XCTUnwrap(base64urlDecode(ivSegment))
        XCTAssertEqual(iv.count, 12, "AES-GCM IV must be 96 bits")
    }

    func testJweTagIsSixteenBytes() throws {
        let token = try sealJwe(samplePayload())
        let tagSegment = String(token.split(separator: ".")[4])
        let tag = try XCTUnwrap(base64urlDecode(tagSegment))
        XCTAssertEqual(tag.count, 16, "AES-GCM tag must be 128 bits")
    }

    func testWrappedCekMatchesModulusSize() throws {
        let token = try sealJwe(samplePayload())
        let wrappedSegment = String(token.split(separator: ".")[1])
        let wrapped = try XCTUnwrap(base64urlDecode(wrappedSegment))
        // RSA-OAEP output size == modulus size. Active key is RSA-4096.
        let modulus = try XCTUnwrap(base64urlDecode(GSKeys.publicKeys["v1"]!.n))
        XCTAssertEqual(wrapped.count, modulus.count)
    }

    // MARK: - Sandbox

    func testSandboxTokenRoundTrips() throws {
        let payload = samplePayload()
        let token = try sandboxToken(payload)
        XCTAssertTrue(token.hasPrefix("gsds_sandbox."))

        let b64 = String(token.dropFirst("gsds_sandbox.".count))
        let padded = b64 + String(repeating: "=", count: (4 - b64.count % 4) % 4)
        let json = try XCTUnwrap(Data(base64Encoded: padded))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])

        XCTAssertEqual(object["v"] as? Int, 1)
        XCTAssertEqual(object["sid"] as? String, "abc")
        let signals = try XCTUnwrap(object["signals"] as? [String: Any])
        let tamper = try XCTUnwrap(signals["tamper"] as? [String: Any])
        XCTAssertEqual(tamper["screen_mirrored"] as? Bool, true) // HC136
        XCTAssertEqual(tamper["in_call"] as? Bool, true)         // HC139
        let network = try XCTUnwrap(signals["network"] as? [String: Any])
        XCTAssertEqual(network["vpn_active"] as? Bool, true)     // HC134
    }

    // MARK: - Payload shape parity

    func testPayloadHasExpectedTopLevelKeys() throws {
        let json = try JSONEncoder().encode(samplePayload())
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        for key in ["v", "sid", "iat", "exp", "nonce", "collected_at", "signals"] {
            XCTAssertNotNil(object[key], "missing top-level key: \(key)")
        }
        let signals = try XCTUnwrap(object["signals"] as? [String: Any])
        for key in ["device", "browser", "tamper", "gps", "network", "storage", "behavior", "email"] {
            XCTAssertNotNil(signals[key], "missing signals key: \(key)")
        }
    }

    func testNilFieldsAreOmitted() throws {
        // BrowserSignals has all-nil fields → encodes to an empty object.
        let json = try JSONEncoder().encode(BrowserSignals())
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertTrue(object.isEmpty, "nil fields must be omitted (fail-soft)")
    }

    // MARK: - Tamper

    func testSimulatorDetectionOnSimulator() {
        #if targetEnvironment(simulator)
        XCTAssertTrue(TamperCollector.isSimulator())
        XCTAssertFalse(TamperCollector.isJailbroken())
        #else
        XCTAssertFalse(TamperCollector.isSimulator())
        #endif
    }

    func testDeviceModelIdentifierIsNonEmpty() {
        XCTAssertFalse(DeviceCollector.deviceModelIdentifier().isEmpty)
    }
}
