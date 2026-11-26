import Foundation

enum SingleInstance {
    private static let polls = 20
    private static let interval: TimeInterval = 0.05

    /// Whether another instance is still running after giving it up to `polls × interval`
    /// (1 s) to exit, so Quit followed by an immediate relaunch doesn't exit the new copy
    /// because the old one hasn't finished terminating.
    static func anotherInstanceRemains(
        wait: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        othersRunning: () -> Bool
    ) -> Bool {
        for _ in 0..<polls {
            guard othersRunning() else { return false }
            wait(interval)
        }
        return othersRunning()
    }
}
