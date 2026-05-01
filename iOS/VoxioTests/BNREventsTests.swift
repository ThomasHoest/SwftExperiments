import XCTest
@testable import Voxio

// T-2721 — BNREvents unit tests using URLProtocol interception.
final class BNREventsTests: XCTestCase {

    // MARK: - Helpers

    private func sessionWithOnce(_ json: String, thenHang: Bool = false) -> URLSession {
        if thenHang {
            OnceOrHangProtocol.reset(payload: json.data(using: .utf8)!)
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [OnceOrHangProtocol.self]
            return URLSession(configuration: config)
        } else {
            RepeatPayloadProtocol.payload = json.data(using: .utf8)!
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [RepeatPayloadProtocol.self]
            return URLSession(configuration: config)
        }
    }

    /// Connect, collect the first event, disconnect. Times out after 3 seconds.
    private func firstEvent(from events: BNREvents) async throws -> BNREvent {
        try await withCheckedThrowingContinuation { cont in
            var resolved = false
            events.onEvent = { event in
                guard !resolved else { return }
                resolved = true
                events.disconnect()
                cont.resume(returning: event)
            }
            events.connect()
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !resolved else { return }
                resolved = true
                events.disconnect()
                cont.resume(throwing: BNREventsTestError.timeout)
            }
        }
    }

    // MARK: - Tests

    // T-2721 #1: VOLUME event normalises level=3000, maximum=9000 → level=33, muted=false
    func testVolumeEvent_normalisesLevel() async throws {
        let json = #"{"notification":{"type":"VOLUME","data":{"speaker":{"level":3000,"muted":false,"range":{"minimum":0,"maximum":9000}}}}}"#
        let events = BNREvents(host: "test.local", port: 8080, session: sessionWithOnce(json))
        let event = try await firstEvent(from: events)

        guard case .volume(let level, let muted) = event else {
            return XCTFail("Expected .volume, got \(event)")
        }
        XCTAssertEqual(level, 33)
        XCTAssertFalse(muted)
    }

    // T-2721 #2: PROGRESS_INFORMATION "play" → .playbackState(.playing)
    func testProgressInformation_play_mapsToPlaying() async throws {
        let json = #"{"notification":{"type":"PROGRESS_INFORMATION","data":{"state":"play"}}}"#
        let events = BNREvents(host: "test.local", port: 8080, session: sessionWithOnce(json))
        let event = try await firstEvent(from: events)

        guard case .playbackState(let state) = event else {
            return XCTFail("Expected .playbackState, got \(event)")
        }
        XCTAssertEqual(state, .playing)
    }

    // T-2721 #3: PROGRESS_INFORMATION "completed" → .playbackState(.stopped)
    func testProgressInformation_completed_mapsTostopped() async throws {
        let json = #"{"notification":{"type":"PROGRESS_INFORMATION","data":{"state":"completed"}}}"#
        let events = BNREvents(host: "test.local", port: 8080, session: sessionWithOnce(json))
        let event = try await firstEvent(from: events)

        guard case .playbackState(let state) = event else {
            return XCTFail("Expected .playbackState, got \(event)")
        }
        XCTAssertEqual(state, .stopped)
    }

    // T-2721 #4: NOW_PLAYING_NET_RADIO maps name→title, liveDescription→artist, album=nil
    func testNowPlayingNetRadio_mapsFields() async throws {
        let json = #"{"notification":{"type":"NOW_PLAYING_NET_RADIO","data":{"name":"Jazz FM","liveDescription":"Miles Davis - Kind of Blue"}}}"#
        let events = BNREvents(host: "test.local", port: 8080, session: sessionWithOnce(json))
        let event = try await firstEvent(from: events)

        guard case .metadata(let title, let artist, let album) = event else {
            return XCTFail("Expected .metadata, got \(event)")
        }
        XCTAssertEqual(title, "Jazz FM")
        XCTAssertEqual(artist, "Miles Davis - Kind of Blue")
        XCTAssertNil(album)
    }

    // T-2721 #5: Unknown notification type is dropped — onEvent not called
    func testUnknownType_droppedNoEvent() async throws {
        let json = #"{"notification":{"type":"SOMETHING_NEW","data":{}}}"#
        let events = BNREvents(host: "test.local", port: 8080,
                               session: sessionWithOnce(json, thenHang: true))
        var eventFired = false
        events.onEvent = { _ in eventFired = true }
        events.connect()
        try await Task.sleep(nanoseconds: 600_000_000)
        events.disconnect()
        XCTAssertFalse(eventFired, "Unknown notification type should be dropped, not forwarded")
    }
}

// MARK: - URLProtocol helpers

/// Returns the configured payload on every request (loop-friendly).
final class RepeatPayloadProtocol: URLProtocol {
    static var payload: Data = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: RepeatPayloadProtocol.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Returns the payload on the first request, then hangs indefinitely on subsequent ones.
final class OnceOrHangProtocol: URLProtocol {
    static var payload: Data = Data()
    private static var deliveredFirst = false
    private static let lock = NSLock()

    static func reset(payload: Data) {
        lock.lock()
        defer { lock.unlock() }
        self.payload = payload
        self.deliveredFirst = false
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var shouldDeliver = false
        OnceOrHangProtocol.lock.lock()
        if !OnceOrHangProtocol.deliveredFirst {
            OnceOrHangProtocol.deliveredFirst = true
            shouldDeliver = true
        }
        OnceOrHangProtocol.lock.unlock()

        guard shouldDeliver else { return }   // hang: never call client callbacks

        let resp = HTTPURLResponse(url: request.url!, statusCode: 200,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: OnceOrHangProtocol.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private enum BNREventsTestError: Error {
    case timeout
}
