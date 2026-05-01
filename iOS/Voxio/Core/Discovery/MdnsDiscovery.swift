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
        Log.verbose("[mDNS] found service: \(service.name)")
        let platform = browserPlatform[ObjectIdentifier(browser)] ?? .mozart
        serviceNameToType[service.name] = platform
        service.delegate = self
        pendingServices.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        pendingServices.removeAll { $0 === sender }
        guard let addresses = sender.addresses else { return }
        let platform = serviceNameToType[sender.name] ?? .mozart
        for data in addresses {
            if let ip = ipv4(from: data) {
                guard foundHosts.insert(ip).inserted else { return }
                Log.info("[mDNS] resolved \(sender.name) → \(ip) (\(platform.rawValue))")
                serviceNameToHost[sender.name] = ip
                Task { await self.onSpeakerDiscovered?(ip, platform) }
                return
            }
        }
        Log.error("[mDNS] could not extract IPv4 for \(sender.name)")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        Log.info("[mDNS] lost service: \(service.name)")
        serviceNameToType.removeValue(forKey: service.name)
        guard let host = serviceNameToHost.removeValue(forKey: service.name) else { return }
        foundHosts.remove(host)
        onSpeakerRemoved?(host)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        Log.error("[mDNS] failed to resolve \(sender.name): \(errorDict)")
        pendingServices.removeAll { $0 === sender }
    }
}
