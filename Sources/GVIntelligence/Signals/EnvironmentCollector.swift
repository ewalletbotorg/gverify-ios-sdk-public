import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CallKit)
import CallKit
#endif

/// Collects device-environment signals that map to dashboard Device Rules:
/// - HC138 screen captured  (`UIScreen.isCaptured`)
/// - HC136 screen mirrored  (`UIScreen.screens.count > 1`)
/// - HC139 active phone call (`CXCallObserver`)
enum EnvironmentCollector {
    struct Result {
        var screenCaptured: Bool?
        var externalDisplay: Bool?
        var inCall: Bool?
    }

    @MainActor
    static func collect() -> Result {
        var result = Result()

        #if canImport(UIKit)
        if #available(iOS 11.0, *) {
            result.screenCaptured = UIScreen.main.isCaptured // HC138
        }
        result.externalDisplay = UIScreen.screens.count > 1 // HC136
        #endif

        #if canImport(CallKit)
        let observer = CXCallObserver()
        let active = observer.calls.contains { !$0.hasEnded }
        result.inCall = active // HC139
        #endif

        return result
    }
}
