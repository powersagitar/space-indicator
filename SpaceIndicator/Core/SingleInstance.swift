import Foundation

enum SingleInstance {
    /// Whether another instance is still running after giving it up to `polls × interval`
    /// (1 s by default) to exit, so Quit followed by an immediate relaunch doesn't exit
    /// the new copy because the old one hasn't finished terminating.
    static func anotherInstanceRemains(
        polls: Int = 20,
        interval: TimeInterval = 0.05,
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
