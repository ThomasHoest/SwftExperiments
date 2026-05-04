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

    override init() {
        super.init()
        mozartBrowser.delegate = self
        bnrBrowser.delegate    = self
        browserPlatform[ObjectIdentifier(mozartBrowser)] = .mozart
        browserPlatform[ObjectIdentifier(bnrBrowser)]    = .bnr
    }

    func start() {
        Log.info("[mDNS] started browsing for _bangolufsen._tcp. and _beoremote._tcp.")
        mozartBrowser.searchForServices(ofType: "_bangolufsen._tcp.", inDomain: "local.")
        bnrBrowser.searchForServices(ofType: "_beoremote._tcp.", inDomain: "local.")
    }

    func stop() {
        Log.info("[mDNS] stopped browsing")
        mozartBrowser.stop()
        bnrBrowser.stop()
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
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        Log.error("[mDNS] failed to resolve \(sender.name): \(errorDict)")
        pendingServices.removeAll { $0 === sender }
    }
}
