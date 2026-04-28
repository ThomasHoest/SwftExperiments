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
        browser.searchForServices(ofType: "_bangolufsen._tcp.", inDomain: "local.")
    }

    func stop() {
        browser.stop()
    }

    private func tryAdd(ip: String) async {
        guard foundHosts.insert(ip).inserted else { return }
        let speaker = Speaker(host: ip)
        do {
            try await speaker.initialize()
            speakers.append(speaker)
        } catch {
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
        service.delegate = self
        pendingServices.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        pendingServices.removeAll { $0 === sender }
        guard let addresses = sender.addresses else { return }
        for data in addresses {
            if let ip = ipv4(from: data) {
                Task { await self.tryAdd(ip: ip) }
                return
            }
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        pendingServices.removeAll { $0 === sender }
    }
}
