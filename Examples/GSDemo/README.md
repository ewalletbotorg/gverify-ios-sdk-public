# GSDemo — example app

A minimal SwiftUI app that exercises the GS Intelligence SDK end-to-end:

- **Get Session** — seals a token. In sandbox mode (`sandbox: true` + a
  `gk_test_` key) the token is unencrypted so the app can pretty-print the
  decoded signal envelope. With a live key it returns an encrypted JWE that
  your backend forwards verbatim to `fraud-check`.
- **Get Device ID** — reads the stable Keychain-backed identifier.
- **Decoded signals** — renders the signal JSON (sandbox only) so you can
  confirm device/network/GPS/tamper fields look correct.

> SPM ignores the `Examples/` directory when clients resolve the package, so
> shipping this in the public repo does not affect consumers.

## Run it

This folder ships only the Swift sources (`GSDemoApp.swift`, `ContentView.swift`)
to keep the repo free of a large, churn-prone `.xcodeproj`. Create the app
shell once:

1. Xcode → **File → New → Project… → iOS → App** (SwiftUI, name it `GSDemo`).
2. Replace the generated `GSDemoApp.swift` / `ContentView.swift` with the files
   in `GSDemo/`.
3. **File → Add Package Dependencies…**
   - Local source of record: **Add Local…** and pick the repo root (where
     `Package.swift` lives).
   - Or the public package: `https://github.com/ewalletbotorg/gsgeo-ios-sdk-public`
4. Add the GPS usage string to **Info.plist**:

   ```xml
   <key>NSLocationWhenInUseUsageDescription</key>
   <string>We use your location to help verify this device.</string>
   ```

5. Set `clientId` in `GSDemoApp.swift`, build, and run on a device or simulator.

For real device-rule testing (VPN, screen capture, calls, jailbreak), run on a
physical device — the simulator cannot produce those signals.

## Getting GPS in the Simulator

The Simulator has no GPS hardware, so CoreLocation only returns a fix if you
explicitly set a simulated location. Without one, you'll see
`GPS: lat=nil lon=nil state=Optional("timeout")` even after granting permission.

1. Make sure `NSLocationWhenInUseUsageDescription` exists (Info tab → Custom iOS
   Target Properties, or Build Settings → "Privacy - Location When In Use Usage
   Description"). Without it iOS never shows the prompt.
2. Run the app, tap **Get Session**, and allow **While Using the App**.
3. In the Simulator menu: **Features → Location → Custom Location…** and enter
   coordinates, e.g. `37.3349`, `-122.0090`.
4. Tap **Get Session** again.

The SDK now starts both a one-shot `requestLocation()` and a continuous
`startUpdatingLocation()` stream, so it picks up the simulated location as soon
as it's available:

```text
GPS: lat=37.3349 lon=-122.0090 state=Optional("granted")
```

Set `debug: true` in `GS.configure(...)` to log `[gs] gps: …` lines (authorization
changes, fixes, timeouts) in the Xcode console. If it still times out after
setting a Custom Location, confirm on a physical device.
