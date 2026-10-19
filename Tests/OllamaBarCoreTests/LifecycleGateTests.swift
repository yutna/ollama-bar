import XCTest

@testable import OllamaBarCore

final class LifecycleGateTests: XCTestCase {
    private enum GateError: Error {
        case boom
    }

    /// Counts overlapping gate holders; only the gate's serialization keeps
    /// `peak` at 1.
    private final class ConcurrencyProbe {
        private let lock = NSLock()
        private var active = 0
        private var peak = 0

        func enter() {
            lock.lock()
            active += 1
            peak = max(peak, active)
            lock.unlock()
        }

        func leave() {
            lock.lock()
            active -= 1
            lock.unlock()
        }

        func snapshot() -> (peak: Int, active: Int) {
            lock.lock()
            defer { lock.unlock() }
            return (peak, active)
        }
    }

    func testSerializesConcurrentCallers() {
        let gate = LifecycleGate()
        let probe = ConcurrencyProbe()

        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            gate.withLock {
                probe.enter()
                Thread.sleep(forTimeInterval: 0.002)
                probe.leave()
            }
        }

        let snapshot = probe.snapshot()
        XCTAssertEqual(snapshot.peak, 1, "more than one caller held the gate at once")
        XCTAssertEqual(snapshot.active, 0)
    }

    func testReleasesTheGateWhenBodyThrows() {
        let gate = LifecycleGate()
        XCTAssertThrowsError(try gate.withLock { throw GateError.boom })
        XCTAssertEqual(gate.withLock { 42 }, 42)
    }

    func testPassesThroughReturnValues() {
        let gate = LifecycleGate()
        XCTAssertEqual(gate.withLock { "value" }, "value")
    }
}
