import Foundation
import Testing

@Suite struct SingleInstanceTests {
    @Test func noOtherInstanceDoesNotWait() {
        var waits: [TimeInterval] = []
        let remains = SingleInstance.anotherInstanceRemains(
            wait: { waits.append($0) }, othersRunning: { false })
        #expect(!remains)
        #expect(waits.isEmpty)
    }

    @Test func terminatingInstanceThatExitsIsIgnored() {
        var calls = 0
        let remains = SingleInstance.anotherInstanceRemains(
            wait: { _ in }, othersRunning: { calls += 1; return calls < 3 })
        #expect(!remains)
        #expect(calls == 3)
    }

    @Test func runningInstanceRemainsAfterAtMostOneSecond() {
        var waits: [TimeInterval] = []
        let remains = SingleInstance.anotherInstanceRemains(
            wait: { waits.append($0) }, othersRunning: { true })
        #expect(remains)
        #expect(!waits.isEmpty)
        #expect(waits.allSatisfy { $0 <= 0.1 })
        #expect(waits.reduce(0, +) <= 1.0 + 1e-9)
    }
}
