import XCTest
@testable import GlassSSHCore

final class KnownHostsStoreTests: XCTestCase {
    func testUnknownHostThenTrustOnFirstUse() {
        let store = KnownHostsStore()
        XCTAssertEqual(store.evaluate(host: "h", port: 22, fingerprint: "SHA256:a"), .unknown)

        let decision = store.trustOnFirstUse(host: "h", port: 22, fingerprint: "SHA256:a")
        XCTAssertEqual(decision, .trusted)
        XCTAssertEqual(store.evaluate(host: "h", port: 22, fingerprint: "SHA256:a"), .trusted)
    }

    func testChangedKeySurfacesMismatchAndIsNotOverwritten() {
        let store = KnownHostsStore()
        store.trustOnFirstUse(host: "h", port: 22, fingerprint: "SHA256:original")

        let decision = store.trustOnFirstUse(host: "h", port: 22, fingerprint: "SHA256:attacker")
        XCTAssertEqual(decision, .mismatch(expected: "SHA256:original", actual: "SHA256:attacker"))
        // The stored value must not have been clobbered.
        XCTAssertEqual(store.fingerprint(host: "h", port: 22), "SHA256:original")
    }

    func testExplicitPinReplacesEntry() {
        let store = KnownHostsStore()
        store.trustOnFirstUse(host: "h", port: 22, fingerprint: "SHA256:original")
        store.pin(host: "h", port: 22, fingerprint: "SHA256:rotated")
        XCTAssertEqual(store.evaluate(host: "h", port: 22, fingerprint: "SHA256:rotated"), .trusted)
    }

    func testDefaultPortIsNormalized() {
        let store = KnownHostsStore()
        store.trustOnFirstUse(host: "Example.com", port: 22, fingerprint: "SHA256:a")
        // Same host via explicit default port and different case resolves identically.
        XCTAssertEqual(store.evaluate(host: "example.com", port: 22, fingerprint: "SHA256:a"), .trusted)
        // A non-default port is a distinct entry.
        XCTAssertEqual(store.evaluate(host: "example.com", port: 2222, fingerprint: "SHA256:a"), .unknown)
    }

    func testPersistenceIsReloaded() {
        let backing = InMemoryKnownHostsPersistence()
        let first = KnownHostsStore(persistence: backing)
        first.trustOnFirstUse(host: "h", port: 22, fingerprint: "SHA256:a")

        let second = KnownHostsStore(persistence: backing)
        XCTAssertEqual(second.evaluate(host: "h", port: 22, fingerprint: "SHA256:a"), .trusted)
    }

    func testForgetRemovesEntry() {
        let store = KnownHostsStore()
        store.trustOnFirstUse(host: "h", port: 22, fingerprint: "SHA256:a")
        store.forget(host: "h", port: 22)
        XCTAssertNil(store.fingerprint(host: "h", port: 22))
    }
}
