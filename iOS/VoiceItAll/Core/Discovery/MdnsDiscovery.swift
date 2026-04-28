import Foundation
import Network
import Combine

@MainActor
class MdnsDiscovery: NSObject, ObservableObject {
    @Published var speakers: [Speaker] = []

    private let browser = NetServiceBrowser()
    private var pendingServices: [NetService] = []
    private var foundHosts = Set<String>()

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        Log.info("[mDNS] started browsing for _bangolufsen._tcp.")
        browser.searchForServices(ofType: "_bangolufsen._tcp.", inDomain: "local.")
    }

    func stop() {
        Log.info("[mDNS] stopped browsing")
        browser.stop()
    }

    private func tryAdd(ip: String) async {
        guard foundHosts.insert(ip).inserted else { return }
        Log.info("[mDNS] attempting to add speaker at \(ip)")
        let speaker = Speaker(host: ip)
        do {
            try await speaker.initialize()
            speakers.append(speaker)
            Log.info("[mDNS] added speaker \(speaker.name) (\(ip))")
        } catch {
            Log.error("[mDNS] rejected \(ip): \(error.localizedDescription)")
            foundHosts.remove(ip)
            speaker.dispose()
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
        Log.verbose("[mDNS] found service: \(service.name)")
        service.delegate = self
        pendingServices.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        pendingServices.removeAll { $0 === sender }
        guard let addresses = sender.addresses else { return }
        for data in addresses {
            if let ip = ipv4(from: data) {
                Log.info("[mDNS] resolved \(sender.name) → \(ip)")
                Task { await self.tryAdd(ip: ip) }
                return
            }
        }
        Log.error("[mDNS] could not extract IPv4 for \(sender.name)")
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        Log.error("[mDNS] failed to resolve \(sender.name): \(errorDict)")
        pendingServices.removeAll { $0 === sender }
    }
}
