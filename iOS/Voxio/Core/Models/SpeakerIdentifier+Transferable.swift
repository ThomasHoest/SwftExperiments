import CoreTransferable
import UniformTypeIdentifiers

// MARK: - SpeakerIdentifier: Transferable (E-59 T-5901)
//
// Uses CodableRepresentation(contentType: .data) so that the existing Codable
// conformance drives serialisation. The live Speaker is resolved from the identifier
// on drop by SessionViewModel.resolveSpeaker(_:) against discovery.groups.flatMap(\.members).
//
// SpeakerIdentifier is a Sendable value type (declared in SpeakerIdentifier.swift)
// with its Codable conformance moved to a nonisolated extension so CodableRepresentation's
// Sendable requirement is satisfied under the target's default-isolation setting.
//
// Behavioural contracts:
//   1. A SpeakerIdentifier round-tripped through JSONEncoder/JSONDecoder produces
//      an equal value (== on all three fields: host, jid, platform).
//   2. .id is always non-empty (host is non-empty per SpeakerDiscovery contract).
//   3. Two SpeakerIdentifiers with the same JID have the same .id even when host differs.

extension SpeakerIdentifier: Transferable {
    nonisolated static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

extension SpeakerIdentifier {
    /// Stable string key used as the joinsInFlight Set<String> key and for
    /// task dictionary lookup. JID preferred (Mozart); host fallback (ASE).
    var id: String { jid ?? host }
}
