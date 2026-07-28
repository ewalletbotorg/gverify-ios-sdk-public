import Foundation

/// Bundled public keys, indexed by `kid`. The SDK encrypts the device token's
/// content-encryption key (CEK) with one of these RSA-OAEP-256 public keys.
/// The matching private key lives only in the GS edge environment
/// (`DEVICE_TOKEN_PRIVATE_KEY_<KID>` secret) and is never shipped to the app.
///
/// IMPORTANT: `n`/`e` and `ACTIVE_KID` MUST stay byte-for-byte identical to
/// `packages/gs-web-sdk/src/keys.ts` so a token sealed by this iOS SDK decrypts
/// with the exact same private key the web SDK's tokens use. During a rotation,
/// add the new `kid` here while keeping the previous one.
struct PublicJwk {
    let kty: String
    /// base64url-encoded RSA modulus.
    let n: String
    /// base64url-encoded RSA public exponent.
    let e: String
}

enum GSKeys {
    static let activeKid = "v1"

    static let publicKeys: [String: PublicJwk] = [
        "v1": PublicJwk(
            kty: "RSA",
            n: "iudSshKiZs1hF1f3KvvoOU15MtR4iVuHHLQ1dx3wvWUbZYfSvbkRrV7WJe3lH3xcMWyiC2WIi7O9Remwr3qWI50RWBVEKNr9uLBCZUmZyPKCnGA6o3-Lm-BYjqpT8LO5QtS0G2jljX3DnOBHz0WDG56oE2g1u2nby_QyIpK_VdNLRq2xDx13_uYtIvQ5hZOu4-_5UQrXdU3IugmOVu7-YOpKoDwb3DjJyJ98iBNfqEi-WCfzw9CyURpY9i19sj0GHFQwxD7JqT7VpKJCIbGS0FTk7ZZe9XMPpABdVe3eR0FoOaEB5i7SHgtznJnkdjPiPb896rQS6CmCvubZ-iHrUGL4fky5Q5SIgYYkXofQN3qayei59h5clBSfkVM69fFQiK0swNAHF2FBAH-ZEardlF897c1uf8W8KsAbMKk5jgy_bZosZgf85GdOsRs-8uCqgO_fXELHj5Eb9-UtueE2LwDrOCwTsK1Ib_QlINotoXsClTk1MQiRGaEvV_fPyLLG5Ytrw82GIubqz2cZunr8h-yxVUv7Hq51Vnp3hUA3__mVt4TWsiImIdiCo6S6TS5T2FqBOOsNUdYmYpoutq_5aMm4byx0TNVDGf_5lKPN3ldllikM5TJ4Wr3yKLg1Oj_pbrMvIeCwnRIJwWUwmgzW2l1LOctK1kpf2hGJRkUF7pE",
            e: "AQAB"
        )
    ]
}
