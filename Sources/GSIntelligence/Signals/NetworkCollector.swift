import Foundation
import Network
#if canImport(CFNetwork)
import CFNetwork
#endif

/// Collects connection type plus VPN/proxy posture (HC134).
enum NetworkCollector {
    /// Synchronously probes the current network path under a short budget.
    static func collect(timeout: TimeInterval = 1.5) -> NetworkSignals {
        var effective: String?
        var expensive: Bool?
        var constrained: Bool?

        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "com.gammasweep.gsintelligence.net")

        monitor.pathUpdateHandler = { path in
            if path.usesInterfaceType(.wifi) {
                effective = "wifi"
            } else if path.usesInterfaceType(.cellular) {
                effective = "cellular"
            } else if path.usesInterfaceType(.wiredEthernet) {
                effective = "ethernet"
            } else if path.status == .satisfied {
                effective = "other"
            } else {
                effective = "none"
            }
            expensive = path.isExpensive
            if #available(iOS 13.0, *) {
                constrained = path.isConstrained
            }
            semaphore.signal()
        }
        monitor.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + timeout)
        monitor.cancel()

        var signals = NetworkSignals()
        signals.effective_type = effective
        signals.vpn_active = vpnActive()
        signals.proxy_active = proxyActive()
        signals.is_expensive = expensive
        signals.is_constrained = constrained
        return signals
    }

    /// VPN detection: the system proxy settings expose scoped per-interface
    /// entries; a `tap`/`tun`/`ppp`/`ipsec`/`utun` scope strongly indicates a
    /// VPN tunnel. Falls back to a raw interface scan.
    static func vpnActive() -> Bool {
        let vpnPrefixes = ["tap", "tun", "ppp", "ipsec", "utun"]
        if let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
           let scoped = settings["__SCOPED__"] as? [String: Any] {
            for key in scoped.keys {
                if vpnPrefixes.contains(where: { key.lowercased().hasPrefix($0) }) {
                    return true
                }
            }
        }
        return interfaceVpnActive(prefixes: vpnPrefixes)
    }

    /// Raw scan of active interfaces for VPN tunnel names.
    private static func interfaceVpnActive(prefixes: [String]) -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return false }
        defer { freeifaddrs(ifaddr) }
        var pointer = ifaddr
        while let current = pointer {
            let name = String(cString: current.pointee.ifa_name)
            if prefixes.contains(where: { name.lowercased().hasPrefix($0) }) {
                freeifaddrs(ifaddr)
                ifaddr = nil
                return true
            }
            pointer = current.pointee.ifa_next
        }
        return false
    }

    /// System HTTP/HTTPS proxy configured.
    static func proxyActive() -> Bool {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return false
        }
        let httpEnabled = (settings[kCFNetworkProxiesHTTPEnable as String] as? Int) ?? 0
        let httpsEnabled = (settings["HTTPSEnable"] as? Int) ?? 0
        let hasHost = settings[kCFNetworkProxiesHTTPProxy as String] != nil
            || settings["HTTPSProxy"] != nil
        return httpEnabled == 1 || httpsEnabled == 1 || hasHost
    }
}
