import XCTest
@testable import Voxio

// E-35 — Unit tests for KeychainDeviceID (T-3507).
//
// KeychainDeviceID is a nonisolated enum wrapping Security framework Keychain calls.
// Keychain is available in the iOS Simulator for the app's own access group
// without additional entitlements.

final class KeychainDeviceIDTests: XCTestCase {

    // MARK: - setUp / tearDown

    override func setUp() {
        super.setUp()
        KeychainDeviceID.delete()
    }

    override func tearDown() {
        KeychainDeviceID.delete()
        super.tearDown()
    }

    // MARK: - readOrCreate() tests

    func testReadOrCreate_returnsAUUID() {
        let id = KeychainDeviceID.readOrCreate()
        XCTAssertNotEqual(id, UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }

    func testReadOrCreate_calledTwice_returnsSameUUID() {
        let first  = KeychainDeviceID.readOrCreate()
        let second = KeychainDeviceID.readOrCreate()
        XCTAssertEqual(first, second,
            "readOrCreate() called twice must return the same UUID")
    }

    func testRead_afterDelete_returnsNil() {
        _ = KeychainDeviceID.readOrCreate()
        KeychainDeviceID.delete()
        let result = KeychainDeviceID.read()
        XCTAssertNil(result, "read() must return nil after delete()")
    }

    func testReadOrCreate_afterDelete_returnsNewUUID() {
        let original = KeychainDeviceID.readOrCreate()
        KeychainDeviceID.delete()
        let regenerated = KeychainDeviceID.readOrCreate()
        XCTAssertNotEqual(regenerated, original,
            "readOrCreate() after delete() must generate a new UUID")
    }

    func testDelete_calledOnEmptyKeychain_doesNotCrash() {
        // setUp already called delete(); this verifies a double-delete is safe.
        KeychainDeviceID.delete()
        // Reaching here without a crash is the pass condition.
    }

    func testWrite_thenRead_returnsSameUUID() {
        let id = UUID()
        KeychainDeviceID.write(id)
        let readBack = KeychainDeviceID.read()
        XCTAssertEqual(readBack, id,
            "read() must return the same UUID that was passed to write(_:)")
    }

    func testWrite_overwrite_returnsLatestUUID() {
        let first  = UUID()
        let second = UUID()
        KeychainDeviceID.write(first)
        KeychainDeviceID.write(second)
        let readBack = KeychainDeviceID.read()
        XCTAssertEqual(readBack, second,
            "write(_:) called twice must replace the stored UUID with the latest value")
    }

    func testReadOrCreate_simulatorSkipIfNoKeychain() throws {
        #if !targetEnvironment(simulator)
        let id = KeychainDeviceID.readOrCreate()
        let second = KeychainDeviceID.readOrCreate()
        XCTAssertEqual(id, second)
        #else
        throw XCTSkip("Skipping Keychain test on Simulator — run on a real device to verify entitlement behaviour")
        #endif
    }
}
