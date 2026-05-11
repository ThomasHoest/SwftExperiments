import Foundation
import Network

@MainActor
class MdnsDiscovery: NSObject {
    var onSpeakerDiscovered: ((String, SpeakerPlatform) async -> Void)?
    var onSpeakerRemoved: ((String) -> Void)?

    private let mozartBrowser = NetServiceBrowser()
    private let bnrBrowser    = NetServiceBrowser()
    private var pendingServices: [NetService] = []
    private var foundHosts = Set<String>()
    private var serviceNameToHost: [String: String] = [:]
    private var serviceNameToType: [String: SpeakerPlatform] = [:]
    private var browserPlatform: [ObjectIdentifier: SpeakerPlatform] = [:]

    // Retry/backoff state for transient mDNS browse failures (e.g. NSNetServicesErrorCode -72000).
    private var retryAttempts: [ObjectIdentifier: Int] = [:]
    private var retryTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private let maxRetryAttempts = 6
    private var isStarted = false

    override init() {
        super.init()
        mozartBrowser.delegate = self
        bnrBrowser.delegate    = self
        browserPlatform[ObjectIdentifier(mozartBrowser)] = .mozart
        browserPlatform[ObjectIdentifier(bnrBrowser)]    = .bnr
    }

    func start() {
        Log.info("[mDNS] started browsing for _bangolufsen._tcp. and _beoremote._tcp.")
        isStarted = true
        retryAttempts.removeAll()
        cancelAllRetries()
        mozartBrowser.searchForServices(ofType: "_bangolufsen._tcp.", inDomain: "local.")
        bnrBrowser.searchForServices(ofType: "_beoremote._tcp.", inDomain: "local.")
    }

    func stop() {
        Log.info("[mDNS] stopped browsing")
        isStarted = false
        cancelAllRetries()
        mozartBrowser.stop()
        bnrBrowser.stop()
    }

    private func cancelAllRetries() {
        for (_, task) in retryTasks { task.cancel() }
        retryTasks.removeAll()
    }

    private func serviceType(for platform: SpeakerPlatform) -> String {
        switch platform {
        case .mozart: return "_bangolufsen._tcp."
        case .bnr:    return "_beoremote._tcp."
        }
    }

    private func scheduleRetry(for browser: NetServiceBrowser) {
        guard isStarted else { return }
        let key = ObjectIdentifier(browser)
        let platform = browserPlatform[key] ?? .mozart
        let attempt = (retryAttempts[key] ?? 0) + 1
        guard attempt <= maxRetryAttempts else {
            Log.error("[mDNS] giving up retrying \(platform.rawValue) browser after \(attempt - 1) attempts")
            return
        }
        retryAttempts[key] = attempt

        // Exponential backoff with cap: 2, 4, 8, 16, 32, 60 seconds.
        let delaySeconds = min(60, Int(pow(2.0, Double(attempt))))
        Log.info("[mDNS] scheduling retry #\(attempt) for \(platform.rawValue) browser in \(delaySeconds)s")

        retryTasks[key]?.cancel()
        retryTasks[key] = Task { [weak self, weak browser] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, let browser, self.isStarted else { return }
                let type = self.serviceType(for: platform)
                Log.info("[mDNS] retrying \(platform.rawValue) browser (attempt #\(attempt))")
                browser.stop()
                browser.searchForServices(ofType: type, inDomain: "local.")
            }
        }
    }

    private func ipv4(from data: Data) -> String? {
        data.withUnsafeBytes { bytes -> String? in
            guard bytes.count >= MemoryLayout<sockaddr_in>.size else { return nil }
            let sa = bytes.load(as: sockaddr_in.self)
            guard sa.sin_family == AF_INET else { return nil }
            var addr = sa.sin_addr
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buf)
        }
    }
}

extension MdnsDiscovery: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let platform = browserPlatform[ObjectIdentifier(browser)] ?? .mozart
        Log.info("[mDNS] found service: \(service.name) type=\(service.type) domain=\(service.domain) platform=\(platform.rawValue)")
        // Successful find — reset retry counter for this browser.
        retryAttempts[ObjectIdentifier(browser)] = 0
        serviceNameToType[service.name] = platform
        service.delegate = self
        pendingServices.append(service)
        service.resolve(withTimeout: 10)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        pendingServices.removeAll { $0 === sender }
        let platform = serviceNameToType[sender.name] ?? .mozart
        Log.info("[mDNS] resolving \(sender.name) port=\(sender.port) hostname=\(sender.hostName ?? "nil") addresses=\(sender.addresses?.count ?? 0) platform=\(platform.rawValue)")

        if let txtData = sender.txtRecordData() {
            let txt = NetService.dictionary(fromTXTRecord: txtData)
            let readable = txt.compactMapValues { String(bytes: $0, encoding: .utf8) }
            Log.info("[mDNS] TXT \(sender.name): \(readable)")
        }

        guard let addresses = sender.addresses, !addresses.isEmpty else {
            Log.error("[mDNS] no addresses for \(sender.name)")
            return
        }

        for (i, data) in addresses.enumerated() {
            let family = data.withUnsafeBytes { $0.load(as: sockaddr.self).sa_family }
            Log.verbose("[mDNS] address[\(i)] family=\(family) bytes=\(data.count)")
            if let ip = ipv4(from: data) {
                guard foundHosts.insert(ip).inserted else {
                    Log.info("[mDNS] \(sender.name) already known at \(ip), skipping")
                    return
                }
                Log.info("[mDNS] resolved \(sender.name) → \(ip):\(sender.port) (\(platform.rawValue))")
                serviceNameToHost[sender.name] = ip
                Task { await self.onSpeakerDiscovered?(ip, platform) }
                return
            }
        }
        Log.error("[mDNS] could not extract IPv4 for \(sender.name) — \(addresses.count) address(es) present, none were AF_INET")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        Log.info("[mDNS] lost service: \(service.name)")
        serviceNameToType.removeValue(forKey: service.name)
        guard let host = serviceNameToHost.removeValue(forKey: service.name) else { return }
        foundHosts.remove(host)
        onSpeakerRemoved?(host)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        let platform = browserPlatform[ObjectIdentifier(browser)]?.rawValue ?? "unknown"
        Log.error("[mDNS] browser didNotSearch (\(platform)): \(errorDict)")
        // NSNetServicesErrorCode -72000 (unknownError) and similar transient failures
        // can occur when the network stack is briefly unavailable (e.g. Wi-Fi flap,
        // backgrounding, VPN reconnect). Reschedule the browse with exponential
        // backoff rather than leaving discovery permanently dead.
        scheduleRetry(for: browser)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        Log.error("[mDNS] failed to resolve \(sender.name): \(errorDict)")
        pendingServices.removeAll { $0 === sender }
    }
}
