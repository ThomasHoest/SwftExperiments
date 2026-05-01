import XCTest
@testable import Voxio

// T-2720 — BNRClient unit tests using URLProtocol interception.
final class BNRClientTests: XCTestCase {

    // MARK: - Helpers

    private func makeClient(handler: @escaping MockProtocol.Handler) -> BNRClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        MockProtocol.handler = handler
        let session = URLSession(configuration: config)
        return BNRClient(host: "test.local", port: 8080, session: session)
    }

    // MARK: - Volume

    // T-2720 #1: getVolume() normalises using range.maximum
    func testGetVolume_normalisesWithMaximum() async throws {
        let client = makeClient { _ in
            let json = #"{"speaker":{"level":3000,"muted":false,"range":{"minimum":0,"maximum":6000}}}"#
            return (.ok(json), URL(string: "http://test.local")!)
        }
        let vol = try await client.getVolume()
        XCTAssertEqual(vol, 50)
    }

    // T-2720 #2: setVolume() scales level by range.maximum
    func testSetVolume_scalesLevelByMaximum() async throws {
        var capturedBody: Data?
        let client = makeClient { request in
            if request.httpMethod == "GET" {
                let json = #"{"speaker":{"level":0,"muted":false,"range":{"minimum":0,"maximum":6000}}}"#
                return (.ok(json), request.url!)
            } else {
                capturedBody = request.httpBody
                return (.ok(""), request.url!)
            }
        }
        try await client.setVolume(50)
        let body = try XCTUnwrap(capturedBody)
        let parsed = try JSONDecoder().decode([String: Int].self, from: body)
        XCTAssertEqual(parsed["level"], 3000)
    }

    // T-2720 #3: mute(true) sends { "muted": true }
    func testMute_sendsMutedTrue() async throws {
        var capturedBody: Data?
        let client = makeClient { request in
            capturedBody = request.httpBody
            return (.ok(""), request.url!)
        }
        try await client.mute(true)
        let body = try XCTUnwrap(capturedBody)
        let parsed = try JSONDecoder().decode([String: Bool].self, from: body)
        XCTAssertEqual(parsed["muted"], true)
    }

    // MARK: - Playback commands

    // T-2720 #4: play() sends both press and release
    func testPlay_sendsPressAndRelease() async throws {
        var paths: [String] = []
        let client = makeClient { request in
            paths.append(request.url?.path ?? "")
            return (.ok(""), request.url!)
        }
        try await client.play()
        XCTAssertTrue(paths.contains("/BeoZone/Zone/Stream/Play"))
        XCTAssertTrue(paths.contains("/BeoZone/Zone/Stream/Play/Release"))
    }

    // T-2720 #5: 501 on play() does NOT throw
    func testPlay_501DoesNotThrow() async throws {
        let client = makeClient { request in
            return (.status(501), request.url!)
        }
        try await client.play()
    }

    // T-2720 #6: 404 on play() throws SpeakerError.httpError(404)
    func testPlay_404Throws() async throws {
        let client = makeClient { request in
            return (.status(404), request.url!)
        }
        do {
            try await client.play()
            XCTFail("Expected SpeakerError.httpError(404)")
        } catch SpeakerError.httpError(let code) {
            XCTAssertEqual(code, 404)
        }
    }

    // T-2720 #7: URLError.timedOut maps to SpeakerError.timeout
    func testURLTimeout_mapsSpeakerTimeout() async throws {
        let client = makeClient { _ in
            throw URLError(.timedOut)
        }
        do {
            try await client.getVolume()
            XCTFail("Expected SpeakerError.timeout")
        } catch SpeakerError.timeout {
            // pass
        }
    }

    // MARK: - getSources

    // T-2720 #8: borrowed=true source is excluded
    func testGetSources_excludesBorrowedSources() async throws {
        let client = makeClient { request in
            let json = """
            {"sources":[
              ["src1",{"id":"src1","friendlyName":"Local Radio","inUse":true,"borrowed":false,"sourceType":{"type":"TUNEIN"},"category":"radio"}],
              ["src2",{"id":"src2","friendlyName":"Remote Radio","inUse":true,"borrowed":true,"sourceType":{"type":"TUNEIN"},"category":"radio"}]
            ]}
            """
            return (.ok(json), request.url!)
        }
        let sources = try await client.getSources()
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0].id, "src1")
    }

    // T-2720 #9: inUse=false source is excluded
    func testGetSources_excludesNotInUseSources() async throws {
        let client = makeClient { request in
            let json = """
            {"sources":[
              ["src1",{"id":"src1","friendlyName":"Active","inUse":true,"borrowed":false,"sourceType":{"type":"TUNEIN"},"category":"radio"}],
              ["src2",{"id":"src2","friendlyName":"Inactive","inUse":false,"borrowed":false,"sourceType":{"type":"TUNEIN"},"category":"radio"}]
            ]}
            """
            return (.ok(json), request.url!)
        }
        let sources = try await client.getSources()
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0].id, "src1")
    }

    // MARK: - getName

    // T-2720 #10: getName() returns productFriendlyName
    func testGetName_returnsProductFriendlyName() async throws {
        let client = makeClient { _ in
            let json = #"{"beoDevice":{"productFriendlyName":{"productFriendlyName":"Beosound Level"}}}"#
            return (.ok(json), URL(string: "http://test.local")!)
        }
        let name = try await client.getName()
        XCTAssertEqual(name, "Beosound Level")
    }
}

// MARK: - URLProtocol mock

final class MockProtocol: URLProtocol {
    // Returns (responseBody, requestURL) or throws.
    typealias Handler = (URLRequest) throws -> (MockResponse, URL)

    enum MockResponse {
        case ok(String)
        case status(Int)

        var statusCode: Int {
            switch self {
            case .ok: return 200
            case .status(let c): return c
            }
        }
        var data: Data {
            switch self {
            case .ok(let s): return s.data(using: .utf8) ?? Data()
            case .status: return Data()
            }
        }
    }

    static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        // URLSession converts httpBody to httpBodyStream for URLProtocol.
        // Reconstruct the body data from the stream so tests can inspect it.
        var reconstructed = request
        if let stream = request.httpBodyStream, reconstructed.httpBody == nil {
            stream.open()
            var body = Data()
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
            defer { buf.deallocate() }
            while stream.hasBytesAvailable {
                let n = stream.read(buf, maxLength: 1024)
                if n > 0 { body.append(buf, count: n) }
            }
            stream.close()
            var mutable = URLRequest(url: request.url!)
            mutable.httpMethod = request.httpMethod
            mutable.allHTTPHeaderFields = request.allHTTPHeaderFields
            mutable.httpBody = body
            reconstructed = mutable
        }

        do {
            let (mockResponse, url) = try handler(reconstructed)
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: mockResponse.statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: mockResponse.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
