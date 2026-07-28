import Foundation
import CryptoKit

/// Random + identity helpers (mirror the web SDK's `util/sha256.ts`).
enum GSRandom {
    static func uuid() -> String {
        UUID().uuidString.lowercased()
    }

    static func randomHex(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, bytes, ptr.baseAddress!)
        }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Run an async operation under a hard wall-clock budget. Returns `fallback`
/// if the operation does not complete within `seconds` (fail-soft parity with
/// the web SDK's `safe()` wrapper).
func withTimeout<T>(_ seconds: TimeInterval, fallback: T, _ operation: @escaping () async -> T) async -> T {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result ?? fallback
    }
}

/// Current epoch milliseconds (matches JS `Date.now()`).
func epochMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}
