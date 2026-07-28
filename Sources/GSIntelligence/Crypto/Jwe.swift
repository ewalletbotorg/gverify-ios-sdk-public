import Foundation
import CryptoKit
import Security

enum JweError: Error {
    case unknownKid
    case keyImportFailed
    case rsaWrapFailed
    case encodingFailed
}

/// base64url-encode bytes (no padding) — matches the web SDK's `b64url`.
func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// base64url-decode (tolerant of missing padding).
func base64urlDecode(_ string: String) -> Data? {
    var s = string
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    while s.count % 4 != 0 { s += "=" }
    return Data(base64Encoded: s)
}

/// Seal a payload into a compact JWE, byte-compatible with the web SDK's
/// `sealJwe`:
///   BASE64URL(header).BASE64URL(encKey).BASE64URL(iv).BASE64URL(ciphertext).BASE64URL(tag)
/// - CEK: random AES-256-GCM key, wrapped with RSA-OAEP-256.
/// - AAD: the ASCII bytes of the encoded protected header (per RFC 7516).
func sealJwe(_ payload: TokenPayload, kid: String = GSKeys.activeKid) throws -> String {
    guard let jwk = GSKeys.publicKeys[kid] else { throw JweError.unknownKid }

    // Protected header — values must match what `fraud-check` expects.
    let header = "{\"alg\":\"RSA-OAEP-256\",\"enc\":\"A256GCM\",\"kid\":\"\(kid)\",\"typ\":\"GSDS\"}"
    let encodedHeader = base64url(Data(header.utf8))
    let aad = Data(encodedHeader.utf8)

    // Content-encryption key (AES-256-GCM).
    let cek = SymmetricKey(size: .bits256)
    let rawCek = cek.withUnsafeBytes { Data($0) }

    // Wrap the CEK with RSA-OAEP-256.
    let pub = try importRSAPublicKey(n: jwk.n, e: jwk.e)
    let wrapped = try rsaOaepEncrypt(pub, rawCek)

    // Encrypt the plaintext payload (12-byte random IV, 128-bit tag).
    let plaintext = try JSONEncoder().encode(payload)
    let nonce = AES.GCM.Nonce()
    let sealedBox = try AES.GCM.seal(plaintext, using: cek, nonce: nonce, authenticating: aad)

    return [
        encodedHeader,
        base64url(wrapped),
        base64url(Data(nonce)),
        base64url(sealedBox.ciphertext),
        base64url(sealedBox.tag)
    ].joined(separator: ".")
}

/// Unencrypted sandbox payload for `gk_test_` integration — mirrors the web
/// SDK's `gsds_sandbox.<base64(payload)>` format (standard base64, no padding).
func sandboxToken(_ payload: TokenPayload) throws -> String {
    let json = try JSONEncoder().encode(payload)
    let b64 = json.base64EncodedString().replacingOccurrences(of: "=", with: "")
    return "gsds_sandbox.\(b64)"
}

// MARK: - RSA helpers

private func rsaOaepEncrypt(_ key: SecKey, _ data: Data) throws -> Data {
    var error: Unmanaged<CFError>?
    guard let encrypted = SecKeyCreateEncryptedData(
        key, .rsaEncryptionOAEPSHA256, data as CFData, &error
    ) else {
        throw JweError.rsaWrapFailed
    }
    return encrypted as Data
}

/// Build a `SecKey` RSA public key from base64url modulus + exponent by
/// assembling a PKCS#1 `RSAPublicKey` DER (what SecKeyCreateWithData expects).
private func importRSAPublicKey(n nB64: String, e eB64: String) throws -> SecKey {
    guard let nData = base64urlDecode(nB64), let eData = base64urlDecode(eB64) else {
        throw JweError.keyImportFailed
    }
    let der = rsaPkcs1DER(modulus: nData, exponent: eData)
    let attrs: [CFString: Any] = [
        kSecAttrKeyType: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass: kSecAttrKeyClassPublic,
        kSecAttrKeySizeInBits: NSNumber(value: nData.count * 8)
    ]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, &error) else {
        throw JweError.keyImportFailed
    }
    return key
}

// MARK: - Minimal DER encoder (RSAPublicKey)

private func derLength(_ length: Int) -> Data {
    if length < 0x80 { return Data([UInt8(length)]) }
    var len = length
    var bytes: [UInt8] = []
    while len > 0 {
        bytes.insert(UInt8(len & 0xff), at: 0)
        len >>= 8
    }
    return Data([UInt8(0x80 | bytes.count)] + bytes)
}

private func derInteger(_ data: Data) -> Data {
    var bytes = [UInt8](data)
    // Ensure a positive (unsigned) INTEGER: prepend 0x00 if the high bit is set.
    if let first = bytes.first, first & 0x80 != 0 {
        bytes.insert(0x00, at: 0)
    }
    var out = Data([0x02])
    out.append(derLength(bytes.count))
    out.append(contentsOf: bytes)
    return out
}

private func rsaPkcs1DER(modulus: Data, exponent: Data) -> Data {
    let body = derInteger(modulus) + derInteger(exponent)
    var out = Data([0x30])
    out.append(derLength(body.count))
    out.append(body)
    return out
}
