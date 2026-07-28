# GS Intelligence — iOS SDK

GS Intelligence helps you stop fraudsters from abusing your iOS app while giving
you rich insight into every customer who uses it. By collecting device, network,
location, behavioral, and tamper signals, the SDK helps you defend against
account takeovers, multiple-account signups, and fraudulent payments.

Each call returns a single-use, 5-minute sealed token (a JWE) that your backend
forwards to GS for scoring. The token format is identical to the GS web SDK's, so
your existing fraud-check endpoint works with **no backend changes**.

- **Zero third-party dependencies** — Apple frameworks only (`Foundation`,
  `CryptoKit`, `CoreLocation`, `UIKit`, `Network`, `DeviceCheck`, `CallKit`).
- **Two-step integration** — `configure` once, then `getSession()` per protected action.
- **Fail-soft by design** — every collector is time-budgeted; any signal that is
  unavailable (e.g. a permission was not granted) is simply omitted, and you
  still receive a valid token.

---

## Requirements

- **iOS 14.0** or higher
- **Swift 5.9** or higher (Xcode 15+)
- _(optional)_ **Core Location** permission — required only for GPS signals
  (latitude/longitude and permission state)

> **Note:** If a permission is not granted, the values that depend on it are
> ignored and the SDK still returns a valid token. We recommend enabling as many
> permissions as your use case allows for the most reliable device intelligence.

---

## Installation (Swift Package Manager)

In Xcode, go to **File → Add Package Dependencies…** and enter the repository URL:

```
https://github.com/ewalletbotorg/gsgeo-ios-sdk-public
```

For the **Dependency Rule**, choose **Up to Next Major Version** and enter the
latest published version (currently `1.0.0`). This automatically picks up
backward-compatible updates.

---

## Host-side setup

The SDK collects GPS signals through Core Location, which iOS only allows if your
app declares a usage description. This is a **one-time step you (the integrating
app) must perform** — add the following key to your app's **Info.plist**:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We use your location to help verify this device.</string>
```

You can change the message text to match your product and privacy wording — it is
the prompt your end users will see. This is the only host-side configuration
beyond the two lines of code below.

---

## Quick start

```swift
import GSIntelligence

// Step 1 — once, at app start (e.g. in your App init or AppDelegate)
GS.configure(clientId: "YOUR_CLIENT_ID")

// Step 2 — per protected user action (login, checkout, signup)
do {
    let session = try await GS.getSession()
    // Send `session` to YOUR backend (see "Sending the token to your backend").
    // Never call the GS fraud-check endpoint directly from the app.
} catch GSError.gpsRequired(let state) {
    // Only thrown when configured with gps: .required
    print("location required, permission state: \(state ?? "unknown")")
} catch {
    print("session error: \(error)")
}
```

---

## Configuration options

`GS.configure` accepts the following options. Only `clientId` is required.

```swift
GS.configure(
    clientId: "YOUR_CLIENT_ID",
    gps: .prompt,          // .off | .silent | .prompt | .required
    behavior: true,        // always-on session-timing capture
    persistence: true,     // Keychain-backed stable device id (set false for GDPR mode)
    sandbox: false,        // true for gk_test_ keys → unencrypted payload
    debug: false,          // verbose console logging
    maxWaitTime: 4.0       // wall-clock collection budget (seconds)
)
```

| Option        | Default   | Description |
|---------------|-----------|-------------|
| `clientId`    | —         | Your client identifier. Required. |
| `gps`         | `.prompt` | GPS behavior: `.off` (never collect), `.silent` (only if already authorized), `.prompt` (ask once), `.required` (throw if not granted). |
| `behavior`    | `true`    | Captures always-on session-timing behavior signals. |
| `persistence` | `true`    | Stores a stable device id in the Keychain. Set `false` for a privacy/GDPR mode with no persistent id. |
| `sandbox`     | `false`   | Set `true` with a `gk_test_` key to receive an unencrypted payload for inspection. |
| `debug`       | `false`   | Enables verbose console logging during integration. |
| `maxWaitTime` | `4.0`     | Maximum seconds the SDK waits while collecting signals. |

> `clientId` mirrors the web SDK: the token itself stays anonymous and is
> identified server-side by your API key. It is **not** embedded in the token.

---

## Sending the token to your backend

The SDK returns an opaque token. Your app sends it to **your** backend, which
forwards it verbatim to the GS fraud-check endpoint with your `x-api-key`. The API
key never lives in the app:

```text
App → (token) → Your backend → POST /functions/v1/fraud-check
                                 headers: x-api-key: <your key>
                                 body:    { "session": "<token>" }
```

---

## Sandbox mode

When you initialize with a `gk_test_` key, set `sandbox: true`. The SDK returns
`gsds_sandbox.<base64(payload)>` (unencrypted) so you can inspect the exact signal
envelope during integration. This mirrors the web SDK's sandbox behavior.

---

## Support

For integration help, API keys, and documentation, contact your GS account team.

---

## Changelog

### 1.0.0
- Initial public release of the GS Intelligence iOS SDK.
- Two-step `GS.configure` / `GS.getSession` integration.
- Device, network, GPS, behavioral, and tamper signal collection.
- GPS collector polls `CLLocationManager.location` as a fallback so a coordinate
  is returned even when `didUpdateLocations` never fires.
- Token format byte-compatible with the GS web and Android SDKs.
- Sandbox mode for `gk_test_` keys.
