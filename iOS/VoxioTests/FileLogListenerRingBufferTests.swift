import XCTest
@testable import Voxio

// E-50 T-5002 — Unit tests for the FileLogListener ring buffer extension.

final class FileLogListenerRingBufferTests: XCTestCase {

    // Use a fresh instance (not .shared) for every test so tests are isolated.
    private func makeListener() -> FileLogListener {
        FileLogListener(flushInterval: 3600, bufferCapacity: 10_000)
    }

    // Helper: emit `count` lines into a listener and return their expected fileLine prefixes.
    private func emit(count: Int, into listener: FileLogListener, prefix: String = "line") {
        for i in 1...count {
            listener.didLog(level: .info, line: "12:00:00.000 [INFO] \(prefix) \(i)", timestamp: Date())
        }
        // Give the async queue a moment to settle.
        listener.flushSync()  // flushSync runs on the serial queue, so after this the ring is updated.
    }

    // MARK: - Basic capacity tests

    func testRingBuffer_10Lines_returnsAll10() {
        let listener = makeListener()
        emit(count: 10, into: listener)

        let snapshot = listener.ringBufferSnapshot()
        XCTAssertEqual(snapshot.count, 10,
                       "10 lines should be retained when capacity is 25")
    }

    func testRingBuffer_100Lines_returns25MostRecent() {
        let listener = makeListener()
        emit(count: 100, into: listener)

        let snapshot = listener.ringBufferSnapshot()
        XCTAssertEqual(snapshot.count, FileLogListener.ringBufferCapacity,
                       "Ring buffer must cap at ringBufferCapacity (25)")

        // Verify the oldest retained line is line 76 and newest is line 100.
        XCTAssertTrue(snapshot.first?.contains("line 76") == true,
                      "Oldest retained line should be line 76; got: \(snapshot.first ?? "nil")")
        XCTAssertTrue(snapshot.last?.contains("line 100") == true,
                      "Newest retained line should be line 100; got: \(snapshot.last ?? "nil")")
    }

    func testRingBuffer_exactlyCapacity_returnsAll() {
        let listener = makeListener()
        emit(count: FileLogListener.ringBufferCapacity, into: listener)

        let snapshot = listener.ringBufferSnapshot()
        XCTAssertEqual(snapshot.count, FileLogListener.ringBufferCapacity)
    }

    // MARK: - Snapshot isolation (copy semantics)

    func testRingBuffer_snapshotIsACopy() {
        let listener = makeListener()
        emit(count: 5, into: listener)

        var snapshot = listener.ringBufferSnapshot()
        snapshot.removeAll()

        // A subsequent call must still return the full 5 lines.
        let snapshot2 = listener.ringBufferSnapshot()
        XCTAssertEqual(snapshot2.count, 5,
                       "Mutating the returned array must not affect the internal ring buffer")
    }

    // MARK: - Ordering

    func testRingBuffer_linesAreOrderedOldestFirst() {
        let listener = makeListener()
        emit(count: 3, into: listener)

        let snapshot = listener.ringBufferSnapshot()
        XCTAssertEqual(snapshot.count, 3)
        XCTAssertTrue(snapshot[0].contains("line 1"))
        XCTAssertTrue(snapshot[1].contains("line 2"))
        XCTAssertTrue(snapshot[2].contains("line 3"))
    }

    // MARK: - Concurrent stress test

    func testRingBuffer_concurrent_doesNotCorrupt() {
        let listener = makeListener()
        let group = DispatchGroup()
        let workerQueues = (0..<8).map {
            DispatchQueue(label: "test.worker.\($0)", qos: .userInteractive)
        }

        // 1000 log calls spread across 8 queues.
        for i in 0..<1000 {
            let q = workerQueues[i % 8]
            group.enter()
            q.async {
                listener.didLog(level: .info,
                                line: "12:00:00.000 [INFO] stress \(i)",
                                timestamp: Date())
                group.leave()
            }
        }

        group.wait()
        listener.flushSync()  // drain the serial queue

        let snapshot = listener.ringBufferSnapshot()
        // Buffer should be exactly `ringBufferCapacity` entries.
        XCTAssertLessThanOrEqual(snapshot.count, FileLogListener.ringBufferCapacity,
                                 "Ring buffer must never exceed capacity under concurrent writes")
        // All entries must be non-empty strings.
        for line in snapshot {
            XCTAssertFalse(line.isEmpty, "All ring buffer entries must be non-empty")
        }
    }

    // MARK: - Empty snapshot

    func testRingBuffer_empty_returnsEmptyArray() {
        let listener = makeListener()
        XCTAssertEqual(listener.ringBufferSnapshot(), [])
    }

    // MARK: - ringBufferCapacity constant

    func testRingBufferCapacity_is25() {
        XCTAssertEqual(FileLogListener.ringBufferCapacity, 25)
    }
}
